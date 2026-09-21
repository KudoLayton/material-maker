extends "test_parameter_edit_ui.gd"

func input_index(generator, input_name: String) -> int:
	var ports: Array = generator.get_input_defs()
	for i in ports.size():
		if ports[i].name == input_name: return i
	return -1

func run():
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	for popup in get_tree().root.find_children("*", "Window", true, false): popup.hide()
	var editor = await window.new_particle_shader()
	for frame in 5: await get_tree().process_frame
	for name in ["Material", "Process"]:
		var node = editor.get_node("node_" + name)
		check(node.controls.transform_mode.selected == 0, "New " + name + " defaults to Components")
		var created = await editor.create_nodes({"type": "particle_node", "settings": {"kind": "constant", "data_type": "vec2", "value": [0.1, 0.2]}}, Vector2(-400, 0))
		var source = created[0]
		editor.on_connect_node(source.name, 0, node.name, input_index(node.generator, "sampling_uv"))
		node.controls.transform_mode.select(1)
		node.controls.transform_mode.item_selected.emit(1)
		for frame in 5: await get_tree().process_frame
		check(node.generator.model_data().transform_mode == 1, "Switch to Matrix")
		check(node.generator.get_source(input_index(node.generator, "sampling_uv")).generator == source.generator, "Sampling UV connection remapped")
		editor.undoredo.undo()
		for frame in 5: await get_tree().process_frame
		check(node.controls.transform_mode.selected == 0, "Undo restores Components")
		check(node.generator.get_source(input_index(node.generator, "sampling_uv")).generator == source.generator, "Undo preserves Sampling UV")
		editor.undoredo.redo()
		for frame in 5: await get_tree().process_frame
		check(node.controls.transform_mode.selected == 1, "Redo restores Matrix")
		var matrices = await editor.create_nodes({"type": "particle_node", "settings": {"kind": "constant", "data_type": "mat4"}}, Vector2(-400, 250))
		var matrix = matrices[0]
		editor.on_connect_node(matrix.name, 0, node.name, input_index(node.generator, "TRANSFORM"))
		var history_step: int = editor.undoredo.step
		node.controls.transform_mode.select(0)
		node.controls.transform_mode.item_selected.emit(0)
		for frame in 5: await get_tree().process_frame
		check(editor.undoredo.step == history_step, "Rejected switch does not add undo history")
		check(node.controls.transform_mode.selected == 1, "Connected matrix blocks destructive switch")
		check(node.generator.get_source(input_index(node.generator, "TRANSFORM")).generator == matrix.generator, "Blocked switch preserves matrix")
		check(node.generator.has_meta("transform_mode_blocked"), "Blocked switch explains required disconnect")
		editor.on_disconnect_node(matrix.name, 0, node.name, input_index(node.generator, "TRANSFORM"))
		node.controls.transform_mode.select(0)
		node.controls.transform_mode.item_selected.emit(0)
		for frame in 5: await get_tree().process_frame
		check(node.controls.transform_mode.selected == 0, "Switch succeeds after disconnect")
	check(await editor.save_file("res://app_transform.ptex"), "Save Components graph")
	check(await window.do_load_project("res://app_transform.ptex"), "Reload Components graph")
	for name in ["Material", "Process"]:
		check(window.get_current_graph_edit().top_generator.get_node(name).model_data().transform_mode == 0, "Saved mode persists")
	check(await window.do_load_project("res://material_maker/examples/particles/blank.ptex"), "Open legacy Matrix graph")
	for name in ["Material", "process_output"]:
		var generator = window.get_current_graph_edit().top_generator.get_node_or_null(name)
		if generator != null: check(generator.model_data().transform_mode == 1, "Legacy file retains Matrix mode")
	print("PARTICLE_TRANSFORM_UI: failures=" + str(failures))
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	await window.quit()
	get_tree().quit(0 if failures.is_empty() else 1)
