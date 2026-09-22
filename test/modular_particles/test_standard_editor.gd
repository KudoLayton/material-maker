extends Node
const S = preload("standard_checks.gd")
const UI = preload("standard_ui_checks.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	get_tree().root.size = Vector2i(1500,1040)
	await S.frames(get_tree(),30)
	var editor = window.new_modular_particles()
	await S.frames(get_tree(),40)
	var original := await UI.run(editor,get_tree(),check,"res://standard-library.png")
	# Roundtrip the completed standard pipeline, not the caller's original document.
	editor.save_path = "res://standard-ui.mpfx"
	check(await editor.save(),"standard mpfx saves")
	# JSON numbers are floats on load; compare persisted data, not GDScript int identity.
	var saved: Dictionary = S.D.load_file(editor.save_path)
	check(await editor.load_project(editor.save_path),"standard mpfx reopens")
	await S.frames(get_tree(),40)
	check(editor.document == saved,"standard metadata, IDs and snapshots roundtrip")
	check((await editor.compile_document()).errors.is_empty(),"reopened standard pipeline compiles")
	var gravity: Dictionary = S.instance(editor.document,"gravity")
	editor.selected = editor.document.stages.update.find(gravity)
	await editor.load_selected()
	await S.frames(get_tree(),10)
	var payload: Dictionary = editor.module_payload(editor.current_module)
	check(S.D.save_file("res://standard-gravity.mmg",payload) == OK,"Save mmg to disk")
	payload = S.D.load_file("res://standard-gravity.mmg")
	payload.particle_module.definition.name = "Imported Gravity"
	check(editor.load_module_data(payload),"explicit mmg revision import")
	await S.frames(get_tree(),40)
	check(editor.document.modules[gravity.module].name == "Imported Gravity" and editor.document.attributes == saved.attributes,"import updates definition without duplicate roles")
	var bad: Dictionary = payload.duplicate(true)
	bad.particle_module.attributes[0].type = "float"
	bad.particle_module.attributes[0].default = 0.0
	var before: Dictionary = editor.document.duplicate(true)
	var cursor: int = editor.undoredo.cursor
	check(not editor.load_module_data(bad) and before == editor.document and cursor == editor.undoredo.cursor,"bad mmg import preserves document/history")
	await UI.restore(editor,original)
	check((await editor.compile_document()).errors.is_empty(),"original document restored")
	print("MODULAR_STANDARD_EDITOR ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	window.quit()
