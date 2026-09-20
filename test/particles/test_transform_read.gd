extends "test_quaternion.gd"

func run():
	var library = JSON.parse_string(FileAccess.get_file_as_string("res://addons/material_maker/particles/library.json"))
	var readers := {}
	for item in library.lib:
		if item.tree_item in ["Particles/Read/Position", "Particles/Read/Rotation", "Particles/Read/Scale"]:
			readers[item.tree_item.get_file()] = item
	check(readers.size() == 3, "Transform component readers are available")
	if readers.size() == 3:
		for transform_case in [[Vector3(0.3, 0.7, -0.5), Vector3.ONE], [Vector3(0.3, 0.7, -0.5), Vector3(2, 3, 4)], [Vector3(0.3, 0.7, -0.5), Vector3(-2, 3, 4)], [Vector3(0.3, 0.7, -0.5), Vector3(0, 2, 3)], [Vector3(PI,0,0), Vector3.ONE], [Vector3(0,PI,0), Vector3.ONE], [Vector3(0,0,PI), Vector3.ONE]]:
			var scale_value: Vector3 = transform_case[1]
			var graph = await make_graph()
			var q := Quaternion.from_euler(transform_case[0])
			var basis := Basis(q).scaled_local(scale_value)
			var columns: Array = []
			for column in [basis.x, basis.y, basis.z]: columns.append([column.x, column.y, column.z, 0])
			columns.append([0.1, 0.2, 0.3, 1])
			graph.get_node("Material").particle_defaults.TRANSFORM = {"value": columns}
			for pair in [["Position", "CUSTOM"], ["Rotation", "USERDATA1"], ["Scale", "USERDATA2"]]:
				var reader = await add(graph, readers[pair[0]].duplicate(true))
				connect_output(graph, reader, "Process", pair[1])
			var expected_scale: Vector3 = basis.get_scale()
			var expected_rotation: Quaternion = basis.get_rotation_quaternion() if abs(basis.determinant()) > 0.000001 else Quaternion.IDENTITY
			var assertion := "distance(CUSTOM.xyz, vec3(0.1, 0.2, 0.3)) < 0.0001 && abs(abs(dot(USERDATA1, %s)) - 1.0) < 0.0001 && distance(USERDATA2.xyz, vec3(%.9f, %.9f, %.9f)) < 0.0001" % [vector4(expected_rotation), expected_scale.x, expected_scale.y, expected_scale.z]
			# Zero determinant still retains the nonzero column lengths.
			if scale_value.x == 0:
				assertion = "abs(USERDATA1.w - 1.0) < 0.0001 && distance(USERDATA2.xyz, vec3(0.0, 2.0, 3.0)) < 0.0001"
			var result = graph.get_node("Material").compile_shader()
			check(result.errors.is_empty(), "Compile component reads: " + str(result.errors))
			result.code = result.code.replace("void process() {", "void process() {\nTRANSFORM = " + Compiler.new().literal("mat4", columns, "") + ";")
			result.code = result.code.insert(result.code.rfind("}"), "COLOR = (" + assertion + ") ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0); TRANSFORM = mat4(1.0); VELOCITY = vec3(0.0);\n")
			await render_probe({}, false, "read_components_" + str(scale_value), false, result)
			graph.queue_free()
	print("PARTICLE_TRANSFORM_READ: passed" if failures.is_empty() else "PARTICLE_TRANSFORM_READ: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
