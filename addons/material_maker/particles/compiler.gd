extends RefCounted

const Interface = preload("interface.gd")
const Document = preload("document.gd")
var errors: Array = []
var document: Dictionary
var stage := ""
var nodes: Dictionary = {}
var cache: Dictionary = {}
var visiting: Dictionary = {}
var emitted: Dictionary = {}
var body: Array = []
var functions: Dictionary = {}
var serial := 0

func fail(node: String, message: String) -> void:
	errors.append({"stage": stage, "node": node, "message": message})

func compile(data: Dictionary) -> Dictionary:
	errors = []
	document = data
	functions = {}
	serial = 0
	stage = ""
	if not Document.valid(data):
		fail("", "Unsupported particle document or version")
		return {"code": "", "errors": errors, "source_map": {}}
	var declarations: Array = []
	var uniform_names: Dictionary = {}
	for uniform in data.get("uniforms", []):
		var owner: String = uniform.get("source_node", "")
		var name: String = uniform.get("name", "")
		var type: String = uniform.get("type", "")
		if not identifier(name) or name in Interface.BUILTINS.start or name in Interface.BUILTINS.process or name in uniform_names:
			fail(owner, "Invalid, reserved or duplicate uniform: " + name)
			continue
		uniform_names[name] = true
		if type not in Interface.TYPES:
			fail(owner, "Unknown uniform type: " + type)
			continue
		var count := int(uniform.get("array_size", 0))
		if count < 0 or count > 1024:
			fail(owner, "Uniform array size must be 0..1024: " + name)
			continue
		var declaration: String = "uniform " + type + " " + name + ("[%d]" % count if count else "")
		var hint: String = uniform.get("hint", "")
		if ";" in hint or "\n" in hint or "{" in hint or "}" in hint:
			fail(owner, "Invalid uniform hint: " + name)
		elif not hint.is_empty():
			declaration += " : " + hint
		if not type.begins_with("sampler"):
			if count:
				var values = uniform.get("value", [])
				if not values is Array or values.size() != count:
					fail(owner, "Uniform array default size mismatch: " + name)
				else:
					for value in values:
						literal(type, value, owner)
			else:
				declaration += " = " + literal(type, uniform.get("value", Interface.default_value(type)), owner)
		declarations.append({"text": declaration + ";", "node": owner})
	var modes: Array[String] = []
	for mode in data.get("render_modes", []):
		if mode not in Interface.MODES or mode in modes:
			fail("", "Invalid or duplicate render mode: " + str(mode))
		else:
			modes.append(mode)
	var stage_bodies: Dictionary = {}
	for current_stage in ["start", "process"]:
		stage = current_stage
		stage_bodies[stage] = compile_stage(data.get("stages", {}).get(stage, {}))
	var lines: Array[String] = ["shader_type particles;"]
	var source_map: Dictionary = {}
	if not modes.is_empty():
		lines.append("render_mode " + ", ".join(modes) + ";")
	for declaration in declarations:
		lines.append(declaration.text)
		source_map[lines.size()] = {"stage": "", "node": declaration.node}
	for function in functions.values():
		for line in function.lines:
			lines.append(line)
			source_map[lines.size()] = {"stage": function.stage, "node": function.node}
	for current_stage in stage_bodies:
		lines.append("void " + current_stage + "() {")
		for line in stage_bodies[current_stage]:
			lines.append("\t" + line.text)
			source_map[lines.size()] = {"stage": current_stage, "node": line.node}
		lines.append("}")
	return {"code": "\n".join(lines) + "\n", "errors": errors.duplicate(), "source_map": source_map}

func compile_stage(graph: Dictionary) -> Array:
	nodes = {}
	body = []
	emitted = {}
	cache = {}
	visiting = {}
	var entries: Array = []
	var outputs: Array = []
	for n in graph.get("nodes", []):
		var id: String = str(n.get("id", ""))
		if not identifier(id) or nodes.has(id):
			fail(id, "Invalid or duplicate node ID")
			continue
		nodes[id] = n
		if n.get("kind") == "entry":
			entries.append(id)
		if n.get("kind") == "output":
			outputs.append(id)
		validate_node(n)
	if entries.size() != 1 or outputs.size() != 1:
		fail("", "Each stage requires exactly one Entry and Output")
		return body
	for n in nodes.values():
		var ports: Dictionary = get_ports(n)
		for input_name in n.get("inputs", {}):
			var target_type: String = port_type(ports.inputs, input_name)
			if target_type.is_empty():
				fail(n.id, "Unknown or read-only input: " + input_name)
				continue
			var binding = n.inputs[input_name]
			if not binding is Dictionary:
				fail(n.id, "Malformed connection: " + input_name)
				continue
			if binding.has("node"):
				var source: Dictionary = nodes.get(str(binding.node), {})
				var source_type: String = port_type(get_ports(source).outputs, binding.get("port", "value"))
				if not types_compatible(source_type, target_type):
					fail(n.id, "Type mismatch on %s: expected %s, got %s" % [input_name, target_type, source_type])
	var successors := {}
	for n in nodes.values():
		var binding: Dictionary = n.get("inputs", {}).get("exec", {})
		if binding.has("node"):
			if successors.has(binding.node):
				fail(n.id, "Execution cannot fork; use Enabled for conditional execution")
			successors[binding.node] = n.id
	var visited := {}
	var current: String = entries[0]
	while not current.is_empty() and nodes.has(current):
		if visited.has(current):
			fail(current, "Execution cycle")
			break
		visited[current] = true
		cache = {}
		visiting = {}
		var n: Dictionary = nodes[current]
		match n.kind:
			"set":
				var target: String = n.get("builtin", "")
				var type: String = Interface.BUILTINS[stage].get(target, {}).get("type", "float")
				var enabled: String = argument(n, "enabled", "bool", true)
				var value: String = argument(n, "value", type)
				line("if (" + enabled + ") { " + target + " = " + value + "; }", current)
			"emit":
				var arguments: Array[String] = []
				var enabled: String = argument(n, "enabled", "bool", true)
				for p in get_ports(n).inputs:
					if p.name not in ["exec", "enabled"]:
						arguments.append(argument(n, p.name, p.type, [1, 1, 1, 1] if p.name == "color" else null))
				var result: String = "emit_" + current
				line("bool " + result + " = false;", current)
				line("if (" + enabled + ") { " + result + " = emit_subparticle(" + ", ".join(arguments) + "); }", current)
				emitted[current] = result
			"output":
				var assignments: Array[String] = []
				for p in get_ports(n).inputs:
					if p.name == "exec" or not n.get("inputs", {}).has(p.name):
						continue
					var value: String = argument(n, p.name, p.type)
					var temporary: String = "output_" + p.name
					line(p.type + " " + temporary + " = " + value + ";", current)
					assignments.append(p.name + " = " + temporary + ";")
				for assignment in assignments:
					line(assignment, current)
		current = successors.get(current, "")
	if not visited.has(outputs[0]):
		fail(outputs[0], "Output must be reachable from Entry")
	for n in nodes.values():
		if n.kind in ["set", "emit"] and not visited.has(n.id):
			fail(n.id, "Connect this action to the execution chain")
	return body.duplicate()

func validate_node(n: Dictionary) -> void:
	var kind: String = n.get("kind", "")
	if kind not in ["entry", "output", "input", "constant", "uniform", "operator", "convert", "compose", "split", "transform", "select", "sample", "array_get", "custom", "set", "emit", "frame"]:
		fail(n.id, "Unknown node kind: " + kind)
	if kind in ["input", "set"]:
		var info: Dictionary = Interface.BUILTINS[stage].get(n.get("builtin", ""), {})
		if info.is_empty() or (kind == "set" and not info.get("write", false)):
			fail(n.id, "Built-in is not available with this access in " + stage)
	if n.has("data_type") and n.data_type not in Interface.TYPES:
		fail(n.id, "Unknown data type")
	if kind == "operator" and n.get("operation", "add") not in Interface.OPERATIONS:
		fail(n.id, "Unknown operator")
	if kind in ["compose", "split"] and not ("vec" in n.get("data_type", "") or n.get("data_type", "").begins_with("mat")):
		fail(n.id, "Compose/Split requires a vector or matrix")
	if kind == "uniform" and get_ports(n).outputs.is_empty():
		fail(n.id, "Uniform is not declared")
	if kind == "custom":
		var names := {}
		for p in n.get("input_ports", []):
			if not identifier(p.get("name", "")) or p.get("name") in names or p.get("type") not in Interface.TYPES:
				fail(n.id, "Invalid Custom Code input declaration")
			names[p.get("name", "")] = true
		var tokens = RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
		for token in tokens.search_all(n.get("code", "")):
			var word: String = token.get_string()
			if word in Interface.BUILTINS.start or word in Interface.BUILTINS.process or word in ["emit_subparticle", "uniform", "shader_type", "render_mode"]:
				fail(n.id, "Pass state through typed inputs; Custom Code cannot access " + word)

func argument(n: Dictionary, name: String, type: String, default = null) -> String:
	var binding: Dictionary = n.get("inputs", {}).get(name, {})
	if binding.has("node"):
		return expression(str(binding.node), binding.get("port", "value"))
	return literal(type, binding.get("value", Interface.default_value(type) if default == null else default), n.id)

func expression(id: String, output: String) -> String:
	var key: String = id + ":" + output
	if cache.has(key):
		return cache[key]
	if visiting.has(key):
		fail(id, "Data dependency cycle")
		return "0.0"
	if not nodes.has(id):
		fail(id, "Missing source node")
		return "0.0"
	visiting[key] = true
	var n: Dictionary = nodes[id]
	var ports: Dictionary = get_ports(n)
	var type: String = port_type(ports.outputs, output)
	var value: String = "0.0"
	var args: Array[String] = []
	for p in ports.inputs:
		if p.type != "exec" and n.kind != "emit":
			args.append(argument(n, p.name, p.type))
	match n.kind:
		"input": value = n.get("builtin", "")
		"constant": value = literal(type, n.get("value", Interface.default_value(type)), id)
		"uniform":
			visiting.erase(key)
			return n.get("uniform", "")
		"emit":
			if not emitted.has(id):
				fail(id, "Emission result is only available after its execution")
			visiting.erase(key)
			return emitted.get(id, "false")
		"operator":
			var operation: String = n.get("operation", "add")
			var symbols = {"add": "+", "subtract": "-", "multiply": "*", "divide": "/", "equal": "==", "less": "<", "greater": ">", "and": "&&", "or": "||", "bit_and": "&", "bit_or": "|", "bit_xor": "^", "shift_left": "<<", "shift_right": ">>"}
			if operation in symbols and args.size() == 2:
				value = "(" + args[0] + " " + symbols[operation] + " " + args[1] + ")"
			elif operation in ["not", "bit_not"]:
				value = ("!" if operation == "not" else "~") + args[0]
			else:
				value = operation + "(" + ", ".join(args) + ")"
		"convert":
			if n.get("editor_profile") == "supplemental_v1" and type in ["bool", "int", "uint", "float"] and "vec" in n.get("source_type", ""):
				args[0] += "[0]"
			value = type + "(" + ", ".join(args) + ")"
		"compose": value = type + "(" + ", ".join(args) + ")"
		"split": value = args[0] + "[%d]" % int(output.trim_prefix("c"))
		"transform": value = "(" + args[0] + " * " + args[1] + ")"
		"select": value = "(" + args[0] + " ? " + args[1] + " : " + args[2] + ")"
		"sample": value = "textureLod(" + ", ".join(args) + ")"
		"array_get": value = args[0] + "[" + args[1] + "]"
		"custom":
			var function_name: String = "custom_" + stage + "_" + id
			var params: Array[String] = []
			for p in ports.inputs:
				params.append(p.type + " " + p.name)
			var lines: Array[String] = [type + " " + function_name + "(" + ", ".join(params) + ") {"]
			for code_line in n.get("code", "return " + literal(type, Interface.default_value(type), id) + ";").split("\n"):
				lines.append("\t" + code_line)
			lines.append("}")
			functions[function_name] = {"lines": lines, "stage": stage, "node": id}
			value = function_name + "(" + ", ".join(args) + ")"
		_: fail(id, "Node has no value output")
	visiting.erase(key)
	if type.is_empty() or type == "exec":
		fail(id, "Invalid value output: " + output)
		return "0.0"
	if type.begins_with("sampler") and n.kind == "array_get":
		cache[key] = value
		return value
	serial += 1
	var variable: String = "n_" + id + "_" + output + "_" + str(serial)
	line(type + " " + variable + " = " + value + ";", id)
	cache[key] = variable
	return variable

func line(text: String, node: String) -> void:
	body.append({"text": text, "node": node})

static func identifier(value: String) -> bool:
	return not value.is_empty() and value.is_valid_identifier() and not value.begins_with("__")

static func port_type(ports: Array, name: String) -> String:
	for p in ports:
		if p.name == name:
			return p.type
	return ""

func literal(type: String, value, node: String) -> String:
	if type == "bool":
		if not value is bool:
			fail(node, "Expected a boolean literal")
			return "false"
		return "true" if value == true else "false"
	if type in ["float", "int", "uint"]:
		if not (value is int or value is float) or not is_finite(float(value)):
			fail(node, "Expected a finite numeric literal")
			return "0.0" if type == "float" else ("0u" if type == "uint" else "0")
		if type == "float":
			return "%.9f" % float(value)
		if float(value) != floor(float(value)) or (type == "uint" and (value < 0 or value > 4294967295)) or (type == "int" and (value < -2147483648 or value > 2147483647)):
			fail(node, "Integer literal is outside its exact range")
		return str(int(value)) + ("u" if type == "uint" else "")
	if type.begins_with("sampler") or "[" in type:
		fail(node, "Connect a uniform for " + type)
		return "missing_resource"
	var count: int = int(type.right(1))
	if not value is Array or value.size() != count or count not in [2, 3, 4]:
		fail(node, "Expected %d components for %s" % [count, type])
		return type + "(0.0)"
	var elements: Array[String] = []
	for component in value:
		elements.append(literal("vec" + str(count) if type.begins_with("mat") else Interface.scalar_type(type), component, node))
	return type + "(" + ", ".join(elements) + ")"

func get_ports(n: Dictionary) -> Dictionary:
	return Interface.ports(n, stage, document.get("uniforms", []))

func types_compatible(source: String, target: String) -> bool:
	return source == target
