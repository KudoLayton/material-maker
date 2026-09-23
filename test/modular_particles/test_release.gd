extends Node
## Shipped as an optional validation scene; normal startup remains parse_args.tscn.
const Exporter = preload("res://addons/material_maker/particles/modular/exporter.gd")
const RenameChecks = preload("rename_checks.gd")
const DeleteChecks = preload("input_delete_checks.gd")
const NamespaceChecks = preload("namespace_checks.gd")
const StandardChecks = preload("standard_checks.gd")
const StandardUI = preload("standard_ui_checks.gd")
const UserUI = preload("user_ui_checks.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--modular-build-check":
		print("FAIL: expected --modular-build-check and a fresh output directory")
		get_tree().quit(1)
		return
	var output := args[1]
	var original_config := mm_globals.config.encode_to_text()
	check(not OS.has_feature("editor"),"release template, not editor executable")
	for script in Exporter.RUNTIME:
		check(not FileAccess.get_file_as_bytes("res://addons/mm_gpu_particles/"+script).is_empty(),"runtime source packaged: " + script)
	check(mm_io_types.types.has("f") and mm_io_types.types.has("rgb") and mm_io_types.types.get("f",{}).has("preview"),"I/O schema and raw preview shaders packaged")
	check(mm_loader.predefined_generators.has("fbm4") and mm_loader.predefined_generators.has("tonality"),"procedural Library definitions packaged")
	var window
	for frame in 360:
		window = get_tree().root.get_node_or_null("MainWindow")
		if window != null: break
		await get_tree().process_frame
	check(window != null,"normal parse_args startup opened MainWindow")
	if window == null:
		await mm_renderer.stop_rendering_thread()
		get_tree().quit(1)
		return
	await frames(90)
	get_tree().root.size = Vector2i(1440,960)
	var editor = window.get_current_project()
	check(editor != null and editor.has_method("compile_document") and str(editor.save_path).get_file() == "mmtest.mpfx","normal command-line launch loaded mpfx example")
	check(editor != null and editor.has_method("compile_document"),"modular editor tab exists")
	if editor != null and editor.has_method("compile_document"):
		for frame in 360:
			if is_instance_valid(editor.preview) and editor.preview.ready_for_simulation: break
			await get_tree().process_frame
		check(is_instance_valid(editor.preview) and editor.preview.ready_for_simulation,"packaged GPU preview: " + editor.status.text)
		check(editor.graph_edit.get_children().any(func(n): return n is GraphNode),"packaged graph canvas")
		var renamed: Dictionary = await RenameChecks.run(editor,get_tree(),check,output.path_join("rename-dialog.png"))
		var deleted: Dictionary = await DeleteChecks.run(editor,get_tree(),check,output.path_join("input-delete.png"))
		editor.save_path = output.path_join("roundtrip.mpfx")
		check(await editor.save(),"packaged authoring save")
		check(await window.do_load_project(editor.save_path),"packaged authoring reopen")
		editor = window.get_current_project()
		await frames(40)
		check(not renamed.is_empty() and editor.document.modules[renamed.id].name == renamed.name,"packaged rename persists after reopening mpfx")
		check(not editor.document.modules[deleted.module_id].inputs.any(func(input): return input.id == deleted.input_id),"packaged input deletion persists after reopening mpfx")
		var clean := true
		for stage in ["spawn","update"]:
			for instance in editor.document.stages[stage]:
				if instance.module == deleted.module_id and instance.parameters.has(deleted.input_id): clean = false
		check(clean,"packaged deleted overrides stay absent after reopen")
		var reopened: Dictionary = await editor.compile_document()
		check(reopened.errors.is_empty(),"packaged deleted-input effect still compiles")
		# Test-only no-op modules must not become part of the delivered Godot demo.
		await DeleteChecks.restore(editor,deleted,get_tree())
		var namespaced: Dictionary = await NamespaceChecks.run(editor,get_tree(),check,output.path_join("namespaces.png"))
		editor.save_path = output.path_join("namespace-roundtrip.mpfx")
		check(await editor.save(),"packaged namespace save")
		check(await window.do_load_project(editor.save_path),"packaged namespace reopen")
		editor = window.get_current_project()
		await frames(40)
		check(editor.document.attributes[0].name == namespaced.name and editor.document.modules[namespaced.module_id].inputs[0].name == "Position","packaged namespace display does not contaminate saved raw names")
		check(NamespaceChecks.ui_node(editor,"Input").title == "Read Module.Position" and NamespaceChecks.ui_node(editor,"CustomRead").title == "Read Particle.Custom."+namespaced.name,"packaged qualified labels restored after reopen")
		await NamespaceChecks.restore(editor,namespaced,get_tree())
		var standard_state: Dictionary = await StandardUI.run(editor,get_tree(),check,output.path_join("standard-library.png"))
		editor.save_path = output.path_join("standard-roundtrip.mpfx")
		check(await editor.save(),"packaged standard authoring save")
		check(await window.do_load_project(editor.save_path),"packaged standard authoring reopen")
		editor = window.get_current_project()
		await frames(40)
		check((await editor.compile_document()).errors.is_empty(),"packaged standard snapshots and role bindings survive reload")
		await StandardUI.restore(editor,standard_state)
		var compiled: Dictionary = await editor.compile_document()
		check(compiled.errors.is_empty(),"packaged Curve/FBM/typed graph compiler: " + str(compiled.errors))
		if compiled.effect != null:
			var exported: Dictionary = await Exporter.new().export_bundle(compiled.effect,output.path_join("godot-example"),128)
			check(exported.error.is_empty(),"export from release EXE: " + exported.error)
		if is_instance_valid(editor.preview):
			await frames(20)
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(output.path_join("material-maker.png"))
	# Compile and dispatch every packaged recipe, including 3D Curl and both
	# editable Gradient/Curve paths. These tests run in the actual release EXE.
	check(StandardChecks.L.catalog().size() == 12,"all twelve catalog entries packaged")
	var all_standard := StandardChecks.document(["initialize_particle","box_location","sphere_location","add_velocity","add_velocity_in_cone"],["gravity","drag","curl_noise","solve_motion","color_over_life","scale_over_life","kill_particles"])
	var all_compiled := await StandardChecks.compile(all_standard)
	check(all_compiled.errors.is_empty(),"all packaged recipes compile: "+str(all_compiled.errors))
	if all_compiled.effect != null:
		var probe = await StandardChecks.start(self,all_compiled.effect,16)
		check(probe.ready_for_simulation,"all packaged recipes GPU shader")
		if probe.ready_for_simulation:
			probe.emit_burst(4)
			probe.advance(1.0/60.0)
			await StandardChecks.frames(get_tree())
			var snapshot := await StandardChecks.snapshot(probe)
			check(snapshot.count == 4 and StandardChecks.vector(probe,snapshot,"position").is_finite(),"packaged 12-module GPU result")
		await StandardChecks.dispose(probe)
	var basic = window.new_modular_particles()
	await frames(50)
	check(basic.document.stages.spawn.size() == 2 and basic.document.stages.update.size() == 4 and basic.document.attributes.size() == 4,"packaged new-document defaults")
	check(is_instance_valid(basic.preview) and basic.preview.ready_for_simulation,"packaged new-document preview")
	check(basic.graph_edit.zoom>=0.5,"packaged large graph keeps labels visible")
	var output_nodes: Array = basic.graph_edit.get_children().filter(func(n): return n is MMGraphNodeGeneric and n.generator != null and n.generator.get("settings") is Dictionary and n.generator.settings.get("kind") == "module_output")
	check(output_nodes.size() == 1 and Rect2(Vector2.ZERO,basic.graph_edit.size).has_point(output_nodes[0].position_offset*basic.graph_edit.zoom-basic.graph_edit.scroll_offset),"packaged Output starts inside graph viewport")
	var basic_document: Dictionary = basic.document.duplicate(true)
	basic_document.emitter.merge({"rate":0.0,"duration":2.0,"lifetime":2.0,"loop":true,"bursts":[{"time":0.0,"count":128}]},true)
	basic_document["preview_capacity"] = 128
	await StandardUI.load_document(basic,basic_document,"spawn")
	basic.save_path = output.path_join("basic-128.mpfx")
	check(await basic.save(),"packaged standalone basic authoring snapshot")
	var basic_compiled: Dictionary = await basic.compile_document()
	check(basic_compiled.errors.is_empty(),"packaged basic burst compilation")
	if basic_compiled.effect != null:
		var exported: Dictionary = await Exporter.new().export_bundle(basic_compiled.effect,output.path_join("godot-basic-example"),128)
		check(exported.error.is_empty(),"standard module export from release EXE: "+exported.error)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(output.path_join("standard-editor.png"))
	var user = window.new_modular_particles()
	await frames(50)
	var user_state: Dictionary = await UserUI.run(user,get_tree(),check,output)
	await UserUI.restore(user,user_state,get_tree())
	var user_example_path := OS.get_executable_path().get_base_dir().path_join("examples/modular_particles/user_parameters.mpfx")
	check(FileAccess.file_exists(user_example_path),"packaged User sidecar example exists")
	check(await user.load_project(user_example_path),"packaged User example load")
	await frames(60)
	check(user.document.version == 2 and user.document.user_parameters.size() == 3,"packaged v2 User example metadata")
	check(is_instance_valid(user.preview) and user.preview.ready_for_simulation and user.preview.effect.user_parameters.size() == 3,"packaged User example GPU preview")
	user.save_path = output.path_join("user-example.mpfx")
	check(await user.save(),"packaged User example authoring save")
	check(await window.do_load_project(user.save_path),"packaged User example authoring reopen")
	user = window.get_current_project()
	await frames(40)
	var user_compiled: Dictionary = await user.compile_document()
	check(user_compiled.errors.is_empty() and user_compiled.effect != null and user_compiled.effect.format_version == 2,"packaged User compilation after reopen")
	if user_compiled.effect != null:
		var exported: Dictionary = await Exporter.new().export_bundle(user_compiled.effect,output.path_join("godot-user-example"),256)
		check(exported.error.is_empty(),"User export from release EXE: "+exported.error)
	var scroll: ScrollContainer = user.input_box.get_parent().get_parent()
	scroll.scroll_vertical = 0
	await frames(3)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(output.path_join("user-example.png"))
	var old = await window.new_particle_shader()
	await frames(10)
	check(old is MMGraphEdit and old.get_material_node() is MMGenParticleMaterial,"legacy ptex editor still opens")
	var info := {"passed":failures == 0,"checks":checks,"engine":Engine.get_version_info().string,"editor":OS.has_feature("editor"),"export":output.path_join("godot-example"),"standard_export":output.path_join("godot-basic-example"),"user_export":output.path_join("godot-user-example"),"userdata":OS.get_user_data_dir()}
	var file := FileAccess.open(output.path_join("release-smoke.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(info,"\t"))
	file.close()
	print("MODULAR_RELEASE ","PASS" if failures == 0 else "FAIL"," checks=",checks," editor=",OS.has_feature("editor"))
	mm_globals.set_config("confirm_quit",false)
	mm_globals.set_config("confirm_close_project",false)
	await window.quit()
	# Tests must not leave altered quit prompts or recent-project settings for users.
	mm_globals.config.clear()
	mm_globals.config.parse(original_config)
	get_tree().quit(0 if failures == 0 else 1)
