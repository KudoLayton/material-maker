extends RefCounted
const S = preload("standard_checks.gd")

static func search(dialog, text: String) -> void:
	dialog.search.text = text
	dialog.search.text_changed.emit(text)

static func load_document(editor, doc: Dictionary, stage: String, index: int = 0) -> void:
	while editor._loading: await editor.get_tree().process_frame
	editor.document = doc.duplicate(true)
	editor.stage = stage
	editor.stage_choice.select(0 if stage == "spawn" else 1)
	editor.selected = index
	editor.refresh_lists()
	await editor.load_selected()
	await S.frames(editor.get_tree(),40)
	editor.capture_graph()

static func run(editor, tree: SceneTree, check: Callable, screenshot: String = "") -> Dictionary:
	editor.capture_graph()
	var original := {"document":editor.document.duplicate(true),"stage":editor.stage,"selected":editor.selected}
	var doc := S.document(["initialize_particle","add_velocity_in_cone"],["gravity","solve_motion","color_over_life","scale_over_life"])
	await load_document(editor,doc,"update")
	check.call(is_instance_valid(editor.preview) and editor.preview.ready_for_simulation,"standard fixture preview ready")
	var before: Dictionary = editor.document.duplicate(true)
	var cursor: int = editor.undoredo.cursor
	var revision: int = editor._revision
	var preview = editor.preview
	editor.need_save = false
	editor.library_button.pressed.emit()
	await S.frames(tree,3)
	var dialog = editor.library_dialog
	check.call(is_instance_valid(dialog) and dialog.visible and dialog.search.has_focus(),"Browse opens searchable modal")
	if not is_instance_valid(dialog): return original
	check.call(dialog.items.item_count == 8,"current Update filter includes 7 new modules and legacy integrate")
	editor.show_library()
	check.call(editor.library_dialog == dialog,"only one Library dialog")
	search(dialog,"velocity cone")
	check.call(dialog.items.item_count == 0 and dialog.get_ok_button().disabled,"search combines terms and current Stage")
	dialog.stage_filter.select(1)
	dialog.stage_filter.item_selected.emit(1)
	check.call(dialog.items.item_count == 1 and dialog.selected_id() == "add_velocity_in_cone" and dialog.get_ok_button().disabled,"other Stage can be inspected but not added")
	dialog.stage_filter.select(3)
	dialog.stage_filter.item_selected.emit(3)
	search(dialog,"drag")
	for i in dialog.category.item_count:
		if dialog.category.get_item_text(i) == "Forces":
			dialog.category.select(i)
			dialog.category.item_selected.emit(i)
	check.call(dialog.items.item_count == 1 and dialog.selected_id() == "drag","category and search combined")
	check.call(dialog.details.text.contains("Module.Drag") and dialog.details.text.contains("Particle.Custom.Drag") and dialog.details.text.contains("seconds") and dialog.details.text.contains("Solve Motion"),"details show namespace, units, inputs, order")
	check.call(not dialog.get_ok_button().disabled,"compatible selection enabled")
	if not screenshot.is_empty():
		await S.frames(tree,2)
		dialog.get_texture().get_image().save_png(screenshot)
	dialog.get_cancel_button().pressed.emit()
	await S.frames(tree,3)
	check.call(not is_instance_valid(editor.library_dialog) and editor.document == before and editor.undoredo.cursor == cursor and not editor.need_save and editor.preview == preview and editor._revision == revision,"browse/cancel has no document/history/preview side effects")
	editor.show_library()
	await S.frames(tree,2)
	dialog = editor.library_dialog
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	dialog.push_input(escape)
	escape = escape.duplicate()
	escape.pressed = false
	if is_instance_valid(dialog): dialog.push_input(escape)
	await S.frames(tree,3)
	check.call(not is_instance_valid(editor.library_dialog) and editor.document == before and editor.undoredo.cursor == cursor,"Escape cancels without mutation")
	editor.show_library()
	await S.frames(tree,2)
	dialog = editor.library_dialog
	search(dialog,"drag")
	# Search may include other descriptions; select the precise catalog entry.
	for i in dialog.items.item_count:
		if dialog.items.get_item_metadata(i) == "drag": dialog.items.select(i)
	dialog.refresh_details()
	dialog.search.text_submitted.emit(dialog.search.text)
	await S.frames(tree,40)
	check.call(not is_instance_valid(editor.library_dialog),"Enter adds and closes Library")
	check.call(editor.document.stages.update.size() == before.stages.update.size()+1 and editor.selected == 1,"insertion immediately after selected row")
	var drag_instance: Dictionary = editor.document.stages.update[1]
	var drag_module: Dictionary = editor.document.modules[drag_instance.module]
	check.call(drag_module.standard_module.catalog_id == "drag" and editor.document.attributes == before.attributes,"existing semantic roles reused")
	check.call(editor.undoredo.cursor == cursor+1 and editor.need_save,"one history transaction for insertion")
	var after: Dictionary = editor.document.duplicate(true)
	editor.undoredo.undo()
	await S.frames(tree,30)
	check.call(editor.document == before,"Undo restores whole insertion")
	editor.undoredo.redo()
	await S.frames(tree,30)
	check.call(editor.document == after,"Redo restores IDs, graph, attributes, instance")
	check.call((await editor.compile_document()).errors.is_empty(),"inserted standard pipeline compiles")
	var first_module: String = drag_instance.module
	editor.selected = 1
	await editor.load_selected()
	check.call(editor.rename_module(first_module,"Drag 이름"),"standard module supports Rename")
	check.call(not editor.delete_input(first_module,"drag"),"referenced standard input remains protected")
	check.call(editor.add_library_module("drag","update"),"second independent catalog copy")
	await S.frames(tree,40)
	var second_module: String = editor.current_module
	check.call(second_module != first_module and editor.document.modules[second_module].name == "Drag" and editor.document.modules[first_module].name == "Drag 이름","catalog copy does not share renamed definition")
	var custom = editor.graph_edit.top_generator.get_node("Accumulate")
	check.call(custom.get_parameter_defs().any(func(p): return p.name == "code" and p.type == "string"),"safe formula is editable through existing text control")
	custom.set_parameter("code","return current+max(drag,0.0)*2.0;")
	editor.capture_graph()
	check.call((await editor.compile_document()).errors.is_empty() and editor.document.modules[first_module].mm_graph.nodes.filter(func(n): return n.name == "Accumulate")[0].parameters.get("code","") != "return current+max(drag,0.0)*2.0;","formula edit stays in independent copy")
	var payload: Dictionary = editor.module_payload(second_module)
	check.call(payload.particle_module.attributes.size() == 1,"Save mmg contains only required custom Attribute")
	var imported := S.L.merge_payload(S.D.create(),payload)
	check.call(imported.ok and imported.document.attributes.size() == 1,"saved mmg imports required role in empty document")
	check.call(not editor.add_library_module("box_location","update"),"incompatible direct insertion rejected")
	before = editor.document.duplicate(true)
	cursor = editor.undoredo.cursor
	editor._loading = true
	check.call(not editor.add_library_module("drag","update"),"insertion rejected during load")
	editor._loading = false
	check.call(not editor.add_library_module("drag","spawn") and editor.document == before and editor.undoredo.cursor == cursor,"stale Stage insertion is atomic")
	# Missing dependencies never insert companion modules or replace the valid preview.
	await load_document(editor,S.document([],[]),"update",-1)
	before = editor.document.duplicate(true)
	cursor = editor.undoredo.cursor
	preview = editor.preview
	editor.show_library()
	await S.frames(tree,2)
	dialog = editor.library_dialog
	search(dialog,"gravity")
	check.call(dialog.details.text.contains("Automatically created Attributes\nParticle.Custom.Acceleration"),"preview lists newly created Attribute")
	dialog.items.item_activated.emit(dialog.items.get_selected_items()[0])
	await S.frames(tree,40)
	check.call(editor.document.attributes.size() == 1 and editor.document.stages.update.size() == 1 and editor.document.stages.spawn.is_empty(),"double-click adds only requested module and Attribute")
	check.call(editor.undoredo.cursor == cursor+1,"Attribute plus module insertion is one Undo")
	check.call(editor.status.text.contains("Solve Motion") and editor.preview == preview,"dependency error retains last good GPU preview")
	check.call((await editor.compile_document()).effect == null,"invalid pipeline cannot export")
	editor.undoredo.undo()
	await S.frames(tree,30)
	check.call(editor.document == before,"Undo removes auto Attribute together with module")
	editor.undoredo.redo()
	await S.frames(tree,30)
	check.call(editor.document.attributes.size() == 1 and editor.status.text.contains("Solve Motion"),"Redo restores dependency diagnostic")
	check.call(editor.add_library_module("solve_motion","update"),"explicit Solve resolves missing dependency")
	await S.frames(tree,45)
	check.call(editor.status.text.begins_with("Ready") and editor.document.stages.update.size() == 2,"no hidden module insertion or reorder")
	check.call(editor.add_library_module("legacy_integrate_velocity","update"),"Legacy modules available from Library")
	await S.frames(tree,45)
	check.call(editor.status.text.begins_with("Ready") and editor.status.text.contains("Warning") and editor.status.text.contains("double integration"),"successful preview retains compatibility warning")
	editor.toggle_module()
	await S.frames(tree,40)
	check.call(not editor.status.text.contains("Warning"),"disabled writer clears warning")
	# Role collision: reject before capture, including dirty live graph edits.
	var bad: Dictionary = editor.document.attributes[0].duplicate(true)
	bad.id = S.D.uid()
	editor.document.attributes.append(bad)
	before = editor.document.duplicate(true)
	cursor = editor.undoredo.cursor
	var live_add = editor.graph_edit.top_generator.get_node("Add")
	live_add.set_parameter("op",1.0)
	var pending_graph: Dictionary = editor.graph_edit.top_generator.serialize()
	check.call(not editor.add_library_module("drag","update") and editor.document == before and editor.undoredo.cursor == cursor and editor.graph_edit.top_generator.serialize() == pending_graph,"ambiguous role insertion preserves pending live graph and history")
	live_add.set_parameter("op",0.0)
	editor.document.attributes.pop_back()
	return original

static func restore(editor, original: Dictionary) -> void:
	await load_document(editor,original.document,original.stage,original.selected)
