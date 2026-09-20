extends RefCounted

const EXTRA_TYPES = ["bool", "int", "uint", "bvec2", "bvec3", "bvec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4", "vec2", "mat2", "mat3", "mat4"]
const MATH_TYPES = ["bool", "int", "uint", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4", "vec2", "vec4", "mat2", "mat3", "mat4"]
const COMPARE_TYPES = ["float", "int", "uint", "bool", "vec2", "vec3", "vec4", "bvec2", "bvec3", "bvec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"]

static func options(profile: String, kind: String, key: String, type: String, legacy: Array) -> Array:
	if profile == "compare_v1":
		if key == "data_type": return COMPARE_TYPES
		if key == "operation": return ["equal", "less", "greater"] if type in ["float", "int", "uint"] else ["equal"]
	if profile != "supplemental_v1": return legacy
	if key == "function_type" and kind == "bridge": return legacy.filter(func(t): return t not in ["f", "rgb", "rgba"])
	if key == "operation": return operations(type)
	if key == "data_type":
		match kind:
			"constant": return EXTRA_TYPES
			"operator": return MATH_TYPES
			"compose", "split": return EXTRA_TYPES.filter(func(t): return "vec" in t or t.begins_with("mat"))
	if key in ["data_type", "source_type"] and kind in ["convert", "select"]:
		return legacy.filter(func(t): return not t.begins_with("sampler"))
	return legacy

static func operations(type: String) -> Array:
	if type == "bool": return ["and", "or", "not"]
	if type.begins_with("mat"): return ["add", "subtract", "multiply", "transpose", "inverse", "determinant"]
	if type in ["int", "uint"] or type.begins_with("ivec") or type.begins_with("uvec"):
		var result: Array = ["add", "subtract", "multiply", "divide", "min", "max", "clamp", "bit_and", "bit_or", "bit_xor", "bit_not", "shift_left", "shift_right"]
		if type == "int" or type.begins_with("ivec"): result.append("abs")
		return result
	return ["add", "subtract", "multiply", "divide", "mod", "min", "max", "clamp", "mix", "dot", "length", "normalize", "abs", "floor", "ceil", "fract", "sin", "cos", "sqrt", "pow"]
