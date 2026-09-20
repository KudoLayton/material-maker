extends Node

const Exporter = preload("res://addons/material_maker/particles/exporter.gd")
var graph: MMGenGraph
var checks := 0

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		push_error("PARTICLE_INTEGRATION: " + message)
		get_tree().quit(1)
	return condition

func run() -> void:
	var loader = get_node("/root/mm_loader")
	graph = await loader.create_gen({"nodes": [
		{"type": "particle_export", "name": "Material"},
		{"type": "particle_node", "name": "Process", "settings": {"kind": "output", "stage": "process"}}
	], "connections": []})
	if not check(graph is MMGenGraph and graph.get_node_or_null("Material") != null, "Particle outputs must use MMGenGraph"): return
	add_child(graph)
	if not valid("Empty stages"): return
	var noise = await add({"type": "noise", "name": "Noise"})
	var transform = await add({"type": "transform", "name": "Transform"})
	var colorize = await add({"type": "colorize", "name": "Colorize"})
	var uv = await particle("Coordinates", {"kind": "constant", "data_type": "vec2"}, {"v0": 0.25, "v1": 0.75})
	var evaluate = await particle("Evaluate", {"kind": "evaluate", "function_type": "rgba"})
	connect_nodes(noise, 0, transform, 0)
	connect_nodes(transform, 0, colorize, 0)
	connect_nodes(colorize, 0, evaluate, 0)
	connect_nodes(uv, 0, evaluate, 1)
	connect_named(evaluate, "value", graph.get_node("Material"), "COLOR")
	connect_named(evaluate, "value", graph.get_node("Process"), "COLOR")
	if not valid("Noise/Transform/Colorize in both stages"): return
	var module := graph.create_subgraph([noise, transform, colorize])
	module.set_type_name("Particle Color Module")
	var remote = module.get_node("gen_parameters")
	remote.widgets = [{"name": "density", "label": "Density", "type": "linked_control", "linked_widgets": [{"node": "Noise", "widget": "density"}]}]
	remote.fix()
	module.set_parameter("density", 0.3)
	if not check(noise.get_parameter("density") == 0.3, "Exposed subgraph parameter controls stock node"): return
	var nested := graph.create_subgraph([module, evaluate])
	if not valid("Nested MMGenGraph interfaces"): return
	var library = load("res://material_maker/tools/library_manager/library.gd").new()
	library.create_library("res://test_modules.json", "Particle test modules")
	library.add_item("Modules/Particle Color", null, nested.serialize())
	if not check(library.save_library() == OK, "Save module library"): return
	var reloaded = library.get_script().new()
	if not check(reloaded.load_library("res://test_modules.json"), "Reload module library"): return
	var restored = await add(reloaded.get_item("Modules/Particle Color").item)
	connect_nodes(uv, 0, restored, 0)
	connect_nodes(restored, 0, graph.get_node("Process"), input_index(graph.get_node("Process"), "COLOR"))
	if not valid("Module reused from library"): return
	DirAccess.make_dir_recursive_absolute("res://exported")
	FileAccess.open("res://exported/library_module.ptex", FileAccess.WRITE).store_string(JSON.stringify(graph.serialize(), "\t"))
	library.free()
	reloaded.free()
	var roundtrip = await loader.create_gen(JSON.parse_string(JSON.stringify(graph.serialize())))
	add_child(roundtrip)
	var roundtrip_result: Dictionary = Exporter.validate(roundtrip.get_node("Material").compile_shader())
	if not check(roundtrip_result.errors.is_empty(), "Graph roundtrip: " + str(roundtrip_result.errors)): return
	roundtrip.queue_free()
	var time = await particle("Time", {"kind": "input", "builtin": "TIME"})
	var bridge = await particle("TimeFunction", {"kind": "bridge", "function_type": "f"})
	var blur = await add({"type": "gaussian_blur_x", "name": "Helper"})
	var helper_eval = await particle("HelperEvaluation", {"kind": "evaluate", "function_type": "rgba"})
	var helper_uv = await particle("HelperUV", {"kind": "constant", "data_type": "vec2"})
	connect_nodes(time, 0, bridge, 0)
	connect_nodes(bridge, 0, blur, 0)
	connect_nodes(blur, 0, helper_eval, 0)
	connect_nodes(helper_uv, 0, helper_eval, 1)
	connect_named(helper_eval, "value", graph.get_node("Process"), "COLOR")
	if not valid("State in generated input and instance functions"): return
	var collision = await particle("Collision", {"kind": "input", "builtin": "COLLISION_DEPTH"})
	connect_nodes(collision, 0, bridge, 0)
	connect_named(helper_eval, "value", graph.get_node("Material"), "COLOR")
	var result = graph.get_node("Material").compile_shader()
	if not check(not result.errors.is_empty(), "Process-only input in Start"): return
	connect_nodes(time, 0, bridge, 0)
	await particle("DisconnectedInvalid", {"kind": "input", "builtin": "NOT_A_BUILTIN"})
	if not valid("Disconnected invalid nodes ignored"): return
	var buffer = await add({"type": "buffer", "name": "RuntimeBuffer", "version": 2, "parameters": {"size": 4, "f32": true}})
	connect_nodes(bridge, 0, buffer, 0)
	connect_nodes(buffer, 0, helper_eval, 0)
	result = graph.get_node("Material").compile_shader()
	if not check(str(result.errors).contains("cannot bake"), "Runtime bake rejected"): return
	var hdr = await add({"type": "shader", "name": "HDR", "shader_model": {"name": "HDR", "inputs": [], "parameters": [], "outputs": [{"type": "rgba", "rgba": "vec4(-2.0, 3.0, 0.25, 0.4)"}]}})
	connect_nodes(hdr, 0, buffer, 0)
	for frame in 30: await get_tree().process_frame
	if not valid("Static float buffer"): return
	var exported: Dictionary = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, "res://integration")
	if not check(exported.errors.is_empty(), str(exported.errors)): return
	var material = load("res://integration.tres")
	if not check(material is ShaderMaterial, "Exported material loads"): return
	var texture_count := 0
	for uniform in material.shader.get_shader_uniform_list():
		var texture = material.get_shader_parameter(uniform.name)
		if texture is Texture2D:
			texture_count += 1
			var pixel: Color = texture.get_image().get_pixel(0, 0)
			if not check(absf(pixel.r + 2.0) < 0.001 and absf(pixel.g - 3.0) < 0.001 and absf(pixel.a - 0.4) < 0.001, "HDR/alpha: " + str(pixel)): return
	if not check(texture_count == 1, "Both stages share texture"): return
	var constant = await particle("StaticColor", {"kind": "constant", "data_type": "vec4"}, {"v0": 0.75, "v1": 0.25, "v2": 0.5, "v3": 1.0})
	var static_bridge = await particle("StaticFunction", {"kind": "bridge", "function_type": "rgba"})
	var fast_blur = await add({"type": "fast_blur", "name": "FastBlur"})
	for b in fast_blur.get_buffers(): b.set_parameter("size", 4)
	connect_nodes(constant, 0, static_bridge, 0)
	connect_nodes(static_bridge, 0, fast_blur, 0)
	connect_nodes(fast_blur, 0, helper_eval, 0)
	if not valid("Static value bridge and Fast Blur"): return
	var baked: Dictionary = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, "res://fast_blur")
	if not check(baked.errors.is_empty(), "Fast Blur export: " + str(baked.errors)): return
	constant.set_parameter("v0", 0.1)
	baked = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, "res://fast_blur_updated")
	if not check(baked.errors.is_empty(), "Immediate re-export after parameter edit"): return
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.6, 0.8))
	img.save_png("res://source_image.png")
	var image_node = await add({"type": "image", "name": "SourceImage", "parameters": {"image": "res://source_image.png"}})
	connect_nodes(image_node, 0, helper_eval, 0)
	baked = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, "res://image_particle")
	if not check(baked.errors.is_empty(), "Image export: " + str(baked.errors)): return
	var image_material = load("res://image_particle.tres")
	for uniform in image_material.shader.get_shader_uniform_list():
		var texture = image_material.get_shader_parameter(uniform.name)
		if texture is Texture2D:
			if not check(absf(texture.get_image().get_pixel(0, 0).a - 0.8) < 0.01, "Image alpha preserved"): return
	print("PARTICLE_INTEGRATION: passed (%d checks)" % checks)
	graph.queue_free()
	for frame in 3: await get_tree().process_frame
	get_tree().quit()

func add(data: Dictionary):
	var node = await get_node("/root/mm_loader").create_gen(data)
	graph.add_generator(node)
	return node

func particle(node_name: String, settings: Dictionary, parameters: Dictionary = {}):
	return await add({"type": "particle_node", "name": node_name, "settings": settings, "parameters": parameters})

func connect_nodes(from: MMGenBase, from_port: int, to: MMGenBase, to_port: int) -> void:
	graph.connect_children(from, from_port, to, to_port)

func input_index(node: MMGenBase, name: String) -> int:
	var inputs := node.get_input_defs()
	for i in inputs.size():
		if inputs[i].name == name: return i
	return -1

func connect_named(from: MMGenBase, output: String, to: MMGenBase, input: String) -> void:
	var outputs: Array = from.particle_ports().outputs
	for i in outputs.size():
		if outputs[i].name == output:
			connect_nodes(from, i, to, input_index(to, input))
			return

func valid(label: String) -> bool:
	var result: Dictionary = Exporter.validate(graph.get_node("Material").compile_shader())
	FileAccess.open("res://last_shader.gdshader", FileAccess.WRITE).store_string(result.code)
	return check(result.errors.is_empty(), label + ": " + str(result.errors))
