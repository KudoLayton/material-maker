extends RefCounted
## Authoring-only stack contracts. No name matching, graph rewriting, or runtime changes.
const L = preload("module_library.gd")
const PREFIX := "mm.standard.v1."
const SPECS := {
	"initialize_particle":{"stage":"spawn","roles":["acceleration","drag","initial_color","initial_scale"],"reads":[],"writes":["position","velocity","rotation","color","scale","lifetime","acceleration","drag","initial_color","initial_scale"]},
	"box_location":{"stage":"spawn","roles":[],"reads":[],"writes":["position"]},
	"sphere_location":{"stage":"spawn","roles":[],"reads":[],"writes":["position"]},
	"add_velocity":{"stage":"spawn","roles":[],"reads":[],"writes":["velocity"]},
	"add_velocity_in_cone":{"stage":"spawn","roles":[],"reads":[],"writes":["velocity"]},
	"gravity":{"stage":"update","roles":["acceleration"],"reads":["acceleration"],"writes":["acceleration"]},
	"drag":{"stage":"update","roles":["drag"],"reads":["drag"],"writes":["drag"]},
	"curl_noise":{"stage":"update","roles":["acceleration"],"reads":["acceleration"],"writes":["acceleration"]},
	"solve_motion":{"stage":"update","roles":["acceleration","drag"],"reads":["acceleration","drag"],"writes":["position","velocity","acceleration","drag"]},
	"color_over_life":{"stage":"update","roles":["initial_color"],"reads":["initial_color"],"writes":["color"]},
	"scale_over_life":{"stage":"update","roles":["initial_scale"],"reads":["initial_scale"],"writes":["scale"]},
	"kill_particles":{"stage":"update","roles":[],"reads":[],"writes":["alive"]}}

static func graph_reads(graph: Dictionary, reads: Array, nested: bool = false) -> void:
	var nodes := {}
	var queue: Array = []
	for node in graph.get("nodes",[]):
		if not node is Dictionary: continue
		nodes[node.get("name","")] = node
		if node.get("settings",{}).get("kind") == "module_output" or (nested and node.get("name") == "gen_outputs"): queue.append(node.get("name",""))
	var seen := {}
	while not queue.is_empty():
		var name = queue.pop_back()
		if seen.has(name) or not nodes.has(name): continue
		seen[name] = true
		var node: Dictionary = nodes[name]
		var settings: Dictionary = node.get("settings",{})
		if settings.get("kind") == "module_read" and settings.get("id") not in reads: reads.append(settings.id)
		if node.get("type") == "graph": graph_reads(node,reads,true)
		for connection in graph.get("connections",[]):
			if connection is Dictionary and connection.get("to") == name: queue.append(connection.get("from",""))

static func access(module: Dictionary) -> Dictionary:
	var writes := {}
	var reads: Array = []
	if module.has("mm_graph"):
		var graph: Dictionary = module.mm_graph
		graph_reads(graph,reads)
		for node in graph.get("nodes",[]):
			if not node is Dictionary: continue
			var settings: Dictionary = node.get("settings",{})
			if settings.get("kind") != "module_output": continue
			var fields: Array = settings.get("fields",[])
			for index in fields.size():
				if graph.get("connections",[]).any(func(c): return c is Dictionary and c.get("to") == node.get("name") and c.get("to_port") == index and graph.nodes.any(func(n): return n is Dictionary and n.get("name") == c.get("from"))):
					writes[fields[index].get("id","")] = fields[index].get("type","")
	elif module.get("graph") is Dictionary:
		# Typed IR writers are valid initial-value providers too; the compiler validates their expressions.
		writes = module.graph.get("outputs",{}).duplicate(true)
	return {"reads":reads,"writes":writes}

static func message(row: Dictionary, text: String) -> Dictionary:
	return {"stage":row.get("stage",""),"module":row.get("instance",{}).get("id",""),"node":"","message":text}

static func validate(document: Dictionary) -> Dictionary:
	var result := {"errors":[],"warnings":[]}
	var rows: Array = []
	var standard_rows: Array = []
	for stage in ["spawn","update"]:
		var stack: Array = document.stages.get(stage,[])
		for index in stack.size():
			var instance = stack[index]
			if not instance is Dictionary or not instance.get("enabled",true): continue
			var module = document.modules.get(instance.get("module",""),{})
			if not module is Dictionary: continue
			var row := {"stage":stage,"index":index,"instance":instance,"module":module,"access":access(module),"kind":"","bindings":{}}
			rows.append(row)
			if not module.has("standard_module"): continue
			var standard = module.standard_module
			if not standard is Dictionary or not standard.get("catalog_id") is String or not SPECS.has(standard.get("catalog_id")) or standard.get("revision") != 1 or not standard.get("bindings") is Dictionary:
				result.errors.append(message(row,"Unsupported or malformed standard module metadata"))
				continue
			row.kind = standard.catalog_id
			row.bindings = standard.bindings
			standard_rows.append(row)
	if standard_rows.is_empty(): return result
	var attributes := {}
	var roles := {}
	for attribute in document.attributes:
		attributes[attribute.id] = attribute
		if attribute.has("standard_role"):
			var role = attribute.standard_role
			if not role is String or not L.ROLES.has(role):
				result.errors.append(message({},"Unknown standard Attribute role"))
				continue
			if roles.has(role): result.errors.append(message({},"Duplicate standard Attribute role: "+role))
			roles[role] = attribute.id
	var solvers := standard_rows.filter(func(row): return row.kind == "solve_motion")
	var initializers := standard_rows.filter(func(row): return row.kind == "initialize_particle")
	if solvers.size()>1:
		for row in solvers: result.errors.append(message(row,"Use exactly one active Solve Motion; duplicate solvers integrate twice"))
	if initializers.size()>1:
		for row in initializers: result.errors.append(message(row,"Use at most one active Initialize Particle"))
	for row in standard_rows:
		var spec: Dictionary = SPECS[row.kind]
		if row.stage != spec.stage: result.errors.append(message(row,"Standard module not allowed in "+row.stage))
		for role in spec.roles:
			var full: String = PREFIX+role
			var id = row.bindings.get(full,"")
			if not attributes.has(id) or attributes[id].get("standard_role") != full or attributes[id].type != L.ROLES[full].type:
				result.errors.append(message(row,"Missing or incompatible standard Attribute binding: "+full))
		for key in ["reads","writes"]:
			for field in spec[key]:
				var id: String = row.bindings.get(PREFIX+field,field)
				if not row.access[key].has(id): result.errors.append(message(row,"Required "+key.trim_suffix("s")+" is disconnected: "+field))
		if row.kind in ["gravity","curl_noise","drag"]:
			if solvers.size() != 1: result.errors.append(message(row,"Add exactly one active Solve Motion after all acceleration/drag modules"))
			else:
				var solver: Dictionary = solvers[0]
				if row.index >= solver.index: result.errors.append(message(row,"Move this module before Solve Motion"))
				for role in spec.roles:
					if row.bindings.get(PREFIX+role) != solver.bindings.get(PREFIX+role): result.errors.append(message(row,"Solve Motion must use the same Attribute binding: "+role))
		if row.kind in ["color_over_life","scale_over_life"]:
			var role: String = spec.roles[0]
			var id = row.bindings.get(PREFIX+role,"")
			if not rows.any(func(candidate): return candidate.stage == "spawn" and candidate.access.writes.has(id)):
				result.errors.append(message(row,"Add an active Spawn writer for "+role+" (Initialize Particle or a custom module)"))
		if row.stage == "spawn" and row.kind in ["box_location","sphere_location","add_velocity","add_velocity_in_cone"]:
			if initializers.size() == 1 and row.index < initializers[0].index: result.errors.append(message(row,"Move Initialize Particle before Location/Velocity modules"))
	if not solvers.is_empty():
		for row in rows:
			if row.stage == "update" and row.kind != "solve_motion" and row.access.writes.has("position"):
				result.warnings.append(message(row,"Another Update module writes Position alongside Solve Motion; check for double integration (intentional position constraints are allowed)"))
	return result
