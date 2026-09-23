extends VBoxContainer
## A project tab wrapping the existing MMGraphEdit, not a second graph editor.
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Library = preload("library.gd")
const History = preload("history.gd")
const Presentation = preload("res://addons/material_maker/particles/modular/presentation.gd")
const ModuleLibrary = preload("res://addons/material_maker/particles/modular/module_library.gd")
const Users = preload("res://addons/material_maker/particles/modular/user_parameters.gd")
const Particles = preload("preview_particles.gd")
const Emission = preload("emission.gd")
var document: Dictionary = Library.new_document()
var save_path := ""
var need_save := false
var undoredo := History.new()
var graph_edit: MMGraphEdit
var stage := "spawn"
var selected := 0
var current_module := ""
var stage_choice: OptionButton
var stack: ItemList
var module_choice: OptionButton
var rename_button: Button
var rename_dialog: ConfirmationDialog
var library_dialog: ConfirmationDialog
var library_button: Button
var compile_warnings: Array = []
var attribute_choice: OptionButton
var attributes_tree: Tree
var binding_details: RichTextLabel
var _detail_kind := "module_read"
var _detail_id := "position"
var _presentation_pending := false
var input_box: VBoxContainer
var user_panel
var emission_panel
var preview_controls
var status: RichTextLabel
var viewport: SubViewport
var scene: Node3D
var camera: Camera3D
var preview: MMGPUParticles3D
var candidate: MMGPUParticles3D
var refresh_timer := Timer.new()
var last_compiled: MMParticleEffect
var _loading := false
var _building := false
var _revision := 0
var _display_graph_baseline: Dictionary = {}
var _hidden_preview_pause := false
var pane_home: Control
var particle_panes: Dictionary = {}

func _ready() -> void:
	undoredo.owner_ref = weakref(self)
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	button(toolbar,"Save",save)
	button(toolbar,"Export",export_effect)
	button(toolbar,"Undo",undoredo.undo)
	button(toolbar,"Redo",undoredo.redo)
	button(toolbar,"Play",func():
		if is_instance_valid(preview): preview.play())
	button(toolbar,"Pause",func():
		if is_instance_valid(preview): preview.pause())
	button(toolbar,"Restart",func():
		if is_instance_valid(preview): preview.restart())
	button(toolbar,"Emitter settings",edit_emitter)
	pane_home = Control.new()
	pane_home.name = "InactiveParticlePanes"
	pane_home.hide()
	add_child(pane_home)
	var stack_scroll := ScrollContainer.new()
	stack_scroll.name = "ModuleStackContents"
	stack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack_scroll.follow_focus = true
	pane_home.add_child(stack_scroll)
	particle_panes["Module Stack"] = stack_scroll
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_scroll.add_child(left)
	emission_panel = preload("emission_panel.gd").new()
	left.add_child(emission_panel)
	emission_panel.setup(self)
	stage_choice = OptionButton.new()
	stage_choice.add_item("Particle Spawn")
	stage_choice.add_item("Particle Update")
	left.add_child(stage_choice)
	stage_choice.item_selected.connect(func(index):
		capture_graph()
		stage = "spawn" if index == 0 else "update"
		selected = 0
		refresh_lists()
		load_selected())
	stack = ItemList.new()
	stack.custom_minimum_size.y = 160
	stack.focus_mode = Control.FOCUS_ALL
	stack.tooltip_text = "Select a module and press F2 to rename it."
	stack.gui_input.connect(stack_input)
	left.add_child(stack)
	stack.item_selected.connect(func(index):
		capture_graph()
		selected = index
		load_selected())
	var actions := HBoxContainer.new()
	left.add_child(actions)
	button(actions,"Up",func(): move_module(-1))
	button(actions,"Down",func(): move_module(1))
	button(actions,"Copy",duplicate_module)
	actions = HBoxContainer.new()
	left.add_child(actions)
	button(actions,"On/Off",toggle_module)
	button(actions,"Remove",remove_module)
	rename_button = button(actions,"Rename",show_rename_dialog)
	rename_button.tooltip_text = "Rename the shared module definition (F2 in the stack)."
	module_choice = OptionButton.new()
	module_choice.fit_to_longest_item = false
	left.add_child(module_choice)
	actions = HBoxContainer.new()
	left.add_child(actions)
	button(actions,"Add",func():
		if module_choice.item_count: add_module(str(module_choice.get_item_metadata(module_choice.selected))))
	button(actions,"New Module",new_module)
	library_button = button(left,"Browse Library…",show_library)
	library_button.name = "BrowseLibrary"
	library_button.tooltip_text = "Search basic modules. Adds an independent graph copy and required Attributes, not prerequisite modules."
	actions = HBoxContainer.new()
	left.add_child(actions)
	button(actions,"Import .mmg",import_module)
	button(actions,"Save .mmg",save_module)
	var user_scroll := ScrollContainer.new()
	user_scroll.name = "UserParameterContents"
	user_scroll.follow_focus = true
	pane_home.add_child(user_scroll)
	particle_panes["User Parameters"] = user_scroll
	user_panel = preload("user_panel.gd").new()
	user_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_scroll.add_child(user_panel)
	user_panel.setup(self)
	var attribute_scroll := ScrollContainer.new()
	attribute_scroll.name = "AttributeContents"
	attribute_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	attribute_scroll.follow_focus = true
	pane_home.add_child(attribute_scroll)
	particle_panes["Attributes"] = attribute_scroll
	left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attribute_scroll.add_child(left)
	var label := Label.new()
	label.text = "Attributes (stable IDs)"
	left.add_child(label)
	attributes_tree = Tree.new()
	attributes_tree.hide_root = true
	attributes_tree.columns = 3
	attributes_tree.column_titles_visible = true
	for column in 3:
		attributes_tree.set_column_title(column,["Namespace","Name","Type / ID"][column])
		attributes_tree.set_column_custom_minimum_width(column,[112,90,130][column])
		attributes_tree.set_column_clip_content(column,true)
	attributes_tree.custom_minimum_size.y = 150
	left.add_child(attributes_tree)
	attributes_tree.item_edited.connect(rename_attribute)
	attributes_tree.item_selected.connect(func():
		var item := attributes_tree.get_selected()
		if item != null: show_binding_details("module_read",str(item.get_metadata(0))))
	actions = HBoxContainer.new()
	left.add_child(actions)
	button(actions,"Add Attribute",add_attribute_dialog)
	button(actions,"Delete",delete_attribute)
	attribute_choice = OptionButton.new()
	attribute_choice.fit_to_longest_item = false
	attribute_choice.item_selected.connect(func(index): show_binding_details("module_read",attribute_choice.get_item_metadata(index).id))
	left.add_child(attribute_choice)
	actions = HBoxContainer.new()
	left.add_child(actions)
	button(actions,"Read",add_read)
	button(actions,"Write binding",add_write)
	button(actions,"Unbind",remove_write)
	var context_row := HBoxContainer.new()
	left.add_child(context_row)
	var context_choice := OptionButton.new()
	for key in ["delta","time","just_spawned","seed","index"]: context_choice.add_item(key)
	context_row.add_child(context_choice)
	button(context_row,"Read Context",func():
		var key := context_choice.get_item_text(context_choice.selected)
		add_binding("module_context",key,{"delta":"float","time":"float","just_spawned":"bool","seed":"uint","index":"uint"}[key],key))
	binding_details = RichTextLabel.new()
	binding_details.custom_minimum_size.y = 100
	binding_details.fit_content = true
	binding_details.scroll_active = false
	binding_details.selection_enabled = true
	left.add_child(binding_details)
	var input_scroll := ScrollContainer.new()
	input_scroll.name = "ModuleInputContents"
	# A very narrow user-resized dock must scroll, never widen into the graph.
	input_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	input_scroll.follow_focus = true
	pane_home.add_child(input_scroll)
	particle_panes["Module Inputs"] = input_scroll
	left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_scroll.add_child(left)
	button(left,"Add Module Input",add_input_dialog)
	input_box = VBoxContainer.new()
	left.add_child(input_box)
	graph_edit = preload("res://material_maker/panels/graph_edit/graph_edit.tscn").instantiate()
	graph_edit.node_factory = get_node("/root/MainWindow/NodeFactory")
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(graph_edit)
	graph_edit.graph_changed.connect(graph_changed)
	graph_edit.view_updated.connect(func(_generator): queue_presentation_refresh())
	preview_controls = preload("preview_controls.gd").new()
	pane_home.add_child(preview_controls)
	particle_panes["Particle Preview"] = preview_controls
	preview_controls.setup(self)
	viewport = preview_controls.viewport
	scene = preview_controls.scene
	camera = preview_controls.camera
	status = RichTextLabel.new()
	tree_exiting.connect(func():
		var layout = get_node_or_null("/root/MainWindow/VBoxContainer/Layout")
		if layout != null and not get_node("/root/MainWindow").quitting and layout.has_method("bind_particle_editor") and layout.current_mode == "particle" and layout.get_panel("Module Stack").source == pane_home:
			layout.bind_particle_editor(null))
	status.custom_minimum_size.y = 55
	status.fit_content = true
	add_child(status)
	refresh_timer.one_shot = true
	refresh_timer.wait_time = 0.25
	refresh_timer.timeout.connect(refresh_preview)
	add_child(refresh_timer)
	visibility_changed.connect(func():
		if is_instance_valid(preview):
			if is_visible_in_tree(): preview.clock.paused = _hidden_preview_pause
			else:
				_hidden_preview_pause = preview.clock.paused
				preview.clock.paused = true)
	refresh_lists()
	load_selected()

static func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func get_project_type() -> String: return "modular_particles"
func get_graph_edit() -> MMGraphEdit: return graph_edit
func get_material_node(): return null
func project_selected() -> void: update_title()

func update_title() -> void:
	if get_parent().has_method("set_tab_title") and get_index() < get_parent().get_tab_count():
		get_parent().set_tab_title(get_index(), (save_path.get_file() if not save_path.is_empty() else "Modular Particles") + (" *" if need_save else ""))

func all_attributes() -> Array:
	return Document.BUILTINS.duplicate(true) + document.attributes

func refresh_lists() -> void:
	if stack == null: return
	if emission_panel != null: emission_panel.refresh()
	update_rename_button()
	stack.clear()
	for instance in document.stages[stage]:
		stack.add_item(("" if instance.get("enabled",true) else "[off] ") + str(document.modules.get(instance.module,{}).get("name",instance.module)))
	selected = mini(selected,stack.item_count-1)
	if selected >= 0: stack.select(selected)
	module_choice.clear()
	for id in document.modules:
		if stage in document.modules[id].stages:
			module_choice.add_item(document.modules[id].name)
			module_choice.set_item_metadata(module_choice.item_count-1,id)
	var tree_id: String = str(attributes_tree.get_selected().get_metadata(0)) if attributes_tree.get_selected() != null else ""
	var choice_id: String = attribute_choice.get_item_metadata(attribute_choice.selected).id if attribute_choice.selected >= 0 else "position"
	attributes_tree.clear()
	var root_item := attributes_tree.create_item()
	attribute_choice.clear()
	for attribute in all_attributes():
		var item := attributes_tree.create_item(root_item)
		item.set_metadata(0,attribute.id)
		item.set_editable(1,document.attributes.any(func(a): return a.id == attribute.id))
		attribute_choice.add_item(attribute.name)
		attribute_choice.set_item_metadata(attribute_choice.item_count-1,attribute)
		if attribute.id == choice_id: attribute_choice.select(attribute_choice.item_count-1)
		if attribute.id == tree_id: item.select(1)
	if is_instance_valid(user_panel): user_panel.refresh()
	refresh_input_sources()
	refresh_attribute_labels(Presentation.context(document,current_module,{},current_instance_id()))
	queue_presentation_refresh()
	update_title()

static func short_binding_label(info: Dictionary) -> String:
	return Presentation.compact(info.qualified,36) + (" " + info.badge if not info.badge.is_empty() else "") + (" [Missing]" if info.missing else "")

func refresh_attribute_labels(ctx: Dictionary) -> void:
	var root_item := attributes_tree.get_root()
	if root_item == null: return
	var index := 0
	for item in root_item.get_children():
		var id: String = str(item.get_metadata(0))
		var info := Presentation.describe("module_read",id,"","",ctx)
		item.set_text(0,info["namespace"])
		item.set_text(1,info.raw_name)
		item.set_text(2,info.type + (" " + info.badge if not info.badge.is_empty() else ""))
		for column in 3: item.set_tooltip_text(column,info.tooltip)
		attribute_choice.set_item_text(index,short_binding_label(info) + " : " + info.type)
		attribute_choice.set_item_tooltip(index,info.tooltip)
		index += 1

func queue_presentation_refresh() -> void:
	if _presentation_pending: return
	_presentation_pending = true
	refresh_binding_display.call_deferred()

func show_binding_details(kind: String, id: String) -> void:
	_detail_kind = kind
	_detail_id = id
	queue_presentation_refresh()

func refresh_binding_display(allow_loading: bool = false) -> void:
	_presentation_pending = false
	if not is_inside_tree() or (_loading and not allow_loading): return
	var graph: Dictionary = {}
	if not current_module.is_empty() and graph_edit.top_generator != null and document.modules.get(current_module,{}).has("mm_graph"):
		graph = graph_edit.top_generator.serialize()
	var ctx := Presentation.context(document,current_module,graph,current_instance_id())
	refresh_attribute_labels(ctx)
	binding_details.text = Presentation.describe(_detail_kind,_detail_id,"","",ctx).tooltip
	for row in input_box.get_children():
		if row.is_queued_for_deletion() or not row.has_meta("module_input_id"): continue
		var info := Presentation.describe("module_parameter",str(row.get_meta("module_input_id")),"","",ctx)
		var label: Label = row.get_node("InputLabel")
		label.text = short_binding_label(info) + " : " + info.type
		if info.get("binding_source","") not in ["","Constant"]: label.text += " ← " + info.binding_source
		label.tooltip_text = info.tooltip
	apply_display_context(graph_edit.top_generator,ctx)
	for node in graph_edit.get_children():
		if not node is MMGraphNodeGeneric or node.generator == null or not node.generator.has_method("set_display_context"): continue
		var signature: Array = [node.generator.get_type_name(),node.generator.get_input_defs(),node.generator.get_output_defs(),node.generator.get_description()]
		if node.get_meta("module_presentation",[]) != signature:
			node.set_meta("module_presentation",signature)
			# No generator signals: __update_all__ would dirty the graph/history.
			node.update_node()
			node.tooltip_text = node.generator.get_description()

func apply_display_context(generator: Node, ctx: Dictionary) -> void:
	if generator == null: return
	if generator.has_method("set_display_context"): generator.set_display_context(ctx)
	for child in generator.get_children(): apply_display_context(child,ctx)

func load_selected() -> void:
	if _loading: return
	_loading = true
	update_rename_button()
	current_module = ""
	_display_graph_baseline = {}
	for child in input_box.get_children(): child.queue_free()
	if selected >= 0 and selected < document.stages[stage].size():
		var instance: Dictionary = document.stages[stage][selected]
		current_module = instance.module
		var module: Dictionary = document.modules[current_module]
		if module.has("mm_graph"):
			await graph_edit.new_material(module.mm_graph.duplicate(true))
			watch(graph_edit.top_generator)
		for parameter in module.inputs: build_input_row(instance,parameter)
		refresh_input_sources()
	else:
		graph_edit.clear_material()
	await get_tree().process_frame
	refresh_binding_display(true)
	# Fit the final qualified labels, not the temporary cached/ID fallback sizes.
	await get_tree().process_frame
	fit_graph()
	if not current_module.is_empty() and (document.modules[current_module].has("standard_module") or document.modules[current_module].get("catalog_snapshot",false)):
		# UI default controls and loader metadata are not user edits. Keep the
		# authored snapshot intact until the graph actually changes; otherwise
		# merely opening a catalog copy creates a second Undo transaction.
		_display_graph_baseline = graph_edit.top_generator.serialize().duplicate(true)
	_loading = false
	update_rename_button()
	schedule_preview()

func fit_graph() -> void:
	var bounds := Rect2()
	var started := false
	for child in graph_edit.get_children():
		if child is GraphNode:
			var rect := Rect2(child.position_offset,child.size)
			bounds = bounds.merge(rect) if started else rect
			started = true
	if started:
		var fitted := clampf(minf((graph_edit.size.x-60.0)/maxf(1.0,bounds.size.x),(graph_edit.size.y-60.0)/maxf(1.0,bounds.size.y)),graph_edit.zoom_min,1.0)
		var catalog: bool = not current_module.is_empty() and (document.modules[current_module].has("standard_module") or document.modules[current_module].get("catalog_snapshot",false))
		# MM hides labels and disables controls below zoom 0.3. Large catalog
		# graphs should open on their Write contract, not as unreadable wires.
		if catalog and fitted < 0.5:
			for node in graph_edit.get_children():
				if node is MMGraphNodeGeneric and node.generator != null and node.generator.get("settings") is Dictionary and node.generator.settings.get("kind") == "module_output":
					graph_edit.zoom = clampf(minf((graph_edit.size.x-56)/maxf(node.size.x,1),(graph_edit.size.y-70)/maxf(node.size.y,1)),0.5,1.0)
					graph_edit.scroll_offset = node.position_offset*graph_edit.zoom-Vector2(28,50)
					return
		graph_edit.zoom = fitted
		if catalog: graph_edit.scroll_offset = bounds.get_center()*graph_edit.zoom-0.5*graph_edit.size
		else: graph_edit.center_view()

func watch(generator: Node) -> void:
	if generator is MMGenBase and not generator.parameter_changed.is_connected(generator_changed): generator.parameter_changed.connect(generator_changed)
	for child in generator.get_children(): watch(child)

func generator_changed(_key, _value) -> void: graph_changed()
func graph_changed() -> void:
	queue_presentation_refresh()
	if _loading: return
	need_save = true
	update_title()
	schedule_preview()

func capture_graph() -> void:
	if _loading or current_module.is_empty() or graph_edit.top_generator == null: return
	var before := document.duplicate(true)
	var graph: Dictionary = graph_edit.top_generator.serialize()
	if not _display_graph_baseline.is_empty():
		if graph == _display_graph_baseline: return
		_display_graph_baseline = graph.duplicate(true)
	document.modules[current_module].mm_graph = graph
	document.modules[current_module].merge(Library.contracts(graph),true)
	undoredo.record(before,document)

func changed(before: Dictionary, reload_graph: bool = false) -> void:
	undoredo.record(before,document)
	need_save = true
	refresh_lists()
	if reload_graph: load_selected()
	else: schedule_preview()

func apply_document(value: Dictionary) -> void:
	var before_graph := document.duplicate(true)
	var after_graph := value.duplicate(true)
	before_graph.erase("emitter")
	after_graph.erase("emitter")
	document = value
	need_save = true
	refresh_lists()
	if before_graph == after_graph: schedule_preview()
	else: load_selected()

func add_module(id: String) -> void:
	capture_graph()
	var before := document.duplicate(true)
	document.stages[stage].append({"id":Document.uid(),"module":id,"parameters":{},"enabled":true})
	selected = document.stages[stage].size()-1
	changed(before,true)

func show_library() -> void:
	if _loading or not is_visible_in_tree() or is_instance_valid(library_dialog): return
	var dialog := preload("library_dialog.gd").new()
	library_dialog = dialog
	add_child(dialog)
	dialog.setup(self)
	dialog.popup_centered(Vector2i(920,610))
	dialog.search.grab_focus()

func add_library_module(catalog_id: String, expected_stage: String = "") -> bool:
	if _loading or (not expected_stage.is_empty() and expected_stage != stage): return false
	var payload := Library.catalog_payload(catalog_id)
	var inserted := ModuleLibrary.insert(document,payload,stage,selected)
	if not inserted.ok:
		status.text = inserted.error
		return false
	capture_graph()
	var before := document.duplicate(true)
	inserted = ModuleLibrary.insert(document,payload,stage,selected)
	document = inserted.document
	selected = inserted.selected
	changed(before,true)
	return true

func new_module() -> void:
	capture_graph()
	var before := document.duplicate(true)
	var id := Document.uid()
	document.modules[id] = Library.definition("Module "+str(document.modules.size()+1),[stage],[])
	document.stages[stage].append({"id":Document.uid(),"module":id,"parameters":{},"enabled":true})
	selected = document.stages[stage].size()-1
	changed(before,true)

func selected_module_id() -> String:
	if _loading or selected < 0 or selected >= document.stages[stage].size(): return ""
	var id: String = document.stages[stage][selected].module
	return id if document.modules.has(id) and id == current_module else ""

func update_rename_button() -> void:
	if rename_button != null: rename_button.disabled = selected_module_id().is_empty()
	if library_button != null: library_button.disabled = _loading

func stack_input(event: InputEvent) -> void:
	# Do not take F2 from graph nodes, text inputs, dialogs or inactive tabs.
	if not is_visible_in_tree() or not stack.has_focus() or selected_module_id().is_empty(): return
	if event is InputEventKey and event.pressed and not event.echo and event.get_keycode_with_modifiers() == KEY_F2:
		stack.accept_event()
		show_rename_dialog()

func show_rename_dialog() -> void:
	var id := selected_module_id()
	if id.is_empty() or not is_visible_in_tree(): return
	if is_instance_valid(rename_dialog): return
	var dialog := ConfirmationDialog.new()
	rename_dialog = dialog
	dialog.name = "RenameModuleDialog"
	dialog.title = "Rename Module"
	dialog.ok_button_text = "Rename"
	dialog.dialog_hide_on_ok = false
	var form := VBoxContainer.new()
	form.name = "Form"
	dialog.add_child(form)
	var info := Label.new()
	info.text = "All instances of this module in this effect share the name."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 420
	form.add_child(info)
	var input := LineEdit.new()
	input.name = "Name"
	input.text = document.modules[id].name
	form.add_child(input)
	var warning := Label.new()
	warning.text = "Name cannot be empty."
	warning.visible = false
	form.add_child(warning)
	input.text_changed.connect(func(text: String):
		var empty := text.strip_edges().is_empty()
		dialog.get_ok_button().disabled = empty
		warning.visible = empty)
	dialog.get_ok_button().disabled = input.text.strip_edges().is_empty()
	dialog.register_text_enter(input)
	dialog.confirmed.connect(func():
		if rename_module(id,input.text): dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460,150))
	input.grab_focus()
	input.select_all()

func rename_module(id: String, new_name: String) -> bool:
	var label := new_name.strip_edges()
	if label.is_empty() or not document.modules.has(id): return false
	if document.modules[id].name == label: return true
	capture_graph()
	var before := document.duplicate(true)
	document.modules[id].name = label
	undoredo.record(before,document)
	need_save = true
	refresh_lists()
	# Display metadata only: do not rebuild the graph or restart the GPU preview.
	return true

func move_module(direction: int) -> void:
	if selected < 0 or selected+direction < 0 or selected+direction >= document.stages[stage].size(): return
	capture_graph()
	var before := document.duplicate(true)
	var item = document.stages[stage].pop_at(selected)
	selected += direction
	document.stages[stage].insert(selected,item)
	changed(before)

func duplicate_module() -> void:
	if selected < 0: return
	capture_graph()
	var before := document.duplicate(true)
	var item: Dictionary = document.stages[stage][selected].duplicate(true)
	item.id = Document.uid()
	document.stages[stage].insert(selected+1,item)
	selected += 1
	changed(before,true)

func toggle_module() -> void:
	if selected < 0: return
	var before := document.duplicate(true)
	var item: Dictionary = document.stages[stage][selected]
	item.enabled = not item.get("enabled",true)
	changed(before)

func remove_module() -> void:
	if selected < 0: return
	capture_graph()
	var before := document.duplicate(true)
	document.stages[stage].remove_at(selected)
	changed(before,true)

func add_binding(kind: String, id: String, type: String, label: String) -> void:
	if current_module.is_empty(): return
	var data := Library.binding("Binding_"+Document.uid().left(8),kind,id,type)
	data.settings.label = label
	await graph_edit.create_nodes(data)
	watch(graph_edit.top_generator)
	graph_changed()

func add_read() -> void:
	var field: Dictionary = attribute_choice.get_item_metadata(attribute_choice.selected)
	add_binding("module_read",field.id,field.type,field.name)

func add_write() -> void:
	if current_module.is_empty(): return
	capture_graph()
	var field: Dictionary = attribute_choice.get_item_metadata(attribute_choice.selected)
	if field.get("readonly",false):
		status.text = "Read-only Attribute"
		return
	var before := document.duplicate(true)
	for node in document.modules[current_module].mm_graph.nodes:
		if node.get("settings",{}).get("kind") == "module_output":
			if node.settings.fields.any(func(f): return f.id == field.id): return
			node.settings.fields.append({"id":field.id,"name":field.name,"type":field.type})
	document.modules[current_module].writes.append(field.id)
	changed(before,true)

func remove_write() -> void:
	if current_module.is_empty(): return
	capture_graph()
	var field: Dictionary = attribute_choice.get_item_metadata(attribute_choice.selected)
	var before := document.duplicate(true)
	var graph: Dictionary = document.modules[current_module].mm_graph
	for node in graph.nodes:
		if node.get("settings",{}).get("kind") != "module_output": continue
		var index: int = node.settings.fields.find(node.settings.fields.filter(func(f): return f.id == field.id).front()) if node.settings.fields.any(func(f): return f.id == field.id) else -1
		if index < 0: return
		graph.connections = graph.connections.filter(func(c): return not (c.to == node.name and c.to_port == index))
		for connection in graph.connections:
			if connection.to == node.name and connection.to_port > index: connection.to_port -= 1
		node.settings.fields.remove_at(index)
	document.modules[current_module].merge(Library.contracts(graph),true)
	changed(before,true)

func value_dialog(title: String, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var form := VBoxContainer.new()
	dialog.add_child(form)
	var label := LineEdit.new()
	label.placeholder_text = "Name"
	form.add_child(label)
	var type := OptionButton.new()
	for key in Document.TYPES: type.add_item(key)
	form.add_child(type)
	var value := LineEdit.new()
	value.text = "0.0"
	form.add_child(value)
	type.item_selected.connect(func(index):
		var selected_type := type.get_item_text(index)
		value.text = {"float":"0.0","int":"0","uint":"0","bool":"false","vec2":"[0,0]","vec3":"[0,0,0]","vec4":"[0,0,0,0]"}[selected_type])
	dialog.confirmed.connect(func():
		var t := type.get_item_text(type.selected)
		var parsed = JSON.parse_string(value.text)
		if label.text.is_empty() or not Document.valid_value(t,parsed): status.text = "Invalid name/type/default"
		else: callback.call(label.text,t,parsed)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(360,180))

func add_attribute_dialog() -> void: value_dialog("New Attribute",add_attribute)
func add_attribute(label: String, type: String, value) -> void:
	var before := document.duplicate(true)
	document.attributes.append({"id":Document.uid(),"name":label,"type":type,"default":value})
	changed(before)

func rename_attribute() -> void:
	var item := attributes_tree.get_edited()
	if item == null or attributes_tree.get_edited_column() != 1: return
	var before := document.duplicate(true)
	for field in document.attributes:
		if field.id == item.get_metadata(0): field.name = item.get_text(1)
	if before != document: changed(before)

func delete_attribute() -> void:
	var item := attributes_tree.get_selected()
	if item == null: return
	var id: String = item.get_metadata(0)
	capture_graph()
	for module in document.modules.values():
		if id in module.reads or id in module.writes:
			status.text = "Attribute is referenced by a module; remove its bindings first"
			return
	var before := document.duplicate(true)
	document.attributes = document.attributes.filter(func(field): return field.id != id)
	changed(before)

func add_input_dialog() -> void:
	if current_module.is_empty(): return
	value_dialog("New Module Input",func(label,type,value):
		var before := document.duplicate(true)
		document.modules[current_module].inputs.append({"id":Document.uid(),"name":label,"type":type,"default":value})
		changed(before,true))

func delete_input(module_id: String, input_id: String) -> bool:
	# Ignore stale row callbacks while switching modules or rebuilding the UI.
	if selected_module_id() != module_id or module_id.is_empty(): return false
	var module: Dictionary = document.modules[module_id]
	if not module.inputs.any(func(input): return input.id == input_id): return false
	var graph: Dictionary = module.get("mm_graph",{})
	if module.has("mm_graph") and graph_edit.top_generator != null:
		graph = graph_edit.top_generator.serialize()
	var reference := Library.input_reference(graph,input_id)
	if reference.is_empty(): reference = Library.input_reference(module.get("graph",{}),input_id)
	if not reference.is_empty():
		status.text = "Cannot delete module input: referenced by " + reference + ". Remove its Read node first (including nested/unconnected nodes)."
		return false
	# Only capture pending graph edits after validation, so a rejected deletion
	# does not change the saved definition, history, dirty flag or GPU preview.
	if module.has("mm_graph"): capture_graph()
	var before := document.duplicate(true)
	module.inputs = module.inputs.filter(func(input): return input.id != input_id)
	for current_stage in ["spawn","update"]:
		for instance in document.stages[current_stage]:
			if instance.module == module_id:
				if instance.has("parameters"): instance.parameters.erase(input_id)
				if instance.has("input_bindings"):
					instance.input_bindings.erase(input_id)
					if instance.input_bindings.is_empty(): instance.erase("input_bindings")
	changed(before,true)
	return true

func current_instance_id() -> String:
	if selected < 0 or selected >= document.stages[stage].size(): return ""
	var instance: Dictionary = document.stages[stage][selected]
	return instance.id if instance.module == current_module else ""

func build_input_row(instance: Dictionary, parameter: Dictionary) -> void:
	var line := GridContainer.new()
	line.columns = 2
	line.set_meta("module_input_id",parameter.id)
	line.set_meta("module_instance_id",instance.id)
	input_box.add_child(line)
	var label := Label.new()
	label.name = "InputLabel"
	label.text = "Module."+parameter.name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 80
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: show_binding_details("module_parameter",parameter.id))
	line.add_child(label)
	button(line,"Read",func(): add_binding("module_parameter",parameter.id,parameter.type,parameter.name))
	var value := LineEdit.new()
	value.name = "InputValue"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(value)
	value.focus_entered.connect(func(): show_binding_details("module_parameter",parameter.id))
	value.text_submitted.connect(func(text): set_input(instance.id,parameter.id,JSON.parse_string(text)))
	var remove := button(line,"Delete",func(): delete_input(instance.module,parameter.id))
	remove.set_meta("module_input_id",parameter.id)
	remove.tooltip_text = "Delete this shared input, its constants and User bindings. Remove all referencing Read nodes first."
	var source := OptionButton.new()
	source.name = "InputSource"
	source.fit_to_longest_item = false
	source.custom_minimum_size.x = 90
	line.add_child(source)
	source.item_selected.connect(func(index):
		var user_id: String = source.get_item_metadata(index)
		if user_id.is_empty():
			var item := Users.instance(document,instance.id)
			if item.get("input_bindings",{}).has(parameter.id): user_operation("unbind",[instance.id,parameter.id])
		else: user_operation("bind",[instance.id,parameter.id,user_id]))
	var edit_user := button(line,"Edit User",func():
		var item := Users.instance(document,instance.id)
		var user_id: String = item.get("input_bindings",{}).get(parameter.id,{}).get("id","")
		user_panel.select_user(user_id)
		user_panel.show_dialog("Value",user_id))
	edit_user.name = "EditUser"

func refresh_input_sources() -> void:
	if input_box == null: return
	var item := Users.instance(document,current_instance_id())
	if item.is_empty(): return
	for row in input_box.get_children():
		if row.is_queued_for_deletion() or row.get_meta("module_instance_id","") != item.id: continue
		var id: String = row.get_meta("module_input_id","")
		var parameter := Users.input(document,item,id)
		if parameter.is_empty(): continue
		var bound: bool = item.get("input_bindings",{}).has(id)
		var user_id: String = item.get("input_bindings",{}).get(id,{}).get("id","")
		var user := Users.definition(document,user_id)
		var source: OptionButton = row.get_node("InputSource")
		source.clear()
		source.add_item("Constant")
		source.set_item_metadata(0,"")
		source.select(0)
		var selected_source := -1
		for definition in document.get("user_parameters",[]):
			if definition.type != parameter.type: continue
			source.add_item("User."+definition.name)
			var index := source.item_count-1
			source.set_item_metadata(index,definition.id)
			source.set_item_tooltip(index,"User."+definition.name+" : "+definition.type+"\nID: "+definition.id)
			source.set_item_disabled(index,not Users.definition_error(definition).is_empty())
			if definition.id == user_id: selected_source = index
		if bound and selected_source < 0:
			source.add_item("Missing User ["+user_id.left(8)+"]")
			selected_source = source.item_count-1
			source.set_item_metadata(selected_source,user_id)
			source.set_item_disabled(selected_source,true)
		if bound: source.select(selected_source)
		source.tooltip_text = "Choose Constant or an exactly matching User type. Unbinding restores the previous constant."
		var value: LineEdit = row.get_node("InputValue")
		value.editable = not bound
		value.text = JSON.stringify(user.default) if bound and not user.is_empty() else ("[Missing]" if bound else JSON.stringify(item.get("parameters",{}).get(id,parameter.default)))
		value.tooltip_text = "Shared User default; use Edit User to change it." if bound else "Module instance constant (JSON)"
		row.get_node("EditUser").disabled = not bound or user.is_empty()

func user_result(action: String, arguments: Array) -> Dictionary:
	match action:
		"add": return Users.add(document,arguments[0],arguments[1],arguments[2])
		"change": return Users.change(document,arguments[0],arguments[1])
		"remove": return Users.remove(document,arguments[0])
		"bind": return Users.bind(document,arguments[0],arguments[1],arguments[2])
		"unbind": return Users.unbind(document,arguments[0],arguments[1])
	return Users.failure("Unknown User operation")

func user_operation(action: String, arguments: Array) -> bool:
	if _loading: return false
	var result := user_result(action,arguments)
	if not result.ok:
		status.text = result.error
		return false
	if result.document == document: return true
	capture_graph()
	var before := document.duplicate(true)
	result = user_result(action,arguments)
	if not result.ok:
		status.text = result.error
		return false
	document = result.document
	if action == "add": user_panel.selected_id = result.user_id
	if action == "change" and arguments[1].has("default") and is_instance_valid(preview):
		var old := Users.definition(before,arguments[0])
		var current := Users.definition(document,arguments[0])
		if not old.is_empty() and old.type == current.type: preview.set_user_parameter_by_id(current.id,current.default)
	changed(before)
	refresh_input_sources()
	queue_presentation_refresh()
	return true

func set_input(instance_id: String, parameter_id: String, value) -> void:
	var before := document.duplicate(true)
	for current_stage in ["spawn","update"]:
		for instance in document.stages[current_stage]:
			if instance.id != instance_id: continue
			if instance.get("input_bindings",{}).has(parameter_id):
				status.text = "Input is bound to a User parameter; edit User value or select Constant."
				return
			for input in document.modules[instance.module].inputs:
				if input.id == parameter_id and Document.valid_value(input.type,value):
					if not instance.has("parameters"): instance.parameters = {}
					instance.parameters[parameter_id] = value
					if is_instance_valid(preview): preview.set_parameter(instance_id+"/"+parameter_id,value)
					undoredo.record(before,document)
					need_save = true
					update_title()
					return
	status.text = "Invalid module input value"

func set_emitter_settings(value: Dictionary) -> bool:
	var problem := Emission.error(value)
	if not problem.is_empty():
		status.text = problem
		return false
	if document.emitter == value: return true
	capture_graph()
	var before := document.duplicate(true)
	document.emitter = value.duplicate(true)
	changed(before)
	return true

func edit_emitter() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Emitter / Renderer settings (JSON)"
	dialog.dialog_hide_on_ok = false
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var error := Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(error)
	var text := TextEdit.new()
	text.custom_minimum_size = Vector2(540,300)
	text.text = JSON.stringify({"emitter":document.emitter,"renderer":document.renderer},"\t")
	box.add_child(text)
	dialog.confirmed.connect(func():
		var value = JSON.parse_string(text.text)
		if not value is Dictionary or not value.get("emitter") is Dictionary or not value.get("renderer") is Dictionary:
			error.text = "Invalid settings JSON"
			return
		error.text = Emission.error(value.emitter)
		if not error.text.is_empty(): return
		capture_graph()
		var before := document.duplicate(true)
		document.emitter = value.emitter.duplicate(true)
		document.renderer = value.renderer.duplicate(true)
		changed(before)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func schedule_preview() -> void:
	_revision += 1
	if is_instance_valid(candidate): candidate.queue_free()
	candidate = null
	if is_inside_tree(): refresh_timer.start()

func compile_document() -> Dictionary:
	capture_graph()
	var snapshot := document.duplicate(true)
	var graphs := {}
	for id in snapshot.modules:
		if snapshot.modules[id].has("mm_graph"):
			graphs[id] = await mm_loader.create_gen(snapshot.modules[id].mm_graph.duplicate(true))
	var result := Compiler.new().compile(snapshot,graphs)
	for generator in graphs.values():
		if is_instance_valid(generator): generator.free()
	return result

static func parameter_layout(effect: MMParticleEffect) -> Array:
	# Unused input deletion can change the parameter buffer without changing
	# shader text. Defaults/names are not layout, so live value edits stay cheap.
	return effect.parameters.map(func(parameter): return [parameter.id,parameter.type,parameter.offset,parameter.get("user_id","")])

func ready_text(effect: MMParticleEffect) -> String:
	var text := "Ready — Godot 4.7.2 / GPU / " + str(effect.component_count) + " components"
	for warning in compile_warnings: text += "\nWarning / %s / %s: %s" % [warning.stage,warning.module,warning.message]
	return text

func refresh_preview() -> void:
	if _building:
		refresh_timer.start()
		return
	_building = true
	var revision := _revision
	var result := await compile_document()
	_building = false
	if revision != _revision or not is_inside_tree(): return
	compile_warnings = result.get("warnings",[])
	if not result.errors.is_empty():
		var messages := PackedStringArray()
		for error in result.errors: messages.append("%s / %s / %s: %s" % [error.stage,error.module,error.node,error.message])
		status.text = "\n".join(messages)
		return
	last_compiled = result.effect
	if is_instance_valid(preview) and preview.effect.source_hash == result.effect.source_hash and parameter_layout(preview.effect) == parameter_layout(result.effect) and preview.effect.render_settings == result.effect.render_settings and preview.capacity == int(document.get("preview_capacity",4096)):
		# The preview owns its compiled resource. Update only parameter metadata,
		# without assigning effect (which would rebuild/reset the GPU).
		var restart_emission := Emission.needs_restart(preview.effect.emitter,result.effect.emitter)
		preview.effect.emitter = result.effect.emitter.duplicate(true)
		if restart_emission: preview.restart()
		preview.effect.format_version = result.effect.format_version
		preview.effect.parameters.assign(result.effect.parameters.duplicate(true))
		preview.effect.user_parameters.assign(result.effect.user_parameters.duplicate(true))
		preview.parameter_overrides.clear()
		preview.user_parameter_overrides.clear()
		for user in result.effect.user_parameters: preview.set_user_parameter_by_id(user.id,user.default)
		for parameter in result.effect.parameters:
			if not parameter.has("user_id"): preview.set_parameter(parameter.id,parameter.default)
		preview.notify_property_list_changed()
		status.text = ready_text(result.effect)
		return
	if is_instance_valid(candidate): candidate.queue_free()
	candidate = Particles.new()
	candidate.effect = result.effect
	candidate.capacity = int(document.get("preview_capacity",4096))
	candidate.hide()
	var pending := candidate
	pending.status_changed.connect(func():
		if not is_instance_valid(pending) or revision != _revision: return
		if not pending.error_text.is_empty():
			status.text = pending.error_text
			pending.queue_free()
			return
		if pending.ready_for_simulation and pending != preview:
			if is_instance_valid(preview): preview.queue_free()
			preview = pending
			candidate = null
			preview.show()
			if not is_visible_in_tree(): preview.clock.paused = true
			status.text = ready_text(result.effect))
	scene.add_child(pending)

func save() -> bool:
	if save_path.is_empty(): return await save_as()
	capture_graph()
	var error := Document.save_file(save_path,document)
	if error != OK:
		status.text = error_string(error)
		return false
	need_save = false
	update_title()
	return true

func choose_file(mode: FileDialog.FileMode, filter: String) -> String:
	var dialog = preload("res://material_maker/windows/file_dialog/file_dialog.tscn").instantiate()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.add_filter(filter)
	var files = await dialog.select_files()
	return files[0] if files.size() == 1 else ""

func save_as() -> bool:
	var path := await choose_file(FileDialog.FILE_MODE_SAVE_FILE,"*.mpfx;Modular Particle Effect")
	if path.is_empty(): return false
	save_path = path if path.get_extension() == "mpfx" else path + ".mpfx"
	return await save()

func load_project(path: String) -> bool:
	while _loading: await get_tree().process_frame
	var data := Document.load_file(path)
	var problem := Document.shape_error(data)
	if not problem.is_empty():
		status.text = problem
		return false
	save_path = path
	document = data
	selected = 0
	refresh_lists()
	await load_selected()
	need_save = false
	update_title()
	return true

func module_payload(id: String) -> Dictionary:
	var module: Dictionary = document.modules[id].duplicate(true)
	var data: Dictionary = module.mm_graph
	module.erase("mm_graph")
	data.particle_module = {"version":1,"id":id,"definition":module,"attributes":ModuleLibrary.snapshots(document,module)}
	return data

func load_module_data(data: Dictionary) -> bool:
	var merged := ModuleLibrary.merge_payload(document,data)
	if not merged.ok:
		status.text = merged.error
		return false
	capture_graph()
	var before := document.duplicate(true)
	merged = ModuleLibrary.merge_payload(document,data)
	document = merged.document
	changed(before,true)
	return true

func import_module() -> void:
	var path := await choose_file(FileDialog.FILE_MODE_OPEN_FILE,"*.mmg;Particle Module")
	if path.is_empty(): return
	var data := Document.load_file(path)
	if not load_module_data(data): status.text = "Not a valid version 1 particle module"

func save_module() -> void:
	if current_module.is_empty(): return
	capture_graph()
	var path := await choose_file(FileDialog.FILE_MODE_SAVE_FILE,"*.mmg;Particle Module")
	if path.is_empty(): return
	status.text = "Module saved" if Document.save_file(path,module_payload(current_module)) == OK else "Module save failed"

func export_effect() -> void:
	var result := await compile_document()
	if not result.errors.is_empty():
		status.text = str(result.errors)
		return
	var path := await choose_file(FileDialog.FILE_MODE_OPEN_DIR,"*")
	if path.is_empty(): return
	var exporter = load("res://addons/material_maker/particles/modular/exporter.gd").new()
	status.text = await exporter.export_effect(result.effect,path,int(document.get("preview_capacity",4096)))
