extends "res://addons/mm_gpu_particles/particles_3d.gd"
## Authoring-only restart: reuse the pipeline and allocation when only the
## emission schedule changes. The standalone runtime/API is left untouched.
func restart() -> void:
	if not ready_for_simulation or _rebuild_pending or _gpu == null:
		super.restart()
		return
	var was_paused: bool = clock.paused
	clock.reset()
	clock.paused = was_paused
	emitting = true
	_steps.clear()
	var state = _gpu
	var data := Codec.pack(effect,_validated_overrides(),global_transform,simulation_space == 1,user_parameter_overrides)
	var current_seed := seed
	RenderingServer.call_on_render_thread(func():
		if not state.ready: return
		# The first three owned buffers are attributes and scan scratch buffers.
		for index in 3:
			var bytes: int = state.capacity*4*(state.effect.component_count if index == 0 else 1)
			state.rd.buffer_clear(state.owned_buffers[index],0,bytes)
		# Repack the empty MultiMesh and indirect draw count even while paused.
		var empty: Array[Dictionary] = [{"time":0.0,"spawn_count":0,"spawn_base":0}]
		state.dispatch(empty,data,current_seed))
