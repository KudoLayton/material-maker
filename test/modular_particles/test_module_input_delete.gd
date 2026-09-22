extends Node
const DeleteChecks = preload("input_delete_checks.gd")
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
	var state: Dictionary = await DeleteChecks.run(editor,get_tree(),check)
	editor.save_path = "res://input_delete_roundtrip.mpfx"
	check(await editor.save(),"save after input deletion")
	check(await window.do_load_project(editor.save_path),"reopen deleted-input effect")
	editor = window.get_current_project()
	await frames(40)
	check(not editor.document.modules[state.module_id].inputs.any(func(input): return input.id == state.input_id),"deleted definition stays absent after reopen")
	var clean := true
	for stage in ["spawn","update"]:
		for instance in editor.document.stages[stage]:
			if instance.module == state.module_id and instance.parameters.has(state.input_id): clean = false
	check(clean,"deleted instance values stay absent after reopen")
	var payload: Dictionary = editor.module_payload(state.module_id)
	check(Document.save_file("res://input_delete_module.mmg",payload) == OK,"save mmg after input deletion")
	var saved: Dictionary = Document.load_file("res://input_delete_module.mmg")
	check(not saved.particle_module.definition.inputs.any(func(input): return input.id == state.input_id),"mmg disk roundtrip omits deleted input")
	check(editor.load_module_data(saved),"reimport mmg after input deletion")
	await frames(30)
	var result: Dictionary = await editor.compile_document()
	check(result.errors.is_empty(),"reopened and reimported effect compiles without stale overrides")
	print("MODULAR_MODULE_INPUT_DELETE ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
