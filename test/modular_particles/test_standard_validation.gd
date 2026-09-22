extends Node
const S = preload("standard_checks.gd")
const V = preload("res://addons/material_maker/particles/modular/standard_validation.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func invalid(doc: Dictionary, text: String) -> void:
	var result := V.validate(doc)
	check(result.errors.any(func(e): return text in e.message),"diagnostic: "+text+" -> "+str(result.errors))
func module(doc: Dictionary, id: String) -> Dictionary:
	return doc.modules[S.instance(doc,id).module]
func run() -> void:
	var base := S.document(["initialize_particle","box_location","add_velocity"],["gravity","drag","curl_noise","solve_motion","color_over_life","scale_over_life","kill_particles"])
	check(V.validate(base).errors.is_empty(),"valid complete stack")
	var doc := base.duplicate(true)
	S.instance(doc,"solve_motion").enabled = false
	invalid(doc,"Add exactly one active Solve Motion")
	doc = base.duplicate(true)
	doc.stages.update.remove_at(3)
	invalid(doc,"Add exactly one active Solve Motion")
	doc = base.duplicate(true)
	var solver: Dictionary = S.instance(doc,"solve_motion").duplicate(true)
	solver.id = S.D.uid()
	doc.stages.update.append(solver)
	invalid(doc,"duplicate solvers")
	doc = base.duplicate(true)
	var gravity: Dictionary = doc.stages.update.pop_front()
	doc.stages.update.append(gravity)
	invalid(doc,"Move this module before Solve Motion")
	doc = base.duplicate(true)
	var role: String = S.attribute_id(doc,"acceleration")
	doc.attributes = doc.attributes.filter(func(a): return a.id != role)
	invalid(doc,"Missing or incompatible standard Attribute binding")
	doc = base.duplicate(true)
	doc.attributes[0].type = "float"
	doc.attributes[0].default = 0.0
	invalid(doc,"incompatible standard Attribute")
	doc = base.duplicate(true)
	var duplicate: Dictionary = doc.attributes[0].duplicate(true)
	duplicate.id = S.D.uid()
	doc.attributes.append(duplicate)
	invalid(doc,"Duplicate standard Attribute role")
	doc = base.duplicate(true)
	module(doc,"gravity").standard_module.bindings["mm.standard.v1.acceleration"] = "position"
	invalid(doc,"same Attribute binding")
	doc = base.duplicate(true)
	module(doc,"solve_motion").mm_graph.connections = module(doc,"solve_motion").mm_graph.connections.filter(func(c): return not (c.to == "Output" and c.to_port == 2))
	invalid(doc,"Required write is disconnected: acceleration")
	doc = base.duplicate(true)
	module(doc,"gravity").mm_graph.connections = module(doc,"gravity").mm_graph.connections.filter(func(c): return c.from != "Read_acceleration")
	invalid(doc,"Required read is disconnected: acceleration")
	doc = base.duplicate(true)
	S.instance(doc,"initialize_particle").enabled = false
	invalid(doc,"Add an active Spawn writer for initial_color")
	invalid(doc,"Add an active Spawn writer for initial_scale")
	doc = base.duplicate(true)
	module(doc,"initialize_particle").mm_graph.connections = module(doc,"initialize_particle").mm_graph.connections.filter(func(c): return not (c.to == "Output" and c.to_port == 4))
	invalid(doc,"Spawn writer for initial_color")
	doc = base.duplicate(true)
	var init: Dictionary = doc.stages.spawn.pop_front()
	doc.stages.spawn.append(init)
	invalid(doc,"Move Initialize Particle before")
	doc = base.duplicate(true)
	init = S.instance(doc,"initialize_particle").duplicate(true)
	init.id = S.D.uid()
	doc.stages.spawn.append(init)
	invalid(doc,"at most one active Initialize")
	S.instance(doc,"initialize_particle").enabled = false
	check(V.validate(doc).errors.any(func(e): return "Move Initialize" in e.message),"disabled initializer not counted as prerequisite")
	doc = base.duplicate(true)
	for definition in doc.modules.values(): definition.name = "무관한 이름"
	for attribute in doc.attributes: attribute.name = "Position"
	check(V.validate(doc).errors.is_empty(),"names and namespace-looking labels do not control rules")
	doc.modules.legacy = Library.defaults().integrate_velocity
	doc.stages.update.append({"id":"legacy_instance","module":"legacy","enabled":true,"parameters":{}})
	var mixed := V.validate(doc)
	check(mixed.errors.is_empty() and mixed.warnings.size() == 1,"other Position writer warns, does not block")
	var compiled := await S.compile(doc)
	check(compiled.errors.is_empty() and compiled.effect != null and compiled.warnings.size() == 1,"compiler returns successful effect plus warnings")
	S.instance(doc,"solve_motion").enabled = false
	compiled = await S.compile(doc)
	check(compiled.effect == null and not compiled.errors.is_empty(),"standard errors block compilation/export")
	doc = base.duplicate(true)
	for definition in doc.modules.values(): definition.erase("standard_module")
	doc.stages.update.reverse()
	check(V.validate(doc).errors.is_empty() and V.validate(doc).warnings.is_empty(),"rules not applied retroactively to untagged modules")
	# A custom typed-IR Spawn writer can supply the initial values; no named Initialize is required.
	doc = S.document([], ["color_over_life","scale_over_life"])
	var color_id := S.attribute_id(doc,"initial_color")
	var scale_id := S.attribute_id(doc,"initial_scale")
	doc.modules.custom = {"name":"Custom Initial Values","stages":["spawn"],"reads":[],"writes":[color_id,scale_id],"inputs":[],"graph":{"nodes":[{"id":"c","op":"constant","type":"vec4","value":[1,1,1,1]},{"id":"s","op":"constant","type":"vec3","value":[1,1,1]}],"outputs":{color_id:"c",scale_id:"s"}}}
	doc.stages.spawn = [{"id":"custom_init","module":"custom","parameters":{}}]
	check(V.validate(doc).errors.is_empty(),"custom connected writer satisfies initial values")
	compiled = await S.compile(doc)
	check(compiled.errors.is_empty(),"custom initial provider compiles")
	doc = base.duplicate(true)
	var detached: Dictionary = module(doc,"gravity").mm_graph.nodes.filter(func(n): return n.name == "Read_acceleration")[0]
	module(doc,"gravity").mm_graph.connections = module(doc,"gravity").mm_graph.connections.filter(func(c): return c.from != detached.name)
	check(not V.access(module(doc,"gravity")).reads.has(S.attribute_id(doc,"acceleration")),"loose Read does not satisfy data flow")
	print("MODULAR_STANDARD_VALIDATION ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
