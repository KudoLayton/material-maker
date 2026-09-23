extends RefCounted
## Pure authoring operations. Stable IDs connect effect inputs to module instances.
## No UI, runtime state or implicit name-based reconnection.
const Document = preload("document.gd")

static func valid_name(value) -> bool:
	if not value is String or value.is_empty(): return false
	if not value[0] in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_": return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_": return false
	return true

static func definition(document: Dictionary, id: String) -> Dictionary:
	var matches: Array = document.get("user_parameters",[]).filter(func(p): return p.id == id)
	return matches[0] if matches.size() == 1 else {}

static func instance(document: Dictionary, id: String) -> Dictionary:
	var matches: Array = []
	for stage in ["spawn","update"]:
		matches.append_array(document.stages[stage].filter(func(item): return item.id == id))
	return matches[0] if matches.size() == 1 else {}

static func input(document: Dictionary, item: Dictionary, id: String) -> Dictionary:
	var matches: Array = document.modules.get(item.get("module",""),{}).get("inputs",[]).filter(func(p): return p.id == id)
	return matches[0] if matches.size() == 1 else {}

static func definition_error(parameter: Dictionary) -> String:
	if not Document.identifier(parameter.get("id")): return "Invalid User ID"
	if not valid_name(parameter.get("name")): return "User name must match [A-Za-z_][A-Za-z0-9_]*"
	if not parameter.get("type") is String or not Document.valid_value(parameter.type,parameter.get("default")): return "Invalid User type/default: User."+parameter.name
	return ""

static func validation_error(document: Dictionary) -> String:
	var shape := Document.shape_error(document)
	if not shape.is_empty(): return shape
	var ids := {}
	var names := {}
	for parameter in document.get("user_parameters",[]):
		var error := definition_error(parameter)
		if not error.is_empty(): return error
		if ids.has(parameter.id): return "Duplicate User ID: "+parameter.id
		if names.has(parameter.name): return "Duplicate User name: User."+parameter.name
		ids[parameter.id] = parameter
		names[parameter.name] = true
	for stage in ["spawn","update"]:
		for item in document.stages[stage]:
			for id in item.get("input_bindings",{}):
				var key: String = stage+"/"+item.id+"/"+id
				var parameter := input(document,item,id)
				if parameter.is_empty(): return "Missing/ambiguous bound Module Input: "+key
				var user_id: String = item.input_bindings[id].id
				if not ids.has(user_id): return "Missing User parameter "+user_id+" for "+key
				if ids[user_id].type != parameter.type: return "User binding type mismatch: "+key
				if not Document.valid_value(parameter.type,item.get("parameters",{}).get(id,parameter.default)): return "Invalid preserved constant: "+key
	return ""

static func references(document: Dictionary, user_id: String) -> Array:
	var found: Array = []
	for stage in ["spawn","update"]:
		for item in document.stages[stage]:
			for input_id in item.get("input_bindings",{}):
				if item.input_bindings[input_id].id != user_id: continue
				var module: Dictionary = document.modules.get(item.module,{})
				var parameter := input(document,item,input_id)
				found.append({"stage":stage,"instance_id":item.id,"module_id":item.module,"module_name":module.get("name",item.module),"input_id":input_id,"input_name":parameter.get("name",input_id),"enabled":item.get("enabled",true)})
	return found

static func reference_text(document: Dictionary, user_id: String) -> String:
	var lines := PackedStringArray()
	for ref in references(document,user_id):
		lines.append("%s / %s [%s] / Module.%s%s" % [ref.stage,ref.module_name,ref.instance_id,ref.input_name," (disabled)" if not ref.enabled else ""])
	return "\n".join(lines)

static func failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}

static func success(document: Dictionary) -> Dictionary:
	var shape := Document.shape_error(document)
	return {"ok":true,"error":"","document":document} if shape.is_empty() else failure(shape)

static func add(document: Dictionary, name: String, type: String, value) -> Dictionary:
	var parameter := {"id":Document.uid(),"name":name.strip_edges(),"type":type,"default":value.duplicate(true) if value is Array else value}
	var error := definition_error(parameter)
	if not error.is_empty(): return failure(error)
	if document.get("user_parameters",[]).any(func(p): return p.name == parameter.name): return failure("Duplicate User name: User."+parameter.name)
	var result := document.duplicate(true)
	result.version = 2
	if not result.has("user_parameters"): result.user_parameters = []
	result.user_parameters.append(parameter)
	var outcome := success(result)
	outcome["user_id"] = parameter.id
	return outcome

static func change(document: Dictionary, id: String, changes: Dictionary) -> Dictionary:
	var original := definition(document,id)
	if original.is_empty(): return failure("Missing/ambiguous User parameter: "+id)
	for key in changes:
		if key not in ["name","type","default"]: return failure("Cannot change User field: "+str(key))
	var updated := original.duplicate(true)
	updated.merge(changes.duplicate(true),true)
	if updated.get("name") is String: updated.name = updated.name.strip_edges()
	var error := definition_error(updated)
	if not error.is_empty(): return failure(error)
	if document.user_parameters.any(func(p): return p.id != id and p.name == updated.name): return failure("Duplicate User name: User."+updated.name)
	if updated.type != original.type and not references(document,id).is_empty(): return failure("User type is in use:\n"+reference_text(document,id))
	var result := document.duplicate(true)
	definition(result,id).merge(updated,true)
	return success(result)

static func remove(document: Dictionary, id: String) -> Dictionary:
	if definition(document,id).is_empty(): return failure("Missing/ambiguous User parameter: "+id)
	if not references(document,id).is_empty(): return failure("User parameter is in use:\n"+reference_text(document,id))
	var result := document.duplicate(true)
	result.user_parameters = result.user_parameters.filter(func(p): return p.id != id)
	return success(result)

static func bind(document: Dictionary, instance_id: String, input_id: String, user_id: String) -> Dictionary:
	var item := instance(document,instance_id)
	var parameter := input(document,item,input_id)
	var user := definition(document,user_id)
	if item.is_empty() or parameter.is_empty(): return failure("Missing/ambiguous Module Input")
	if user.is_empty(): return failure("Missing/ambiguous User parameter")
	var error := definition_error(user)
	if not error.is_empty(): return failure(error)
	if parameter.type != user.type: return failure("User binding requires exactly matching types")
	if not Document.valid_value(parameter.type,item.get("parameters",{}).get(input_id,parameter.default)): return failure("Invalid preserved constant")
	var result := document.duplicate(true)
	var target := instance(result,instance_id)
	if not target.has("input_bindings"): target.input_bindings = {}
	target.input_bindings[input_id] = {"kind":"user","id":user_id}
	return success(result)

static func unbind(document: Dictionary, instance_id: String, input_id: String) -> Dictionary:
	var item := instance(document,instance_id)
	if item.is_empty() or not item.get("input_bindings",{}).has(input_id): return failure("Input has no User binding")
	var result := document.duplicate(true)
	var target := instance(result,instance_id)
	target.input_bindings.erase(input_id)
	if target.input_bindings.is_empty(): target.erase("input_bindings")
	# Allow repairing one Missing reference while other compiler errors remain.
	return success(result)
