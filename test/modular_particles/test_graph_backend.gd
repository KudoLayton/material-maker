extends Node
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var doc := Document.create()
	doc.emitter.rate = 0.0
	doc.attributes = [{"id":"curve","name":"Curve","type":"float","default":0.0},{"id":"noise","name":"Noise","type":"float","default":0.0}]
	var fields: Array = [{"id":"curve","name":"Curve","type":"float"},{"id":"noise","name":"Noise","type":"float"},{"id":"rotation","name":"Rotation","type":"vec4"}]
	var module := Library.definition("Procedural",["spawn"],fields)
	var curve := {"type":"tonality","name":"Curve","parameters":{"curve":{"type":"Curve","points":[{"x":0.0,"y":1.0,"ls":-1.0,"rs":-1.0},{"x":1.0,"y":0.0,"ls":-1.0,"rs":-1.0}]}}}
	var nested := {"type":"graph","name":"NestedCurve","nodes":[{"name":"Value","type":"uniform_greyscale","parameters":{"color":0.25}},curve,{"name":"gen_inputs","type":"ios","ports":[]},{"name":"gen_outputs","type":"ios","ports":[{"name":"value","type":"f"}]},{"name":"gen_parameters","type":"remote","widgets":[]}],"connections":[Library.connect_nodes("Value","Curve",0),Library.connect_nodes("Curve","gen_outputs",0)]}
	var quaternion_fixture := Document.load_file("res://material_maker/examples/particles/quaternion_rotation.ptex")
	var quaternion_node: Dictionary = quaternion_fixture.nodes.filter(func(n): return n.name == "Filter_Math_Euler_to_Quaternion")[0].duplicate(true)
	quaternion_node.name = "Quaternion"
	module.mm_graph.nodes.append_array([nested,
		{"name":"FBM","type":"fbm4","parameters":{"noise":1.0,"iterations":3.0,"scale_x":2.0,"scale_y":2.0}},
		{"name":"UV","type":"particle_node","settings":{"kind":"constant","data_type":"vec2"},"parameters":{"v0":0.17,"v1":0.29}},
		{"name":"Evaluate","type":"particle_node","settings":{"kind":"evaluate","function_type":"f"},"parameters":{}},quaternion_node])
	module.mm_graph.connections = [Library.connect_nodes("NestedCurve","Output",0),Library.connect_nodes("FBM","Evaluate",0),Library.connect_nodes("UV","Evaluate",1),Library.connect_nodes("Evaluate","Output",1),Library.connect_nodes("Quaternion","Output",2)]
	doc.modules.procedural = module
	doc.stages.spawn = [{"id":"first","module":"procedural","parameters":{}},{"id":"second","module":"procedural","parameters":{}}]
	var variant: Dictionary = module.duplicate(true)
	var nested_variant: Dictionary = variant.mm_graph.nodes.filter(func(n): return n.name == "NestedCurve")[0]
	var curve_variant: Dictionary = nested_variant.nodes.filter(func(n): return n.name == "Curve")[0]
	curve_variant.parameters.curve.points = [{"x":0.0,"y":0.0,"ls":1.0,"rs":1.0},{"x":1.0,"y":1.0,"ls":1.0,"rs":1.0}]
	doc.modules["variant"] = variant
	doc.stages.spawn.append({"id":"third","module":"variant","parameters":{}})
	var graphs := {}
	for id in doc.modules: graphs[id] = await mm_loader.create_gen(doc.modules[id].mm_graph)
	var result := Compiler.new().compile(doc,graphs)
	check(result.errors.is_empty(), "nested graph/Curve/FBM/Evaluate/Quaternion: " + str(result.errors))
	for graph in graphs.values(): graph.free()
	if result.effect == null:
		await finish()
		return
	graphs.clear()
	for id in doc.modules: graphs[id] = await mm_loader.create_gen(doc.modules[id].mm_graph)
	var repeated := Compiler.new().compile(doc,graphs)
	for graph in graphs.values(): graph.free()
	check(repeated.errors.is_empty() and repeated.effect.source_hash == result.effect.source_hash,"procedural and typed transient IDs have stable compilation hash")
	var particles := Particles.new()
	particles.manual_processing = true
	particles.capacity = 4
	particles.effect = result.effect
	add_child(particles)
	for frame in 120:
		await get_tree().process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation, "procedural GPU shader: " + particles.error_text)
	if particles.ready_for_simulation:
		particles.emit_burst(1)
		particles.advance(1.0/60.0)
		for frame in 3:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var values := {}
		var state = particles._gpu
		RenderingServer.call_on_render_thread(func():
			values.data = state.rd.buffer_get_data(state.owned_buffers[0])
			values.done = true)
		while not values.has("done"): await get_tree().process_frame
		var curve_offset: int = result.effect.attribute("curve").offset * 4 * particles.capacity
		var noise_offset: int = result.effect.attribute("noise").offset * 4 * particles.capacity
		var quat_offset: int = (result.effect.attribute("rotation").offset + 3) * 4 * particles.capacity
		check(absf(values.data.decode_float(curve_offset)-0.25) < 1e-5,"distinct Curve module namespaces and numerical output")
		check(is_finite(values.data.decode_float(noise_offset)),"FBM numerical output finite")
		check(absf(values.data.decode_float(quat_offset)-1.0) < 1e-5,"Quaternion identity")
	particles.queue_free()
	for frame in 5: await get_tree().process_frame
	await finish()
func finish() -> void:
	print("MODULAR_GRAPH_BACKEND ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
