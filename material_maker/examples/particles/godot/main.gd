extends Node3D

func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(8, 7, 14)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.vertex_color_use_as_albedo = true
	mesh.material = draw
	var emitters: Array[GPUParticles3D] = []
	for index in 3:
		var example: String = ["library_gravity", "collision", "subparticle"][index]
		var particles := GPUParticles3D.new()
		particles.amount = 128
		particles.lifetime = 2
		particles.position.x = (index - 1) * 3.5
		particles.process_material = load("res://" + example + ".tres")
		particles.draw_pass_1 = mesh
		particles.visibility_aabb = AABB(Vector3(-4, -5, -4), Vector3(8, 12, 8))
		add_child(particles)
		emitters.append(particles)
		var label := Label3D.new()
		label.text = example.capitalize()
		label.no_depth_test = true
		label.position = Vector3(particles.position.x, -1.7, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	var collider := GPUParticlesCollisionBox3D.new()
	collider.position = Vector3(0, -0.7, 0)
	collider.size = Vector3(3, 0.4, 4)
	add_child(collider)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = collider.size
	floor_mesh.mesh = box
	floor_mesh.position = collider.position
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.albedo_color = Color(0.2, 0.25, 0.35)
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	var child := GPUParticles3D.new()
	child.amount = 512
	child.lifetime = 2
	child.emitting = false
	child.draw_pass_1 = mesh
	child.visibility_aabb = emitters[2].visibility_aabb
	var child_shader := Shader.new()
	child_shader.code = "shader_type particles; void start() { COLOR = vec4(1.0, 0.7, 0.15, 1.0); float a = float(NUMBER) * 2.399963; VELOCITY = vec3(cos(a), 2.0, sin(a)); } void process() { VELOCITY.y -= 3.0 * DELTA; }"
	var child_material := ShaderMaterial.new()
	child_material.shader = child_shader
	child.process_material = child_material
	add_child(child)
	emitters[2].sub_emitter = emitters[2].get_path_to(child)
	for frame in 5: await get_tree().process_frame
	for particles in emitters: particles.restart()
