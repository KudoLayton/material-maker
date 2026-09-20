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
	output.set_preview_setting("amount", 4)
	output.set_preview_setting("lifetime", 0.4)
	output.set_preview_setting("emission", 1)
	await settle(30)
	var resets := 0
	var previous_x := 0.0
	var maximum_width := 0.0
	for frame in 72:
		await settle(1)
		bounds = runtime.particles.capture_aabb()
		var center: float = bounds.get_center().x
		if previous_x - center > 0.15: resets += 1
		previous_x = center
		maximum_width = maxf(maximum_width, bounds.size.x)
	check(resets >= 2, "Burst actually repeats across multiple GPU lifetimes")
	check(maximum_width < 0.201, "Burst particles spawn together: width=" + str(maximum_width))
	output.set_preview_setting("emission", 0)
	await settle(40)
	check(runtime.particles.capture_aabb().size.x > 0.25, "Continuous particles have staggered ages")
	output.particle_defaults.VELOCITY = {"value": [0.0, 0.0, 0.0]}
	output.set_preview_setting("amount", 1)
	output.set_preview_setting("lifetime", 10.0)
	output.set_preview_setting("quad_size", 1.0)
	runtime.schedule_refresh()
	await settle(40)
	var circle: Image = viewport.get_texture().get_image()
	circle.save_png("res://preview_circle.png")
	check(circle.get_pixel(64, 64).a > 0.8 and circle.get_pixel(72, 64).a > 0.2 and circle.get_pixel(72, 64).a < 0.7 and circle.get_pixel(78, 78).a < 0.05, "Soft circle has opaque center and transparent falloff")
	check(circle.get_pixel(64, 64).g > circle.get_pixel(64, 64).r, "Graph color tints preview sprite")
	output.set_preview_setting("shape", 0)
	await settle(5)
	var square: Image = viewport.get_texture().get_image()
	check(square.get_pixel(78, 78).a > 0.9, "Square keeps its corners")
	camera.position = Vector3(4, 0, 0)
	camera.look_at(Vector3.ZERO)
	await settle(5)
	check(viewport.get_texture().get_image().get_pixel(78, 78).a > 0.9, "Quad faces rotated camera")
	camera.position = Vector3(0, 0, 5)
	camera.look_at(Vector3.ZERO)
	output.particle_defaults.TRANSFORM = {"value": [[2, 0, 0, 0], [0, 2, 0, 0], [0, 0, 2, 0], [0, 0, 0, 1]]}
	runtime.schedule_refresh()
	await settle()
	check(viewport.get_texture().get_image().get_pixel(90, 90).a > 0.9, "Billboard preserves graph scale")
	var remote = await add(graph, {"type": "remote", "name": "Controls", "parameters": {"brightness": 0.8}, "widgets": [{"name": "brightness", "label": "Brightness", "type": "named_parameter", "min": 0.0, "max": 1.0, "step": 0.1, "default": 0.8}]})
	var value = await add(graph, {"type": "uniform_greyscale", "name": "Brightness", "parameters": {"color": "$brightness"}})
	connect_output(graph, value, "Process", "COLOR")
	runtime.schedule_refresh()
	await settle()
	var bright: float = viewport.get_texture().get_image().get_pixel(64, 64).r
	remote.set_parameter("brightness", 0.1)
	await settle()
	check(viewport.get_texture().get_image().get_pixel(64, 64).r < bright - 0.2, "Remote changes update actual rendered output")
	var array = await add(graph, {"type": "particle_node", "name": "Weights", "settings": {"kind": "uniform", "data_type": "float", "uniform": "weights"}, "parameters": {"is_array": true, "array_size": 3, "default_json": "[0.25, 0.5, 0.75]"}})
	var element = await particle(graph, "Element", {"kind": "array_get", "data_type": "float", "array_size": 3})
	graph.connect_children(array, 0, element, 0)
	connect_output(graph, element, "Process", "COLOR")
	runtime.schedule_refresh()
	await settle()
	check(runtime.error_text.is_empty() and runtime.particles.process_material.get_shader_parameter("weights") == PackedFloat32Array([0.25, 0.5, 0.75]), "Typed array defaults bound in preview")
	var preparation = load("res://addons/material_maker/particles/preview_material.gd")
	var malformed: Dictionary = await preparation.prepare({"errors": [], "mm_uniforms": {}, "uniforms": [{"name": "maps", "type": "sampler2D", "array_size": 2, "resources": [""]}], "target_project": ""}, get_tree())
	check(not malformed.errors.is_empty(), "Reject mismatched external texture array")
	var cancelled: Dictionary = await preparation.prepare({"errors": [], "mm_uniforms": {"texture_1": MMGenBase.ShaderUniform.new("texture_1", "sampler2D", MMTexture.new())}, "uniforms": []}, get_tree(), func(): return false)
	check(cancelled.get("cancelled", false), "Discard obsolete texture preparation")
	preview.queue_free()
	graph.queue_free()
	await settle(5)
	await mm_renderer.stop_rendering_thread()
	print("PARTICLE_PREVIEW: failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
