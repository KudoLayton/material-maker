extends "test_unified.gd"

func run():
	var library = load("res://material_maker/tools/library_manager/library.gd").new()
	library.load_library("res://addons/material_maker/particles/library.json")
	var expected := {
		"Simple/Constant/Typed": "Typed Constant", "Filter/Math/Typed": "Typed Math",
		"Filter/Math/Compare": "Compare", "Filter/Combine/Typed": "Typed Combine",
		"Filter/Decompose/Typed": "Typed Decompose", "Filter/Math/Type Cast": "Type Cast",
		"Filter/Math/Matrix Transform": "Matrix Transform", "Filter/Math/Select": "Select",
		"Miscellaneous/Typed Uniform": "Typed Uniform", "Miscellaneous/Array Element": "Array Element",
		"Miscellaneous/Texture Sample": "Texture Sample", "Miscellaneous/Evaluate Function": "Evaluate Function",
		"Miscellaneous/Value to Function": "Value to Function", "Particles/Execution/Start Entry": "Start Entry",
		"Particles/Execution/Process Entry": "Process Entry", "Particles/Random": "Particle Random",
		"Particles/Execution/Emit": "Emit Subparticle"}
	for path in expected:
		var item = library.get_item(path)
		check(item != null, "Library contains " + path)
		if item != null:
			var node = await mm_loader.create_gen(item.item)
			check(node.get_type_name() == expected[path], "Title for " + path)
			node.free()
	for path in ["Particles/Tools/Custom Shader", "Particles/Tools/Constant", "Particles/Tools/Operator", "Particles/Library/Value to Function"]:
		check(library.get_item(path) == null, "Duplicate library entry removed: " + path)
	library.free()
	if failures.is_empty():
		var graph = await make_graph()
		var combine = await add(graph, {"type": "combine", "name": "Combine"})
		for i in 4:
			var value = await add(graph, {"type": "uniform_greyscale", "name": "Component" + str(i), "parameters": {"color": [-1.0, 2.0, 3.0, 0.25][i]}})
			graph.connect_children(value, 0, combine, i)
		var decompose = await add(graph, {"type": "decompose", "name": "Decompose"})
		graph.connect_children(combine, 0, decompose, 0)
		var math = await add(graph, {"type": "math_v3", "name": "Math", "parameters": {"op": 0, "d_in2_x": 1.0, "d_in2_y": 1.0, "d_in2_z": 1.0}})
		graph.connect_children(combine, 0, math, 0)
		connect_output(graph, combine, "Process", "CUSTOM")
		connect_output(graph, decompose, "Process", "MASS")
		connect_output(graph, math, "Process", "VELOCITY")
		await probe(graph, "all(lessThan(abs(CUSTOM - vec4(-1.0, 2.0, 3.0, 0.25)), vec4(0.00001))) && abs(MASS + 1.0) < 0.00001 && all(lessThan(abs(VELOCITY - vec3(0.0, 3.0, 4.0)), vec3(0.00001)))", "stock_workflow")
		graph.queue_free()
		graph = await make_graph()
		var source = await add(graph, {"type": "shader", "shader_model": {"name": "Color", "parameters": [], "inputs": [], "outputs": [{"type": "rgba", "rgba": "vec4(2.0, 4.0, 9.0, 0.25)"}]}})
		var cast = await particle(graph, "Cast", {"kind": "convert", "source_type": "vec4", "data_type": "float", "editor_profile": "supplemental_v1"})
		graph.connect_children(source, 0, cast, 0)
		connect_output(graph, source, "Process", "MASS")
		connect_output(graph, cast, "Process", "CUSTOM")
		var compare = await particle(graph, "Compare", {"kind": "operator", "operation": "less", "data_type": "float", "editor_profile": "compare_v1", "inputs": {"b": {"value": 3.0}}})
		graph.connect_children(cast, 0, compare, 0)
		connect_output(graph, compare, "Process", "ACTIVE")
		await probe(graph, "abs(MASS - 5.0) < 0.00001 && all(lessThan(abs(CUSTOM - vec4(2.0, 2.0, 2.0, 1.0)), vec4(0.00001)))", "cast_and_compare")
		graph.queue_free()
		await check_supplemental_operations()
	for frame in 5: await get_tree().process_frame
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_WORKFLOW: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func check_supplemental_operations():
	var count := 0
	for profile in ["supplemental_v1", "compare_v1"]:
		var types: Array = MMGenParticle.EditorProfile.MATH_TYPES if profile == "supplemental_v1" else MMGenParticle.EditorProfile.COMPARE_TYPES
		for type in types:
			var operations: Array = MMGenParticle.EditorProfile.options(profile, "operator", "operation", type, [])
			for operation in operations:
				var graph = await make_graph()
				var settings := {"kind": "operator", "data_type": type, "operation": operation, "editor_profile": profile, "inputs": {}}
				for port in MMGenParticle.Interface.ports(settings, "process").inputs:
					var value = MMGenParticle.Interface.default_value(port.type)
					if value is Array and not port.type.begins_with("mat"):
						value.fill(true if port.type.begins_with("bvec") else 1)
					elif not value is Array: value = true if port.type == "bool" else 1
					settings.inputs[port.name] = {"value": value}
				var math = await particle(graph, "Math", settings)
				var output_type: String = math.particle_ports().outputs[0].type
				var expression := "$value($uv)"
				if output_type.begins_with("mat"): expression += "[0][0]"
				elif "vec" in output_type: expression += "[0]"
				var consumer = await add(graph, {"type": "shader", "shader_model": {"name": "Consume", "parameters": [], "inputs": [{"name": "value", "type": MMGenParticle.value_type(output_type)}], "outputs": [{"type": "f", "f": "float(" + expression + ")"}]}})
				graph.connect_children(math, 0, consumer, 0)
				connect_output(graph, consumer, "Process", "MASS")
				var result = Exporter.validate(graph.get_node("Material").compile_shader())
				check(result.errors.is_empty(), type + "/" + operation + ": " + str(result.errors))
				count += 1
				graph.queue_free()
				await get_tree().process_frame
	print("PARTICLE_SUPPLEMENTAL_GPU: %d combinations" % count)
