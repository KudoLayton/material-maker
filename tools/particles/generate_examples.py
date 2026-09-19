"""Generate particle behavior fixtures; validate.py exports them as MMGenGraph examples."""
import copy
import json
from pathlib import Path

DEST = Path(__file__).resolve().parents[2] / 'test/particles/fixtures'


def document():
    return dict(type='particle_graph', version=1, target='Godot 4.7', uniforms=[],
                render_modes=[], target_project='', active_stage='start',
                stages={stage: dict(nodes=[
                    dict(id='entry', kind='entry', position=[40, 40], inputs={}),
                    dict(id='output', kind='output', position=[1000, 40], inputs={'exec': ref('entry', 'next')})
                ], view=dict(scroll=[0, 0], zoom=0.8, selection=[])) for stage in ['start', 'process']})


def ref(node, port='value'):
    return dict(node=node, port=port)


def add(doc, stage, id, kind, inputs=None, **fields):
    nodes = doc['stages'][stage]['nodes']
    nodes.append(dict(id=id, kind=kind, position=[40 + ((len(nodes)-2) % 3)*300, 200 + ((len(nodes)-2)//3)*170], inputs=inputs or {}, **fields))
    return ref(id)


def output(doc, stage):
    return doc['stages'][stage]['nodes'][1]['inputs']


def save(name, doc):
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / (name + '.json')).write_text(json.dumps(doc, indent=2) + '\n', encoding='utf-8')


def main():
    save('blank', document())
    gravity = document()
    gravity['uniforms'] = [dict(name='gravity', type='vec3', value=[0, -9.8, 0]),
                           dict(name='launch_speed', type='float', value=5)]
    output(gravity, 'start')['TRANSFORM'] = add(gravity, 'start', 'emitter_transform', 'input', builtin='EMISSION_TRANSFORM')
    speed = add(gravity, 'start', 'speed', 'uniform', uniform='launch_speed')
    number = add(gravity, 'start', 'number', 'input', builtin='NUMBER')
    launch = add(gravity, 'start', 'launch', 'custom', {'speed': speed, 'number': number}, data_type='vec3',
                 input_ports=[dict(name='speed', type='float'), dict(name='number', type='uint')],
                 code='float angle = float(number % 128u) * 2.399963;\nreturn vec3(cos(angle) * 1.5, speed, sin(angle) * 1.5);')
    output(gravity, 'start')['VELOCITY'] = launch
    output(gravity, 'start')['COLOR'] = dict(value=[0.2, 0.7, 1, 1])
    velocity = add(gravity, 'process', 'velocity', 'input', builtin='VELOCITY')
    delta = add(gravity, 'process', 'delta', 'input', builtin='DELTA')
    acceleration = add(gravity, 'process', 'gravity', 'uniform', uniform='gravity')
    update = add(gravity, 'process', 'integrate', 'custom', {'velocity': velocity, 'acceleration': acceleration, 'delta': delta},
                 data_type='vec3', input_ports=[dict(name='velocity', type='vec3'), dict(name='acceleration', type='vec3'), dict(name='delta', type='float')],
                 code='return velocity + acceleration * delta;')
    output(gravity, 'process')['VELOCITY'] = update
    save('gravity', gravity)
    collision = copy.deepcopy(gravity)
    collision['render_modes'] = ['collision_use_scale']
    hit = add(collision, 'process', 'collided', 'input', builtin='COLLIDED')
    normal = add(collision, 'process', 'normal', 'input', builtin='COLLISION_NORMAL')
    bounce = add(collision, 'process', 'bounce', 'custom', {'velocity': update, 'normal': normal}, data_type='vec3',
                 input_ports=[dict(name='velocity', type='vec3'), dict(name='normal', type='vec3')], code='return reflect(velocity, normal) * 0.8;')
    output(collision, 'process')['VELOCITY'] = add(collision, 'process', 'choose_velocity', 'select',
                                                 {'condition': hit, 'true': bounce, 'false': update}, data_type='vec3')
    save('collision', collision)
    emit = document()
    transform = add(emit, 'start', 'transform', 'input', builtin='EMISSION_TRANSFORM')
    output(emit, 'start')['TRANSFORM'] = transform
    flag = add(emit, 'start', 'position_flag', 'input', builtin='FLAG_EMIT_POSITION')
    rotation = add(emit, 'start', 'rotation_scale_flag', 'input', builtin='FLAG_EMIT_ROT_SCALE')
    flag = add(emit, 'start', 'flags', 'operator', {'a': flag, 'b': rotation}, operation='bit_or', data_type='uint')
    add(emit, 'start', 'emit_child', 'emit', {'exec': ref('entry', 'next'), 'transform': transform, 'flags': flag})
    output(emit, 'start')['exec'] = ref('emit_child', 'next')
    output(emit, 'start')['COLOR'] = add(emit, 'start', 'emission_status', 'select',
        {'condition': ref('emit_child', 'success'), 'true': dict(value=[0, 1, 0, 1]), 'false': dict(value=[1, 0, 0, 1])}, data_type='vec4')
    save('subparticle', emit)


if __name__ == '__main__':
    main()
