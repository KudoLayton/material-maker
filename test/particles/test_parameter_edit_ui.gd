extends Node

var failures: Array[String] = []
var editor_viewport: Viewport

func _ready():
	run.call_deferred()

func check(condition: bool, message: String):
	if not condition: failures.append(message)

func key_input(code: int, character: int = 0):
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.unicode = character
	editor_viewport.handle_input_locally = true
	editor_viewport.push_input(event, true)
	for frame in 3: await get_tree().process_frame

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
	var input: LineEdit = node.controls.uniform_name
	editor_viewport = input.get_viewport()
	editor_viewport.gui_disable_input = false
	var original: String = node.generator.uniform_definition().name
	input.grab_focus()
	input.edit()
	input.select_all()
	await key_input(KEY_V, 118)
	check(not is_instance_valid(input) or input.text == "v", "Key input reaches the name field")
	check(is_instance_valid(input) and input.has_focus(), "Name retains focus after one character")
	check(node.generator.uniform_definition().name == original, "Typing does not commit the name")
	if failures.is_empty():
		for character in "elocity": await key_input(0, character.unicode_at(0))
		check(input.text == "velocity", "Continuous typing")
		await key_input(KEY_ENTER)
		check(node.generator.uniform_definition().name == "velocity", "Enter commits name")
		input.release_focus()
		for frame in 3: await get_tree().process_frame
		editor.undoredo.undo()
		check(node.generator.uniform_definition().name == original, "One undo reverts complete name without duplicate commit")
		editor.undoredo.redo()
		input = node.controls.uniform_name
		input.grab_focus()
		input.edit()
		input.select_all()
		for character in "speed": await key_input(0, character.unicode_at(0))
		input.release_focus()
		for frame in 3: await get_tree().process_frame
		check(node.generator.uniform_definition().name == "speed", "Focus exit commits name")
	if failures.is_empty():
		input = node.controls.hint
		input.grab_focus()
		input.edit()
		await key_input(KEY_A, 97)
		check(node.generator.uniform_definition().hint == "a", "Ordinary string fields still update immediately")
	print("PARTICLE_PARAMETER_EDIT_UI: failures=" + str(failures))
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	await window.quit()
	get_tree().quit(0 if failures.is_empty() else 1)
