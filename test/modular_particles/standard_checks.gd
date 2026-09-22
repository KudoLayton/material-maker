extends RefCounted
## Shared test fixtures; all readbacks stay here, never in the runtime.
const D = preload("res://addons/material_maker/particles/modular/document.gd")
const L = preload("res://addons/material_maker/particles/modular/module_library.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
const Codec = preload("res://addons/mm_gpu_particles/value_codec.gd")

static func document(spawn: Array, update: Array, overrides: Dictionary = {}) -> Dictionary:
	var doc := D.create()
	doc.emitter.merge({"rate":0.0,"duration":4.0,"loop":false,"lifetime":4.0},true)
	for stage in ["spawn","update"]:
		for id in spawn if stage == "spawn" else update:
			var added := L.insert(doc,L.payload(id),stage)
			assert(added.ok,"Standard test fixture insertion must succeed")
			doc = added.document
			doc.stages[stage].back().parameters = overrides.get(id,{}).duplicate(true)
	return doc

static func instance(doc: Dictionary, catalog_id: String) -> Dictionary:
	for stage in ["spawn","update"]:
		for item in doc.stages[stage]:
			if doc.modules[item.module].get("standard_module",{}).get("catalog_id") == catalog_id: return item
	return {}

static func attribute_id(doc: Dictionary, role: String) -> String:
	for attribute in doc.attributes:
		if attribute.get("standard_role") == "mm.standard.v1."+role: return attribute.id
	return ""

static func compile(doc: Dictionary) -> Dictionary:
	var graphs := {}
	for id in doc.modules:
		if doc.modules[id].has("mm_graph"): graphs[id] = await mm_loader.create_gen(doc.modules[id].mm_graph.duplicate(true))
	var result := Compiler.new().compile(doc,graphs)
	for graph in graphs.values(): graph.free()
	return result

static func frames(tree: SceneTree, count: int = 3) -> void:
	for frame in count:
		await tree.process_frame
		await RenderingServer.frame_post_draw

static func start(owner: Node, effect: Resource, capacity: int = 16, options: Dictionary = {}):
	var particles := Particles.new()
	particles.manual_processing = true
	particles.capacity = capacity
	particles.effect = effect
	for key in options: particles.set(key,options[key])
	owner.add_child(particles)
	for frame in 180:
		await owner.get_tree().process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	if particles.ready_for_simulation: particles._draw.visible = false
	return particles

static func snapshot(particles) -> Dictionary:
	var result := {}
	var state = particles._gpu
	RenderingServer.call_on_render_thread(func():
		result.data = state.rd.buffer_get_data(state.owned_buffers[0])
		result.count = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid())).decode_u32(4)
		result.done = true)
	while not result.has("done"): await particles.get_tree().process_frame
	return result

static func value(particles, snapshot: Dictionary, id: String, index: int = 0):
	var attribute: Dictionary = particles.effect.attribute(id)
	var values: Array = []
	for component in D.TYPES[attribute.type]:
		var address: int = ((attribute.offset+component)*particles.capacity+index)*4
		if attribute.type == "bool": values.append(snapshot.data.decode_u32(address) != 0)
		elif attribute.type == "uint": values.append(snapshot.data.decode_u32(address))
		else: values.append(snapshot.data.decode_float(address))
	return values[0] if values.size() == 1 else values

static func vector(particles, snapshot: Dictionary, id: String, index: int = 0) -> Vector3:
	var v: Array = value(particles,snapshot,id,index)
	return Vector3(v[0],v[1],v[2])

static func dispose(particles) -> void:
	var tree: SceneTree = particles.get_tree()
	particles.queue_free()
	await frames(tree,5)
