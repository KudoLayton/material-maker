extends RefCounted

const Interface = preload("res://addons/material_maker/particles/interface.gd")

static func create(document: Dictionary, owner: Node) -> MMGenGraph:
	var nodes: Array = []
	var connections: Array = []
	for stage in ["start", "process"]:
		var descriptions: Dictionary = {}
		for n in document.stages[stage].nodes:
			descriptions[n.id] = n
			var settings: Dictionary = n.duplicate(true)
			settings.stage = stage
			settings.inputs = {}
			var parameters: Dictionary = {}
			if n.kind == "uniform":
				for uniform in document.uniforms:
					if uniform.name == n.uniform:
						settings.data_type = uniform.type
						parameters = {"uniform_name": uniform.name, "default_json": JSON.stringify(uniform.value), "array_size": uniform.get("array_size", 0)}
			var name: String = "Material" if stage == "start" and n.kind == "output" else stage + "_" + n.id
			var node: Dictionary = {"name": name, "type": "particle_export" if name == "Material" else "particle_node", "settings": settings, "parameters": parameters,
				"node_position": {"x": n.get("position", [0, 0])[0], "y": n.get("position", [0, 0])[1] + (850 if stage == "process" else 0)}}
			if name == "Material":
				node["particle_defaults"] = {}
				for mode in document.render_modes: parameters[mode] = true
			if n.kind == "custom":
				var inputs: Array = []
				var arguments: Array[String] = []
				var declarations: Array[String] = []
				for p in n.get("input_ports", []):
					var type: String = MMGenParticle.value_type(p.type)
					var rules = preload("res://addons/material_maker/particles/compiler.gd").new()
					var value = n.get("inputs", {}).get(p.name, {}).get("value", Interface.default_value(p.type))
					inputs.append({"name": p.name, "label": p.name, "type": type, "default": rules.literal(p.type, value, n.id) if not p.type.begins_with("sampler") else "missing_texture"})
					arguments.append("$" + p.name + "($uv)")
					declarations.append(p.type + " " + p.name)
				var type: String = MMGenParticle.value_type(n.data_type)
				node.type = "shader"
				node["shader_model"] = {"name": n.id.capitalize(), "parameters": [], "inputs": inputs,
					"outputs": [{"type": type, type: "$(name)_evaluate(" + ", ".join(arguments) + ")"}],
					"instance": n.data_type + " $(name)_evaluate(" + ", ".join(declarations) + ") {\n" + n.code + "\n}"}
				node.erase("settings")
			nodes.append(node)
		for n in document.stages[stage].nodes:
			var ports: Dictionary = Interface.ports(n, stage, document.uniforms)
			for i in ports.inputs.size():
				var binding: Dictionary = n.get("inputs", {}).get(ports.inputs[i].name, {})
				if binding.has("value"):
					var constant_name: String = stage + "_" + n.id + "_" + ports.inputs[i].name
					nodes.append({"name": constant_name, "type": "particle_node", "settings": {"kind": "constant", "data_type": ports.inputs[i].type, "value": binding.value},
						"node_position": {"x": -400, "y": 170 * connections.size()}})
					connections.append({"from": constant_name, "from_port": 0, "to": "Material" if stage == "start" and n.kind == "output" else stage + "_" + n.id, "to_port": i})
					continue
				if not binding.has("node"): continue
				var source_ports: Array = Interface.ports(descriptions[binding.node], stage, document.uniforms).outputs
				for j in source_ports.size():
					if source_ports[j].name == binding.get("port", "value"):
						connections.append({"from": stage + "_" + str(binding.node), "from_port": j,
							"to": "Material" if stage == "start" and n.kind == "output" else stage + "_" + n.id, "to_port": i})
	var graph: MMGenGraph = await owner.get_node("/root/mm_loader").create_gen({"nodes": nodes, "connections": connections})
	owner.add_child(graph)
	return graph

static func compile(document: Dictionary, owner: Node) -> Dictionary:
	var graph := await create(document, owner)
	var result: Dictionary = graph.get_node("Material").compile_shader()
	graph.queue_free()
	return result
