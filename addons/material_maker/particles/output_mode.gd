extends RefCounted

static func parameter(generator: MMGenBase) -> Dictionary:
	return {"name": "transform_mode", "label": "Transform Mode" if not generator.has_meta("transform_mode_blocked") else "Transform Mode (disconnect inputs first)", "type": "enum", "default": 1,
		"values": [{"name": "Components", "value": 0}, {"name": "Matrix", "value": 1}],
		"longdesc": "Components sets only connected Position, Rotation (quaternion x/y/z/w), and Scale values. Matrix preserves arbitrary transforms. Disconnect transform inputs and remove explicit values before switching modes."}

static func set_mode(generator: MMGenBase, value) -> void:
	if not (value is int or value is float) or (float(value) != 0.0 and float(value) != 1.0): return
	var previous: int = int(generator.parameters.get("transform_mode", 1))
	if previous == int(value):
		generator.parameters["transform_mode"] = int(value)
		return
	var old_ports: Array = generator.get_input_defs()
	var model: Dictionary = generator.model_data()
	var new_ports: Array = MMGenParticle.output_ports(model.stage, int(value)).inputs
	var names: Array = new_ports.map(func(p): return p.name)
	var remap := {}
	var graph = generator.get_parent()
	for i in old_ports.size():
		var target: int = names.find(old_ports[i].name)
		if target < 0 and (model.get("inputs", {}).has(old_ports[i].name) or (graph is MMGenGraph and generator.get_source(i) != null)):
			generator.set_meta("transform_mode_blocked", true)
			generator.parameter_changed.emit.call_deferred("__update_all__", null)
			return
		remap[i] = target
	generator.remove_meta("transform_mode_blocked")
	if graph is MMGenGraph:
		var old_connections: Array = graph.connections.filter(func(c): return c.to == generator.name)
		graph.connections_changed.emit(old_connections, [])
	generator.parameters["transform_mode"] = int(value)
	if graph is MMGenGraph:
		var blocked: bool = graph.is_blocking_signals()
		graph.set_block_signals(true)
		graph.reconnect_inputs(generator, remap)
		graph.set_block_signals(blocked)
	if generator.is_inside_tree() and not generator.has_meta("transform_refresh_pending"):
		generator.set_meta("transform_refresh_pending", true)
		refresh_ports.call_deferred(weakref(generator))
	generator.parameter_changed.emit("transform_mode", int(value))
	if generator.is_inside_tree(): generator.all_sources_changed.call_deferred()
	if generator is MMGenMaterial: generator.update_preview()

static func refresh_ports(reference: WeakRef) -> void:
	var generator = reference.get_ref()
	if generator == null or generator.is_queued_for_deletion(): return
	generator.remove_meta("transform_refresh_pending")
	generator.parameter_changed.emit("__update_all__", null)
	var graph = generator.get_parent()
	if graph is MMGenGraph:
		var connections: Array = graph.connections.filter(func(c): return c.to == generator.name)
		graph.connections_changed.emit([], connections)
