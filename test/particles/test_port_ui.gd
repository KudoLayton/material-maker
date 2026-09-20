extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures.append(message)
	return value

func has_label(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if label.text == text: return true
	return false

func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	get_tree().root.size = Vector2i(1600, 1000)
	var editor = await window.new_particle_shader()
	for frame in 3: await get_tree().process_frame
	var start = editor.get_node("node_Material")
	check(start.get_input_port_color(3) == mm_io_types.types.f.color, "MASS must reuse Grayscale color")
	check(has_label(start, "MASS : float"), "Start ports must display their exact type")
	if not failures.is_empty():
		print("PARTICLE_PORT_UI: " + str(failures))
		get_tree().quit(1)
		return
	var palette = {"float": mm_io_types.types.f.color, "vec3": mm_io_types.types.rgb.color,
		"vec4": mm_io_types.types.rgba.color, "vec2": Color("43bfa9"), "exec": mm_io_types.types.any.color}
	for type in ["bool", "bvec2", "bvec3", "bvec4"]: palette[type] = Color("d9c65d")
	for type in ["int", "uint", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"]: palette[type] = Color("c98b60")
	for type in ["mat2", "mat3", "mat4"]: palette[type] = Color("9a83d6")
	for type in MMGenParticle.Interface.TYPES:
		if type.begins_with("sampler"): palette[type] = Color("c879b5")
	for type in palette:
		check(mm_io_types.types[MMGenParticle.value_type(type)].color == palette[type], "Palette " + type)
		if type != "exec": check(mm_io_types.types[MMGenParticle.value_type(type + "[4]")].color == palette[type], "Array color " + type)
	for stage in ["Material", "Process"]:
		var output = editor.get_node("node_" + stage)
		var ports = output.generator.get_input_defs()
		var original_ports = MMGenParticle.Interface.ports({"kind": "output", "transform_mode": 0}, "start" if stage == "Material" else "process").inputs
		check(ports.size() == original_ports.size() + 1 and ports[-1].name == "sampling_uv", stage + " appends Sampling UV")
		for i in original_ports.size(): check(ports[i].name == original_ports[i].name, stage + " preserves port index " + str(i))
		for i in ports.size():
			var type: String = ports[i].get("shader_type", mm_io_types.types[ports[i].type].get("particle_type", ""))
			check(output.get_input_port_color(i) == palette[type], stage + " color " + ports[i].name)
			check(has_label(output, ports[i].get("label", ports[i].name) + " : " + type), stage + " label " + ports[i].name)
	var created = await editor.create_nodes({"type": "particle_node", "settings": {"kind": "constant", "data_type": "float"}}, Vector2(-500, 0))
	var constant = created[0]
	check(has_label(constant, "Value : float"), "Constant output label")
	constant.controls.data_type.select(MMGenParticle.Interface.TYPES.find("bvec3"))
	constant.controls.data_type.item_selected.emit(MMGenParticle.Interface.TYPES.find("bvec3"))
	for frame in 3: await get_tree().process_frame
	check(has_label(constant, "Value : bvec3") and constant.get_output_port_color(0) == palette.bool, "Type change refreshes label and color")
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	check(has_label(constant, "Value : float") and constant.get_output_port_color(0) == palette.float, "Undo refreshes label and color")
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	check(has_label(constant, "Value : bvec3"), "Redo refreshes label")
	check(mm_io_types.types.f.slot_type == mm_io_types.types.particle_float.slot_type, "Legacy numeric aliases share the standard connection type")
	var custom_nodes = await editor.create_nodes({"type": "shader", "name": "TypedCustom", "shader_model": {
		"name": "Typed Custom", "parameters": [],
		"inputs": [{"name": "velocity", "type": "particle_vec3", "default": "vec3(0.0)"}],
		"outputs": [{"type": "particle_vec3", "particle_vec3": "$velocity($uv)"}]}}, Vector2(-500, 250))
	check(has_label(custom_nodes[0], "velocity : vec3") and has_label(custom_nodes[0], "value : vec3"), "Custom Shader typed ports")
	var evaluation_nodes = await editor.create_nodes({"type": "particle_node", "name": "Evaluate", "settings": {"kind": "evaluate", "function_type": "rgba"}}, Vector2(-500, 500))
	check(evaluation_nodes[0].get_input_port_color(0) == mm_io_types.types.rgba.color, "Evaluate keeps function color")
	check(has_label(evaluation_nodes[0], "Coordinates : vec2") and has_label(evaluation_nodes[0], "Value : vec4"), "Evaluate typed value ports")
	var graph = editor.top_generator
	var uniform = await mm_loader.create_gen({"type": "particle_node", "name": "Array", "settings": {"kind": "uniform", "data_type": "float"}, "parameters": {"array_size": 4}})
	var element = await mm_loader.create_gen({"type": "particle_node", "name": "Element", "settings": {"kind": "array_get", "data_type": "float", "array_size": 4}})
	graph.add_generator(uniform)
	graph.add_generator(element)
	graph.connect_children(uniform, 0, element, 0)
	graph.connect_children(element, 0, graph.get_node("Process"), 3)
	var module = graph.create_subgraph([element])
	var nested = graph.create_subgraph([module])
	await editor.update_view(graph)
	for frame in 3: await get_tree().process_frame
	var module_node = editor.get_node("node_" + nested.name)
	check(has_label(module_node, "port0 : float[4]"), "Nested subgraph array input label")
	check(has_label(module_node, "port0 : float"), "Nested subgraph output label")
	check(module_node.get_input_port_color(0) == palette.float, "Subgraph array color")
	var library = load("res://material_maker/tools/library_manager/library.gd").new()
	library.create_library("res://app_port_library.json", "Port UI regression")
	library.add_item("Modules/Array Element", null, nested.serialize())
	library.load_library("res://app_port_library.json")
	var copies = await editor.create_nodes(library.get_item("Modules/Array Element").item, Vector2(-500, 400))
	check(has_label(copies[0], "port0 : float[4]"), "Library reuse keeps typed label")
	library.free()
	check(await editor.save_file("res://app_port_ui.ptex"), "Save graph")
	check(await window.do_load_project("res://app_port_ui.ptex"), "Reopen graph")
	for frame in 5: await get_tree().process_frame
	editor = window.get_current_graph_edit()
	module_node = editor.get_node("node_" + nested.name)
	check(has_label(module_node, "port0 : float[4]") and module_node.get_input_port_color(0) == palette.float, "Reopened graph keeps presentation")
	check(editor.top_generator.get_node(NodePath(nested.name)).get_input_defs()[0].name == "port0", "Display suffix is not serialized as port name")
	await window.new_particle_shader()
	window.layout.reset_panels()
	for theme in ["Default Dark", "Default Light"]:
		await window.change_theme(theme.to_lower())
		for frame in 30: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png("res://app_ports_" + theme.to_lower().replace(" ", "_") + ".png")
	await window.change_theme("default dark")
	print("PARTICLE_PORT_UI: %d checks; failures=%s" % [checks, str(failures)])
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	if failures.is_empty(): window.quit()
	else: get_tree().quit(1)
