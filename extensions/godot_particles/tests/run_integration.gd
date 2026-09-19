extends Node

const PACKAGE = "res://extensions/godot_particles/"
@onready var root: Window = get_tree().root
var assertions := 0
var failures: Array[String] = []
var retained_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	await get_tree().process_frame
	mm_loader.update_predefined_generators()
	DirAccess.make_dir_recursive_absolute("res://validation_outputs")
	for filename in ["examples/blank.ptex", "tests/shared_stages.ptex", "examples/gravity.ptex", "tests/state_inputs.ptex"]:
		var graph = await mm_loader.load_gen(PACKAGE + filename)
		check(graph != null, "Graph loads: " + filename)
		if graph == null:
			continue
		root.add_child(graph)
		var output = graph.get_node("output")
		var profile = output.get_export("Godot 4/Particles 3D")
		var shader_text: String = output.process_shader(profile.files[0].template, profile.custom, true).shader_code
		check(not "$" in shader_text, "All substitutions resolved: " + filename)
		check(shader_text.count("void mm_evaluate(") == 1, "Single evaluation body")
		check(shader_text.count("mm_evaluate(") == 3, "Both stages call the evaluation body")
		check(not "= mm_particle_life_fraction()" in shader_text, "State reads exported")
		var basename: String = filename.get_file().get_basename()
		var prefix: String = "res://validation_outputs/" + basename
		await output.export_material(prefix, "Godot 4/Particles 3D", 16, true)
		check(FileAccess.file_exists(prefix + ".gdshader"), "Shader exported")
		check(FileAccess.file_exists(prefix + ".tres"), "Material exported")
		var material = ResourceLoader.load(prefix + ".tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		check(material is ShaderMaterial, "Exported ShaderMaterial loads")
		if material is ShaderMaterial:
			retained_materials.append(material)
			check(normalize(material.shader.code) == normalize(shader_text), "Actual file matches generated shader")
		var saved_path: String = prefix + ".ptex"
		mm_loader.save_gen(saved_path, graph)
		var reloaded = await mm_loader.load_gen(saved_path)
		check(reloaded != null and reloaded.connections.size() == graph.connections.size(), "Round-trip connections")
		if reloaded != null:
			root.add_child(reloaded)
			var reloaded_output = reloaded.get_node("output")
			var reloaded_profile = reloaded_output.get_export("Godot 4/Particles 3D")
			var reloaded_code: String = reloaded_output.process_shader(reloaded_profile.files[0].template, reloaded_profile.custom, true).shader_code
			FileAccess.open(prefix + ".before.txt", FileAccess.WRITE).store_string(normalize(shader_text))
			FileAccess.open(prefix + ".after.txt", FileAccess.WRITE).store_string(normalize(reloaded_code))
			check(normalize(shader_text) == normalize(reloaded_code), "Round-trip shader behavior: " + filename)
			reloaded.queue_free()
		graph.queue_free()
		await get_tree().process_frame
	# Exercise the installed library's node names and every output preview.
	mm_loader.update_predefined_generators()
	var library_loader = load("res://material_maker/tools/library_manager/library.gd").new()
	check(library_loader.load_library(PACKAGE + "particles.json"), "Library imports through the app loader")
	library_loader.free()
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE + "particles.json"))
	for entry in library.lib:
		var node = await mm_loader.create_gen(entry)
		check(node != null, "Library node loads: " + entry.type)
		if node == null:
			continue
		var holder = MMGenGraph.new()
		root.add_child(holder)
		holder.add_generator(node)
		if node is MMGenShader and not node is MMGenMaterial:
			for index in node.get_output_defs().size():
				var source = node.get_shader_code("UV", index, MMGenContext.new())
				var preview_code: String = MMGenBase.generate_preview_shader(source, source.output_type)
				var preview_material = ShaderMaterial.new()
				preview_material.shader = Shader.new()
				preview_material.shader.code = preview_code
				preview_material.shader.get_shader_uniform_list()
				retained_materials.append(preview_material)
		holder.queue_free()
		await get_tree().process_frame
	for material_name in ["material", "material_dynamic_sky"]:
		var baseline = await mm_loader.create_gen({"type": material_name, "name": material_name})
		var holder = MMGenGraph.new()
		root.add_child(holder)
		holder.add_generator(baseline)
		var preview: String = baseline.process_shader(baseline.process_conditionals(baseline.shader_model.preview_shader)).shader_code
		check(not "$begin_generate" in preview, "Existing material generation: " + material_name)
		var shader = Shader.new()
		shader.code = preview
		shader.get_shader_uniform_list()
		holder.queue_free()
		await get_tree().process_frame
	await render_probe(retained_materials[1].shader.code, "initial_velocity / 4.0", Color(0.25, 0.5, 0.75))
	await render_probe(retained_materials[1].shader.code, "acceleration / 4.0", Color(0.25, 0.5, 0.75))
	await render_probe(retained_materials[2].shader.code, "particle_color.rgb", Color(0.525, 0.25, 0.525))
	await render_probe(retained_materials[2].shader.code, "vec3(particle_scale)", Color(0.175, 0.175, 0.175))
	await render_probe(retained_materials[3].shader.code, "initial_position", Color(0.2, 0.3, 0.4))
	await render_probe(retained_materials[3].shader.code, "initial_velocity", Color(0.3, 0.4, 0.5))
	await render_probe(retained_materials[3].shader.code, "acceleration", Color(1.0, 0.5, 0.016))
	await render_particles()
	var report = FileAccess.open("res://validation_outputs/report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "engine": Engine.get_version_info().string}, "  "))
	report.close()
	print("PARTICLE_INTEGRATION_RESULT: ", failures)
	retained_materials.clear()
	await mm_renderer.thread_run(func():
		mm_renderer.rendering_device.free()
		mm_renderer.rendering_device = null
	)
	await mm_renderer.stop_rendering_thread()
	mm_renderer.shader_error_handler.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func normalize(code: String) -> String:
	code = MMGenBase.remove_comments(code)
	var regex = RegEx.create_from_string("o[0-9]+")
	var identifiers: Dictionary = {}
	for match_result in regex.search_all(code):
		identifiers[match_result.get_string()] = true
	var index := 0
	for identifier in identifiers:
		code = code.replace(identifier, "NODE" + str(index))
		index += 1
	return RegEx.create_from_string("\\s+").sub(code, "", true)

func render_particles() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "GPU validation requires a real display/rendering driver")
		return
	var scene = Node3D.new()
	root.add_child(scene)
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(3, 1, 9)
	camera.look_at(Vector3(1, 1, 0))
	camera.current = true
	var draw_material = StandardMaterial3D.new()
	draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_material.vertex_color_use_as_albedo = true
	draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh = SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	mesh.material = draw_material
	for index in range(3):
		var particles = GPUParticles3D.new()
		particles.amount = 24
		particles.lifetime = 2.0
		particles.local_coords = true
		particles.fixed_fps = 60
		particles.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
		particles.draw_pass_1 = mesh
		particles.process_material = retained_materials[index]
		particles.position.x = float(index - 1) * 2.0
		scene.add_child(particles)
	for frame in range(180):
		await get_tree().process_frame
		if frame in [30, 90, 179]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://validation_outputs/frame_%03d.png" % frame)
	scene.queue_free()

func render_probe(particle_code: String, expression: String, expected: Color) -> void:
	var code: String = particle_code.get_slice("void start()", 0)
	code = code.replace("shader_type particles;", "shader_type canvas_item;").replace("render_mode disable_force;", "render_mode unshaded;")
	code += "void fragment() { vec3 initial_position; vec3 initial_velocity; vec3 acceleration; vec4 particle_color; float particle_scale; mm_evaluate(vec3(0.2, 0.3, 0.4), vec3(0.3, 0.4, 0.5), 1.0, 0.5, 0.016, initial_position, initial_velocity, acceleration, particle_color, particle_scale); COLOR = vec4(" + expression + ", 1.0); }"
	var viewport = SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect = ColorRect.new()
	rect.size = Vector2(8, 8)
	var material = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = code
	rect.material = material
	viewport.add_child(rect)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual: Color = viewport.get_texture().get_image().get_pixel(4, 4)
	check(abs(actual.r - expected.r) < 0.015 and abs(actual.g - expected.g) < 0.015 and abs(actual.b - expected.b) < 0.015,
		"GPU numeric probe " + expression + ": expected " + str(expected) + ", got " + str(actual))
	viewport.queue_free()
	await get_tree().process_frame
