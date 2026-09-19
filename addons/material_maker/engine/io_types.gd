@tool
extends Node

var type_names : Array = []
var types : Dictionary = {}

func _ready():
	for p in MMPaths.get_nodes_paths():
		var file : FileAccess = FileAccess.open(p+"/io_types.mmt", FileAccess.READ)
		if file != null:
			var test_json_conv = JSON.new()
			test_json_conv.parse(file.get_as_text())
			var type_list = test_json_conv.get_data()
			file = null
			for t in type_list:
				if t.has("label"):
					type_names.push_back(t.name)
				var c = t.color
				if c is String:
					t.color = Color(c)
				else:
					t.color = Color(c.r, c.g, c.b, c.a)
				file = FileAccess.open(p+"/preview_"+t.name+".gdshader", FileAccess.READ)
				if file != null:
					t.preview = file.get_as_text()
				types[t.name] = t
			MMGenParticle.register_types()
			return
	print("Failed to load io types")

func format_port_label(label: String, type: String) -> String:
	var definition: Dictionary = types.get(type, {})
	if definition.has("particle_type"):
		return label + " : " + definition.particle_type
	return label

func is_particle_function_connection(output_slot: int, input_slot: int) -> bool:
	if input_slot != types.rgb.slot_type: return false
	for type in ["particle_float", "particle_vec3", "particle_vec4"]:
		if types.has(type) and output_slot == types[type].slot_type: return true
	return false
