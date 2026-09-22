extends ConfirmationDialog
const Library = preload("library.gd")
const Model = preload("res://addons/material_maker/particles/modular/module_library.gd")
const Presentation = preload("res://addons/material_maker/particles/modular/presentation.gd")
var editor_ref: WeakRef
var target_stage := ""
var entries: Array = []
var search: LineEdit
var category: OptionButton
var stage_filter: OptionButton
var items: ItemList
var details: RichTextLabel
var error_label: Label

func setup(editor: Node) -> void:
	editor_ref = weakref(editor)
	target_stage = editor.stage
	entries = Library.catalog_entries()
	name = "ParticleLibraryDialog"
	title = "Particle Module Library"
	ok_button_text = "Add Copy"
	dialog_hide_on_ok = false
	exclusive = true
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(880,530)
	add_child(form)
	var row := HBoxContainer.new()
	form.add_child(row)
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search name, description, tags..."
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(search)
	category = OptionButton.new()
	category.name = "Category"
	category.add_item("All categories")
	var categories: Array = []
	for entry in entries:
		if entry.category not in categories: categories.append(entry.category)
	categories.sort()
	for value in categories: category.add_item(value)
	row.add_child(category)
	stage_filter = OptionButton.new()
	stage_filter.name = "StageFilter"
	for value in ["Current Stage","All stages","Spawn","Update"]: stage_filter.add_item(value)
	row.add_child(stage_filter)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(split)
	items = ItemList.new()
	items.name = "Modules"
	items.custom_minimum_size.x = 270
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(items)
	details = RichTextLabel.new()
	details.name = "Details"
	details.selection_enabled = true
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(details)
	error_label = Label.new()
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	form.add_child(error_label)
	search.text_changed.connect(func(_text): refresh_list())
	category.item_selected.connect(func(_index): refresh_list())
	stage_filter.item_selected.connect(func(_index): refresh_list())
	items.item_selected.connect(func(_index): refresh_details())
	items.item_activated.connect(func(_index): try_add())
	confirmed.connect(try_add)
	canceled.connect(queue_free)
	register_text_enter(search)
	refresh_list()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.get_keycode_with_modifiers() == KEY_ESCAPE:
		set_input_as_handled()
		queue_free()

func selected_id() -> String:
	var selected := items.get_selected_items()
	return str(items.get_item_metadata(selected[0])) if not selected.is_empty() else ""

func entry_for(id: String) -> Dictionary:
	for entry in entries:
		if entry.id == id: return entry
	return {}

func refresh_list() -> void:
	var selected := selected_id()
	items.clear()
	var filter: String = [target_stage,"","spawn","update"][stage_filter.selected]
	var terms := Array(search.text.to_lower().split(" ",false))
	for entry in entries:
		if not filter.is_empty() and filter not in entry.stages: continue
		if category.selected > 0 and entry.category != category.get_item_text(category.selected): continue
		var haystack: String = (entry.name+" "+entry.description+" "+entry.tags).to_lower()
		if not terms.all(func(term): return haystack.contains(term)): continue
		var index := items.add_item(entry.name+"  ["+"/".join(entry.stages)+"]")
		items.set_item_metadata(index,entry.id)
		items.set_item_tooltip(index,entry.description)
		if target_stage not in entry.stages: items.set_item_custom_fg_color(index,Color(0.6,0.6,0.6))
		if entry.id == selected: items.select(index)
	if items.item_count>0 and items.get_selected_items().is_empty(): items.select(0)
	refresh_details()

func refresh_details() -> void:
	error_label.visible = false
	get_ok_button().disabled = true
	var entry := entry_for(selected_id())
	if entry.is_empty():
		details.text = "No matching modules. Try a different search or filter."
		return
	var editor = editor_ref.get_ref()
	if editor == null: return
	var payload := Library.catalog_payload(entry.id)
	var merged := Model.merge_payload(editor.document,payload,true)
	details.text = entry.name+"\n"+entry.category+" / "+"/".join(entry.stages)+"\n\n"+entry.description+"\n\n"+entry.inputs_help+"\n\nOrder: "+entry.order
	if not merged.ok:
		details.text += "\n\nCannot add: "+merged.error
		return
	var module: Dictionary = merged.document.modules[merged.module_id]
	var ctx := Presentation.context(merged.document,merged.module_id)
	details.text += "\n\nModule Inputs"
	for input in module.inputs: details.text += "\nModule."+input.get("name",input.id)+" : "+input.type+" = "+JSON.stringify(input.default)
	if module.inputs.is_empty(): details.text += "\n(none)"
	for key in ["reads","writes"]:
		details.text += "\n\n"+("Read" if key == "reads" else "Write")
		for id in module[key]: details.text += "\n"+Presentation.describe("module_read" if key == "reads" else "module_output",id,"","",ctx).qualified
		if module[key].is_empty(): details.text += "\n(none)"
	details.text += "\n\nAutomatically created Attributes"
	for attribute in merged.added_attributes: details.text += "\nParticle.Custom."+attribute.name+" : "+attribute.type
	if merged.added_attributes.is_empty(): details.text += "\n(none; existing matching roles are reused)"
	details.text += "\n\nAdds an independent editable copy after the selected row (or at the end). Does not add or reorder other modules. One Undo removes the entire insertion."
	if target_stage not in entry.stages:
		details.text += "\n\nUnavailable in the current "+target_stage+" Stage. Close this window and switch Stage first."
	elif editor._loading or editor.stage != target_stage:
		details.text += "\n\nEditor context changed or is loading. Close and reopen the Library."
	else: get_ok_button().disabled = false

func try_add() -> void:
	refresh_details()
	if get_ok_button().disabled: return
	var editor = editor_ref.get_ref()
	if editor != null and editor.add_library_module(selected_id(),target_stage):
		queue_free()
	else:
		error_label.text = "Could not add module. The editor context or Attribute bindings changed."
		error_label.visible = true
