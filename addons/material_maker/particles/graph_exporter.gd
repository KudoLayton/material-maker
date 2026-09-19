extends RefCounted

const Exporter = preload("exporter.gd")
const BufferState = preload("../engine/dependencies.gd").Buffer

static func export_graph(graph: MMGenGraph, prefix: String) -> Dictionary:
	var result: Dictionary = load("res://addons/material_maker/particles/graph_compiler.gd").new().compile_graph(graph)
	Exporter.validate(result)
	if not result.errors.is_empty(): return result
	for frame in 2: await graph.get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 30000
	mm_deps.update()
	while true:
		var pending := false
		for buffer in mm_deps.buffers.values():
			if not buffer.object is MMGenTexture: continue
			var needed: bool = result.mm_uniforms.values().any(func(u): return u.value is MMTexture and u.value == buffer.object.texture)
			if not needed or buffer.status == BufferState.Updated: continue
			if buffer.status == BufferState.Error or Time.get_ticks_msec() > deadline:
				result.errors.append({"stage": "", "node": buffer.object.get_hier_name(), "message": "Texture rendering failed or was paused. Resume the buffer and retry."})
				return result
			pending = true
		if not pending: break
		await graph.get_tree().process_frame
	var textures: Dictionary = {}
	var parameters: Dictionary = {}
	var resources: Dictionary = {}
	for name in result.mm_uniforms:
		var uniform = result.mm_uniforms[name]
		if uniform.value is MMTexture:
			if not textures.has(uniform.value):
				var texture: ImageTexture = await uniform.value.get_texture()
				var file := prefix + "_texture_%d.res" % textures.size()
				if texture == null or texture.get_image() == null or ResourceSaver.save(texture, file) != OK:
					result.errors.append({"stage": "", "node": "", "message": "Cannot save baked texture: " + file})
					return result
				textures[uniform.value] = file.get_file()
			resources[name] = textures[uniform.value]
		else: parameters[name] = uniform.value
	result["texture_parameters"] = resources
	result["material_parameters"] = parameters
	return Exporter.write_result({"uniforms": result.uniforms, "target_project": result.target_project}, prefix, result)
