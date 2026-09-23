extends Node
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Exporter = preload("res://addons/material_maker/particles/modular/exporter.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var doc := Document.load_file("res://material_maker/examples/modular_particles/user_parameters.mpfx")
	var graphs := {}
	for id in doc.modules: graphs[id] = await mm_loader.create_gen(doc.modules[id].mm_graph.duplicate(true))
	var result := Compiler.new().compile(doc,graphs)
	for graph in graphs.values(): graph.free()
	check(result.errors.is_empty(),"User example compilation: "+str(result.errors))
	if result.effect != null:
		var effect: MMParticleEffect = result.effect
		check(effect.format_version == 2 and effect.user_parameters.size() == 3,"versioned User metadata")
		var speed := effect.user_parameter("User.Speed")
		check(effect.parameters.filter(func(p): return p.get("user_id") == speed.id).size() == 2,"Speed shared by both cone bounds")
		var destination := ProjectSettings.globalize_path("res://user-standalone")
		var exporter := Exporter.new()
		var exported := await exporter.export_bundle(effect,destination,256)
		check(exported.error.is_empty(),"User export: "+exported.error)
		if exported.error.is_empty():
			check(exported.manifest.files.has("effects/modular_particles/user_demo.gd"),"standalone controls owned by manifest")
			for path in exported.manifest.files:
				check(FileAccess.get_sha256(destination.path_join(path)) == exported.manifest.files[path],"User export checksum: "+path)
			var loaded: MMParticleEffect = load(destination.path_join("effects/modular_particles/effect.res"))
			check(loaded.validation_error().is_empty() and loaded.shader_file != null,"v2 metadata and SPIR-V roundtrip")
			check(loaded.user_parameter("User.Speed").id == speed.id,"User ID stable in standalone resource")
			var config := FileAccess.get_file_as_bytes(destination.path_join("project.godot"))
			config.append_array("\n; user-owned settings\n".to_utf8_buffer())
			Exporter._write(destination.path_join("project.godot"),config)
			check((await exporter.export_bundle(effect,destination,256)).error.is_empty(),"v2 repeat export")
			check(FileAccess.get_file_as_bytes(destination.path_join("project.godot")) == config,"v2 preserves project settings")
			var path := destination.path_join("effects/modular_particles/user_demo.gd")
			var pristine := FileAccess.get_file_as_bytes(path)
			Exporter._write(path,pristine+"\n# user edit\n".to_utf8_buffer())
			var before := snapshot(destination)
			check(not (await exporter.export_bundle(effect,destination,256)).error.is_empty() and snapshot(destination) == before,"modified User controls reject re-export atomically")
			Exporter._write(path,pristine)
			var malformed: MMParticleEffect = effect.duplicate(true)
			malformed.user_parameters.clear()
			before = snapshot(destination)
			check(not (await exporter.export_bundle(malformed,destination,256)).error.is_empty() and snapshot(destination) == before,"invalid User metadata rejected before any writes")
	print("MODULAR_USER_EXPORT ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
func snapshot(path: String) -> Dictionary:
	var values := {}
	var dir := DirAccess.open(path)
	for file in dir.get_files(): values[file] = FileAccess.get_sha256(path.path_join(file))
	for child in dir.get_directories(): values[child] = snapshot(path.path_join(child))
	return values
