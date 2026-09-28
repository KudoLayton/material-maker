extends RefCounted
const SOURCE := """#version 450
layout(local_size_x=128) in;
const float PI=3.14159265358979323846;
const float TAU=6.28318530717958647692;
const float E=2.71828182845904523536;
layout(set=0,binding=0,std430) buffer Attributes { uint data[]; };
layout(set=0,binding=1,std430) buffer ScanA { uint scan_a[]; };
layout(set=0,binding=2,std430) buffer ScanB { uint scan_b[]; };
layout(set=0,binding=3,std430) buffer Instances { float instances[]; };
layout(set=0,binding=4,std430) buffer Commands { uint commands[]; };
layout(set=0,binding=5,std430) readonly buffer Parameters { uint params[]; };
layout(push_constant,std430) uniform Push {
 uint capacity; uint phase; uint offset; uint scan_read;
 float delta; float time; uint seed; uint spawn_count;
 uint spawn_base; uint surfaces; uint render_dimension; uint unused1;
} p;
struct ParticleState {
@FIELDS@
};
uint mm_hash(uint v) {
 v=((v>>16u)^v)*73244475u; v=((v>>16u)^v)*73244475u;
 return (v>>16u)^v;
}
float mm_next(inout uint state) {
 int current=int(state);
 if (current==0) current=305420679;
 int q=current/127773;
 current=16807*(current-q*127773)-2836*q;
 if(current<0) current+=2147483647;
 state=uint(current); return float(state%65536u)/65535.0;
}
vec4 mm_random(uint id,uint seed,uint offset) {
 uint state=mm_hash(id+1u+seed+offset);
 float x=mm_next(state); float y=mm_next(state);
 float z=mm_next(state); float w=mm_next(state);
 return vec4(x,y,z,w);
}
mat3 mm_basis(vec4 q) {
 float norm=dot(q,q);
 q=norm>1e-12 ? q*inversesqrt(norm) : vec4(0,0,0,1);
 float x=q.x,y=q.y,z=q.z,w=q.w;
 return mat3(1-2*y*y-2*z*z,2*x*y+2*z*w,2*x*z-2*y*w,
             2*x*y-2*z*w,1-2*x*x-2*z*z,2*y*z+2*x*w,
             2*x*z+2*y*w,2*y*z-2*x*w,1-2*x*x-2*y*y);
}
@FUNCTIONS@
uint prefix(uint i) { return p.scan_read==0u ? scan_a[i] : scan_b[i]; }
void main() {
 uint i=gl_GlobalInvocationID.x;
 if(i>=p.capacity) return;
 if(p.phase==0u) {
  bool alive=data[@ALIVE_OFFSET@u*p.capacity+i]!=0u;
  scan_a[i]=(p.offset==0u ? !alive : alive) ? 1u : 0u;
  return;
 }
 if(p.phase==1u) {
  uint value=prefix(i);
  if(i>=p.offset) value+=prefix(i-p.offset);
  if(p.scan_read==0u) scan_b[i]=value; else scan_a[i]=value;
  return;
 }
 ParticleState s;
 @LOAD@
 if(p.phase==2u) {
  bool just_spawned=false;
  s.just_spawned=false;
  if(!@ALIVE@) {
   uint rank=prefix(i)-1u;
   if(rank>=p.spawn_count) return;
   @DEFAULTS@
   @ALIVE@=true;
   @PARTICLE_ID@=p.spawn_base+rank;
   @LIFETIME@=uintBitsToFloat(params[16]);
   if(params[17]!=0u) @POSITION@=vec3(uintBitsToFloat(params[12]),uintBitsToFloat(params[13]),uintBitsToFloat(params[14]));
   just_spawned=true;
   s.just_spawned=true;
   @SPAWN@
  }
  @AGE@+=p.delta;
  if(@ALIVE@ && @LIFETIME@>0.0) {
   @UPDATE@
  }
  if(@AGE@>=@LIFETIME@ || @LIFETIME@<=0.0 || isnan(@LIFETIME@) || isinf(@LIFETIME@)) @ALIVE@=false;
  if(any(isnan(@POSITION@)) || any(isinf(@POSITION@)) || any(isnan(@SCALE@)) || any(isinf(@SCALE@))) @ALIVE@=false;
  @SAVE@
  return;
 }
 if(p.phase==3u) {
  if(p.render_dimension==2u) {
   uint count=prefix(p.capacity-1u);
   // Clear only the tail, not dead source indices: compaction may write those.
   if(i>=count) for(uint c=0u;c<16u;c++) instances[i*16u+c]=0.0;
   if(!@ALIVE@) return;
   uint target=(prefix(i)-1u)*16u;
   float units=uintBitsToFloat(params[18]);
   float fy=params[19]!=0u ? -1.0 : 1.0;
   mat3 b=mm_basis(@ROTATION@);
   b[0]*=@SCALE@.x; b[1]*=@SCALE@.y;
   // F * B.xy * F converts both coordinate bases (keeps sprite UV upright).
   vec2 x=units*vec2(b[0].x,fy*b[0].y);
   vec2 y=units*vec2(fy*b[1].x,b[1].y);
   vec2 pos=units*vec2(@POSITION@.x,fy*@POSITION@.y);
   if(params[17]!=0u) {
    mat2 inv=mat2(uintBitsToFloat(params[20]),uintBitsToFloat(params[24]),
                  uintBitsToFloat(params[21]),uintBitsToFloat(params[25]));
    pos=inv*pos+vec2(uintBitsToFloat(params[23]),uintBitsToFloat(params[27]));
    x=inv*x; y=inv*y;
   }
   instances[target]=x.x; instances[target+1u]=y.x;
   instances[target+2u]=0.0; instances[target+3u]=pos.x;
   instances[target+4u]=x.y; instances[target+5u]=y.y;
   instances[target+6u]=0.0; instances[target+7u]=pos.y;
   for(uint c=0u;c<4u;c++) {
    instances[target+8u+c]=@COLOR@[c];
    instances[target+12u+c]=@RENDER_CUSTOM@[c];
   }
   return;
  }
  if(i==0u) {
   uint count=prefix(p.capacity-1u);
   for(uint surface=0u;surface<p.surfaces;surface++) commands[surface*5u+1u]=count;
  }
  if(!@ALIVE@) return;
  uint target=(prefix(i)-1u)*20u;
  mat3 basis=mm_basis(@ROTATION@);
  basis[0]*=@SCALE@.x; basis[1]*=@SCALE@.y; basis[2]*=@SCALE@.z;
  for(uint row=0u;row<3u;row++) {
   for(uint col=0u;col<3u;col++) instances[target+row*4u+col]=basis[col][row];
   instances[target+row*4u+3u]=@POSITION@[row];
  }
  for(uint component=0u;component<4u;component++) {
   instances[target+12u+component]=@COLOR@[component];
   instances[target+16u+component]=@RENDER_CUSTOM@[component];
  }
 }
}
"""
