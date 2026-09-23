extends SceneTree
## Exercise the runtime without depending on the new authoring/compiler feature.
## Compile legacy input slots, then attach exactly the format-2 runtime metadata.
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
const Codec = preload("res://addons/mm_gpu_particles/value_codec.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
const VALUES := {"bool":true,"int":-17,"uint":4294967295,"float":2.0,"vec2":[1.0,2.0],"vec3":[3.0,4.0,5.0],"vec4":[0.25,0.5,0.75,1.0]}
const CHANGED := {"bool":false,"int":-2147483648,"uint":2147483649,"float":5.0,"vec2":[6.0,7.0],"vec3":[8.0,9.0,10.0],"vec4":[0.8,0.6,0.4,0.2]}
var checks := 0
var failures := 0
var nodes: Array[MMGPUParticles3D] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func _initialize() -> void: run.call_deferred()

func fixture() -> MMParticleEffect:
	var doc := Fixtures.basic()
	doc.emitter.rate = 0.0
	doc.emitter.lifetime = 100.0
	for stage in ["spawn","update"]:
		var inputs: Array = []
		var graph_nodes: Array = []
		var outputs := {}
		for type in VALUES:
			var attribute: String = stage+"_"+type
			doc.attributes.append({"id":attribute,"name":attribute,"type":type,"default":VALUES[type]})
			inputs.append({"id":type,"name":type,"type":type,"default":VALUES[type]})
			graph_nodes.append({"id":type,"op":"parameter","parameter":type})
			outputs[attribute] = type
		doc.modules[stage+"_values"] = {"name":"Values","stages":[stage],"inputs":inputs,"reads":[],"writes":outputs.keys(),"graph":{"nodes":graph_nodes,"outputs":outputs}}
		doc.stages[stage].append({"id":stage+"_values","module":stage+"_values"})
	# Multiple module instances plus both stages consume each User.
	doc.stages.update.append({"id":"update_copy","module":"update_values"})
	var result := Compiler.new().compile(doc)
	check(result.errors.is_empty(),"latest input fixture: "+str(result.errors))
	if result.effect == null: return null
	var effect: MMParticleEffect = result.effect
	check(effect.validation_error().is_empty() and effect.format_version == 2,"latest effect without Users validates")
	for type in VALUES:
		effect.user_parameters.append({"id":"user_"+type,"name":"Value_"+type,"type":type,"default":VALUES[type]})
	for parameter in effect.parameters:
		parameter.user_id = "user_float" if parameter.id == "spawn1/speed" else "user_"+parameter.type
	check(effect.validation_error().is_empty(),"format-2 metadata validates")
	return effect

func validation_tests(effect: MMParticleEffect) -> void:
	var bad := effect.duplicate(true)
	bad.format_version = 1
	check(not bad.validation_error().is_empty(),"User definitions rejected in format 1")
	bad = effect.duplicate(true)
	bad.user_parameters.clear()
	check(not bad.validation_error().is_empty(),"dangling binding rejected")
	bad = effect.duplicate(true)
	bad.user_parameters.append(bad.user_parameters[0].duplicate(true))
	check(not bad.validation_error().is_empty(),"duplicate User ID rejected")
	bad = effect.duplicate(true)
	bad.user_parameters[1].name = bad.user_parameters[0].name
	check(not bad.validation_error().is_empty(),"duplicate User name rejected")
	for label in ["", "User.Wind", "3Wind", "Wind Speed", "Wind/Speed", "바람"]:
		bad = effect.duplicate(true)
		bad.user_parameters[0].name = label
		check(not bad.validation_error().is_empty(),"invalid name rejected: "+label)
	bad = effect.duplicate(true)
	bad.parameters[0].user_id = "user_vec3"
	check(not bad.validation_error().is_empty(),"binding type mismatch rejected")
	bad = effect.duplicate(true)
	bad.parameters[0].offset = 0
	check(not bad.validation_error().is_empty(),"reserved buffer words protected")
	bad = effect.duplicate(true)
	bad.parameters[1].offset = bad.parameters[0].offset
	check(not bad.validation_error().is_empty(),"overlapping input slots rejected")
	bad = effect.duplicate(true)
	bad.user_parameters[3].default = NAN
	check(not bad.validation_error().is_empty(),"nonfinite User default rejected")
	var owner := Particles.new()
	check(not owner.set_user_parameter("User.Value_float",3.0),"no effect setter rejected")
	check(owner.get_user_parameter("User.Value_float") == null,"no effect getter null")
	owner.effect = effect
	for type in VALUES:
		check(owner.get_user_parameter("User.Value_"+type) == Codec.canonical(type,VALUES[type]),"typed default "+type)
		check(owner.set_user_parameter_by_id("user_"+type,CHANGED[type]),"pre-tree ID setter "+type)
		check(owner.get_user_parameter("User.Value_"+type) == Codec.canonical(type,CHANGED[type]),"typed getter "+type)
		check(owner.reset_user_parameter("User.Value_"+type),"name reset "+type)
	check(owner.user_parameter_overrides.is_empty(),"reset erases overrides")
	check(owner.reset_user_parameter_by_id("user_float"),"reset absent override succeeds")
	for name in ["Value_float","User.missing","Particle.Value_float"]:
		check(not owner.set_user_parameter(name,1.0) and owner.get_user_parameter(name) == null and not owner.reset_user_parameter(name),"qualified known name required "+name)
	for pair in [["float",INF],["float",NAN],["float",1e40],["float",Vector3.ONE],["uint",-1],["uint",4294967296],["uint",1.5],["int",2147483648],["int",-2147483649],["bool",1],["vec3",[1,2]]]:
		check(not owner.set_user_parameter_by_id("user_"+pair[0],pair[1]),"invalid override rejected "+str(pair))
	check(owner.user_parameter_overrides.is_empty(),"invalid setters unchanged")
	var values: Array = [1.0,2.0,3.0]
	check(owner.set_user_parameter_by_id("user_vec3",values),"Array accepted")
	values[0] = 99.0
	check(owner.get_user_parameter_by_id("user_vec3") == Vector3(1,2,3),"caller mutable value isolated")
	check(owner.set_user_parameter_by_id("user_vec4",Color(1,0,0,0.5)),"Color accepted as vec4")
	check(owner.get_user_parameter_by_id("user_vec4") == Vector4(1,0,0,0.5),"Color canonical Vector4")
	owner.user_parameter_overrides["orphan"] = 12
	owner.user_parameter_overrides["user_float"] = "wrong"
	check(owner._get_configuration_warnings().size() == 2,"orphan/invalid stored overrides warn")
	check(owner.get_user_parameter_by_id("user_float") == 2.0,"invalid stored value uses default")
	check(owner.user_parameter_overrides.has("orphan"),"orphan value preserved")
	owner.parameter_overrides["spawn1/speed"] = 99.0
	check(not owner.set_parameter("spawn1/speed",11.0),"bound legacy setter rejected")
	var packed := Codec.pack(effect,owner.parameter_overrides,Transform3D.IDENTITY,false,owner.user_parameter_overrides)
	check(packed.decode_float(effect.parameter("spawn1/speed").offset*4) == 2.0,"raw stale module override cannot shadow User")
	owner.free()

func wait_ready(node: MMGPUParticles3D) -> void:
	for frame in 180:
		await process_frame
		if node.ready_for_simulation or not node.error_text.is_empty(): break
	check(node.ready_for_simulation,"GPU initialization: "+node.error_text)

func step(count: int = 1) -> void:
	for tick in count:
		for node in nodes: node.advance(1.0/60.0)
		await process_frame
		await RenderingServer.frame_post_draw

func snapshot(node: MMGPUParticles3D) -> Dictionary:
	var result := {}
	var state = node._gpu
	RenderingServer.call_on_render_thread(func():
		result.data = state.rd.buffer_get_data(state.owned_buffers[0])
		result.params = state.rd.buffer_get_data(state.owned_buffers[3])
		result.count = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid())).decode_u32(4)
		result.done = true)
	while not result.has("done"): await process_frame
	return result

func attribute_matches(node: MMGPUParticles3D, bytes: PackedByteArray, attribute: String, slot: int, expected) -> bool:
	var field := node.effect.attribute(attribute)
	var items := Codec.components(field.type,expected)
	for component in items.size():
		var offset: int = ((field.offset+component)*node.capacity+slot)*4
		match field.type:
			"bool":
				if bytes.decode_u32(offset) != (1 if items[component] else 0): return false
			"uint":
				if bytes.decode_u32(offset) != items[component]: return false
			"int":
				if bytes.decode_s32(offset) != items[component]: return false
			_:
				if absf(bytes.decode_float(offset)-items[component]) > 0.00001: return false
	return true

func run() -> void:
	var effect := fixture()
	if effect == null:
		quit(1)
		return
	validation_tests(effect)
	for index in 2:
		var node := Particles.new()
		node.manual_processing = true
		node.effect = effect
		node.capacity = 4
		if index == 0: check(node.set_user_parameter("User.Value_float",3.0),"value set before tree")
		nodes.append(node)
		root.add_child(node)
		await wait_ready(node)
	if nodes.any(func(n): return not n.ready_for_simulation):
		for node in nodes: node.queue_free()
		await process_frame
		quit(1)
		return
	var a := nodes[0]
	var b := nodes[1]
	var state = a._gpu
	var generation: int = a._generation
	var pipeline: RID = state.pipeline
	var buffers: Array = state.owned_buffers.duplicate()
	var hash_before := effect.source_hash
	for node in nodes: node.emit_burst(1)
	await step()
	var first := await snapshot(a)
	var other := await snapshot(b)
	for type in VALUES:
		var value = 3.0 if type == "float" else VALUES[type]
		check(attribute_matches(a,first.data,"spawn_"+type,0,value),"Spawn GPU type "+type)
		check(attribute_matches(a,first.data,"update_"+type,0,value),"Update GPU type "+type)
		check(attribute_matches(b,other.data,"update_"+type,0,VALUES[type]),"shared resource independent node "+type)
		check(a.set_user_parameter("User.Value_"+type,CHANGED[type]),"live setter "+type)
	a.parameter_overrides["spawn1/speed"] = 99.0
	a.parameter_overrides["update_values/uint"] = 0
	check(not a.set_parameter("update_values/uint",0),"live bound setter rejected")
	a.emit_burst(1)
	await step()
	var changed := await snapshot(a)
	for type in VALUES:
		check(attribute_matches(a,changed.data,"spawn_"+type,0,3.0 if type == "float" else VALUES[type]),"old Spawn value retained "+type)
		check(attribute_matches(a,changed.data,"spawn_"+type,1,CHANGED[type]),"new Spawn sees changed User "+type)
		check(attribute_matches(a,changed.data,"update_"+type,0,CHANGED[type]) and attribute_matches(a,changed.data,"update_"+type,1,CHANGED[type]),"Update changes all living slots "+type)
	check(attribute_matches(a,changed.data,"velocity",0,Vector3(3,0,0)) and attribute_matches(a,changed.data,"velocity",1,Vector3(5,0,0)),"Spawn-only velocity not rewritten")
	check(attribute_matches(a,changed.data,"particle_id",0,0) and attribute_matches(a,changed.data,"age",0,2.0/60.0),"ID and age preserved across live changes")
	check(a._gpu == state and a._generation == generation and state.pipeline == pipeline and state.owned_buffers == buffers and effect.source_hash == hash_before,"no rebuild, new GPU resources or recompilation")
	check(changed.params.decode_float(effect.parameter("spawn1/speed").offset*4) == 5.0,"bound input buffer ignores stale raw override")
	other = await snapshot(b)
	check(attribute_matches(b,other.data,"update_float",0,2.0),"other instance still default")
	check(effect.user_parameter("User.Value_float").default == 2.0,"shared effect defaults immutable")
	a.pause()
	check(a.set_user_parameter("User.Value_float",7.0),"set while paused")
	await step(3)
	var paused := await snapshot(a)
	check(paused.data == changed.data,"pause does not dispatch new value")
	a.play()
	await step()
	var resumed := await snapshot(a)
	check(attribute_matches(a,resumed.data,"update_float",0,7.0),"resume consumes new value")
	check(a.reset_user_parameter("User.Value_float"),"live reset")
	await step()
	var reset := await snapshot(a)
	check(attribute_matches(a,reset.data,"update_float",0,2.0),"reset sends resource default on next step")
	a.set_user_parameter_by_id("user_float",6.0)
	a.restart()
	await wait_ready(a)
	a.emit_burst(1)
	await step()
	var restarted := await snapshot(a)
	check(attribute_matches(a,restarted.data,"spawn_float",0,6.0),"restart preserves User override")
	for node in nodes: node.queue_free()
	nodes.clear()
	for frame in 8: await process_frame
	print("MODULAR_USER_RUNTIME ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
