extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
const Particles = preload("res://addons/mm_gpu_particles/particles_2d.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
func respawn(node) -> void:
	for frame in 180:
		await process_frame
		if node.ready_for_simulation: break
	check(node.ready_for_simulation,"reparent rebuild ready")
	node.emit_burst(1)
	node.advance(1.0/60.0)
	await settle()
func snapshot(node) -> Dictionary:
	var result := {}
	var state = node._gpu
	RenderingServer.call_on_render_thread(func():
		result.instances = state.rd.buffer_get_data(RenderingServer.multimesh_get_buffer_rd_rid(state.multimesh.get_rid()))
		result.attributes = state.rd.buffer_get_data(state.owned_buffers[0])
		result.done = true)
	while not result.has("done"): await process_frame
	return result
func run() -> void:
	var doc := Fixtures.basic()
	doc.emitter.rate = 0.0
	doc.emitter.lifetime = 100.0
	doc.renderer.quad_size = 0.4
	doc.user_parameters = [{"id":"speed","name":"Speed","type":"float","default":0.0}]
	doc.stages.spawn[0].input_bindings = {"speed":{"kind":"user","id":"speed"}}
	var compiled := Compiler.new().compile(doc)
	check(compiled.errors.is_empty(),"compile")
	if compiled.effect == null:
		quit(1)
		return
	var particles := Particles.new()
	particles.effect = compiled.effect
	particles.manual_processing = true
	particles.capacity = 7
	particles.position = Vector2(64,64)
	root.add_child(particles)
	for i in 180:
		await process_frame
		if particles.ready_for_simulation or not particles.error_text.is_empty(): break
	check(particles.ready_for_simulation,"2D ready: "+particles.error_text)
	if not particles.ready_for_simulation:
		particles.queue_free()
		await settle()
		quit(1)
		return
	check(not particles.set_parameter("spawn1/speed",5.0),"User-bound input cannot be shadowed")
	check(particles.set_user_parameter("User.Speed",0.0),"set User")
	check(not particles.set_user_parameter("User.Speed",Vector2.ONE),"reject wrong User type")
	check(particles._get_property_list().any(func(p): return p.name == "user_parameters/Speed"),"dynamic Inspector")
	check(particles._property_get_revert("user_parameters/Speed") == 0.0,"Inspector revert")
	particles.emit_burst(1)
	particles.advance(1.0/60.0)
	await settle()
	var before := await snapshot(particles)
	check(before.instances.decode_float(44) == 1.0,"live output")
	var image := root.get_texture().get_image()
	check(image.get_pixel(64,64).r > 0.8,"visible Canvas pixels")
	particles.position = Vector2(32,64)
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(32,64).r > 0.8 and image.get_pixel(64,64).r < 0.1,"Local follows movement")
	particles.position = Vector2(64,64)
	var parent := Node2D.new()
	parent.position = Vector2(16,0)
	root.add_child(parent)
	particles.reparent(parent,false)
	await respawn(particles)
	image = root.get_texture().get_image()
	check(image.get_pixel(80,64).r > 0.8 and image.get_pixel(46,64).r < 0.1,"Local inherits parent transform")
	particles.reparent(root,false)
	await respawn(particles)
	parent.queue_free()
	var camera := Camera2D.new()
	camera.position = Vector2(64,64)
	camera.zoom = Vector2(2,2)
	root.add_child(camera)
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(30,64).r > 0.8,"Camera2D zoom")
	camera.queue_free()
	await settle()
	var layer := CanvasLayer.new()
	layer.offset = Vector2(12,0)
	root.add_child(layer)
	particles.reparent(layer,false)
	await respawn(particles)
	image = root.get_texture().get_image()
	check(image.get_pixel(76,64).r > 0.8 and image.get_pixel(46,64).r < 0.1,"CanvasLayer transform")
	particles.reparent(root,false)
	await respawn(particles)
	layer.queue_free()
	particles.draw_material = Particles.create_material({"mode":"alpha","round_quad":true})
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(64,64).r > 0.8 and image.get_pixel(45,45).r < 0.1,"soft round quad")
	var custom := ShaderMaterial.new()
	custom.shader = Shader.new()
	custom.shader.code = "shader_type canvas_item; render_mode unshaded; void fragment(){COLOR=vec4(0,1,0,1);}"
	particles.draw_material = custom
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(64,64).g > 0.8 and image.get_pixel(64,64).r < 0.1,"custom Canvas shader")
	particles.draw_material = null
	particles.visibility_rect = Rect2(10000,10000,1,1)
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(64,64).r < 0.1,"manual visibility bounds cull")
	particles.visibility_rect = Rect2(-10000,-10000,20000,20000)
	await settle()
	particles.pause()
	var time: float = particles.clock.time
	particles.advance(0.1)
	check(particles.clock.time == time,"pause")
	particles.pixels_per_unit = 50
	await settle()
	var after := await snapshot(particles)
	check(after.attributes == before.attributes,"projection does not simulate")
	check(after.instances.decode_float(0) == 50.0,"projection changes while paused")
	particles.pixels_per_unit = 0
	await settle()
	check(not particles._draw.visible and not particles.error_text.is_empty(),"invalid scale hides with diagnostic")
	particles.pixels_per_unit = 100
	await settle()
	check(particles._draw.visible and particles.error_text.is_empty(),"valid scale recovers")
	particles.draw_material = StandardMaterial3D.new()
	await settle()
	check(not particles._draw.visible and particles.error_text.contains("CanvasItem"),"3D draw material rejected")
	particles.draw_material = null
	# Asymmetric sprite proves native top-left UVs and image alpha.
	var sprite := Image.create(2,2,false,Image.FORMAT_RGBA8)
	sprite.set_pixel(0,0,Color.RED)
	sprite.set_pixel(1,0,Color.GREEN)
	sprite.set_pixel(0,1,Color.BLUE)
	sprite.set_pixel(1,1,Color.TRANSPARENT)
	particles.texture = ImageTexture.create_from_image(sprite)
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.blend_mode = 1
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(54,54).r > 0.8 and image.get_pixel(54,54).g < 0.1,"sprite top-left red")
	check(image.get_pixel(74,54).g > 0.8,"sprite top-right green")
	check(image.get_pixel(54,74).b > 0.8,"sprite bottom-left blue")
	check(image.get_pixel(74,74).r < 0.1,"sprite transparent corner")
	particles.self_modulate = Color(0.25,1,1,1)
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(54,54).r < 0.6,"self_modulate forwarded")
	particles.self_modulate = Color.WHITE
	var translucent := Image.create(2,2,false,Image.FORMAT_RGBA8)
	translucent.fill(Color(1,0,0,0.25))
	particles.texture = ImageTexture.create_from_image(translucent)
	for mode in [1,2,3,4]:
		particles.blend_mode = mode
		await settle()
		image = root.get_texture().get_image()
		var red := image.get_pixel(64,64).r
		check(red < 0.1 if mode == 4 else red > 0.9 if mode == 3 else red > 0.15 and red < 0.8,"blend mode "+str(mode))
	var overlay := ColorRect.new()
	overlay.position = Vector2(44,44)
	overlay.size = Vector2(40,40)
	overlay.color = Color.GREEN
	root.add_child(overlay)
	particles.blend_mode = 3
	particles.z_index = 1
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(64,64).r > 0.9,"z_index above Canvas sibling")
	particles.z_index = -1
	await settle()
	image = root.get_texture().get_image()
	check(image.get_pixel(64,64).g > 0.9,"z_index below Canvas sibling")
	overlay.queue_free()
	particles.z_index = 0
	particles.texture = null
	particles.blend_mode = 0
	particles.simulation_space = 1
	await settle()
	particles.emit_burst(1)
	particles.advance(1.0/60.0)
	await settle()
	particles.pause()
	before = await snapshot(particles)
	particles.position = Vector2(87,79)
	particles.rotation = 0.2
	particles.scale = Vector2(1.5,0.8)
	await settle()
	after = await snapshot(particles)
	check(before.attributes == after.attributes,"World motion while paused preserves state")
	var local := Vector2(after.instances.decode_float(12),after.instances.decode_float(28))
	check((particles.global_transform*local).distance_to(Vector2(64,64)) < 0.001,"World position survives node transform")
	particles.transform = Transform2D(Vector2(1,1),Vector2(1,1),particles.position)
	await settle()
	check(not particles._draw.visible and particles.error_text.contains("invertible"),"singular World transform rejected")
	particles.transform = Transform2D(0.0,particles.position)
	await settle()
	check(particles._draw.visible and particles.error_text.is_empty(),"World recovers")
	var second := Particles.new()
	second.effect = particles.effect
	second.set_user_parameter("User.Speed",7.0)
	check(particles.get_user_parameter("User.Speed") == 0.0,"shared effect override independence")
	check(second.get_user_parameter("User.Speed") == 7.0,"second override")
	second.reset_user_parameter("User.Speed")
	check(second.get_user_parameter("User.Speed") == 0.0,"reset User")
	second.set_user_parameter("User.Speed",3.0)
	var packed := PackedScene.new()
	check(packed.pack(second) == OK,"pack Inspector overrides")
	var clone = packed.instantiate()
	check(clone.get_user_parameter("User.Speed") == 3.0,"stable-ID serialized override")
	clone.free()
	second.free()
	particles.queue_free()
	await settle()
	print("MODULAR_RUNTIME_2D ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	quit(0 if failures == 0 else 1)
