extends RefCounted
## Pure authoring operations. Never mutate the caller, bind by name, or load GPU resources.
const Document = preload("document.gd")
const ROOT := "res://material_maker/panels/modular_particles/standard/"
const ROLES := {
	"mm.standard.v1.acceleration":{"name":"Acceleration","type":"vec3","default":[0.0,0.0,0.0]},
	"mm.standard.v1.drag":{"name":"Drag","type":"float","default":0.0},
	"mm.standard.v1.initial_color":{"name":"InitialColor","type":"vec4","default":[1.0,1.0,1.0,1.0]},
	"mm.standard.v1.initial_scale":{"name":"InitialScale","type":"vec3","default":[1.0,1.0,1.0]}}

static func catalog() -> Array:
	return Document.load_file(ROOT + "catalog.json").get("modules",[])

static func payload(catalog_id: String) -> Dictionary:
	for entry in catalog():
		if entry.id == catalog_id: return Document.load_file(ROOT + entry.file)
	return {}

static func snapshots(document: Dictionary, module: Dictionary) -> Array:
	var result: Array = []
	for attribute in document.attributes:
		if attribute.id in module.reads or attribute.id in module.writes: result.append(attribute.duplicate(true))
	return result

static func failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

static func attribute_error(attribute: Dictionary) -> String:
	if not Document.identifier(attribute.get("id")) or not attribute.get("name") is String or not Document.valid_value(attribute.get("type",""),attribute.get("default")):
		return "Malformed Attribute snapshot"
	if Document.BUILTINS.any(func(a): return a.id == attribute.id): return "Custom Attribute collides with built-in ID: " + attribute.id
	if attribute.has("standard_role"):
		var role = attribute.standard_role
		if not role is String or not ROLES.has(role): return "Unknown standard Attribute role"
		if attribute.type != ROLES[role].type: return "Standard Attribute type mismatch: " + role
	return ""

static func remap_graph(graph: Dictionary, ids: Dictionary) -> void:
	var settings: Dictionary = graph.get("settings",{})
	if graph.get("type") == "modular_particle":
		if settings.get("kind") == "module_read" and ids.has(settings.get("id")): settings.id = ids[settings.id]
		if settings.get("kind") == "module_output":
			for field in settings.get("fields",[]):
				if ids.has(field.get("id")): field.id = ids[field.id]
	# Module input IDs, node names, connection indices and code strings are NOT Attribute IDs.
	for child in graph.get("nodes",[]):
		if child is Dictionary: remap_graph(child,ids)

static func merge_payload(document: Dictionary, data: Dictionary, independent: bool = false) -> Dictionary:
	var metadata = data.get("particle_module",{})
	if not metadata is Dictionary or metadata.get("version") != 1 or not Document.identifier(metadata.get("id")) or not metadata.get("definition") is Dictionary:
		return failure("Not a version 1 particle module")
	if data.get("type") != "graph" or not data.get("nodes") is Array or not data.get("connections") is Array:
		return failure("Missing module graph")
	var module: Dictionary = metadata.definition.duplicate(true)
	for key in ["stages","inputs","reads","writes"]:
		if not module.get(key) is Array: return failure("Malformed module " + key)
	if not metadata.get("attributes",[]) is Array: return failure("Malformed Attribute snapshots")
	var result := document.duplicate(true)
	var by_id := {}
	var by_role := {}
	for attribute in result.attributes:
		var problem := attribute_error(attribute)
		if not problem.is_empty(): return failure(problem)
		if by_id.has(attribute.id): return failure("Duplicate Attribute ID: " + attribute.id)
		by_id[attribute.id] = attribute
		if attribute.has("standard_role"):
			if by_role.has(attribute.standard_role): return failure("Duplicate standard Attribute role: " + attribute.standard_role)
			by_role[attribute.standard_role] = attribute
	var mapping := {}
	var incoming_roles := {}
	var added: Array = []
	for raw in metadata.get("attributes",[]):
		if not raw is Dictionary: return failure("Malformed Attribute snapshot")
		var attribute: Dictionary = raw.duplicate(true)
		var problem := attribute_error(attribute)
		if not problem.is_empty(): return failure(problem)
		var old_id: String = attribute.id
		if mapping.has(old_id): return failure("Duplicate imported Attribute ID: " + old_id)
		if attribute.has("standard_role"):
			var role: String = attribute.standard_role
			if incoming_roles.has(role): return failure("Duplicate imported standard Attribute role: " + role)
			incoming_roles[role] = old_id
			if by_role.has(role):
				mapping[old_id] = by_role[role].id
				continue
			# Allocate on first use, even without an ID collision. The template ID is not the document ID.
			attribute.id = Document.uid()
		elif by_id.has(old_id):
			if by_id[old_id].type != attribute.type: return failure("Attribute type mismatch: " + old_id)
			mapping[old_id] = old_id
			continue
		mapping[old_id] = attribute.id
		result.attributes.append(attribute)
		added.append(attribute.duplicate(true))
		by_id[attribute.id] = attribute
		if attribute.has("standard_role"): by_role[attribute.standard_role] = attribute
	if module.has("standard_module"):
		var standard = module.standard_module
		if not standard is Dictionary or not standard.get("catalog_id") is String or standard.get("revision") != 1 or not standard.get("bindings") is Dictionary:
			return failure("Malformed standard module metadata")
		for role in standard.bindings:
			var source_id = standard.bindings[role]
			if not incoming_roles.has(role) or incoming_roles[role] != source_id:
				return failure("Missing standard Attribute snapshot: " + str(role))
			standard.bindings[role] = mapping[source_id]
	module.mm_graph = data.duplicate(true)
	module.mm_graph.erase("particle_module")
	remap_graph(module.mm_graph,mapping)
	for key in ["reads","writes"]:
		for index in module[key].size():
			var id = module[key][index]
			if mapping.has(id): module[key][index] = mapping[id]
	var module_id: String = Document.uid() if independent else metadata.id
	result.modules[module_id] = module
	var shape := Document.shape_error(result)
	if not shape.is_empty(): return failure(shape)
	return {"ok":true,"error":"","document":result,"module_id":module_id,"added_attributes":added}

static func insert(document: Dictionary, data: Dictionary, stage: String, after: int = -1) -> Dictionary:
	if stage not in ["spawn","update"]: return failure("Unknown Stage")
	var merged := merge_payload(document,data,true)
	if not merged.ok: return merged
	var module: Dictionary = merged.document.modules[merged.module_id]
	if stage not in module.stages: return failure("Module not allowed in " + stage)
	var stack: Array = merged.document.stages[stage]
	var index := mini(after+1,stack.size()) if after >= 0 else stack.size()
	stack.insert(index,{"id":Document.uid(),"module":merged.module_id,"parameters":{},"enabled":true})
	merged["selected"] = index
	return merged
