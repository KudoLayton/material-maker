extends VBoxContainer
## Effect-level definitions only. Module graphs remain effect-independent.
const Users = preload("res://addons/material_maker/particles/modular/user_parameters.gd")
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
var editor_ref: WeakRef
var tree: Tree
var details: RichTextLabel
var dialog: ConfirmationDialog
var selected_id := ""

class UserDialog:
	extends ConfirmationDialog
	func _input(event: InputEvent) -> void:
		if visible and event is InputEventKey and event.pressed and not event.echo and event.get_keycode_with_modifiers() == KEY_ESCAPE:
			set_input_as_handled()
			canceled.emit()
			queue_free()

func setup(editor) -> void:
	editor_ref = weakref(editor)
	name = "UserParameters"
	var label := Label.new()
	label.text = "User Parameters (effect instance)"
	add_child(label)
	tree = Tree.new()
	tree.name = "Definitions"
	tree.hide_root = true
	tree.columns = 5
	tree.column_titles_visible = true
	for column in 5:
		tree.set_column_title(column,["Namespace","Name","Type","Default","Uses"][column])
		tree.set_column_custom_minimum_width(column,[70,80,45,85,35][column])
		tree.set_column_clip_content(column,true)
	tree.custom_minimum_size.y = 130
	add_child(tree)
	tree.item_selected.connect(func():
		var item := tree.get_selected()
		selected_id = str(item.get_metadata(0)) if item != null else ""
		refresh_details())
	var actions := HBoxContainer.new()
	add_child(actions)
	for action in ["Add","Rename","Value","Type","Delete"]:
		var button := Button.new()
		button.name = action
		button.text = action
		button.pressed.connect(func():
			if action == "Delete":
				var owner = editor_ref.get_ref()
				if owner != null and not selected_id.is_empty(): owner.user_operation("remove",[selected_id])
			else: show_dialog(action,selected_id))
		actions.add_child(button)
	details = RichTextLabel.new()
	details.name = "Details"
	details.custom_minimum_size.y = 55
	details.fit_content = true
	details.scroll_active = false
	details.selection_enabled = true
	add_child(details)
	refresh()

func refresh() -> void:
	var editor = editor_ref.get_ref() if editor_ref != null else null
	if editor == null or tree == null: return
	tree.clear()
	var root := tree.create_item()
	for definition in editor.document.get("user_parameters",[]):
		var item := tree.create_item(root)
		item.set_metadata(0,definition.id)
		var uses := Users.references(editor.document,definition.id).size()
		var texts := ["User",definition.name,definition.type,JSON.stringify(definition.default),str(uses)]
		for column in 5:
			item.set_text(column,texts[column])
			item.set_tooltip_text(column,"User."+definition.name+" : "+definition.type+"\nStable ID: "+definition.id+"\nDefault: "+JSON.stringify(definition.default))
		if definition.id == selected_id: item.select(1)
	refresh_details()

func select_user(id: String) -> void:
	selected_id = id
	refresh()

func refresh_details() -> void:
	var editor = editor_ref.get_ref() if editor_ref != null else null
	if editor == null or details == null: return
	var definition := Users.definition(editor.document,selected_id)
	if definition.is_empty():
		details.text = "Shared by this effect instance; not a Particle Attribute."
		return
	var usage := Users.reference_text(editor.document,selected_id)
	details.text = "User."+definition.name+" : "+definition.type+" — read-only effect input\nID: "+definition.id+"\n"+(usage if not usage.is_empty() else "Not bound to a Module Input")

func show_dialog(action: String, id: String = "") -> void:
	var editor = editor_ref.get_ref() if editor_ref != null else null
	if editor == null or editor._loading or not editor.is_visible_in_tree() or is_instance_valid(dialog): return
	var definition := Users.definition(editor.document,id)
	if action != "Add" and definition.is_empty(): return
	var popup := UserDialog.new()
	dialog = popup
	popup.name = "UserParameterDialog"
	popup.title = action+" User Parameter"
	popup.dialog_hide_on_ok = false
	popup.exclusive = true
	var form := VBoxContainer.new()
	form.name = "Form"
	form.custom_minimum_size.x = 460
	popup.add_child(form)
	var label := Label.new()
	label.text = "Name: ASCII identifier, unique within this effect.\nRename keeps IDs; update game code that uses the old name."
	form.add_child(label)
	var name_input := LineEdit.new()
	name_input.name = "Name"
	name_input.text = definition.get("name","")
	name_input.editable = action in ["Add","Rename"]
	form.add_child(name_input)
	var type := OptionButton.new()
	type.name = "Type"
	for key in Document.TYPES:
		type.add_item(key)
		if key == definition.get("type","float"): type.select(type.item_count-1)
	type.disabled = action not in ["Add","Type"]
	form.add_child(type)
	var value := LineEdit.new()
	value.name = "Default"
	value.text = JSON.stringify(definition.get("default",0.0))
	value.editable = action != "Rename"
	value.placeholder_text = "JSON default (e.g. 1.0, true, [0,1,0])"
	form.add_child(value)
	var warning := Label.new()
	warning.name = "Error"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(warning)
	popup.confirmed.connect(func():
		var owner = editor_ref.get_ref()
		if owner == null or owner._loading: return
		var parser := JSON.new()
		if parser.parse(value.text) != OK:
			warning.text = "Invalid JSON default"
			return
		var operation := "add" if action == "Add" else "change"
		var arguments: Array = []
		if action == "Add": arguments = [name_input.text,type.get_item_text(type.selected),parser.data]
		elif action == "Rename": arguments = [id,{"name":name_input.text}]
		elif action == "Value": arguments = [id,{"default":parser.data}]
		else: arguments = [id,{"type":type.get_item_text(type.selected),"default":parser.data}]
		if owner.user_operation(operation,arguments): popup.queue_free()
		else: warning.text = owner.status.text)
	popup.canceled.connect(popup.queue_free)
	popup.register_text_enter(name_input)
	popup.register_text_enter(value)
	add_child(popup)
	popup.popup_centered(Vector2i(500,260))
	var focus: LineEdit = name_input if action in ["Add","Rename"] else value
	focus.grab_focus()
	focus.select_all()
