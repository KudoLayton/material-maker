extends RefCounted

static func create() -> Dictionary:
	var stages := {}
	for stage in ["start", "process"]:
		stages[stage] = {
			"nodes": [
				{"id": "entry", "kind": "entry", "position": [40, 80], "inputs": {}},
				{"id": "output", "kind": "output", "position": [620, 80], "inputs": {"exec": {"node": "entry", "port": "next"}}}
			], "view": {"scroll": [0, 0], "zoom": 1.0, "selection": []}
		}
	return {"type": "particle_graph", "version": 1, "target": "Godot 4.7", "stages": stages,
		"uniforms": [], "render_modes": [], "target_project": "", "active_stage": "start"}

static func node(graph: Dictionary, id: String) -> Dictionary:
	for item in graph.get("nodes", []):
		if str(item.get("id", "")) == id:
			return item
	return {}

static func load_file(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if valid(data):
		return data
	return {}

static func save_file(path: String, data: Dictionary) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK

static func valid(data) -> bool:
	if not data is Dictionary or data.get("type") != "particle_graph" or data.get("version") != 1:
		return false
	if data.get("active_stage", "start") not in ["start", "process"] or not data.get("stages") is Dictionary:
		return false
	if not data.get("uniforms", []) is Array or not data.get("render_modes", []) is Array:
		return false
	for uniform in data.get("uniforms", []):
		if not uniform is Dictionary or not uniform.get("name") is String or not uniform.get("type") is String:
			return false
	for stage in ["start", "process"]:
		var graph = data.stages.get(stage)
		if not graph is Dictionary or not graph.get("nodes") is Array or not graph.get("view", {}) is Dictionary:
			return false
		for n in graph.nodes:
			if not n is Dictionary or not n.get("id") is String or not n.get("kind") is String or not n.get("inputs", {}) is Dictionary:
				return false
			var position = n.get("position", [0, 0])
			if not position is Array or position.size() != 2 or not numeric(position[0]) or not numeric(position[1]):
				return false
			for binding in n.get("inputs", {}).values():
				if not binding is Dictionary or (binding.has("node") and not binding.node is String):
					return false
			if not n.get("input_ports", []) is Array:
				return false
			for port in n.get("input_ports", []):
				if not port is Dictionary or not port.get("name") is String or not port.get("type") is String:
					return false
	return true

static func numeric(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
