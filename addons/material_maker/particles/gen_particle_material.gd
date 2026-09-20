@tool
extends MMGenMaterial
class_name MMGenParticleMaterial

const Interface = preload("interface.gd")
var particle_defaults: Dictionary = {}

func _ready() -> void:
	MMGenParticle.register_types()

func get_type() -> String:
	return "particle_export"

func get_type_name() -> String:
	return "Start Output"

func get_description() -> String:
	return "Godot particle shader export. Shared render modes and resource project are configured here."

func model_data() -> Dictionary:
	return {"id": "g" + str(get_instance_id()), "kind": "output", "stage": "start", "inputs": particle_defaults.duplicate(true)}

func particle_ports() -> Dictionary:
	return Interface.ports(model_data(), "start")

func get_input_defs() -> Array:
	var result: Array = []
	for port in particle_ports().inputs:
		result.append({"name": port.name, "label": port.name, "type": MMGenParticle.value_type(port.type), "shader_type": port.type})
	return result

func get_output_defs(_show_hidden: bool = false) -> Array:
	return []

func get_parameter_defs() -> Array:
	var result: Array = []
	for mode in Interface.MODES:
		result.append({"name": mode, "label": mode, "type": "boolean", "default": false})
	result.append({"name": "target_project", "label": "Godot project directory", "type": "string", "default": ""})
	return result

func particle_configuration() -> Dictionary:
	var modes: Array = []
	for mode in Interface.MODES:
		if parameters.get(mode, false): modes.append(mode)
	return {"render_modes": modes, "target_project": str(parameters.get("target_project", "")).replace("\\", "/")}

func compile_shader() -> Dictionary:
	return load("res://addons/material_maker/particles/graph_compiler.gd").new().compile_graph(get_parent())

func get_export_profiles() -> Array:
	return ["Godot 4/Particles"]

func get_export_extension(_profile: String) -> String:
	return "tres"

func export_material(prefix: String, profile: String, _size: int = 0, _command_line: bool = false) -> void:
	export_last_target = profile
	export_paths[profile] = prefix
	var result: Dictionary = await load("res://addons/material_maker/particles/graph_exporter.gd").export_graph(get_parent(), prefix)
	if not result.errors.is_empty():
		var messages: PackedStringArray = []
		for error in result.errors:
			messages.append("%s / %s: %s" % [error.stage, error.node, error.message])
		if mm_globals.main_window != null:
			var dialog := AcceptDialog.new()
			dialog.title = "Particle shader export failed"
			dialog.dialog_text = "\n".join(messages)
			mm_globals.main_window.add_child(dialog)
			dialog.popup_centered(Vector2i(850, 400))
			dialog.confirmed.connect(dialog.queue_free)
		else: push_error("\n".join(messages))

func update() -> void:
	pass

func update_shaders() -> void:
	pass

func set_3d_previews(previews: Dictionary[Node, Array]) -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(0.1); }"
	for preview in previews:
		for material in previews[preview]:
			if material is ShaderMaterial: material.shader = shader


func _serialize(data: Dictionary) -> Dictionary:
	data.type = "particle_export"
	data.particle_defaults = particle_defaults
	data.export = {"last_target": export_last_target, "paths": export_paths}
	return data

func _deserialize(data: Dictionary) -> void:
	particle_defaults = data.get("particle_defaults", {}).duplicate(true)
	var saved: Dictionary = data.get("export", {})
	export_last_target = saved.get("last_target", "")
	export_paths = saved.get("paths", {})

func edit(_node, _tab: String = "") -> void:
	var result := compile_shader()
	var dialog := AcceptDialog.new()
	dialog.title = "Generated particle shader"
	var code := CodeEdit.new()
	code.text = result.code
	code.editable = false
	code.custom_minimum_size = Vector2(850, 600)
	dialog.add_child(code)
	mm_globals.main_window.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
