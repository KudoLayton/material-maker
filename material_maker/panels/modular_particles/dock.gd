extends Control
## Shared dock shell; an editor owns its controls even when they are displayed here.
var displayed: Control
var source: Node

func _init() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(160, 100)

func show_editor(control: Control, home: Node) -> void:
	if displayed == control: return
	if is_instance_valid(displayed):
		remove_child(displayed)
		if is_instance_valid(source) and not source.is_queued_for_deletion(): source.add_child(displayed)
		displayed = null
		source = null
	if control != null and is_instance_valid(control) and is_instance_valid(home):
		control.get_parent().remove_child(control)
		add_child(control)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		displayed = control
		source = home

