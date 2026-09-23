extends RefCounted
const Emission = preload("res://material_maker/panels/modular_particles/emission.gd")
static func frames(tree: SceneTree, count: int = 20) -> void:
	for frame in count: await tree.process_frame
static func run(editor, tree: SceneTree, check: Callable, directory: String) -> void:
	var window = tree.root.get_node("MainWindow")
	check.call(window.get_current_mode() == "particle","packaged particle workspace")
	var dock = window.layout.get_panel("Module Inputs")
	var scroll: ScrollContainer = editor.particle_panes["Module Inputs"]
	for size in [Vector2i(1440,960),Vector2i(1024,720)]:
		tree.root.size = size
		await frames(tree)
		check.call(dock.get_global_rect().grow(1).encloses(scroll.get_global_rect()),"packaged input scroll viewport contained at "+str(size))
		check.call(dock.clip_contents and scroll.clip_contents,"packaged input clipping")
		RenderingServer.force_draw()
		tree.root.get_texture().get_image().save_png(directory.path_join("workspace-%d.png" % size.x))
	tree.root.size = Vector2i(1440,960)
	await frames(tree)
	var controls = editor.preview_controls
	var live = editor.preview
	var gpu = live._gpu
	var camera: Camera3D = editor.camera
	var transform := camera.transform
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	motion.relative = Vector2(15,5)
	controls.container.gui_input.emit(motion)
	await frames(tree,3)
	check.call(not camera.transform.is_equal_approx(transform),"packaged MMB orbit")
	controls.reset_button.pressed.emit()
	await frames(tree,3)
	check.call(camera.transform.is_equal_approx(transform),"packaged Reset View")
	controls.clear_button.button_pressed = false
	controls.set_environment(0)
	await frames(tree)
	check.call(controls.world.environment.sky != null and not editor.viewport.transparent_bg,"packaged HDRI without editor resources")
	var before: Dictionary = editor.document.duplicate(true)
	var graph = editor.graph_edit.top_generator
	live.pause()
	var emitter := Emission.convert(before.emitter,"Looping")
	check.call(editor.set_emitter_settings(emitter),"packaged Looping settings")
	await frames(tree,50)
	check.call(live == editor.preview and live._gpu == gpu and graph == editor.graph_edit.top_generator,"packaged emission does not rebuild graph/GPU")
	editor.emission_panel.mode_choice.item_selected.emit(1)
	await frames(tree,50)
	check.call(Emission.mode(editor.document.emitter) == "Burst" and not editor.document.emitter.loop,"packaged Burst default is one-shot")
	check.call(live.clock.paused and live.clock.time == 0 and camera.transform.is_equal_approx(transform),"packaged emission restart preserves pause/camera")
	editor.undoredo.undo()
	await frames(tree,50)
	check.call(Emission.mode(editor.document.emitter) == "Looping","packaged emission Undo")
	editor.undoredo.redo()
	await frames(tree,50)
	check.call(Emission.mode(editor.document.emitter) == "Burst","packaged emission Redo")
	editor.apply_document(before)
	await frames(tree,50)
	live.play()
	RenderingServer.force_draw()
	tree.root.get_texture().get_image().save_png(directory.path_join("workspace-hdri.png"))
