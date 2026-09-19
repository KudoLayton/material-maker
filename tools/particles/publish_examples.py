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


def write(name, document):
    layout(document)
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / (name + '.ptex')).write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8')


def main():
    examples = {}
    for name in ['blank', 'gravity', 'collision', 'subparticle', 'library_module']:
        examples[name] = json.loads((SOURCE / (name + '.ptex')).read_text(encoding='utf-8'))
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
    print(f'Published {len(examples) + 1} MMGenGraph examples to {DEST}')


if __name__ == '__main__':
    main()
