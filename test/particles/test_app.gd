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
	var editor = window.new_particle_shader()
	for frame in 10: await get_tree().process_frame
	assert(window.get_current_mode() == "particle")
	assert(editor.validate_document())
	assert(editor.save_file("res://app_roundtrip.ptex"))
	assert(await window.do_load_project("res://app_roundtrip.ptex"))
	for frame in 10: await get_tree().process_frame
	assert(window.get_current_project().get_project_type() == "particle")
	var tabs = window.projects_panel.get_projects()
	tabs.current_tab = 0
	for frame in 5: await get_tree().process_frame
	assert(window.get_current_mode() == "material")
	tabs.current_tab = tabs.get_tab_count() - 1
	for frame in 5: await get_tree().process_frame
	assert(window.get_current_mode() == "particle")
	window.layout.reset_panels()
	window.edit_select_all()
	window.edit_copy()
	window.edit_select_none()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://app.png")
	DisplayServer.clipboard_set(previous_clipboard)
	print("PARTICLE_APP_TESTS: passed")
	for frame in 120: await get_tree().process_frame
	root.get_node("mm_globals").set_config("confirm_quit", false)
	root.get_node("mm_globals").set_config("confirm_close_project", false)
	window.quit()
