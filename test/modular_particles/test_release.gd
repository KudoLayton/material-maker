extends Node
## Shipped as an optional validation scene; normal startup remains parse_args.tscn.
const Exporter = preload("res://addons/material_maker/particles/modular/exporter.gd")
const RenameChecks = preload("rename_checks.gd")
const DeleteChecks = preload("input_delete_checks.gd")
const NamespaceChecks = preload("namespace_checks.gd")
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
		var compiled: Dictionary = await editor.compile_document()
		check(compiled.errors.is_empty(),"packaged Curve/FBM/typed graph compiler: " + str(compiled.errors))
		if compiled.effect != null:
			var exported: Dictionary = await Exporter.new().export_bundle(compiled.effect,output.path_join("godot-example"),128)
			check(exported.error.is_empty(),"export from release EXE: " + exported.error)
		if is_instance_valid(editor.preview):
			await frames(20)
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(output.path_join("material-maker.png"))
	var old = await window.new_particle_shader()
	await frames(10)
	check(old is MMGraphEdit and old.get_material_node() is MMGenParticleMaterial,"legacy ptex editor still opens")
	var info := {"passed":failures == 0,"checks":checks,"engine":Engine.get_version_info().string,"editor":OS.has_feature("editor"),"export":output.path_join("godot-example"),"userdata":OS.get_user_data_dir()}
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
