extends "test_unified.gd"

func run():
	DirAccess.make_dir_recursive_absolute("res://exported")
	var graph = await make_graph()
	var remote = await add(graph, {"type": "remote", "name": "Controls", "parameters": {"speed": 10.0}, "widgets": [{"name": "speed", "label": "Speed", "type": "named_parameter", "min": -20.0, "max": 20.0, "step": 0.1, "default": 10.0}]})
	var value = await add(graph, {"type": "uniform_greyscale", "name": "Value", "parameters": {"color": "$speed * 2.0"}})
	var math = await add(graph, {"type": "math_v3", "name": "Math", "parameters": {"op": 2, "d_in2_x": -1.0, "d_in2_y": 2.0, "d_in2_z": 3.0}})
	graph.connect_children(value, 0, math, 0)
	connect_output(graph, math, "Material", "VELOCITY")
	connect_output(graph, value, "Process", "MASS")
	for speed in [10.0, 4.0]:
		remote.set_parameter("speed", speed)
		var result = await preload("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, "res://exported/internal")
		check(result.errors.is_empty(), "Internal graph exports: " + str(result.errors))
		check(result.get("material_parameters", {}).is_empty(), "Internal controls are absent from material parameters")
		var shader := Shader.new()
		shader.code = result.code
		check(shader.get_shader_uniform_list().is_empty(), "Internal controls are absent from Inspector")
		await probe(graph, "abs(MASS - %s) < 0.0001" % (speed * 2.0), "internal_remote_" + str(speed), "TRANSFORM = mat4(1.0); VELOCITY = vec3(0.0);")
	graph.queue_free()
	for frame in 5: await get_tree().process_frame
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_INTERNAL: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
