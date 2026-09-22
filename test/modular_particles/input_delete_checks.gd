extends RefCounted
## Shared checks for the source editor and the actual packaged Windows EXE.
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
const MODULE := "delete_test_module"
const OTHER := "delete_other_module"
const INPUT := "delete_test_value"
const KEEP := "delete_keep_value"

static func frames(tree: SceneTree, count: int) -> void:
	for i in count: await tree.process_frame

static func delete_button(editor, id: String) -> Button:
	for row in editor.input_box.get_children():
		if row.is_queued_for_deletion(): continue
		for child in row.get_children():
			if child is Button and child.get_meta("module_input_id","") == id: return child
	return null

static func nested(name: String, children: Array) -> Dictionary:
	return {"type":"graph","name":name,"nodes":children + [
		{"name":"gen_inputs","type":"ios","ports":[]},
		{"name":"gen_outputs","type":"ios","ports":[]},
		{"name":"gen_parameters","type":"remote","widgets":[]}],"connections":[]}

static func run(editor, tree: SceneTree, check: Callable, screenshot_path: String = "") -> Dictionary:
	editor.capture_graph()
	var original: Dictionary = editor.document.duplicate(true)
	var selection: int = editor.selected
	var original_stage: String = editor.stage
	var setup: Dictionary = original.duplicate(true)
	var module := Library.definition("Input deletion test",["spawn","update"],[{"id":"velocity","name":"Velocity","type":"vec3"}])
	module.inputs = [{"id":KEEP,"name":"Keep","type":"float","default":1.0},
		{"id":INPUT,"name":"Delete Me","type":"vec3","default":[1.0,2.0,3.0]}]
	setup.modules[MODULE] = module
	setup.modules[OTHER] = module.duplicate(true)
	# The same input ID referenced by a DIFFERENT module must not block deletion.
	setup.modules[OTHER].mm_graph.nodes.append(Library.binding("OtherRead","module_parameter",INPUT,"vec3"))
	setup.stages.spawn.append_array([
		{"id":"delete_s0","module":MODULE,"parameters":{INPUT:[2.0,3.0,4.0],KEEP:42.0},"enabled":true},
		{"id":"delete_s1","module":MODULE,"parameters":{INPUT:[4.0,5.0,6.0],KEEP:43.0},"enabled":false},
		{"id":"delete_s2","module":MODULE,"parameters":{},"enabled":true}])
	setup.stages.update.append_array([
		{"id":"delete_u0","module":MODULE,"parameters":{INPUT:[7.0,8.0,9.0],KEEP:44.0},"enabled":true},
		{"id":"delete_other","module":OTHER,"parameters":{INPUT:[10.0,11.0,12.0],KEEP:45.0},"enabled":true}])
	editor.stage = "spawn"
	editor.stage_choice.select(0)
	editor.selected = setup.stages.spawn.size()-3
	editor.apply_document(setup.duplicate(true))
	await frames(tree,45)
	check.call(delete_button(editor,INPUT) != null,"each input has a Delete button")
	check.call(not editor.delete_input(OTHER,INPUT) and not editor.delete_input(MODULE,"missing"),"stale module and unknown input callbacks ignored")
	editor._loading = true
	check.call(not editor.delete_input(MODULE,INPUT),"deletion ignored while changing modules")
	editor._loading = false

	# Connected and nested/disconnected bindings both protect the definition.
	for kind in ["connected","nested"]:
		var with_read: Dictionary = setup.duplicate(true)
		var read := Library.binding("ProtectedRead","module_parameter",INPUT,"vec3")
		if kind == "connected":
			with_read.modules[MODULE].mm_graph.nodes.append(read)
			with_read.modules[MODULE].mm_graph.connections.append(Library.connect_nodes("ProtectedRead","Output",0))
		else:
			with_read.modules[MODULE].mm_graph.nodes.append(nested("Outer",[nested("Inner",[read])]))
		editor.apply_document(with_read)
		await frames(tree,45)
		editor.capture_graph()
		var before: Dictionary = editor.document.duplicate(true)
		var cursor: int = editor.undoredo.cursor
		var preview = editor.preview
		editor.need_save = false
		delete_button(editor,INPUT).pressed.emit()
		check.call(editor.document == before and editor.undoredo.cursor == cursor and not editor.need_save and editor.preview == preview,"referenced deletion is a no-op: " + kind)
		check.call(editor.status.text.contains("ProtectedRead") and (kind != "nested" or editor.status.text.contains("Outer/Inner")),"reference diagnostic identifies node path: " + kind)

	var ir := {"nodes":[{"id":"TypedRead","op":"parameter","parameter":INPUT}]}
	check.call(Library.input_reference(ir,INPUT).ends_with("TypedRead"),"typed IR references are detected")
	check.call(Library.input_reference(Library.binding("Attribute","module_read",INPUT,"vec3"),INPUT).is_empty(),"same-ID Attribute Read is not a module input reference")

	# A just-created, unconnected Read exists only in the live graph until capture.
	editor.apply_document(setup.duplicate(true))
	await frames(tree,45)
	editor.capture_graph()
	var created: Array = await editor.graph_edit.create_nodes(Library.binding("LiveRead","module_parameter",INPUT,"vec3"))
	editor.refresh_timer.stop()
	check.call(created.size() == 1,"live Read node added on the existing graph canvas")
	var pending: Dictionary = editor.document.duplicate(true)
	var pending_cursor: int = editor.undoredo.cursor
	check.call(Library.input_reference(pending.modules[MODULE].mm_graph,INPUT).is_empty(),"live Read has not been saved to the definition yet")
	check.call(not editor.delete_input(MODULE,INPUT) and editor.status.text.contains("LiveRead"),"unsaved unconnected Read blocks deletion")
	check.call(editor.document == pending and editor.undoredo.cursor == pending_cursor,"blocked live-graph deletion does not capture or mutate history")
	if not created.is_empty(): editor.graph_edit.remove_node(created[0])
	editor.refresh_timer.stop()
	editor.capture_graph()
	var before: Dictionary = editor.document.duplicate(true)
	var compiled: Dictionary = await editor.compile_document()
	check.call(compiled.errors.is_empty(),"compile before deleting unused input")
	await editor.refresh_preview()
	await frames(tree,30)
	var cursor: int = editor.undoredo.cursor
	editor.need_save = false
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png(screenshot_path)
	delete_button(editor,INPUT).pressed.emit()
	var expected: Dictionary = before.duplicate(true)
	expected.modules[MODULE].inputs = expected.modules[MODULE].inputs.filter(func(input): return input.id != INPUT)
	for stage in ["spawn","update"]:
		for instance in expected.stages[stage]:
			if instance.module == MODULE: instance.parameters.erase(INPUT)
	check.call(editor.document == expected,"delete changes only the shared definition and matching instance overrides in both stages")
	check.call(editor.need_save and editor.undoredo.cursor == cursor+1,"delete marks dirty and records one undo entry")
	await frames(tree,50)
	check.call(delete_button(editor,INPUT) == null and delete_button(editor,KEEP) != null,"input rows refresh without removing unrelated inputs")
	var after: Dictionary = await editor.compile_document()
	check.call(after.errors.is_empty(),"deleted overrides do not cause compiler errors")
	check.call(compiled.effect != null and after.effect != null and compiled.effect.source_hash == after.effect.source_hash,"unused-input fixture keeps the same shader hash")
	check.call(is_instance_valid(editor.preview) and editor.preview.ready_for_simulation,"preview is ready after input deletion")
	if is_instance_valid(editor.preview):
		check.call(editor.parameter_layout(editor.preview.effect) == editor.parameter_layout(after.effect),"preview buffer layout updates even with identical shader text")
		check.call(not editor.preview.set_parameter("delete_s0/"+INPUT,[1.0,2.0,3.0]),"deleted runtime input is no longer accepted")
	check.call(not editor.module_payload(MODULE).particle_module.definition.inputs.any(func(input): return input.id == INPUT),"mmg snapshot omits deleted input")

	editor.undoredo.undo()
	await frames(tree,50)
	check.call(editor.document == before,"Undo restores definition, order and all per-instance values")
	check.call(delete_button(editor,INPUT) != null and editor.preview.set_parameter("delete_s0/"+INPUT,[2.0,3.0,4.0]),"Undo restores UI and runtime input layout")
	editor.undoredo.redo()
	await frames(tree,50)
	check.call(editor.document == expected and delete_button(editor,INPUT) == null,"Redo removes definition and overrides again")
	cursor = editor.undoredo.cursor
	check.call(not editor.delete_input(MODULE,INPUT) and editor.undoredo.cursor == cursor,"repeated deletion is a no-op")
	var preview_id: int = editor.preview.get_instance_id()
	editor.set_input("delete_s0",KEEP,99.0)
	await editor.refresh_preview()
	await frames(tree,20)
	check.call(editor.preview.get_instance_id() == preview_id,"ordinary value edits still reuse the simulation")
	return {"original":original,"selection":selection,"stage":original_stage,"module_id":MODULE,"input_id":INPUT}

static func restore(editor, state: Dictionary, tree: SceneTree) -> void:
	editor.stage = state.stage
	editor.stage_choice.select(0 if state.stage == "spawn" else 1)
	editor.selected = state.selection
	editor.apply_document(state.original)
	await frames(tree,45)
