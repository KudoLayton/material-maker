"""Rebuild the distributable nodes and self-contained example graphs."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NODES = {}


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def inp(name, kind, default, label=None):
    return dict(name=name, type=kind, default=default, label=label or name.title())


def out(kind, expression, label='Value'):
    return dict(type=kind, shortdesc=label, **{kind: expression})


def param(name, default=0.0):
    return dict(name=name, label=name.title(), type='float', default=default,
                min=-10000, max=10000, step=0.01, control='None')


def node(key, title, inputs=(), outputs=(), parameters=(), global_code=''):
    data = dict(name='mm_particle_' + key, type='shader', node_position=dict(x=0, y=0),
                seed_int=0, parameters={}, shader_model=dict(
                    name=title, shortdesc=title,
                    longdesc='Godot particles only. Preview uses placeholder state; validate the exported effect in Godot.',
                    inputs=list(inputs), outputs=list(outputs), parameters=list(parameters),
                    code='', instance='', **{'global': global_code}))
    NODES[key] = data
    return data


node('scalar', 'Scalar', outputs=[out('f', '$value')], parameters=[param('value')])
node('vector', 'Vector', outputs=[out('rgb', 'vec3($x, $y, $z)')],
     parameters=[param('x'), param('y'), param('z')])
node('color', 'Color', outputs=[out('rgba', 'vec4($r, $g, $b, $a)')],
     parameters=[param(c, 1.0) for c in 'rgba'])

STATE = {
    'position': ('rgb', 'vec3', 'vec3(0.0)', 'mm_position'),
    'velocity': ('rgb', 'vec3', 'vec3(0.0)', 'mm_velocity'),
    'age': ('f', 'float', '0.0', 'mm_age'),
    'life_fraction': ('f', 'float', '0.0', 'mm_life_fraction'),
    'delta': ('f', 'float', '0.0', 'mm_delta'),
}
for key, (kind, glsl_type, default, argument) in STATE.items():
    function = 'mm_particle_' + key
    node(key, key.replace('_', ' ').title(), outputs=[out(kind, function + '()')],
         global_code=f'{glsl_type} {function}() {{ return {default}; }}')

for kind, label, zero, one in [('f', 'Scalar', '0.0', '1.0'),
                                ('rgb', 'Vector', 'vec3(0.0)', 'vec3(1.0)')]:
    for operation, symbol in [('add', '+'), ('subtract', '-'), ('multiply', '*'), ('divide', '/')]:
        node(label.lower() + '_' + operation, label + ' ' + operation.title(),
             [inp('a', kind, zero), inp('b', kind, one if operation in ('multiply', 'divide') else zero)],
             [out(kind, f'($a($uv) {symbol} $b($uv))')])
    node(label.lower() + '_clamp', label + ' Clamp',
         [inp('value', kind, zero), inp('minimum', kind, zero), inp('maximum', kind, one)],
         [out(kind, 'clamp($value($uv), $minimum($uv), $maximum($uv))')])

for kind, label, zero, one in [('f', 'Scalar', '0.0', '1.0'),
                                ('rgb', 'Vector', 'vec3(0.0)', 'vec3(1.0)'),
                                ('rgba', 'Color', 'vec4(0.0)', 'vec4(1.0)')]:
    node(label.lower() + '_mix', label + ' Mix',
         [inp('a', kind, zero), inp('b', kind, one), inp('weight', 'f', '0.0')],
         [out(kind, 'mix($a($uv), $b($uv), clamp($weight($uv), 0.0, 1.0))')])
node('compose', 'Compose Vector', [inp(c, 'f', '0.0') for c in 'xyz'],
     [out('rgb', 'vec3($x($uv), $y($uv), $z($uv))')])
node('split', 'Split Vector', [inp('vector', 'rgb', 'vec3(0.0)')],
     [out('f', f'($vector($uv)).{c}', c.upper()) for c in 'xyz'])
node('scale_vector', 'Scale Vector', [inp('vector', 'rgb', 'vec3(0.0)'), inp('factor', 'f', '1.0')],
     [out('rgb', '($vector($uv) * $factor($uv))')])

output = node('output', 'Particles 3D Output (No Preview)', [
    inp('initial_position', 'rgb', 'vec3(0.0)', 'Start: Position'),
    inp('initial_velocity', 'rgb', 'vec3(0.0)', 'Start: Velocity'),
    inp('acceleration', 'rgb', 'vec3(0.0)', 'Update: Acceleration'),
    inp('color', 'rgba', 'vec4(1.0)', 'Appearance: Color'),
    inp('scale', 'f', '1.0', 'Appearance: Scale'),
])
output['type'] = 'material_export'
output['export'] = {}
output['shader_model']['preview_shader'] = [
    'shader_type spatial;', 'render_mode unshaded;',
    'void fragment() { ALBEDO = vec3(0.15); }',
]
custom = ['func process_option_particle_state(s : String, is_declaration : bool = false) -> String:',
          '\tif is_declaration:', '\t\treturn s']
for key, (_, _, _, argument) in STATE.items():
    custom.append(f'\ts = s.replace("mm_particle_{key}()", "{argument}")')
custom.append('\treturn s')

shader = '''shader_type particles;
render_mode disable_force;
$definitions float_uniform_to_const

void mm_evaluate(vec3 mm_position, vec3 mm_velocity, float mm_age, float mm_life_fraction, float mm_delta,
                 out vec3 initial_position, out vec3 initial_velocity, out vec3 acceleration,
                 out vec4 particle_color, out float particle_scale) {
    vec2 uv = vec2(0.0);
$begin_generate particle_state
    initial_position = $initial_position(uv);
    initial_velocity = $initial_velocity(uv);
    acceleration = $acceleration(uv);
    particle_color = $color(uv);
    particle_scale = max($scale(uv), 0.0);
$end_generate
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
'''
material = '''[gd_resource type="ShaderMaterial" load_steps=2 format=3]
[ext_resource type="Shader" path="$(file_prefix).gdshader" id="1"]
[resource]
shader = ExtResource("1")
'''
output['shader_model']['exports'] = {'Godot 4/Particles 3D': {
    'name': 'Godot 4/Particles 3D', 'export_extension': 'tres', 'custom': custom,
    'files': [dict(type='template', file_name='$(path_prefix).gdshader', template=shader.splitlines()),
              dict(type='template', file_name='$(path_prefix).tres', template=material.splitlines())],
}}

library = []
for key, data in NODES.items():
    write(ROOT / 'nodes' / (data['name'] + '.mmg'), data)
    library.append(dict(name=data['name'], type=data['name'],
                        tree_item='Godot Particles/' + data['shader_model']['name']))
write(ROOT / 'particles.json', dict(name='Godot Particles', lib=library))


def instance(key, name, editor_x, editor_y, **parameters):
    data = copy.deepcopy(NODES[key])
    data.update(name=name, node_position=dict(x=editor_x, y=editor_y), parameters=parameters)
    return data


def edge(source, target_port, target='output', source_port=0):
    return dict(**{'from': source, 'from_port': source_port, 'to': target, 'to_port': target_port})


def graph(nodes, connections):
    return dict(type='graph', name='particles', label='Godot Particles', nodes=nodes, connections=connections)


write(ROOT / 'examples/blank.ptex', graph([instance('output', 'output', 400, 0)], []))
write(ROOT / 'tests/shared_stages.ptex', graph([
    instance('output', 'output', 400, 0), instance('vector', 'shared', 0, 0, x=1.0, y=2.0, z=3.0),
], [edge('shared', 1), edge('shared', 2)]))
write(ROOT / 'examples/gravity.ptex', graph([
    instance('output', 'output', 900, 0),
    instance('vector', 'velocity', 0, 0, x=1.0, y=4.0, z=0.0),
    instance('vector', 'gravity', 0, 220, x=0.0, y=-3.0, z=0.0),
    instance('life_fraction', 'life', 0, 440),
    instance('color', 'orange', 250, 300, r=1.0, g=0.3, b=0.05, a=1.0),
    instance('color', 'blue', 250, 500, r=0.05, g=0.2, b=1.0, a=0.0),
    instance('color_mix', 'color_mix', 570, 330),
    instance('scalar', 'initial_size', 250, 710, value=0.35),
    instance('scalar_mix', 'size_mix', 570, 650),
], [edge('velocity', 1), edge('gravity', 2), edge('orange', 0, 'color_mix'),
    edge('blue', 1, 'color_mix'), edge('life', 2, 'color_mix'), edge('color_mix', 3),
    edge('initial_size', 0, 'size_mix'), edge('life', 2, 'size_mix'), edge('size_mix', 4)]))
# The end size is zero, not the generic mix node's default of one.
path = ROOT / 'examples/gravity.ptex'
data = json.loads(path.read_text())
next(n for n in data['nodes'] if n['name'] == 'size_mix')['shader_model']['inputs'][1]['default'] = '0.0'
write(path, data)

write(ROOT / 'tests/state_inputs.ptex', graph([
    instance('output', 'output', 600, 0),
    instance('position', 'position', 0, 0),
    instance('velocity', 'velocity', 0, 150),
    instance('age', 'age', 0, 300),
    instance('life_fraction', 'life', 0, 450),
    instance('delta', 'delta', 0, 600),
    instance('compose', 'compose', 300, 300),
], [edge('position', 0), edge('velocity', 1), edge('age', 0, 'compose'),
    edge('life', 1, 'compose'), edge('delta', 2, 'compose'), edge('compose', 2), edge('age', 4)]))
