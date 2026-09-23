extends VBoxContainer
## Same camera controller and EnvironmentManager as Material Maker's 3D preview.
const Controller = preload("res://material_maker/windows/environment_editor/camera_controller.tscn")
const CLEAR_SETTING := "3D_preview_panel_clear_background"
var viewport: SubViewport
var scene: Node3D
var camera: Camera3D
var controller: Node3D
var container: TextureRect
var world: WorldEnvironment
var sun: DirectionalLight3D
var environments: OptionButton
var clear_button: CheckBox
var reset_button: Button
var manager: Node
var current_environment := 0
var clear_background := false
var _environment_revision := 0

func setup(editor: Node) -> void:
	name = "ParticlePreviewContents"
	manager = get_node("/root/MainWindow/EnvironmentManager")
	current_environment = int(mm_globals.get_config("ui_3d_preview_environment"))
	clear_background = bool(mm_globals.get_config(CLEAR_SETTING)) if mm_globals.has_config(CLEAR_SETTING) else false
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	environments = OptionButton.new()
	environments.fit_to_longest_item = false
	environments.custom_minimum_size.x = 110
	environments.tooltip_text = "Material Maker environment presets"
	toolbar.add_child(environments)
	environments.item_selected.connect(func(index):
		mm_globals.set_config("ui_3d_preview_environment",index)
		set_environment(index))
	reset_button = Button.new()
	reset_button.text = "Reset View"
	reset_button.pressed.connect(reset_view)
	toolbar.add_child(reset_button)
	clear_button = CheckBox.new()
	clear_button.text = "Clear Background"
	clear_button.set_pressed_no_signal(clear_background)
	clear_button.toggled.connect(func(value):
		clear_background = value
		mm_globals.set_config(CLEAR_SETTING,value)
		set_environment(current_environment))
	toolbar.add_child(clear_button)
	container = TextureRect.new()
	container.custom_minimum_size.y = 100
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.stretch_mode = TextureRect.STRETCH_SCALE
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.tooltip_text = "MMB / Alt+LMB: orbit; Shift+drag: pan; wheel: zoom; Ctrl+wheel: FOV"
	container.gui_input.connect(on_gui_input)
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	# Keep GPU/world nodes in the project tab, not inside reparented dock UI.
	# Removing a SubViewport from the tree retires the live particle buffers.
	editor.add_child(viewport)
	container.texture = viewport.get_texture()
	container.resized.connect(func(): viewport.size = Vector2i(container.size).max(Vector2i(2,2)))
	scene = Node3D.new()
	viewport.add_child(scene)
	world = WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	scene.add_child(world)
	sun = DirectionalLight3D.new()
	scene.add_child(sun)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	scene.add_child(camera)
	controller = Controller.instantiate()
	controller.camera_path = NodePath("../Camera3D")
	controller.capture_mouse = false
	scene.add_child(controller)
	reset_view()
	manager.environment_updated.connect(environment_updated)
	manager.name_updated.connect(func(_index,_text): refresh_environments())
	refresh_environments()
	set_environment(current_environment)

func refresh_environments() -> void:
	environments.clear()
	for item in manager.get_environment_list(): environments.add_item(item.name)
	if environments.item_count > 0:
		current_environment = clampi(current_environment,0,environments.item_count-1)
		environments.select(current_environment)

func environment_updated(index: int) -> void:
	refresh_environments()
	if index == current_environment: set_environment(index)

func locally_available(index: int) -> bool:
	if index < 0 or index >= manager.environments.size(): return false
	if manager.environment_textures[index].has("hdri"): return true
	var file: String = str(manager.environments[index].get("hdri_url","")).get_file()
	if file.is_empty(): return false
	for directory in [manager.base_dir+"/environments/hdris","res://material_maker/environments/hdris","user://hdris"]:
		if FileAccess.file_exists(directory.path_join(file)): return true
	return false

func set_environment(index: int) -> void:
	_environment_revision += 1
	var revision := _environment_revision
	current_environment = index
	if index >= 0 and index < environments.item_count: environments.select(index)
	var selected := index
	if not locally_available(selected): selected = 0
	var environment := Environment.new()
	# Never block this editor on a missing custom HDRI/download. Fall back to
	# a bundled preset, or a procedural sky if the installation is incomplete.
	if locally_available(selected):
		await manager.apply_environment(selected,environment,sun,Color.TRANSPARENT,clear_background)
	else:
		environment.sky = Sky.new()
		environment.sky.sky_material = ProceduralSkyMaterial.new()
		environment.background_mode = Environment.BG_COLOR if clear_background else Environment.BG_SKY
		environment.background_color = Color.TRANSPARENT
		sun.light_energy = 1.0
	if revision != _environment_revision or not is_inside_tree(): return
	world.environment = environment
	viewport.transparent_bg = clear_background

func reset_view() -> void:
	controller.position = Vector3.ZERO
	controller.camera_rotation1.rotation = Vector3.ZERO
	controller.camera_rotation2.rotation = Vector3(-PI/4,0,0)
	controller.camera_position.position = Vector3(0,0,4)
	camera.fov = 70

func on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed: return
	if event is InputEventMouseButton and event.is_command_or_control_pressed() and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		camera.fov = clampf(camera.fov+(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1),10,90)
		container.accept_event()
	elif controller.process_event(event,container.get_viewport()):
		controller.camera_position.position.z = clampf(controller.camera_position.position.z,0.5,150)
		container.accept_event()
