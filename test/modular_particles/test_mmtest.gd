extends Node
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Oracle = preload("mmtest_oracle.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var doc := Document.load_file("res://material_maker/examples/modular_particles/mmtest.mpfx")
	var reference_path := "res://test/modular_particles/fixtures/mmtest_reference.ptex"
	check(FileAccess.get_sha256(reference_path) == doc.reference.sha256,"reference fixture hash")
	var legacy_graph = await mm_loader.create_gen(Document.load_file(reference_path))
	add_child(legacy_graph)
	var legacy: Dictionary = legacy_graph.get_node("Material").compile_shader()
	check(legacy.errors.is_empty(),"fresh legacy ptex compilation: " + str(legacy.errors))
	if not legacy.errors.is_empty():
		legacy_graph.free()
		await finish()
		return
	var oracle_code := Oracle.source(legacy)
	legacy_graph.free()
	var graphs := {}
	for id in doc.modules: graphs[id] = await mm_loader.create_gen(doc.modules[id].mm_graph)
	var result := Compiler.new().compile(doc,graphs)
	for graph in graphs.values(): graph.free()
	check(result.errors.is_empty(),"mmtest module compilation: " + str(result.errors))
	if result.effect == null:
		await finish()
		return
	var particles := Particles.new()
	particles.capacity = 128
	particles.manual_processing = true
	particles.effect = result.effect
	particles.emitting = false
	add_child(particles)
	var camera := Camera3D.new()
	camera.position = Vector3(0,0,6)
	add_child(camera)
	camera.current = true
	get_tree().root.size = Vector2i(960,640)
	for frame in 120:
		await get_tree().process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation,"mmtest GPU: " + particles.error_text)
	if particles.ready_for_simulation:
		particles.emit_burst(128)
		for tick in 40:
			particles.advance(1.0/60.0)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			if tick == 19: get_tree().root.get_texture().get_image().save_png("res://mmtest.png")
			if tick+1 not in [1,10,20,40]: continue
			var values := {}
			var state = particles._gpu
			var steps := tick+1
			RenderingServer.call_on_render_thread(func():
				values.modular = state.rd.buffer_get_data(state.owned_buffers[0])
				values.legacy = Oracle.evaluate(oracle_code,steps)
				values.done = true)
			while not values.has("done"): await get_tree().process_frame
			check(values.legacy.error.is_empty(),"legacy oracle compute: " + values.legacy.error)
			if not values.legacy.error.is_empty(): break
			var comparisons := {"position":[0,3,0.003],"velocity":[3,3,0.03],"scale":[6,3,0.00001],"age":[9,1,0.00001],"initial_velocity":[10,3,0.00001],"spherical_uv":[13,2,0.00001],"curl_velocity":[15,3,0.03]}
			for attribute in comparisons:
				var comparison: Array = comparisons[attribute]
				var max_error := 0.0
				var offset: int = result.effect.attribute(attribute).offset
				for i in 128:
					for component in comparison[1]:
						var a: float = values.modular.decode_float(((offset+component)*128+i)*4)
						var b: float = values.legacy.data.decode_float((i*20+comparison[0]+component)*4)
						max_error = maxf(max_error,absf(a-b)) if is_finite(a) and is_finite(b) else INF
				check(max_error <= comparison[2],"step %d %s max error %g" % [steps,attribute,max_error])
				print("MODULAR_MMTEST_COMPARE step=",steps," field=",attribute," max_error=",max_error)
	particles.queue_free()
	camera.queue_free()
	for frame in 5: await get_tree().process_frame
	await finish()
func finish() -> void:
	print("MODULAR_MMTEST ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
