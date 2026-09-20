extends "test_runtime.gd"

func make_graph():
	var graph = await mm_loader.create_gen({"nodes": [
		{"type": "particle_export", "name": "Material"},
		{"type": "particle_node", "name": "Process", "settings": {"kind": "output", "stage": "process"}}
	], "connections": []})
	add_child(graph)
	return graph

func add(graph, data):
	var node = await mm_loader.create_gen(data)
	graph.add_generator(node)
	return node

func particle(graph, name: String, settings: Dictionary):
	return await add(graph, {"type": "particle_node", "name": name, "settings": settings})

func connect_output(graph, source, target_name: String, input_name: String):
	var target = graph.get_node(target_name)
	for i in target.get_input_defs().size():
		if target.get_input_defs()[i].name == input_name:
			graph.connect_children(source, 0, target, i)
			return
	check(false, "Missing input " + input_name)

func probe(graph, assertion: String, name: String):
	var result = graph.get_node("Material").compile_shader()
	check(result.errors.is_empty(), name + ": " + str(result.errors))
	if not result.errors.is_empty(): return
	result.code = result.code.insert(result.code.rfind("}"), "COLOR = (" + assertion + ") ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);\n")
	await render_probe({}, false, name, false, result)

func run():
	DirAccess.make_dir_recursive_absolute("res://exported")
	check(MMGenParticle.value_type("float") == "f", "float uses Grayscale")
	check(MMGenParticle.value_type("vec3") == "rgb", "vec3 uses Color")
	check(MMGenParticle.value_type("vec4") == "rgba", "vec4 uses RGBA")
	if not failures.is_empty():
		print("PARTICLE_UNIFIED: " + str(failures))
		get_tree().quit(1)
		return
	var graph = await make_graph()
	var random = await particle(graph, "Random", {"kind": "random", "data_type": "vec3", "minimum": 0.25, "maximum": 0.25})
	var math = await add(graph, {"type": "math_v3", "name": "Math", "parameters": {"op": 0, "d_in2_x": 1.0, "d_in2_y": 2.0, "d_in2_z": 3.0}})
	graph.connect_children(random, 0, math, 0)
	connect_output(graph, math, "Material", "CUSTOM")
	connect_output(graph, math, "Process", "VELOCITY")
	await probe(graph, "all(lessThan(abs(CUSTOM - vec4(1.25, 2.25, 3.25, 1.0)), vec4(0.00001))) && all(lessThan(abs(VELOCITY - CUSTOM.xyz), vec3(0.00001)))", "unified_direct_math")
	var module = graph.create_subgraph([math])
	graph.create_subgraph([module])
	var restored = await mm_loader.create_gen(JSON.parse_string(JSON.stringify(graph.serialize())))
	add_child(restored)
	await probe(restored, "all(lessThan(abs(VELOCITY - vec3(1.25, 2.25, 3.25)), vec3(0.00001)))", "unified_nested")
	graph.queue_free()
	restored.queue_free()
	for type in ["f", "rgb", "rgba"]:
		graph = await make_graph()
		var expressions = {"f": "0.4", "rgb": "vec3(0.2, 0.4, 0.6)", "rgba": "vec4(0.2, 0.4, 0.6, 0.8)"}
		var color = await add(graph, {"type": "shader", "shader_model": {"name": "Numeric Source", "parameters": [], "inputs": [], "outputs": [{"type": type, type: expressions[type]}]}})
		connect_output(graph, color, "Process", "COLOR")
		connect_output(graph, color, "Process", "VELOCITY")
		connect_output(graph, color, "Process", "MASS")
		connect_output(graph, color, "Process", "USERDATA1")
		var expected: String = "vec4(0.4, 0.4, 0.4, 1.0)" if type == "f" else ("vec4(0.2, 0.4, 0.6, 1.0)" if type == "rgb" else expressions[type])
		await probe(graph, "abs(MASS - 0.4) < 0.00001 && all(lessThan(abs(USERDATA1 - " + expected + "), vec4(0.00001))) && all(lessThan(abs(VELOCITY - USERDATA1.xyz), vec3(0.00001)))", "unified_conversion_" + type)
		graph.queue_free()
	graph = await make_graph()
	var uv_source = await add(graph, {"type": "shader", "name": "UVSource", "shader_model": {"name": "UV Source", "parameters": [], "inputs": [], "outputs": [{"type": "rgb", "rgb": "vec3($uv, 0.5)"}]}})
	var multiply = await particle(graph, "Multiply", {"kind": "operator", "data_type": "vec3", "operation": "multiply", "inputs": {"b": {"value": [2.0, 2.0, 2.0]}}})
	math = await add(graph, {"type": "math_v3", "name": "Math", "parameters": {"op": 0, "d_in2_x": 1.0, "d_in2_y": 2.0, "d_in2_z": 3.0}})
	graph.connect_children(uv_source, 0, multiply, 0)
	graph.connect_children(multiply, 0, math, 0)
	var helper = await add(graph, {"type": "shader", "name": "LegacyHelper", "shader_model": {"name": "Legacy Helper", "parameters": [], "inputs": [{"name": "value", "type": "particle_vec3", "default": "vec3(0.0)", "function": true}], "outputs": [{"type": "particle_vec3", "particle_vec3": "$value($uv)"}]}})
	graph.connect_children(math, 0, helper, 0)
	for pair in [["Material", [0.2, 0.3]], ["Process", [0.6, 0.7]]]:
		var evaluate = await particle(graph, "Evaluate" + pair[0], {"kind": "evaluate", "function_type": "rgb"})
		var coordinates = await particle(graph, "Coordinates" + pair[0], {"kind": "constant", "data_type": "vec2", "value": pair[1]})
		graph.connect_children(helper, 0, evaluate, 0)
		graph.connect_children(coordinates, 0, evaluate, 1)
		connect_output(graph, evaluate, pair[0], "CUSTOM" if pair[0] == "Material" else "USERDATA1")
	await probe(graph, "all(lessThan(abs(CUSTOM - vec4(1.4, 2.6, 4.0, 1.0)), vec4(0.00001))) && all(lessThan(abs(USERDATA1 - vec4(2.2, 3.4, 4.0, 1.0)), vec4(0.00001)))", "unified_mixed_coordinates_legacy_function")
	var buffer = await add(graph, {"type": "buffer", "name": "RuntimeBuffer", "version": 2, "parameters": {"size": 4}})
	var state = await particle(graph, "Time", {"kind": "input", "builtin": "TIME"})
	graph.connect_children(state, 0, buffer, 0)
	connect_output(graph, buffer, "Process", "COLOR")
	check(str(graph.get_node("Material").compile_shader().errors).contains("cannot bake"), "Standard ports retain runtime bake rejection")
	for frame in 30: await get_tree().process_frame
	graph.queue_free()
	for alias in mm_io_types.TYPE_ALIASES:
		check(not mm_io_types.type_names.has(alias), "Legacy alias hidden in new type choices")
		var input_editor = load("res://material_maker/windows/node_editor/input.tscn").instantiate()
		add_child(input_editor)
		input_editor.set_model_data({"name": "value", "label": "Value", "type": alias, "default": "0.0"})
		check(input_editor.get_model_data().type == alias, "Legacy input survives editor roundtrip")
		input_editor.queue_free()
		var output_editor = load("res://material_maker/windows/node_editor/output.tscn").instantiate()
		add_child(output_editor)
		output_editor.set_model_data({"type": alias, alias: "$value($uv)"})
		var saved = output_editor.get_model_data()
		check(saved.type == alias and saved.get(alias) == "$value($uv)", "Legacy output expression survives editor roundtrip")
		output_editor.queue_free()
	for frame in 30: await get_tree().process_frame
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_UNIFIED: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
