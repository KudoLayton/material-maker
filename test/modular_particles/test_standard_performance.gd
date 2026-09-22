extends Node
const S = preload("standard_checks.gd")
const CAPACITY := 100000
const TICKS := 100
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func stats(values: Array) -> Dictionary:
	values.sort()
	return {} if values.is_empty() else {"median":values[values.size()/2],"p95":values[int(values.size()*0.95)]}
func run() -> void:
	var report := {"capacity":CAPACITY,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"readback_in_timed_region":false,"raster_in_timed_region":false,"cases":{}}
	for curl_enabled in [false,true]:
		var doc := S.document(["initialize_particle","box_location"],["gravity","curl_noise","drag","solve_motion"])
		doc.emitter.lifetime = 100.0
		S.instance(doc,"curl_noise").enabled = curl_enabled
		var compiled := await S.compile(doc)
		check(compiled.errors.is_empty(),"100k compile "+str(compiled.errors))
		if compiled.effect == null: continue
		var particles = await S.start(self,compiled.effect,CAPACITY)
		check(particles.ready_for_simulation,"100k GPU allocation "+particles.error_text)
		if not particles.ready_for_simulation:
			await S.dispose(particles)
			continue
		var state = particles._gpu
		var params := S.Codec.pack(particles.effect,{},Transform3D.IDENTITY,false)
		var measurements := {"gpu":[],"last_frame":-1}
		for tick in TICKS:
			var current := tick
			var steps: Array[Dictionary] = [{"time":(tick+1)/60.0,"spawn_count":CAPACITY if tick == 0 else 0,"spawn_base":0}]
			RenderingServer.call_on_render_thread(func():
				var rd: RenderingDevice = state.rd
				var captured := rd.get_captured_timestamps_frame()
				if current > 20 and captured != measurements.last_frame:
					var begin: int = -1
					for index in rd.get_captured_timestamps_count():
						if rd.get_captured_timestamp_name(index) == "standard_begin": begin = rd.get_captured_timestamp_gpu_time(index)
						if rd.get_captured_timestamp_name(index) == "standard_end" and begin >= 0: measurements.gpu.append((rd.get_captured_timestamp_gpu_time(index)-begin)/1000000.0)
					measurements.last_frame = captured
				rd.capture_timestamp("standard_begin")
				state.dispatch(steps,params,0)
				rd.capture_timestamp("standard_end"))
			await S.frames(get_tree(),1)
		var snapshot := await S.snapshot(particles)
		check(snapshot.count == CAPACITY,"100k remain alive")
		check(S.vector(particles,snapshot,"position").is_finite() and S.vector(particles,snapshot,"position",CAPACITY-1).is_finite(),"first/last slots finite")
		check(measurements.gpu.size()>=50,"GPU timing samples")
		report.cases["curl_on" if curl_enabled else "curl_off"] = {"samples":measurements.gpu.size(),"gpu_ms":stats(measurements.gpu),"allocation_bytes":state.allocation_bytes,"components":compiled.effect.component_count}
		await S.dispose(particles)
	var file := FileAccess.open("res://standard-performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("MODULAR_STANDARD_PERFORMANCE_RESULT ",JSON.stringify(report))
	print("MODULAR_STANDARD_PERFORMANCE ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
