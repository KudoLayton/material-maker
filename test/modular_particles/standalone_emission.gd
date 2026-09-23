extends SceneTree
var failures := 0
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ",message)
func run() -> void:
	for version in [1,2]:
		var particles = load("res://addons/mm_gpu_particles/particles_3d.gd").new()
		particles.manual_processing = true
		particles.capacity = 256
		particles.effect = load("res://emission-v%d.res" % version)
		root.add_child(particles)
		for frame in 180:
			await process_frame
			if particles.ready_for_simulation or not particles.error_text.is_empty(): break
		check(particles.ready_for_simulation,"standalone GPU v%d: %s" % [version,particles.error_text])
		if particles.ready_for_simulation:
			for tick in 12:
				particles.advance(1.0/60)
				await process_frame
				await RenderingServer.frame_post_draw
			var state = particles._gpu
			var result := {}
			RenderingServer.call_on_render_thread(func():
				result.count = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid())).decode_u32(4))
			while result.is_empty(): await process_frame
			check(particles.clock.sequence == 15 and result.count == 15,"saved mixed schedule produces 12 continuous + 3 burst GPU particles")
		particles.queue_free()
		for frame in 10:
			await process_frame
			await RenderingServer.frame_post_draw
	print("MODULAR_STANDALONE_EMISSION ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
