extends SceneTree
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Users = preload("res://addons/material_maker/particles/modular/user_parameters.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Library = preload("res://addons/material_maker/particles/modular/module_library.gd")
const Fixtures = preload("fixtures.gd")
const Codec = preload("res://addons/mm_gpu_particles/value_codec.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func _initialize() -> void: run.call_deferred()

func errors(document: Dictionary) -> bool:
	var result := Compiler.new().compile(document)
	return result.effect == null and not result.errors.is_empty()

func payload(document: Dictionary) -> Dictionary:
	return {"type":"graph","nodes":[],"connections":[],"particle_module":{"version":1,"id":"initialize","definition":document.modules.initialize.duplicate(true),"attributes":[]}}

func run() -> void:
	var legacy := Fixtures.basic()
	var untouched := legacy.duplicate(true)
	var original := Compiler.new().compile(legacy)
	check(original.errors.is_empty() and original.effect.format_version == 2,"v2 compilation without Users")
	check(legacy == untouched and legacy.user_parameters.is_empty(),"v2 validation/compilation is nonmutating")
	var unsupported := legacy.duplicate(true)
	unsupported.version = 1
	check(not Users.add(unsupported,"Speed","float",1.0).ok and unsupported.version == 1,"adding User never upgrades unsupported documents")
	check(Document.save_file("user://latest.mpfx",legacy) == OK,"save v2")
	var restored := Document.load_file("user://latest.mpfx")
	# JSON parses every number as float; compare normalized documents and GPU semantics.
	check(restored == JSON.parse_string(JSON.stringify(legacy)) and restored.user_parameters.is_empty(),"v2 roundtrip unchanged")
	check(Compiler.new().compile(restored).effect.source_hash == original.effect.source_hash,"JSON numeric representation preserves shader")
	check(not Users.add(legacy,"Bad Name","float",1).ok,"invalid identifier rejected")
	check(not Users.add(legacy,"Speed","uint",-1).ok,"invalid default rejected")
	check(legacy == untouched,"failed adds unchanged")
	var added := Users.add(legacy,"Speed","float",3.0)
	check(added.ok and added.document.version == 2,"first User preserves v2")
	var doc: Dictionary = added.document
	var id: String = added.user_id
	check(Document.identifier(id) and id.length() == 32,"stable UUID allocated")
	check(doc.stages.spawn[0].get("input_bindings",{}).is_empty(),"matching Module/User names do not bind automatically")
	check(not Users.add(doc,"Speed","float",1).ok,"duplicate name rejected")
	check(Users.add(doc,"speed","float",1).ok,"names are case-sensitive")
	for label in ["Wind","_value","value1","3value","User.Wind","a/b","a b","바람",""]:
		check(Users.valid_name(label) == MMParticleEffect.valid_user_name(label),"authoring/runtime name parity: "+label)
	doc.stages.spawn[0].parameters.speed = 9.0
	var before := doc.duplicate(true)
	var bound := Users.bind(doc,"spawn1","speed",id)
	check(bound.ok and doc == before,"binding is pure")
	doc = bound.document
	check(doc.stages.spawn[0].parameters.speed == 9.0,"binding preserves constant")
	check(Users.references(doc,id).size() == 1,"reference enumeration")
	var compiled := Compiler.new().compile(doc)
	check(compiled.errors.is_empty() and compiled.effect.format_version == 2,"v2 compiled")
	check(compiled.effect.parameter("spawn1/speed").user_id == id and compiled.effect.parameter("spawn1/speed").default == 3.0,"runtime binding and effective default")
	check(compiled.effect.compute_source == original.effect.compute_source,"binding does not change GLSL or GPU slots")
	check(compiled.effect.parameters.map(func(p): return [p.id,p.type,p.offset]) == original.effect.parameters.map(func(p): return [p.id,p.type,p.offset]),"ABI unchanged")
	check(compiled.effect.user_parameters == doc.user_parameters,"User metadata exported")
	check(ResourceSaver.save(compiled.effect,"user://user_effect.tres") == OK,"save v2 runtime resource")
	var loaded: MMParticleEffect = load("user://user_effect.tres")
	check(loaded.validation_error().is_empty() and loaded.parameter("spawn1/speed").user_id == id,"resource metadata roundtrip")
	check(Document.save_file("user://v2.mpfx",doc) == OK,"save v2 authoring")
	var roundtrip := Document.load_file("user://v2.mpfx")
	check(Users.validation_error(roundtrip).is_empty() and roundtrip.stages.spawn[0].input_bindings.speed.id == id,"v2 JSON stable binding roundtrip")
	check(not Users.remove(doc,id).ok,"used deletion blocked")
	check(not Users.change(doc,id,{"type":"vec3","default":[0,0,0]}).ok,"used type change blocked")
	var renamed := Users.change(doc,id,{"name":"Velocity"})
	check(renamed.ok and renamed.document.user_parameters[0].id == id and renamed.document.stages.spawn[0].input_bindings.speed.id == id,"rename preserves identity")
	var changed := Users.change(doc,id,{"default":5.0})
	check(changed.ok and Compiler.new().compile(changed.document).effect.parameter("spawn1/speed").default == 5.0,"default update compiles")
	check(not Users.change(doc,id,{"id":"new"}).ok,"identity cannot be edited")
	doc.stages.spawn[0].enabled = false
	check(not Users.remove(doc,id).ok and Users.reference_text(doc,id).contains("disabled"),"disabled use still blocks removal")
	var broken := doc.duplicate(true)
	broken.stages.spawn[0].input_bindings.speed.id = "missing"
	check(Document.shape_error(broken).is_empty() and errors(broken),"Missing reference loads but is a hard compile error even when disabled")
	check(Users.unbind(broken,"spawn1","speed").ok,"Missing reference can be repaired")
	doc.stages.spawn[0].enabled = true
	var copy: Dictionary = doc.stages.spawn[0].duplicate(true)
	copy.id = "spawn_copy"
	doc.stages.spawn.append(copy)
	check(Users.references(doc,id).size() == 2,"copied instance retains shared User")
	var many := Compiler.new().compile(doc)
	check(many.errors.is_empty() and many.effect.parameters.all(func(p): return p.user_id == id),"multiple module instances export same User ID")
	var bytes := Codec.pack(many.effect,{},Transform3D.IDENTITY,false,{id:7.0})
	check(many.effect.parameters.all(func(p): return bytes.decode_float(p.offset*4) == 7.0),"single User expands to every bound input slot")
	var unbound := Users.unbind(doc,"spawn1","speed")
	check(unbound.ok and unbound.document.stages.spawn[0].parameters.speed == 9.0,"unbind restores preserved constant")
	check(not unbound.document.stages.spawn[0].has("input_bindings"),"empty binding object omitted")
	var partial := Compiler.new().compile(unbound.document)
	check(partial.effect.parameter("spawn1/speed").default == 9.0 and not partial.effect.parameter("spawn1/speed").has("user_id"),"unbound compile uses literal")
	unbound = Users.unbind(unbound.document,"spawn_copy","speed")
	var resized := Users.change(unbound.document,id,{"type":"vec3","default":[0,1,0]})
	check(resized.ok,"unused type change with valid new default")
	check(not Users.bind(resized.document,"spawn1","speed",id).ok,"binding type must match exactly")
	var removed := Users.remove(unbound.document,id)
	check(removed.ok and removed.document.version == 2 and removed.document.user_parameters.is_empty(),"last deletion does not downgrade format")
	check(legacy == untouched,"all pure actions preserve original document")
	var bad := doc.duplicate(true)
	bad.version = 1
	check(not Document.shape_error(bad).is_empty() and errors(bad),"v1 cannot silently carry User data")
	bad = doc.duplicate(true)
	bad.user_parameters.append(bad.user_parameters[0].duplicate(true))
	check(errors(bad),"duplicate IDs rejected")
	bad = doc.duplicate(true)
	var duplicate: Dictionary = bad.user_parameters[0].duplicate(true)
	duplicate.id = "another_id"
	bad.user_parameters.append(duplicate)
	check(errors(bad),"duplicate names rejected")
	for malformed in [["default",NAN],["default","wrong"],["type","texture"],["name","User.Nested"]]:
		bad = doc.duplicate(true)
		bad.user_parameters[0][malformed[0]] = malformed[1]
		check(errors(bad),"bad definition rejected: "+str(malformed))
	bad = doc.duplicate(true)
	bad.stages.spawn[0].input_bindings.unknown = {"kind":"user","id":id}
	check(errors(bad),"unknown input rejected")
	bad = doc.duplicate(true)
	bad.stages.spawn[0].input_bindings.speed.kind = "attribute"
	check(not Document.shape_error(bad).is_empty(),"no implicit Attribute source")
	bad = doc.duplicate(true)
	bad.user_parameters[0].type = "uint"
	bad.user_parameters[0].default = 3
	check(errors(bad),"float/uint binding mismatch rejected")
	var incoming := payload(doc)
	check(not JSON.stringify(incoming).contains("user_parameters") and not JSON.stringify(incoming).contains("input_bindings"),"mmg snapshot independent of effect User state")
	var merged := Library.merge_payload(doc,incoming)
	check(merged.ok and merged.document.stages.spawn[0].input_bindings.speed.id == id,"compatible revision retains bindings")
	var immutable := doc.duplicate(true)
	incoming.particle_module.definition.inputs = []
	check(not Library.merge_payload(doc,incoming).ok and doc == immutable,"removed bound input revision rejected atomically")
	incoming = payload(doc)
	incoming.particle_module.definition.inputs[0].type = "vec3"
	incoming.particle_module.definition.inputs[0].default = [0,0,0]
	check(not Library.merge_payload(doc,incoming).ok and doc == immutable,"changed bound type revision rejected atomically")
	incoming = payload(doc)
	incoming.particle_module.definition.inputs[0].name = "Renamed Input"
	check(Library.merge_payload(doc,incoming).ok,"input display rename compatible")
	print("MODULAR_USER_MODEL ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
