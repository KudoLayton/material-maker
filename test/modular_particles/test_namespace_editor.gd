extends Node
const Checks = preload("namespace_checks.gd")
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
	get_tree().root.size = Vector2i(1600,1100)
	var editor = window.new_modular_particles()
	await frames(50)
	var state: Dictionary = await Checks.run(editor,get_tree(),check,"res://namespaces.png")
	editor.save_path = "res://namespace_roundtrip.mpfx"
	check(await editor.save(),"save namespace effect")
	check(await window.do_load_project(editor.save_path),"reopen namespace effect")
	editor = window.get_current_project()
	await frames(40)
	check(editor.document.attributes[0].name == state.name and editor.document.modules[state.module_id].inputs[0].name == "Position","saved raw names contain no generated namespace prefix")
	check(Checks.ui_node(editor,"Input").title == "Read Module.Position" and Checks.ui_node(editor,"CustomRead").title == "Read Particle.Custom."+state.name,"namespace display restored after reopen")
	var payload: Dictionary = editor.module_payload(state.module_id)
	check(Document.save_file("res://namespace_module.mmg",payload) == OK,"save module snapshot")
	var saved: Dictionary = Document.load_file("res://namespace_module.mmg")
	check(saved.particle_module.definition.inputs[0].name == "Position" and saved.particle_module.id == state.module_id,"mmg keeps raw input name and stable module ID")
	check(editor.load_module_data(saved),"import saved module")
	await frames(40)
	check(Checks.ui_node(editor,"CustomRead").title == "Read Particle.Custom."+state.name,"module import refreshes live names, not stale settings labels")
	var compiled: Dictionary = await editor.compile_document()
	check(compiled.errors.is_empty(),"namespace roundtrip/import compiles")
	print("MODULAR_NAMESPACE_EDITOR ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
