extends RefCounted

static func runtime_source(generator: MMGenBase, visited: Dictionary = {}) -> String:
	if visited.has(generator): return ""
	visited[generator] = true
	if generator is MMGenShader and JSON.stringify(generator.shader_model).contains("$time"):
		return generator.get_hier_name() + ": animated shader"
	if generator.has_method("model_data"):
		var kind: String = generator.model_data().kind
		if kind in ["input", "transform_read", "uniform", "emit", "set", "random"]: return generator.get_hier_name()
	for i in generator.get_input_defs().size():
		var source = source(generator, i)
		if source != null:
			var found := runtime_source(source.generator, visited)
			if not found.is_empty(): return found
	return ""

static func bake_error(generator: MMGenBase, visited: Dictionary = {}) -> String:
	if visited.has(generator): return ""
	visited[generator] = true
	if generator is MMGenBuffer or generator is MMGenIterateBuffer:
		var runtime := runtime_source(generator)
		if not runtime.is_empty(): return generator.get_hier_name() + ": cannot bake runtime particle input " + runtime
	for i in generator.get_input_defs().size():
		var source = source(generator, i)
		if source != null:
			var found := bake_error(source.generator, visited)
			if not found.is_empty(): return found
	return ""

static func requires_context(generator: MMGenBase, visited: Dictionary = {}) -> bool:
	if visited.has(generator): return false
	visited[generator] = true
	if generator.has_method("model_data"): return true
	for output in generator.get_output_defs():
		if str(output.type).begins_with("particle_"): return true
	for i in generator.get_input_defs().size():
		var source = source(generator, i)
		if source != null and requires_context(source.generator, visited): return true
	return false

static func source(generator: MMGenBase, index: int):
	var port = generator.get_source(index)
	var visited: Dictionary = {}
	while port != null and (port.generator is MMGenReroute or port.generator is MMGenPortal):
		if visited.has(port.generator): return null
		visited[port.generator] = true
		if port.generator is MMGenPortal:
			port.generator.update_source()
			port = port.generator.source
		else: port = port.generator.get_source(0)
	return port
