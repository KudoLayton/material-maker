extends "test_quaternion.gd"

func run():
	var graph = await make_graph()
	for target in [graph.get_node("Material"), graph.get_node("Process")]:
		check(target.model_data().get("transform_mode", 1) == 1, "Legacy output stays Matrix")
		target.set_parameter("transform_mode", 0)
		check(target.get_input_defs().any(func(p): return p.name == "position"), "Components expose Position")
		check(target.get_input_defs().any(func(p): return p.name == "rotation" and p.type == "rgba"), "Rotation uses RGBA")
	var restored = await mm_loader.create_gen(JSON.parse_string(JSON.stringify(graph.serialize())))
	add_child(restored)
	check(restored.get_node("Material").model_data().transform_mode == 0 and restored.get_node("Process").model_data().transform_mode == 0, "JSON numeric modes survive loading")
	restored.queue_free()
	graph.get_node("Material").particle_defaults.position = {"value": [1, 2, 3]}
	graph.get_node("Material").set_parameter("transform_mode", 1)
	check(graph.get_node("Material").model_data().transform_mode == 0, "Explicit component default blocks mode change")
	graph.queue_free()
	if failures.is_empty():
		for stage_name in ["Material", "Process"]:
			for mask in 8:
				graph = await make_graph()
				var target = graph.get_node(stage_name)
				target.set_parameter("transform_mode", 0)
				var old_q := Quaternion.from_euler(Vector3(0.2, 0.4, 0.1))
				var new_q := Quaternion.from_euler(Vector3(-0.3, 0.7, 0.5))
				var new_scale := Vector3(0, -1.5, 2.5) if mask == 7 else Vector3(0.5, 1.5, 2.5)
				var old_basis := Basis(old_q).scaled_local(Vector3(2, 3, 4))
				var expected := Basis(new_q if mask & 2 else old_q).scaled_local(new_scale if mask & 4 else Vector3(2, 3, 4))
				for data in [[1, "position", "vec3", [0.4, 0.3, 0.2]], [2, "rotation", "vec4", [new_q.x*2, new_q.y*2, new_q.z*2, new_q.w*2]], [4, "scale", "vec3", [new_scale.x, new_scale.y, new_scale.z]]]:
					if mask & data[0]:
						var source = await particle(graph, data[1], {"kind": "constant", "data_type": data[2], "value": data[3]})
						connect_output(graph, source, stage_name, data[1])
				var result = graph.get_node("Material").compile_shader()
				check(result.errors.is_empty(), "Compile components: " + str(result.errors))
				var initial := "TRANSFORM = mat4(%s, %s, %s, vec4(0.1, 0.2, 0.3, 1.0));" % [column(old_basis.x), column(old_basis.y), column(old_basis.z)]
				var stage := "start" if stage_name == "Material" else "process"
				if stage == "start":
					graph.get_node("Material").set_parameter("initialize_particle", false)
					result = graph.get_node("Material").compile_shader()
				result.code = result.code.replace("void " + stage + "() {", "void " + stage + "() {\n" + initial)
				var assertions: Array[String] = []
				for i in 3: assertions.append("distance(TRANSFORM[%d], %s) < 0.0001" % [i, column(expected[i])])
				assertions.append("distance(TRANSFORM[3].xyz, %s) < 0.0001" % ("vec3(0.4, 0.3, 0.2)" if mask & 1 else "vec3(0.1, 0.2, 0.3)"))
				var condition := " && ".join(assertions)
				if stage == "start":
					var end: int = result.code.rfind("}", result.code.find("void process()"))
					result.code = result.code.insert(end, "USERDATA6.x = (" + condition + ") ? 1.0 : 0.0;\n")
					condition = "USERDATA6.x == 1.0"
				result.code = result.code.insert(result.code.rfind("}"), "COLOR = (" + condition + ") ? vec4(0,1,0,1) : vec4(1,0,0,1); TRANSFORM = mat4(1.0); VELOCITY = vec3(0.0);\n")
				await render_probe({}, false, "output_" + stage + str(mask), false, result)
				graph.queue_free()
	print("PARTICLE_TRANSFORM_OUTPUT: passed" if failures.is_empty() else "PARTICLE_TRANSFORM_OUTPUT: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func column(v: Vector3) -> String:
	return "vec4(%.9f, %.9f, %.9f, 0.0)" % [v.x, v.y, v.z]
