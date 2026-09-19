extends RefCounted

const Compiler = preload("compiler.gd")

class ShaderErrors extends Logger:
	var messages: Array[Dictionary] = []
	var lock := Mutex.new()
	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != 1:
			lock.lock()
			messages.append({"message": code + " " + rationale, "line": line if error_type == 3 else 0})
			lock.unlock()

static func validate(result: Dictionary) -> Dictionary:
	if not result.errors.is_empty():
		return result
	var logger = ShaderErrors.new()
	OS.add_logger(logger)
	var shader = Shader.new()
	shader.code = result.code
	shader.get_shader_uniform_list()
	OS.remove_logger(logger)
	logger.lock.lock()
	for error in logger.messages:
		var source: Dictionary = result.source_map.get(error.line, {})
		result.errors.append({"stage": source.get("stage", ""), "node": source.get("node", ""), "message": error.message})
	logger.lock.unlock()
	return result

static func export_files(document: Dictionary, prefix: String) -> Dictionary:
	var compiler = Compiler.new()
	var result: Dictionary = validate(compiler.compile(document))
	return write_result(document, prefix, result)

static func write_result(document: Dictionary, prefix: String, result: Dictionary) -> Dictionary:
	if not result.errors.is_empty():
		return result
	var resources: Array[String] = []
	var parameters: Array[String] = []
	var resource_id := 2
	for uniform in document.get("uniforms", []):
		if not uniform.type.begins_with("sampler"):
			if int(uniform.get("array_size", 0)):
				var flat: Array = []
				flatten(uniform.value, flat)
				var values = PackedFloat32Array(flat) if uniform.type == "float" or uniform.type.begins_with("vec") or uniform.type.begins_with("mat") else PackedInt32Array(flat)
				parameters.append("shader_parameter/" + uniform.name + " = " + var_to_str(values))
			continue
		var paths: Array = uniform.get("resources", []) if int(uniform.get("array_size", 0)) else [uniform.get("resource", "")]
		var count := int(uniform.get("array_size", 0))
		if count and paths.is_empty(): paths.resize(count); paths.fill("")
		if count and paths.size() != count:
			result.errors.append({"stage": "", "node": "", "message": "Texture array size mismatch: " + uniform.name})
			continue
		var references: Array[String] = []
		for path in paths:
			if path == "":
				references.append("null")
				continue
			var project: String = document.get("target_project", "")
			var disk_path: String = project.path_join(str(path).trim_prefix("res://")).simplify_path()
			if project.is_empty() or not FileAccess.file_exists(project.path_join("project.godot")) or not str(path).begins_with("res://") or not disk_path.begins_with(project.simplify_path().trim_suffix("/") + "/") or not FileAccess.file_exists(disk_path):
				result.errors.append({"stage": "", "node": "", "message": "Texture must exist inside the selected Godot project: " + str(path)})
				continue
			var types = {"sampler2D": "Texture2D", "sampler2DArray": "Texture2DArray", "sampler3D": "Texture3D", "samplerCube": "Cubemap", "samplerCubeArray": "CubemapArray"}
			var resource_type: String = types[uniform.type]
			if resource_type == "Texture2D" and disk_path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg", "exr", "hdr"]:
				pass
			else:
				var texture = ResourceLoader.load(disk_path)
				if texture == null or not texture.is_class(resource_type):
					result.errors.append({"stage": "", "node": "", "message": "Expected " + resource_type + ": " + str(path)})
					continue
			var id: String = str(resource_id)
			resources.append('[ext_resource type="%s" path=%s id="%s"]' % [resource_type, JSON.stringify(path), id])
			references.append('ExtResource("%s")' % id)
			resource_id += 1
		if not references.is_empty():
			parameters.append("shader_parameter/" + uniform.name + " = " + ("[" + ", ".join(references) + "]" if int(uniform.get("array_size", 0)) else references[0]))
	if not result.errors.is_empty():
		return result
	for name in result.get("material_parameters", {}):
		parameters.append("shader_parameter/" + name + " = " + var_to_str(result.material_parameters[name]))
	for name in result.get("texture_parameters", {}):
		resources.append('[ext_resource type="Texture2D" path=%s id="%s"]' % [JSON.stringify(result.texture_parameters[name]), str(resource_id)])
		parameters.append('shader_parameter/%s = ExtResource("%s")' % [name, str(resource_id)])
		resource_id += 1
	var material: String = '[gd_resource type="ShaderMaterial" load_steps=%d format=3]\n' % resource_id
	material += '[ext_resource type="Shader" path=%s id="1"]\n' % JSON.stringify(prefix.get_file() + ".gdshader")
	material += "\n".join(resources) + '\n[resource]\nshader = ExtResource("1")\n' + "\n".join(parameters) + "\n"
	for item in [[".gdshader", result.code], [".tres", material]]:
		var file = FileAccess.open(prefix + item[0], FileAccess.WRITE)
		if file == null:
			result.errors.append({"stage": "", "node": "", "message": "Cannot write " + prefix + item[0]})
			return result
		file.store_string(item[1])
	return result

static func flatten(value, output: Array) -> void:
	if value is Array:
		for item in value: flatten(item, output)
	else:
		output.append(int(value) if value is bool else value)
