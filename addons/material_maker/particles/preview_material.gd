extends RefCounted

const Exporter = preload("exporter.gd")
const BufferState = preload("../engine/dependencies.gd").Buffer

static func prepare(result: Dictionary, tree: SceneTree, still_current: Callable = Callable()) -> Dictionary:
	if not result.errors.is_empty(): return result
	var parameters := {}
	var texture_versions := {}
	var deadline := Time.get_ticks_msec() + 30000
	for name in result.mm_uniforms:
		var value = result.mm_uniforms[name].value
		if value is MMTexture:
			while true:
				if still_current.is_valid() and not still_current.call():
					result["cancelled"] = true
					return result
				var pending := false
				for buffer in mm_deps.buffers.values():
					if not buffer.object is MMGenTexture or buffer.object.texture != value: continue
					if buffer.status == BufferState.Error or Time.get_ticks_msec() > deadline:
						result.errors.append({"message": "Texture rendering failed or was paused: " + buffer.object.get_hier_name()})
						return result
					pending = buffer.status != BufferState.Updated
					texture_versions[value] = buffer.renders
				if not pending: break
				await tree.process_frame
			value = await value.get_texture()
			await tree.process_frame
			if value == null or value.get_image() == null:
				result.errors.append({"message": "Texture is not ready: " + name})
				return result
		parameters[name] = value
	for uniform in result.uniforms:
		var count := int(uniform.get("array_size", 0))
		if not uniform.type.begins_with("sampler"):
			if count:
				var flat: Array = []
				Exporter.flatten(uniform.value, flat)
				parameters[uniform.name] = PackedFloat32Array(flat) if uniform.type == "float" or uniform.type.begins_with("vec") or uniform.type.begins_with("mat") else PackedInt32Array(flat)
			continue
		var paths: Array = uniform.get("resources", []).duplicate() if count else [uniform.get("resource", "")]
		if count and paths.is_empty(): paths.resize(count); paths.fill("")
		if count and paths.size() != count:
			result.errors.append({"message": "Texture array size mismatch: " + uniform.name})
			return result
		var textures: Array = []
		for path in paths:
			if path == "":
				textures.append(null)
				continue
			var project: String = result.target_project
			var disk_path: String = project.path_join(str(path).trim_prefix("res://")).simplify_path()
			if project.is_empty() or not FileAccess.file_exists(project.path_join("project.godot")) or not str(path).begins_with("res://") or not disk_path.begins_with(project.simplify_path().trim_suffix("/") + "/") or not FileAccess.file_exists(disk_path):
				result.errors.append({"message": "Texture must exist inside the selected Godot project: " + str(path)})
				return result
			var texture: Resource
			if disk_path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg", "exr", "hdr"]:
				var image := Image.load_from_file(disk_path)
				if image != null: texture = ImageTexture.create_from_image(image)
			else:
				texture = ResourceLoader.load(disk_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var types := {"sampler2D": "Texture2D", "sampler2DArray": "Texture2DArray", "sampler3D": "Texture3D", "samplerCube": "Cubemap", "samplerCubeArray": "CubemapArray"}
			if texture == null or not texture.is_class(types[uniform.type]):
				result.errors.append({"message": "Cannot preview " + uniform.type + " resource: " + str(path)})
				return result
			textures.append(texture)
		parameters[uniform.name] = textures if count else textures[0]
	result["parameters"] = parameters
	result["texture_versions"] = texture_versions
	return result

static func signature(result: Dictionary) -> int:
	var values: Array = [result.code]
	for name in result.parameters:
		values.append([name, parameter_signature(result.parameters[name])])
	return hash(values)

static func parameter_signature(value):
	if value is Array:
		return value.map(parameter_signature)
	if value is Texture2D:
		var image: Image = value.get_image()
		return image.get_data() if image != null else null
	if value is Resource:
		return [value.get_class(), value.resource_path, FileAccess.get_modified_time(value.resource_path)]
	return value
