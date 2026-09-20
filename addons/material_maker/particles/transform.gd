extends RefCounted

const SHADER = """
vec4 mm_particle_rotation_safe(vec4 q) {
	float magnitude = max(max(abs(q.x), abs(q.y)), max(abs(q.z), abs(q.w)));
	if (!(magnitude > 0.000001) || isinf(magnitude)) { return vec4(0.0, 0.0, 0.0, 1.0); }
	return normalize(q / magnitude);
}
vec3 mm_particle_scale(mat4 transform) {
	mat3 basis = mat3(transform);
	float direction = determinant(basis) < 0.0 ? -1.0 : 1.0;
	return direction * vec3(length(basis[0]), length(basis[1]), length(basis[2]));
}
vec4 mm_particle_rotation(mat4 transform) {
	mat3 b = mat3(transform);
	if (length(b[0]) <= 0.000001 || length(b[1]) <= 0.000001 || length(b[2]) <= 0.000001) { return vec4(0.0, 0.0, 0.0, 1.0); }
	b[0] = normalize(b[0]); b[1] = normalize(b[1]); b[2] = normalize(b[2]);
	float det = determinant(b);
	if (abs(det) <= 0.000001) { return vec4(0.0, 0.0, 0.0, 1.0); }
	if (det < 0.0) { b *= -1.0; }
	b[1] = normalize(b[1] - b[0] * dot(b[0], b[1]));
	b[2] = cross(b[0], b[1]);
	float trace = b[0][0] + b[1][1] + b[2][2];
	vec4 q;
	if (trace > 0.0) {
		float s = sqrt(trace + 1.0) * 2.0;
		q = vec4((b[1][2]-b[2][1])/s, (b[2][0]-b[0][2])/s, (b[0][1]-b[1][0])/s, s*0.25);
	} else if (b[0][0] > b[1][1] && b[0][0] > b[2][2]) {
		float s = sqrt(1.0+b[0][0]-b[1][1]-b[2][2])*2.0;
		q = vec4(s*0.25, (b[1][0]+b[0][1])/s, (b[2][0]+b[0][2])/s, (b[1][2]-b[2][1])/s);
	} else if (b[1][1] > b[2][2]) {
		float s = sqrt(1.0+b[1][1]-b[0][0]-b[2][2])*2.0;
		q = vec4((b[1][0]+b[0][1])/s, s*0.25, (b[2][1]+b[1][2])/s, (b[2][0]-b[0][2])/s);
	} else {
		float s = sqrt(1.0+b[2][2]-b[0][0]-b[1][1])*2.0;
		q = vec4((b[2][0]+b[0][2])/s, (b[2][1]+b[1][2])/s, s*0.25, (b[0][1]-b[1][0])/s);
	}
	return mm_particle_rotation_safe(q);
}
mat3 mm_particle_basis(vec4 rotation, vec3 scale_value) {
	vec4 q = mm_particle_rotation_safe(rotation);
	vec3 x = vec3(1.0-2.0*(q.y*q.y+q.z*q.z), 2.0*(q.x*q.y+q.z*q.w), 2.0*(q.x*q.z-q.y*q.w));
	vec3 y = vec3(2.0*(q.x*q.y-q.z*q.w), 1.0-2.0*(q.x*q.x+q.z*q.z), 2.0*(q.y*q.z+q.x*q.w));
	vec3 z = vec3(2.0*(q.x*q.z+q.y*q.w), 2.0*(q.y*q.z-q.x*q.w), 1.0-2.0*(q.x*q.x+q.y*q.y));
	return mat3(x*scale_value.x, y*scale_value.y, z*scale_value.z);
}
"""
