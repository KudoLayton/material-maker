@tool
extends Node

const TYPE_ALIASES = {"particle_float": "f", "particle_vec3": "rgb", "particle_vec4": "rgba"}

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

func canonical_type(type: String) -> String:
	return TYPE_ALIASES.get(type, type)

func format_port_label(label: String, type: String, shader_type: String = "") -> String:
	var definition: Dictionary = types.get(type, {})
	if shader_type.is_empty(): shader_type = definition.get("particle_type", "")
	return label + " : " + shader_type if not shader_type.is_empty() else label

func complete_output_values(output_type: String, values: Dictionary) -> void:
	if not values.has(output_type): return
	var type := canonical_type(output_type)
	if not types.has(type): return
	if not values.has(type): values[type] = values[output_type]
	for conversion in types[type].get("convert", []):
		if not values.has(conversion.type):
			values[conversion.type] = conversion.expr.replace("$(value)", values[type])
	for alias in TYPE_ALIASES:
		if values.has(TYPE_ALIASES[alias]) and not values.has(alias):
			values[alias] = values[TYPE_ALIASES[alias]]
