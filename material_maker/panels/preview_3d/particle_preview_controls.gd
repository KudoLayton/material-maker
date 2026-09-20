extends HBoxContainer

var runtime: Node
var fields: Dictionary = {}
var pause := CheckButton.new()
var panel := PanelContainer.new()
var button := Button.new()
var error_label := Label.new()
var syncing := false

func _ready() -> void:
	button.text = "Particles"
	button.toggle_mode = true
	button.theme_type_variation = &"MM_PanelMenuButton"
	add_child(button)
	panel.top_level = true
	panel.theme_type_variation = &"MM_PanelMenuSubPanel"
	button.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	var grid := GridContainer.new()
	grid.columns = 2
	rows.add_child(grid)
	for spec in [["emission", "Emission", ["Continuous", "Burst"]], ["shape", "Shape", ["Square", "Soft Circle"]]]:
		var option := OptionButton.new()
		for item in spec[2]: option.add_item(item)
		add_field(grid, spec[0], spec[1], option)
		option.item_selected.connect(func(value): change_setting(spec[0], value))
	for spec in [["amount", "Amount", 1.0, 100000.0, 1.0], ["lifetime", "Lifetime (s)", 0.01, 3600.0, 0.01], ["quad_size", "Quad Size", 0.001, 1000.0, 0.001]]:
		var spin := SpinBox.new()
		spin.min_value = spec[2]
		spin.max_value = spec[3]
		spin.step = spec[4]
		spin.custom_minimum_size.x = 145
		spin.update_on_text_changed = false
		add_field(grid, spec[0], spec[1], spin)
		spin.value_changed.connect(func(value): change_setting(spec[0], value))
	var playback := HBoxContainer.new()
	rows.add_child(playback)
	pause.text = "Pause"
	pause.toggled.connect(runtime.set_paused)
	playback.add_child(pause)
	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(runtime.restart)
	playback.add_child(restart)
	button.toggled.connect(func(value):
		panel.visible = value
		if value:
			panel.reset_size()
			panel.global_position = Vector2(clampf(button.global_position.x, 0.0, maxf(0.0, get_viewport_rect().size.x - panel.size.x)), button.global_position.y + button.size.y + 6.0))
	panel.hide()
	error_label.position = Vector2(8, 38)
	error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	runtime.preview.add_child(error_label)
	runtime.status_changed.connect(sync_status)
	runtime.generator.preview_settings_changed.connect(sync_settings)
	runtime.preview.visibility_changed.connect(func():
		if not runtime.preview.is_visible_in_tree(): button.button_pressed = false)
	sync_settings()
	sync_status()

func add_field(grid: GridContainer, key: String, title: String, control: Control) -> void:
	var label := Label.new()
	label.text = title
	grid.add_child(label)
	grid.add_child(control)
	fields[key] = control

func change_setting(key: String, value) -> void:
	if not syncing: runtime.generator.set_preview_setting(key, value)

func sync_settings() -> void:
	syncing = true
	for key in fields:
		if fields[key] is OptionButton: fields[key].select(int(runtime.generator.preview_settings[key]))
		else: fields[key].set_value_no_signal(runtime.generator.preview_settings[key])
	syncing = false

func sync_status() -> void:
	pause.set_pressed_no_signal(runtime.paused)
	error_label.size.x = maxf(100.0, runtime.preview.size.x - 16.0)
	error_label.text = "Preview paused — " + runtime.error_text
	error_label.visible = not runtime.error_text.is_empty()

func _input(event: InputEvent) -> void:
	if panel.visible and event is InputEventMouseButton and event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null or (hovered != button and not button.is_ancestor_of(hovered)): button.button_pressed = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(error_label): error_label.queue_free()
