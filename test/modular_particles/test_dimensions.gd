extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
const State = preload("res://addons/mm_gpu_particles/gpu_state.gd")
const Codec = preload("res://addons/mm_gpu_particles/value_codec.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var doc := Fixtures.basic()
	doc.emitter.lifetime = 0.05
	var effect: MMParticleEffect = Compiler.new().compile(doc).effect
	check(effect != null and effect.format_version == 3,"common v3 compilation")
	var legacy = load("res://addons/mm_gpu_particles/examples/mmtest/effects/modular_particles/effect.res")
	check(legacy != null and legacy.format_version == 2 and legacy.validation_error().is_empty(),"unchanged v2 snapshot validates")
	check(not State.size_error(legacy,1,2).is_empty(),"v2 rejected for 2D")
	var result := {}
	RenderingServer.call_on_render_thread(func():
		for amount in [1,7,129]:
			var states: Array = []
			var data: Array = []
			for dimension in [3,2]:
				var mm := MultiMesh.new()
				RenderingServer.multimesh_allocate_data(mm.get_rid(),amount,RenderingServer.MULTIMESH_TRANSFORM_2D if dimension == 2 else RenderingServer.MULTIMESH_TRANSFORM_3D,true,true,dimension == 3)
				mm.mesh = QuadMesh.new()
				var state := State.new()
				var bytes := Codec.pack_2d(effect,{},Transform2D.IDENTITY,false) if dimension == 2 else Codec.pack(effect,{},Transform3D.IDENTITY,false)
				var problem := state.initialize(effect,mm,amount,bytes,dimension)
				check(problem.is_empty(),"initialize %dD/%d: %s" % [dimension,amount,problem])
				states.append(state)
				data.append(bytes)
			if not states[0].ready or not states[1].ready:
				for state in states: state.release()
				continue
			var spawn: Array[Dictionary] = [{"time":1.0/60.0,"spawn_count":amount+5,"spawn_base":0}]
			for i in 2: states[i].dispatch(spawn,data[i],42)
			var rd: RenderingDevice = states[0].rd
			check(rd.buffer_get_data(states[0].owned_buffers[0]) == rd.buffer_get_data(states[1].owned_buffers[0]),"identical simulation %d" % amount)
			var packed := rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid()))
			check(packed.size() == amount*64,"2D stride")
			check(is_equal_approx(packed.decode_float(12),100.0/60.0),"pixel position")
			check(packed.decode_float(0) == 100.0 and packed.decode_float(20) == 100.0,"upright default basis")
			check(packed.decode_float(32) == 1.0 and packed.decode_float(44) == 1.0,"color offsets")
			# Seed explicit 3D state to exercise projection, rotation, scale and custom slots.
			var values := {"position":[1.0,2.0,3.0],"rotation":[0.0,0.0,sqrt(0.5),sqrt(0.5)],"scale":[2.0,3.0,4.0],"custom":[0.1,0.2,0.3,0.4]}
			for id in values:
				for component in values[id].size():
					var word := PackedByteArray()
					word.resize(4)
					word.encode_float(0,values[id][component])
					rd.buffer_update(states[1].owned_buffers[0],(effect.attribute(id).offset+component)*amount*4,4,word)
			var render_only: Array[Dictionary] = []
			states[1].dispatch(render_only,data[1],42)
			packed = rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid()))
			check(is_equal_approx(packed.decode_float(12),100.0) and is_equal_approx(packed.decode_float(28),-200.0),"XY/Y flip projection")
			check(absf(packed.decode_float(0))<0.001 and is_equal_approx(packed.decode_float(4),300.0) and is_equal_approx(packed.decode_float(16),-200.0),"quaternion/nonuniform scale projection")
			check(is_equal_approx(packed.decode_float(48),0.1) and is_equal_approx(packed.decode_float(60),0.4),"CustomData packing")
			var no_flip := Codec.pack_2d(effect,{},Transform2D.IDENTITY,false,{},100.0,false)
			states[1].dispatch(render_only,no_flip,42)
			packed = rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid()))
			check(packed.decode_float(28) == 200.0 and is_equal_approx(packed.decode_float(4),-300.0),"Y flip off")
			var z := PackedByteArray()
			z.resize(4)
			z.encode_float(0,1234.0)
			rd.buffer_update(states[1].owned_buffers[0],(effect.attribute("position").offset+2)*amount*4,4,z)
			states[1].dispatch(render_only,no_flip,42)
			check(packed == rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid())),"Z-only motion does not change output")
			var transform := Transform2D(0.3,Vector2(45,67))
			var world_data := Codec.pack_2d(effect,{},transform,true)
			var before := rd.buffer_get_data(states[1].owned_buffers[0])
			var empty: Array[Dictionary] = []
			states[1].dispatch(empty,world_data,42)
			check(rd.buffer_get_data(states[1].owned_buffers[0]) == before,"paused World repack does not simulate")
			var alive_bits := PackedByteArray()
			alive_bits.resize(amount*4)
			for i in amount: alive_bits.encode_u32(i*4,i%2)
			rd.buffer_update(states[1].owned_buffers[0],effect.attribute("alive").offset*amount*4,alive_bits.size(),alive_bits)
			var sparse_step: Array[Dictionary] = [{"time":2.0/60.0,"spawn_count":0,"spawn_base":amount}]
			states[1].dispatch(sparse_step,data[1],42)
			packed = rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid()))
			var count := floori(amount/2.0)
			var sparse_ok := true
			for i in amount:
				if packed.decode_float(i*64+44) != (1.0 if i<count else 0.0): sparse_ok = false
			check(sparse_ok,"sparse compaction cannot race tail clearing")
			for tick in 5:
				var steps: Array[Dictionary] = [{"time":(tick+2)/60.0,"spawn_count":0,"spawn_base":amount}]
				states[1].dispatch(steps,data[1],42)
			packed = rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid()))
			var zero := PackedByteArray()
			zero.resize(amount*64)
			check(packed == zero,"all dead clears every output slot")
			states[1].dispatch(spawn,data[1],42)
			packed = rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(states[1].multimesh.get_rid()))
			check(packed.decode_float(44) == 1.0,"respawn after zero alive")
			for state in states: state.release()
		# Actually execute the existing v2 bytecode, not a v3 shader relabelled v2.
		var mm := MultiMesh.new()
		RenderingServer.multimesh_allocate_data(mm.get_rid(),128,RenderingServer.MULTIMESH_TRANSFORM_3D,true,true,true)
		mm.mesh = QuadMesh.new()
		var state := State.new()
		var bytes := Codec.pack(legacy,{},Transform3D.IDENTITY,false)
		check(state.initialize(legacy,mm,128,bytes).is_empty(),"legacy v2 GPU initialize")
		if state.ready:
			var steps: Array[Dictionary] = [{"time":1.0/60.0,"spawn_count":128,"spawn_base":0}]
			state.dispatch(steps,bytes,0)
			check(state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(mm.get_rid())).decode_u32(4) == 128,"legacy indirect draw still works")
		state.release()
		result.done = true)
	while not result.has("done"): await process_frame
	for frame in 8: await process_frame
	print("MODULAR_DIMENSIONS ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
