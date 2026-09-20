extends "test_unified.gd"

func inspect_example(data: Dictionary, name: String) -> void:
	for node in data.get("nodes", []):
		if node.get("type") == "particle_node":
			var settings: Dictionary = node.settings
			if settings.kind in ["constant", "operator", "select", "evaluate"]:
				check(settings.get("editor_profile") == "supplemental_v1", name + ": new examples use supplemental choices")
			check(not (settings.kind == "constant" and settings.get("data_type") in ["float", "vec3", "vec4"]), name + ": ordinary fixed values use stock nodes")
		if node.has("nodes"): inspect_example(node, name)

func run():
	DirAccess.make_dir_recursive_absolute("res://exported/published")
	for name in ["blank", "gravity", "collision", "subparticle", "library_module", "library_gravity"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://material_maker/examples/particles/" + name + ".ptex"))
		inspect_example(data, name)
		if name in ["gravity", "collision", "library_gravity"]:
			check(data.nodes.any(func(n): return n.get("settings", {}).get("kind") == "uniform"), name + ": Typed Parameter exposes effect parameters")
		if not failures.is_empty(): continue
		var graph = await mm_loader.create_gen(data)
		add_child(graph)
		var result = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, "res://exported/published/" + name)
		check(result.errors.is_empty(), name + ": " + str(result.errors))
		check(load("res://exported/published/" + name + ".tres") is ShaderMaterial, name + ": exported material loads")
		if name == "gravity":
			await probe(graph, "abs(VELOCITY.y - (5.0 - 9.8 * DELTA)) < 0.0001", "stock_gravity", "TRANSFORM = mat4(1.0); VELOCITY = vec3(0.0, 5.0, 0.0);")
			for node in graph.get_children():
				if node is MMGenParticle and node.settings.kind == "uniform":
					if node.uniform_definition().name == "launch_speed": node.set_parameter("default_json", "8.0")
					if node.uniform_definition().name == "gravity": node.set_parameter("default_json", "[0.0, -4.0, 0.0]")
			await probe(graph, "abs(VELOCITY.y - (8.0 - 4.0 * DELTA)) < 0.0001", "parameter_gravity", "TRANSFORM = mat4(1.0); VELOCITY = vec3(0.0, 8.0, 0.0);")
		graph.queue_free()
	for frame in 5: await get_tree().process_frame
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_EXAMPLES: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
