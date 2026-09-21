extends Node
## Copied into the isolated export verification project only. No authoring API.
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var demo = load("res://effects/modular_particles/demo.tscn").instantiate()
	var particles = demo.get_node("Particles")
	particles.manual_processing = true
	add_child(demo)
	check(particles.effect.shader_file != null,"packaged SPIR-V")
	for frame in 180:
		await get_tree().process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation,"packaged GPU: " + particles.error_text)
	if particles.ready_for_simulation:
		for frame in 20:
			particles.advance(1.0/60.0)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var result := {}
		var state = particles._gpu
		RenderingServer.call_on_render_thread(func():
			var commands: PackedByteArray = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid()))
			result.count = commands.decode_u32(4)
			result.done = true)
		while not result.has("done"): await get_tree().process_frame
		check(result.count == 128,"packaged indirect draw count")
		var image := get_tree().root.get_texture().get_image()
		var lit := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x,y).r > 0.1: lit += 1
		check(lit > 30,"packaged visible pixels: " + str(lit))
		image.save_png("user://standalone.png")
		particles.pause()
		var time: float = particles.clock.time
		particles.advance(0.1)
		check(particles.clock.time == time,"packaged pause")
	demo.queue_free()
	for frame in 8: await get_tree().process_frame
	print("MODULAR_STANDALONE ","PASS" if failures == 0 else "FAIL"," checks=",checks," editor=",OS.has_feature("editor"))
	get_tree().quit(0 if failures == 0 else 1)
