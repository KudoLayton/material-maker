extends Node
const Document = preload("res://addons/material_maker/particles/modular/document.gd")
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Exporter = preload("res://addons/material_maker/particles/modular/exporter.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ",message)
func _ready() -> void: run.call_deferred()
func run() -> void:
	var doc := Document.load_file("res://material_maker/examples/modular_particles/mmtest.mpfx")
	var graphs := {}
	for id in doc.modules: graphs[id] = await mm_loader.create_gen(doc.modules[id].mm_graph)
	var compiled := Compiler.new().compile(doc,graphs)
	for graph in graphs.values(): graph.free()
	check(compiled.errors.is_empty(),"sample compilation")
	if compiled.effect != null:
		var root := ProjectSettings.globalize_path("res://standalone")
		var exporter := Exporter.new()
		var result := await exporter.export_bundle(compiled.effect,root,128)
		check(result.error.is_empty(),"first standalone export: " + result.error)
		if result.error.is_empty():
			var resource: MMParticleEffect = load(root.path_join("effects/modular_particles/effect.res"))
			check(resource != null and resource.validation_error().is_empty(),"portable effect load/hash")
			check(resource.shader_file != null and not resource.shader_file.get_spirv().bytecode_compute.is_empty(),"precompiled SPIR-V persisted")
			check(not DirAccess.dir_exists_absolute(root.path_join("addons/material_maker")),"no MM dependency")
			for relative in result.manifest.files:
				check(result.manifest.files[relative] == FileAccess.get_sha256(root.path_join(relative)),"manifest checksum: " + relative)
			var config := FileAccess.get_file_as_bytes(root.path_join("project.godot"))
			config.append_array("\n; user settings must be retained\n".to_utf8_buffer())
			Exporter._write(root.path_join("project.godot"),config)
			Exporter._write(root.path_join("unrelated.txt"),"user-owned".to_utf8_buffer())
			result = await exporter.export_bundle(compiled.effect,root,128)
			check(result.error.is_empty(),"repeat export of unmodified owned files: " + result.error)
			check(FileAccess.get_file_as_bytes(root.path_join("project.godot")) == config,"existing project settings preserved")
			check(FileAccess.get_file_as_string(root.path_join("unrelated.txt")) == "user-owned","unrelated file preserved")
			var managed := root.path_join("addons/mm_gpu_particles/particles_3d.gd")
			var pristine := FileAccess.get_file_as_bytes(managed)
			Exporter._write(managed,pristine + "\n# user edit\n".to_utf8_buffer())
			var before := snapshot(root)
			result = await exporter.export_bundle(compiled.effect,root,128)
			check(not result.error.is_empty(),"modified managed file rejected")
			check(before == snapshot(root),"conflict changes no files")
			Exporter._write(managed,pristine)
			var other := root.path_join("unmanaged")
			DirAccess.make_dir_recursive_absolute(other.path_join("effects/modular_particles"))
			Exporter._write(other.path_join("effects/modular_particles/effect.res"),"existing user data".to_utf8_buffer())
			before = snapshot(other)
			result = await exporter.export_bundle(compiled.effect,other,128)
			check(not result.error.is_empty() and before == snapshot(other),"unmanaged collision preserved")
			var broken: MMParticleEffect = compiled.effect.duplicate(true)
			broken.compute_source = "#version 450\nnot valid compute"
			broken.source_hash = broken.compute_source.sha256_text()
			before = snapshot(root)
			result = await exporter.export_bundle(broken,root,128)
			check(not result.error.is_empty() and before == snapshot(root),"failed compilation preserves last export")
	print("MODULAR_EXPORT ","PASS" if failures == 0 else "FAIL"," checks=",checks)
	await mm_renderer.stop_rendering_thread()
	get_tree().quit(0 if failures == 0 else 1)
func snapshot(root: String, prefix: String = "") -> Dictionary:
	var result := {}
	var dir := DirAccess.open(root.path_join(prefix))
	for name in dir.get_files(): result[prefix.path_join(name)] = FileAccess.get_sha256(root.path_join(prefix).path_join(name))
	for name in dir.get_directories(): result.merge(snapshot(root,prefix.path_join(name)))
	return result
