extends "test_unified.gd"

func vector4(q: Quaternion) -> String:
	return "vec4(%.9f, %.9f, %.9f, %.9f)" % [q.x, q.y, q.z, q.w]

func run():
	var library = JSON.parse_string(FileAccess.get_file_as_string("res://addons/material_maker/particles/library.json"))
	var definitions := {}
	for item in library.lib:
		if item.tree_item in ["Filter/Math/Euler to Quaternion", "Filter/Math/Quaternion Multiply"]:
			definitions[item.tree_item.get_file()] = item
	check(definitions.size() == 2, "Quaternion math is available as ordinary library nodes")
	if definitions.size() != 2:
		print("PARTICLE_QUATERNION: " + str(failures))
		get_tree().quit(1)
		return
	for degrees in [Vector3.ZERO, Vector3(90, 0, 0), Vector3(0, 90, 0), Vector3(0, 0, 90), Vector3(25, -70, 130)]:
		for unit in 2:
			var graph = await make_graph()
			var data: Dictionary = definitions["Euler to Quaternion"].duplicate(true)
			data.parameters = {"unit": unit}
			var conversion = await add(graph, data)
			var angles: Vector3 = degrees if unit == 0 else degrees * PI / 180.0
			var source = await particle(graph, "Angles", {"kind": "constant", "data_type": "vec3", "value": [angles.x, angles.y, angles.z]})
			graph.connect_children(source, 0, conversion, 0)
			connect_output(graph, conversion, "Process", "CUSTOM")
			var q := Quaternion.from_euler(degrees * PI / 180.0)
			await probe(graph, "abs(abs(dot(CUSTOM, " + vector4(q) + ")) - 1.0) < 0.0001", "euler_" + str(unit) + str(degrees))
			graph.queue_free()
	for values in [[Quaternion.IDENTITY, Quaternion.IDENTITY], [Quaternion(Vector3.UP, 0.8), Quaternion(Vector3.RIGHT, 0.6)], [Quaternion(Vector3.RIGHT, 0.6), Quaternion(Vector3.UP, 0.8)], [Quaternion(0,0,0,0), Quaternion.IDENTITY], [Quaternion(0,0,0,-2), Quaternion(Vector3.UP, 0.8)]]:
		var graph = await make_graph()
		var multiply = await add(graph, definitions["Quaternion Multiply"].duplicate(true))
		for i in 2:
			var q: Quaternion = values[i]
			var source = await particle(graph, "Q" + str(i), {"kind": "constant", "data_type": "vec4", "value": [q.x, q.y, q.z, q.w]})
			graph.connect_children(source, 0, multiply, i)
		var a: Quaternion = values[0].normalized() if values[0].length() > 0.000001 else Quaternion.IDENTITY
		var b: Quaternion = values[1].normalized() if values[1].length() > 0.000001 else Quaternion.IDENTITY
		connect_output(graph, multiply, "Process", "CUSTOM")
		var module = graph.create_subgraph([multiply])
		graph.create_subgraph([module])
		var restored = await mm_loader.create_gen(JSON.parse_string(JSON.stringify(graph.serialize())))
		add_child(restored)
		await probe(restored, "abs(abs(dot(CUSTOM, " + vector4(a*b) + ")) - 1.0) < 0.0001", "multiply_" + str(values))
		graph.queue_free()
		restored.queue_free()
	print("PARTICLE_QUATERNION: passed" if failures.is_empty() else "PARTICLE_QUATERNION: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
