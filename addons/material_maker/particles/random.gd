extends RefCounted

# Godot ParticleProcessMaterial's integer hash and Park-Miller recurrence.
# Reference: https://github.com/godotengine/godot/blob/master/scene/resources/particle_process_material.cpp
const SHADER = """
uint mm_particle_hash(uint value) {
    value = ((value >> 16u) ^ value) * 73244475u;
    value = ((value >> 16u) ^ value) * 73244475u;
    return (value >> 16u) ^ value;
}
float mm_particle_random_next(inout uint state) {
    int current = int(state);
    if (current == 0) { current = 305420679; }
    int quotient = current / 127773;
    current = 16807 * (current - quotient * 127773) - 2836 * quotient;
    if (current < 0) { current += 2147483647; }
    state = uint(current);
    return float(state % 65536u) / 65535.0;
}
vec4 mm_particle_random(uint particle_id, uint system_seed, uint offset) {
    uint state = mm_particle_hash(particle_id + 1u + system_seed + offset);
    float x = mm_particle_random_next(state);
    float y = mm_particle_random_next(state);
    float z = mm_particle_random_next(state);
    float w = mm_particle_random_next(state);
    return vec4(x, y, z, w);
}
"""
