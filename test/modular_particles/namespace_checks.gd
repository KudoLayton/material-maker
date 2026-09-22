extends RefCounted
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
const MODULE := "namespace_spawn"
const CUSTOM := "custom_position"
const INPUT := "manual_position"
const RENAMED := "Renamed Position : 테스트"

static func frames(tree: SceneTree, count: int) -> void:
	for i in count: await tree.process_frame

static func ui_node(editor, name: String):
	for node in editor.graph_edit.get_children():
		if node is MMGraphNodeGeneric and node.generator.name == name: return node
	return null

static func attribute_item(editor, id: String) -> TreeItem:
	for item in editor.attributes_tree.get_root().get_children():
		if item.get_metadata(0) == id: return item
	return null

static func choose_attribute(editor, id: String) -> void:
	for index in editor.attribute_choice.item_count:
		if editor.attribute_choice.get_item_metadata(index).id == id:
			editor.attribute_choice.select(index)
			editor.attribute_choice.item_selected.emit(index)
			return

static func focused_line(node: Node) -> LineEdit:
	if node is LineEdit and node.has_focus(): return node
	for child in node.get_children(true):
		var result := focused_line(child)
		if result != null: return result
	return null

static func fixture() -> Dictionary:
	var doc := Library.legacy_document()
	doc.emitter.rate = 0.0
	doc.attributes = [{"id":CUSTOM,"name":"Position","type":"vec3","default":[0.0,0.0,0.0]},
		{"id":"copy","name":"StoredPositionCopy","type":"vec3","default":[0.0,0.0,0.0]},
		{"id":"12345678a","name":"Duplicate","type":"vec4","default":[0.0,0.0,0.0,0.0]},
		{"id":"12345678b","name":"Duplicate","type":"vec4","default":[0.0,0.0,0.0,0.0]}]
	var module := Library.definition("Namespace examples",["spawn"],[{"id":"position","name":"Old builtin label","type":"vec3"},{"id":CUSTOM,"name":"Old custom label","type":"vec3"}])
	module.mm_graph.nodes[0].node_position = {"x":80.0,"y":100.0}
	module.inputs = [{"id":INPUT,"name":"Position","type":"vec3","default":[5.0,6.0,7.0]},
		{"id":"literal","name":"Particle.Position.한글 " + "Long".repeat(20),"type":"float","default":1.0}]
	module.mm_graph.nodes.append_array([
		Library.binding("Input","module_parameter",INPUT,"vec3",Vector2(-350,0)),
		Library.binding("BuiltinRead","module_read","position","vec3",Vector2(-350,180)),
		Library.binding("CustomRead","module_read",CUSTOM,"vec3",Vector2(-350,360)),
		{"type":"graph","name":"Nested","node_position":{"x":100,"y":360},"nodes":[
			Library.binding("NestedRead","module_read",CUSTOM,"vec3"),
			{"name":"gen_inputs","type":"ios","ports":[]},{"name":"gen_outputs","type":"ios","ports":[]},
			{"name":"gen_parameters","type":"remote","widgets":[]}],"connections":[]}])
	module.mm_graph.connections = [Library.connect_nodes("Input","Output",1)]
	module.merge(Library.contracts(module.mm_graph),true)
	var update := Library.definition("Copy custom state",["update"],[{"id":"copy","name":"StoredPositionCopy","type":"vec3"}])
	update.mm_graph.nodes.append_array([Library.binding("CopyRead","module_read",CUSTOM,"vec3"),Library.binding("Delta","module_context","delta","float")])
	update.mm_graph.connections = [Library.connect_nodes("CopyRead","Output",0)]
	update.merge(Library.contracts(update.mm_graph),true)
	doc.modules[MODULE] = module
	doc.modules["namespace_update"] = update
	doc.stages = {"spawn":[{"id":"namespace_instance","module":MODULE,"parameters":{}}],"update":[{"id":"namespace_update_instance","module":"namespace_update","parameters":{}}]}
	return doc

static func gpu_check(effect: MMParticleEffect, tree: SceneTree, check: Callable) -> void:
	var particles := Particles.new()
	particles.manual_processing = true
	particles.capacity = 4
	particles.effect = effect
	tree.root.add_child(particles)
	for i in 120:
		await tree.process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check.call(particles.ready_for_simulation,"namespace fixture GPU initialization")
	if particles.ready_for_simulation:
		particles.emit_burst(1)
		particles.advance(1.0/60.0)
		await frames(tree,5)
		var snapshot := {}
		var gpu = particles._gpu
		RenderingServer.call_on_render_thread(func():
			snapshot.data = gpu.rd.buffer_get_data(gpu.owned_buffers[0])
			snapshot.instances = gpu.rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(gpu.multimesh.get_rid()))
			snapshot.commands = gpu.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(gpu.multimesh.get_rid()))
			snapshot.done = true)
		while not snapshot.has("done"): await tree.process_frame
		check.call(snapshot.commands.decode_u32(4) == 1,"namespace fixture produced one live particle")
		for id in ["position",CUSTOM,"copy"]:
			var values := []
			for component in 3: values.append(snapshot.data.decode_float((int(effect.attribute(id).offset)+component)*4*4))
			check.call(values == ([0.0,0.0,0.0] if id == "position" else [5.0,6.0,7.0]),"GPU attribute identity: " + id)
		check.call(snapshot.instances.decode_float(3*4) == 0.0 and snapshot.instances.decode_float(7*4) == 0.0 and snapshot.instances.decode_float(11*4) == 0.0,"custom Position read/write never aliases rendered builtin Position")
	particles.queue_free()
	await frames(tree,10)

static func run(editor, tree: SceneTree, check: Callable, screenshot_path: String = "") -> Dictionary:
	editor.capture_graph()
	var original: Dictionary = editor.document.duplicate(true)
	var original_stage: String = editor.stage
	var original_selection: int = editor.selected
	editor.stage = "spawn"
	editor.stage_choice.select(0)
	editor.selected = 0
	editor.apply_document(fixture())
	await frames(tree,50)
	check.call(editor.attributes_tree.columns == 3,"namespace/name/type columns")
	var builtin := attribute_item(editor,"position")
	var custom := attribute_item(editor,CUSTOM)
	check.call(builtin.get_text(0) == "Particle" and builtin.get_text(1) == "Position" and not builtin.is_editable(1),"builtin row remains readonly")
	check.call(custom.get_text(0) == "Particle.Custom" and custom.get_text(1) == "Position" and custom.is_editable(1) and not custom.is_editable(0) and not custom.is_editable(2),"only raw custom Name cell is editable")
	check.call(attribute_item(editor,"12345678a").get_text(2).contains("[#12345678a]") and attribute_item(editor,"12345678b").get_text(2).contains("[#12345678b]"),"duplicate identity badges are outside editable names")
	choose_attribute(editor,CUSTOM)
	await frames(tree,3)
	check.call(editor.attribute_choice.get_item_text(editor.attribute_choice.selected) == "Particle.Custom.Position : vec3","qualified Attribute selector")
	check.call(editor.binding_details.text.contains("Renderer: Not bound") and editor.binding_details.text.contains("Module Output: Connected"),"details separate origin, render binding and graph write")
	check.call(ui_node(editor,"Input").title == "Read Module.Position" and ui_node(editor,"BuiltinRead").title == "Read Particle.Position" and ui_node(editor,"CustomRead").title == "Read Particle.Custom.Position","three same-name node sources are distinct")
	var sink = ui_node(editor,"Output")
	check.call(sink.generator.get_input_defs()[0].label == "Write Particle.Position" and sink.generator.get_input_defs()[1].label == "Write Particle.Custom.Position","qualified write ports")
	check.call(sink.generator.get_input_defs()[0].tooltip.contains("Unconnected") and sink.generator.get_input_defs()[1].tooltip.contains("Connected"),"write registration is not confused with connection")
	check.call(sink.get_child(0).get_child(0).tooltip_text.contains("Stable ID: position"),"port tooltip reaches the existing Generic node UI")
	var row = editor.input_box.get_child(0)
	check.call(row.get_node("InputLabel").text == "Module.Position : vec3","module input row uses the same namespace")
	var literal_label: Label = editor.input_box.get_child(1).get_node("InputLabel")
	check.call(literal_label.text.contains("…") and literal_label.tooltip_text.contains("Module.Particle.Position.한글"),"long literal names are shortened without interpreting prefixes")

	editor.capture_graph()
	var document: Dictionary = editor.document.duplicate(true)
	var serialized: Dictionary = editor.graph_edit.top_generator.serialize().duplicate(true)
	var before: Dictionary = await editor.compile_document()
	var history: int = editor.undoredo.cursor
	var preview_id: int = editor.preview.get_instance_id()
	var revision: int = editor._revision
	editor.need_save = false
	for i in 3: editor.refresh_binding_display()
	await frames(tree,5)
	check.call(editor.document == document and editor.graph_edit.top_generator.serialize() == serialized,"display refresh never writes labels or namespaces into authoring data")
	check.call(not editor.need_save and editor.undoredo.cursor == history and editor._revision == revision and editor.preview.get_instance_id() == preview_id,"display refresh leaves dirty/history/preview unchanged")
	var after: Dictionary = await editor.compile_document()
	check.call(before.errors.is_empty() and after.errors.is_empty() and before.effect.source_hash == after.effect.source_hash and before.effect.attributes == after.effect.attributes and before.effect.parameters == after.effect.parameters,"display has identical shader hash and storage layouts")
	await gpu_check(after.effect,tree,check)
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png(screenshot_path)

	# Edit the actual Tree Name cell, not a test-only rename API.
	custom.select(1)
	editor.attributes_tree.grab_focus()
	editor.attributes_tree.ensure_cursor_is_visible()
	check.call(editor.attributes_tree.edit_selected(),"custom Name cell enters inline editing")
	await frames(tree,3)
	var text := focused_line(editor.attributes_tree)
	check.call(text != null and text.text == "Position","inline editor receives raw name without a namespace or type suffix")
	if text != null:
		text.text = RENAMED
		text.text_submitted.emit(text.text)
	await frames(tree,40)
	check.call(editor.document.attributes[0].name == RENAMED,"raw name containing colon/Unicode persists verbatim")
	check.call(ui_node(editor,"CustomRead").title == "Read Particle.Custom."+RENAMED and ui_node(editor,"Output").generator.get_input_defs()[1].label == "Write Particle.Custom."+RENAMED,"node and output labels resolve current definitions instead of stale cached labels")
	check.call(ui_node(editor,"BuiltinRead").title == "Read Particle.Position","custom rename never renames builtin")
	editor.undoredo.undo()
	await frames(tree,40)
	check.call(ui_node(editor,"CustomRead").title == "Read Particle.Custom.Position","Undo refreshes names")
	editor.undoredo.redo()
	await frames(tree,40)
	check.call(ui_node(editor,"CustomRead").title.ends_with(RENAMED),"Redo refreshes names")
	var root = editor.graph_edit.top_generator
	editor.graph_edit.update_view(root.get_node("Nested"))
	await frames(tree,8)
	check.call(ui_node(editor,"NestedRead").title == "Read Particle.Custom."+RENAMED,"nested graph view has the same presentation context")
	editor.graph_edit.update_view(root)
	await frames(tree,8)
	editor.stage_choice.select(1)
	editor.stage_choice.item_selected.emit(1)
	await frames(tree,40)
	check.call(editor.input_box.get_child_count() == 0 and ui_node(editor,"CopyRead").title.ends_with(RENAMED) and ui_node(editor,"Delta").title == "Read Context.delta","module/stage switch rebuilds context without stale input rows")
	editor.stage_choice.select(0)
	editor.stage_choice.item_selected.emit(0)
	await frames(tree,40)

	var input_ui = ui_node(editor,"Input")
	sink = ui_node(editor,"Output")
	editor.graph_edit.on_disconnect_node(input_ui.name,0,sink.name,1)
	await frames(tree,8)
	check.call(sink.generator.get_input_defs()[1].tooltip.contains("Unconnected"),"disconnect refreshes output status")
	choose_attribute(editor,CUSTOM)
	editor.remove_write()
	await frames(tree,40)
	check.call(editor.binding_details.text.contains("Not registered"),"Unbind is distinct from an unconnected output port")
	editor.add_write()
	await frames(tree,40)
	check.call(ui_node(editor,"Output").generator.get_input_defs()[1].tooltip.contains("Unconnected"),"new output binding is not claimed connected")
	editor.graph_edit.on_connect_node(ui_node(editor,"Input").name,0,ui_node(editor,"Output").name,1)
	await frames(tree,8)
	check.call(ui_node(editor,"Output").generator.get_input_defs()[1].tooltip.contains("Connected"),"new wire refreshes status")

	await editor.add_binding("module_read","missing_namespace_id","vec3","Position")
	await frames(tree,40)
	var missing_ui
	for node in editor.graph_edit.get_children():
		if node is MMGraphNodeGeneric and node.generator.get("settings") is Dictionary and node.generator.settings.get("id") == "missing_namespace_id": missing_ui = node
	check.call(missing_ui != null and missing_ui.title.contains("Missing: missing_namespace_id"),"new invalid Read is shown as Missing, not resolved by name")
	var invalid: Dictionary = await editor.compile_document()
	check.call(not invalid.errors.is_empty(),"Missing display does not suppress the existing compiler diagnostic")
	if missing_ui != null: editor.graph_edit.remove_node(missing_ui)
	await frames(tree,40)
	var valid: Dictionary = await editor.compile_document()
	check.call(valid.errors.is_empty(),"removing the missing node restores the graph")
	return {"original":original,"stage":original_stage,"selection":original_selection,"module_id":MODULE,"custom_id":CUSTOM,"name":RENAMED}

static func restore(editor, state: Dictionary, tree: SceneTree) -> void:
	editor.stage = state.stage
	editor.stage_choice.select(0 if state.stage == "spawn" else 1)
	editor.selected = state.selection
	editor.apply_document(state.original)
	await frames(tree,45)
