extends "test_unified.gd"

func run():
	var graph = await make_graph()
	var material = graph.get_node("Material")
	var result = material.compile_shader()
	check(result.errors.is_empty(), "Compile legacy graph")
	var start: String = result.code.split("void start() {")[1].split("void process() {")[0]
	for flag in ["POSITION", "ROT_SCALE", "VELOCITY", "COLOR", "CUSTOM"]:
		check(start.contains("if (RESTART_" + flag + ")"), "Default restart guard: " + flag)
	check(start.find("TRANSFORM[3] = EMISSION_TRANSFORM[3]") >= 0, "Reset position to emitter")
	check(start.find("if (RESTART_POSITION)") < start.find("_mm_state.TRANSFORM = TRANSFORM"), "Initialize before state snapshot")
	check(not result.code.split("void process() {")[1].contains("if (RESTART_"), "Process never initializes")
	check(not result.code.contains("uniform bool initialize_particle"), "Policy is not a uniform")
	material.set_parameter("initialize_particle", false)
	check(not material.compile_shader().code.contains("if (RESTART_"), "Explicit opt out")
	var restored = await mm_loader.create_gen(JSON.parse_string(JSON.stringify(graph.serialize())))
	add_child(restored)
	check(not restored.get_node("Material").compile_shader().code.contains("if (RESTART_"), "Opt out survives serialization")
	restored.queue_free()
	material.set_parameter("initialize_particle", true)
	material.set_parameter("keep_data", true)
	check(not material.compile_shader().code.contains("if (RESTART_"), "keep_data disables initialization")
	material.set_parameter("keep_data", false)
	if not failures.is_empty():
		print("PARTICLE_DEFAULTS: " + str(failures))
		get_tree().quit(1)
		return
	await start_probe(graph, "COLOR == vec4(1.0) && CUSTOM == vec4(0.0) && VELOCITY == vec3(0.0) && MASS == 1.0", "default_state")
	for mask in 32:
		var conditions: Array[String] = []
		conditions.append("TRANSFORM[3] == " + ("EMISSION_TRANSFORM[3]" if mask & 1 else "vec4(3.0, 4.0, 5.0, 1.0)"))
		for column in 3:
			conditions.append("TRANSFORM[%d] == " % column + ("EMISSION_TRANSFORM[%d]" % column if mask & 2 else "mat4(2.0)[%d]" % column))
		conditions.append("VELOCITY == vec3(%s)" % ("0.0" if mask & 4 else "7.0"))
		conditions.append("COLOR == vec4(%s)" % ("1.0" if mask & 8 else "0.25"))
		conditions.append("CUSTOM == vec4(%s)" % ("0.0" if mask & 16 else "0.75"))
		await start_probe(graph, " && ".join(conditions), "restart_flags_%d" % mask, mask)
	material.particle_defaults.CUSTOM = {"value": [0.25, 0.5, 0.75, 1.0]}
	await start_probe(graph, "CUSTOM == vec4(0.25, 0.5, 0.75, 1.0)", "explicit_output_wins")
	var color = await particle(graph, "InitialColor", {"kind": "input", "builtin": "COLOR"})
	connect_output(graph, color, "Material", "CUSTOM")
	var coordinates = await add(graph, {"type": "shader", "name": "InitialCoordinates", "shader_model": {"name": "Initial Coordinates", "parameters": [], "inputs": [{"name": "color", "type": "rgba", "default": "vec4(0.0)"}], "outputs": [{"type": "particle_vec2", "particle_vec2": "$color($uv).xy"}]}})
	graph.connect_children(color, 0, coordinates, 0)
	connect_output(graph, coordinates, "Material", "sampling_uv")
	var sampled = await add(graph, {"type": "shader", "name": "UV", "shader_model": {"name": "UV", "parameters": [], "inputs": [], "outputs": [{"type": "rgb", "rgb": "vec3($uv, 0.0)"}]}})
	connect_output(graph, sampled, "Material", "USERDATA1")
	await start_probe(graph, "CUSTOM == vec4(1.0) && USERDATA1.xy == vec2(1.0)", "read_and_sampling_use_initialized_state")
	await motion_probe(graph)
	graph.queue_free()
	print("PARTICLE_DEFAULTS: passed" if failures.is_empty() else "PARTICLE_DEFAULTS: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func start_probe(graph, assertion: String, name: String, mask: int = -1):
	var result = graph.get_node("Material").compile_shader()
	if mask >= 0:
		var flags = ["POSITION", "ROT_SCALE", "VELOCITY", "COLOR", "CUSTOM"]
		for index in flags.size():
			result.code = result.code.replace("if (RESTART_" + flags[index] + ")", "if (" + ("true" if mask & (1 << index) else "false") + ")")
		result.code = result.code.replace("void start() {", "void start() {\nTRANSFORM = mat4(2.0); TRANSFORM[3] = vec4(3.0, 4.0, 5.0, 1.0); VELOCITY = vec3(7.0); COLOR = vec4(0.25); CUSTOM = vec4(0.75);")
	var process_index: int = result.code.find("void process() {")
	var start_end: int = result.code.rfind("}", process_index)
	result.code = result.code.insert(start_end, "USERDATA6 = vec4((" + assertion + ") ? 1.0 : 0.0);\n")
	result.code = result.code.insert(result.code.rfind("}"), "TRANSFORM = mat4(1.0); VELOCITY = vec3(0.0); COLOR = USERDATA6.x == 1.0 ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);\n")
	await render_probe({}, false, name, false, result)

func motion_probe(graph):
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(20, 10, 40)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100
	graph.get_node("Material").particle_defaults.VELOCITY = {"value": [1.0, 1.0, 1.0]}
	var shader := Shader.new()
	shader.code = graph.get_node("Material").compile_shader().code
	var cases: Array[GPUParticles3D] = []
	for local in [false, true]:
		for transformed in [false, true]:
			var particles := GPUParticles3D.new()
			particles.amount = 1
			particles.lifetime = 0.25
			particles.fixed_fps = 60
			particles.local_coords = local
			particles.visibility_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
			particles.draw_pass_1 = QuadMesh.new()
			var material := ShaderMaterial.new()
			material.shader = shader
			particles.process_material = material
			viewport.add_child(particles)
			particles.position = Vector3(20, 10, 5)
			if transformed:
				particles.rotation = Vector3(0.3, 0.5, 0.7)
				particles.scale = Vector3(2.0, 0.5, 1.5)
			particles.restart()
			cases.append(particles)
	for frame in 120:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if frame > 15:
			for particles in cases:
				var bounds := particles.capture_aabb()
				check(bounds.size.length() > 0.0 and bounds.get_center().length() < 2.0, "Repeated spawn remains near emitter, local=" + str(particles.local_coords))
	viewport.queue_free()
