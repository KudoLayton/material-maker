extends HBoxContainer


const PANELS = [
	{ name="Library", scene=preload("res://material_maker/panels/library/library.tscn"), position="TopLeft" },
	{ name="Preview2D", scene=preload("res://material_maker/panels/preview_2d/preview_2d_panel.tscn"), position="TopRight" , parameters={preview_mode=1} },
	{ name="Preview3D", scene=preload("res://material_maker/panels/preview_3d/preview_3d_panel.tscn"), position="BottomLeft" },
	{ name="Preview2D (2)", scene=preload("res://material_maker/panels/preview_2d/preview_2d_panel.tscn"), position="BottomRight", parameters={preview_mode=2} },
	{ name="Histogram", scene=preload("res://material_maker/widgets/histogram/histogram.tscn"), position="BottomRight" },
	{ name="Hierarchy", scene=preload("res://material_maker/panels/hierarchy/hierarchy_panel.tscn"), position="TopRight"},
	{ name="Reference", scene=preload("res://material_maker/panels/reference/reference_panel.tscn"), position="BottomLeft"},
	{ name="Brushes", scene=preload("res://material_maker/panels/brushes/brushes.tscn"), position="TopLeft" },
	{ name="Layers", scene=preload("res://material_maker/panels/layers/layers.tscn"), position="BottomRight" },
	{ name="Parameters", scene=preload("res://material_maker/panels/parameters/parameters.tscn"), position="TopRight" },
]

var default_material_layout := {
	&"main": { &"type": "FlexTop", &"w": 1900.0, &"h": 939.0, &"children": [
		{ &"type": "FlexSplit", &"w": 1900.0, &"h": 939.0, &"children": [
			{ &"type": "FlexTab", &"w": 373.0, &"h": 939.0, &"children": [], &"tabs": [
				&"Library", &"Hierarchy"], &"current": 0 },
			{ &"type": "FlexMain", &"w": 1073.0, &"h": 939.0, &"children": [] },
			{ &"type": "FlexSplit", &"w": 434.0, &"h": 939.0, &"children": [
				{ &"type": "FlexTab", &"w": 434.0, &"h": 501.0, &"children": [], &"tabs": [
					&"Preview2D", &"Histogram"], &"current": 0 },
				{ &"type": "FlexTab", &"w": 434.0, &"h": 427.0, &"children": [], &"tabs": [
					&"Preview3D", &"Preview2D (2)", &"Reference"], &"current": 0 }
			], &"dir": "v" }], &"dir": "h" }]}, &"windows": [] }

var default_particle_layout := {
	&"main": { &"type": "FlexTop", &"w": 1440.0, &"h": 900.0, &"children": [
		{ &"type": "FlexSplit", &"dir": "h", &"w": 1440.0, &"h": 900.0, &"children": [
			{ &"type": "FlexSplit", &"dir": "v", &"w": 280.0, &"h": 900.0, &"children": [
				{ &"type": "FlexTab", &"w": 280.0, &"h": 460.0, &"children": [], &"tabs": [&"Module Inputs", &"Library", &"Hierarchy"], &"current": 0 },
				{ &"type": "FlexTab", &"w": 280.0, &"h": 440.0, &"children": [], &"tabs": [&"User Parameters", &"Attributes"], &"current": 0 }
			] },
			{ &"type": "FlexMain", &"w": 860.0, &"h": 900.0, &"children": [] },
			{ &"type": "FlexSplit", &"dir": "v", &"w": 300.0, &"h": 900.0, &"children": [
				{ &"type": "FlexTab", &"w": 300.0, &"h": 440.0, &"children": [], &"tabs": [&"Module Stack"], &"current": 0 },
				{ &"type": "FlexTab", &"w": 300.0, &"h": 460.0, &"children": [], &"tabs": [&"Particle Preview"], &"current": 0 }
			] }
		] }
	]}, &"windows": [] }

var default_paint_layout : Dictionary = { main={ children=[ { children=[ { children=[], current=0, h=766.0, tabs=["Brushes"], type="FlexTab", w=279.0 }, { children=[], h=766.0, type="FlexMain", w=844.0 }, { children=[ { children=[], current=0, h=370.0, tabs=["Parameters"], type="FlexTab", w=240.0 }, { children=[], current=0, h=386.0, tabs=["Layers"], type="FlexTab", w=240.0 }], dir="v", h=766.0, type="FlexSplit", w=240.0 }], dir="h", h=766.0, type="FlexSplit", w=1383.0 }], h=766.0, type="FlexTop", w=1383.0 }, windows=[] }

const HIDE_PANELS : Dictionary[String, Array] = {
	"material": [ "Brushes", "Layers", "Parameters" ],
	"paint": [ "Preview3D", "Histogram", "Hierarchy" ],
	"particle": [ "Preview2D", "Preview2D (2)", "Preview3D", "Histogram", "Brushes", "Layers", "Parameters", "Reference" ]
}


var panels = {}
var previous_width : float
var current_mode : String = "material"
var layout : Dictionary = {}

var presets : Array[Dictionary]
var previous_layout : Dictionary


func _ready() -> void:
	previous_width = size.x

func toggle_side_panels() -> void:
	if not previous_layout.is_empty():
		$FlexibleLayout.init(previous_layout)
		previous_layout.clear()
	else:
		var main_layout : Dictionary = {
			&"main": { &"type": "FlexTop",&"w": 1073.0, &"h": 939.0,
				&"children": [{ &"type": "FlexMain", &"w": 1073.0, &"h": 939.0, &"children": [] }] }, &"windows": [] }
		previous_layout = $FlexibleLayout.serialize()
		$FlexibleLayout.init(main_layout)

func load_panels() -> void:
	# Create panels
	for panel in PANELS:
		var node : Node = panel.scene.instantiate()
		node.name = panel.name
		if panel.has("parameters"):
			for p in panel.parameters.keys():
				node.set(p, panel.parameters[p])
		panels[panel.name] = node
		$FlexibleLayout.add(panel.name, node)

	for mode in [ "material", "paint", "particle" ]:
		if mm_globals.config.has_section_key("layout", mode):
			layout[mode] = JSON.parse_string(mm_globals.config.get_value("layout", mode))
		elif mode == "material":
			layout[mode] = default_material_layout
		elif mode == "paint":
			layout[mode] = default_paint_layout
		elif mode == "particle":
			layout[mode] = default_particle_layout
	for title in ["Module Inputs", "User Parameters", "Attributes", "Module Stack", "Particle Preview"]:
		var dock = preload("res://material_maker/panels/modular_particles/dock.gd").new()
		dock.name = title
		panels[title] = dock
		$FlexibleLayout.add(title,dock)
	$FlexibleLayout.init(layout[current_mode] if layout.has(current_mode) else null)

	# Restore layout presets
	var preset_keys : PackedStringArray
	if mm_globals.config.has_section("layout_presets"):
		preset_keys = mm_globals.config.get_section_keys("layout_presets")
	for preset in preset_keys:
		presets.push_back({
			"name": preset,
			"preset": JSON.parse_string(
					mm_globals.config.get_value("layout_presets", preset))
		})

func save_config() -> void:
	layout[current_mode] = $FlexibleLayout.serialize()
	if not previous_layout.is_empty():
		layout[current_mode] = previous_layout
	for mode in [ "material", "paint", "particle" ]:
		if layout.has(mode):
			mm_globals.config.set_value("layout", mode, JSON.stringify(layout[mode]))

	# Save layout presets
	if mm_globals.config.has_section("layout_presets"):
		mm_globals.config.erase_section("layout_presets")
	for preset in presets:
		mm_globals.config.set_value("layout_presets",
			preset.name, JSON.stringify(preset.preset))


func get_panel(n) -> Control:
	if panels.has(n):
		return panels[n]
	return Control.new()

func get_panel_list() -> Array:
	var panels_list = panels.keys()
	panels_list.sort()
	return panels_list

func is_panel_visible(panel_name : String) -> bool:
	return $FlexibleLayout.flex_layout.is_panel_shown(panel_name)

func set_panel_visible(panel_name : String, v : bool) -> void:
	previous_layout.clear()
	$FlexibleLayout.show_panel(panel_name, v)
	$FlexibleLayout.layout()

func bind_particle_editor(editor: Control) -> void:
	for title in ["Module Inputs", "User Parameters", "Attributes", "Module Stack", "Particle Preview"]:
		var dock = panels.get(title)
		if dock == null: continue
		var content: Control = editor.particle_panes.get(title) if is_instance_valid(editor) else null
		dock.show_editor(content,editor.pane_home if is_instance_valid(editor) else null)

func change_mode(m : String) -> void:
	if m == current_mode:
		return
	layout[current_mode] = $FlexibleLayout.serialize()
	current_mode = m
	if layout.has(current_mode):
		$FlexibleLayout.init(layout[current_mode])

func _on_tab_changed(_tab):
	pass

func reset_panels() -> void:
	if current_mode == "material":
		$FlexibleLayout.init(default_material_layout)
	elif current_mode == "paint":
		$FlexibleLayout.init(default_paint_layout)
	elif current_mode == "particle":
		$FlexibleLayout.init(default_particle_layout)
	owner.view_center()
