extends Node
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Users = preload("res://addons/material_maker/particles/modular/user_parameters.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int = 35) -> void:
	for frame in count: await get_tree().process_frame
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames()
	var editor = window.new_modular_particles()
	await frames()
	var doc := Document.create()
	var module := Library.definition("User cleanup",["spawn","update"],[])
	module.inputs = [{"id":"bound","name":"Bound","type":"float","default":1.0},{"id":"literal","name":"Literal","type":"float","default":2.0}]
	doc.modules.fixture = module
	doc.stages.spawn = [{"id":"first","module":"fixture","parameters":{"bound":9.0}},{"id":"disabled","module":"fixture","enabled":false}]
	doc.stages.update = [{"id":"update","module":"fixture"}]
	var added := Users.add(doc,"Shared","float",3.0)
	doc = added.document
	for id in ["first","disabled","update"]: doc = Users.bind(doc,id,"bound",added.user_id).document
	editor.stage = "spawn"
	editor.selected = 0
	editor.apply_document(doc)
	await frames(60)
	editor.capture_graph()
	var before: Dictionary = editor.document.duplicate(true)
	var cursor: int = editor.undoredo.cursor
	editor.set_input("first","bound",77.0)
	check(editor.document == before and editor.undoredo.cursor == cursor,"bound literal callback rejected without history")
	check(editor.status.text.contains("bound to a User"),"bound literal diagnostic")
	var snapshot: Dictionary = editor.module_payload("fixture")
	check(not snapshot.particle_module.has("user_parameters") and not JSON.stringify(snapshot).contains("input_bindings"),"actual mmg payload excludes User dependencies")
	check(editor.delete_input("fixture","bound"),"unused graph input with User sources can be deleted")
	await frames(60)
	check(Users.references(editor.document,added.user_id).is_empty(),"all bound instances cleaned including disabled and missing parameters dictionaries")
	check(editor.document.user_parameters.size() == 1,"definition remains after input deletion")
	check(editor.document.stages.spawn.all(func(i): return not i.get("parameters",{}).has("bound")) and editor.document.stages.update.all(func(i): return not i.get("input_bindings",{}).has("bound")),"constant and binding removed across both stages")
	check(editor.undoredo.cursor == cursor+1,"input deletion single undo")
	var compiled: Dictionary = await editor.compile_document()
	check(compiled.errors.is_empty() and compiled.effect.format_version == 2,"v2 compiles after cleanup")
	editor.undoredo.undo()
	await frames(60)
	check(editor.document == before and Users.references(editor.document,added.user_id).size() == 3,"undo restores all User connections and literals")
	editor.undoredo.redo()
	await frames(60)
	check(Users.references(editor.document,added.user_id).is_empty(),"redo cleans User references again")
	print("MODULAR_USER_BINDING_APP ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	get_tree().root.get_node("mm_globals").set_config("confirm_quit",false)
	get_tree().root.get_node("mm_globals").set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
