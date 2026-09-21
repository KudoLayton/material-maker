extends RefCounted
const Document = preload("res://addons/material_maker/particles/modular/document.gd")

static func basic() -> Dictionary:
	var doc := Document.create()
	doc.modules["initialize"] = {
		"name":"Initialize", "stages":["spawn"], "reads":[], "writes":["velocity"],
		"inputs":[{"id":"speed","name":"Speed","type":"float","default":1.0}],
		"graph":{"nodes":[
			{"id":"direction","op":"constant","type":"vec3","value":[1.0,0.0,0.0]},
			{"id":"speed","op":"parameter","parameter":"speed"},
			{"id":"velocity","op":"multiply","args":["direction","speed"]}
		],"outputs":{"velocity":"velocity"}}
	}
	doc.modules["integrate"] = {
		"name":"Integrate Velocity", "stages":["update"], "reads":["velocity","position"], "writes":["position"], "inputs":[],
		"graph":{"nodes":[
			{"id":"position","op":"read","attribute":"position"},
			{"id":"velocity","op":"read","attribute":"velocity"},
			{"id":"dt","op":"context","field":"delta"},
			{"id":"motion","op":"multiply","args":["velocity","dt"]},
			{"id":"result","op":"add","args":["position","motion"]}
		],"outputs":{"position":"result"}}
	}
	doc.stages.spawn = [{"id":"spawn1","module":"initialize","parameters":{}}]
	doc.stages.update = [{"id":"update1","module":"integrate","parameters":{}}]
	return doc
