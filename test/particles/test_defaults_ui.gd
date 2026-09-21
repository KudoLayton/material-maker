extends "test_parameter_edit_ui.gd"

func run():
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	for popup in get_tree().root.find_children("*", "Window", true, false): popup.hide()
	var editor = await window.new_particle_shader()
	for frame in 5: await get_tree().process_frame
	var outputs = editor.get_children().filter(func(child): return child is GraphNode and child.get("generator") is MMGenParticleMaterial)
	check(outputs.size() == 1, "Start output exists")
	if outputs.size() == 1:
		var node = outputs[0]
		check(node.controls.initialize_particle.button_pressed, "Initialization enabled by default")
		node.controls.initialize_particle.button_pressed = false
		for frame in 3: await get_tree().process_frame
		check(not node.generator.particle_configuration().initialize_particle, "Toggle changes compiler policy")
		editor.undoredo.undo()
		for frame in 3: await get_tree().process_frame
		check(node.controls.initialize_particle.button_pressed and node.generator.particle_configuration().initialize_particle, "Undo restores initialization")
		editor.undoredo.redo()
		for frame in 3: await get_tree().process_frame
		check(not node.controls.initialize_particle.button_pressed and not node.generator.particle_configuration().initialize_particle, "Redo restores opt out")
		check(await editor.save_file("res://app_defaults.ptex"), "Save initialization policy")
		check(await window.do_load_project("res://app_defaults.ptex"), "Reload initialization policy")
		check(not window.get_current_graph_edit().top_generator.get_node("Material").particle_configuration().initialize_particle, "Saved opt out persists")
	print("PARTICLE_DEFAULTS_UI: failures=" + str(failures))
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	await window.quit()
	get_tree().quit(0 if failures.is_empty() else 1)
