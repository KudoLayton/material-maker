extends "compiler.gd"

var generators: Dictionary = {}
var mm_uniforms: Dictionary = {}
var graph_models: Dictionary = {}
var state_fields: Dictionary = {}
var collecting: Dictionary = {}
var collection_errors: Array = []
var current_uv := "vec2(0.0)"

func compile_graph(graph: MMGenGraph) -> Dictionary:
	collecting = {}
	collection_errors = []
	generators = {}
	mm_uniforms = {}
	graph_models = {}
	state_fields = Interface.BUILTINS.start.duplicate(true)
	state_fields.merge(Interface.BUILTINS.process)
	state_fields["sampling_uv"] = {"type": "vec2"}
	var data := Document.create()
	var material = graph.get_node_or_null("Material")
	if material != null and material.has_method("particle_configuration"):
		data.merge(material.particle_configuration(), true)
	var uniforms: Dictionary = {}
	for current_stage in ["start", "process"]:
		var models: Dictionary = {}
		for child in graph.get_children():
			if child.has_method("model_data"):
				var model: Dictionary = child.model_data()
				if model.kind == "output" and model.get("stage", "process") == current_stage:
					collect(child, models)
		for model in models.values():
			if model.kind == "uniform":
				var u: Dictionary = generators[model.id].uniform_definition()
				if uniforms.has(u.name) and uniforms[u.name] != u:
					# Preserve both declarations so the common validator reports the conflict.
					data.uniforms.append(u)
				uniforms[u.name] = u
			if model.kind == "emit": state_fields["result_" + model.id] = {"type": "bool"}
		graph_models[current_stage] = models
	if not collection_errors.is_empty():
		return {"code": "", "errors": collection_errors, "source_map": {}}
	data.uniforms.append_array(uniforms.values())
	var result := compile(data)
	result["uniforms"] = data.uniforms
	result["target_project"] = data.get("target_project", "")
	result["mm_uniforms"] = mm_uniforms
	for error in result.errors:
		if generators.has(error.node): error.node = generators[error.node].get_hier_name()
	for location in result.source_map.values():
		if generators.has(location.node): location.node = generators[location.node].get_hier_name()
	return result

func collect(generator: MMGenBase, models: Dictionary) -> void:
	var id := "g" + str(generator.get_instance_id())
	if collecting.has(id):
		collection_errors.append({"stage": "", "node": generator.get_hier_name(), "message": "Data or execution dependency cycle"})
		return
	if models.has(id): return
	collecting[id] = true
	generators[id] = generator
	var n: Dictionary = generator.model_data() if generator.has_method("model_data") else {"id": id, "kind": "library", "inputs": {}}
	models[id] = n
	var inputs := generator.get_input_defs()
	for i in inputs.size():
		var source = preload("dependencies.gd").source(generator, i)
		if source == null: continue
		if source.output_index < 0 or source.output_index >= source.generator.get_output_defs().size():
			collection_errors.append({"stage": "", "node": generator.get_hier_name(), "message": "Invalid source output port"})
			continue
		collect(source.generator, models)
		if n.kind != "library":
			var source_id := "g" + str(source.generator.get_instance_id())
			var output_name: String = "port%d" % source.output_index
			if source.generator.has_method("particle_ports"):
				output_name = source.generator.particle_ports().outputs[source.output_index].name
			n.inputs[inputs[i].name] = {"node": source_id, "port": output_name}

	collecting.erase(id)

func get_ports(n: Dictionary) -> Dictionary:
	if n.get("kind") == "library":
		var outputs: Array = []
		if generators.has(n.id):
			for p in generators[n.id].get_output_defs():
				outputs.append({"name": "port%d" % outputs.size(), "type": shader_type(p.type)})
		return {"inputs": [], "outputs": outputs}
	if n.get("kind") in ["evaluate", "bridge"]:
		return generators[n.id].particle_ports()
	return super.get_ports(n)

static func shader_type(type: String) -> String:
	if type in ["f", "rgb", "rgba"]: return mm_io_types.types[type].type
	return mm_io_types.types[type].get("particle_type", type) if mm_io_types.types.has(type) else type

func validate_node(n: Dictionary) -> void:
	if n.kind == "random":
		if n.data_type not in Interface.RANDOM_TYPES: fail(n.id, "Random requires float, vec2, vec3 or vec4")
		return
	if n.kind in ["library", "evaluate", "bridge"]: return
	if n.kind == "entry" and n.get("stage", stage) != stage:
		fail(n.id, "Entry belongs to " + str(n.stage))
	super.validate_node(n)

func compile_stage(_graph: Dictionary) -> Array:
	current_uv = "_mm_state.sampling_uv"
	var models: Dictionary = graph_models[stage]
	var sampling = {"id": "", "inputs": {}}
	for model in models.values():
		if model.kind == "output":
			sampling.id = model.id
			if model.inputs.has("sampling_uv"):
				sampling.inputs.sampling_uv = model.inputs.sampling_uv
				model.inputs.erase("sampling_uv")
	var entries: Array = models.values().filter(func(n): return n.kind == "entry")
	if entries.is_empty():
		var entry := {"id": "entry", "kind": "entry", "inputs": {}}
		models.entry = entry
		for n in models.values():
			if n.kind == "output" and not n.inputs.has("exec"):
				n.inputs.exec = {"node": "entry", "port": "next"}
	var lines: Array[String] = ["struct MMParticleState {"]
	for field in state_fields: lines.append("\t" + state_fields[field].type + " " + field + ";")
	lines.append("};")
	functions["particle_state"] = {"lines": lines, "node": "", "stage": ""}
	var generated: Array = super.compile_stage({"nodes": models.values()})
	body = []
	cache = {}
	visiting = {}
	emitted = {}
	current_uv = "vec2(0.0)"
	var uv := "vec2(0.0)"
	var binding = sampling.inputs.get("sampling_uv", {})
	if not binding is Dictionary:
		fail(sampling.id, "Malformed Sampling UV input")
	elif binding.has("node") and not types_compatible(port_type(get_ports(nodes.get(str(binding.node), {})).outputs, binding.get("port", "value")), "vec2"):
		fail(sampling.id, "Sampling UV requires vec2")
	else:
		uv = argument(sampling, "sampling_uv", "vec2", [0.0, 0.0])
	var initial: Array = [{"text": "MMParticleState _mm_state;", "node": ""}, {"text": "float _seed_variation_ = 0.0; vec4 _controlled_variation_ = vec4(0.0);", "node": ""}]
	for field in Interface.BUILTINS[stage]:
		initial.append({"text": "_mm_state." + field + " = " + field + ";", "node": ""})
	initial.append({"text": "_mm_state.sampling_uv = vec2(0.0);", "node": sampling.id})
	initial.append_array(body)
	initial.append({"text": "_mm_state.sampling_uv = " + uv + ";", "node": sampling.id})
	initial.append_array(generated)
	return initial

func line(text: String, node: String) -> void:
	super.line(text, node)
	if text.begins_with("if (") and nodes.has(node):
		if nodes[node].kind == "set":
			var field: String = nodes[node].builtin
			super.line("_mm_state." + field + " = " + field + ";", node)
		elif nodes[node].kind == "emit":
			super.line("_mm_state.result_" + node + " = emit_" + node + ";", node)

func expression(id: String, output: String) -> String:
	if not nodes.has(id): return super.expression(id, output)
	var n: Dictionary = nodes[id]
	if n.kind == "random": return random_expression(n)
	if n.kind == "input": return "_mm_state." + str(n.builtin)
	if n.kind == "emit" and emitted.has(id): return "_mm_state.result_" + id
	if n.kind == "bridge": return argument(n, "value", n.data_type)
	if n.kind == "library":
		return evaluate_library(generators[id], int(output.trim_prefix("port")), current_uv, id)
	if n.kind != "evaluate": return super.expression(id, output)
	if visiting.has(id):
		fail(id, "Evaluation dependency cycle")
		return "0.0"
	visiting[id] = true
	var generator: MMGenBase = generators[id]
	var source = generator.get_source(0)
	if source == null or generator.get_source(1) == null:
		fail(id, "Evaluate requires a function and explicit coordinates")
		visiting.erase(id)
		return "0.0"
	var coordinates := argument(n, "coordinates", get_ports(n).inputs[1].type)
	var result := evaluate_library(source.generator, source.output_index, coordinates, id, n.function_type)
	visiting.erase(id)
	return result

func random_expression(n: Dictionary) -> String:
	if n.data_type not in Interface.RANDOM_TYPES: return "0.0"
	functions["particle_random"] = {"lines": preload("random.gd").SHADER.split("\n"), "stage": "", "node": n.id}
	var particle_id := argument(n, "particle_id", "uint") if n.inputs.has("particle_id") else "_mm_state.NUMBER"
	var system_seed := argument(n, "system_seed", "uint") if n.inputs.has("system_seed") else "_mm_state.RANDOM_SEED"
	var seed := argument(n, "seed", "uint", n.get("seed", 0))
	var bounds: Array[String] = []
	for key in ["minimum", "maximum"]:
		var value = n.get(key, 1.0 if key == "maximum" else 0.0)
		if n.data_type != "float":
			var components: Array = []
			components.resize(int(n.data_type.right(1)))
			components.fill(value)
			value = components
		bounds.append(argument(n, key, n.data_type, value))
	var swizzle: String = {"float": "x", "vec2": "xy", "vec3": "xyz", "vec4": "xyzw"}.get(n.data_type, "x")
	return "mix(%s, %s, mm_particle_random(%s, %s, %s).%s)" % [bounds[0], bounds[1], particle_id, system_seed, seed, swizzle]

func generate_value(generator: MMGenBase, output_index: int, uv: String, _context: MMGenContext) -> MMGenBase.ShaderCode:
	var id := "g" + str(generator.get_instance_id())
	var saved_body := body
	var saved_cache := cache
	var saved_uv := current_uv
	current_uv = uv
	body = []
	cache = {}
	var ports: Dictionary = generator.particle_ports()
	var value := expression(id, ports.outputs[output_index].name)
	var result := MMGenBase.ShaderCode.new()
	result.output_type = generator.get_output_defs()[output_index].type
	result.output_values[result.output_type] = value
	for item in body: result.code += item.text + "\n"
	body = saved_body
	cache = saved_cache
	current_uv = saved_uv
	return result

func evaluate_library(generator: MMGenBase, index: int, coordinates: String, owner_id: String, requested_type: String = "") -> String:
	var problem := preload("dependencies.gd").bake_error(generator)
	if not problem.is_empty():
		fail(owner_id, problem)
		return "0.0"
	var context := MMGenContext.new()
	context.particle_compiler = self
	var code: MMGenBase.ShaderCode = generator.get_shader_code(coordinates, index, context)
	if not code.error.is_empty(): fail(owner_id, code.error)
	serial += 1
	var prefix := "mm_%s_%d_" % [stage, serial]
	var symbols := RegEx.create_from_string("mm_(?:start|process)_[0-9]+_o[0-9]+|o[0-9]+")
	var rewrite = func(text: String) -> String:
		var matches := symbols.search_all(text)
		matches.reverse()
		for match in matches:
			if match.get_string().begins_with("o"):
				text = text.insert(match.get_start(), prefix)
		return text.replace("vec4 _controlled_variation_", "vec4 _controlled_variation_, MMParticleState _mm_state").replace("_controlled_variation_)", "_controlled_variation_, _mm_state)").replace("(, float _seed_variation_", "(float _seed_variation_").replace("(, _seed_variation_", "(_seed_variation_")
	for uniform in code.uniforms:
		var name: String = rewrite.call(uniform.name)
		if not uniform.type.begins_with("sampler"):
			functions[name] = {"lines": [rewrite.call(uniform.to_str("const", true))], "stage": stage, "node": owner_id}
			continue
		mm_uniforms[name] = uniform
		var declaration := "uniform " + uniform.type + " " + name
		if uniform.size > 0: declaration += "[%d]" % uniform.size
		elif uniform.type == "sampler2D": declaration += " : repeat_enable"
		functions[name] = {"lines": [declaration + ";"], "stage": stage, "node": owner_id}
	functions["mm_common"] = {"lines": MMGenMaterial.get_template_text("glsl_defs.tmpl").split("\n"), "stage": "", "node": ""}
	for global in code.globals:
		functions[global.code] = {"lines": global.code.split("\n"), "stage": stage, "node": owner_id}
	functions[prefix] = {"lines": str(rewrite.call(code.defs)).split("\n"), "stage": stage, "node": owner_id}
	for code_line in str(rewrite.call(code.code)).split("\n"):
		line(code_line, owner_id)
	var type: String = requested_type if not requested_type.is_empty() else code.output_type
	if not code.output_values.has(type):
		fail(owner_id, "Library output cannot provide " + type)
		return "0.0"
	return rewrite.call(code.output_values[type])

func static_value(generator: MMGenBase, output_index: int, uv: String) -> MMGenBase.ShaderCode:
	var models: Dictionary = {}
	collect(generator, models)
	var result := MMGenBase.ShaderCode.new()
	for model in models.values():
		if model.kind in ["library", "evaluate", "input", "uniform", "set", "emit", "random"]:
			result.error = generator.get_hier_name() + ": this value requires a particle context"
			return result
	nodes = models
	document = {"uniforms": []}
	stage = "process"
	result = generate_value(generator, output_index, uv, MMGenContext.new())
	for function in functions.values(): result.defs += "\n".join(function.lines) + "\n"
	if not errors.is_empty(): result.error = str(errors)
	return result

func argument(n: Dictionary, name: String, type: String, default = null) -> String:
	var value := super.argument(n, name, type, default)
	var binding: Dictionary = n.get("inputs", {}).get(name, {})
	if not binding.has("node"): return value
	var source: Dictionary = nodes.get(str(binding.node), {})
	var source_type := shader_type(port_type(get_ports(source).outputs, binding.get("port", "value")))
	var target_type := shader_type(type)
	if source_type == target_type: return value
	if source_type in ["float", "vec3", "vec4"] and target_type in ["float", "vec3", "vec4"]:
		for conversion in mm_io_types.types[MMGenParticle.value_type(source_type)].get("convert", []):
			if conversion.type == MMGenParticle.value_type(target_type):
				return conversion.expr.replace("$(value)", value)
	return value

func types_compatible(source: String, target: String) -> bool:
	if shader_type(source) == shader_type(target): return true
	if shader_type(source) in ["float", "vec3", "vec4"] and shader_type(target) in ["float", "vec3", "vec4"]: return true
	if source in MMGenParticle.FUNCTION_TYPES and target in MMGenParticle.FUNCTION_TYPES:
		for conversion in mm_io_types.types[source].get("convert", []):
			if conversion.type == target: return true
	return false
