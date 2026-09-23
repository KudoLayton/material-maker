extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)

func _initialize() -> void:
	var compiler := Compiler.new()
	var doc := Fixtures.basic()
	var result := compiler.compile(doc)
	check(result.errors.is_empty(), "basic compile " + str(result.errors))
	if result.effect == null:
		quit(1)
		return
	check(doc.version == 2 and doc.user_parameters.is_empty(), "new documents are v2 without Users")
	check(result.effect.format_version == 2, "compiled effects are v2")
	for rejected_version in [0, 1, 3]:
		var rejected := doc.duplicate(true)
		rejected.version = rejected_version
		check(not compiler.compile(rejected).errors.is_empty(), "reject document version " + str(rejected_version))
	var missing_version := doc.duplicate(true)
	missing_version.erase("version")
	check(not compiler.compile(missing_version).errors.is_empty(), "reject missing document version")
	check(not MMParticleEffect.new().validation_error().is_empty(), "unversioned runtime resource is invalid")
	for rejected_version in [0, 1, 3]:
		var rejected_effect = result.effect.duplicate()
		rejected_effect.format_version = rejected_version
		check(not rejected_effect.validation_error().is_empty(), "reject runtime version " + str(rejected_version))
	var saved_path := "user://latest_effect.res"
	check(ResourceSaver.save(result.effect, saved_path) == OK, "save latest effect")
	var reloaded = ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded != null and reloaded.format_version == 2 and reloaded.validation_error().is_empty(), "v2 survives binary serialization with invalid default")
	check(result.effect.validation_error().is_empty(), "effect hash/layout")
	check(not "@" in result.effect.compute_source, "all kernel placeholders resolved")
	check(result.effect.compute_source.contains("s.a0 = out_a0"), "module output commits")
	for i in 33:
		doc.attributes.append({"id":"user"+str(i),"name":"Field "+str(i),"type":"vec4","default":[1.0,2.0,3.0,4.0]})
	doc.attributes.append({"id":"large_int","name":"Large Integer","type":"uint","default":4294967295})
	result = compiler.compile(doc)
	check(result.errors.is_empty(), "33 custom vec4 and exact uint " + str(result.errors))
	check(result.effect.component_count == 158, "SoA component count")
	check(result.effect.compute_source.contains("4294967295u"), "no integer float conversion")
	var before: String = result.effect.source_hash
	doc.attributes[0].name = "Renamed field"
	check(compiler.compile(doc).effect.source_hash == before, "rename preserves stable IDs/code")
	doc.stages.spawn.append({"id":"spawn2","module":"initialize","parameters":{"speed":4.0}})
	result = compiler.compile(doc)
	check(result.effect.parameters.size() == 2, "scoped repeated module parameters")
	check(result.effect.parameters[0].id != result.effect.parameters[1].id, "parameter scope")
	doc.stages.spawn[1].enabled = false
	check(compiler.compile(doc).effect.parameters.size() == 1, "disabled modules excluded")
	var invalid := doc.duplicate(true)
	invalid.stages.update.append({"id":"bad_stage","module":"initialize"})
	check(not compiler.compile(invalid).errors.is_empty(), "stage violation")
	invalid = doc.duplicate(true)
	invalid.attributes.append(invalid.attributes[0])
	check(not compiler.compile(invalid).errors.is_empty(), "duplicate attribute")
	invalid = doc.duplicate(true)
	invalid.modules.integrate.graph.nodes[0] = {"id":"position","op":"add","args":["result","result"]}
	check(not compiler.compile(invalid).errors.is_empty(), "cycle detection")
	invalid = doc.duplicate(true)
	invalid.modules.initialize.graph.nodes[0].value = [1.0,2.0]
	check(not compiler.compile(invalid).errors.is_empty(), "bad default")
	invalid = doc.duplicate(true)
	invalid.modules.initialize.graph.outputs = {"age":"speed"}
	invalid.modules.initialize.writes = ["age"]
	check(not compiler.compile(invalid).errors.is_empty(), "readonly Age")
	invalid = doc.duplicate(true)
	invalid.modules.integrate.graph.nodes[0].attribute = "unknown"
	check(not compiler.compile(invalid).errors.is_empty(), "missing attribute")
	invalid = doc.duplicate(true)
	invalid.modules.initialize.graph.nodes[2].op = "unsupported_texture_bake"
	var diagnostic: Dictionary = compiler.compile(invalid).errors[0]
	check(diagnostic.stage == "spawn" and diagnostic.module == "spawn1" and diagnostic.node == "velocity", "located unsupported-node error")
	invalid = doc.duplicate(true)
	invalid.modules.initialize.graph.outputs = {"velocity":"speed"}
	check(not compiler.compile(invalid).errors.is_empty(), "output type mismatch")
	var sequential := Fixtures.basic()
	sequential.modules.integrate.graph.steps = [{"outputs":{"position":"result"}}]
	var sequential_result := compiler.compile(sequential)
	check(sequential_result.errors.is_empty(), "sequential write steps compile")
	check(sequential_result.effect.compute_source.count("s.a0 = out_a0;") == 2, "explicit write plus final output")
	var ordered := Fixtures.basic()
	ordered.stages.update.append({"id":"update2","module":"integrate"})
	var first_hash: String = compiler.compile(ordered).effect.source_hash
	ordered.stages.update.reverse()
	check(compiler.compile(ordered).effect.source_hash != first_hash, "stack ordering affects emitted execution")
	var token_collision := Fixtures.basic()
	token_collision.attributes = [{"id":"FUNCTIONS","name":"Functions","type":"float","default":0.0},{"id":"Position","name":"Other position","type":"vec3","default":[0.0,0.0,0.0]}]
	var safe := compiler.compile(token_collision)
	check(safe.errors.is_empty() and not safe.effect.compute_source.contains("\ns.a25\n") and safe.effect.compute_source.contains("instances[target+row*4u+3u]=s.a0[row]"),"user IDs cannot replace kernel tokens")
	print("MODULAR_COMPILER ", "PASS" if failures == 0 else "FAIL", " checks=",checks)
	quit(0 if failures == 0 else 1)
