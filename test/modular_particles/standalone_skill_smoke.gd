extends Node
## Independent game fixture: two installed effects, no MM graphs/autoloads/demo.
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int = 5) -> void:
	for i in count: await get_tree().process_frame
func snapshot(node: MMGPUParticles3D) -> Dictionary:
	var box := {}
	var state = node._gpu
	RenderingServer.call_on_render_thread(func():
		box.data = state.rd.buffer_get_data(state.owned_buffers[0])
		box.count = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid())).decode_u32(4))
	while not box.has("count"): await get_tree().process_frame
	return box
func value(node: MMGPUParticles3D, data: Dictionary, attribute: String, slot: int = 0) -> Vector4:
	var field := node.effect.attribute(attribute)
	var result := Vector4.ZERO
	for i in {"vec2":2,"vec3":3,"vec4":4}.get(field.type,1):
		var address: int = ((field.offset+i)*node.capacity+slot)*4
		if field.type in ["uint","bool"]: result[i] = data.data.decode_u32(address)
		elif field.type == "int": result[i] = data.data.decode_s32(address)
		else: result[i] = data.data.decode_float(address)
	return result
func velocity(node: MMGPUParticles3D, data: Dictionary, slot: int = 0) -> Vector3:
	var v := value(node,data,"velocity",slot)
	return Vector3(v.x,v.y,v.z)
func wait_ready(nodes: Array) -> void:
	for i in 180:
		await frames(1)
		if nodes.all(func(n): return n.ready_for_simulation and not n._rebuild_pending): return
func run() -> void:
	check(not DirAccess.dir_exists_absolute("res://addons/material_maker"),"no authoring dependency")
	check(not FileAccess.file_exists("res://effects/modular_particles/fountain/demo.tscn"),"standalone demo not installed")
	var fountain := load("res://effects/modular_particles/fountain/particles.tscn") as PackedScene
	var burst := load("res://effects/modular_particles/burst/particles.tscn") as PackedScene
	check(fountain != null and burst != null,"two installed scenes load")
	if fountain == null or burst == null:
		get_tree().quit(1)
		return
	var a: MMGPUParticles3D = fountain.instantiate()
	var b: MMGPUParticles3D = fountain.instantiate()
	var c: MMGPUParticles3D = burst.instantiate()
	for n in [a,b,c]:
		n.manual_processing = true
		add_child(n)
	a.position.x = -1
	b.position.x = 1
	c.position.y = 2
	var camera := Camera3D.new()
	camera.position = Vector3(0,0.6,7)
	camera.current = true
	add_child(camera)
	await wait_ready([a,b,c])
	check(a.ready_for_simulation and b.ready_for_simulation and c.ready_for_simulation,"three independent GPU nodes ready")
	if not (a.ready_for_simulation and b.ready_for_simulation and c.ready_for_simulation):
		get_tree().quit(1)
		return
	check(a.effect == b.effect and a.effect != c.effect,"shared fountain, separate burst resource")
	check(a.effect.format_version == 2 and c.effect.format_version == 2,"latest runtime format")
	check(a.effect.shader_file != null and c.effect.shader_file != null,"precompiled SPIR-V")
	check(a.get_user_parameter("User.Speed") == 4.0 and b.get_user_parameter("User.Speed") == 4.0,"edited source default reaches game")
	var defaults := a.effect.user_parameters.duplicate(true)
	for n in [a,b]:
		n.stop()
		check(n.set_user_parameter("User.Gravity",Vector3.ZERO),"zero gravity override")
		n.emit_burst(8)
		n.advance(1.0/60)
	check(a.set_user_parameter("User.Tint",Color(1,0,0,1)) and b.set_user_parameter("User.Tint",Color(0,0,1,1)),"typed per-node color override")
	c.advance(1.0/60)
	await frames()
	var first_a := await snapshot(a)
	var first_b := await snapshot(b)
	check(first_a.count == 8 and first_b.count == 8 and (await snapshot(c)).count == 12,"manual and saved one-shot burst GPU counts")
	check(absf(velocity(a,first_a).length()-4.0)<0.0001 and absf(velocity(b,first_b).length()-4.0)<0.0001,"default Speed drives both cone inputs")
	var state = a._gpu
	var shader: RID = state.shader
	var generation: int = a._generation
	check(a.set_user_parameter("User.Speed",7.0) and a.set_user_parameter("User.Gravity",Vector3(0,6,0)),"dynamic Speed/Gravity accepted")
	check(not a.set_user_parameter("User.Missing",1.0) and not a.set_user_parameter("User.Speed",Vector3.ONE),"invalid name/type rejected")
	var bound: Dictionary = a.effect.parameters.filter(func(p): return p.has("user_id"))[0]
	check(not a.set_parameter(bound.id,1.0),"bound input cannot bypass User API")
	a.emit_burst(1)
	a.advance(1.0/60)
	b.advance(1.0/60)
	await frames()
	var second_a := await snapshot(a)
	var second_b := await snapshot(b)
	check(second_a.count == 9 and second_b.count == 8,"User updates preserve living particles")
	check((velocity(a,second_a)-velocity(a,first_a)).is_equal_approx(Vector3(0,0.1,0)),"new gravity updates living particles")
	check(absf((velocity(a,second_a,8)-Vector3(0,0.1,0)).length()-7.0)<0.0001,"new speed reaches next spawn")
	check(velocity(b,second_b).is_equal_approx(velocity(b,first_b)) and b.get_user_parameter("User.Speed") == 4.0,"other node unaffected")
	var ca := value(a,second_a,"color")
	var cb := value(b,second_b,"color")
	check(ca.x>0.5 and ca.y<0.01 and ca.z<0.01 and cb.z>0.5 and cb.x<0.01,"independent colors reach GPU")
	check(a._gpu == state and a._gpu.shader == shader and a._generation == generation,"User updates do not rebuild GPU state")
	await frames(12)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var red := 0
	var blue := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x,y)
			if pixel.r>0.1 and pixel.r>pixel.b*1.5: red += 1
			if pixel.b>0.1 and pixel.b>pixel.r*1.5: blue += 1
	check(red>3 and blue>3,"actual rendered red/blue particles: "+str([red,blue]))
	image.save_png("user://skill-game.png")
	a.reset_user_parameter("User.Speed")
	a.reset_user_parameter("User.Tint")
	check(a.get_user_parameter("User.Speed") == 4.0 and a.get_user_parameter("User.Tint") == Vector4.ONE,"reset restores source defaults")
	check(b.get_user_parameter("User.Tint") == Vector4(0,0,1,1) and a.effect.user_parameters == defaults,"reset is local, shared resource unchanged")
	a.pause()
	var paused: float = a.clock.time
	a.advance(0.1)
	await frames()
	check(a.clock.time == paused and (await snapshot(a)).count == 9,"Pause preserves time and particles")
	a.play()
	a.advance(1.0/60)
	await frames()
	check((await snapshot(a)).count == 10,"Play resumes saved rate emission")
	a.stop()
	a.advance(1.0/60)
	await frames()
	check((await snapshot(a)).count == 10 and a.clock.time > paused,"Stop disables emission but updates living particles")
	for i in 120:
		c.advance(1.0/60)
		await frames(1)
	check(c.clock.sequence == 12,"one-shot schedule does not repeat across periods")
	c.restart()
	await wait_ready([c])
	check(c.ready_for_simulation and c.clock.sequence == 0,"restart resets scheduler")
	c.advance(1.0/60)
	await frames()
	check((await snapshot(c)).count == 12,"restart replays saved burst")
	for n in [a,b,c]: n.queue_free()
	await frames(10)
	print("MODULAR_SKILL_GAME ","PASS" if failures == 0 else "FAIL"," checks=",checks," editor=",OS.has_feature("editor"))
	get_tree().quit(0 if failures == 0 else 1)
