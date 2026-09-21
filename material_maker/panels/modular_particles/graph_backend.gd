extends "res://addons/material_maker/particles/graph_compiler.gd"
## Adapter for existing MM procedural nodes, Curve, FBM, nested subgraphs,
## typed operations and Evaluate Function. No legacy particle shader translation.
var backend: RefCounted
var module: Dictionary
var module_instance := ""

func compile_module(graph: MMGenGraph, owner: RefCounted, definition: Dictionary, instance: String) -> Dictionary:
	# MM procedural seed inheritance expects the graph to have a parent.
	var temporary_parent: Node
	if graph.get_parent() == null:
		temporary_parent = Node.new()
		temporary_parent.add_child(graph)
	backend = owner
	module = definition
	module_instance = instance
	stage = "process"
	document = {"uniforms":[]}
	var sinks: Array = []
	for child in graph.get_children():
		if child.get("settings") is Dictionary and child.settings.get("kind") == "module_output": sinks.append(child)
	if sinks.size() != 1: fail("", "Module requires exactly one Module Output")
	var models := {}
	if sinks.size() == 1: collect(sinks[0], models)
	errors.append_array(collection_errors)
	nodes = models
	for model in models.values():
		if model.kind in ["input", "uniform", "set", "emit", "entry", "output", "sample", "array_get", "transform_read"]:
			fail(model.id, "Use named module bindings instead of legacy particle built-ins; texture/array nodes are not supported")
	var assignments := PackedStringArray()
	if errors.is_empty():
		var sink = sinks[0]
		var model: Dictionary = models["g" + str(sink.get_instance_id())]
		for field in sink.settings.fields:
			if not model.inputs.has(field.id): continue
			if not backend.attributes.has(field.id) or field.id not in module.writes:
				fail(model.id,"Missing output Attribute contract: " + field.id)
				continue
			var attribute: Dictionary = backend.attributes[field.id]
			if attribute.get("readonly", false) or field.type != attribute.type:
				fail(model.id,"Invalid or read-only output Attribute: " + field.id)
				continue
			var value := argument(model,field.id,field.type)
			line(field.type + " out_" + attribute.symbol + " = " + value + ";", model.id)
			assignments.append("s."+attribute.symbol+" = out_"+attribute.symbol+";")
	var code := "{\nParticleState _mm_state = s;\nfloat _seed_variation_=0.0; vec4 _controlled_variation_=vec4(0.0);\n"
	for statement in body: code += statement.text + "\n"
	code += "\n".join(assignments) + "\n}\n"
	if not mm_uniforms.is_empty(): fail("", "Texture and baked Buffer inputs are not supported in modular particle v1")
	# Replace transient object IDs and namespace per module instance. Only shader
	# identifiers are rewritten; authoring IDs and the runtime layout stay stable.
	# Godot 4 ObjectIDs include the validator bits (at least 8 decimal digits).
	# Do NOT rewrite ordinary shared GLSL locals such as noise gradients g0/g1.
	var symbols := RegEx.create_from_string("[og][0-9]{7,}")
	var shader_prefix := "mod_" + instance.sha256_text().left(12) + "_"
	var stable: Dictionary = {}
	var ordinal := 0
	var all_text := code
	for function in functions.values(): all_text += "\n".join(function.lines)
	for token in symbols.search_all(all_text):
		if not stable.has(token.get_string()):
			stable[token.get_string()] = shader_prefix + "o" + str(ordinal)
			ordinal += 1
	var rewrite := func(text: String) -> String:
		var matches := symbols.search_all(text)
		matches.reverse()
		for token in matches:
			text = text.left(token.get_start()) + stable[token.get_string()] + text.substr(token.get_end())
		return text.replace("mm_process_", shader_prefix).replace("MMParticleState", "ParticleState")
	var declarations: Array[String] = []
	for function in functions.values(): declarations.append(rewrite.call("\n".join(function.lines)))
	var diagnostics: Array[Dictionary] = []
	for error in errors:
		var location: String = error.node
		if generators.has(location): location = generators[location].get_hier_name()
		diagnostics.append({"stage":owner.stage,"module":instance,"node":location,"message":error.message})
	if temporary_parent != null:
		temporary_parent.remove_child(graph)
		temporary_parent.free()
	return {"code":rewrite.call(code),"functions":declarations,"errors":diagnostics}

func get_ports(n: Dictionary) -> Dictionary:
	if n.get("kind", "").begins_with("module_"): return generators[n.id].particle_ports()
	return super.get_ports(n)

func expression(id: String, output: String) -> String:
	if not nodes.has(id): return super.expression(id, output)
	var n: Dictionary = nodes[id]
	if n.kind == "module_read":
		var binding: String = generators[id].settings.id
		if not backend.attributes.has(binding) or binding not in module.reads:
			fail(id,"Missing read Attribute contract: " + binding)
			return "0.0"
		if backend.attributes[binding].type != n.data_type: fail(id,"Read Attribute type changed: " + binding)
		return "_mm_state." + backend.attributes[binding].symbol
	if n.kind == "module_parameter":
		var key: String = module_instance + "/" + generators[id].settings.id
		if not backend.parameters.has(key):
			fail(id,"Missing module input: " + key)
			return "0.0"
		var parameter: Dictionary = backend.parameters[key]
		if parameter.type != n.data_type: fail(id,"Module input type changed: " + key)
		return backend.read_storage(parameter.type,parameter.offset,"params","1u","0u")
	if n.kind == "module_context":
		return {"delta":"p.delta","time":"p.time","just_spawned":"_mm_state.just_spawned","seed":"p.seed","index":"gl_GlobalInvocationID.x"}.get(generators[id].settings.id,"0.0")
	return super.expression(id,output)

func random_expression(n: Dictionary) -> String:
	return super.random_expression(n).replace("_mm_state.NUMBER","_mm_state."+backend.attributes.particle_id.symbol).replace("_mm_state.RANDOM_SEED","p.seed")
