"""Generate the particle entries for the existing Material Maker library."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    abi = (ROOT / 'addons/material_maker/particles/abi.gd').read_text(encoding='utf-8')
    builtins = json.loads(abi.split('const BUILTINS = ', 1)[1])
    entries = []

    def add(label, settings):
        entries.append({'name': re.sub(r'\W+', '_', label), 'type': 'particle_node',
                        'tree_item': 'Particles/' + label, 'settings': settings})

    merged = dict(builtins['start'], **builtins['process'])
    for name, definition in merged.items():
        add('Read/' + name, {'kind': 'input', 'builtin': name})
        if definition.get('write'):
            add('Write/' + name, {'kind': 'set', 'builtin': name})
    for stage in ['start', 'process']:
        add('Execution/' + stage.capitalize() + ' Entry', {'kind': 'entry', 'stage': stage})
    for kind, label in [('evaluate', 'Evaluate Function'), ('bridge', 'Value to Function')]:
        add('Library/' + label, {'kind': kind, 'function_type': 'rgba'})
    for kind, data_type in [('constant', 'float'), ('random', 'vec3'), ('operator', 'float'), ('convert', 'vec3'),
                            ('compose', 'vec3'), ('split', 'vec3'), ('transform', 'vec4'),
                            ('select', 'float'), ('uniform', 'float'), ('array_get', 'float'),
                            ('sample', 'vec4'), ('emit', 'bool')]:
        add('Tools/' + kind.replace('_', ' ').title(), {'kind': kind, 'data_type': data_type})
    entries.append({'name': 'particle_custom', 'type': 'shader', 'tree_item': 'Particles/Tools/Custom Shader',
                    'shader_model': {'name': 'Particle Custom Shader', 'parameters': [],
                                     'inputs': [{'name': 'value', 'type': 'f', 'default': '0.0', 'label': 'Value'}],
                                     'outputs': [{'type': 'f', 'f': '$value($uv)'}],
                                     'code': '', 'instance': '', 'global': ''}})
    (ROOT / 'addons/material_maker/particles/library.json').write_text(
        json.dumps({'name': 'Particles', 'lib': entries}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
