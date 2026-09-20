extends Node

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	for frame in 30: await get_tree().process_frame
	var editor = await window.new_particle_shader()
	var item = window.get_node("NodeLibraryManager").get_item("Simple/Constant/Typed")
	var created = await editor.create_nodes(item.item, Vector2(0, 0))
	var node = created[0]
	var option: OptionButton = node.controls.data_type
	var index: int = node.generator.option_values("data_type").find("bvec3")
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
	assert(node.generator.model_data().data_type == "vec2")
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
	item = window.get_node("NodeLibraryManager").get_item("Particles/Random")
	created = await editor.create_nodes(item.item, Vector2(0, 0))
	node = created[0]
	assert(node.generator.model_data().data_type == "vec3")
	assert(mm_io_types.types.particle_vec3.slot_type == mm_io_types.types.rgb.slot_type)
	assert(MMGenParticle.value_type("vec3") == "rgb")
	var popup = editor.node_popup
	popup.qc_slot_type = mm_io_types.types.particle_vec3.slot_type
	popup.qc_is_output = false
	assert(popup.check_quick_connect({"type": "math_v3"}))
	popup.qc_slot_type = mm_io_types.types.rgb.slot_type
	popup.qc_is_output = true
	assert(popup.check_quick_connect({"type": "shader", "shader_model": {"outputs": [{"type": "particle_vec3"}]}}))
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
	editor = await window.new_particle_shader()
	item = window.get_node("NodeLibraryManager").get_item("Filter/Math/Compare")
	created = await editor.create_nodes(item.item, Vector2(0, 0))
	node = created[0]
	index = node.generator.option_values("data_type").find("vec3")
	node.controls.data_type.select(index)
	node.controls.data_type.item_selected.emit(index)
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().operation == "equal")
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().operation == "less", "Undo must restore the previous comparison")
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.model_data().operation == "equal")
	print("PARTICLE_RANDOM_UI: type selection, undo/redo and settings roundtrip passed")
	get_tree().root.size = Vector2i(1600, 1000)
	window.layout.reset_panels()
	editor.get_node("node_Material").position_offset = Vector2(0, 1100)
	editor.get_node("node_Process").position_offset = Vector2(650, 1100)
	node.position_offset = Vector2(0, 380)
	for pair in [["Simple/Constant/Typed", Vector2(0, 0)], ["Filter/Math/Typed", Vector2(310, 0)], ["Miscellaneous/Typed Parameter", Vector2(650, 0)]]:
		item = window.get_node("NodeLibraryManager").get_item(pair[0])
		created = await editor.create_nodes(item.item, pair[1])
		created[0].position_offset = pair[1]
		if pair[0] == "Miscellaneous/Typed Parameter":
			var parameter = created[0]
			parameter.set_generator_parameter("uniform_name", "velocity")
			parameter.set_generator_parameter("value", 10.0)
			assert(parameter.generator.uniform_definition().value == 10.0)
			var type_index: int = parameter.generator.option_values("data_type").find("vec3")
			parameter.controls.data_type.select(type_index)
			parameter.controls.data_type.item_selected.emit(type_index)
			for frame in 3: await get_tree().process_frame
			for i in 3: parameter.set_generator_parameter("v%d" % i, [-1.0, 2.0, 3.0][i])
			type_index = parameter.generator.option_values("data_type").find("bvec3")
			parameter.controls.data_type.select(type_index)
			parameter.controls.data_type.item_selected.emit(type_index)
			for frame in 3: await get_tree().process_frame
			assert(parameter.controls.v0 is CheckBox)
			parameter.controls.v0.button_pressed = true
			assert(parameter.generator.uniform_definition().value == [true, false, false])
			editor.undoredo.undo()
			for frame in 3: await get_tree().process_frame
			assert(parameter.generator.uniform_definition().value == [false, false, false])
			editor.undoredo.undo()
			for frame in 3: await get_tree().process_frame
			assert(parameter.generator.uniform_definition().value == [-1.0, 2.0, 3.0])
			editor.undoredo.redo()
			for frame in 3: await get_tree().process_frame
			assert(parameter.generator.model_data().data_type == "bvec3")
			editor.undoredo.undo()
			for frame in 3: await get_tree().process_frame
			assert(await editor.save_file("res://app_parameter.ptex"))
			print("PARTICLE_PARAMETER_UI: typed defaults and undo/redo passed")
	editor.zoom = 0.85
	editor.scroll_offset = Vector2(-30, -30)
	for frame in 15: await get_tree().process_frame
	window.modulate = Color.WHITE
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("res://app_supplemental_ui.png")
	assert(await window.do_load_project("res://app_parameter.ptex"))
	for frame in 5: await get_tree().process_frame
	var saved_parameters = window.get_current_graph_edit().top_generator.get_children().filter(func(g): return g is MMGenParticle and g.settings.kind == "uniform")
	assert(saved_parameters.size() == 1)
	assert(saved_parameters[0].uniform_definition().name == "velocity")
	assert(saved_parameters[0].uniform_definition().value == [-1.0, 2.0, 3.0])
	print("PARTICLE_CONSTANT_UI: passed")
	mm_globals.set_config("confirm_quit", false)
	mm_globals.set_config("confirm_close_project", false)
	window.quit()
