extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
var particles: MMGPUParticles3D
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for frame in 120:
		await process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation, "GPU state: " + particles.error_text)

func emit() -> void:
	particles.emit_burst(2)
	particles.advance(1.0/60.0)
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(128,128)
	var camera := Camera3D.new()
	camera.position.z = 3
	root.add_child(camera)
	camera.current = true
	var document := Fixtures.basic()
	document.emitter.rate = 0.0
	document.renderer.quad_size = 2.0
	document.modules.initialize.graph.nodes[0].value = [0.0,0.0,0.0]
	document.modules.initialize.writes.append_array(["color","custom"])
	document.modules.initialize.graph.nodes.append({"id":"red","op":"constant","type":"vec4","value":[1.0,0.0,0.0,1.0]})
	document.modules.initialize.graph.nodes.append({"id":"green","op":"constant","type":"vec4","value":[0.0,1.0,0.0,1.0]})
	document.modules.initialize.graph.outputs.color = "red"
	document.modules.initialize.graph.outputs.custom = "green"
	particles = Particles.new()
	particles.capacity = 4
	particles.manual_processing = true
	particles.effect = Compiler.new().compile(document).effect
	root.add_child(particles)
	await settle()
	for mode in ["opaque","additive","cutout"]:
		document.renderer.mode = mode
		particles.effect = Compiler.new().compile(document).effect
		await settle()
		await emit()
		var pixel := root.get_texture().get_image().get_pixel(64,64)
		check(pixel.r > 0.8 and pixel.g < 0.1, "GPU Color in " + mode + ": " + str(pixel))
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded,cull_disabled; varying vec4 data; void vertex(){data=INSTANCE_CUSTOM;} void fragment(){ALBEDO=data.rgb;}"
	var material := ShaderMaterial.new()
	material.shader = shader
	particles.draw_material = material
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var custom_pixel := root.get_texture().get_image().get_pixel(64,64)
	check(custom_pixel.g > 0.8 and custom_pixel.r < 0.1, "GPU CustomData reaches spatial material")
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,-1,0),Vector3(1,-1,0),Vector3(0,1,0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	particles.mesh = mesh
	await settle()
	await emit()
	var data := {}
	var state = particles._gpu
	RenderingServer.call_on_render_thread(func():
		data.commands = state.rd.buffer_get_data(RenderingServer.multimesh_get_command_buffer_rd_rid(state.multimesh.get_rid()))
		data.done = true)
	while not data.has("done"): await process_frame
	check(data.commands.decode_u32(4) == 2 and data.commands.decode_u32(24) == 2, "both mesh surfaces receive active count")
	check(data.commands.decode_u32(0) == 3 and data.commands.decode_u32(20) == 3, "index/vertex counts preserved")
	particles.visibility_aabb = AABB(Vector3(-2,-2,-2),Vector3(4,4,4))
	check(particles._draw.multimesh.custom_aabb == particles.visibility_aabb, "custom AABB propagated")
	for i in 16:
		particles.capacity = 4 + i
		await settle()
		await emit()
	check(particles.ready_for_simulation, "repeated capacity changes remain live")
	var broken: MMParticleEffect = particles.effect.duplicate(true)
	broken.compute_source = "#version 450\nthis is not valid GLSL"
	broken.source_hash = broken.compute_source.sha256_text()
	particles.effect = broken
	for frame in 20: await process_frame
	check(not particles.ready_for_simulation and not particles.error_text.is_empty(), "partial GPU initialization reports error")
	particles.effect = Compiler.new().compile(document).effect
	await settle()
	await emit()
	root.get_texture().get_image().save_png("user://modular_render.png")
	particles.restart()
	particles.queue_free() # pending rebuild/initialization must not outlive the node
	for frame in 8: await process_frame
	for i in 8:
		var temporary := Particles.new()
		temporary.effect = Compiler.new().compile(document).effect
		temporary.capacity = 4
		root.add_child(temporary)
		await process_frame
		temporary.queue_free()
	for frame in 8: await process_frame
	camera.queue_free()
	await process_frame
	print("MODULAR_RENDER ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
