"""Generate the particle entries for the existing Material Maker library."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    abi = (ROOT / 'addons/material_maker/particles/abi.gd').read_text(encoding='utf-8')
    builtins = json.loads(abi.split('const BUILTINS = ', 1)[1])
    entries = []

    def add(path, settings):
        entries.append({'name': re.sub(r'\W+', '_', path), 'type': 'particle_node',
                        'tree_item': path, 'settings': settings})

    merged = dict(builtins['start'], **builtins['process'])
    for name, definition in merged.items():
        add('Particles/Read/' + name, {'kind': 'input', 'builtin': name})
        if definition.get('write'):
            add('Particles/Write/' + name, {'kind': 'set', 'builtin': name})
    for stage in ['start', 'process']:
        add('Particles/Execution/' + stage.capitalize() + ' Entry', {'kind': 'entry', 'stage': stage})
    add('Particles/Random', {'kind': 'random', 'data_type': 'vec3'})
    add('Particles/Execution/Emit', {'kind': 'emit'})
    supplemental = [
        ('Simple/Constant/Typed', 'constant', 'vec2'),
        ('Filter/Math/Typed', 'operator', 'int'),
        ('Filter/Combine/Typed', 'compose', 'vec2'),
        ('Filter/Decompose/Typed', 'split', 'vec2'),
        ('Filter/Math/Type Cast', 'convert', 'vec2'),
        ('Filter/Math/Matrix Transform', 'transform', 'vec4'),
        ('Filter/Math/Select', 'select', 'float'),
        ('Miscellaneous/Typed Parameter', 'uniform', 'float'),
        ('Miscellaneous/Array Element', 'array_get', 'float'),
        ('Miscellaneous/Texture Sample', 'sample', 'vec4'),
    ]
    for path, kind, data_type in supplemental:
        add(path, {'kind': kind, 'data_type': data_type, 'editor_profile': 'supplemental_v1'})
    add('Filter/Math/Compare', {'kind': 'operator', 'data_type': 'float',
                              'operation': 'less', 'editor_profile': 'compare_v1'})
    for kind, label, function_type in [('evaluate', 'Evaluate Function', 'rgba'),
                                      ('bridge', 'Value to Function', 'sdf3d')]:
        add('Miscellaneous/' + label, {'kind': kind, 'function_type': function_type,
                                       'editor_profile': 'supplemental_v1'})
    (ROOT / 'addons/material_maker/particles/library.json').write_text(
        json.dumps({'name': 'Particles', 'lib': entries}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
