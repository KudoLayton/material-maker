extends SceneTree

const Editor = preload("res://material_maker/panels/particles/particle_editor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr(message)

func run() -> void:
	var previous_clipboard := DisplayServer.clipboard_get()
	var editor = Editor.new()
	root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	check(editor.stage == "start", "Start tab is the initial stage")
	for index in editor.library.item_count:
		var item: Dictionary = editor.library.get_item_metadata(index)
		if item.kind == "constant" and item.data_type == "vec3":
			editor._add_from_library(index)
			break
	check(editor.document.stages.start.nodes.size() == 3, "Add a typed node")
	editor._set_property("constant_1", "value", [1, 2, 3], false)
	editor._selected(editor.graph.get_node("constant_1"))
	var components = editor.inspector.find_children("*", "SpinBox", true, false)
	components[0].value = 9
	check(editor.document.stages.start.nodes[2].value[0] == 9, "Edit vector component through inspector")
	editor.undoredo.undo()
	check(editor.document.stages.start.nodes[2].value[0] == 1, "Undo vector component without aliasing")
	editor._connect_ports("constant_1", 0, "output", 2)
	check(editor.validate_document(), "Valid typed connection")
	editor.graph.get_node("constant_1").selected = true
	editor._selected(editor.graph.get_node("constant_1"))
	editor.copy()
	editor.paste()
	check(editor.document.stages.start.nodes.size() == 4, "Copy/paste")
	editor.undoredo.undo()
	check(editor.document.stages.start.nodes.size() == 3, "Undo")
	editor.undoredo.redo()
	check(editor.document.stages.start.nodes.size() == 4, "Redo")
	editor.frame_nodes()
	await process_frame
	editor._switch_stage(1)
	check(editor.document.stages.process.nodes.size() == 2, "Separate Process graph")
	check(editor.stage == "process", "Switch to Process")
	await process_frame
	editor._switch_stage(0)
	check(editor.document.stages.start.nodes.size() == 5, "Start state survives tab switching")
	check(editor.save_file("res://editor_roundtrip.ptex"), "Save particle document")
	var other = Editor.new()
	root.add_child(other)
	check(other.load_file("res://editor_roundtrip.ptex"), "Reopen particle document")
	check(JSON.stringify(other.document) == JSON.stringify(JSON.parse_string(JSON.stringify(editor.document))), "Persist graphs, groups and view state")
	await process_frame
	other.queue_free()
	editor._uniforms_inspector()
	editor._modes_inspector()
	await process_frame
	editor._switch_stage(1)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://editor.png")
	editor.queue_free()
	await process_frame
	DisplayServer.clipboard_set(previous_clipboard)
	print("PARTICLE_EDITOR_TESTS: ", failures)
	quit(0 if failures.is_empty() else 1)
