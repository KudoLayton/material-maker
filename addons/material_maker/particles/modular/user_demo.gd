extends Node3D
## Standalone exported example. Uses only the public runtime API, never MM or GPU readback.
var selected := 0
var controls: VBoxContainer
var status: Label
var elapsed := 0.0
var animate_speed := false

func target() -> MMGPUParticles3D:
	return $Particles if selected == 0 else $Second

func _ready() -> void:
	if $Second.effect.user_parameter("User.Tint").get("type") == "vec4":
		$Second.set_user_parameter("User.Tint",Color(0.0,0.0,1.0,1.0))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(12,12)
	panel.custom_minimum_size.x = 400
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "User Parameters — independent particle instances"
	box.add_child(title)
	var choice := OptionButton.new()
	choice.name = "Target"
	choice.add_item("Left instance")
	choice.add_item("Right instance")
	choice.item_selected.connect(func(index):
		selected = index
		refresh_controls())
	box.add_child(choice)
	controls = VBoxContainer.new()
	controls.name = "Values"
	box.add_child(controls)
	var reset := Button.new()
	reset.name = "ResetDefaults"
	reset.text = "Reset selected instance to effect defaults"
	reset.pressed.connect(reset_selected)
	box.add_child(reset)
	var animate := CheckBox.new()
	animate.name = "AnimateSpeed"
	animate.text = "Animate left User.Speed (game logic example)"
	animate.disabled = $Particles.effect.user_parameter("User.Speed").get("type") != "float"
	animate.toggled.connect(func(enabled): animate_speed = enabled)
	box.add_child(animate)
	status = Label.new()
	status.text = "Speed: new particles; Gravity/Tint: living particles.\nChanges do not restart the simulation."
	box.add_child(status)
	refresh_controls()

func _process(delta: float) -> void:
	elapsed += delta
	if animate_speed: $Particles.set_user_parameter("User.Speed",3.0+2.0*sin(elapsed))

func reset_selected() -> void:
	for definition in target().effect.user_parameters: target().reset_user_parameter_by_id(definition.id)
	refresh_controls()

func set_value(id: String, value) -> void:
	status.text = "Updated selected instance only." if target().set_user_parameter_by_id(id,value) else "Rejected: value must match the declared type/range."

func refresh_controls() -> void:
	for child in controls.get_children():
		controls.remove_child(child)
		child.queue_free()
	for definition in target().effect.user_parameters:
		var row := HBoxContainer.new()
		controls.add_child(row)
		var label := Label.new()
		label.text = "User."+definition.name
		label.custom_minimum_size.x = 110
		row.add_child(label)
		var value = target().get_user_parameter_by_id(definition.id)
		if definition.name == "Speed" and definition.type == "float":
			var slider := HSlider.new()
			slider.name = "SpeedSlider"
			slider.min_value = 0
			slider.max_value = 12
			slider.step = 0.1
			slider.value = value
			slider.custom_minimum_size.x = 200
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(slider)
			slider.value_changed.connect(func(next): set_value(definition.id,next))
		elif definition.name == "Gravity" and definition.type == "vec3":
			for component in 3:
				var spin := SpinBox.new()
				spin.name = "Gravity"+str(component)
				spin.min_value = -50
				spin.max_value = 50
				spin.step = 0.01
				spin.allow_greater = true
				spin.allow_lesser = true
				spin.value = value[component]
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(spin)
				spin.value_changed.connect(func(next):
					var gravity: Vector3 = target().get_user_parameter_by_id(definition.id)
					gravity[component] = next
					set_value(definition.id,gravity))
		elif definition.name == "Tint" and definition.type == "vec4":
			var picker := ColorPickerButton.new()
			picker.name = "TintPicker"
			picker.color = Color(value.x,value.y,value.z,value.w)
			picker.custom_minimum_size = Vector2(200,25)
			row.add_child(picker)
			picker.color_changed.connect(func(next): set_value(definition.id,next))
		else:
			var edit := LineEdit.new()
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text = JSON.stringify(json_value(value))
			edit.tooltip_text = definition.type+" — enter a JSON value"
			row.add_child(edit)
			edit.text_submitted.connect(func(text):
				var parser := JSON.new()
				if parser.parse(text) == OK: set_value(definition.id,parser.data)
				else: status.text = "Invalid JSON")

static func json_value(value):
	if value is Vector2: return [value.x,value.y]
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Vector4: return [value.x,value.y,value.z,value.w]
	return value
