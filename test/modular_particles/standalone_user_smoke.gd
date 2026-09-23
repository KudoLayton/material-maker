extends Node
## Runs from only the manifest-owned files, including in a Windows release EXE.
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
	var box := {"done":false}
	var state = node._gpu
	RenderingServer.call_on_render_thread(func():
		box["data"] = state.rd.buffer_get_data(state.owned_buffers[0])
		box["count"] = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid())).decode_u32(4)
		box["done"] = true)
	while not box.done: await get_tree().process_frame
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
func run() -> void:
	check(not DirAccess.dir_exists_absolute("res://addons/material_maker"),"no Material Maker dependency")
	var resource: MMParticleEffect = load("res://effects/modular_particles/effect.res")
	check(resource != null and resource.validation_error().is_empty(),"portable User resource validates")
	if resource == null or not resource.validation_error().is_empty():
		get_tree().quit(1)
		return
	check(resource.format_version == 2 and resource.user_parameters.size() == 3,"v2 and three public definitions")
	check(resource.shader_file != null and not resource.shader_file.get_spirv().bytecode_compute.is_empty(),"SPIR-V persisted")
	var demo = load("res://effects/modular_particles/demo.tscn").instantiate()
	var a: MMGPUParticles3D = demo.get_node("Particles")
	var b: MMGPUParticles3D = demo.get_node("Second")
	a.manual_processing = true
	b.manual_processing = true
	add_child(demo)
	for i in 180:
		if a.ready_for_simulation and b.ready_for_simulation: break
		await frames(1)
	check(a.ready_for_simulation and b.ready_for_simulation,"two independent GPU nodes")
	if a.ready_for_simulation and b.ready_for_simulation:
		check(a.effect == b.effect,"shared effect resource")
		check(a.get_user_parameter("User.Tint") == Vector4.ONE and b.get_user_parameter("User.Tint") == Vector4(0,0,1,1),"initial per-instance tint")
		for node in [a,b]:
			node.stop()
			check(node.set_user_parameter("User.Gravity",Vector3.ZERO),"set independent gravity")
			node.emit_burst(16)
			node.advance(1.0/60.0)
		await frames()
		var before_a := await snapshot(a)
		var before_b := await snapshot(b)
		check(before_a.count == 16 and before_b.count == 16,"controlled alive counts")
		check(absf(velocity(a,before_a).length()-3.0)<0.0001 and absf(velocity(b,before_b).length()-3.0)<0.0001,"shared Speed controls both spawn cone limits")
		var gpu = a._gpu
		var generation: int = a._generation
		var data_rid: RID = a._gpu.owned_buffers[0]
		var shader: RID = a._gpu.shader
		var defaults := resource.user_parameters.duplicate(true)
		demo.find_child("SpeedSlider",true,false).value = 7.0
		demo.find_child("Gravity1",true,false).value = 6.0
		var picker: ColorPickerButton = demo.find_child("TintPicker",true,false)
		picker.color = Color(1,0,0,1)
		picker.color_changed.emit(picker.color)
		check(a.get_user_parameter("User.Speed") == 7.0 and a.get_user_parameter("User.Gravity") == Vector3(0,6,0) and a.get_user_parameter("User.Tint") == Vector4(1,0,0,1),"live controls use public User API")
		check(b.get_user_parameter("User.Speed") == 3.0 and b.get_user_parameter("User.Gravity") == Vector3.ZERO and b.get_user_parameter("User.Tint") == Vector4(0,0,1,1),"controls leave other node untouched")
		check(resource.user_parameters == defaults,"no shared resource mutation")
		check(a._gpu == gpu and a._gpu.owned_buffers[0] == data_rid and a._gpu.shader == shader and a._generation == generation,"no allocation, shader rebuild or restart")
		a.emit_burst(1)
		a.advance(1.0/60.0)
		b.advance(1.0/60.0)
		await frames()
		var after_a := await snapshot(a)
		var after_b := await snapshot(b)
		check(after_a.count == 17 and after_b.count == 16,"living particles preserved")
		check(value(a,after_a,"particle_id").x == value(a,before_a,"particle_id").x and value(a,after_a,"age").x > value(a,before_a,"age").x,"ID and age continue without restart")
		check((velocity(a,after_a)-velocity(a,before_a)).is_equal_approx(Vector3(0,0.1,0)),"new gravity affects living particles next update")
		check(velocity(b,after_b).is_equal_approx(velocity(b,before_b)),"other node velocity unchanged")
		check(absf((velocity(a,after_a,16)-Vector3(0,0.1,0)).length()-7.0)<0.0001,"new Speed applies to next spawn")
		var color_a := value(a,after_a,"color")
		var color_b := value(b,after_b,"color")
		check(color_a.x>0.5 and is_zero_approx(color_a.y) and is_zero_approx(color_a.z) and color_b.z>0.5 and color_b.x<0.3,"independent tint reaches GPU color")
		await frames(10)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var red := 0
		var blue := 0
		# Exclude the top-left control panel; count actual rendered particles.
		for y in range(340,image.get_height()):
			for x in image.get_width():
				var pixel := image.get_pixel(x,y)
				if pixel.r>0.1 and pixel.r>pixel.b*1.5: red += 1
				if pixel.b>0.1 and pixel.b>pixel.r*1.5: blue += 1
		check(red>3 and blue>3,"two rendered colors below controls: "+str([red,blue]))
		image.save_png("user://user-standalone.png")
		demo.find_child("ResetDefaults",true,false).pressed.emit()
		check(a.get_user_parameter("User.Speed") == 3.0 and a.get_user_parameter("User.Gravity").is_equal_approx(Vector3(0,-9.81,0)) and a.get_user_parameter("User.Tint") == Vector4.ONE,"reset selected instance to effect defaults")
		check(b.get_user_parameter("User.Tint") == Vector4(0,0,1,1),"reset is instance-local")
		check(a._gpu == gpu and a._gpu.owned_buffers[0] == data_rid and a._generation == generation,"reset defaults preserves simulation")
		demo.find_child("Target",true,false).item_selected.emit(1)
		demo.find_child("SpeedSlider",true,false).value = 5.0
		check(b.get_user_parameter("User.Speed") == 5.0 and a.get_user_parameter("User.Speed") == 3.0,"switch control target without sharing overrides")
		demo.animate_speed = true
		demo._process(0.25)
		check(a.get_user_parameter("User.Speed") != 3.0 and b.get_user_parameter("User.Speed") == 5.0,"game logic updates only left node")
		demo.animate_speed = false
	demo.queue_free()
	await frames(8)
	print("MODULAR_STANDALONE ","PASS" if failures == 0 else "FAIL"," checks=",checks," editor=",OS.has_feature("editor")," user_parameters=true")
	get_tree().quit(0 if failures == 0 else 1)
