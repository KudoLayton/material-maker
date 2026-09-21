extends "test_parameter_edit_ui.gd"

func run():
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	for popup in get_tree().root.find_children("*", "Window", true, false): popup.hide()
	var editor = await window.new_particle_shader()
	for frame in 30: await get_tree().process_frame
	window.layout.reset_panels()
	window.layout.set_panel_visible("Preview3D", true)
	for frame in 10: await get_tree().process_frame
	var preview = window.preview_3d
	check(preview.has_method("set_particle_generator"), "Existing 3D Preview supports particle graphs")
	if preview.has_method("set_particle_generator"):
		var runtime = preview.particle_preview
		check(runtime != null and runtime.particles.process_material != null, "Particle graph runs in preview")
		check(not preview.objects.visible, "Ordinary mesh hidden in particle mode")
		check(preview.is_visible_in_tree() and runtime.particles.speed_scale == 1.0, "Visible panel plays after layout changes")
		check(runtime.error_text.is_empty(), "Default graph previews without errors")
		var material = editor.top_generator.get_node("Material")
		var before: String = material.compile_shader().code
		var revision: int = runtime.restart_count
		await window.update_preview_3d([preview])
		for frame in 20: await get_tree().process_frame
		check(runtime.restart_count == revision, "Unchanged graph does not restart")
		check(material.has_method("set_preview_setting"), "Per-document preview settings supported")
		if material.has_method("set_preview_setting"):
			var controls = runtime.controls
			controls.fields.emission.select(1)
			controls.fields.emission.item_selected.emit(1)
			controls.fields.amount.value = 24
			controls.fields.lifetime.value = 0.5
			controls.fields.quad_size.value = 0.25
			for frame in 20: await get_tree().process_frame
			check(runtime.particles.amount == 24 and runtime.particles.lifetime == 0.5, "Controls update live emitter")
			check(runtime.particles.explosiveness == 1.0 and not runtime.particles.one_shot, "Burst repeats automatically")
			check(runtime.particles.draw_pass_1.size == Vector2(0.25, 0.25), "Quad size control")
			check(material.compile_shader().code == before, "Preview settings never change exported shader")
			check(not material.set_preview_setting("amount", 0) and not material.set_preview_setting("amount", 1.5), "Reject invalid particle counts")
			check(not material.set_preview_setting("lifetime", -1.0), "Reject negative lifetime")
			controls.pause.button_pressed = true
			check(runtime.particles.speed_scale == 0.0, "Pause button")
			controls.pause.button_pressed = false
			check(await editor.save_file("res://app_preview.ptex"), "Save preview settings")
			check(await window.do_load_project("res://app_preview.ptex"), "Reload preview settings")
			for frame in 30: await get_tree().process_frame
			check(window.get_current_graph_edit().top_generator.get_node("Material").preview_settings.amount == 24, "Saved preview settings restored")
		var current_runtime = preview.particle_preview
		if current_runtime.controls != null:
			current_runtime.controls.button.button_pressed = true
			for frame in 5: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			preview.get_viewport().get_texture().get_image().save_png("res://preview_controls.png")
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			check(await window.do_load_project(args[0]), "Load requested graph without modifying it")
			for frame in 90: await get_tree().process_frame
			check(preview.particle_preview.error_text.is_empty(), "Requested graph previews")
			check(preview.particle_preview.particles.capture_aabb().size.length() > 0.0, "Requested graph actually simulates")
			var requested = window.get_current_graph_edit().top_generator.get_node("Material")
			requested.set_preview_setting("emission", 1)
			for frame in 150: await get_tree().process_frame
			check(preview.particle_preview.error_text.is_empty() and preview.particle_preview.particles.capture_aabb().size.length() > 0.0, "Requested graph previews in repeating burst mode")
			await RenderingServer.frame_post_draw
			preview.get_viewport().get_texture().get_image().save_png("res://preview_requested.png")
		preview.set_particle_generator(null)
		check(preview.objects.visible and preview.particle_preview == null, "Ordinary mesh restored")
	print("PARTICLE_PREVIEW_UI: failures=" + str(failures))
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	await window.quit()
	get_tree().quit(0 if failures.is_empty() else 1)
