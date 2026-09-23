extends RefCounted
## Portable runtime exporter. Only checksum-owned, unmodified files may be
## replaced. A preflight conflict aborts before any target file is changed.
const Document = preload("document.gd")
const MANIFEST := "mm_particles_manifest.json"
const RUNTIME := ["effect.gd","gpu_state.gd","multimesh_lifetime.gd","particles_3d.gd","scheduler.gd","value_codec.gd","plugin.gd","plugin.cfg"]
const PROJECT := """config_version=5
[application]
config/name="Modular GPU Particles"
run/main_scene="res://effects/modular_particles/demo.tscn"
[display]
window/size/viewport_width=960
window/size/viewport_height=640
[rendering]
renderer/rendering_method="forward_plus"
environment/defaults/default_clear_color=Color(0,0,0,1)
"""

func export_effect(effect: MMParticleEffect, destination: String, capacity: int = 4096) -> String:
	var result := await export_bundle(effect,destination,capacity)
	return ("Exported standalone runtime: " + destination) if result.error.is_empty() else result.error

func export_bundle(effect: MMParticleEffect, destination: String, capacity: int = 4096) -> Dictionary:
	if effect == null: return problem("No compiled effect")
	var error := effect.validation_error()
	if not error.is_empty(): return problem(error)
	error = preload("res://addons/mm_gpu_particles/gpu_state.gd").size_error(effect,capacity)
	if not error.is_empty(): return problem(error)
	var root := ProjectSettings.globalize_path(destination).simplify_path()
	if not root.is_absolute_path(): return problem("Export destination must be absolute")
	var files := {}
	for name in RUNTIME:
		var path: String = "addons/mm_gpu_particles/" + name
		if not FileAccess.file_exists("res://" + path): return problem("Runtime source is missing; export from the source editor: " + path)
		files[path] = FileAccess.get_file_as_bytes("res://" + path)
		if files[path].is_empty(): return problem("Empty runtime source: " + path)
	files["effects/modular_particles/effect.res"] = PackedByteArray() # Saved after shader compilation.
	files["effects/modular_particles/effect.glsl.txt"] = effect.compute_source.to_utf8_buffer()
	files["effects/modular_particles/particles.tscn"] = ("""[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://addons/mm_gpu_particles/particles_3d.gd" id="1"]
[ext_resource type="Resource" path="res://effects/modular_particles/effect.res" id="2"]
[node name="MMGPUParticles3D" type="Node3D"]
script = ExtResource("1")
effect = ExtResource("2")
capacity = %d
""" % capacity).to_utf8_buffer()
	files["effects/modular_particles/demo.tscn"] = """[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://effects/modular_particles/particles.tscn" id="1"]
[node name="Demo" type="Node3D"]
[node name="Particles" parent="." instance=ExtResource("1")]
[node name="Camera" type="Camera3D" parent="."]
position = Vector3(0,0,6)
current = true
""".to_utf8_buffer()
	if not effect.user_parameters.is_empty():
		var controls := FileAccess.get_file_as_bytes("res://addons/material_maker/particles/modular/user_demo.gd")
		if controls.is_empty(): return problem("User demo source is not packaged")
		files["effects/modular_particles/user_demo.gd"] = controls
		files["effects/modular_particles/demo.tscn"] = """[gd_scene load_steps=3 format=3]
[ext_resource type="PackedScene" path="res://effects/modular_particles/particles.tscn" id="1"]
[ext_resource type="Script" path="res://effects/modular_particles/user_demo.gd" id="2"]
[node name="Demo" type="Node3D"]
script = ExtResource("2")
[node name="Particles" parent="." instance=ExtResource("1")]
position = Vector3(-1.1,0,0)
[node name="Second" parent="." instance=ExtResource("1")]
position = Vector3(1.1,0,0)
[node name="Camera" type="Camera3D" parent="."]
position = Vector3(0,0.8,6)
current = true
""".to_utf8_buffer()
	files["effects/modular_particles/README.txt"] = """Godot 4.7.2 stable, Forward+, Vulkan. No Material Maker/autoload required.
Instance particles.tscn in your scene, or run demo.tscn. The binary effect
contains precompiled SPIR-V; effect.glsl.txt is diagnostic source only.
MMGPUParticles3D: play/pause/stop/restart/emit_burst/set_parameter.
Format-2 effects expose User Parameters in the Inspector and support
set/get/reset_user_parameter("User.Name", ...) plus *_by_id variants.
User-bound inputs reject set_parameter; use the User API. Values are per-node.
User demos contain two instances and live controls; graphs/compiler are not needed.
Set capacity and visibility_aabb explicitly. Opaque/additive/cutout only;
transparent depth sorting is not supported. Runtime scripts are required.
Do not edit manifest-owned files before re-exporting. Export into a new
folder if a checksum conflict occurs. project.godot is never overwritten.
""".to_utf8_buffer()
	var manifest_path := root.path_join(MANIFEST)
	if _linked(root,MANIFEST): return problem("Refusing linked manifest")
	var old := {}
	var manifest_hash := FileAccess.get_sha256(manifest_path) if FileAccess.file_exists(manifest_path) else ""
	if FileAccess.file_exists(manifest_path):
		old = Document.load_file(manifest_path)
		if old.get("format") != "mm_gpu_particles_export" or old.get("version") != 1 or not old.get("files") is Dictionary:
			return problem("Unrecognized export manifest; nothing was changed")
		for checksum in old.files.values():
			if not checksum is String or checksum.length() != 64: return problem("Invalid manifest checksum")
	for relative in files:
		if _linked(root,relative): return problem("Refusing linked export path: " + relative)
		var target := root.path_join(relative)
		if DirAccess.dir_exists_absolute(target): return problem("Export path is a directory: " + relative)
		if FileAccess.file_exists(target) and old.get("files",{}).get(relative,"") != FileAccess.get_sha256(target):
			return problem("Unmanaged or modified file; nothing was changed: " + relative)
	# Compile on the main RD, before touching any target files. Runtime builds
	# consume this bytecode instead of requiring the editor shader compiler.
	var compilation := {}
	var source_code := effect.compute_source
	RenderingServer.call_on_render_thread(func():
		var rd := RenderingServer.get_rendering_device()
		if rd == null:
			compilation.error = "Export requires a Forward+ RenderingDevice"
		else:
			var source := RDShaderSource.new()
			source.source_compute = source_code
			compilation.spirv = rd.shader_compile_spirv_from_source(source)
			compilation.error = compilation.spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		compilation.done = true)
	while not compilation.has("done"): await Engine.get_main_loop().process_frame
	if not compilation.error.is_empty(): return problem("Compute compilation failed: " + compilation.error)
	var stage := root.path_join(".mm-export-" + Document.uid())
	if DirAccess.make_dir_recursive_absolute(stage) != OK: return problem("Cannot create export staging directory")
	var packaged: MMParticleEffect = effect.duplicate(true)
	packaged.shader_file = RDShaderFile.new()
	packaged.shader_file.set_bytecode(compilation.spirv)
	for relative in files:
		var staged := stage.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(staged.get_base_dir()) != OK:
			_cleanup(stage)
			return problem("Cannot create staged directory: " + relative)
		if relative.ends_with("effect.res"):
			if ResourceSaver.save(packaged,staged,ResourceSaver.FLAG_COMPRESS) != OK:
				_cleanup(stage)
				return problem("Cannot save compiled effect")
		else:
			error = _write(staged,files[relative])
			if not error.is_empty():
				_cleanup(stage)
				return problem(error)
	var manifest := {"format":"mm_gpu_particles_export","version":1,"target":"4.7.2","source_hash":effect.source_hash,"files":{}}
	for relative in files: manifest.files[relative] = FileAccess.get_sha256(stage.path_join(relative))
	error = _write(stage.path_join(MANIFEST),JSON.stringify(manifest,"\t").to_utf8_buffer())
	if not error.is_empty():
		_cleanup(stage)
		return problem(error)
	# A new project's config becomes user-owned immediately; subsequent exports
	# neither overwrite it nor require its checksum to remain unchanged.
	if not FileAccess.file_exists(root.path_join("project.godot")):
		files["project.godot"] = PROJECT.to_utf8_buffer()
		error = _write(stage.path_join("project.godot"),files["project.godot"])
		if not error.is_empty():
			_cleanup(stage)
			return problem(error)
	var committed: Array[String] = []
	var existed := {}
	var ordered: Array = files.keys()
	ordered.append(MANIFEST) # Ownership is published last.
	for relative in ordered:
		if _linked(root,relative):
			error = "Linked path appeared during export: " + relative
			break
		var target := root.path_join(relative)
		var backup := stage.path_join("backup/" + relative)
		var previous: String = old.get("files",{}).get(relative,"")
		# Recheck after the await; do not clobber concurrent user edits.
		if relative == MANIFEST: previous = manifest_hash
		if FileAccess.file_exists(target):
			if previous.is_empty() or FileAccess.get_sha256(target) != previous:
				error = "File changed during export: " + relative
				break
			DirAccess.make_dir_recursive_absolute(backup.get_base_dir())
			if DirAccess.copy_absolute(target,backup) != OK:
				error = "Cannot back up: " + relative
				break
			existed[relative] = true
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK or DirAccess.rename_absolute(stage.path_join(relative),target) != OK:
			error = "Cannot publish: " + relative
			break
		committed.append(relative)
	if not error.is_empty():
		committed.reverse()
		for relative in committed:
			var target := root.path_join(relative)
			var rollback := DirAccess.rename_absolute(stage.path_join("backup/"+relative),target) if existed.has(relative) else DirAccess.remove_absolute(target)
			if rollback != OK: return problem(error + "; rollback requires manual recovery from " + stage)
	_cleanup(stage)
	return {"error":error,"manifest":manifest if error.is_empty() else {}}

static func problem(message: String) -> Dictionary:
	return {"error":message,"manifest":{}}

static func _write(path: String, data: PackedByteArray) -> String:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return "Cannot write: " + path
	file.store_buffer(data)
	file.flush()
	var error := file.get_error()
	file.close()
	return "" if error == OK else "Write failed: " + path

static func _linked(root: String, relative: String) -> bool:
	var parent := root
	for part in relative.split("/"):
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(part): return true
		parent = parent.path_join(part)
	return false

static func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for name in directory.get_files(): directory.remove(name)
	for name in directory.get_directories(): _cleanup(path.path_join(name))
	DirAccess.remove_absolute(path)
