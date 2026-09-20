extends Node

const Preparation = preload("res://addons/material_maker/particles/preview_material.gd")
const Exporter = preload("res://addons/material_maker/particles/exporter.gd")
const BufferState = preload("res://addons/material_maker/engine/dependencies.gd").Buffer

signal status_changed

var generator: MMGenParticleMaterial
var particles := GPUParticles3D.new()
var mesh := QuadMesh.new()
var preview: Control
var timer := Timer.new()
var paused := false
var error_text := ""
var restart_count := 0
var request_revision := 0
var building := false
var last_signature := 0
var textures: Dictionary = {}
var texture_versions: Dictionary = {}

func _ready() -> void:
	timer.one_shot = true
	timer.wait_time = 0.2
	timer.timeout.connect(refresh)
	add_child(timer)
	particles.visible = false
	particles.emitting = false
	particles.amount = 128
	particles.lifetime = 2.0
	particles.fixed_fps = 60
	particles.use_fixed_seed = true
	particles.seed = 0
	particles.visibility_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.size = Vector2(0.1, 0.1)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.billboard_keep_scale = true
	draw.vertex_color_use_as_albedo = true
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = draw
	mm_deps.updated.connect(textures_updated)
	preview.visibility_changed.connect(update_playback)

func _exit_tree() -> void:
	if is_instance_valid(particles): particles.queue_free()

func set_generator(value: MMGenParticleMaterial) -> void:
	generator = value
	schedule_refresh()

func schedule_refresh() -> void:
	request_revision += 1
	if is_inside_tree(): timer.start()

func parameter_changed(_name, _value) -> void:
	schedule_refresh()

func watch(node: Node) -> void:
	if node is MMGenBase and not node.parameter_changed.is_connected(parameter_changed):
		node.parameter_changed.connect(parameter_changed)
	if node is MMGenGraph and not node.graph_changed.is_connected(schedule_refresh):
		node.graph_changed.connect(schedule_refresh)
	for child in node.get_children(): watch(child)

func textures_updated() -> void:
	if building: return
	for texture in textures.values():
		if not texture is MMTexture: continue
		if texture.texture_needs_update:
			schedule_refresh()
			return
		for buffer in mm_deps.buffers.values():
			if buffer.object is MMGenTexture and buffer.object.texture == texture and (buffer.renders != texture_versions.get(texture, -1) or buffer.status == BufferState.Error):
				schedule_refresh()
				return

func refresh() -> void:
	if building:
		timer.start()
		return
	if not is_instance_valid(generator) or not generator.is_inside_tree(): return
	building = true
	var revision := request_revision
	watch(generator.get_parent())
	var result: Dictionary = generator.compile_shader()
	if result.errors.is_empty():
		textures.clear()
		for name in result.mm_uniforms: textures[name] = result.mm_uniforms[name].value
	result = await Preparation.prepare(result, get_tree())
	building = false
	if not is_inside_tree() or not is_instance_valid(generator) or revision != request_revision: return
	if result.errors.is_empty():
		var signature := Preparation.signature(result)
		if signature != last_signature or particles.process_material == null:
			Exporter.validate(result)
			if result.errors.is_empty():
				var shader := Shader.new()
				shader.code = result.code
				shader.get_shader_uniform_list()
				var material := ShaderMaterial.new()
				material.shader = shader
				for name in result.parameters: material.set_shader_parameter(name, result.parameters[name])
				particles.process_material = material
				last_signature = signature
				restart()
	if result.errors.is_empty(): texture_versions = result.texture_versions
	var messages: PackedStringArray = []
	for error in result.errors: messages.append(str(error.get("node", "")) + ": " + error.message)
	error_text = "\n".join(messages)
	update_playback()
	status_changed.emit()

func restart() -> void:
	if particles.process_material == null: return
	particles.hide()
	particles.draw_pass_1 = null
	if not particles.is_inside_tree(): preview.get_node("MaterialPreview/Preview3d").add_child(particles)
	particles.emitting = true
	particles.restart(true)
	restart_count += 1
	var revision := restart_count
	particles.request_particles_process(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or revision != restart_count: return
	particles.draw_pass_1 = mesh
	particles.show()
	update_playback()

func update_playback() -> void:
	particles.speed_scale = 0.0 if paused or not error_text.is_empty() or not preview.is_visible_in_tree() else 1.0

func set_paused(value: bool) -> void:
	paused = value
	update_playback()
	status_changed.emit()
