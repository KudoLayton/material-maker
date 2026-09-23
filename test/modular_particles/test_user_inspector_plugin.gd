@tool
extends EditorPlugin
## Installed only by run_inspector_tests.py in a fresh temporary project.
const Particles = preload("res://addons/mm_gpu_particles/particles_3d.gd")
const Effect = preload("res://addons/mm_gpu_particles/effect.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func _enter_tree() -> void: run.call_deferred()

func frames(count: int = 6) -> void:
	for frame in count: await get_tree().process_frame

func fixture() -> MMParticleEffect:
	var effect := Effect.new()
	effect.format_version = 2
	effect.compute_source = "// Inspector fixture: editor preview intentionally disabled"
	effect.source_hash = effect.compute_source.sha256_text()
	effect.component_count = 1
	effect.attributes = [{"id":"value","name":"Value","type":"float","default":0.0,"offset":0}]
	effect.user_parameters = [
		{"id":"enabled_id","name":"Enabled","type":"bool","default":true},
		{"id":"count_id","name":"Count","type":"int","default":1},
		{"id":"mask_id","name":"Mask","type":"uint","default":0},
		{"id":"strength_id","name":"Strength","type":"float","default":2.0},
		{"id":"uv_id","name":"UV","type":"vec2","default":[0.0,0.0]},
		{"id":"wind_id","name":"Wind","type":"vec3","default":[0.0,0.0,0.0]},
		{"id":"tint_id","name":"Tint","type":"vec4","default":[1.0,1.0,1.0,1.0]}]
	return effect

func property_control(name: String) -> EditorProperty:
	for control in EditorInterface.get_inspector().find_children("*","EditorProperty",true,false):
		if control.get_edited_property() == "user_parameters/"+name: return control
	return null

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event)

func edit_control(name: String, value) -> void:
	var control := property_control(name)
	check(control != null,"native EditorProperty exists: "+name)
	if control == null: return
	EditorInterface.get_inspector().ensure_control_visible(control)
	await frames(2)
	if value is bool:
		var buttons := control.find_children("*","CheckBox",true,false)
		check(buttons.size() == 1,"native bool widget")
		if buttons.size() == 1 and buttons[0].button_pressed != value: click_at(buttons[0].get_global_rect().get_center())
	else:
		var components: Array = []
		if value is Vector2: components = [value.x,value.y]
		elif value is Vector3: components = [value.x,value.y,value.z]
		elif value is Vector4: components = [value.x,value.y,value.z,value.w]
		else: components = [value]
		var spins := control.find_children("*","EditorSpinSlider",true,false)
		check(spins.size() == components.size(),"native numeric widgets: "+name)
		for index in mini(spins.size(),components.size()): spins[index].value = components[index]
	await frames()

func shortcut(shift: bool = false) -> void:
	get_viewport().gui_release_focus()
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_Z
		event.ctrl_pressed = true
		event.shift_pressed = shift
		event.pressed = pressed
		get_viewport().push_input(event)
	await frames()

func run() -> void:
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1500,1000)
	get_tree().root.position = Vector2i(80,80)
	await frames(20)
	check(Engine.is_editor_hint(),"actual editor, not runtime property emulation")
	var effect := fixture()
	check(effect.validation_error().is_empty(),"fixture metadata validates")
	check(ResourceSaver.save(effect,"res://effect.tres") == OK,"save shared effect")
	var root := Node3D.new()
	root.name = "UserScene"
	for label in ["First","Second"]:
		var node := Particles.new()
		node.name = label
		node.effect = effect
		root.add_child(node)
		node.owner = root
	var packed := PackedScene.new()
	check(packed.pack(root) == OK and ResourceSaver.save(packed,"res://users.tscn") == OK,"create temporary two-instance scene")
	root.free()
	EditorInterface.open_scene_from_path("res://users.tscn")
	await frames(25)
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.name == "UserScene","scene opened in editor")
	if scene == null: return
	var a: MMGPUParticles3D = scene.get_node("First")
	var b: MMGPUParticles3D = scene.get_node("Second")
	check(a.effect == b.effect,"two nodes share resource")
	check(not a.preview_in_editor and not a.ready_for_simulation,"editing values does not start GPU")
	EditorInterface.edit_node(a)
	await frames(15)
	EditorInterface.get_inspector().expand_all_folding()
	await frames()
	var fields := a.get_property_list().filter(func(p): return str(p.name).begins_with("user_parameters/"))
	check(fields.size() == 7,"seven dynamic fields")
	check(fields.all(func(p): return (p.usage & PROPERTY_USAGE_EDITOR) != 0 and (p.usage & PROPERTY_USAGE_STORAGE) == 0),"UI names are not serialized")
	var storage := a.get_property_list().filter(func(p): return p.name == "user_parameter_overrides")
	check(storage.size() == 1 and (storage[0].usage & PROPERTY_USAGE_STORAGE) != 0 and (storage[0].usage & PROPERTY_USAGE_EDITOR) == 0,"ID map stored but hidden")
	var values := {"Enabled":false,"Count":-123,"Mask":4294967295,"UV":Vector2(2,3),"Wind":Vector3(4,5,6),"Tint":Vector4(0.25,0.5,0.75,1),"Strength":5.5}
	for label in values:
		await edit_control(label,values[label])
		check(a.get_user_parameter("User."+label) == values[label],"widget edited value: "+label)
		check(b.get_user_parameter("User."+label) != values[label],"other node unchanged: "+label)
	check(a.user_parameter_overrides.size() == 7,"all Inspector overrides use stable IDs")
	await shortcut()
	check(a.get_user_parameter("User.Strength") == 2.0 and not a.user_parameter_overrides.has("strength_id"),"actual editor Ctrl+Z removes override")
	await shortcut(true)
	check(a.get_user_parameter("User.Strength") == 5.5,"actual editor Ctrl+Shift+Z restores override")
	var control := property_control("Strength")
	EditorInterface.get_inspector().ensure_control_visible(control)
	await frames(4)
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("res://user-inspector.png")
	# Exercise the native revert icon immediately before the numeric editor.
	var spin: Control = control.find_children("*","EditorSpinSlider",true,false)[0]
	var point := Vector2(spin.get_global_rect().position.x-12.0,control.get_global_rect().get_center().y)
	click_at(point)
	await frames()
	check(a.get_user_parameter("User.Strength") == 2.0 and not a.user_parameter_overrides.has("strength_id"),"native revert button erases override")
	check(EditorInterface.save_scene() == OK,"save scene through editor")
	var text := FileAccess.get_file_as_string("res://users.tscn")
	check(text.contains("wind_id") and not text.contains("user_parameters/"),"scene stores IDs, not display-property names")
	EditorInterface.reload_scene_from_path("res://users.tscn")
	await frames(25)
	scene = EditorInterface.get_edited_scene_root()
	a = scene.get_node("First")
	b = scene.get_node("Second")
	check(a.get_user_parameter("User.Wind") == Vector3(4,5,6) and b.get_user_parameter("User.Wind") == Vector3.ZERO,"save/reopen preserves independent values")
	check(a.effect == b.effect,"save/reopen preserves shared effect")
	var renamed: MMParticleEffect = a.effect.duplicate(true)
	renamed.user_parameter_by_id("wind_id").name = "Breeze"
	check(ResourceSaver.save(renamed,"res://renamed.tres") == OK,"save renamed effect fixture")
	a.effect = renamed
	EditorInterface.edit_node(a)
	await frames(15)
	check(property_control("Breeze") != null and property_control("Wind") == null,"effect replacement refreshes Inspector names")
	check(a.get_user_parameter("User.Breeze") == Vector3(4,5,6) and a.get_user_parameter("User.Wind") == null,"Rename preserves override by ID")
	check(b.get_user_parameter("User.Wind") == Vector3.ZERO,"other resource instance unaffected by replacement")
	renamed.user_parameter_by_id("wind_id").name = "Air"
	renamed.emit_changed()
	await frames(12)
	check(property_control("Air") != null and property_control("Breeze") == null,"resource changed signal refreshes fields")
	check(a.get_user_parameter("User.Air") == Vector3(4,5,6),"resource rename does not erase values")
	a.effect = null
	await frames(10)
	check(property_control("Air") == null and a.user_parameter_overrides.has("wind_id"),"null effect hides UI, preserves ID overrides")
	check(not a._get_configuration_warnings().is_empty(),"unavailable definitions warn")
	a.effect = effect
	await frames()
	check(a.get_user_parameter("User.Wind") == Vector3(4,5,6),"reassign original definition restores retained override")
	EditorInterface.save_scene()
	EditorInterface.get_selection().clear()
	EditorInterface.inspect_object(null)
	check(EditorInterface.close_scene() == OK,"close isolated scene before editor shutdown")
	await frames(16)
	print("MODULAR_USER_INSPECTOR ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures == 0 else 1)
