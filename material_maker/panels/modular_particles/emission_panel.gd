extends VBoxContainer
const Emission = preload("emission.gd")
var editor_ref: WeakRef
var mode_choice: OptionButton
var amount: LineEdit
var duration: LineEdit
var repeat: CheckBox
var message: Label
var apply_button: Button
var conversion: ConfirmationDialog
var _refreshing := false

func setup(editor) -> void:
	editor_ref = weakref(editor)
	name = "EffectEmission"
	var title := Label.new()
	title.text = "Effect Emission"
	add_child(title)
	mode_choice = OptionButton.new()
	mode_choice.name = "Mode"
	for text in ["Looping","Burst","Custom"]: mode_choice.add_item(text)
	add_child(mode_choice)
	mode_choice.item_selected.connect(select_mode)
	amount = field("Amount","Rate / Count")
	duration = field("Duration","Duration (seconds)")
	repeat = CheckBox.new()
	repeat.name = "Repeat"
	repeat.text = "Repeat burst"
	add_child(repeat)
	apply_button = Button.new()
	apply_button.text = "Apply Emission"
	apply_button.pressed.connect(apply)
	add_child(apply_button)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 100
	add_child(message)
	var advanced := Button.new()
	advanced.text = "Advanced Emitter / Renderer…"
	advanced.clip_text = true
	advanced.pressed.connect(editor.edit_emitter)
	add_child(advanced)
	refresh()

func field(title: String, hint: String) -> LineEdit:
	var label := Label.new()
	label.text = hint
	add_child(label)
	var edit := LineEdit.new()
	edit.name = title
	edit.placeholder_text = hint
	edit.tooltip_text = hint
	add_child(edit)
	return edit

func refresh() -> void:
	var editor = editor_ref.get_ref()
	if editor == null: return
	_refreshing = true
	var emitter: Dictionary = editor.document.emitter
	var mode := Emission.mode(emitter)
	mode_choice.select(["Looping","Burst","Custom"].find(mode))
	amount.editable = mode != "Custom"
	duration.editable = mode != "Custom"
	apply_button.disabled = mode == "Custom"
	repeat.visible = mode == "Burst"
	repeat.set_pressed_no_signal(emitter.get("loop",false) == true)
	amount.text = str(emitter.get("rate",0)) if mode == "Looping" else (str(emitter.bursts[0].count) if mode == "Burst" else "Custom schedule")
	amount.tooltip_text = "Particles per second" if mode == "Looping" else "Particles per burst (positive uint32 integer)"
	duration.text = str(emitter.get("duration",1.0))
	message.text = "Mixed/delayed schedule preserved. Use Advanced, or explicitly convert to Looping/Burst." if mode == "Custom" else ("Continuous particles per second." if mode == "Looping" else "Burst at t=0; Repeat uses Duration as its period.")
	_refreshing = false

func select_mode(index: int) -> void:
	if _refreshing: return
	var editor = editor_ref.get_ref()
	var target: String = ["Looping","Burst","Custom"][index]
	var current := Emission.mode(editor.document.emitter)
	refresh()
	if target == current or target == "Custom": return
	if current != "Custom":
		editor.set_emitter_settings(Emission.convert(editor.document.emitter,target))
		return
	conversion = ConfirmationDialog.new()
	conversion.title = "Convert Custom emission?"
	conversion.dialog_text = "Replace the existing rate and burst schedule with " + target + "?\nThe original schedule can be restored with Undo."
	conversion.confirmed.connect(func():
		editor.set_emitter_settings(Emission.convert(editor.document.emitter,target))
		conversion.queue_free())
	conversion.canceled.connect(conversion.queue_free)
	add_child(conversion)
	conversion.popup_centered()

static func parse_number(text: String):
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null

func apply() -> void:
	var editor = editor_ref.get_ref()
	var emitter: Dictionary = editor.document.emitter.duplicate(true)
	var mode := Emission.mode(emitter)
	if mode == "Custom": return
	var number = parse_number(amount.text)
	var seconds = parse_number(duration.text)
	if not Emission.Document.valid_value("float",seconds) or seconds <= 0:
		message.text = "Duration must be a finite positive number."
		return
	if not Emission.Document.valid_value("float" if mode == "Looping" else "uint",number) or number <= 0:
		message.text = "Rate must be positive." if mode == "Looping" else "Count must be a positive uint32 integer."
		return
	emitter.duration = seconds
	if mode == "Looping": emitter.rate = number
	else:
		emitter.bursts[0].count = int(number)
		emitter.loop = repeat.button_pressed
	editor.set_emitter_settings(emitter)
