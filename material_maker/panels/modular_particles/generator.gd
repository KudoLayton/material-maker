@tool
extends MMGenParticle
## Named module inputs/attributes and output sink, hosted by the existing MM canvas.
const Presentation = preload("res://addons/material_maker/particles/modular/presentation.gd")
# Transient UI metadata: deliberately absent from settings/model_data/_serialize.
var display_context: Dictionary = {}

func set_display_context(value: Dictionary) -> void:
	display_context = value

func binding_description(kind: String, id: String, label: String, type: String) -> Dictionary:
	return Presentation.describe(kind,id,label,type,display_context)

func get_type() -> String:
	return "modular_particle"

func get_type_name() -> String:
	if settings.get("kind") == "module_output": return "Module Output (Write)"
	var info := binding_description(settings.get("kind",""),settings.get("id",""),settings.get("label",""),settings.get("data_type",""))
	return "Read " + info.display

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

func port_defs(side: String) -> Array:
	# The base class synthesizes labels from port IDs; only this modular adapter
	# decorates them. Compilation still uses the unchanged particle_ports().
	var result: Array = []
	for port in particle_ports()[side]:
		var info: Dictionary
		if side == "inputs": info = binding_description("module_output",port.name,port.get("label",port.name),port.type)
		else: info = binding_description(settings.kind,settings.get("id",""),settings.get("label",""),port.type)
		result.append({"name":port.name,"label":("Write " if side == "inputs" else "") + info.display,
			"type":value_type(port.type),"shader_type":port.type,"tooltip":info.tooltip})
	return result

func get_parameter_defs() -> Array:
	return []

func get_description() -> String:
	if settings.get("kind") == "module_output":
		return "Module Output (Write). Each port targets the displayed Attribute ID. Unconnected ports preserve the existing value; namespace does not change on write."
	return binding_description(settings.get("kind",""),settings.get("id",""),settings.get("label",""),settings.get("data_type","")).tooltip

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
