extends RefCounted
## Shared by the source UI test and the real packaged Windows release observer.
static func frames(tree: SceneTree, count: int) -> void:
	for i in count: await tree.process_frame

static func key(editor, echo: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.pressed = true
	event.echo = echo
	event.shift_pressed = shift
	editor.get_viewport().push_input(event)
	event = event.duplicate()
	event.pressed = false
	editor.get_viewport().push_input(event)

static func run(editor, tree: SceneTree, check: Callable, screenshot_path: String = "") -> Dictionary:
	editor.capture_graph()
	var original: Dictionary = editor.document.duplicate(true)
	var id: String = editor.current_module
	var old_name: String = original.modules[id].name
	var new_name := "Renamed Velocity 테스트"
	check.call(not editor.rename_button.disabled,"Rename enabled for selected module")
	var selection: int = editor.selected
	editor.selected = -1
	editor.update_rename_button()
	check.call(editor.rename_button.disabled,"Rename disabled with no selected module")
	editor.selected = selection
	editor.update_rename_button()
	editor.duplicate_module()
	await frames(tree,40)
	var compiled: Dictionary = await editor.compile_document()
	check.call(compiled.errors.is_empty(),"compile before rename")
	var before: Dictionary = editor.document.duplicate(true)
	var preview = editor.preview
	var graph = editor.graph_edit.top_generator
	var revision: int = editor._revision
	var cursor: int = editor.undoredo.cursor
	editor.need_save = false

	editor.rename_button.pressed.emit()
	await frames(tree,3)
	var dialog = editor.rename_dialog
	check.call(is_instance_valid(dialog) and dialog.visible,"Rename button opens dialog")
	if not is_instance_valid(dialog): return {}
	var input: LineEdit = dialog.get_node("Form/Name")
	check.call(input.text == old_name and input.has_focus() and input.has_selection(),"current name selected and focused")
	editor.show_rename_dialog()
	check.call(editor.rename_dialog == dialog,"only one rename dialog")
	input.text = "   \t "
	input.text_changed.emit(input.text)
	check.call(dialog.get_ok_button().disabled,"blank name disables confirmation")
	input.text_submitted.emit(input.text)
	await frames(tree,2)
	check.call(is_instance_valid(dialog) and dialog.visible and editor.document == before,"Enter cannot accept a blank name")
	check.call(not editor.rename_module(id,input.text) and not editor.rename_module("missing_module","Name"),"blank and missing module rejected")
	input.text = "Discard this name"
	input.text_changed.emit(input.text)
	dialog.get_cancel_button().pressed.emit()
	await frames(tree,3)
	check.call(not is_instance_valid(editor.rename_dialog) and editor.document == before and editor.undoredo.cursor == cursor and not editor.need_save,"cancel preserves document and history")

	var unrelated := LineEdit.new()
	editor.add_child(unrelated)
	unrelated.grab_focus()
	key(editor)
	await frames(tree,2)
	check.call(not is_instance_valid(editor.rename_dialog),"F2 outside stack does not rename module")
	unrelated.queue_free()
	editor.stack.grab_focus()
	key(editor,true)
	key(editor,false,true)
	await frames(tree,2)
	check.call(not is_instance_valid(editor.rename_dialog),"repeated and modified F2 ignored")
	editor.hide()
	key(editor)
	await frames(tree,2)
	check.call(not is_instance_valid(editor.rename_dialog),"inactive tab does not open dialog")
	editor.show()
	editor.stack.grab_focus()
	key(editor)
	await frames(tree,3)
	dialog = editor.rename_dialog
	check.call(is_instance_valid(dialog) and dialog.visible,"stack-focused F2 opens dialog")
	if not is_instance_valid(dialog): return {}
	input = dialog.get_node("Form/Name")
	input.text = "  " + new_name + "  "
	input.text_changed.emit(input.text)
	check.call(not dialog.get_ok_button().disabled,"valid name enables confirmation")
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		dialog.get_texture().get_image().save_png(screenshot_path)
	input.text_submitted.emit(input.text)
	await frames(tree,3)
	check.call(not is_instance_valid(editor.rename_dialog) and editor.document.modules[id].name == new_name,"Enter confirms trimmed Unicode name")
	check.call(editor.need_save and editor.undoredo.cursor == cursor+1,"rename marks dirty and records one history entry")
	var expected: Dictionary = before.duplicate(true)
	expected.modules[id].name = new_name
	check.call(editor.document == expected,"only name changes; stable IDs, inputs, graphs and stages preserved")
	var shared_rows := 0
	for i in editor.document.stages[editor.stage].size():
		if editor.document.stages[editor.stage][i].module == id:
			shared_rows += 1
			check.call(editor.stack.get_item_text(i).ends_with(new_name),"shared instance label refreshed")
	check.call(shared_rows >= 2,"shared definition tested with duplicate instances")
	for i in editor.module_choice.item_count:
		if editor.module_choice.get_item_metadata(i) == id:
			check.call(editor.module_choice.get_item_text(i) == new_name,"module chooser label refreshed")
	check.call(editor.module_payload(id).particle_module.definition.name == new_name,"mmg snapshot carries renamed definition")
	check.call(editor.preview == preview and editor.graph_edit.top_generator == graph and editor._revision == revision,"rename does not rebuild graph or restart GPU preview")
	var after: Dictionary = await editor.compile_document()
	check.call(after.errors.is_empty() and compiled.effect != null and after.effect != null and compiled.effect.source_hash == after.effect.source_hash,"display name does not change generated shader")
	cursor = editor.undoredo.cursor
	check.call(editor.rename_module(id,"  "+new_name+"  ") and editor.undoredo.cursor == cursor,"same trimmed name is a no-op")
	editor.undoredo.undo()
	await frames(tree,40)
	check.call(editor.document.modules[id].name == old_name,"rename Undo")
	editor.undoredo.redo()
	await frames(tree,40)
	check.call(editor.document.modules[id].name == new_name,"rename Redo")

	# Remove the test duplicate before saving/exporting the real effect.
	editor.selected = selection
	editor.apply_document(original)
	await frames(tree,40)
	editor.rename_button.pressed.emit()
	await frames(tree,3)
	dialog = editor.rename_dialog
	if is_instance_valid(dialog):
		input = dialog.get_node("Form/Name")
		input.text = new_name
		input.text_changed.emit(input.text)
		dialog.get_ok_button().pressed.emit()
	await frames(tree,3)
	check.call(not is_instance_valid(editor.rename_dialog) and editor.document.modules[id].name == new_name,"Rename confirmation button on original stack")
	return {"id":id,"name":new_name}
