shader_type particles;
render_mode disable_force;
float dot2(vec2 x) {
	return dot(x, x);
}

float rand(vec2 x) {
    return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
}

vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14))) * 43758.5);
}

vec3 rand3(vec2 x) {
    return fract(cos(mod(vec3(dot(x, vec2(13.9898, 8.141)),
							  dot(x, vec2(3.4562, 17.398)),
                              dot(x, vec2(13.254, 5.867))), vec3(3.14))) * 43758.5);
}

float param_rnd(float minimum, float maximum, float seed) {
	return minimum+(maximum-minimum)*rand(vec2(seed));
}

float param_rndi(float minimum, float maximum, float seed) {
	return floor(param_rnd(minimum, maximum + 1.0, seed));
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = c.g < c.b ? vec4(c.bg, K.wz) : vec4(c.gb, K.xy);
	vec4 q = c.r < p.x ? vec4(p.xyw, c.r) : vec4(c.r, p.yzx);

	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
const float p_o167050741604_value = 0.350000000;
const float p_o167017187165_r = 0.050000000;
const float p_o167017187165_g = 0.200000000;
const float p_o167017187165_b = 1.000000000;
const float p_o167017187165_a = 0.000000000;
const float p_o167000409930_r = 1.000000000;
const float p_o167000409930_g = 0.300000000;
const float p_o167000409930_b = 0.050000000;
const float p_o167000409930_a = 1.000000000;
const float p_o166966855511_x = 0.000000000;
const float p_o166966855511_y = -3.000000000;
const float p_o166966855511_z = 0.000000000;
const float p_o166950078292_x = 1.000000000;
const float p_o166950078292_y = 4.000000000;
const float p_o166950078292_z = 0.000000000;
// #globals: size_mix (o167067518805)
// #globals: life (o166983632716)
float mm_particle_life_fraction() { return 0.0; }
void mm_evaluate(vec3 mm_position, vec3 mm_velocity, float mm_age, float mm_life_fraction, float mm_delta,
                 out vec3 initial_position, out vec3 initial_velocity, out vec3 acceleration,
                 out vec4 particle_color, out float particle_scale) {
    vec2 uv = vec2(0.0);

// #output0: life (o166983632716)
float o166983632716_0_1_f = mm_life_fraction;

// #output0: initial_size (o167050741604)
float o167050741604_0_1_f = p_o167050741604_value;

// #output0: size_mix (o167067518805)
float o167067518805_0_1_f = mix(o167050741604_0_1_f, 0.0, clamp(o166983632716_0_1_f, 0.0, 1.0));

// #output0: blue (o167017187165)
vec4 o167017187165_0_1_rgba = vec4(p_o167017187165_r, p_o167017187165_g, p_o167017187165_b, p_o167017187165_a);

// #output0: orange (o167000409930)
vec4 o167000409930_0_1_rgba = vec4(p_o167000409930_r, p_o167000409930_g, p_o167000409930_b, p_o167000409930_a);

// #output0: color_mix (o167033964380)
vec4 o167033964380_0_1_rgba = mix(o167000409930_0_1_rgba, o167017187165_0_1_rgba, clamp(o166983632716_0_1_f, 0.0, 1.0));

// #output0: gravity (o166966855511)
vec3 o166966855511_0_1_rgb = vec3(p_o166966855511_x, p_o166966855511_y, p_o166966855511_z);

// #output0: velocity (o166950078292)
vec3 o166950078292_0_1_rgb = vec3(p_o166950078292_x, p_o166950078292_y, p_o166950078292_z);

    initial_position = vec3(0.0);
    initial_velocity = o166950078292_0_1_rgb;
    acceleration = o166966855511_0_1_rgb;
    particle_color = o167033964380_0_1_rgba;
    particle_scale = max(o167067518805_0_1_f, 0.0);
}
void start() {
    CUSTOM.x = 0.0;
    vec3 initial_position;
    vec3 initial_velocity;
    vec3 acceleration;
    vec4 particle_color;
    float particle_scale;
    mm_evaluate(vec3(0.0), vec3(0.0), 0.0, 0.0, 0.0,
                initial_position, initial_velocity, acceleration, particle_color, particle_scale);
    TRANSFORM[3] = EMISSION_TRANSFORM * vec4(initial_position, 1.0);
    VELOCITY = (EMISSION_TRANSFORM * vec4(initial_velocity, 0.0)).xyz;
    COLOR = particle_color;
    float mm_scale = particle_scale;
    TRANSFORM[0] = vec4(mm_scale, 0.0, 0.0, 0.0);
    TRANSFORM[1] = vec4(0.0, mm_scale, 0.0, 0.0);
    TRANSFORM[2] = vec4(0.0, 0.0, mm_scale, 0.0);
}
void process() {
    CUSTOM.x += DELTA;
    vec3 initial_position;
    vec3 initial_velocity;
    vec3 acceleration;
    vec4 particle_color;
    float particle_scale;
    mm_evaluate(TRANSFORM[3].xyz, VELOCITY, CUSTOM.x, clamp(CUSTOM.x / max(LIFETIME, 0.000001), 0.0, 1.0), DELTA,
                initial_position, initial_velocity, acceleration, particle_color, particle_scale);
    VELOCITY += acceleration * DELTA;
    COLOR = particle_color;
    float mm_scale = particle_scale;
    TRANSFORM[0] = vec4(mm_scale, 0.0, 0.0, 0.0);
    TRANSFORM[1] = vec4(0.0, mm_scale, 0.0, 0.0);
    TRANSFORM[2] = vec4(0.0, 0.0, mm_scale, 0.0);
    if (CUSTOM.x >= LIFETIME) { ACTIVE = false; }
}
