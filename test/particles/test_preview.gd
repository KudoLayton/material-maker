extends "test_unified.gd"

func settle(frames: int = 30):
	for frame in frames: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func run():
	var graph = await make_graph()
	var output = graph.get_node("Material")
	output.particle_defaults.VELOCITY = {"value": [1.0, 0.0, 0.0]}
	var preview := Control.new()
	add_child(preview)
	var viewport := SubViewport.new()
	viewport.name = "MaterialPreview"
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	var scene := Node3D.new()
	scene.name = "Preview3d"
	viewport.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position.z = 5.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	var runtime = load("res://material_maker/panels/preview_3d/particle_preview.gd").new()
	runtime.preview = preview
	preview.add_child(runtime)
	runtime.set_generator(output)
	await settle(60)
	var first: Image = viewport.get_texture().get_image()
	first.save_png("res://preview_first.png")
	var pixels := 0
	for y in first.get_height():
		for x in first.get_width():
			if first.get_pixel(x, y).a > 0.1: pixels += 1
	check(pixels > 10, "GPU preview actually draws particles")
	check(runtime.error_text.is_empty(), "Default shader compiles")
	check(runtime.particles.process_material is ShaderMaterial, "Shader installed in actual GPUParticles3D")
	var bounds: AABB = runtime.particles.capture_aabb()
	check(bounds.size.x > 0.2, "GPU particles move using exported velocity")
	var version: int = runtime.restart_count
	runtime.schedule_refresh()
	await settle()
	check(runtime.restart_count == version, "Identical graph keeps simulation state")
	runtime.set_paused(true)
	check(runtime.particles.speed_scale == 0.0, "Pause stops simulation")
	runtime.set_paused(false)
	preview.hide()
	check(runtime.particles.speed_scale == 0.0, "Hidden preview pauses")
	preview.show()
	check(runtime.particles.speed_scale == 1.0, "Visible preview resumes")
	var parameter = await particle(graph, "Speed", {"kind": "uniform", "data_type": "float", "uniform": "speed", "default": 2.0})
	connect_output(graph, parameter, "Process", "MASS")
	runtime.schedule_refresh()
	await settle()
	check(runtime.particles.process_material.shader.code.contains("uniform float speed"), "Typed Parameter used by preview")
	parameter.set_parameter("uniform_name", "not valid")
	await settle()
	check(not runtime.error_text.is_empty() and runtime.particles.speed_scale == 0.0, "Invalid graph freezes last good preview with error")
	parameter.set_parameter("uniform_name", "speed")
	await settle()
	check(runtime.error_text.is_empty() and runtime.particles.speed_scale == 1.0, "Preview recovers after error")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.8, 0.2, 1.0))
	image.save_png("res://preview_texture.png")
	var source = await add(graph, {"type": "image", "name": "Image", "parameters": {"image": "res://preview_texture.png"}})
	connect_output(graph, source, "Process", "COLOR")
	runtime.schedule_refresh()
	await settle(90)
	check(runtime.error_text.is_empty(), "MM image previews without baking files: " + runtime.error_text)
	check(runtime.particles.process_material.get_shader_parameter("texture_1") is Texture2D, "MM image bound to GPU material")
	graph.create_subgraph([source])
	runtime.schedule_refresh()
	await settle()
	check(runtime.error_text.is_empty(), "Subgraph texture previews")
	preview.queue_free()
	graph.queue_free()
	await settle(5)
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_PREVIEW: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
