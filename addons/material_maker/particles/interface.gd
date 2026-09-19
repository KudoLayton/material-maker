extends RefCounted

const BUILTINS = preload("abi.gd").BUILTINS
const MODES = ["collision_use_scale", "disable_force", "disable_velocity", "keep_data"]
const TYPES = ["bool", "int", "uint", "float", "bvec2", "bvec3", "bvec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "sampler2D", "sampler2DArray", "sampler3D", "samplerCube", "samplerCubeArray"]
const RANDOM_TYPES = ["float", "vec2", "vec3", "vec4"]
const OPERATIONS = ["add", "subtract", "multiply", "divide", "mod", "min", "max", "clamp", "mix", "dot", "cross", "length", "normalize", "abs", "floor", "ceil", "fract", "sin", "cos", "sqrt", "pow", "equal", "less", "greater", "and", "or", "not", "bit_and", "bit_or", "bit_xor", "bit_not", "shift_left", "shift_right", "transpose", "inverse", "determinant"]

static func port(name: String, type: String) -> Dictionary:
	return {"name": name, "type": type}

static func ports(n: Dictionary, stage: String, uniforms: Array = []) -> Dictionary:
	var inputs: Array = []
	var outputs: Array = []
	var type: String = n.get("data_type", "float")
	match n.get("kind", ""):
		"entry":
			outputs = [port("next", "exec")]
		"output":
			inputs = [port("exec", "exec")]
			for key in BUILTINS.get(stage, {}):
				if BUILTINS[stage][key].write:
					inputs.append(port(key, BUILTINS[stage][key].type))
		"input":
			var item: Dictionary = BUILTINS.get(stage, {}).get(n.get("builtin", ""), {})
			if not item.is_empty():
				outputs = [port("value", item.type)]
		"random":
			inputs = [port("particle_id", "uint"), port("system_seed", "uint"), port("seed", "uint"), port("minimum", type), port("maximum", type)]
			outputs = [port("value", type)]
		"constant":
			outputs = [port("value", type)]
		"uniform":
			for u in uniforms:
				if u.name == n.get("uniform", ""):
					outputs = [port("value", u.type + ("[%d]" % int(u.get("array_size", 0)) if int(u.get("array_size", 0)) > 0 else ""))]
		"set":
			inputs = [port("exec", "exec"), port("enabled", "bool")]
			var item: Dictionary = BUILTINS.get(stage, {}).get(n.get("builtin", ""), {})
			if item.get("write", false):
				inputs.append(port("value", item.type))
			outputs = [port("next", "exec")]
		"emit":
			inputs = [port("exec", "exec"), port("enabled", "bool"), port("transform", "mat4"), port("velocity", "vec3"), port("color", "vec4"), port("custom", "vec4"), port("flags", "uint")]
			outputs = [port("next", "exec"), port("success", "bool")]
		"operator":
			var operation: String = n.get("operation", "add")
			inputs = [port("a", type)]
			if operation not in ["length", "normalize", "abs", "floor", "ceil", "fract", "sin", "cos", "sqrt", "not", "bit_not", "transpose", "inverse", "determinant"]:
				inputs.append(port("b", type))
			if operation in ["clamp", "mix"]:
				inputs.append(port("c", "float" if operation == "mix" else type))
			outputs = [port("value", "bool" if operation in ["equal", "less", "greater"] else ("float" if operation in ["length", "dot", "determinant"] else type))]
		"convert":
			inputs = [port("value", n.get("source_type", "float"))]
			outputs = [port("value", type)]
		"compose":
			var count: int = int(type.right(1))
			var element: String = ("vec" + str(count)) if type.begins_with("mat") else scalar_type(type)
			for index in count:
				inputs.append(port("c%d" % index, element))
			outputs = [port("value", type)]
		"split":
			inputs = [port("value", type)]
			var count: int = int(type.right(1))
			var element: String = ("vec" + str(count)) if type.begins_with("mat") else scalar_type(type)
			for index in count:
				outputs.append(port("c%d" % index, element))
		"transform":
			inputs = [port("matrix", "mat4"), port("vector", "vec4")]
			outputs = [port("value", "vec4")]
		"select":
			inputs = [port("condition", "bool"), port("true", type), port("false", type)]
			outputs = [port("value", type)]
		"sample":
			var sampler: String = n.get("sampler_type", "sampler2D")
			inputs = [port("texture", sampler), port("coordinates", "vec2" if sampler == "sampler2D" else ("vec4" if sampler == "samplerCubeArray" else "vec3")), port("lod", "float")]
			outputs = [port("value", "vec4")]
		"array_get":
			inputs = [port("array", type + "[%d]" % int(n.get("array_size", 1))), port("index", "int")]
			outputs = [port("value", type)]
		"custom":
			inputs = n.get("input_ports", [])
			outputs = [port("value", type)]
	return {"inputs": inputs, "outputs": outputs}

static func scalar_type(type: String) -> String:
	if type.begins_with("bvec"):
		return "bool"
	if type.begins_with("ivec"):
		return "int"
	if type.begins_with("uvec"):
		return "uint"
	return "float"

static func default_value(type: String):
	if type == "bool":
		return false
	if type in ["int", "uint", "float"]:
		return 0
	var count := int(type.right(1))
	var values: Array = []
	for index in count:
		if type.begins_with("mat"):
			var column: Array = []
			for row in count:
				column.append(1 if row == index else 0)
			values.append(column)
		else:
			values.append(false if type.begins_with("bvec") else 0)
	return values
