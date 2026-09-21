extends RefCounted

const Document = preload("document.gd")
const Effect = preload("res://addons/mm_gpu_particles/effect.gd")
const Kernel = preload("kernel.gd")
var errors: Array[Dictionary] = []
var attributes: Dictionary = {}
var parameters: Dictionary = {}
var nodes: Dictionary = {}
var cache: Dictionary = {}
var visiting: Dictionary = {}
var stage := ""
var instance_id := ""
var node_id := ""
var reads: Dictionary = {}
var module_reads: Array = []
var graph_modules: Dictionary = {}
var graph_functions: Dictionary = {}

func fail(message: String) -> void:
	errors.append({"stage":stage,"module":instance_id,"node":node_id,"message":message})

func compile(document: Dictionary, prepared_graphs: Dictionary = {}) -> Dictionary:
	graph_modules = prepared_graphs
	graph_functions.clear()
	errors.clear()
	attributes.clear()
	parameters.clear()
	stage = ""
	instance_id = ""
	node_id = ""
	var effect := Effect.new()
	var shape_error := Document.shape_error(document)
	if not shape_error.is_empty():
		fail(shape_error)
		return result(effect)
	for key in ["modules", "stages", "emitter", "renderer"]:
		if not document.get(key) is Dictionary: fail("Expected object: " + key)
	if not document.get("attributes") is Array: fail("Expected attributes array")
	if not errors.is_empty(): return result(effect)
	var definitions: Array = Document.BUILTINS.duplicate(true)
	definitions.append_array(document.attributes)
	for definition in definitions:
		if not definition is Dictionary:
			fail("Malformed attribute")
			continue
		var id = definition.get("id", "")
		var type = definition.get("type", "")
		if not Document.identifier(id) or attributes.has(id) or not Document.valid_value(type, definition.get("default")):
			fail("Invalid/duplicate attribute or default: " + str(id))
			continue
		var attribute: Dictionary = definition.duplicate(true)
		attribute.offset = effect.component_count
		attribute.symbol = "a" + str(effect.attributes.size())
		effect.component_count += Document.TYPES[type]
		attributes[id] = attribute
		effect.attributes.append(attribute)
	var emitter: Dictionary = document.emitter
	for key in ["rate", "duration", "lifetime"]:
		var value = emitter.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: fail("Invalid emitter " + key)
	if not emitter.get("loop") is bool: fail("Invalid emitter loop")
	if not emitter.get("bursts") is Array:
		fail("Expected bursts array")
	else:
		for burst in emitter.bursts:
			if not burst is Dictionary or not Document.valid_value("float", burst.get("time")) or not Document.valid_value("uint", burst.get("count")):
				fail("Malformed burst")
			elif burst.time < 0 or burst.time >= emitter.get("duration", 0): fail("Burst time must be inside emitter duration")
	var renderer: Dictionary = document.renderer
	if renderer.get("mode") not in ["additive", "opaque", "cutout"]: fail("Unsupported renderer mode")
	if not Document.valid_value("float", renderer.get("quad_size")) or float(renderer.get("quad_size", 0)) <= 0: fail("Quad size must be positive")
	var custom: String = str(renderer.get("custom_attribute", "custom"))
	if not attributes.has(custom) or attributes[custom].type != "vec4": fail("Renderer custom binding requires vec4")
	if not errors.is_empty(): return result(effect)
	effect.emitter = emitter.duplicate(true)
	effect.render_settings = renderer.duplicate(true)
	var bodies := {}
	var instance_ids := {}
	for current_stage in ["spawn", "update"]:
		stage = current_stage
		var body := PackedStringArray()
		if not document.stages.get(stage) is Array:
			fail("Missing stage list")
			continue
		for instance in document.stages[stage]:
			if not instance is Dictionary:
				fail("Malformed module instance")
				continue
			instance_id = str(instance.get("id", ""))
			if not Document.identifier(instance_id) or instance_ids.has(instance_id):
				fail("Invalid/duplicate module instance ID")
				continue
			instance_ids[instance_id] = true
			if not instance.get("enabled", true): continue
			var module = document.modules.get(instance.get("module", ""))
			if not module is Dictionary:
				fail("Missing module snapshot")
				continue
			body.append(compile_module(module, instance, effect))
		bodies[stage] = "\n".join(body)
	if not errors.is_empty(): return result(effect)
	var fields := PackedStringArray(["bool just_spawned;"])
	var load_lines := PackedStringArray()
	var save_lines := PackedStringArray()
	var defaults := PackedStringArray()
	for attribute in effect.attributes:
		fields.append("%s %s;" % [attribute.type, attribute.symbol])
		load_lines.append("s.%s = %s;" % [attribute.symbol, read_storage(attribute.type, attribute.offset, "data", "p.capacity", "i")])
		defaults.append("s.%s = %s;" % [attribute.symbol, literal(attribute.type, attribute.default)])
		for component in Document.TYPES[attribute.type]:
			var value: String = "s." + attribute.symbol + ("[%d]" % component if Document.TYPES[attribute.type] > 1 else "")
			save_lines.append("data[%du*p.capacity+i] = %s;" % [attribute.offset + component, encode(attribute.type, value)])
	var code: String = Kernel.SOURCE
	var substitutions := {"FUNCTIONS":"\n".join(graph_functions.keys()),"FIELDS":"\n".join(fields),"LOAD":"\n".join(load_lines),"SAVE":"\n".join(save_lines),"DEFAULTS":"\n".join(defaults),"SPAWN":bodies.spawn,"UPDATE":bodies.update}
	# Only engine-owned built-ins may fill kernel tokens. A user ID such as
	# FUNCTIONS or Position must not replace a kernel section/builtin binding.
	for builtin in Document.BUILTINS: substitutions[builtin.id.to_upper()] = "s." + attributes[builtin.id].symbol
	substitutions["ALIVE_OFFSET"] = str(attributes.alive.offset)
	substitutions["RENDER_CUSTOM"] = "s." + attributes[custom].symbol
	for key in substitutions: code = code.replace("@" + key + "@", substitutions[key])
	effect.compute_source = code
	effect.source_hash = code.sha256_text()
	var lines := code.split("\n")
	for line in lines.size():
		if lines[line].begins_with("// MODULE "):
			effect.source_map[line + 1] = lines[line].trim_prefix("// MODULE ")
	return result(effect)

func result(effect: Resource) -> Dictionary:
	return {"effect":effect if errors.is_empty() else null, "errors":errors.duplicate(true)}

func compile_module(module: Dictionary, instance: Dictionary, effect: Resource) -> String:
	if not module.get("stages") is Array or stage not in module.stages:
		fail("Module not allowed in " + stage)
		return ""
	for key in ["inputs", "reads", "writes"]:
		if not module.get(key) is Array: fail("Malformed module " + key)
	if not (module.get("graph") is Dictionary or module.get("mm_graph") is Dictionary) or not instance.get("parameters", {}) is Dictionary:
		fail("Malformed module graph/parameters")
		return ""
	if not errors.is_empty(): return ""
	reads.clear()
	module_reads = module.reads
	for id in module.reads + module.writes:
		if not attributes.has(id): fail("Missing contract attribute: " + str(id))
	for input in module.inputs:
		if not input is Dictionary:
			fail("Malformed input")
			continue
		var id := str(input.get("id", ""))
		var key := instance_id + "/" + id
		var type := str(input.get("type", ""))
		var value = instance.get("parameters", {}).get(id, input.get("default"))
		if not Document.identifier(id) or parameters.has(key) or not Document.valid_value(type, value):
			fail("Invalid parameter: " + key)
			continue
		var offset := 32
		if not effect.parameters.is_empty():
			var last: Dictionary = effect.parameters.back()
			offset = last.offset + Document.TYPES[last.type]
		var definition := {"id":key,"name":input.get("name", id),"type":type,"default":value,"offset":offset}
		effect.parameters.append(definition)
		parameters[key] = definition
	for override_id in instance.get("parameters", {}):
		if not parameters.has(instance_id + "/" + str(override_id)): fail("Unknown parameter override: " + str(override_id))
	if module.has("mm_graph"):
		if not graph_modules.has(instance.get("module", "")) or not is_instance_valid(graph_modules[instance.module]):
			fail("Material Maker graph has not been prepared")
			return ""
		var adapter = load("res://material_maker/panels/modular_particles/graph_backend.gd").new()
		var generated: Dictionary = adapter.compile_module(graph_modules[instance.module], self, module, instance_id)
		errors.append_array(generated.errors)
		for function in generated.functions: graph_functions[function] = true
		return "// MODULE " + stage + "/" + instance_id + "\n" + generated.code
	var graph: Dictionary = module.graph
	if not graph.get("nodes") is Array or not graph.get("outputs") is Dictionary:
		fail("Malformed graph nodes/outputs")
		return ""
	nodes.clear()
	cache.clear()
	visiting.clear()
	for node in graph.nodes:
		if not node is Dictionary or not Document.identifier(node.get("id", "")):
			fail("Malformed graph node")
			continue
		if nodes.has(node.id): fail("Duplicate graph node ID")
		nodes[node.id] = node
	var lines := PackedStringArray(["// MODULE " + stage + "/" + instance_id, "{"])
	if not graph.get("steps", []) is Array:
		fail("Malformed write steps")
		return ""
	var steps: Array = graph.get("steps", []).duplicate()
	steps.append({"outputs":graph.outputs})
	for step in steps:
		if not step is Dictionary or not step.get("outputs") is Dictionary:
			fail("Malformed write step")
			continue
		# Invalidate expressions after each explicit write boundary.
		cache.clear()
		lines.append("{")
		if step.has("enabled"):
			var condition := expression(str(step.enabled))
			if condition.type != "bool": fail("Write Enabled requires bool")
			lines.append("if (" + condition.code + ") {")
		var commits := PackedStringArray()
		for id in step.outputs:
			node_id = str(step.outputs[id])
			if not attributes.has(id) or id not in module.writes:
				fail("Undeclared output attribute: " + str(id))
				continue
			var attribute: Dictionary = attributes[id]
			if attribute.get("readonly", false):
				fail("Read-only attribute: " + str(id))
				continue
			var value := expression(str(step.outputs[id]))
			if value.type != attribute.type: fail("Output type mismatch: " + str(id))
			var temporary: String = "out_" + attribute.symbol
			lines.append("%s %s = %s;" % [attribute.type, temporary, value.code])
			commits.append("s.%s = %s;" % [attribute.symbol, temporary])
		lines.append_array(commits)
		if step.has("enabled"): lines.append("}")
		lines.append("}")
	lines.append("}")
	return "\n".join(lines)

func expression(id: String) -> Dictionary:
	node_id = id
	if cache.has(id): return cache[id]
	if visiting.has(id) or not nodes.has(id):
		fail("Cyclic or missing node reference: " + id)
		return {"type":"float","code":"0.0"}
	visiting[id] = true
	var node: Dictionary = nodes[id]
	var values: Array[Dictionary] = []
	if not node.get("args", []) is Array:
		fail("Malformed node arguments")
	else:
		for argument in node.get("args", []): values.append(expression(str(argument)))
	node_id = id
	var value := lower(node, values)
	visiting.erase(id)
	cache[id] = value
	return value

func lower(node: Dictionary, values: Array[Dictionary]) -> Dictionary:
	var op: String = str(node.get("op", ""))
	var type: String = str(node.get("type", "float"))
	var code := "0.0"
	var args: PackedStringArray = []
	for value in values: args.append(value.code)
	match op:
		"constant":
			if not Document.valid_value(type, node.get("value")): fail("Invalid constant")
			else: code = literal(type, node.value)
		"read":
			var attribute = attributes.get(node.get("attribute"))
			if attribute == null or node.get("attribute") not in module_reads: fail("Undeclared attribute read")
			else:
				type = attribute.type
				code = "s." + attribute.symbol
		"parameter":
			var parameter = parameters.get(instance_id + "/" + str(node.get("parameter", "")))
			if parameter == null: fail("Missing parameter")
			else:
				type = parameter.type
				code = read_storage(type, parameter.offset, "params", "1u", "0u")
		"context":
			var fields := {"delta":["float","p.delta"],"time":["float","p.time"],"just_spawned":["bool","just_spawned"],"seed":["uint","p.seed"],"index":["uint","i"]}
			if not fields.has(node.get("field")): fail("Unknown context field")
			else:
				type = fields[node.field][0]
				code = fields[node.field][1]
		"random":
			if type not in ["float", "vec2", "vec3", "vec4"] or not Document.valid_value("uint", node.get("seed", 0)): fail("Invalid random node")
			else: code = "mm_random(s.%s,p.seed,%su)%s" % [attributes.particle_id.symbol,str(int(node.get("seed",0))),{"float":".x","vec2":".xy","vec3":".xyz","vec4":""}[type]]
		"compose":
			if type not in ["vec2", "vec3", "vec4"] or values.size() != Document.TYPES.get(type): fail("Invalid vector constructor")
			for value in values:
				if value.type != "float": fail("Vector components require float")
			code = type + "(" + ",".join(args) + ")"
		"swizzle":
			var swizzle := str(node.get("components", ""))
			if values.size() != 1 or values[0].type not in ["vec2","vec3","vec4"] or swizzle.length() < 1 or swizzle.length() > 4:
				fail("Invalid swizzle")
			else:
				for letter in swizzle:
					if letter not in "xyzw".left(Document.TYPES[values[0].type]): fail("Swizzle component out of range")
				type = "float" if swizzle.length() == 1 else "vec" + str(swizzle.length())
				code = "(" + args[0] + ")." + swizzle
		"select":
			if values.size() != 3 or values[0].type != "bool" or values[1].type != values[2].type: fail("Invalid conditional")
			else:
				type = values[1].type
				code = "(%s ? %s : %s)" % [args[0],args[1],args[2]]
		"add", "subtract", "multiply", "divide", "min", "max", "atan2", "dot":
			if values.size() != 2: fail("Binary operation requires two inputs")
			else:
				type = values[0].type
				if type != values[1].type:
					if type == "float" and values[1].type.begins_with("vec"): type = values[1].type
					elif not (values[1].type == "float" and type.begins_with("vec")): fail("Binary input type mismatch")
				if type == "bool": fail("Numeric operation on bool")
				var symbols := {"add":"+","subtract":"-","multiply":"*","divide":"/"}
				if op in symbols: code = "(%s %s %s)" % [args[0],symbols[op],args[1]]
				else: code = ("atan" if op == "atan2" else op) + "(" + ",".join(args) + ")"
				if op == "dot": type = "float"
		"sin", "cos", "acos", "sqrt", "abs", "floor", "normalize", "length", "negate", "not":
			if values.size() != 1: fail("Unary operation requires one input")
			else:
				type = values[0].type
				if op == "not":
					if type != "bool": fail("Not requires bool")
					code = "(!" + args[0] + ")"
				elif op == "negate": code = "(-" + args[0] + ")"
				else: code = op + "(" + args[0] + ")"
				if op == "length": type = "float"
		"mix", "clamp":
			if values.size() != 3 or values[0].type != values[1].type: fail("Invalid mix/clamp inputs")
			else:
				type = values[0].type
				if values[2].type != type and values[2].type != "float": fail("Invalid mix/clamp third input")
				code = op + "(" + ",".join(args) + ")"
		_:
			fail("Unsupported node operation: " + op)
	return {"type":type,"code":code}

static func literal(type: String, value) -> String:
	if type == "bool": return "true" if value else "false"
	if type == "uint": return str(int(value)) + "u"
	if type == "int": return str(int(value)) if int(value) != -2147483648 else "(-2147483647-1)"
	if type == "float": return "float(" + String.num_scientific(float(value)) + ")"
	var parts := PackedStringArray()
	for item in value: parts.append(literal("float", item))
	return type + "(" + ",".join(parts) + ")"

static func encode(type: String, value: String) -> String:
	if type == "bool": return "(" + value + " ? 1u : 0u)"
	if type == "uint": return value
	if type == "int": return "uint(" + value + ")"
	return "floatBitsToUint(" + value + ")"

static func read_storage(type: String, offset: int, buffer: String, stride: String, index: String) -> String:
	var parts := PackedStringArray()
	for component in Document.TYPES[type]:
		var word := "%s[%du*%s+%s]" % [buffer, offset + component, stride, index]
		if type == "bool": word = "(" + word + " != 0u)"
		elif type == "int": word = "int(" + word + ")"
		elif type != "uint": word = "uintBitsToFloat(" + word + ")"
		parts.append(word)
	return parts[0] if parts.size() == 1 else type + "(" + ",".join(parts) + ")"
