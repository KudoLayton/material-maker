extends ConfirmationDialog
## Export-only preferences: neither the graph nor the 3D preview is changed.
signal options_selected(options: Dictionary)
var target: OptionButton
var units: SpinBox
var flip: CheckBox
var blend: OptionButton
var sprite: LineEdit
var settings: VBoxContainer

func setup(editor: Node) -> void:
	title = "Export Modular GPU Particles"
	ok_button_text = "Choose Destination…"
	min_size = Vector2i(520,280)
	var box := VBoxContainer.new()
	add_child(box)
	var label := Label.new()
	label.text = "Output node (the same graph and simulation are used)"
	box.add_child(label)
	target = OptionButton.new()
	target.name = "RenderTarget"
	target.add_item("3D — MMGPUParticles3D")
	target.add_item("2D — MMGPUParticles2D (XY projection)")
	box.add_child(target)
	settings = VBoxContainer.new()
	box.add_child(settings)
	label = Label.new()
	label.text = "2D output settings — the editor preview remains 3D"
	settings.add_child(label)
	var row := HBoxContainer.new()
	settings.add_child(row)
	label = Label.new()
	label.text = "Pixels Per Unit"
	row.add_child(label)
	units = SpinBox.new()
	units.name = "PixelsPerUnit"
	units.min_value = 0.001
	units.max_value = 1000000
	units.allow_greater = true
	units.step = 0.001
	units.value = 100
	row.add_child(units)
	flip = CheckBox.new()
	flip.name = "FlipY"
	flip.text = "Flip Y (+Y up → screen up)"
	flip.button_pressed = true
	settings.add_child(flip)
	blend = OptionButton.new()
	blend.name = "BlendMode"
	for text in ["Effect default","Alpha","Additive","Opaque","Cutout"]: blend.add_item(text)
	settings.add_child(blend)
	row = HBoxContainer.new()
	settings.add_child(row)
	sprite = LineEdit.new()
	sprite.name = "Sprite"
	sprite.placeholder_text = "Optional PNG (empty = effect quad/round quad)"
	sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sprite)
	var browse := Button.new()
	browse.text = "Browse…"
	row.add_child(browse)
	browse.pressed.connect(func():
		var path: String = await editor.choose_file(FileDialog.FILE_MODE_OPEN_FILE,"*.png;PNG sprite")
		if not path.is_empty(): sprite.text = path)
	target.item_selected.connect(func(index): settings.visible = index == 1)
	settings.hide()
	confirmed.connect(func(): options_selected.emit(values()))
	canceled.connect(func(): options_selected.emit({}))

func values() -> Dictionary:
	if target.selected == 0: return {"render_target":"3d"}
	return {"render_target":"2d","pixels_per_unit":units.value,"flip_y":flip.button_pressed,"blend_mode":["effect","alpha","additive","opaque","cutout"][blend.selected],"sprite":sprite.text.strip_edges()}
