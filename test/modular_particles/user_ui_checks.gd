extends RefCounted
## Shared by source app tests and the packaged Windows smoke test.
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Users = preload("res://addons/material_maker/particles/modular/user_parameters.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")

static func frames(tree: SceneTree, count: int = 35) -> void:
	for frame in count: await tree.process_frame

static func row(editor, id: String) -> Control:
	for child in editor.input_box.get_children():
		if not child.is_queued_for_deletion() and child.get_meta("module_input_id","") == id: return child
	return null

static func read_node(editor):
	for child in editor.graph_edit.get_children():
		if child is MMGraphNodeGeneric and child.generator != null and child.generator.name == "ReadPosition": return child
	return null

static func source_select(editor, id: String, user_id: String) -> void:
	var source: OptionButton = row(editor,id).get_node("InputSource")
	for index in source.item_count:
		if source.get_item_metadata(index) == user_id:
			source.select(index)
			source.item_selected.emit(index)
			return

static func gpu_snapshot(preview, tree: SceneTree) -> Dictionary:
	var result := {}
	var state = preview._gpu
	var effect = preview.effect
	var capacity: int = preview.capacity
	RenderingServer.call_on_render_thread(func():
		var bytes: PackedByteArray = state.rd.buffer_get_data(state.owned_buffers[0])
		var position: int = effect.attribute("position").offset*capacity*4
		result.position = Vector3(bytes.decode_float(position),bytes.decode_float(position+capacity*4),bytes.decode_float(position+capacity*8))
		result.age = bytes.decode_float(effect.attribute("age").offset*capacity*4)
		result.id = bytes.decode_u32(effect.attribute("particle_id").offset*capacity*4)
		result.done = true)
	while not result.has("done"): await tree.process_frame
	return result

static func run(editor, tree: SceneTree, check: Callable, directory: String = "user://") -> Dictionary:
	editor.capture_graph()
	var state := {"original":editor.document.duplicate(true),"stage":editor.stage,"selection":editor.selected}
	var doc := Document.create()
	doc.preview_capacity = 8
	doc.emitter = {"rate":0.0,"duration":20.0,"loop":true,"bursts":[{"time":0.0,"count":2}],"lifetime":20.0}
	var module := Library.definition("User fixture",["spawn","update"],[{"id":"position","name":"Position","type":"vec3"}])
	module.catalog_snapshot = true
	module.inputs = [{"id":"position_input","name":"Position","type":"vec3","default":[-1.0,0.0,0.0]},{"id":"strength","name":"Strength","type":"float","default":4.0}]
	module.mm_graph.nodes.append(Library.binding("ReadPosition","module_parameter","position_input","vec3",Vector2(-200,0)))
	module.mm_graph.connections.append(Library.connect_nodes("ReadPosition","Output",0))
	doc.modules.fixture = module
	doc.stages.spawn = [{"id":"first","module":"fixture","parameters":{"position_input":[-2.0,0.0,0.0]}},{"id":"second","module":"fixture","enabled":false}]
	doc.stages.update = [{"id":"update","module":"fixture"}]
	editor.stage = "spawn"
	editor.stage_choice.select(0)
	editor.selected = 0
	editor.apply_document(doc)
	await frames(tree,60)
	check.call(editor.document.version == 1 and not editor.document.has("user_parameters"),"opening panel does not migrate v1")
	var panel = editor.user_panel
	check.call(panel.tree.get_root().get_child_count() == 0,"empty User panel")
	editor.capture_graph()
	var before: Dictionary = editor.document.duplicate(true)
	var cursor: int = editor.undoredo.cursor
	editor.need_save = false
	panel.show_dialog("Add")
	check.call(is_instance_valid(panel.dialog) and panel.dialog.visible,"Add opens User dialog")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel.dialog.get_viewport().push_input(escape)
	await frames(tree,3)
	check.call(not is_instance_valid(panel.dialog),"Escape cancels User dialog")
	check.call(editor.document == before and editor.undoredo.cursor == cursor and not editor.need_save,"cancel leaves document/history/dirty unchanged")
	panel.show_dialog("Add")
	panel.dialog.get_node("Form/Name").text = "Bad Name"
	panel.dialog.confirmed.emit()
	check.call(is_instance_valid(panel.dialog) and not panel.dialog.get_node("Form/Error").text.is_empty() and editor.document == before,"invalid name rejected in dialog")
	panel.dialog.get_node("Form/Name").text = "Position"
	var types: OptionButton = panel.dialog.get_node("Form/Type")
	for index in types.item_count:
		if types.get_item_text(index) == "vec3": types.select(index)
	panel.dialog.get_node("Form/Default").text = "[1,0,0]"
	panel.dialog.confirmed.emit()
	await frames(tree)
	var user_id: String = panel.selected_id
	check.call(editor.document.version == 2 and editor.document.user_parameters.size() == 1,"successful add upgrades v2")
	check.call(editor.undoredo.cursor == cursor+1 and editor.need_save,"add is one undo operation")
	check.call(editor.document.stages.spawn[0].get("input_bindings",{}).is_empty(),"same Module/User name never auto-binds")
	check.call(editor.user_operation("add",["Intensity","float",2.0]),"add different User type")
	await frames(tree)
	var source: OptionButton = row(editor,"position_input").get_node("InputSource")
	check.call(source.item_count == 2 and source.get_item_metadata(1) == user_id,"binding dropdown filters exact types")
	check.call(row(editor,"strength").get_node("InputSource").item_count == 2,"float dropdown excludes vec3 User")
	var unused_id: String = panel.selected_id
	before = editor.document.duplicate(true)
	cursor = editor.undoredo.cursor
	panel.show_dialog("Value",unused_id)
	panel.dialog.get_node("Form/Default").text = "{"
	panel.dialog.confirmed.emit()
	check.call(editor.document == before and panel.dialog.get_node("Form/Error").text.contains("JSON"),"invalid JSON default is a no-op")
	panel.dialog.get_node("Form/Default").text = "true"
	panel.dialog.confirmed.emit()
	check.call(editor.document == before and editor.undoredo.cursor == cursor,"wrong typed default is a no-op")
	panel.dialog.canceled.emit()
	await frames(tree,3)
	panel.show_dialog("Rename",unused_id)
	panel.dialog.get_node("Form/Name").text = "Position"
	panel.dialog.confirmed.emit()
	check.call(editor.document == before and editor.undoredo.cursor == cursor,"duplicate name rejected without dirty/history changes")
	panel.dialog.canceled.emit()
	await frames(tree,3)
	panel.show_dialog("Type",unused_id)
	types = panel.dialog.get_node("Form/Type")
	for index in types.item_count:
		if types.get_item_text(index) == "vec2": types.select(index)
	panel.dialog.get_node("Form/Default").text = "[7,8]"
	panel.dialog.confirmed.emit()
	await frames(tree)
	check.call(Users.definition(editor.document,unused_id).type == "vec2" and Users.definition(editor.document,unused_id).default == [7.0,8.0],"unused type/default changed atomically through dialog")
	check.call(row(editor,"strength").get_node("InputSource").item_count == 1,"type edit refreshes compatible source choices")
	panel.select_user(unused_id)
	cursor = editor.undoredo.cursor
	panel.find_child("Delete",true,false).pressed.emit()
	await frames(tree)
	check.call(Users.definition(editor.document,unused_id).is_empty() and editor.undoredo.cursor == cursor+1,"unused User Delete button records one action")
	editor.undoredo.undo()
	await frames(tree)
	check.call(Users.definition(editor.document,unused_id).type == "vec2" and editor.preview.get_user_parameter("User.Intensity") == Vector2(7,8),"delete Undo restores same ID/type/default")
	editor.undoredo.redo()
	await frames(tree)
	check.call(Users.definition(editor.document,unused_id).is_empty() and editor.preview.get_user_parameter("User.Intensity") == null,"delete Redo removes metadata and stale preview override")
	cursor = editor.undoredo.cursor
	source_select(editor,"position_input",user_id)
	await frames(tree)
	check.call(Users.references(editor.document,user_id).size() == 1 and editor.undoredo.cursor == cursor+1,"source dropdown creates one binding transaction")
	check.call(not row(editor,"position_input").get_node("InputValue").editable,"bound constant editor read-only")
	check.call(row(editor,"position_input").get_node("InputLabel").text.contains("User.Position"),"input row shows User source")
	check.call(read_node(editor).title.contains("Module.Position") and read_node(editor).tooltip_text.contains("Source: User.Position"),"graph identity remains Module with source tooltip")
	check.call(editor.user_operation("bind",["update","position_input",user_id]),"one User shared across stages")
	await frames(tree)
	panel.select_user(user_id)
	check.call(panel.details.text.contains("spawn") and panel.details.text.contains("update"),"reference details enumerate stages")
	editor.selected = 1
	editor.load_selected()
	await frames(tree)
	check.call(row(editor,"position_input").get_node("InputValue").editable and read_node(editor).tooltip_text.contains("Source: Constant"),"same module other instance has independent source display")
	editor.selected = 0
	editor.load_selected()
	await frames(tree)
	check.call(read_node(editor).tooltip_text.contains("Source: User.Position"),"switching back restores correct instance context")
	editor.capture_graph()
	before = editor.document.duplicate(true)
	cursor = editor.undoredo.cursor
	var preview = editor.preview
	check.call(not editor.user_operation("remove",[user_id]) and editor.status.text.contains("Module.Position"),"used deletion rejected with references")
	check.call(not editor.user_operation("change",[user_id,{"type":"float","default":1.0}]),"used type change rejected")
	check.call(editor.document == before and editor.undoredo.cursor == cursor and editor.preview == preview,"rejected changes preserve history and preview")
	preview.manual_processing = true
	await frames(tree,3)
	var first := await gpu_snapshot(preview,tree)
	check.call(first.position == Vector3(1,0,0),"initial bound User reaches GPU")
	var generation: int = preview._generation
	var buffers: Array = preview._gpu.owned_buffers.duplicate()
	row(editor,"position_input").get_node("EditUser").pressed.emit()
	check.call(is_instance_valid(panel.dialog) and panel.dialog.get_node("Form/Name").text == "Position","Edit User opens the referenced definition")
	panel.dialog.get_node("Form/Default").text = "[2,3,4]"
	panel.dialog.confirmed.emit()
	await frames(tree,40)
	check.call(editor.preview == preview and preview._generation == generation and preview._gpu.owned_buffers == buffers,"value-only edit reuses GPU state and buffers")
	check.call(preview.get_user_parameter("User.Position") == Vector3(2,3,4),"runtime override reflects editor value")
	check.call(preview.effect.user_parameter("User.Position").default == [2.0,3.0,4.0],"preview resource metadata/defaults synchronized")
	preview.advance(1.0/60.0)
	await frames(tree,3)
	var changed := await gpu_snapshot(preview,tree)
	check.call(changed.position == Vector3(2,3,4) and changed.id == first.id and absf(changed.age-first.age-1.0/60.0)<0.00001,"next step changes live particle without resetting age/ID")
	editor.undoredo.undo()
	await frames(tree,50)
	check.call(editor.preview == preview and preview.get_user_parameter("User.Position") == Vector3(1,0,0),"User value Undo reuses simulation")
	editor.undoredo.redo()
	await frames(tree,50)
	check.call(editor.preview == preview and preview.get_user_parameter("User.Position") == Vector3(2,3,4),"User value Redo reuses simulation")
	panel.show_dialog("Rename",user_id)
	check.call(panel.dialog.get_node("Form/Name").text == "Position","rename edits raw name, not namespace")
	panel.dialog.get_node("Form/Name").text = "Wind"
	panel.dialog.confirmed.emit()
	await frames(tree,40)
	check.call(Users.definition(editor.document,user_id).name == "Wind" and editor.document.stages.spawn[0].input_bindings.position_input.id == user_id,"rename keeps connection ID")
	check.call(editor.preview == preview and preview.get_user_parameter("User.Wind") == Vector3(2,3,4) and preview.get_user_parameter("User.Position") == null,"rename refreshes preview lookup without rebuild")
	check.call(read_node(editor).tooltip_text.contains("Source: User.Wind"),"rename refreshes graph tooltip")
	var snapshot: Dictionary = editor.module_payload("fixture")
	check.call(not JSON.stringify(snapshot).contains("input_bindings") and not JSON.stringify(snapshot).contains("User.Wind"),"mmg does not serialize effect binding/display context")
	var file: String = directory.path_join("user-ui.mpfx")
	check.call(Document.save_file(file,editor.document) == OK,"save v2 editor document")
	check.call(await editor.load_project(file),"reload v2 editor document")
	await frames(tree,50)
	check.call(editor.document.stages.spawn[0].input_bindings.position_input.id == user_id and read_node(editor).tooltip_text.contains("User.Wind"),"save/open retains IDs and source UI")
	cursor = editor.undoredo.cursor
	source_select(editor,"position_input","")
	await frames(tree)
	check.call(editor.document.stages.spawn[0].parameters.position_input == [-2.0,0.0,0.0] and row(editor,"position_input").get_node("InputValue").editable,"Constant restores previous literal")
	check.call(editor.undoredo.cursor == cursor+1,"unbind single undo")
	editor.undoredo.undo()
	await frames(tree)
	check.call(editor.document.stages.spawn[0].input_bindings.position_input.id == user_id,"unbind undo restores exact User ID")
	var valid: Dictionary = editor.document.duplicate(true)
	var invalid: Dictionary = valid.duplicate(true)
	invalid.stages.spawn[0].input_bindings.position_input.id = "missing_user"
	preview = editor.preview
	editor.apply_document(invalid)
	await frames(tree,50)
	check.call(editor.status.text.contains("Missing User") and editor.preview == preview and preview.ready_for_simulation,"bad reference retains last good GPU preview")
	check.call(row(editor,"position_input").get_node("InputSource").get_item_text(row(editor,"position_input").get_node("InputSource").selected).contains("Missing"),"Missing shown without constant fallback")
	var bad_result: Dictionary = await editor.compile_document()
	check.call(bad_result.effect == null and not bad_result.errors.is_empty(),"invalid User binding blocks export compilation")
	source_select(editor,"position_input",user_id)
	await frames(tree,45)
	check.call(editor.status.text.begins_with("Ready"),"explicit rebind repairs Missing reference")
	preview = editor.preview
	var revision: int = editor._revision
	for value in [[4.0,5.0,6.0],[7.0,8.0,9.0],[0.2,0.3,0.0]]:
		check.call(editor.user_operation("change",[user_id,{"default":value}]),"rapid default edit accepted")
	check.call(editor._revision == revision+3,"each User mutation invalidates pending compile results")
	await frames(tree,55)
	check.call(editor.preview == preview and preview.get_user_parameter("User.Wind").is_equal_approx(Vector3(0.2,0.3,0)) and preview.effect.user_parameter("User.Wind").default == [0.2,0.3,0.0],"latest rapid value wins in override and compiled preview metadata")
	panel.select_user(user_id)
	if not directory.is_empty():
		RenderingServer.force_draw()
		tree.root.get_texture().get_image().save_png(directory.path_join("user-editor.png"))
		var scroll: ScrollContainer = editor.input_box.get_parent().get_parent()
		scroll.ensure_control_visible(row(editor,"position_input"))
		await frames(tree,3)
		RenderingServer.force_draw()
		tree.root.get_texture().get_image().save_png(directory.path_join("user-bindings.png"))
	return state

static func restore(editor, state: Dictionary, tree: SceneTree) -> void:
	editor.stage = state.stage
	editor.stage_choice.select(0 if state.stage == "spawn" else 1)
	editor.selected = state.selection
	editor.apply_document(state.original)
	await frames(tree,50)
