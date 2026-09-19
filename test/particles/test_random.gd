extends "test_runtime.gd"

func make_graph(type: String, values: Array, minimum: float = 0.0, maximum: float = 1.0):
	var inputs := {}
	if not values.is_empty():
		for i in 3: inputs[["particle_id", "system_seed", "seed"][i]] = {"value": values[i]}
	var packed: String = {"float": "vec4($value($uv), 0.0, 0.0, 1.0)", "vec2": "vec4($value($uv), 0.0, 1.0)", "vec3": "vec4($value($uv), 1.0)", "vec4": "$value($uv)"}[type]
	var graph = await mm_loader.create_gen({"nodes": [
		{"type": "particle_export", "name": "Material"},
		{"type": "particle_node", "name": "Process", "settings": {"kind": "output", "stage": "process"}},
		{"type": "particle_node", "name": "Random", "settings": {"kind": "random", "data_type": type, "inputs": inputs}, "parameters": {"minimum": minimum, "maximum": maximum}},
		{"type": "shader", "name": "Pack", "shader_model": {"name": "Pack", "parameters": [], "inputs": [{"name": "value", "type": "particle_" + type, "default": type + "(0.0)"}], "outputs": [{"type": "particle_vec4", "particle_vec4": packed}]}}
	], "connections": [
		{"from": "Random", "from_port": 0, "to": "Pack", "to_port": 0},
		{"from": "Pack", "from_port": 0, "to": "Material", "to_port": 5},
		{"from": "Pack", "from_port": 0, "to": "Process", "to_port": 6}
	]})
	add_child(graph)
	return graph

func probe(graph: MMGenGraph, expected: Array, name: String) -> void:
	var result = graph.get_node("Material").compile_shader()
	check(result.errors.is_empty(), name + " compile " + str(result.errors))
	if not result.errors.is_empty(): return
	var expected_code: Array[String] = []
	for value in expected: expected_code.append("%.9f" % value)
	var assertion := "COLOR = (all(lessThan(abs(CUSTOM - vec4(%s)), vec4(0.000002))) && all(lessThan(abs(CUSTOM - USERDATA1), vec4(0.000002)))) ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);" % ", ".join(expected_code)
	result.code = result.code.insert(result.code.rfind("}"), assertion + "\n")
	await render_probe({}, false, name, false, result)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://exported")
	var cases = [
		[[0, 0, 0], [35365, 49751, 65207, 45330]],
		[[42, 777, 0], [28413, 50712, 22748, 59265]],
		[[42, 777, 1], [10182, 21743, 13461, 23283]],
		[[43, 777, 0], [10182, 21743, 13461, 23283]],
		[[4294967295, 0, 0], [46951, 57647, 64001, 31864]],
		[[42, 778, 0], [10182, 21743, 13461, 23283]],
		[[4294967295, 4294967295, 4294967295], [45400, 9337, 45482, 16380]]]
	for i in cases.size():
		var graph = await make_graph("vec4", cases[i][0])
		var expected: Array = cases[i][1].map(func(x): return x / 65535.0)
		await probe(graph, expected, "random_reference_%d" % i)
		graph.queue_free()
	for type in ["float", "vec2", "vec3", "vec4"]:
		var graph = await make_graph(type, [42, 777, 0], -2.0, 3.0)
		var count := 1 if type == "float" else int(type.right(1))
		var expected: Array = [0.0, 0.0, 0.0, 1.0]
		for i in count: expected[i] = -2.0 + 5.0 * cases[1][1][i] / 65535.0
		await probe(graph, expected, "random_range_" + type)
		graph.queue_free()
	var connected = await make_graph("vec4", [42, 777, 0], -99.0, 99.0)
	for bound in [["minimum", [-2.0, 0.0, 1.0, 4.0], 3], ["maximum", [3.0, 2.0, 1.0, 6.0], 4]]:
		var constant = await mm_loader.create_gen({"type": "particle_node", "settings": {"kind": "constant", "data_type": "vec4", "value": bound[1]}})
		connected.add_generator(constant)
		connected.connect_children(constant, 0, connected.get_node("Random"), bound[2])
	await probe(connected, [-2.0 + 5.0 * 28413 / 65535.0, 2.0 * 50712 / 65535.0, 1.0, 4.0 + 2.0 * 59265 / 65535.0], "random_connected_bounds")
	connected.queue_free()
	var graph = await make_graph("vec4", [], 0.25, 0.25)
	var initial = graph.get_node("Material").compile_shader()
	check(initial.code.contains("mm_particle_random(_mm_state.NUMBER, _mm_state.RANDOM_SEED, 0u)"), "Default particle identity and system seed")
	await probe(graph, [0.25, 0.25, 0.25, 0.25], "random_constant_range")
	var random = graph.get_node("Random")
	check(not preload("res://addons/material_maker/particles/dependencies.gd").runtime_source(random).is_empty(), "Random is runtime-dependent")
	random.set_parameter("minimum", 0.0)
	random.set_parameter("maximum", 1.0)
	random.settings.inputs = {"particle_id": {"value": 42}, "system_seed": {"value": 777}}
	random.set_parameter("seed", 1)
	var module = graph.create_subgraph([random])
	var nested = graph.create_subgraph([module])
	await probe(graph, cases[2][1].map(func(x): return x / 65535.0), "random_nested")
	var lib = load("res://material_maker/tools/library_manager/library.gd").new()
	lib.create_library("res://app_random_library.json", "Random module test")
	lib.add_item("Modules/Random", null, nested.serialize())
	lib.load_library("res://app_random_library.json")
	var reused = await mm_loader.create_gen(lib.get_item("Modules/Random").item)
	graph.add_generator(reused)
	graph.connect_children(reused, 0, graph.get_node("Pack"), 0)
	lib.free()
	await probe(graph, cases[2][1].map(func(x): return x / 65535.0), "random_library")
	var restored = await mm_loader.create_gen(JSON.parse_string(JSON.stringify(graph.serialize())))
	add_child(restored)
	await probe(restored, cases[2][1].map(func(x): return x / 65535.0), "random_roundtrip")
	var exported = await preload("res://addons/material_maker/particles/graph_exporter.gd").export_graph(restored, "res://exported/random")
	check(exported.errors.is_empty(), "Random material export")
	check(load("res://exported/random.tres") is ShaderMaterial, "Random material reload")
	graph.queue_free()
	restored.queue_free()
	var compiler = preload("res://addons/material_maker/particles/graph_compiler.gd").new()
	compiler.validate_node({"id": "invalid_random", "kind": "random", "data_type": "int"})
	check(not compiler.errors.is_empty(), "Unsupported Random type rejected")
	print("PARTICLE_RANDOM: GPU reference vectors, ranges, stages, subgraphs, library and export; failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
