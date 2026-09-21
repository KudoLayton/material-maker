extends RefCounted
## Test-only oracle: execute freshly generated legacy start/process bodies in
## an isolated compute harness with Godot's previous-velocity integration order.
## This is NOT a runtime backend or an authoring/import feature.
const Interface = preload("res://addons/material_maker/particles/interface.gd")
const Literal = preload("res://addons/material_maker/particles/modular/compiler.gd")

static func source(legacy: Dictionary) -> String:
	var code := "#version 450\nlayout(local_size_x=128) in;\nlayout(set=0,binding=0,std430) buffer Output { float values[]; };\nlayout(push_constant) uniform Params { uint steps; uint count; uint seed; uint pad; } config;\n"
	var fields: Dictionary = Interface.BUILTINS.start.duplicate(true)
	fields.merge(Interface.BUILTINS.process)
	for name in fields:
		var type: String = fields[name].type
		var value := type + "(0)"
		if type == "bool": value = "false"
		if name in ["EMISSION_TRANSFORM","TRANSFORM"]: value = "mat4(1.0)"
		if name == "PI": value = "3.14159265358979323846"
		if name == "TAU": value = "6.28318530717958647692"
		if name == "E": value = "2.71828182845904523536"
		code += ("const " if name in ["PI","TAU","E"] else "") + type + " " + name + " = " + value + ";\n"
	for uniform in legacy.uniforms:
		code += "const " + uniform.type + " " + uniform.name + " = " + Literal.literal(uniform.type,uniform.value) + ";\n"
	for line in legacy.code.split("\n"):
		if line.begins_with("shader_type ") or line.begins_with("render_mode ") or line.begins_with("uniform "): continue
		code += line + "\n"
	code += """
void main() {
 uint i=gl_GlobalInvocationID.x;
 if(i>=config.count) return;
 INDEX=i; NUMBER=i; RANDOM_SEED=config.seed;
 LIFETIME=0.7; DELTA=1.0/60.0; ACTIVE=true; MASS=1.0; AMOUNT_RATIO=1.0;
 RESTART_POSITION=true; RESTART_ROT_SCALE=true; RESTART_VELOCITY=true; RESTART_COLOR=true; RESTART_CUSTOM=true;
 start();
 for(uint step=0u;step<config.steps;step++) {
  RESTART=(step==0u);
  TIME=float(step+1u)*DELTA;
  if(step>0u) TRANSFORM[3].xyz+=VELOCITY*DELTA;
  process();
 }
 vec3 scale=vec3(length(TRANSFORM[0].xyz),length(TRANSFORM[1].xyz),length(TRANSFORM[2].xyz));
 for(uint c=0u;c<3u;c++) {
  values[i*20u+c]=TRANSFORM[3][c];
  values[i*20u+3u+c]=VELOCITY[c];
  values[i*20u+6u+c]=scale[c];
  values[i*20u+10u+c]=USERDATA2[c];
  values[i*20u+15u+c]=VELOCITY[c]-USERDATA2[c]*scale.x;
 }
 values[i*20u+9u]=USERDATA1.x;
 values[i*20u+13u]=USERDATA3.x;
 values[i*20u+14u]=USERDATA3.y;
}
"""
	return code

static func evaluate(code: String, steps: int, count: int = 128) -> Dictionary:
	var rd := RenderingServer.get_rendering_device()
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = code
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): return {"error":error}
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var buffer := rd.storage_buffer_create(count*20*4)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer)
	var bindings := rd.uniform_set_create([uniform],shader,0)
	var push := PackedByteArray()
	push.resize(16)
	push.encode_u32(0,steps)
	push.encode_u32(4,count)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,bindings,0)
	rd.compute_list_set_push_constant(list,push,16)
	rd.compute_list_dispatch(list,ceili(count/128.0),1,1)
	rd.compute_list_end()
	var result := {"data":rd.buffer_get_data(buffer),"error":""}
	for rid in [bindings,pipeline,shader,buffer]: rd.free_rid(rid)
	return result
