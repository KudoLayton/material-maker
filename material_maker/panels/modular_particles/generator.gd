@tool
extends MMGenParticle
## Named module inputs/attributes and output sink, hosted by the existing MM canvas.

func get_type() -> String:
	return "modular_particle"

func get_type_name() -> String:
	return {"module_read":"Read Attribute", "module_parameter":"Module Input", "module_output":"Module Output", "module_context":"Simulation Context"}.get(settings.get("kind"), "Module") + (": " + str(settings.get("label", settings.get("id", ""))) if settings.has("id") else "")

func can_be_deleted() -> bool:
	return settings.get("kind") != "module_output"

func model_data() -> Dictionary:
	var model := settings.duplicate(true)
	model.id = "g" + str(get_instance_id())
	model.inputs = {}
	return model

func particle_ports() -> Dictionary:
	var inputs: Array = []
	var outputs: Array = []
	if settings.kind == "module_output":
		for field in settings.get("fields", []): inputs.append({"name":field.id,"label":field.name,"type":field.type})
	else:
		outputs.append({"name":"value","type":settings.get("data_type", "float")})
	return {"inputs":inputs,"outputs":outputs}

func get_parameter_defs() -> Array:
	return []

func get_description() -> String:
	return "Stable-ID module binding. Configure attributes and module inputs in the module stack panel. Unconnected outputs preserve the current value."

func _serialize(data: Dictionary) -> Dictionary:
	data.type = get_type()
	data.settings = settings.duplicate(true)
	return data

func _get_shader_code(uv: String, output_index: int, context: MMGenContext) -> ShaderCode:
	if context.particle_compiler != null:
		return context.particle_compiler.generate_value(self, output_index, uv, context)
	var code := ShaderCode.new()
	code.error = "Module bindings require a modular particle evaluation context"
	return code
