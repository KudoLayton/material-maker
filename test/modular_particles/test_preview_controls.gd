extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func frames(count: int = 8) -> void:
	for frame in count: await get_tree().process_frame
func _ready() -> void: run.call_deferred()
func motion(mask: int, shift: bool = false, alt: bool = false) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = mask
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.relative = Vector2(20,10)
	return event
func wheel(ctrl: bool = false, shift: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	return event
func run() -> void:
	var window = load("res://material_maker/main_window.tscn").instantiate()
	get_tree().root.add_child(window)
	await frames(35)
	get_tree().root.size = Vector2i(1440,960)
	var editor = window.new_modular_particles()
	await frames(100)
	var controls = editor.preview_controls
	var camera: Camera3D = controls.camera
	var controller = controls.controller
	var live = editor.preview
	var gpu = live._gpu
	live.pause()
	var clock_time: float = live.clock.time
	var emitter: Dictionary = editor.document.emitter.duplicate(true)
	var history: int = editor.undoredo.cursor
	var original: Transform3D = camera.transform
	check(controller.get_script().resource_path.ends_with("environment_editor/camera_controller.gd"),"reuse Material Maker camera controller")
	check(editor.viewport.get_parent() == editor,"viewport is owned by project, not moving dock")
	check(not controls.viewport.transparent_bg and controls.world.environment.background_mode == Environment.BG_SKY,"HDRI visible by default")
	check(controls.world.environment.sky != null and controls.world.environment.sky.sky_material is PanoramaSkyMaterial,"bundled HDRI applied")
	controls.container.gui_input.emit(motion(MOUSE_BUTTON_MASK_MIDDLE))
	await frames()
	check(not camera.transform.is_equal_approx(original),"MMB orbit")
	controls.reset_button.pressed.emit()
	await frames()
	check(camera.transform.is_equal_approx(original),"Reset restores camera")
	controls.container.gui_input.emit(motion(MOUSE_BUTTON_MASK_LEFT,false,true))
	await frames()
	check(not camera.transform.is_equal_approx(original),"Alt+LMB orbit")
	controls.reset_view()
	controls.container.gui_input.emit(motion(MOUSE_BUTTON_MASK_MIDDLE,true))
	await frames()
	check(controller.position != Vector3.ZERO and camera.basis.is_equal_approx(original.basis),"Shift+MMB pan without rotation")
	controls.container.gui_input.emit(motion(MOUSE_BUTTON_MASK_LEFT,true,true))
	await frames()
	check(controller.position.length() > 0.1,"Shift+Alt+LMB pan")
	var before_zoom: float = controller.camera_position.position.z
	controls.container.gui_input.emit(wheel())
	check(controller.camera_position.position.z < before_zoom,"wheel zoom")
	var before_fov: float = camera.fov
	controls.container.gui_input.emit(wheel(true))
	check(camera.fov == before_fov+1,"Ctrl+wheel FOV")
	for index in 200: controls.container.gui_input.emit(wheel(false,true))
	check(controller.camera_position.position.z == 0.5,"zoom clamp")
	controls.reset_view()
	await frames()
	var transform: Transform3D = camera.transform
	controls.environments.item_selected.emit(1)
	await frames(30)
	check(camera.transform.is_equal_approx(transform) and editor.preview == live and live._gpu == gpu,"environment change preserves camera and GPU")
	check(live.clock.time == clock_time and live.clock.paused,"environment change preserves simulation and Pause")
	controls.clear_button.button_pressed = true
	await frames()
	check(controls.viewport.transparent_bg and controls.world.environment.background_mode == Environment.BG_COLOR,"Clear Background")
	controls.clear_button.button_pressed = false
	await frames()
	check(not controls.viewport.transparent_bg and controls.world.environment.background_mode == Environment.BG_SKY,"HDRI restoration")
	var manager = controls.manager
	var missing: Dictionary = manager.environments[0].duplicate(true)
	missing.hdri_url = "https://invalid.example/missing-preview.hdr"
	missing.name = "Missing test HDRI"
	manager.environments.append(missing)
	manager.environment_textures.append({"thumbnail":ImageTexture.new()})
	controls.refresh_environments()
	controls.set_environment(manager.environments.size()-1)
	await frames()
	check(controls.world.environment.sky != null and manager.progress_window == null,"missing custom HDRI falls back without network/download")
	manager.environments.pop_back()
	manager.environment_textures.pop_back()
	controls.refresh_environments()
	controls.set_environment(0)
	await frames()
	# Real project-tab changes and dock hiding must not retire GPU resources.
	var second = window.new_modular_particles()
	await frames(60)
	check(live._gpu == gpu and live.ready_for_simulation,"switch away preserves first effect GPU")
	window.projects_panel.get_projects().current_tab = editor.get_index()
	await frames(20)
	check(live._gpu == gpu and live.ready_for_simulation and live.clock.paused,"switch back preserves GPU and Pause")
	check(camera.transform.is_equal_approx(transform),"tab switch preserves camera")
	window.layout.set_panel_visible("Particle Preview",false)
	window.layout.set_panel_visible("Particle Preview",true)
	await frames()
	check(live._gpu == gpu and live.ready_for_simulation,"dock close/reopen preserves live scene")
	window.layout.reset_panels()
	await frames()
	check(editor.undoredo.cursor == history and editor.document.emitter == emitter,"preview-only settings never dirty effect/history")
	check(not RenderingServer.frame_pre_draw.is_connected(second.preview._before_draw) or second.preview.ready_for_simulation,"inactive effect remains valid")
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://particle-hdri.png")
	var image: Image = controls.viewport.get_texture().get_image()
	check(image.get_pixel(5,5).a > 0.9 and image.get_pixel(5,5) != image.get_pixel(image.get_width()-6,image.get_height()-6),"HDRI renders non-uniform opaque background")
	print("MODULAR_PREVIEW_CONTROLS ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	get_tree().quit(0 if failures == 0 else 1)
