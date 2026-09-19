extends VBoxContainer

const Document = preload("res://addons/material_maker/particles/document.gd")
const Interface = preload("res://addons/material_maker/particles/interface.gd")
const Compiler = preload("res://addons/material_maker/particles/compiler.gd")
const Exporter = preload("res://addons/material_maker/particles/exporter.gd")

var document: Dictionary = Document.create()
var save_path := ""
var need_save := false
var undoredo := UndoRedo.new()
var stage := "start"
var graph: GraphEdit
var library: ItemList
var search: LineEdit
var inspector: VBoxContainer
var error_list: ItemList
var stage_tabs: TabBar
var palette: Array = []
var rebuilding := false
var move_before: Dictionary = {}
var last_export := ""
var last_result: Dictionary = {}

func _ready() -> void:
	name = "Particle Shader"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	stage_tabs = TabBar.new()
	stage_tabs.custom_minimum_size.x = 260
	stage_tabs.add_tab("Start")
	stage_tabs.add_tab("Process (Update)")
	stage_tabs.tab_changed.connect(_switch_stage)
	toolbar.add_child(stage_tabs)
	button(toolbar, "Uniforms", _uniforms_inspector)
	button(toolbar, "Render Modes", _modes_inspector)
	button(toolbar, "Validate", validate_document)
	button(toolbar, "Shader Code", show_code)
	button(toolbar, "Export", export_dialog)
	var editbar := HBoxContainer.new()
	add_child(editbar)
	button(editbar, "Undo", undoredo.undo)
	button(editbar, "Redo", undoredo.redo)
	button(editbar, "Copy", copy)
	button(editbar, "Paste", paste)
	button(editbar, "Duplicate", duplicate_selected)
	button(editbar, "Group", frame_nodes)
	button(editbar, "Delete", delete_selected)
	var message := Label.new()
	message.text = "Godot 4.7 · Explicit state writes · No simulation preview"
	editbar.add_child(message)
	var horizontal := HSplitContainer.new()
	horizontal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(horizontal)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220
	horizontal.add_child(left)
	search = LineEdit.new()
	search.placeholder_text = "Search particle nodes"
	search.text_changed.connect(func(_text): _populate_library())
	left.add_child(search)
	library = ItemList.new()
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.item_activated.connect(_add_from_library)
	left.add_child(library)
	button(left, "Add selected node", func():
		if not library.get_selected_items().is_empty():
			_add_from_library(library.get_selected_items()[0]))
	var center := HSplitContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal.add_child(center)
	graph = GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.zoom_min = 0.25
	graph.zoom_max = 2.0
	graph.connection_request.connect(_connect_ports)
	graph.disconnection_request.connect(_disconnect_ports)
	graph.delete_nodes_request.connect(_delete_nodes)
	graph.node_selected.connect(_selected)
	graph.begin_node_move.connect(func(): move_before = document.duplicate(true))
	graph.end_node_move.connect(_finish_move)
	graph.copy_nodes_request.connect(copy)
	graph.paste_nodes_request.connect(paste)
	graph.duplicate_nodes_request.connect(duplicate_selected)
	center.add_child(graph)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	center.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	error_list = ItemList.new()
	error_list.custom_minimum_size.y = 80
	error_list.item_activated.connect(_focus_error)
	add_child(error_list)
	_rebuild()

static func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func get_project_type() -> String:
	return "particle"

func get_graph_edit():
	return null

func get_material_node():
	return self

func get_export_profiles() -> Array:
	return ["Godot 4/Particles 3D"]

func get_export_extension(_profile: String) -> String:
	return "tres"

func get_last_export_target() -> String:
	return "Godot 4/Particles 3D" if not last_export.is_empty() else ""

func get_export_path(_profile: String) -> String:
	return last_export + ".tres" if not last_export.is_empty() else ""

func project_selected() -> void:
	_update_title()

func _snapshot_view() -> void:
	if graph == null:
		return
	var selection: Array[String] = []
	for child in graph.get_children():
		if child is GraphElement and child.selected:
			selection.append(str(child.name))
	document.stages[stage].view = {"scroll": [graph.scroll_offset.x, graph.scroll_offset.y], "zoom": graph.zoom, "selection": selection}

func _switch_stage(index: int) -> void:
	if rebuilding:
		return
	_snapshot_view()
	stage = "start" if index == 0 else "process"
	document.active_stage = stage
	_rebuild()

func _apply(data: Dictionary) -> void:
	document = data.duplicate(true)
	stage = document.get("active_stage", "start")
	need_save = true
	_rebuild()
	_update_title()

func _commit(before: Dictionary, label: String, refresh := true) -> void:
	undoredo.create_action(label)
	undoredo.add_do_method(_apply.bind(document.duplicate(true)))
	undoredo.add_undo_method(_apply.bind(before))
	undoredo.commit_action(false)
	need_save = true
	if refresh:
		_rebuild()
	_update_title()

func _update_title() -> void:
	var title: String = save_path.get_file() if not save_path.is_empty() else "Particle Shader"
	if need_save:
		title += " (*)"
	var tabs = get_parent()
	if tabs != null and tabs.has_method("set_tab_title") and get_index() < tabs.get_tab_count():
		tabs.set_tab_title(get_index(), title)

func _stage_graph() -> Dictionary:
	return document.stages[stage]

func _id(prefix: String) -> String:
	var index := 1
	while not Document.node(_stage_graph(), prefix + str(index)).is_empty():
		index += 1
	return prefix + str(index)

func _populate_library() -> void:
	palette = []
	for name in Interface.BUILTINS[stage]:
		var info: Dictionary = Interface.BUILTINS[stage][name]
		palette.append({"label": "Read / " + name + " : " + info.type, "node": {"kind": "input", "builtin": name}})
		if info.write:
			palette.append({"label": "Write / " + name + " : " + info.type, "node": {"kind": "set", "builtin": name}})
	for type in Interface.TYPES:
		if not type.begins_with("sampler"):
			palette.append({"label": "Constant / " + type, "node": {"kind": "constant", "data_type": type, "value": Interface.default_value(type)}})
	for operation in Interface.OPERATIONS:
		var type: String = "float"
		if operation in ["and", "or", "not"]:
			type = "bool"
		elif operation.begins_with("bit_") or operation.begins_with("shift_"):
			type = "uint"
		elif operation in ["dot", "cross", "normalize", "length"]:
			type = "vec3"
		elif operation in ["transpose", "inverse", "determinant"]:
			type = "mat4"
		palette.append({"label": "Math / " + operation.capitalize(), "node": {"kind": "operator", "operation": operation, "data_type": type}})
	for kind in ["compose", "split", "convert", "transform", "select", "sample", "array_get", "uniform", "custom", "emit"]:
		var item: Dictionary = {"kind": kind, "data_type": "vec3" if kind in ["compose", "split"] else "float"}
		if kind == "custom":
			item.input_ports = [{"name": "value", "type": "float"}]
			item.code = "return value;"
		if kind == "uniform":
			item.uniform = document.uniforms[0].name if not document.uniforms.is_empty() else ""
		palette.append({"label": "Tools / " + ("Emit Subparticle" if kind == "emit" else kind.capitalize()), "node": item})
	library.clear()
	for entry in palette:
		if search.text.is_empty() or search.text.to_lower() in entry.label.to_lower():
			var index: int = library.add_item(entry.label)
			library.set_item_metadata(index, entry.node)

func _add_from_library(index: int) -> void:
	var before: Dictionary = document.duplicate(true)
	var n: Dictionary = library.get_item_metadata(index).duplicate(true)
	n.id = _id(n.kind + "_")
	n.inputs = {}
	var point: Vector2 = (graph.scroll_offset + graph.size * 0.4) / graph.zoom
	n.position = [point.x, point.y]
	_stage_graph().nodes.append(n)
	_commit(before, "Add " + n.kind)
	graph.get_node(NodePath(n.id)).selected = true
	_selected(graph.get_node(NodePath(n.id)))

static func _type_id(type: String) -> int:
	return 100 if type == "exec" else (Interface.TYPES.find(type.get_slice("[", 0)) + 1)

static func _color(type: String) -> Color:
	return Color.WHITE if type == "exec" else Color.from_hsv(float(_type_id(type)) / 26.0, 0.55, 0.95)

func _rebuild() -> void:
	if graph == null:
		return
	rebuilding = true
	graph.clear_connections()
	for child in graph.get_children():
		if child is GraphElement:
			if child is GraphFrame:
				for attached in graph.get_attached_nodes_of_frame(child.name):
					graph.detach_graph_element_from_frame(attached)
			child.free()
	stage_tabs.current_tab = 0 if stage == "start" else 1
	_populate_library()
	var view: Dictionary = _stage_graph().get("view", {})
	for n in _stage_graph().nodes:
		var element: GraphElement
		if n.kind == "frame":
			var frame := GraphFrame.new()
			frame.title = n.get("title", "Group")
			element = frame
		else:
			var control := GraphNode.new()
			control.title = n.kind.capitalize() + (" · " + str(n.get("builtin", n.get("operation", n.get("uniform", n.get("data_type", ""))))))
			control.custom_minimum_size.x = 230
			var ports: Dictionary = Interface.ports(n, stage, document.uniforms)
			control.set_meta("ports", ports)
			for row in max(ports.inputs.size(), ports.outputs.size()):
				var line := HBoxContainer.new()
				var input: Dictionary = ports.inputs[row] if row < ports.inputs.size() else {}
				var output: Dictionary = ports.outputs[row] if row < ports.outputs.size() else {}
				var left := Label.new()
				left.text = input.get("name", "") + (" : " + input.type if not input.is_empty() else "")
				left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line.add_child(left)
				var right := Label.new()
				right.text = output.get("name", "") + (" : " + output.type if not output.is_empty() else "")
				line.add_child(right)
				control.add_child(line)
				control.set_slot(row, not input.is_empty(), _type_id(input.get("type", "exec")), _color(input.get("type", "exec")), not output.is_empty(), _type_id(output.get("type", "exec")), _color(output.get("type", "exec")))
			element = control
		element.name = n.id
		var pos: Array = n.get("position", [0, 0])
		element.position_offset = Vector2(pos[0], pos[1])
		graph.add_child(element)
		element.selected = n.id in view.get("selection", [])
	for n in _stage_graph().nodes:
		if n.has("frame") and graph.has_node(NodePath(n.frame)):
			graph.attach_graph_element_to_frame(n.id, n.frame)
		for input_name in n.get("inputs", {}):
			var binding: Dictionary = n.inputs[input_name]
			if binding.has("node") and graph.has_node(NodePath(str(binding.node))):
				var source = graph.get_node(NodePath(str(binding.node)))
				var target = graph.get_node(NodePath(n.id))
				if not source.has_meta("ports") or not target.has_meta("ports"):
					continue
				var from_port: int = _port_index(source.get_meta("ports").outputs, binding.get("port", "value"))
				var to_port: int = _port_index(target.get_meta("ports").inputs, input_name)
				if from_port >= 0 and to_port >= 0:
					graph.connect_node(source.name, from_port, target.name, to_port)
	graph.zoom = view.get("zoom", 1.0)
	var offset: Array = view.get("scroll", [0, 0])
	graph.scroll_offset = Vector2(offset[0], offset[1])
	rebuilding = false
	_clear_inspector()
	for child in graph.get_children():
		if child is GraphElement and child.selected:
			_selected(child)
			break

static func _port_index(ports: Array, name: String) -> int:
	for index in ports.size():
		if ports[index].name == name:
			return index
	return -1

func _connect_ports(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	var source: Dictionary = graph.get_node(NodePath(from)).get_meta("ports").outputs[from_port]
	var target: Dictionary = graph.get_node(NodePath(to)).get_meta("ports").inputs[to_port]
	if source.type != target.type:
		show_errors([{"stage": stage, "node": str(to), "message": "Use an explicit Convert node: " + source.type + " → " + target.type}])
		return
	var before: Dictionary = document.duplicate(true)
	Document.node(_stage_graph(), str(to)).inputs[target.name] = {"node": str(from), "port": source.name}
	_commit(before, "Connect nodes")

func _disconnect_ports(_from: StringName, _from_port: int, to: StringName, to_port: int) -> void:
	var before: Dictionary = document.duplicate(true)
	var target: Dictionary = graph.get_node(NodePath(to)).get_meta("ports").inputs[to_port]
	Document.node(_stage_graph(), str(to)).inputs.erase(target.name)
	_commit(before, "Disconnect nodes")

func _finish_move() -> void:
	if move_before.is_empty():
		return
	for child in graph.get_children():
		if child is GraphElement:
			Document.node(_stage_graph(), str(child.name)).position = [child.position_offset.x, child.position_offset.y]
	_snapshot_view()
	_commit(move_before, "Move nodes", false)
	move_before = {}

func _clear_inspector() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()

func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(label)

func _text(parent: Node, value: String, submit: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.text_submitted.connect(submit)
	parent.add_child(edit)
	return edit

func _option(parent: Node, values: Array, current: String, changed: Callable) -> void:
	var choice := OptionButton.new()
	for value in values:
		choice.add_item(str(value))
	choice.select(max(0, values.find(current)))
	choice.item_selected.connect(func(index): changed.call(str(values[index])))
	parent.add_child(choice)

func _value(parent: Node, type: String, value, changed: Callable) -> void:
	if type == "bool":
		var toggle := CheckBox.new()
		toggle.button_pressed = bool(value)
		toggle.toggled.connect(changed)
		parent.add_child(toggle)
	elif type in ["float", "int", "uint"]:
		var number := SpinBox.new()
		number.min_value = 0 if type == "uint" else -2147483648
		number.max_value = 4294967295
		number.step = 0.01 if type == "float" else 1.0
		number.allow_greater = type == "float"
		number.allow_lesser = type == "float"
		number.value = float(value)
		number.value_changed.connect(func(v): changed.call(v if type == "float" else int(v)))
		parent.add_child(number)
	elif value is Array:
		value = value.duplicate(true)
		var box: BoxContainer = VBoxContainer.new() if type.begins_with("mat") else HBoxContainer.new()
		parent.add_child(box)
		for index in value.size():
			_value(box, "vec" + str(value.size()) if type.begins_with("mat") else Interface.scalar_type(type), value[index], func(v):
				value[index] = v
				changed.call(value.duplicate(true)))

func _set_property(id: String, key: String, value, refresh := true) -> void:
	var before: Dictionary = document.duplicate(true)
	Document.node(_stage_graph(), id)[key] = value
	_snapshot_view()
	_commit(before, "Edit " + key, refresh)

func _set_input(id: String, key: String, value) -> void:
	var before: Dictionary = document.duplicate(true)
	Document.node(_stage_graph(), id).inputs[key] = {"value": value}
	_commit(before, "Edit " + key, false)

func _selected(element: Node) -> void:
	if rebuilding:
		return
	_clear_inspector()
	var n: Dictionary = Document.node(_stage_graph(), str(element.name))
	if n.is_empty():
		return
	_label(stage.capitalize() + " / " + n.id)
	if n.kind == "frame":
		_text(inspector, n.get("title", "Group"), func(v): _set_property(n.id, "title", v))
		return
	if n.has("data_type"):
		_label("Value type")
		_option(inspector, Interface.TYPES, n.data_type, func(v):
			var before: Dictionary = document.duplicate(true)
			n.data_type = v
			if n.kind == "constant":
				n.value = Interface.default_value(v)
			_snapshot_view()
			_commit(before, "Change value type"))
	if n.kind == "constant":
		_value(inspector, n.data_type, n.get("value", Interface.default_value(n.data_type)), func(v): _set_property(n.id, "value", v, false))
	if n.kind == "operator":
		_option(inspector, Interface.OPERATIONS, n.operation, func(v): _set_property(n.id, "operation", v))
	if n.kind == "convert":
		_label("Source type")
		_option(inspector, Interface.TYPES, n.get("source_type", "float"), func(v): _set_property(n.id, "source_type", v))
	if n.kind == "sample":
		_option(inspector, Interface.TYPES.filter(func(v): return v.begins_with("sampler")), n.get("sampler_type", "sampler2D"), func(v): _set_property(n.id, "sampler_type", v))
	if n.kind == "array_get":
		_label("Array size")
		_value(inspector, "uint", n.get("array_size", 1), func(v): _set_property(n.id, "array_size", max(1, v)))
	if n.kind == "uniform":
		var names: Array = document.uniforms.map(func(u): return u.name)
		if names.is_empty():
			_label("Declare a uniform in the Uniforms panel first.")
		else:
			_option(inspector, names, n.get("uniform", ""), func(v): _set_property(n.id, "uniform", v))
	if n.kind == "custom":
		_label("Typed inputs")
		for index in n.get("input_ports", []).size():
			var p: Dictionary = n.input_ports[index]
			_text(inspector, p.name, func(v):
				var ports: Array = n.input_ports.duplicate(true)
				ports[index].name = v
				_set_property(n.id, "input_ports", ports))
			_option(inspector, Interface.TYPES, p.type, func(v):
				var ports: Array = n.input_ports.duplicate(true)
				ports[index].type = v
				_set_property(n.id, "input_ports", ports))
			button(inspector, "Remove " + p.name, func():
				var ports: Array = n.input_ports.duplicate(true)
				ports.remove_at(index)
				_set_property(n.id, "input_ports", ports))
		button(inspector, "Add typed input", func():
			var ports: Array = n.get("input_ports", []).duplicate(true)
			ports.append({"name": "input_" + str(ports.size() + 1), "type": "float"})
			_set_property(n.id, "input_ports", ports))
		_label("Function body; read state through inputs")
		var code := CodeEdit.new()
		code.custom_minimum_size = Vector2(280, 180)
		code.text = n.get("code", "return 0.0;")
		inspector.add_child(code)
		button(inspector, "Apply code", func(): _set_property(n.id, "code", code.text))
	for p in Interface.ports(n, stage, document.uniforms).inputs:
		if p.type == "exec":
			continue
		_label(p.name + " : " + p.type)
		var binding: Dictionary = n.get("inputs", {}).get(p.name, {})
		if binding.has("node"):
			_label("Connected: " + str(binding.node) + "." + binding.get("port", "value"))
			button(inspector, "Disconnect " + p.name, func():
				var before: Dictionary = document.duplicate(true)
				n.inputs.erase(p.name)
				_snapshot_view()
				_commit(before, "Disconnect " + p.name))
		elif n.kind == "output" and binding.is_empty():
			button(inspector, "Write constant to " + p.name, func():
				_set_input(n.id, p.name, Interface.default_value(p.type))
				_selected(element))
		elif not p.type.begins_with("sampler") and not "[" in p.type:
			var fallback = true if p.name == "enabled" else ([1, 1, 1, 1] if n.kind == "emit" and p.name == "color" else Interface.default_value(p.type))
			_value(inspector, p.type, binding.get("value", fallback), func(v): _set_input(n.id, p.name, v))
			if n.kind == "output":
				button(inspector, "Leave " + p.name + " unchanged", func():
					var before: Dictionary = document.duplicate(true)
					n.inputs.erase(p.name)
					_snapshot_view()
					_commit(before, "Remove state write"))

func _modes_inspector() -> void:
	_clear_inspector()
	_label("Render modes — disabled unless selected")
	for mode in Interface.MODES:
		var toggle := CheckBox.new()
		toggle.text = mode
		toggle.button_pressed = mode in document.render_modes
		toggle.toggled.connect(func(enabled):
			var before: Dictionary = document.duplicate(true)
			if enabled: document.render_modes.append(mode)
			else: document.render_modes.erase(mode)
			_commit(before, "Change render mode", false))
		inspector.add_child(toggle)

func _uniforms_inspector() -> void:
	_clear_inspector()
	_label("Godot project directory (for res:// textures)")
	_text(inspector, document.get("target_project", ""), func(v):
		var before: Dictionary = document.duplicate(true)
		document.target_project = v.replace("\\", "/").trim_suffix("/")
		_commit(before, "Set target project", false))
	for index in document.uniforms.size():
		var u: Dictionary = document.uniforms[index]
		_label("Uniform " + str(index + 1))
		_text(inspector, u.name, func(v): _uniform_property(index, "name", v))
		_option(inspector, Interface.TYPES, u.type, func(v):
			var before: Dictionary = document.duplicate(true)
			u.type = v
			u.value = Interface.default_value(v)
			u.array_size = 0
			_commit(before, "Change uniform type")
			_uniforms_inspector())
		_label("Array size (0 = single value)")
		_value(inspector, "uint", u.get("array_size", 0), func(v):
			var before: Dictionary = document.duplicate(true)
			u.array_size = min(v, 1024)
			u.value = [] if v > 0 else Interface.default_value(u.type)
			for unused in int(u.array_size): u.value.append(Interface.default_value(u.type))
			_commit(before, "Change uniform array")
			_uniforms_inspector())
		_label("Godot shader hint (optional)")
		_text(inspector, u.get("hint", ""), func(v): _uniform_property(index, "hint", v))
		if u.type.begins_with("sampler"):
			_label("Resource paths as a JSON list" if int(u.get("array_size", 0)) else "Resource path (res://…)")
			_text(inspector, JSON.stringify(u.get("resources", [])) if int(u.get("array_size", 0)) else u.get("resource", ""), func(v):
				if int(u.get("array_size", 0)):
					var paths = JSON.parse_string(v)
					if paths is Array: _uniform_property(index, "resources", paths)
				else: _uniform_property(index, "resource", v))
		elif int(u.get("array_size", 0)):
			_label("Array default (JSON)")
			_text(inspector, JSON.stringify(u.value), func(v):
				var values = JSON.parse_string(v)
				if values is Array: _uniform_property(index, "value", values))
		else:
			_value(inspector, u.type, u.get("value", Interface.default_value(u.type)), func(v): _uniform_property(index, "value", v))
		button(inspector, "Remove " + u.name, func():
			var before: Dictionary = document.duplicate(true)
			document.uniforms.remove_at(index)
			_commit(before, "Remove uniform")
			_uniforms_inspector())
	button(inspector, "Add uniform", func():
		var before: Dictionary = document.duplicate(true)
		document.uniforms.append({"name": "parameter_" + str(document.uniforms.size() + 1), "type": "float", "value": 0.0, "array_size": 0})
		_commit(before, "Add uniform")
		_uniforms_inspector())

func _uniform_property(index: int, key: String, value) -> void:
	var before: Dictionary = document.duplicate(true)
	document.uniforms[index][key] = value
	_commit(before, "Edit uniform " + key, key == "name")

func validate_document() -> bool:
	last_result = Exporter.validate(Compiler.new().compile(document))
	show_errors(last_result.errors)
	return last_result.errors.is_empty()

func show_errors(errors: Array) -> void:
	error_list.clear()
	if errors.is_empty():
		error_list.add_item("Valid Godot 4.7 particle shader")
	for error in errors:
		var index: int = error_list.add_item("%s / %s: %s" % [error.get("stage", "Shared"), error.get("node", ""), error.message])
		error_list.set_item_metadata(index, error)

func _focus_error(index: int) -> void:
	var error = error_list.get_item_metadata(index)
	if not error is Dictionary:
		return
	if error.stage in ["start", "process"]:
		_switch_stage(0 if error.stage == "start" else 1)
		var element = graph.get_node_or_null(NodePath(error.node))
		if element is GraphElement:
			element.selected = true
			graph.scroll_offset = element.position_offset * graph.zoom - graph.size * 0.3
			_selected(element)

func show_code() -> void:
	validate_document()
	var dialog := AcceptDialog.new()
	dialog.title = "Generated particle shader"
	var code := CodeEdit.new()
	code.text = last_result.code
	code.editable = false
	code.custom_minimum_size = Vector2(900, 600)
	dialog.add_child(code)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _file_dialog(mode: FileDialog.FileMode, filter: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.add_filter(filter)
	dialog.size = Vector2i(900, 650)
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	return dialog

func save() -> bool:
	if save_path.is_empty():
		return await save_as()
	return save_file(save_path)

func save_as() -> bool:
	var dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.ptex;Particle Shader Graph")
	dialog.current_file = "particles.ptex" if save_path.is_empty() else save_path.get_file()
	var result := {"done": false, "path": ""}
	dialog.file_selected.connect(func(path): result.path = path; result.done = true)
	dialog.canceled.connect(func(): result.done = true)
	dialog.popup_centered()
	while not result.done:
		await get_tree().process_frame
	if is_instance_valid(dialog): dialog.queue_free()
	return save_file(result.path) if not result.path.is_empty() else false

func save_file(path: String) -> bool:
	_snapshot_view()
	var status: Error = Document.save_file(path, document)
	if status != OK:
		show_errors([{"message": "Could not save " + path}])
		return false
	save_path = path
	need_save = false
	_update_title()
	return true

func load_file(path: String) -> bool:
	var loaded: Dictionary = Document.load_file(path)
	if loaded.is_empty():
		return false
	document = loaded
	stage = document.get("active_stage", "start")
	save_path = path
	need_save = false
	undoredo.clear_history()
	_rebuild()
	_update_title()
	return true

func export_dialog() -> void:
	var dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.tres;Godot ShaderMaterial")
	dialog.current_file = "particles.tres"
	dialog.file_selected.connect(func(path): export_material(path.get_basename(), "Godot 4/Particles 3D"); dialog.queue_free())
	dialog.popup_centered()

func export_material(prefix: String, _profile: String) -> void:
	last_result = Exporter.export_files(document, prefix)
	show_errors(last_result.errors)
	if last_result.errors.is_empty():
		last_export = prefix
		error_list.clear()
		error_list.add_item("Exported " + prefix + ".gdshader and .tres")

func _selection() -> Array[String]:
	var ids: Array[String] = []
	for child in graph.get_children():
		if child is GraphElement and child.selected and str(child.name) not in ["entry", "output"]:
			ids.append(str(child.name))
	return ids

func can_copy() -> bool:
	return not _selection().is_empty()

func copy() -> void:
	var nodes: Array = []
	var selected: Array[String] = _selection()
	for n in _stage_graph().nodes:
		if n.id in selected:
			nodes.append(n.duplicate(true))
	DisplayServer.clipboard_set(JSON.stringify({"type": "particle_selection", "nodes": nodes, "uniforms": document.uniforms}))

func cut() -> void:
	copy()
	delete_selected()

func paste() -> void:
	var data = JSON.parse_string(DisplayServer.clipboard_get())
	if not data is Dictionary or data.get("type") != "particle_selection":
		return
	for incoming in data.get("uniforms", []):
		for existing in document.uniforms:
			if existing.name == incoming.name and JSON.stringify(JSON.parse_string(JSON.stringify(existing))) != JSON.stringify(incoming):
				show_errors([{"stage": stage, "node": "", "message": "Conflicting uniform: " + incoming.name + ". Rename it before pasting."}])
				return
	var before: Dictionary = document.duplicate(true)
	var mapping := {}
	var added: Array = []
	for source in data.get("nodes", []):
		var n: Dictionary = source.duplicate(true)
		if n.kind in ["entry", "output"]: continue
		n.id = _id(n.kind + "_")
		mapping[source.id] = n.id
		var position: Array = n.get("position", [0, 0])
		n.position = [position[0] + 40, position[1] + 40]
		_stage_graph().nodes.append(n)
		added.append(n)
	for n in added:
		for key in n.get("inputs", {}).keys():
			var binding: Dictionary = n.inputs[key]
			if binding.has("node"):
				if mapping.has(binding.node): binding.node = mapping[binding.node]
				else: n.inputs.erase(key)
		if n.has("frame"):
			if mapping.has(n.frame): n.frame = mapping[n.frame]
			else: n.erase("frame")
	for uniform in data.get("uniforms", []):
		if not document.uniforms.any(func(u): return u.name == uniform.name):
			document.uniforms.append(uniform)
	_stage_graph().view.selection = mapping.values()
	_commit(before, "Paste particle nodes")

func duplicate_selected() -> void:
	var previous: String = DisplayServer.clipboard_get()
	copy()
	paste()
	DisplayServer.clipboard_set(previous)

func _delete_nodes(ids: Array[StringName]) -> void:
	var before: Dictionary = document.duplicate(true)
	var removable: Array = ids.filter(func(id): return str(id) not in ["entry", "output"])
	_stage_graph().nodes = _stage_graph().nodes.filter(func(n): return n.id not in removable)
	for n in _stage_graph().nodes:
		for key in n.get("inputs", {}).keys():
			if n.inputs[key].get("node", "") in removable:
				n.inputs.erase(key)
		if n.get("frame", "") in removable: n.erase("frame")
	_commit(before, "Delete nodes")

func delete_selected() -> void:
	var ids: Array[StringName] = []
	for id in _selection(): ids.append(StringName(id))
	_delete_nodes(ids)

func frame_nodes() -> void:
	var selected: Array[String] = _selection()
	if selected.is_empty(): return
	var before: Dictionary = document.duplicate(true)
	var id: String = _id("group_")
	_stage_graph().nodes.append({"id": id, "kind": "frame", "title": "Group", "position": [0, 0], "inputs": {}})
	for selected_id in selected:
		if Document.node(_stage_graph(), selected_id).kind != "frame":
			Document.node(_stage_graph(), selected_id).frame = id
	_commit(before, "Group nodes")

func select_all() -> void:
	for child in graph.get_children():
		if child is GraphElement: child.selected = true

func select_none() -> void:
	for child in graph.get_children():
		if child is GraphElement: child.selected = false

func select_invert() -> void:
	for child in graph.get_children():
		if child is GraphElement: child.selected = not child.selected

func center_view() -> void:
	var bounds := Rect2()
	var first := true
	for child in graph.get_children():
		if child is GraphNode:
			var rect := Rect2(child.position_offset, child.size)
			bounds = rect if first else bounds.merge(rect)
			first = false
	if not first:
		graph.scroll_offset = bounds.get_center() * graph.zoom - graph.size * 0.5
