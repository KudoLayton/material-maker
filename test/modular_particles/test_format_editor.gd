extends Node
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int = 30) -> void:
	for frame in count: await get_tree().process_frame
func settle(editor) -> void:
	await frames(45)
	while editor._loading or editor._building: await frames(3)
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames()
	var editor = window.new_modular_particles()
	await settle(editor)
	editor.capture_graph()
	editor.save_path = "res://latest-format.mpfx"
	check(await editor.save(),"save latest document")
	var doc: Dictionary = editor.document.duplicate(true)
	var history: int = editor.undoredo.cursor
	var preview = editor.preview
	var graph = editor.graph_edit.top_generator
	var current: int = window.projects_panel.get_projects().current_tab
	var count: int = window.projects_panel.get_projects().get_tab_count()
	var saved_hash := FileAccess.get_sha256(editor.save_path)
	var clipboard := DisplayServer.clipboard_get()
	check(doc.version == 2 and doc.user_parameters.is_empty(),"new GUI effect is v2 with no Users")
	check(is_instance_valid(preview) and preview.ready_for_simulation,"valid preview before rejections")
	for version in [null,1,3]:
		var bad := doc.duplicate(true)
		if version == null: bad.erase("version")
		else: bad.version = version
		var path := "res://invalid-format-%s.mpfx" % ("missing" if version == null else str(version))
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(bad))
		file.close()
		check(not await editor.load_project(path),"panel rejects version " + str(version))
		check(not await window.do_load_project(path),"File/Load rejects version " + str(version))
		editor.apply_document(bad)
		DisplayServer.clipboard_set(JSON.stringify(bad))
		var parsed: Dictionary = await mm_globals.parse_paste_data(DisplayServer.clipboard_get())
		check(parsed.graph == null and parsed.error.contains("version 2"),"clipboard reports required version")
		await editor.graph_edit.paste()
		await settle(editor)
		check(editor.document == doc and editor.save_path == "res://latest-format.mpfx" and not editor.need_save,"rejection preserves original document/path/dirty")
		check(editor.undoredo.cursor == history and editor.graph_edit.top_generator == graph,"rejection preserves graph/history")
		check(editor.preview == preview and preview.ready_for_simulation,"rejection preserves last good GPU preview")
		check(window.projects_panel.get_projects().get_tab_count() == count and window.projects_panel.get_projects().current_tab == current,"rejection does not create or switch tabs")
		# Guard the save boundary even against a corrupted in-memory document.
		editor.document = bad
		check(not await editor.save() and FileAccess.get_sha256(editor.save_path) == saved_hash,"unsupported save never overwrites existing file")
		editor.document = doc.duplicate(true)
	DisplayServer.clipboard_set(clipboard)
	check(await editor.load_project("res://latest-format.mpfx"),"latest GUI reload accepted")
	await settle(editor)
	check(editor.document.version == 2,"reload retains v2")
	print("MODULAR_FORMAT_EDITOR ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
