extends "test_unified.gd"

func choices(node, key: String) -> Array:
	return node.get_parameter_def(key).values.map(func(v): return v.value)

func run():
	var graph = await make_graph()
	var legacy = await particle(graph, "Legacy", {"kind": "operator", "data_type": "vec3", "operation": "cross"})
	legacy.set_parameter("data_type", MMGenParticle.Interface.TYPES.find("vec3"))
	legacy.set_parameter("operation", MMGenParticle.Interface.OPERATIONS.find("cross"))
	var restored = await add(graph, JSON.parse_string(JSON.stringify(legacy.serialize())))
	check(restored.model_data().data_type == "vec3" and restored.model_data().operation == "cross", "Legacy enum indices survive roundtrip")
	var constant = await particle(graph, "TypedConstant", {"kind": "constant", "data_type": "vec2", "editor_profile": "supplemental_v1"})
	check(not choices(constant, "data_type").has("float") and not choices(constant, "data_type").has("vec3") and not choices(constant, "data_type").has("vec4"), "New constants exclude stock numeric values")
	check(not choices(constant, "data_type").has("sampler2D"), "A sampler is not a literal constant")
	constant.set_parameter("data_type", choices(constant, "data_type").find("bvec3"))
	constant.set_parameter("v0", true)
	restored = await add(graph, JSON.parse_string(JSON.stringify(constant.serialize())))
	check(restored.model_data().data_type == "bvec3" and restored.model_data().value == [true, false, false], "Supplemental bool vector survives roundtrip")
	for kind in ["compose", "split"]:
		var node = await particle(graph, kind, {"kind": kind, "data_type": "vec2", "editor_profile": "supplemental_v1"})
		check(not choices(node, "data_type").has("vec3") and not choices(node, "data_type").has("vec4"), kind + " excludes stock Combine/Decompose types")
	var math = await particle(graph, "TypedMath", {"kind": "operator", "data_type": "int", "editor_profile": "supplemental_v1"})
	check(not choices(math, "data_type").has("float") and not choices(math, "data_type").has("vec3"), "Typed Math excludes stock math")
	math.set_parameter("operation", choices(math, "operation").find("bit_or"))
	restored = await add(graph, JSON.parse_string(JSON.stringify(math.serialize())))
	check(restored.model_data().operation == "bit_or" and restored.model_data().data_type == "int", "Typed operation survives roundtrip")
	var compare = await particle(graph, "Compare", {"kind": "operator", "data_type": "float", "operation": "less", "editor_profile": "compare_v1"})
	check(choices(compare, "operation") == ["equal", "less", "greater"], "Compare exposes scalar comparisons")
	compare.set_parameter("data_type", choices(compare, "data_type").find("vec3"))
	check(choices(compare, "operation") == ["equal"] and compare.model_data().operation == "equal", "Vector Compare only exposes whole-vector equality")
	var bridge = await particle(graph, "Function", {"kind": "bridge", "function_type": "sdf3d", "editor_profile": "supplemental_v1"})
	check(not choices(bridge, "function_type").has("f") and not choices(bridge, "function_type").has("rgb") and not choices(bridge, "function_type").has("rgba"), "Numeric values do not need a function adapter")
	graph.queue_free()
	for frame in 5: await get_tree().process_frame
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_PROFILES: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
