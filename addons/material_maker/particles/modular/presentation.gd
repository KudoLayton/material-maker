extends RefCounted
## Display-only metadata. Never write qualified labels back into authoring data.
const Document = preload("document.gd")
const CONTEXT := {"delta":"float","time":"float","just_spawned":"bool","seed":"uint","index":"uint"}
const RENDERER := {"position":"Position","rotation":"Rotation","scale":"Scale","color":"Color"}

static func is_builtin(id: String) -> bool:
	return Document.BUILTINS.any(func(field): return field.id == id)

static func context(document: Dictionary, module_id: String, live_graph: Dictionary = {}) -> Dictionary:
	var module: Dictionary = document.get("modules",{}).get(module_id,{})
	var graph: Dictionary = live_graph if not live_graph.is_empty() else module.get("mm_graph",{})
	var outputs := {}
	for node in graph.get("nodes",[]):
		if node.get("type") != "modular_particle" or node.get("settings",{}).get("kind") != "module_output": continue
		var fields: Array = node.settings.get("fields",[])
		for port in fields.size():
			var id: String = fields[port].id
			var connected: bool = graph.get("connections",[]).any(func(c): return c.get("to") == node.name and c.get("to_port") == port)
			outputs[id] = connected or outputs.get(id,false)
	return {"known":true,"attributes":Document.BUILTINS.duplicate(true) + document.get("attributes",[]).duplicate(true),
		"inputs":module.get("inputs",[]).duplicate(true),"renderer":document.get("renderer",{}).duplicate(true),
		"outputs":outputs,"output_known":not graph.is_empty()}

static func id_badge(id: String, raw_name: String, peers: Array) -> String:
	var duplicates: Array = peers.filter(func(p): return str(p.get("name",p.id)) == raw_name)
	if duplicates.size() < 2: return ""
	var length := mini(8,id.length())
	while length < id.length() and duplicates.any(func(p): return p.id != id and str(p.id).left(length) == id.left(length)):
		length += 1
	return "[#" + id.left(length) + "]"

static func describe(kind: String, id: String, fallback_name: String = "", fallback_type: String = "", ctx: Dictionary = {}) -> Dictionary:
	var known: bool = ctx.get("known",false)
	var scope_name := ""
	var origin := ""
	var role := "Read"
	var peers: Array = []
	if kind == "module_parameter":
		scope_name = "Module"
		origin = "Module input (shared per module instance)"
		role = "Input / Read"
		peers = ctx.get("inputs",[])
	elif kind == "module_context":
		scope_name = "Context"
		origin = "Simulation context"
		for key in CONTEXT: peers.append({"id":key,"name":key,"type":CONTEXT[key],"readonly":true})
		known = true
	else:
		var builtin := is_builtin(id)
		scope_name = "Particle" if builtin else "Particle.Custom"
		origin = "Built-in particle attribute" if builtin else "User-defined particle attribute"
		if kind == "module_output": role = "Write"
		var attributes: Array = ctx.get("attributes",Document.BUILTINS)
		peers = attributes.filter(func(p): return is_builtin(p.id) == builtin)
	var matches: Array = peers.filter(func(p): return p.id == id)
	var found := not matches.is_empty()
	var definition: Dictionary = matches[0] if found else {}
	var raw_name: String = str(definition.get("name",id)) if found else (fallback_name if not fallback_name.is_empty() else id)
	var type: String = definition.get("type",fallback_type)
	var missing := known and not found
	var badge := id_badge(id,raw_name,peers) if found else ""
	var qualified := scope_name + "." + raw_name
	var display := qualified + (" " + badge if not badge.is_empty() else "")
	if missing: display += " [Missing: " + id + "]"
	var renderer := "Not bound"
	var output := "Not applicable"
	if scope_name.begins_with("Particle"):
		var bindings: Array[String] = []
		if found and is_builtin(id) and RENDERER.has(id): bindings.append(RENDERER[id])
		if known and found and id == ctx.get("renderer",{}).get("custom_attribute","custom"):
			bindings.append("INSTANCE_CUSTOM" if type == "vec4" else "Invalid INSTANCE_CUSTOM target (requires vec4)")
		if not bindings.is_empty(): renderer = ", ".join(bindings)
		elif not known: renderer = "Definition context unavailable"
		if ctx.get("output_known",false):
			output = "Not registered"
			if ctx.outputs.has(id): output = "Connected" if ctx.outputs[id] else "Unconnected — existing value preserved"
		else: output = "Module graph context unavailable"
	var readonly: bool = definition.get("readonly",false)
	var tooltip := display + " : " + type + "\n" + origin + "\nRole: " + role + "\nStable ID: " + id
	if readonly: tooltip += "\nRead-only"
	if not known: tooltip += "\nDefinition context unavailable; using saved label, not name-based binding"
	if missing: tooltip += "\nMissing definition; no automatic name-based reconnection"
	if scope_name.begins_with("Particle"): tooltip += "\nRenderer: " + renderer + "\nModule Output: " + output
	return {"namespace":scope_name,"raw_name":raw_name,"qualified":qualified,"display":display,"badge":badge,
		"id":id,"type":type,"kind":kind,"role":role,"origin":origin,"readonly":readonly,
		"missing":missing,"renderer":renderer,"output":output,"tooltip":tooltip}

static func compact(text: String, limit: int = 48) -> String:
	return text if text.length() <= limit else text.left(maxi(1,limit-1)) + "…"
