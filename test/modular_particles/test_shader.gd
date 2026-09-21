extends SceneTree
const Compiler = preload("res://addons/material_maker/particles/modular/compiler.gd")
const Fixtures = preload("fixtures.gd")
var finished := false
var error := ""
var effect: MMParticleEffect

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var doc := Fixtures.basic()
	for i in 33:
		doc.attributes.append({"id":"v"+str(i),"name":"V","type":"vec4","default":[1.0,2.0,3.0,4.0]})
	doc.attributes.append({"id":"exact","name":"Exact uint","type":"uint","default":4294967295})
	var result := Compiler.new().compile(doc)
	if not result.errors.is_empty():
		print(result.errors)
		quit(1)
		return
	effect = result.effect
	RenderingServer.call_on_render_thread(compile_gpu)
	while not finished: await process_frame
	print("MODULAR_SHADER ", "PASS" if error.is_empty() else "FAIL", " ",error)
	quit(0 if error.is_empty() else 1)

func compile_gpu() -> void:
	var rd := RenderingServer.get_rendering_device()
	var source := RDShaderSource.new()
	source.source_compute = effect.compute_source
	var spirv := rd.shader_compile_spirv_from_source(source)
	error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if error.is_empty():
		var shader := rd.shader_create_from_spirv(spirv)
		var pipeline := rd.compute_pipeline_create(shader)
		if not pipeline.is_valid(): error = "Invalid compute pipeline"
		else: rd.free_rid(pipeline)
		rd.free_rid(shader)
	finished = true
