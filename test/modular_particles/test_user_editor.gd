extends Node
const Checks = preload("user_ui_checks.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await Checks.frames(get_tree(),30)
	get_tree().root.size = Vector2i(1440,960)
	var editor = window.new_modular_particles()
	await Checks.frames(get_tree(),50)
	var state := await Checks.run(editor,get_tree(),check,"res://")
	await Checks.restore(editor,state,get_tree())
	print("MODULAR_USER_EDITOR ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
