extends RefCounted

const SHADER = """
vec4 mm_quat_normalize(vec4 q) {
	float magnitude = max(max(abs(q.x), abs(q.y)), max(abs(q.z), abs(q.w)));
	if (!(magnitude > 0.000001) || isinf(magnitude)) { return vec4(0.0, 0.0, 0.0, 1.0); }
	return normalize(q / magnitude);
}
vec4 mm_quat_multiply(vec4 a, vec4 b) {
	a = mm_quat_normalize(a);
	b = mm_quat_normalize(b);
	return mm_quat_normalize(vec4(a.w*b.xyz + b.w*a.xyz + cross(a.xyz, b.xyz), a.w*b.w - dot(a.xyz, b.xyz)));
}
vec4 mm_quat_euler_yxz(vec3 angles) {
	vec3 s = sin(angles * 0.5);
	vec3 c = cos(angles * 0.5);
	return mm_quat_multiply(mm_quat_multiply(vec4(0.0, s.y, 0.0, c.y), vec4(s.x, 0.0, 0.0, c.x)), vec4(0.0, 0.0, s.z, c.z));
}
"""
