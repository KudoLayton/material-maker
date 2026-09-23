extends Node
const Emission = preload("res://material_maker/panels/modular_particles/emission.gd")
const S = preload("standard_checks.gd")
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Scheduler = preload("res://addons/mm_gpu_particles/scheduler.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int = 12) -> void:
	for frame in count: await get_tree().process_frame
func scheduled(emitter: Dictionary, ticks: int) -> int:
	var clock := Scheduler.new()
	for tick in ticks: clock.advance(1.0/60,emitter,true)
	return clock.sequence
func settle(editor) -> void:
	await frames(45)
	while editor._building or editor._loading: await frames(3)
func run() -> void:
	var loop := {"rate":60.0,"duration":0.5,"loop":true,"bursts":[],"lifetime":2.0}
	check(Emission.mode(loop) == "Looping" and scheduled(loop,120) == 120,"loop rate over multiple periods")
	var burst := Emission.convert(loop,"Burst")
	burst.bursts[0].count = 7
	check(Emission.mode(burst) == "Burst" and scheduled(burst,120) == 7,"one-shot burst does not silently repeat")
	burst.loop = true
	check(scheduled(burst,120) == 28,"repeat burst period boundary")
	var custom := loop.duplicate(true)
	custom.bursts = [{"time":0.1,"count":3},{"time":0.3,"count":2}]
	check(Emission.mode(custom) == "Custom" and scheduled(custom,60) == 70,"mixed schedule retained")
	for invalid in [-1.0,INF,NAN,"2",null]:
		var bad := loop.duplicate(true)
		bad.duration = invalid
		check(not Emission.error(bad).is_empty(),"invalid duration rejected")
	for invalid in [-1,0.5,4294967296]:
		var bad := burst.duplicate(true)
		bad.bursts[0].count = invalid
		check(not Emission.error(bad).is_empty(),"invalid count rejected")
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames(30)
	get_tree().root.size = Vector2i(1440,960)
	var editor = window.new_modular_particles()
	await settle(editor)
	var original: Dictionary = editor.document.duplicate(true)
	var panel = editor.emission_panel
	var graph = editor.graph_edit.top_generator
	var live = editor.preview
	check(is_instance_valid(live) and live.ready_for_simulation,"GPU ready")
	var state = live._gpu
	var shader: RID = state.shader
	var pipeline: RID = state.pipeline
	live.manual_processing = true
	live.pause()
	var camera: Camera3D = editor.camera
	camera.position = Vector3(3,4,5)
	var camera_transform := camera.transform
	var previous_time: float = live.clock.time
	var history: int = editor.undoredo.cursor
	panel.amount.text = "120"
	panel.apply_button.pressed.emit()
	await settle(editor)
	check(editor.document.emitter.rate == 120 and editor.need_save,"UI edits authoritative emitter")
	check(editor.undoredo.cursor == history+1,"single emission edit is one undo")
	check(editor.graph_edit.top_generator == graph,"emission edit does not rebuild graph")
	check(editor.preview == live and live._gpu == state and state.shader == shader and state.pipeline == pipeline,"emission edit reuses GPU pipeline")
	check(live.clock.time == previous_time and live.clock.paused,"rate edit preserves time and pause")
	panel.mode_choice.item_selected.emit(1)
	await settle(editor)
	check(Emission.mode(editor.document.emitter) == "Burst" and not editor.document.emitter.loop,"Burst UI selects one-shot")
	check(live.clock.time == 0 and live.clock.paused,"mode change restarts once and preserves Pause")
	check(camera.transform == camera_transform,"emission changes preserve camera")
	check(live._gpu == state and state.shader == shader,"restart retains shader/allocation")
	var snapshot := await S.snapshot(live)
	check(snapshot.count == 0,"paused restart clears GPU indirect draw count")
	panel.amount.text = "7"
	panel.duration.text = "0.5"
	panel.repeat.button_pressed = false
	panel.apply_button.pressed.emit()
	await settle(editor)
	live.play()
	live.advance(1.0/60)
	await frames(3)
	snapshot = await S.snapshot(live)
	check(snapshot.count == 7 and live.clock.sequence == 7,"Burst UI produces exactly seven GPU particles")
	for tick in 40: live.advance(1.0/60)
	await frames(3)
	check(live.clock.sequence == 7,"non-repeating burst stays one-shot")
	live.pause()
	var before_invalid: Dictionary = editor.document.duplicate(true)
	for text in ["-1","0","1.5","4294967296","NaN"]:
		panel.amount.text = text
		panel.apply_button.pressed.emit()
		check(editor.document == before_invalid,"invalid UI count leaves document untouched: "+text)
	editor.undoredo.undo()
	await settle(editor)
	check(panel.amount.text == "64","Undo refreshes emission controls")
	editor.undoredo.redo()
	await settle(editor)
	check(panel.amount.text == "7","Redo refreshes emission controls")
	check(editor.graph_edit.top_generator == graph,"emission Undo/Redo leaves graph intact")
	check(editor.set_emitter_settings(custom),"set custom schedule")
	await settle(editor)
	var custom_doc: Dictionary = editor.document.duplicate(true)
	panel.refresh()
	check(panel.mode_choice.selected == 2 and panel.apply_button.disabled and editor.document == custom_doc,"Custom is read-only without normalization")
	panel.mode_choice.item_selected.emit(1)
	check(is_instance_valid(panel.conversion) and editor.document == custom_doc,"Custom conversion requires confirmation")
	panel.conversion.canceled.emit()
	await frames()
	check(editor.document == custom_doc,"cancel keeps mixed bursts exactly")
	panel.mode_choice.item_selected.emit(1)
	panel.conversion.confirmed.emit()
	await settle(editor)
	check(Emission.mode(editor.document.emitter) == "Burst","explicit Custom conversion")
	editor.undoredo.undo()
	await settle(editor)
	check(editor.document.emitter == custom,"Undo restores exact original Custom schedule")
	for version in [1,2]:
		editor.document.version = version
		if version == 2: editor.document.user_parameters = []
		editor.save_path = "res://emission-v%d.mpfx" % version
		check(await editor.save(),"save emission v%d" % version)
		var saved := Document.load_file(editor.save_path)
		check(saved.emitter == JSON.parse_string(JSON.stringify(custom)) and saved.version == version,"emission persisted without format migration")
		var result: Dictionary = await editor.compile_document()
		check(result.errors.is_empty() and result.effect.emitter == custom,"compiled/export emitter is same dictionary")
		check(ResourceSaver.save(result.effect,"res://emission-v%d.res" % version) == OK,"save compiled effect")
		var loaded = ResourceLoader.load("res://emission-v%d.res" % version,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(loaded.emitter == custom and scheduled(loaded.emitter,60) == 70,"saved standalone emitter schedule")
	check(original.modules == editor.document.modules and original.stages == editor.document.stages,"emission controls preserve existing graphs and stack")
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://emission-ui.png")
	print("MODULAR_EMISSION_UI ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
