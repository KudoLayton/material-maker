extends Node

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var root = get_tree().root
	var previous_clipboard := DisplayServer.clipboard_get()
	var window = load("res://material_maker/main_window.tscn").instantiate()
	root.add_child(window)
	for frame in 30: await get_tree().process_frame
	root.size = Vector2i(1400, 900)
	var editor = await window.new_particle_shader()
	for frame in 10: await get_tree().process_frame
	assert(editor is MMGraphEdit)
	assert(window.get_current_mode() == "material")
	assert(window.get_current_graph_edit() == editor)
	assert(window.get_panel("Library").is_inside_tree())
	assert(window.get_panel("Hierarchy").is_inside_tree())
	var library = window.get_node("NodeLibraryManager")
	var item = library.get_item("Simple/Uniform/Grayscale")
	assert(item != null)
	var created = await editor.create_nodes(item.item, Vector2(0, 0))
	assert(created.size() == 1)
	var node = created[0]
	var original_count = editor.top_generator.get_child_count()
	node.set_generator_parameter("color", 0.75)
	assert(node.generator.get_parameter("color") == 0.75)
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.get_parameter("color") == 0.5)
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	assert(node.generator.get_parameter("color") == 0.75)
	editor.select_none()
	node.selected = true
	window.edit_copy()
	window.edit_paste()
	for frame in 5: await get_tree().process_frame
	assert(editor.top_generator.get_child_count() == original_count + 1)
	editor.undoredo.undo()
	for frame in 3: await get_tree().process_frame
	assert(editor.top_generator.get_child_count() == original_count)
	editor.undoredo.redo()
	for frame in 3: await get_tree().process_frame
	assert(editor.top_generator.get_child_count() == original_count + 1)
	editor.select_none()
	var pasted = editor.get_children().filter(func(child): return child is GraphNode and child != node and str(child.name).begins_with(str(node.name)))[0]
	editor.on_connect_node(pasted.name, 0, "node_Process", 3)
	pasted.selected = true
	print("PARTICLE_APP_STEP: group")
	window.create_subgraph()
	for frame in 5: await get_tree().process_frame
	assert(editor.generator != editor.top_generator)
	editor.on_ButtonUp_pressed()
	for frame in 5: await get_tree().process_frame
	assert(editor.generator == editor.top_generator)
	editor.select_none()
	for child in editor.get_children():
		if child is GraphNode and child.generator is MMGenGraph: child.selected = true
	await window.add_selection_to_library(1, false, true)
	assert(not library.get_child(1).library_items.is_empty())
	print("PARTICLE_APP_STEP: save")
	assert(await editor.save_file("res://app_roundtrip.ptex"))
	assert(await window.do_load_project("res://app_roundtrip.ptex"))
	for frame in 10: await get_tree().process_frame
	assert(window.get_current_graph_edit() is MMGraphEdit)
	var current = window.get_current_graph_edit()
	assert(current.get_material_node() is MMGenParticleMaterial)
	assert(current.get_material_node().compile_shader().errors.is_empty())
	var result = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(current.top_generator, "res://app_particle")
	assert(result.errors.is_empty())
	window.new_material()
	for frame in 10: await get_tree().process_frame
	assert(not window.get_current_graph_edit().get_material_node() is MMGenParticleMaterial)
	assert(await window.get_current_graph_edit().save_file("res://ordinary_roundtrip.ptex"))
	await window.do_load_project("res://app_roundtrip.ptex")
	for frame in 10: await get_tree().process_frame
	window.layout.reset_panels()
	await window.new_particle_shader()
	for frame in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://app.png")
	DisplayServer.clipboard_set(previous_clipboard)
	print("PARTICLE_APP_TESTS: passed")
	for frame in 30: await get_tree().process_frame
	root.get_node("mm_globals").set_config("confirm_quit", false)
	root.get_node("mm_globals").set_config("confirm_close_project", false)
	window.quit()
