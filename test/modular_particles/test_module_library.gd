extends Node
const D = preload("res://addons/material_maker/particles/modular/document.gd")
const L = preload("res://addons/material_maker/particles/modular/module_library.gd")
const Library = preload("res://material_maker/panels/modular_particles/library.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func fixture() -> Dictionary:
	var module := Library.definition("Same Name",["update"],[{"id":"template_acc","name":"Acceleration","type":"vec3"}])
	module.reads = ["template_acc"]
	module.inputs = [{"id":"template_acc","name":"Acceleration","type":"vec3","default":[1,2,3]}]
	module.standard_module = {"catalog_id":"gravity","revision":1,"bindings":{"mm.standard.v1.acceleration":"template_acc"}}
	module.mm_graph.nodes.append(Library.binding("Input","module_parameter","template_acc","vec3"))
	module.mm_graph.nodes.append({"type":"graph","name":"Nested","nodes":[Library.binding("Read","module_read","template_acc","vec3"),{"type":"particle_node","settings":{"kind":"custom","code":"// template_acc"}}],"connections":[]})
	var data: Dictionary = module.mm_graph.duplicate(true)
	module.erase("mm_graph")
	data.particle_module = {"version":1,"id":"test_module","definition":module,"attributes":[{"id":"template_acc","name":"Acceleration","type":"vec3","default":[0,0,0],"standard_role":"mm.standard.v1.acceleration"}]}
	return data
func run() -> void:
	var doc := D.create()
	doc.attributes = [{"id":"template_acc","name":"Acceleration","type":"float","default":42}]
	var original := doc.duplicate(true)
	var data := fixture()
	var source := data.duplicate(true)
	var added := L.insert(doc,data,"update")
	check(added.ok,"standard insertion")
	check(doc == original and data == source,"pure caller/payload isolation")
	if added.ok:
		var next: Dictionary = added.document
		var id: String = next.attributes[1].id
		var module: Dictionary = next.modules[added.module_id]
		check(id != "template_acc" and next.attributes[0] == doc.attributes[0],"same name/ID user field not overwritten or bound")
		check(module.reads == [id] and module.writes == [id],"contracts remapped")
		check(module.mm_graph.nodes[0].settings.fields[0].id == id,"output field remapped")
		check(module.mm_graph.nodes[2].nodes[0].settings.id == id,"nested read remapped")
		check(module.mm_graph.nodes[1].settings.id == "template_acc" and module.inputs[0].id == "template_acc","input ID is not an Attribute ID")
		check(module.mm_graph.nodes[2].nodes[1].settings.code == "// template_acc","code not rewritten")
		check(module.standard_module.bindings["mm.standard.v1.acceleration"] == id,"metadata remapped")
		next.attributes[1].name = "사용자 이름"
		next.attributes[1].default = [9,8,7]
		var repeated := L.insert(next,data,"update",0)
		check(repeated.ok and repeated.document.attributes.size() == 2,"role reused across copies")
		check(repeated.document.attributes[1].name == "사용자 이름" and repeated.document.attributes[1].default == [9,8,7],"user name/default preserved")
		check(repeated.module_id != added.module_id and repeated.document.stages.update[0].id != repeated.document.stages.update[1].id,"fresh module and instance IDs")
		repeated.document.modules[repeated.module_id].name = "Changed"
		check(repeated.document.modules[added.module_id].name == "Same Name","independent definitions")
		var snapshot: Dictionary = module.mm_graph.duplicate(true)
		var definition := module.duplicate(true)
		definition.erase("mm_graph")
		snapshot.particle_module = {"version":1,"id":added.module_id,"definition":definition,"attributes":L.snapshots(next,module)}
		var imported := L.merge_payload(D.create(),snapshot)
		check(imported.ok and imported.document.attributes.size() == 1,"mmg carries required Attribute snapshot into fresh document")
		var revised := L.merge_payload(next,snapshot)
		check(revised.ok and revised.module_id == added.module_id and revised.document.attributes.size() == 2,"explicit revision import preserves ID and roles")
		check(revised.document.stages == next.stages,"revision does not alter instances")
		var invalid := next.duplicate(true)
		invalid.attributes[1].type = "float"
		invalid.attributes[1].default = 0
		check(not L.merge_payload(invalid,data).ok,"role type mismatch rejected")
		invalid = next.duplicate(true)
		var duplicate: Dictionary = invalid.attributes[1].duplicate(true)
		duplicate.id = D.uid()
		invalid.attributes.append(duplicate)
		check(not L.merge_payload(invalid,data).ok,"ambiguous role rejected")
		check(L.snapshots(next,module).size() == 1,"only contract attributes exported")
	check(not L.insert(doc,data,"spawn").ok and doc == original,"wrong Stage rejected without mutation")
	var bad := data.duplicate(true)
	bad.particle_module.attributes.append(bad.particle_module.attributes[0].duplicate(true))
	check(not L.merge_payload(doc,bad).ok,"duplicate imported ID/role rejected")
	bad = data.duplicate(true)
	bad.particle_module.attributes = []
	check(not L.merge_payload(doc,bad).ok,"missing role snapshot rejected")
	bad = data.duplicate(true)
	bad.particle_module.attributes[0].id = "position"
	check(not L.merge_payload(doc,bad).ok,"built-in collision rejected")
	bad = data.duplicate(true)
	bad.particle_module.definition.erase("standard_module")
	bad.particle_module.attributes[0].erase("standard_role")
	check(not L.merge_payload(doc,bad).ok,"ordinary ID/type conflict rejected")
	bad.particle_module.attributes[0].type = "float"
	bad.particle_module.attributes[0].default = 0
	var ordinary := L.merge_payload(doc,bad)
	check(ordinary.ok and ordinary.document.attributes == doc.attributes,"ordinary matching ID/type preserves definition")
	var legacy: Dictionary = Library.defaults().initialize_velocity.duplicate(true)
	var legacy_graph: Dictionary = legacy.mm_graph
	legacy.erase("mm_graph")
	legacy_graph.particle_module = {"version":1,"id":"legacy","definition":legacy}
	check(L.merge_payload(D.create(),legacy_graph).ok,"legacy mmg without metadata supported")
	check(not L.merge_payload(doc,{}).ok and doc == original,"malformed payload atomic")
	print("MODULAR_MODULE_LIBRARY ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
