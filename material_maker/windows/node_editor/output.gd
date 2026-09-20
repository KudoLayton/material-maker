extends HBoxContainer

var original_type := ""
var original_expressions: Dictionary = {}

func _ready():
	$Type.clear()
	for tn in mm_io_types.type_names:
		var t = mm_io_types.types[tn]
		$Type.add_item(t.label)

func update_up_down_button() -> void:
	var parent = get_parent()
	if parent == null:
		return
	$Up.disabled = (get_index() == 0)
	$Down.disabled = (get_index() == get_parent().get_child_count()-2)

func set_model_data(data, remaining_group_size = 0) -> int:
	$Description.short_description = data.shortdesc if data.has("shortdesc") else ""
	$Description.long_description = data.longdesc if data.has("longdesc") else ""
	$Description.update_tooltip()
	for i in range(mm_io_types.type_names.size()):
		if data.has(mm_io_types.type_names[i]):
			$Type.selected = i
			$Value.text = data[mm_io_types.type_names[i]]
	original_type = data.get("type", "")
	original_expressions = {}
	for key in data:
		if mm_io_types.types.has(key): original_expressions[key] = data[key]
	if mm_io_types.TYPE_ALIASES.has(original_type) and data.has(original_type):
		$Type.selected = mm_io_types.type_names.find(mm_io_types.canonical_type(original_type))
		$Value.text = data[original_type]
	if data.has("group_size") and data.group_size > 1:
		$PortGroupButton.set_state(1)
		return data.group_size-1
	elif remaining_group_size == 1:
		$PortGroupButton.set_state(1)
	return int(max(remaining_group_size-1, 0))

func get_model_data() -> Dictionary:
	var selected_type: String = mm_io_types.type_names[$Type.selected]
	var data = { "type":selected_type, selected_type:$Value.text }
	if mm_io_types.TYPE_ALIASES.has(original_type) and mm_io_types.canonical_type(original_type) == selected_type:
		data = original_expressions.duplicate()
		data.type = original_type
		data[original_type] = $Value.text
	if $Description.short_description != "":
		data.shortdesc = $Description.short_description
	if $Description.long_description != "":
		data.longdesc = $Description.long_description
	if $PortGroupButton.group_size > 0:
		data.group_size = $PortGroupButton.group_size
	return data

func _on_Delete_pressed() -> void:
	var p = get_parent()
	p.remove_child(self)
	p.update_up_down_buttons()
	queue_free()

func _on_Up_pressed() -> void:
	get_parent().move_child(self, get_index() - 1)
	get_parent().update_up_down_buttons()

func _on_Down_pressed() -> void:
	get_parent().move_child(self, get_index() + 1)
	get_parent().update_up_down_buttons()
