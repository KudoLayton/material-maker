extends "test_parameter_edit_ui.gd"

func run():
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	for popup in get_tree().root.find_children("*", "Window", true, false): popup.hide()
	var editor = await window.new_particle_shader()
	var item = window.get_node("NodeLibraryManager").get_item("Miscellaneous/Typed Parameter")
	var created = await editor.create_nodes(item.item, Vector2.ZERO)
	var node = created[0]
	for frame in 5: await get_tree().process_frame
	check(node.controls.has("is_array") and not node.controls.has("array_size"), "New parameters have an explicit unchecked array toggle")
	if failures.is_empty():
		node.set_generator_parameter("value", 7.0)
		node.controls.is_array.button_pressed = true
		for frame in 3: await get_tree().process_frame
		check(node.generator.uniform_definition().array_size == 1 and node.generator.uniform_definition().value is Array and node.generator.uniform_definition().value == [7.0], "First array toggle wraps scalar")
		check(node.generator.get_output_defs()[0].shader_type == "float[1]", "Length-one array is a distinct port type")
		check(node.controls.array_size.get_node("Edit").text == "1", "Array size displays an integer")
		editor_viewport = node.get_viewport()
		for invalid in ["4.5", "0", "1025", "$size"]:
			var input: LineEdit = node.controls.array_size.get_node("Edit")
			input.grab_focus()
			input.edit()
			input.select_all()
			for character in invalid: await key_input(0, character.unicode_at(0))
			await key_input(KEY_ENTER)
			check(node.generator.uniform_definition().array_size == 1, "Reject invalid size: " + invalid)
		var input: LineEdit = node.controls.array_size.get_node("Edit")
		input.grab_focus()
		input.edit()
		input.select_all()
		await key_input(KEY_4, 52)
		await key_input(KEY_ENTER)
		check(node.generator.get_parameter("array_size") is int and node.generator.uniform_definition().array_size == 4, "Committed size is an integer")
		node.set_generator_parameter("default_json", "[1,2,3,4]")
		node.controls.is_array.button_pressed = false
		for frame in 3: await get_tree().process_frame
		check(node.generator.uniform_definition().value == 7.0 and not node.controls.has("array_size"), "Scalar default survives toggle")
		editor.undoredo.undo()
		for frame in 3: await get_tree().process_frame
		check(node.generator.uniform_definition().value is Array and node.generator.uniform_definition().value == [1.0,2.0,3.0,4.0], "Undo restores array and defaults")
		editor.undoredo.redo()
		for frame in 3: await get_tree().process_frame
		node.controls.is_array.button_pressed = true
		for frame in 3: await get_tree().process_frame
		check(node.generator.uniform_definition().array_size == 4 and node.generator.uniform_definition().value is Array and node.generator.uniform_definition().value == [1.0,2.0,3.0,4.0], "Array size and defaults survive toggle")
		var node_name: String = node.generator.name
		assert(await editor.save_file("res://app_parameter_array.ptex"))
		assert(await window.do_load_project("res://app_parameter_array.ptex"))
		for frame in 5: await get_tree().process_frame
		var restored = window.get_current_graph_edit().top_generator.get_node(node_name)
		check(restored.get_parameter("is_array") and restored.uniform_definition().array_size == 4 and restored.uniform_definition().value is Array and restored.uniform_definition().value == [1.0,2.0,3.0,4.0], "Array editor save and reload")
	var generic = load("res://material_maker/nodes/generic/generic.gd")
	var counter = generic.create_parameter_control({"type": "float", "name": "count", "min": 1, "max": 1024, "step": 1, "default": 1, "integer": true}, true)
	add_child(counter)
	counter.size = Vector2(100, 30)
	var emitted: Array = []
	counter.value_changed.connect(func(v): emitted.append(v))
	counter.mode = FloatEdit.Modes.SLIDING
	counter.start_position = 0
	counter.start_value = 1
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(7, 0)
	motion.alt_pressed = true
	counter._gui_input(motion)
	check(not emitted.is_empty() and emitted[-1] is int and counter.get_node("Edit").text.is_valid_int(), "Alt-drag remains integer")
	counter.mode = FloatEdit.Modes.IDLE
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	counter._gui_input(wheel)
	check(emitted[-1] is int, "Wheel emits integers")
	var count = counter.get_value()
	counter.set_value("$invalid", true)
	check(counter.get_value() == count, "Pasted expressions do not change integer values")
	var ordinary = generic.create_parameter_control({"type": "float", "name": "ordinary", "min": 0, "max": 10, "step": 1, "default": 1}, true)
	add_child(ordinary)
	ordinary.set_value(1.25)
	check(ordinary.get_value() == 1.25, "Ordinary step-one fields still accept fractions")
	print("PARTICLE_PARAMETER_ARRAY_UI: failures=" + str(failures))
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	window.quit()
	get_tree().quit(0 if failures.is_empty() else 1)
