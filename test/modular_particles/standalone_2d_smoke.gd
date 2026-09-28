extends Node
## Strict standalone/Release probe: intentionally contains no authoring dependency.
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var scene_path: String = ProjectSettings.get_setting("mm_verification/demo","res://effects/modular_particles/demo.tscn")
	var demo = load(scene_path).instantiate()
	var particles = demo.get_node("Particles")
	particles.manual_processing = true
	add_child(demo)
	check(particles is MMGPUParticles2D,"2D runtime node")
	check(particles.effect.format_version == 3 and particles.effect.shader_file != null,"v3 embedded SPIR-V")
	for frame in 180:
		await get_tree().process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation,"GPU initialized: "+particles.error_text)
	if particles.ready_for_simulation:
		particles.emit_burst(mini(128,particles.capacity))
		for frame in 10:
			particles.advance(1.0/60.0)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var result := {}
		var state = particles._gpu
		RenderingServer.call_on_render_thread(func():
			result.instances = state.rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(state.multimesh.get_rid()))
			result.data = state.rd.buffer_get_data(state.owned_buffers[0])
			result.done = true)
		while not result.has("done"): await get_tree().process_frame
		check(result.instances.size() == particles.capacity*64,"2D stride in Release")
		var alive := 0
		var offset: int = particles.effect.attribute("alive").offset*particles.capacity*4
		for i in particles.capacity:
			if result.data.decode_u32(offset+i*4) != 0: alive += 1
		check(alive > 0 and alive <= particles.capacity,"alive population without indirect draw")
		var image := get_viewport().get_texture().get_image()
		var lit := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x,y).r > 0.1: lit += 1
		check(lit > 30,"visible 2D pixels: "+str(lit))
		image.save_png("user://standalone-2d.png")
		if particles.texture != null: check(particles.texture.get_image() != null,"embedded sprite without source PNG")
		particles.pause()
		var time: float = particles.clock.time
		particles.advance(0.1)
		check(time == particles.clock.time,"pause")
		if demo.has_node("Second"):
			check(demo.get_node("Second") is MMGPUParticles2D,"2D User demo second instance")
			for user in particles.effect.user_parameters:
				check(particles.reset_user_parameter_by_id(user.id),"User reset: "+user.name)
	demo.queue_free()
	for frame in 8: await get_tree().process_frame
	print("MODULAR_STANDALONE ","PASS" if failures == 0 else "FAIL"," checks=",checks," editor=",OS.has_feature("editor"))
	get_tree().quit(0 if failures == 0 else 1)
