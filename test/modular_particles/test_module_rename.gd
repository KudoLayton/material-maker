extends Node
const RenameChecks = preload("rename_checks.gd")
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames(30)
	get_tree().root.size = Vector2i(1440,960)
	var editor = window.new_modular_particles()
	await frames(50)
	var renamed: Dictionary = await RenameChecks.run(editor,get_tree(),check)
	if not renamed.is_empty():
		editor.save_path = "res://renamed_roundtrip.mpfx"
		check(await editor.save(),"save renamed mpfx")
		check(await window.do_load_project(editor.save_path),"reopen renamed mpfx")
		editor = window.get_current_project()
		await frames(40)
		check(editor.document.modules[renamed.id].name == renamed.name,"renamed module survives save/reopen")
		check(editor.stack.get_item_text(0) == renamed.name,"reopened stack shows renamed module")
		var payload: Dictionary = editor.module_payload(renamed.id)
		check(Document.save_file("res://renamed_module.mmg",payload) == OK,"save renamed mmg snapshot")
		var saved: Dictionary = Document.load_file("res://renamed_module.mmg")
		check(saved.particle_module.id == renamed.id and saved.particle_module.definition.name == renamed.name,"mmg disk roundtrip keeps stable ID and name")
		saved.particle_module.definition.name = "Imported Rename"
		check(editor.load_module_data(saved),"reimport renamed mmg")
		await frames(20)
		check(editor.document.modules[renamed.id].name == "Imported Rename","mmg revision applies display name")
		var result: Dictionary = await editor.compile_document()
		check(result.errors.is_empty(),"renamed mmg still compiles")
	print("MODULAR_MODULE_RENAME ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
