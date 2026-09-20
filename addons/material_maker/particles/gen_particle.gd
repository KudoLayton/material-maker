@tool
extends MMGenBase
class_name MMGenParticle

const Interface = preload("interface.gd")
const EditorProfile = preload("editor_profile.gd")
const FUNCTION_TYPES = ["f", "rgb", "rgba", "sdf2d", "sdf3d", "sdf3dc", "tex3d_gs", "tex3d", "v4v4"]
var settings: Dictionary = {"kind": "constant", "data_type": "float"}
var loading_parameters := false
var operations_by_type: Dictionary = {}
var defaults_by_type: Dictionary = {}

static func value_type(type: String) -> String:
	if type in ["float", "vec3", "vec4"]: return {"float": "f", "vec3": "rgb", "vec4": "rgba"}[type]
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
	for alias in mm_io_types.TYPE_ALIASES:
		var type: String = mm_io_types.TYPE_ALIASES[alias]
		mm_io_types.types[alias] = mm_io_types.types[type].duplicate(true)
		mm_io_types.types[alias].name = alias
		mm_io_types.types[alias]["particle_type"] = mm_io_types.types[type].type

func get_type() -> String:
	return "particle_node"

func get_type_name() -> String:
	var n := model_data()
	match n.kind:
		"input": return "Read " + n.get("builtin", "VELOCITY")
		"set": return "Write " + n.get("builtin", "VELOCITY")
		"output": return "Process Output" if n.get("stage") == "process" else "Start Output"
		"entry": return "Process Entry" if n.get("stage") == "process" else "Start Entry"
		"operator": return "Compare" if settings.get("editor_profile") == "compare_v1" else "Typed Math"
	return {"constant": "Typed Constant", "compose": "Typed Combine", "split": "Typed Decompose",
		"convert": "Type Cast", "transform": "Matrix Transform", "select": "Select",
		"uniform": "Typed Parameter", "array_get": "Array Element", "sample": "Texture Sample",
		"evaluate": "Evaluate Function", "bridge": "Value to Function", "random": "Particle Random",
		"emit": "Emit Subparticle"}.get(n.kind, str(n.kind).capitalize())

func can_be_deleted() -> bool:
	return settings.kind != "output"

func accept_float_expressions() -> bool:
	return false

func get_description() -> String:
	if settings.kind == "output":
		return "Particle stage output. Sampling UV defaults to (0, 0) and is evaluated once at stage entry. Evaluate Function can override coordinates for a branch."
	if settings.kind == "random":
		return "Deterministic per-particle random values. Particle ID defaults to Godot NUMBER; System Seed defaults to Godot RANDOM_SEED. Seed Offset is an additional node-specific offset, not a Godot built-in. Input default controls apply only while the corresponding input is unconnected. Random Value is the only output."
	var descriptions := {
		"input": "Read a Godot particle shader built-in value.",
		"set": "Write a Godot particle shader built-in value in execution order.",
		"entry": "Begin the execution chain for this particle stage.",
		"emit": "Emit a subparticle in execution order. Success is available after emission.",
		"constant": "A literal of an additional shader type. Use Grayscale Uniform, Uniform or Vec3 Math for ordinary numeric values. Existing saved constants remain supported.",
		"operator": "Math for additional shader types. Use Math and Vec3 Math for ordinary float and Color calculations.",
		"compose": "Combine components or matrix columns of an additional type. Use Combine for Color and RGBA.",
		"split": "Decompose components or matrix columns of an additional type. Use Decompose for Color and RGBA.",
		"convert": "Explicit shader type constructor. Unlike Material Maker color conversion, casting a vector to float selects its first component instead of averaging RGB.",
		"transform": "Multiply a mat4 matrix by a vec4 vector. This does not remap image UV coordinates.",
		"select": "Choose a value using a runtime bool condition. The existing Switch chooses a graph input through an editor setting.",
		"uniform": "An externally editable parameter with a named, typed output. Use Remote for internal graph controls and Typed Constant for fixed values. Supports arrays and Godot hints. Currently supported by particle shader export only.",
		"array_get": "Read an element of a shader array by index.",
		"sample": "Sample a shader texture resource with explicit coordinates and LOD. Use Image for ordinary 2D images. Currently supported by particle shader export only.",
		"evaluate": "Evaluate a function at explicit coordinates. Ordinary numeric connections need no adapter. Currently supported by particle shader export only.",
		"bridge": "Provide a value as an SDF or 3D function. Grayscale, Color and RGBA values connect directly without this adapter. Existing saved adapters remain supported."
	}
	if settings.get("editor_profile") == "compare_v1":
		return "Compare scalar numbers or test whole-vector equality, returning bool for runtime conditions."
	return descriptions.get(settings.kind, "Supplemental node for particle shader authoring.")

func option_values(key: String, type: String = "") -> Array:
	var values: Array = Interface.TYPES
	match key:
		"operation": values = Interface.OPERATIONS
		"function_type": values = FUNCTION_TYPES
		"sampler_type": values = Interface.TYPES.filter(func(t): return t.begins_with("sampler"))
		"data_type":
			if settings.kind == "random": values = Interface.RANDOM_TYPES
	return EditorProfile.options(settings.get("editor_profile", ""), settings.kind, key, type, values)

func model_data() -> Dictionary:
	var n := settings.duplicate(true)
	n["id"] = "g" + str(get_instance_id())
	n["inputs"] = settings.get("inputs", {}).duplicate(true)
	for key in ["data_type", "source_type", "operation", "function_type", "sampler_type"]:
		if parameters.has(key):
			var values := option_values(key, n.get("data_type", "float"))
			n[key] = values[clampi(int(parameters[key]), 0, values.size() - 1)]
	if n.kind in ["evaluate", "bridge"]:
		n["function_type"] = n.get("function_type", "rgba")
		n["data_type"] = mm_io_types.types[n.function_type].type
	if n.kind == "array_get": n["array_size"] = int(parameters.get("array_size", n.get("array_size", 1)))
	if n.kind == "sample": n["sampler_type"] = n.get("sampler_type", "sampler2D")
	if n.kind == "random":
		for key in ["seed", "minimum", "maximum"]:
			n[key] = parameters.get(key, n.get(key, 1.0 if key == "maximum" else 0.0))
	if n.kind == "constant":
		var type: String = n.get("data_type", "float")
		var value = n.get("value", Interface.default_value(type))
		if value is Array:
			for i in value.size():
				if value[i] is Array:
					for j in value[i].size(): value[i][j] = constant_component("v%d_%d" % [i, j], value[i][j], type)
				else: value[i] = constant_component("v%d" % i, value[i], type)
		else: value = constant_component("value", n.get("value", value), type)
		n["value"] = value
	if n.kind == "uniform":
		n["uniform"] = parameters.get("uniform_name", n.get("uniform", "parameter"))
		n["array_size"] = int(parameters.get("array_size", 0))
	return n

func constant_component(key: String, fallback, type: String):
	var value = parameters.get(key, fallback)
	var scalar := Interface.scalar_type(type)
	if type == "bool" or scalar == "bool": return bool(value)
	if type in ["int", "uint"] or scalar in ["int", "uint"]: return int(value)
	return float(value)

func uniform_definition() -> Dictionary:
	var n := model_data()
	var type: String = n.get("data_type", "float")
	var json := JSON.new()
	json.parse(str(parameters.get("default_json", JSON.stringify(default_parameter_value(n)))))
	var value = json.data
	return {"name": n.uniform, "type": type, "array_size": int(parameters.get("array_size", 0)),
		"value": value, "hint": parameters.get("hint", ""), "resource": parameters.get("resource", ""),
		"resources": JSON.parse_string(str(parameters.get("resources", "[]")))}

static func output_ports(stage: String) -> Dictionary:
	var ports := Interface.ports({"kind": "output"}, stage)
	ports.inputs.append({"name": "sampling_uv", "type": "vec2"})
	return ports

func particle_ports() -> Dictionary:
	var n := model_data()
	if n.kind == "output": return output_ports(n.get("stage", "process"))
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
		var label: String = {"sampling_uv": "Sampling UV", "exec": "Execution", "lod": "LOD"}.get(p.name, str(p.name).capitalize())
		if p.name == str(p.name).to_upper(): label = p.name
		if str(p.name).begins_with("c") and str(p.name).substr(1).is_valid_int():
			var index := int(str(p.name).substr(1))
			label = "Column %d" % (index + 1) if str(model_data().data_type).begins_with("mat") else ["X", "Y", "Z", "W"][index]
		if settings.kind == "random":
			label = {"particle_id": "Particle ID (NUMBER)", "system_seed": "System Seed (RANDOM_SEED)", "seed": "Seed Offset", "minimum": "Minimum", "maximum": "Maximum", "value": "Random Value"}.get(p.name, p.name)
		result.append({"name": p.name, "label": label, "type": p.type if p.type in FUNCTION_TYPES else value_type(p.type), "shader_type": "" if p.type in FUNCTION_TYPES else p.type})
	return result

func get_input_defs() -> Array:
	return port_defs("inputs")

func get_output_defs(_show_hidden: bool = false) -> Array:
	return port_defs("outputs")

static func enum_parameter(key: String, values: Array, selected: String) -> Dictionary:
	var options: Array = []
	for value in values:
		var label: String = value
		if key == "function_type": label = mm_io_types.types[value].label
		elif key in ["data_type", "source_type"] and value in ["float", "vec3", "vec4"]:
			label = mm_io_types.types[value_type(value)].label + " (" + value + ")"
		elif key == "operation": label = {"add": "A+B", "subtract": "A-B", "multiply": "A*B", "divide": "A/B", "equal": "A == B", "less": "A < B", "greater": "A > B"}.get(value, str(value).capitalize())
		options.append({"name": label, "value": value})
	return {"name": key, "label": {"data_type": "Type", "source_type": "From Type"}.get(key, key.capitalize()), "type": "enum", "values": options, "default": maxi(0, values.find(selected))}

static func number_parameter(key: String, value, integer: bool = false) -> Dictionary:
	var label := key.capitalize()
	if key.begins_with("v") and key.substr(1).get_slice("_", 0).is_valid_int():
		var indices := key.substr(1).split("_")
		label = "C%d / R%d" % [int(indices[0]) + 1, int(indices[1]) + 1] if indices.size() == 2 else ["X", "Y", "Z", "W"][int(indices[0])]
	return {"name": key, "label": label, "type": "boolean" if value is bool else "float", "default": value,
		"min": -4294967295.0, "max": 4294967295.0, "step": 1.0 if integer else 0.01}

func get_parameter_defs() -> Array:
	var result: Array = []
	var n := model_data()
	if n.kind == "random":
		var output_type := enum_parameter("data_type", Interface.RANDOM_TYPES, settings.get("data_type", "vec3"))
		output_type.label = "6:Output Type"
		result.append(output_type)
		for key in ["seed", "minimum", "maximum"]:
			var parameter := number_parameter(key, n[key], key == "seed")
			parameter.label = "%d:Input default" % {"seed": 3, "minimum": 4, "maximum": 5}[key]
			parameter.shortdesc = {"seed": "Seed Offset", "minimum": "Minimum", "maximum": "Maximum"}[key]
			parameter.longdesc = "Used only when this input is unconnected. A connected input overrides this setting."
			if key == "seed":
				parameter.min = 0.0
				parameter.longdesc += " Additional node-specific offset; this is not Godot's RANDOM_SEED."
			result.append(parameter)
	if n.kind in ["constant", "operator", "convert", "compose", "split", "select", "uniform", "array_get"] or (n.kind == "sample" and not settings.has("editor_profile")):
		result.append(enum_parameter("data_type", option_values("data_type"), settings.get("data_type", "float")))
	if n.kind == "sample": result.append(enum_parameter("sampler_type", Interface.TYPES.filter(func(t): return t.begins_with("sampler")), settings.get("sampler_type", "sampler2D")))
	if n.kind == "convert":
		result[0].label = "To Type"
		result.append(enum_parameter("source_type", option_values("source_type"), settings.get("source_type", "float")))
	if n.kind == "operator": result.append(enum_parameter("operation", option_values("operation", n.data_type), settings.get("operation", "add")))
	if n.kind in ["evaluate", "bridge"]: result.append(enum_parameter("function_type", option_values("function_type"), settings.get("function_type", "rgba")))
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
		result.append({"name": "uniform_name", "label": "Name", "type": "string", "default": settings.get("uniform", "parameter")})
		result.append(number_parameter("array_size", 0, true))
		result[-1].min = 0
		result[-1].max = 1024
		if n.data_type.begins_with("sampler"):
			var key := "resources" if n.get("array_size", 0) > 0 else "resource"
			result.append({"name": key, "label": "Paths (JSON)" if key == "resources" else "Resource", "type": "string", "default": "[]" if key == "resources" else ""})
		elif n.get("array_size", 0) > 0:
			result.append({"name": "default_json", "label": "Default (JSON)", "type": "string", "default": JSON.stringify(default_parameter_value(n))})
		else:
			var value = parameter_editor_value()
			var integer: bool = n.data_type in ["int", "uint"] or Interface.scalar_type(n.data_type) in ["int", "uint"]
			if value is Array:
				for i in value.size():
					if value[i] is Array:
						for j in value[i].size(): result.append(number_parameter("v%d_%d" % [i, j], value[i][j]))
					else: result.append(number_parameter("v%d" % i, value[i], integer))
			else: result.append(number_parameter("value", value, integer))
		result.append({"name": "hint", "label": "Hint", "type": "string", "default": ""})
	return result

static func default_parameter_value(n: Dictionary):
	var value = Interface.default_value(n.data_type)
	if n.get("array_size", 0) > 0:
		var values: Array = []
		for i in clampi(n.array_size, 0, 1024): values.append(value.duplicate(true) if value is Array else value)
		return values
	return value

func parameter_editor_value():
	var n := model_data()
	var value = uniform_definition().value
	var validator = preload("compiler.gd").new()
	validator.literal(n.data_type, value, "")
	return value if validator.errors.is_empty() else Interface.default_value(n.data_type)

func is_parameter_component(key: String) -> bool:
	return settings.kind == "uniform" and (key == "value" or RegEx.create_from_string("^v[0-3](_[0-3])?$").search(key) != null)

func get_parameter(key: String):
	if is_parameter_component(key):
		return get_parameter_def(key).get("default")
	return super.get_parameter(key)

func set_parameter(key: String, value) -> void:
	if is_parameter_component(key):
		var edited = parameter_editor_value()
		var type: String = model_data().data_type
		var scalar: String = type if type in ["bool", "int", "uint", "float"] else Interface.scalar_type(type)
		value = bool(value) if scalar == "bool" else (int(value) if scalar in ["int", "uint"] else float(value))
		if key == "value": edited = value
		else:
			var indices := key.substr(1).split("_")
			if indices.size() == 2: edited[int(indices[0])][int(indices[1])] = value
			else: edited[int(indices[0])] = value
		super.set_parameter("default_json", JSON.stringify(edited))
		parameter_changed.emit(key, value)
		if is_inside_tree(): all_sources_changed.call_deferred()
		return
	var change_default: bool = not loading_parameters and settings.kind == "uniform" and key in ["data_type", "array_size"]
	if change_default:
		var n := model_data()
		defaults_by_type[n.data_type + ":" + str(n.get("array_size", 0))] = parameters.get("default_json", JSON.stringify(default_parameter_value(n)))
	var remap_operation: bool = not loading_parameters and key == "data_type" and settings.kind == "operator" and settings.has("editor_profile")
	var previous_operation: String = model_data().get("operation", "add") if remap_operation else ""
	if remap_operation: operations_by_type[model_data().data_type] = previous_operation
	super.set_parameter(key, value)
	if change_default:
		var n := model_data()
		super.set_parameter("default_json", defaults_by_type.get(n.data_type + ":" + str(n.get("array_size", 0)), JSON.stringify(default_parameter_value(n))))
	if remap_operation:
		var options := option_values("operation", model_data().data_type)
		super.set_parameter("operation", maxi(0, options.find(operations_by_type.get(model_data().data_type, previous_operation))))
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
	if settings.kind == "uniform":
		for key in data.parameters.keys():
			if is_parameter_component(key): data.parameters.erase(key)
		for key in ["default_json", "hint", "resource", "resources"]:
			if parameters.has(key): data.parameters[key] = parameters[key]
		if not data.parameters.has("default_json"):
			data.parameters.default_json = JSON.stringify(default_parameter_value(model_data()))
	data.type = get_type()
	data.settings = settings.duplicate(true)
	return data

func _deserialize(data: Dictionary) -> void:
	settings = data.get("settings", settings).duplicate(true)

func deserialize(data: Dictionary) -> void:
	loading_parameters = true
	operations_by_type.clear()
	defaults_by_type.clear()
	await super.deserialize(data)
	loading_parameters = false
