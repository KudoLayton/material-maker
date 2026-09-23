extends RefCounted
## Authoring format. IDs (not labels) are persisted in all connections.
const TYPES := {"float": 1, "int": 1, "uint": 1, "bool": 1, "vec2": 2, "vec3": 3, "vec4": 4}
const BUILTINS := [
	{"id":"position", "name":"Position", "type":"vec3", "default":[0.0,0.0,0.0]},
	{"id":"velocity", "name":"Velocity", "type":"vec3", "default":[0.0,0.0,0.0]},
	{"id":"rotation", "name":"Rotation", "type":"vec4", "default":[0.0,0.0,0.0,1.0]},
	{"id":"scale", "name":"Scale", "type":"vec3", "default":[1.0,1.0,1.0]},
	{"id":"color", "name":"Color", "type":"vec4", "default":[1.0,1.0,1.0,1.0]},
	{"id":"age", "name":"Age", "type":"float", "default":0.0, "readonly":true},
	{"id":"lifetime", "name":"Lifetime", "type":"float", "default":1.0},
	{"id":"alive", "name":"Alive", "type":"bool", "default":false},
	{"id":"particle_id", "name":"ParticleID", "type":"uint", "default":0, "readonly":true},
	{"id":"custom", "name":"CustomData", "type":"vec4", "default":[0.0,0.0,0.0,0.0]}
]

static func create() -> Dictionary:
	return {"type":"mm_particle_effect", "version":1, "target":"4.7.2", "attributes":[], "modules":{}, "stages":{"spawn":[], "update":[]}, "emitter":{"rate":64.0,"duration":1.0,"loop":true,"bursts":[],"lifetime":1.0}, "renderer":{"mode":"additive","billboard":true,"quad_size":0.1,"custom_attribute":"custom"}}

static func shape_error(data: Dictionary) -> String:
	if data.get("type") != "mm_particle_effect" or (data.get("version") != 1 and data.get("version") != 2) or data.get("target") != "4.7.2": return "Unsupported document format or target"
	for key in ["modules","stages","emitter","renderer"]:
		if not data.get(key) is Dictionary: return "Expected object: " + key
	if not data.get("attributes") is Array: return "Expected Attribute array"
	for field in data.attributes:
		if not field is Dictionary or not identifier(field.get("id")) or not field.get("name") is String or not field.get("type") is String: return "Malformed Attribute"
	for id in data.modules:
		var module = data.modules[id]
		if not identifier(id) or not module is Dictionary or not module.get("name") is String: return "Malformed module"
		for key in ["stages","inputs","reads","writes"]:
			if not module.get(key) is Array: return "Malformed module " + key
		if not (module.get("graph") is Dictionary or module.get("mm_graph") is Dictionary): return "Missing module graph"
		for input in module.inputs:
			if not input is Dictionary or not identifier(input.get("id")) or not input.get("type") is String or not input.has("default"): return "Malformed module input"
	for stage in ["spawn","update"]:
		if not data.stages.get(stage) is Array: return "Missing Stage"
		for instance in data.stages[stage]:
			if not instance is Dictionary or not identifier(instance.get("id")) or not instance.get("module") is String or not instance.get("parameters",{}) is Dictionary: return "Malformed module instance"
			var bindings = instance.get("input_bindings",{})
			if not bindings is Dictionary: return "Expected input_bindings object"
			if data.version == 1 and not bindings.is_empty(): return "User bindings require document version 2"
			for id in bindings:
				var binding = bindings[id]
				if not identifier(id) or not binding is Dictionary or binding.get("kind") != "user" or not identifier(binding.get("id")): return "Malformed User input binding"
	if not data.get("user_parameters",[]) is Array: return "Expected User parameters array"
	if data.version == 1 and not data.get("user_parameters",[]).is_empty(): return "User parameters require document version 2"
	for parameter in data.get("user_parameters",[]):
		if not parameter is Dictionary or not identifier(parameter.get("id")) or not parameter.get("name") is String or not parameter.get("type") is String or not parameter.has("default"): return "Malformed User parameter"
	# Semantic User errors (including Missing references) are compiler diagnostics,
	# not load errors: the editor must be able to show and repair those documents.
	return ""

static func uid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func load_file(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

static func save_file(path: String, data: Dictionary) -> Error:
	# Write beside the destination first; a failed write must not truncate it.
	var temporary := path + "." + uid() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(temporary, path)

static func components(type: String, value) -> Array:
	if type == "bool": return [value]
	if TYPES.get(type, 0) == 1: return [value]
	return value if value is Array else []

static func valid_value(type: String, value) -> bool:
	if not TYPES.has(type): return false
	var items := components(type, value)
	if items.size() != TYPES[type]: return false
	for item in items:
		if type == "bool":
			if not item is bool: return false
		else:
			if not (item is int or item is float) or not is_finite(float(item)): return false
			if type not in ["int", "uint"] and absf(float(item)) > 3.4028234e38: return false
			if type == "uint" and (float(item) < 0 or float(item) > 4294967295.0 or float(item) != floor(float(item))): return false
			if type == "int" and (float(item) < -2147483648.0 or float(item) > 2147483647.0 or float(item) != floor(float(item))): return false
	return true

static func identifier(value) -> bool:
	if not (value is String or value is StringName) or str(value).is_empty(): return false
	for character in str(value):
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true
