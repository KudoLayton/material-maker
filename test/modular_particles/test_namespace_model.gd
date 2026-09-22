extends Node
const Presentation = preload("res://addons/material_maker/particles/modular/presentation.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
const Generator = preload("res://material_maker/panels/modular_particles/generator.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var doc := Library.new_document()
	doc.attributes = [{"id":"custom_position","name":"Position","type":"vec3","default":[0.0,0.0,0.0]},
		{"id":"12345678a","name":"Duplicate","type":"vec4","default":[0.0,0.0,0.0,0.0]},
		{"id":"12345678b","name":"Duplicate","type":"vec4","default":[0.0,0.0,0.0,0.0]}]
	var module_id := "initialize_velocity"
	doc.modules[module_id].inputs[0].name = "Position"
	var original: Dictionary = doc.duplicate(true)
	var ctx := Presentation.context(doc,module_id)
	var input := Presentation.describe("module_parameter","velocity","Stale","float",ctx)
	var builtin := Presentation.describe("module_read","position","Stale","float",ctx)
	var custom := Presentation.describe("module_read","custom_position","Stale","float",ctx)
	check(input.display == "Module.Position" and input.type == "vec3","module namespace and current definition override cached label/type")
	check(builtin.display == "Particle.Position" and builtin.renderer == "Position","builtin namespace and render binding")
	check(custom.display == "Particle.Custom.Position" and custom.renderer == "Not bound","custom Position does not bind by name")
	check(builtin.output == "Not registered","output absent distinguished from a declared port")
	check(Presentation.describe("module_read","velocity","","",ctx).output == "Connected","connected output detected")
	var graph: Dictionary = doc.modules[module_id].mm_graph.duplicate(true)
	graph.connections.clear()
	ctx = Presentation.context(doc,module_id,graph)
	check(Presentation.describe("module_output","velocity","","",ctx).output.begins_with("Unconnected"),"declared but unwired output preserves value")
	check(Presentation.describe("module_output","position","","",ctx).qualified == builtin.qualified,"read and write share namespace")
	check(Presentation.describe("module_output","age","","",ctx).readonly,"readonly builtin preserved")
	check(Presentation.describe("module_context","delta","Wrong","",ctx).display == "Context.delta","context namespace")
	var first := Presentation.describe("module_read","12345678a","","",ctx)
	var second := Presentation.describe("module_read","12345678b","","",ctx)
	check(first.badge == "[#12345678a]" and second.badge == "[#12345678b]","duplicate badges extend beyond colliding eight-character prefix")
	check(first.raw_name == "Duplicate" and first.tooltip.contains("Stable ID: 12345678a"),"badge does not alter raw name and full ID is available")
	doc.renderer.custom_attribute = "12345678a"
	ctx = Presentation.context(doc,module_id)
	check(Presentation.describe("module_read","12345678a","","",ctx).renderer == "INSTANCE_CUSTOM","custom renderer target follows actual ID setting")
	check(Presentation.describe("module_read","custom","","",ctx).renderer == "Not bound","old custom-data target is no longer marked bound")
	doc.renderer.custom_attribute = "custom_position"
	ctx = Presentation.context(doc,module_id)
	check(Presentation.describe("module_read","custom_position","","",ctx).renderer.contains("requires vec4"),"invalid renderer target is not represented as valid binding")
	var missing := Presentation.describe("module_read","missing","Position","vec3",ctx)
	check(missing.missing and missing.display.contains("Missing: missing") and missing.renderer == "Not bound","missing ID never aliases a same-name definition")
	var fallback := Presentation.describe("module_parameter","unknown","Saved Position","vec3")
	check(not fallback.missing and fallback.display == "Module.Saved Position" and fallback.tooltip.contains("context unavailable"),"Library fallback is explicit about unavailable context")
	var literal := "Particle.Position.한글 " + "Long".repeat(30)
	doc.modules[module_id].inputs[0].name = literal
	ctx = Presentation.context(doc,module_id)
	check(Presentation.describe("module_parameter","velocity","","",ctx).qualified == "Module."+literal,"namespace-looking raw names are literal")
	check(Presentation.compact(literal).length() == 48 and Presentation.compact(literal).ends_with("…"),"long labels have a bounded display form")

	var generator := Generator.new()
	generator.settings = {"kind":"module_read","id":"custom_position","label":"Old Position","data_type":"vec3"}
	var serialized := generator.serialize().duplicate(true)
	var ports := generator.particle_ports().duplicate(true)
	generator.set_display_context(ctx)
	check(generator.get_type_name() == "Read Particle.Custom.Position","node title is qualified")
	check(generator.get_output_defs()[0].label == "Particle.Custom.Position","modular port_defs preserves qualified label")
	check(generator.get_output_defs()[0].name == "value" and generator.get_output_defs()[0].type == "rgb" and generator.get_output_defs()[0].shader_type == "vec3","port ID and type ABI preserved")
	check(generator.get_output_defs()[0].tooltip.contains("Stable ID: custom_position"),"optional port tooltip supplied")
	check(generator.serialize() == serialized and generator.particle_ports() == ports,"display context is absent from serialization and compiler port models")
	generator.settings = {"kind":"module_output","fields":[{"id":"position","name":"Stale","type":"vec3"},{"id":"custom_position","name":"Stale","type":"vec3"}]}
	check(generator.get_input_defs()[0].label == "Write Particle.Position" and generator.get_input_defs()[1].label == "Write Particle.Custom.Position","same-name output targets are distinct")
	generator.free()

	var graphs := {}
	for id in original.modules: graphs[id] = await mm_loader.create_gen(original.modules[id].mm_graph.duplicate(true))
	var compiled := Compiler.new().compile(original,graphs)
	for id in graphs:
		var snapshot: Dictionary = graphs[id].serialize().duplicate(true)
		var context := Presentation.context(original,id)
		for node in graphs[id].get_children():
			if node.has_method("set_display_context"): node.set_display_context(context)
		check(snapshot == graphs[id].serialize(),"loaded graph serialization unchanged: " + id)
	var after := Compiler.new().compile(original,graphs)
	check(compiled.errors.is_empty() and after.errors.is_empty(),"qualified graph compiles")
	check(compiled.effect.source_hash == after.effect.source_hash and compiled.effect.attributes == after.effect.attributes and compiled.effect.parameters == after.effect.parameters,"shader hash and attribute/parameter layouts unchanged")
	for graph_node in graphs.values(): graph_node.free()
	print("MODULAR_NAMESPACE_MODEL ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
