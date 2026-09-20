"""Publish tested MMGenGraph examples and a reusable library-driven particle effect."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'build/particle-integration/app/exported'
DEST = ROOT / 'material_maker/examples/particles'


def layout(graph):
    nodes = {n['name']: n for n in graph.get('nodes', [])}
    predecessors = {name: [] for name in nodes}
    for edge in graph.get('connections', []):
        predecessors[edge['to']].append(edge['from'])
    ranks = {}

    def rank(name):
        if name not in ranks:
            ranks[name] = max((rank(p) + 1 for p in predecessors[name]), default=0)
        return ranks[name]

    rows = {}
    for name, node in nodes.items():
        column = rank(name)
        row = rows.get(column, 0)
        node['node_position'] = {'x': column * 420, 'y': row * 480}
        rows[column] = row + 1
        if 'nodes' in node:
            layout(node)


def use_stock_nodes(graph):
    for node in graph.get('nodes', []):
        if 'nodes' in node:
            use_stock_nodes(node)
        if node.get('type') != 'particle_node':
            continue
        settings = node['settings']
        kind, data_type = settings['kind'], settings.get('data_type')
        if kind == 'uniform':
            parameters = node.setdefault('parameters', {})
            count = int(parameters.get('array_size', 0))
            parameters.setdefault('is_array', count > 0)
            parameters['array_size'] = count if count > 0 else 1
        if kind != 'constant' or data_type not in ['float', 'vec3', 'vec4']:
            if kind in ['constant', 'operator', 'compose', 'split', 'convert', 'transform',
                        'select', 'uniform', 'array_get', 'sample', 'evaluate', 'bridge']:
                settings['editor_profile'] = 'supplemental_v1'
                for key in ['data_type', 'source_type', 'operation', 'function_type', 'sampler_type']:
                    node.get('parameters', {}).pop(key, None)
            continue
        parameters = node.get('parameters', {})
        value = settings.get('value', 0.0)
        value = parameters.get('value', value) if data_type == 'float' else [parameters.get('v' + str(i), v) for i, v in enumerate(value)]
        node.pop('settings')
        if data_type == 'float':
            node.update(type='uniform_greyscale', parameters={'color': value})
        elif data_type == 'vec3':
            node.update(type='math_v3', parameters={'op': 0, 'clamp': False,
                **{'d_in1_' + axis: value[i] for i, axis in enumerate('xyz')}})
        else:
            node.update(type='uniform', parameters={'color': dict(type='Color', **dict(zip('rgba', value)))})
    integrate = next((n for n in graph.get('nodes', []) if n['name'] == 'process_integrate'), None)
    if integrate is not None:
        integrate.pop('shader_model', None)
        integrate.update(type='math_v3', parameters={'op': 0, 'clamp': False})
        graph['nodes'].append({'name': 'AccelerationStep', 'type': 'math_v3', 'parameters': {'op': 2, 'clamp': False}})
        for edge in graph['connections']:
            if edge['to'] == 'process_integrate' and edge['to_port'] in [1, 2]:
                edge['to'] = 'AccelerationStep'
                edge['to_port'] -= 1
        graph['connections'].append({'from': 'AccelerationStep', 'from_port': 0, 'to': 'process_integrate', 'to_port': 1})


def write(name, document):
    layout(document)
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / (name + '.ptex')).write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8')


def main():
    examples = {}
    for name in ['blank', 'gravity', 'collision', 'subparticle', 'library_module']:
        examples[name] = json.loads((SOURCE / (name + '.ptex')).read_text(encoding='utf-8'))
        use_stock_nodes(examples[name])
        write(name, examples[name])
    effect = copy.deepcopy(examples['gravity'])
    module = copy.deepcopy(next(n for n in examples['library_module']['nodes'] if 'nodes' in n))
    module['name'] = 'ColorModule'
    module['label'] = 'Noise Color Module'
    effect['nodes'].extend([module,
        {'name': 'ParticleIndex', 'type': 'particle_node', 'settings': {'kind': 'input', 'builtin': 'NUMBER'}},
        {'name': 'ColorCoordinates', 'type': 'shader', 'shader_model': {
            'name': 'Particle Color Coordinates', 'parameters': [],
            'inputs': [{'name': 'index', 'label': 'Index', 'type': 'particle_uint', 'default': '0u'}],
            'outputs': [{'type': 'particle_vec2', 'particle_vec2': 'vec2(float($index($uv)) * 0.037, 0.5)'}]
        }}])
    old_colors = [e for e in effect['connections'] if e['to'] == 'Material' and e['to_port'] == 1]
    effect['connections'] = [e for e in effect['connections'] if e not in old_colors]
    for old in old_colors:
        if not any(e['from'] == old['from'] for e in effect['connections']):
            effect['nodes'] = [n for n in effect['nodes'] if n['name'] != old['from']]
    effect['connections'].extend([
        {'from': 'ParticleIndex', 'from_port': 0, 'to': 'ColorCoordinates', 'to_port': 0},
        {'from': 'ColorCoordinates', 'from_port': 0, 'to': 'ColorModule', 'to_port': 0},
        {'from': 'ColorModule', 'from_port': 0, 'to': 'Material', 'to_port': 1},
        {'from': 'ColorModule', 'from_port': 0, 'to': 'process_output', 'to_port': 1}])
    write('library_gravity', effect)
    write('quaternion_rotation', json.loads((SOURCE / 'quaternion_rotation.ptex').read_text(encoding='utf-8')))
    print(f'Published {len(examples) + 2} MMGenGraph examples to {DEST}')


if __name__ == '__main__':
    main()
