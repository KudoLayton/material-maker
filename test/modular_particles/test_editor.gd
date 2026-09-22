extends Node
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int) -> void:
	for frame in count: await get_tree().process_frame
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames(30)
	get_tree().root.size = Vector2i(1400,900)
	var editor = window.new_modular_particles()
	await frames(40)
	# Explicit original workflow fixture; new-document defaults have their own tests.
	editor.apply_document(preload("res://material_maker/panels/modular_particles/library.gd").legacy_document())
	await frames(40)
	check(window.get_current_mode() == "material", "material layout")
	check(window.get_current_graph_edit() == editor.graph_edit, "existing MM graph canvas")
	check(editor.graph_edit.get_children().filter(func(n): return n is GraphNode).size() >= 2,"editable module graph nodes exist")
	var result: Dictionary = await editor.compile_document()
	check(result.errors.is_empty(), "MM graph backend: " + str(result.errors))
	if result.effect != null:
		check(not "@" in result.effect.compute_source,"kernel complete")
		var second: Dictionary = await editor.compile_document()
		check(second.effect.source_hash == result.effect.source_hash,"transient MM object IDs do not change code")
	for frame in 180:
		if is_instance_valid(editor.preview) and editor.preview.ready_for_simulation: break
		await get_tree().process_frame
	check(is_instance_valid(editor.preview),"GPU preview: " + editor.status.text)
	var payload: Dictionary = editor.module_payload("initialize_velocity")
	check(payload.has("particle_module") and payload.type == "graph","Library-compatible mmg metadata")
	payload.particle_module.definition.name = "Revised Velocity"
	check(editor.document.modules.initialize_velocity.name != "Revised Velocity","Library snapshot isolation")
	check(editor.load_module_data(payload),"explicit Library revision import")
	await frames(15)
	check(editor.document.modules.initialize_velocity.name == "Revised Velocity","Library revision applied explicitly")
	var instance_id: String = editor.document.stages.spawn[0].id
	var live_preview = editor.preview
	editor.set_input(instance_id,"velocity",[0.0,2.0,0.0])
	await frames(5)
	check(editor.preview == live_preview,"numeric input does not recreate simulation")
	editor.document.modules.initialize_velocity.stages = ["update"]
	await editor.refresh_preview()
	check(editor.preview == live_preview and editor.status.text.contains("not allowed"),"invalid compilation retains last valid preview and diagnostic")
	editor.document.modules.initialize_velocity.stages = ["spawn"]
	await editor.refresh_preview()
	var count: int = editor.document.stages.spawn.size()
	editor.duplicate_module()
	await frames(10)
	check(editor.document.stages.spawn.size() == count+1,"duplicate module")
	editor.undoredo.undo()
	await frames(10)
	check(editor.document.stages.spawn.size() == count,"stack undo")
	editor.undoredo.redo()
	await frames(10)
	check(editor.document.stages.spawn.size() == count+1,"stack redo")
	editor.toggle_module()
	check(not editor.document.stages.spawn[editor.selected].enabled,"disable module")
	editor.add_attribute("InitialVelocity","vec3",[0.0,0.0,0.0])
	var id: String = editor.document.attributes[0].id
	check(not id.is_empty(),"stable Attribute ID")
	editor.save_path = "res://editor_roundtrip.mpfx"
	check(await editor.save(),"save mpfx")
	check(await window.do_load_project("res://editor_roundtrip.mpfx"),"open mpfx")
	await frames(30)
	var reopened = window.get_current_project()
	check(reopened.document.attributes[0].id == id,"Attribute ID roundtrip")
	check(reopened.get_project_type() == "modular_particles","project type")
	await frames(30)
	reopened.capture_graph()
	check(await reopened.save(),"repeat save replaces authoring file safely")
	var old = await window.new_particle_shader()
	await frames(10)
	check(old is MMGraphEdit and old.get_material_node() is MMGenParticleMaterial,"legacy ptex editor preserved")
	window.projects_panel.get_projects().current_tab = reopened.get_index()
	await frames(20)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("res://editor.png")
	print("MODULAR_EDITOR ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	window.quit()
