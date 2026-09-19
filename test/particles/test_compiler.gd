extends SceneTree

const Document = preload("res://addons/material_maker/particles/document.gd")
const Compiler = preload("res://addons/material_maker/particles/compiler.gd")
const Interface = preload("res://addons/material_maker/particles/interface.gd")
var assertions := 0
var failures: Array[String] = []

func expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var doc = Document.create()
	var compiler = Compiler.new()
	var result = compiler.compile(doc)
	expect(result.errors.is_empty(), "Blank document compiles")
	expect(not "CUSTOM.x" in result.code, "No implicit age storage")
	expect(not "VELOCITY =" in result.code, "Disconnected outputs do not write")
	expect(not "disable_force" in result.code, "No implicit render modes")
	for stage in ["start", "process"]:
		for name in Interface.BUILTINS[stage]:
			var entry: Dictionary = Interface.BUILTINS[stage][name]
			expect(entry.type in Interface.TYPES, "Registered type: " + name)
			var sample = Document.create()
			var graph: Dictionary = sample.stages[stage]
			graph.nodes.append({"id": "read", "kind": "input", "builtin": name, "inputs": {}})
			if entry.write:
				Document.node(graph, "output").inputs[name] = {"node": "read", "port": "value"}
			var built = compiler.compile(sample)
			expect(built.errors.is_empty(), stage + ": " + name)
			if entry.write:
				expect(name + " =" in built.code, "Writable: " + name)
	expect(Interface.BUILTINS.start.USERDATA6.write, "USERDATA is writable in Godot 4.7")
	expect(Interface.BUILTINS.start.AMOUNT_RATIO.type == "float", "AMOUNT_RATIO is float")
	var bad = Document.create()
	bad.stages.start.nodes.append({"id": "collision", "kind": "input", "builtin": "COLLIDED", "inputs": {}})
	expect(not compiler.compile(bad).errors.is_empty(), "Reject stage violation even when disconnected")
	bad = Document.create()
	Document.node(bad.stages.start, "output").inputs.TIME = {"value": 1.0}
	expect(not compiler.compile(bad).errors.is_empty(), "Reject writes to read-only state")
	bad = Document.create()
	bad.stages.start.nodes.append({"id": "number", "kind": "constant", "data_type": "uint", "value": 7, "inputs": {}})
	Document.node(bad.stages.start, "output").inputs.VELOCITY = {"node": "number", "port": "value"}
	expect(not compiler.compile(bad).errors.is_empty(), "Reject implicit uint to vector conversion")
	bad = Document.create()
	bad.uniforms = [{"name": "speed", "type": "float", "value": 1.0}, {"name": "speed", "type": "vec3", "value": [1, 2, 3]}]
	expect(not compiler.compile(bad).errors.is_empty(), "Reject conflicting uniforms")
	bad = Document.create()
	bad.stages.process.nodes.append({"id": "cycle", "kind": "operator", "operation": "add", "data_type": "float", "inputs": {"a": {"node": "cycle", "port": "value"}}})
	Document.node(bad.stages.process, "output").inputs.MASS = {"node": "cycle", "port": "value"}
	expect(not compiler.compile(bad).errors.is_empty(), "Reject data cycles")
	var ordered = Document.create()
	ordered.stages.process.nodes.append({"id": "set_mass", "kind": "set", "builtin": "MASS", "inputs": {"exec": {"node": "entry", "port": "next"}, "value": {"value": 2.0}}})
	ordered.stages.process.nodes.append({"id": "mass", "kind": "input", "builtin": "MASS", "inputs": {}})
	var output: Dictionary = Document.node(ordered.stages.process, "output")
	output.inputs.exec = {"node": "set_mass", "port": "next"}
	output.inputs.MASS = {"node": "mass", "port": "value"}
	result = compiler.compile(ordered)
	expect(result.errors.is_empty(), "Ordered state writes compile")
	expect(result.code.find("MASS =") < result.code.rfind("= MASS;"), "Reads after writes are not cached across steps")
	var emission = Document.create()
	emission.stages.process.nodes.append({"id": "emit", "kind": "emit", "inputs": {"exec": {"node": "entry", "port": "next"}}})
	output = Document.node(emission.stages.process, "output")
	output.inputs.exec = {"node": "emit", "port": "next"}
	output.inputs.ACTIVE = {"node": "emit", "port": "success"}
	result = compiler.compile(emission)
	expect(result.errors.is_empty(), "Emission success can be consumed downstream")
	expect(result.code.count("emit_subparticle(") == 1, "Emission is evaluated once")
	var restored = JSON.parse_string(JSON.stringify(ordered))
	expect(compiler.compile(restored).code == compiler.compile(ordered).code, "Stable serialization")
	for malformed in [{}, {"type": "particle_graph", "version": 1}, {"type": "particle_graph", "version": 99}]:
		expect(not compiler.compile(malformed).errors.is_empty(), "Reject malformed document")
	bad = Document.create()
	bad.stages.start.nodes.append({"id": "malformed", "kind": "custom", "input_ports": [1], "inputs": {}})
	expect(not compiler.compile(bad).errors.is_empty(), "Reject malformed custom ports")
	print("PARTICLE_NATIVE_TESTS: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
