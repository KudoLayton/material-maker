extends Node

const Document = preload("res://addons/material_maker/particles/document.gd")
const Compiler = preload("res://addons/material_maker/particles/compiler.gd")
const Exporter = preload("res://addons/material_maker/particles/exporter.gd")
const Interface = preload("res://addons/material_maker/particles/interface.gd")
var failures: Array = []
var count := 0

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://array_exports")
	for stage in ["start", "process"]:
		for name in Interface.BUILTINS[stage]:
			var doc = Document.create()
			var info: Dictionary = Interface.BUILTINS[stage][name]
			var graph: Dictionary = doc.stages[stage]
			graph.nodes.append({"id": "read", "kind": "input", "builtin": name, "inputs": {}})
			var targets = {"bool": "ACTIVE", "float": "MASS", "vec3": "VELOCITY", "vec4": "CUSTOM", "mat4": "TRANSFORM"}
			var source: String = "read"
			var type: String = info.type
			if type == "uint":
				graph.nodes.append({"id": "convert", "kind": "convert", "source_type": "uint", "data_type": "float", "inputs": {"value": {"node": "read", "port": "value"}}})
				source = "convert"
				type = "float"
			Document.node(graph, "output").inputs[targets[type]] = {"node": source, "port": "value"}
			var result: Dictionary = Exporter.validate(await preload("graph_fixtures.gd").compile(doc, self))
			count += 1
			if not result.errors.is_empty():
				failures.append({"case": stage + "/" + name, "errors": result.errors})
	for type in Interface.TYPES:
		for size in [0, 2]:
			var doc = Document.create()
			var value = Interface.default_value(type)
			doc.uniforms = [{"name": "test_parameter", "type": type, "array_size": size, "value": value if size == 0 else [value, value]}]
			doc.stages.start.nodes.append({"id": "uniform_value", "kind": "uniform", "uniform": "test_parameter", "inputs": {}})
			var source := "uniform_value"
			if size:
				doc.stages.start.nodes.append({"id": "element", "kind": "array_get", "data_type": type, "array_size": size, "inputs": {"array": {"node": source, "port": "value"}}})
				source = "element"
			var code := "return float(value);"
			if "vec" in type: code = "return float(value.x);"
			if type.begins_with("mat"): code = "return value[0][0];"
			if type.begins_with("sampler"):
				var coords := "vec2(0.0)" if type == "sampler2D" else ("vec4(0.0)" if type == "samplerCubeArray" else "vec3(0.0)")
				code = "return textureLod(value, " + coords + ", 0.0).r;"
			doc.stages.start.nodes.append({"id": "consume", "kind": "custom", "data_type": "float", "input_ports": [{"name": "value", "type": type}], "code": code, "inputs": {"value": {"node": source, "port": "value"}}})
			Document.node(doc.stages.start, "output").inputs.MASS = {"node": "consume", "port": "value"}
			var result = Exporter.validate(await preload("graph_fixtures.gd").compile(doc, self))
			count += 1
			if not result.errors.is_empty(): failures.append({"case": type + str(size), "errors": result.errors})
			if size and not type.begins_with("sampler"):
				var prefix: String = "res://array_exports/" + type
				var graph = await preload("graph_fixtures.gd").create(doc, self)
				var exported = await preload("res://addons/material_maker/particles/graph_exporter.gd").export_graph(graph, prefix)
				graph.queue_free()
				if not exported.errors.is_empty():
					failures.append({"case": type + " export", "errors": exported.errors})
				else:
					var material = load(prefix + ".tres")
					var expected: Array = []
					Exporter.flatten([value, value], expected)
					if material == null or material.get_shader_parameter("test_parameter").size() != expected.size():
						failures.append(type + " exported array defaults")
	for mode in Interface.MODES:
		var doc = Document.create()
		doc.render_modes = [mode]
		if not Exporter.validate(await preload("graph_fixtures.gd").compile(doc, self)).errors.is_empty(): failures.append(mode)
	var bad = Document.create()
	bad.stages.start.nodes.append({"id": "broken", "kind": "custom", "data_type": "float", "input_ports": [], "code": "return broken_syntax( ;", "inputs": {}})
	Document.node(bad.stages.start, "output").inputs.MASS = {"node": "broken", "port": "value"}
	var errors = Exporter.validate(await preload("graph_fixtures.gd").compile(bad, self)).errors
	if errors.is_empty():
		failures.append("Custom code errors were not captured")
	elif not errors.any(func(error): return str(error.node).ends_with("start_broken") and error.stage == "start"):
		failures.append("Shader error was not localized to its source node")
	print("PARTICLE_GPU_TESTS: ", count, " interface shaders; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
