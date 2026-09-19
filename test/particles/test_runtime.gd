extends SceneTree

const Document = preload("res://addons/material_maker/particles/document.gd")
const Compiler = preload("res://addons/material_maker/particles/compiler.gd")
const Exporter = preload("res://addons/material_maker/particles/exporter.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://exported")
	for name in ["blank", "gravity", "collision", "subparticle"]:
		var doc = Document.load_file("res://material_maker/examples/particles/" + name + ".ptex")
		var result = Exporter.export_files(doc, "res://exported/" + name)
		check(result.errors.is_empty(), "Export example: " + name + str(result.errors))
		check(load("res://exported/" + name + ".tres") is ShaderMaterial, "Load exported material: " + name)
	var doc = Document.create()
	doc.render_modes = ["disable_velocity", "disable_force", "keep_data"]
	var start: Dictionary = Document.node(doc.stages.start, "output").inputs
	start.CUSTOM = {"value": [0.25, 0.5, 0.75, 1.0]}
	start.VELOCITY = {"value": [1, 2, 3]}
	start.MASS = {"value": 3.0}
	start.TRANSFORM = {"value": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]}
	var arguments := {}
	var ports: Array = []
	var conditions: Array[String] = []
	for index in range(1, 7):
		var builtin := "USERDATA" + str(index)
		start[builtin] = {"value": [index, 2, 3, 4]}
		var id := "userdata_" + str(index)
		doc.stages.process.nodes.append({"id": id, "kind": "input", "builtin": builtin, "inputs": {}})
		arguments[id] = {"node": id, "port": "value"}
		ports.append({"name": id, "type": "vec4"})
		conditions.append(id + ".x == " + str(index) + ".0")
	for item in [["CUSTOM", "vec4", "custom_data", "custom_data.z == 0.75"], ["VELOCITY", "vec3", "velocity", "velocity.y == 2.0"], ["MASS", "float", "mass", "mass == 7.0"], ["TRANSFORM", "mat4", "transform", "transform[3].w == 1.0"]]:
		doc.stages.process.nodes.append({"id": item[2], "kind": "input", "builtin": item[0], "inputs": {}})
		arguments[item[2]] = {"node": item[2], "port": "value"}
		ports.append({"name": item[2], "type": item[1]})
		conditions.append(item[3])
	doc.stages.process.nodes.append({"id": "set_mass", "kind": "set", "builtin": "MASS", "inputs": {"exec": {"node": "entry", "port": "next"}, "value": {"value": 7.0}}})
	doc.stages.process.nodes.append({"id": "verify", "kind": "custom", "data_type": "vec4", "inputs": arguments, "input_ports": ports, "code": "return (" + " && ".join(conditions) + ") ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);"})
	var output: Dictionary = Document.node(doc.stages.process, "output").inputs
	output.exec = {"node": "set_mass", "port": "next"}
	output.COLOR = {"node": "verify", "port": "value"}
	await render_probe(doc, false, "state_and_order")
	var collision = Document.create()
	collision.render_modes = ["disable_velocity", "collision_use_scale"]
	Document.node(collision.stages.start, "output").inputs.COLOR = {"value": [1, 0, 0, 1]}
	collision.stages.process.nodes.append({"id": "hit", "kind": "input", "builtin": "COLLIDED", "inputs": {}})
	collision.stages.process.nodes.append({"id": "color", "kind": "select", "data_type": "vec4", "inputs": {"condition": {"node": "hit", "port": "value"}, "true": {"value": [0, 1, 0, 1]}, "false": {"value": [1, 0, 0, 1]}}})
	Document.node(collision.stages.process, "output").inputs.COLOR = {"node": "color", "port": "value"}
	await render_probe(collision, true, "collision")
	var emission = Document.load_file("res://material_maker/examples/particles/subparticle.ptex")
	Document.node(emission.stages.start, "emit_child").inputs.flags = {"value": 3}
	Document.node(emission.stages.start, "emit_child").inputs.transform = {"value": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0.7, 0, 0, 1]]}
	Document.node(emission.stages.start, "output").inputs.TRANSFORM = {"value": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [-0.7, 0, 0, 1]]}
	await render_probe(emission, false, "subparticle", true)
	print("PARTICLE_RUNTIME_TESTS: ", failures)
	quit(0 if failures.is_empty() else 1)

func render_probe(doc: Dictionary, collision: bool, name: String, subparticle := false) -> void:
	var result = Exporter.validate(Compiler.new().compile(doc))
	check(result.errors.is_empty(), name + " compilation")
	if not result.errors.is_empty(): return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	var particles := GPUParticles3D.new()
	particles.amount = 1
	particles.lifetime = 10
	particles.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var shader := Shader.new()
	shader.code = result.code
	var material := ShaderMaterial.new()
	material.shader = shader
	particles.process_material = material
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.vertex_color_use_as_albedo = true
	mesh.material = draw
	particles.draw_pass_1 = mesh
	viewport.add_child(particles)
	if collision:
		var box := GPUParticlesCollisionBox3D.new()
		box.size = Vector3(3, 3, 3)
		viewport.add_child(box)
	if subparticle:
		var child := GPUParticles3D.new()
		child.amount = 16
		child.lifetime = 10
		child.emitting = false
		child.visibility_aabb = particles.visibility_aabb
		child.draw_pass_1 = mesh
		var child_shader := Shader.new()
		child_shader.code = "shader_type particles; void start() { COLOR = vec4(0.0, 0.0, 1.0, 1.0); }"
		var child_material := ShaderMaterial.new()
		child_material.shader = child_shader
		child.process_material = child_material
		viewport.add_child(child)
		particles.sub_emitter = particles.get_path_to(child)
		for frame in 5: await process_frame
	particles.restart()
	for frame in 30: await process_frame
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	image.save_png("res://exported/" + name + ".png")
	var green := 0
	var red := 0
	var blue := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel = image.get_pixel(x, y)
			if pixel.g > 0.6 and pixel.r < 0.2: green += 1
			if pixel.b > 0.6 and pixel.r < 0.2 and pixel.g < 0.2: blue += 1
			if pixel.r > 0.6 and pixel.g < 0.2: red += 1
	check(green > 100 and red == 0, name + ": green=" + str(green) + " red=" + str(red))
	if subparticle: check(blue > 100, "Subparticles are actually emitted: blue=" + str(blue))
	viewport.queue_free()
	await process_frame
