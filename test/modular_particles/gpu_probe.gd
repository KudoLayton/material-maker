extends SceneTree

var multimesh: MultiMesh
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var bindings := RID()
var dispatched := false
var error := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(128, 128)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position.z = 3.0
	world.add_child(camera)
	camera.current = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	multimesh = MultiMesh.new()
	RenderingServer.multimesh_allocate_data(multimesh.get_rid(), 1, RenderingServer.MULTIMESH_TRANSFORM_3D, true, true, true)
	multimesh.mesh = mesh
	RenderingServer.multimesh_set_custom_aabb(multimesh.get_rid(), AABB(Vector3(-2,-2,-2), Vector3(4,4,4)))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	world.add_child(instance)
	RenderingServer.call_on_render_thread(dispatch)
	for frame in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	var image := root.get_texture().get_image()
	var center := image.get_pixel(64, 64)
	var ok := dispatched and center.r > 0.8 and center.g < 0.2 and center.b < 0.2
	print("MODULAR_GPU_PROBE ", "PASS" if ok else "FAIL", " center=", center, " version=", Engine.get_version_info().string)
	image.save_png("user://gpu_probe.png")
	world.queue_free()
	await process_frame
	RenderingServer.call_on_render_thread(cleanup)
	await process_frame
	multimesh = null
	await process_frame
	quit(0 if ok else 1)

func dispatch() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		error = "Main RenderingDevice unavailable"
		return
	var source := RDShaderSource.new()
	source.source_compute = """#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Instances { float values[]; };
layout(set=0,binding=1,std430) buffer Commands { uint command[]; };
void main() {
 for (uint i=0u;i<20u;i++) values[i]=0.0;
 values[0]=1.0; values[5]=1.0; values[10]=1.0;
 values[12]=1.0; values[15]=1.0;
 command[1]=1u;
}
"""
	var spirv := rd.shader_compile_spirv_from_source(source)
	error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var uniforms: Array[RDUniform] = []
	var buffers := [RenderingServer.multimesh_get_buffer_rd_rid(multimesh.get_rid()), RenderingServer.multimesh_get_command_buffer_rd_rid(multimesh.get_rid())]
	for i in buffers.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = i
		uniform.add_id(buffers[i])
		uniforms.append(uniform)
	bindings = rd.uniform_set_create(uniforms, shader, 0)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, bindings, 0)
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	dispatched = true

func cleanup() -> void:
	if rd == null: return
	for rid in [bindings, pipeline, shader]:
		if rid.is_valid(): rd.free_rid(rid)
	preload("res://addons/mm_gpu_particles/multimesh_lifetime.gd").release(multimesh)
	# Exercise repeated allocations as well as the rendered allocation.
	for i in 32:
		var temporary := MultiMesh.new()
		RenderingServer.multimesh_allocate_data(temporary.get_rid(), 4, RenderingServer.MULTIMESH_TRANSFORM_3D, true, true, true)
		temporary.mesh = QuadMesh.new()
		preload("res://addons/mm_gpu_particles/multimesh_lifetime.gd").release(temporary)
