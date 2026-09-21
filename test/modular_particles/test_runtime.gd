extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
const Scheduler = preload("res://addons/mm_gpu_particles/scheduler.gd")
var failures := 0
var checks := 0
var particles: MMGPUParticles3D

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ",message)

func _initialize() -> void:
	call_deferred("run")

func wait_ready() -> void:
	for frame in 120:
		await process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation, "runtime initialized: " + particles.error_text)

func snapshot() -> Dictionary:
	var result := {}
	var state = particles._gpu
	RenderingServer.call_on_render_thread(func():
		if state == null or not state.ready:
			result.error = "GPU not ready"
		else:
			result.data = state.rd.buffer_get_data(state.owned_buffers[0])
			result.commands = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid()))
			result.instances = state.rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(state.multimesh.get_rid()))
		result.done = true)
	while not result.has("done"): await process_frame
	return result

func step(count: int = 1) -> void:
	for tick in count:
		particles.advance(Scheduler.STEP)
		await process_frame
		await RenderingServer.frame_post_draw

func f(data: PackedByteArray, attribute: String, index: int, component: int = 0) -> float:
	return data.decode_float((int(particles.effect.attribute(attribute).offset + component) * particles.capacity + index) * 4)

func u(data: PackedByteArray, attribute: String, index: int) -> int:
	return data.decode_u32((int(particles.effect.attribute(attribute).offset) * particles.capacity + index) * 4)

func run() -> void:
	var doc := Fixtures.basic()
	doc.emitter.rate = 0.0
	doc.emitter.lifetime = 0.04
	for i in 33: doc.attributes.append({"id":"v"+str(i),"name":"V","type":"vec4","default":[1.0,2.0,3.0,4.0]})
	doc.attributes.append({"id":"exact","name":"Exact","type":"uint","default":4294967295})
	doc.attributes.append({"id":"counter","name":"Counter","type":"float","default":5.0})
	doc.modules.counter = {"name":"Counter","stages":["update"],"inputs":[],"reads":["counter"],"writes":["counter"],"graph":{"nodes":[{"id":"read","op":"read","attribute":"counter"},{"id":"one","op":"constant","type":"float","value":1.0},{"id":"sum","op":"add","args":["read","one"]}],"outputs":{"counter":"sum"}}}
	doc.stages.update.append({"id":"count1","module":"counter"})
	var result := Compiler.new().compile(doc)
	check(result.errors.is_empty(), "test effect compile: " + str(result.errors))
	if result.effect == null:
		quit(1)
		return
	particles = Particles.new()
	particles.manual_processing = true
	particles.capacity = 4
	particles.effect = result.effect
	root.add_child(particles)
	await wait_ready()
	if not particles.ready_for_simulation:
		particles.queue_free()
		await process_frame
		quit(1)
		return
	particles.emit_burst(6)
	await step()
	var first := await snapshot()
	check(first.commands.decode_u32(4) == 4, "capacity overflow clamps on GPU")
	check(is_equal_approx(f(first.data,"position",0),1.0/60.0), "Spawn then Update integration")
	check(is_equal_approx(f(first.data,"counter",0),6.0), "initialized attribute then update")
	check(u(first.data,"exact",0) == 4294967295, "uint is bit-exact")
	check(f(first.data,"v32",3,3) == 4.0, "33rd custom vec4 survives GPU storage")
	check(u(first.data,"particle_id",3) == 3, "stable slot-order allocation")
	particles.pause()
	await step(3)
	var paused := await snapshot()
	check(paused.data == first.data, "pause freezes state")
	particles.emit_burst(1)
	particles.play()
	particles.stop()
	await step()
	var second := await snapshot()
	check(f(second.data,"counter",0) == 7.0, "stop still updates live particles")
	await step()
	var dead := await snapshot()
	check(dead.commands.decode_u32(4) == 0, "per-particle lifetime kills")
	particles.emit_burst(2)
	await step()
	var recycled := await snapshot()
	check(recycled.commands.decode_u32(4) == 2, "dead slots recycled without delayed overflow")
	check(f(recycled.data,"counter",0) == 6.0, "recycled attributes reinitialized")
	check(u(recycled.data,"particle_id",0) == 7, "dropped spawn requests still advance sequence")
	particles.restart()
	await wait_ready()
	particles.emit_burst(6)
	await step()
	var repeated := await snapshot()
	check(repeated.data == first.data, "restart restores deterministic state")
	check(particles.set_parameter("spawn1/speed",2.0), "typed override accepted")
	check(not particles.set_parameter("spawn1/speed",Vector3.ONE), "bad override rejected")
	particles.simulation_space = 1
	particles.position = Vector3(5,0,0)
	await wait_ready()
	particles.emit_burst(1)
	await step()
	var world := await snapshot()
	check(absf(f(world.data,"position",0) - (5.0+2.0/60.0)) < 1e-5, "World emission transform")
	check(particles._draw.global_transform == Transform3D.IDENTITY, "World draw has no double transform")
	particles.simulation_space = 0
	await wait_ready()
	particles.emit_burst(1)
	await step()
	var local := await snapshot()
	check(absf(f(local.data,"position",0) - 2.0/60.0) < 1e-5, "Local position excludes emitter transform")
	var random_doc := Fixtures.basic()
	random_doc.emitter.rate = 0.0
	random_doc.modules.initialize.graph.nodes[0] = {"id":"direction","op":"random","type":"vec3","seed":5}
	particles.effect = Compiler.new().compile(random_doc).effect
	particles.seed = 42
	await wait_ready()
	particles.emit_burst(4)
	await step()
	var random_first := await snapshot()
	particles.restart()
	await wait_ready()
	particles.emit_burst(4)
	await step()
	var random_repeat := await snapshot()
	check(random_first.data == random_repeat.data, "seeded random restart repeatability")
	particles.seed = 43
	await wait_ready()
	particles.emit_burst(4)
	await step()
	var random_changed := await snapshot()
	check(random_first.data != random_changed.data, "different seed changes particle values")
	var scheduler := Scheduler.new()
	var config := {"rate":30.0,"duration":1.0,"loop":true,"bursts":[]}
	var total := 0
	for tick in 60:
		for scheduled in scheduler.advance(Scheduler.STEP, config, true): total += scheduled.spawn_count
	check(total == 30, "fractional continuous rate")
	scheduler.reset()
	config.rate = 0.0
	config.bursts = [{"time":0.0,"count":3}]
	total = 0
	for tick in 120:
		for scheduled in scheduler.advance(Scheduler.STEP, config, true): total += scheduled.spawn_count
	check(total == 6, "loop burst exactly once per cycle")
	scheduler.reset()
	check(scheduler.advance(10.0,config,true).size() == 8 and scheduler.dropped_time > 9.0, "bounded catchup")
	particles.queue_free()
	await process_frame
	await process_frame
	print("MODULAR_RUNTIME ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
