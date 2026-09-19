extends Node

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	var editor = await window.new_particle_shader()
	var item = window.get_node("NodeLibraryManager").get_item("Particles/Tools/Constant")
	var created = await editor.create_nodes(item.item, Vector2(0, 0))
	var node = created[0]
	var option: OptionButton = node.controls.data_type
	var index: int = MMGenParticle.Interface.TYPES.find("bvec3")
	print("PARTICLE_CONSTANT_UI: selecting bvec3 through popup")
	option.select(index)
	option.item_selected.emit(index)
	if not is_instance_valid(option):
		push_error("Particle type selection destroyed its active OptionButton")
		get_tree().quit(1)
		return
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().data_type == "bvec3")
	for key in ["v0", "v1", "v2"]:
		assert(node.controls[key] is CheckBox)
	node.controls.v0.button_pressed = true
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().value == [true, false, false])
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().value == [false, false, false])
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().value == [true, false, false])
	editor.undoredo.undo()
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().data_type == "float")
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().data_type == "bvec3")
	assert(node.controls.v0 is CheckBox)
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	var generator_name: String = node.generator.name
	assert(await editor.save_file("res://app_constant_bvec3.ptex"))
	assert(await window.do_load_project("res://app_constant_bvec3.ptex"))
	for frame in 5: await get_tree().process_frame
	var reopened = window.get_current_graph_edit().top_generator.get_node(generator_name)
	assert(reopened.model_data().data_type == "bvec3")
	assert(reopened.model_data().value == [true, false, false])
	editor = await window.new_particle_shader()
	item = window.get_node("NodeLibraryManager").get_item("Particles/Tools/Random")
	created = await editor.create_nodes(item.item, Vector2(0, 0))
	node = created[0]
	assert(node.generator.model_data().data_type == "vec3")
	var random_inputs = node.generator.get_input_defs()
	assert(random_inputs[2].name == "seed" and random_inputs[2].label == "Seed Offset")
	assert(random_inputs[1].label == "System Seed (RANDOM_SEED)")
	assert(node.generator.get_output_defs().size() == 1)
	assert(node.generator.get_output_defs()[0].label == "Random Value")
	for key in ["seed", "minimum", "maximum"]:
		assert(node.controls[key].tooltip_text.contains("unconnected"))
		var row = node.controls[key].get_parent()
		assert(row.get_child(1).text == "Input default")
		assert(row.get_child(0).text.begins_with({"seed": "Seed Offset", "minimum": "Minimum", "maximum": "Maximum"}[key]))
	option = node.controls.data_type
	assert(option.item_count == 4)
	option.select(1)
	option.item_selected.emit(1)
	assert(is_instance_valid(option))
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().data_type == "vec2")
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().data_type == "vec3")
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().data_type == "vec2")
	for pair in [["seed", 17.0], ["minimum", -2.0], ["maximum", 3.0]]:
		assert(node.controls.has(pair[0]))
		node.controls[pair[0]].value_changed_undo.emit(pair[1], false)
	for frame in 3: await get_tree().process_frame
	generator_name = node.generator.name
	assert(await editor.save_file("res://app_random.ptex"))
	assert(await window.do_load_project("res://app_random.ptex"))
	for frame in 5: await get_tree().process_frame
	reopened = window.get_current_graph_edit().top_generator.get_node(generator_name)
	assert(reopened.model_data().data_type == "vec2")
	assert(reopened.model_data().seed == 17.0)
	assert(reopened.model_data().minimum == -2.0)
	assert(reopened.model_data().maximum == 3.0)
	print("PARTICLE_RANDOM_UI: type selection, undo/redo and settings roundtrip passed")
	print("PARTICLE_CONSTANT_UI: passed")
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	window.quit()
