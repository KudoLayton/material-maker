extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
const Particles2D = preload("res://addons/mm_gpu_particles/particles_2d.gd")
var render_dimension := 3
const Codec = preload("res://addons/mm_gpu_particles/value_codec.gd")
const CAPACITY := 100000
const TICKS := 160
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var doc := Fixtures.basic()
	doc.emitter.rate = 0.0
	doc.emitter.lifetime = 100.0
	var module := {"name":"32 vec4 bandwidth","stages":["update"],"reads":[],"writes":[],"inputs":[],"graph":{"nodes":[],"outputs":{}}}
	for index in 32:
		var id := "field" + str(index)
		doc.attributes.append({"id":id,"name":id,"type":"vec4","default":[index,index,index,index]})
		module.reads.append(id)
		module.writes.append(id)
		module.graph.nodes.append_array([
			{"id":id,"op":"read","attribute":id},
			{"id":id+"step","op":"constant","type":"vec4","value":[1.0,2.0,3.0,4.0]},
			{"id":id+"next","op":"add","args":[id,id+"step"]}])
		module.graph.outputs[id] = id+"next"
	doc.modules["bandwidth"] = module
	doc.stages.update.append({"id":"bandwidth1","module":"bandwidth","parameters":{}})
	var compiled := Compiler.new().compile(doc)
	check(compiled.errors.is_empty(),"performance effect compilation")
	if compiled.effect == null:
		quit(1)
		return
	var particles = Particles2D.new() if render_dimension == 2 else Particles.new()
	particles.manual_processing = true
	particles.capacity = CAPACITY
	particles.effect = compiled.effect
	root.add_child(particles)
	for frame in 180:
		await process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation,"100k allocation: " + particles.error_text)
	if not particles.ready_for_simulation:
		particles.queue_free()
		await process_frame
		quit(1)
		return
	particles.hide() # isolate compute, not 100k overlapping fragments
	var state = particles._gpu
	var parameter_data := Codec.pack_2d(particles.effect,{},Transform2D.IDENTITY,false) if render_dimension == 2 else Codec.pack(particles.effect,{},Transform3D.IDENTITY,false)
	var measurements := {"gpu":[],"cpu":[],"last_frame":-1}
	for tick in TICKS:
		var current := tick
		var steps: Array[Dictionary] = [{"time":(tick+1)/60.0,"spawn_count":CAPACITY if tick == 0 else 0,"spawn_base":0}]
		RenderingServer.call_on_render_thread(func():
			var rd: RenderingDevice = state.rd
			var captured := rd.get_captured_timestamps_frame()
			if current > 20 and captured != measurements.last_frame:
				var first: int = -1
				for i in rd.get_captured_timestamps_count():
					if rd.get_captured_timestamp_name(i) == "mm_begin": first = rd.get_captured_timestamp_gpu_time(i)
					if rd.get_captured_timestamp_name(i) == "mm_end" and first >= 0:
						measurements.gpu.append((rd.get_captured_timestamp_gpu_time(i)-first)/1000000.0)
				measurements.last_frame = captured
			rd.capture_timestamp("mm_begin")
			var started := Time.get_ticks_usec()
			state.dispatch(steps,parameter_data,0)
			if current > 20: measurements.cpu.append((Time.get_ticks_usec()-started)/1000.0)
			rd.capture_timestamp("mm_end"))
		await process_frame
		await RenderingServer.frame_post_draw
	var result := {}
	RenderingServer.call_on_render_thread(func():
		var rd: RenderingDevice = state.rd
		if render_dimension == 3:
			result.count = rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid())).decode_u32(4)
		else:
			var offset: int = compiled.effect.attribute("alive").offset*CAPACITY*4
			var alive := rd.buffer_get_data(state.owned_buffers[0],offset,CAPACITY*4)
			result.count = 0
			for i in CAPACITY:
				if alive.decode_u32(i*4) != 0: result.count += 1
		result.values = []
		for index in 32:
			var offset: int = compiled.effect.attribute("field"+str(index)).offset
			var data := rd.buffer_get_data(state.owned_buffers[0],offset*CAPACITY*4,4*CAPACITY*4)
			for component in 4:
				result.values.append([data.decode_float(component*CAPACITY*4),data.decode_float(((component+1)*CAPACITY-1)*4),index+(component+1)*TICKS])
		result.allocation_bytes = state.allocation_bytes
		result.done = true)
	while not result.has("done"): await process_frame
	check(result.count == CAPACITY,"all 100k remain alive")
	for row in result.values: check(row[0] == row[2] and row[1] == row[2],"SoA field first/last slot roundtrip")
	check(measurements.gpu.size() >= 100,"GPU timestamp sample count")
	var report := {"render_dimension":render_dimension,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"capacity":CAPACITY,"custom_vec4":32,"components":compiled.effect.component_count,"allocation_bytes":result.allocation_bytes,"samples":measurements.gpu.size(),"gpu_ms":stats(measurements.gpu),"render_thread_submission_ms":stats(measurements.cpu),"readback_in_timed_region":false,"rendering_in_timed_region":false}
	if render_dimension == 2:
		# Measure Canvas separately from simulation; all 100k slots are submitted.
		# Tiny quads bound overdraw rather than hiding the draw node as above.
		particles.pixels_per_unit = 1.0
		particles.position = Vector2(64,64)
		particles.show()
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		var canvas_gpu: Array = []
		var canvas_cpu: Array = []
		for frame in 120:
			await process_frame
			await RenderingServer.frame_post_draw
			if frame > 20:
				canvas_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				canvas_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		report["canvas_gpu_ms"] = stats(canvas_gpu)
		report["canvas_cpu_ms"] = stats(canvas_cpu)
		report["canvas_instances_submitted"] = CAPACITY
	var file := FileAccess.open("res://performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("MODULAR_PERFORMANCE_RESULT ",JSON.stringify(report))
	particles.queue_free()
	for frame in 8: await process_frame
	print("MODULAR_PERFORMANCE ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean":total/values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*0.95)]}
