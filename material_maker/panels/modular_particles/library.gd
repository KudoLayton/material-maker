extends RefCounted
const Document = preload("res://addons/material_maker/particles/modular/document.gd")

static func binding(name: String, kind: String, id: String, type: String, position := Vector2.ZERO) -> Dictionary:
	return {"name":name,"type":"modular_particle","parameters":{},"settings":{"kind":kind,"id":id,"data_type":type,"label":id},"node_position":{"x":position.x,"y":position.y}}

static func sink(fields: Array) -> Dictionary:
	return {"name":"Output","type":"modular_particle","parameters":{},"settings":{"kind":"module_output","fields":fields},"node_position":{"x":650.0,"y":0.0}}

static func connect_nodes(from: String, to: String, to_port: int, from_port: int = 0) -> Dictionary:
	return {"from":from,"from_port":from_port,"to":to,"to_port":to_port}

static func definition(label: String, stages: Array, fields: Array) -> Dictionary:
	return {"name":label,"stages":stages,"inputs":[],"reads":[],"writes":fields.map(func(field): return field.id),"revision":1,"mm_graph":{"type":"graph","name":"Module","nodes":[sink(fields)],"connections":[]}}

static func defaults() -> Dictionary:
	var initialize := definition("Initialize Velocity",["spawn"],[{"id":"velocity","name":"Velocity","type":"vec3"}])
	initialize.inputs = [{"id":"velocity","name":"Velocity","type":"vec3","default":[0.0,1.0,0.0]}]
	initialize.mm_graph.nodes.append(binding("Velocity","module_parameter","velocity","vec3"))
	initialize.mm_graph.connections.append(connect_nodes("Velocity","Output",0))
	var integrate := definition("Integrate Velocity",["update"],[{"id":"position","name":"Position","type":"vec3"}])
	integrate.reads = ["position","velocity"]
	integrate.mm_graph.nodes.append_array([
		binding("Position","module_read","position","vec3",Vector2(-500,-200)),
		binding("Velocity","module_read","velocity","vec3",Vector2(-500,0)),
		binding("Delta","module_context","delta","float",Vector2(-500,200)),
		{"name":"Multiply","type":"math_v3","parameters":{"op":2.0,"clamp":false},"node_position":{"x":-150.0,"y":0.0}},
		{"name":"Add","type":"math_v3","parameters":{"op":0.0,"clamp":false},"node_position":{"x":200.0,"y":0.0}}
	])
	integrate.mm_graph.connections = [connect_nodes("Velocity","Multiply",0),connect_nodes("Delta","Multiply",1),connect_nodes("Position","Add",0),connect_nodes("Multiply","Add",1),connect_nodes("Add","Output",0)]
	return {"initialize_velocity":initialize,"integrate_velocity":integrate}

static func new_document() -> Dictionary:
	var data := Document.create()
	data.modules = defaults()
	data.stages.spawn = [{"id":Document.uid(),"module":"initialize_velocity","parameters":{},"enabled":true}]
	data.stages.update = [{"id":Document.uid(),"module":"integrate_velocity","parameters":{},"enabled":true}]
	return data

static func input_reference(graph: Dictionary, input_id: String, parent_path: String = "") -> String:
	# Inspect every binding, not just connected/reachable shader nodes. A loose
	# or nested Read must remain valid if the user connects it later.
	var label: String = str(graph.get("name",graph.get("id","Graph")))
	var path := label if parent_path.is_empty() else parent_path + "/" + label
	var settings: Dictionary = graph.get("settings",{})
	if graph.get("type") == "modular_particle" and settings.get("kind") == "module_parameter" and settings.get("id") == input_id:
		return path
	if graph.get("op") == "parameter" and graph.get("parameter") == input_id:
		return path
	for child in graph.get("nodes",[]):
		if child is Dictionary:
			var reference := input_reference(child,input_id,path)
			if not reference.is_empty(): return reference
	return ""

static func contracts(graph: Dictionary) -> Dictionary:
	var reads: Array = []
	var writes: Array = []
	var visit: Callable
	visit = func(node: Dictionary, recurse: Callable):
		var settings: Dictionary = node.get("settings", {})
		if node.get("type") == "modular_particle":
			if settings.get("kind") == "module_read" and settings.id not in reads: reads.append(settings.id)
			if settings.get("kind") == "module_output":
				for field in settings.fields:
					if field.id not in writes: writes.append(field.id)
		for child in node.get("nodes", []): recurse.call(child,recurse)
	visit.call(graph,visit)
	return {"reads":reads,"writes":writes}
