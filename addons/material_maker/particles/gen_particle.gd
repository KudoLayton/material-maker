@tool
extends MMGenBase
class_name MMGenParticle

const Interface = preload("interface.gd")
const FUNCTION_TYPES = ["f", "rgb", "rgba", "sdf2d", "sdf3d", "sdf3dc", "tex3d_gs", "tex3d", "v4v4"]
var settings: Dictionary = {"kind": "constant", "data_type": "float"}

static func value_type(type: String) -> String:
	var key := "particle_" + type.replace("[", "_array_").replace("]", "")
	if not mm_io_types.types.has(key):
		mm_io_types.types[key] = {"name": key, "label": type, "type": type, "particle_type": type,
			"paramdefs": "vec2 uv", "params": "uv", "slot_type": 100 + mm_io_types.types.size(),
			"color": port_color(type)}
		mm_io_types.type_names.append(key)
	return key

static func port_color(type: String) -> Color:
	var element := type.get_slice("[", 0)
	match element:
		"float": return mm_io_types.types.f.color
		"vec3": return mm_io_types.types.rgb.color
		"vec4": return mm_io_types.types.rgba.color
		"exec": return mm_io_types.types.any.color
		"vec2": return Color("43bfa9")
	if element == "bool" or element.begins_with("bvec"): return Color("d9c65d")
	if element in ["int", "uint"] or element.begins_with("ivec") or element.begins_with("uvec"): return Color("c98b60")
	if element.begins_with("mat"): return Color("9a83d6")
	if element.begins_with("sampler"): return Color("c879b5")
	return mm_io_types.types.any.color

static func register_types() -> void:
	for type in Interface.TYPES + ["exec"]:
		value_type(type)

func get_type() -> String:
	return "particle_node"

func get_type_name() -> String:
	var n := model_data()
	match n.kind:
		"input": return "Read " + n.get("builtin", "VELOCITY")
		"set": return "Write " + n.get("builtin", "VELOCITY")
		"output": return "Process Output" if n.get("stage") == "process" else "Start Output"
		"evaluate": return "Evaluate " + n.function_type
		"bridge": return "Value to " + n.function_type
	return "Particle " + str(n.kind).capitalize()

func can_be_deleted() -> bool:
	return settings.kind != "output"

func accept_float_expressions() -> bool:
	return false

func get_description() -> String:
	return "Godot particle shader. State-dependent outputs have no image preview."

func model_data() -> Dictionary:
	var n := settings.duplicate(true)
	n["id"] = "g" + str(get_instance_id())
	n["inputs"] = settings.get("inputs", {}).duplicate(true)
	for key in ["data_type", "source_type", "operation", "function_type", "sampler_type"]:
		if parameters.has(key):
			var values: Array = Interface.OPERATIONS if key == "operation" else (FUNCTION_TYPES if key == "function_type" else (Interface.TYPES.filter(func(t): return t.begins_with("sampler")) if key == "sampler_type" else Interface.TYPES))
			n[key] = values[clampi(int(parameters[key]), 0, values.size() - 1)]
	if n.kind in ["evaluate", "bridge"]:
		n["function_type"] = n.get("function_type", "rgba")
		n["data_type"] = mm_io_types.types[n.function_type].type
	if n.kind == "array_get": n["array_size"] = int(parameters.get("array_size", n.get("array_size", 1)))
	if n.kind == "sample": n["sampler_type"] = n.get("sampler_type", "sampler2D")
	if n.kind == "constant":
		var type: String = n.get("data_type", "float")
		var value = n.get("value", Interface.default_value(type))
		if value is Array:
			for i in value.size():
				if value[i] is Array:
					for j in value[i].size(): value[i][j] = parameters.get("v%d_%d" % [i, j], value[i][j])
				else: value[i] = parameters.get("v%d" % i, value[i])
		else: value = parameters.get("value", n.get("value", value))
		n["value"] = value
	if n.kind == "uniform":
		n["uniform"] = parameters.get("uniform_name", n.get("uniform", "parameter"))
	return n

func uniform_definition() -> Dictionary:
	var n := model_data()
	var type: String = n.get("data_type", "float")
	var value = JSON.parse_string(str(parameters.get("default_json", JSON.stringify(Interface.default_value(type)))))
	return {"name": n.uniform, "type": type, "array_size": int(parameters.get("array_size", 0)),
		"value": value, "hint": parameters.get("hint", ""), "resource": parameters.get("resource", ""),
		"resources": JSON.parse_string(str(parameters.get("resources", "[]")))}

func particle_ports() -> Dictionary:
	var n := model_data()
	if n.kind == "evaluate":
		var coordinate_type: String = "vec2" if n.function_type in ["f", "rgb", "rgba", "sdf2d"] else ("vec3" if n.function_type in ["sdf3d", "sdf3dc"] else "vec4")
		return {"inputs": [{"name": "function", "type": n.function_type}, {"name": "coordinates", "type": coordinate_type}], "outputs": [{"name": "value", "type": n.data_type}]}
	if n.kind == "bridge":
		return {"inputs": [{"name": "value", "type": n.data_type}], "outputs": [{"name": "value", "type": n.function_type}]}
	var stage: String = n.get("stage", "process")
	if n.kind == "input" and not Interface.BUILTINS[stage].has(n.get("builtin", "")): stage = "start"
	return Interface.ports(n, stage, [uniform_definition()] if n.kind == "uniform" else [])

func port_defs(side: String) -> Array:
	var result: Array = []
	for p in particle_ports()[side]:
		result.append({"name": p.name, "label": p.name, "type": p.type if p.type in FUNCTION_TYPES else value_type(p.type)})
	return result

func get_input_defs() -> Array:
	return port_defs("inputs")

func get_output_defs(_show_hidden: bool = false) -> Array:
	return port_defs("outputs")

static func enum_parameter(key: String, values: Array, selected: String) -> Dictionary:
	var options: Array = []
	for value in values: options.append({"name": value, "value": value})
	return {"name": key, "label": key.capitalize(), "type": "enum", "values": options, "default": maxi(0, values.find(selected))}

static func number_parameter(key: String, value, integer: bool = false) -> Dictionary:
	return {"name": key, "label": key, "type": "boolean" if value is bool else "float", "default": value,
		"min": -4294967295.0, "max": 4294967295.0, "step": 1.0 if integer else 0.01}

func get_parameter_defs() -> Array:
	var result: Array = []
	var n := model_data()
	if n.kind in ["constant", "operator", "convert", "compose", "split", "select", "uniform", "array_get", "sample"]:
		result.append(enum_parameter("data_type", Interface.TYPES, settings.get("data_type", "float")))
	if n.kind == "sample": result.append(enum_parameter("sampler_type", Interface.TYPES.filter(func(t): return t.begins_with("sampler")), settings.get("sampler_type", "sampler2D")))
	if n.kind == "convert": result.append(enum_parameter("source_type", Interface.TYPES, settings.get("source_type", "float")))
	if n.kind == "operator": result.append(enum_parameter("operation", Interface.OPERATIONS, settings.get("operation", "add")))
	if n.kind in ["evaluate", "bridge"]: result.append(enum_parameter("function_type", FUNCTION_TYPES, settings.get("function_type", "rgba")))
	if n.kind == "constant":
		var value = n.value
		var integer: bool = n.get("data_type", "float") in ["int", "uint"] or Interface.scalar_type(n.get("data_type", "float")) in ["int", "uint"]
		if value is Array:
			for i in value.size():
				if value[i] is Array:
					for j in value[i].size(): result.append(number_parameter("v%d_%d" % [i, j], value[i][j], integer))
				else: result.append(number_parameter("v%d" % i, value[i], integer))
		else: result.append(number_parameter("value", value, integer))
	if n.kind == "array_get": result.append(number_parameter("array_size", settings.get("array_size", 1), true))
	if n.kind == "uniform":
		for pair in [["uniform_name", settings.get("uniform", "parameter")], ["default_json", JSON.stringify(Interface.default_value(n.get("data_type", "float")))], ["hint", ""], ["resource", ""], ["resources", "[]"]]:
			result.append({"name": pair[0], "label": pair[0], "type": "string", "default": pair[1]})
		result.append(number_parameter("array_size", 0, true))
	return result

func set_parameter(key: String, value) -> void:
	super.set_parameter(key, value)
	if is_inside_tree(): all_sources_changed.call_deferred()
	if key in ["data_type", "source_type", "function_type", "operation", "array_size", "uniform_name", "sampler_type"]:
		parameter_changed.emit.call_deferred("__update_all__", null)

func _get_shader_code(uv: String, output_index: int, context: MMGenContext) -> ShaderCode:
	if context.particle_compiler != null:
		return context.particle_compiler.generate_value(self, output_index, uv, context)
	if preload("dependencies.gd").runtime_source(self).is_empty():
		return load("res://addons/material_maker/particles/graph_compiler.gd").new().static_value(self, output_index, uv)
	var result := ShaderCode.new()
	result.error = get_hier_name() + ": particle values require a particle evaluation context"
	return result

func _serialize(data: Dictionary) -> Dictionary:
	data.type = get_type()
	data.settings = settings.duplicate(true)
	return data

func _deserialize(data: Dictionary) -> void:
	settings = data.get("settings", settings).duplicate(true)
