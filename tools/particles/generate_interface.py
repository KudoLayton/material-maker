"""Generate the particle ABI table from Godot 4.7 shader_types.cpp."""
import argparse
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
args = parser.parse_args()
source = args.source.read_text(encoding='utf-8')
pattern = r'SHADER_PARTICLES\]\.functions\["(\w+)"\]\.built_ins\["(\w+)"\] = (.*?);'
builtins = {'start': {}, 'process': {}}
for stage, name, declaration in re.findall(pattern, source):
    item = {'type': re.search(r'TYPE_(\w+)', declaration)[1].lower(),
            'write': 'constt(' not in declaration}
    if stage in ('global', 'constants'):
        for values in builtins.values():
            values[name] = item
    elif stage in builtins:
        builtins[stage][name] = item
assert len(builtins['start']) == 35 and len(builtins['process']) == 35, {s: len(v) for s,v in builtins.items()}
target = Path(__file__).resolve().parents[2] / 'addons/material_maker/particles/abi.gd'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text('extends RefCounted\n\n# Generated from Godot 4.7 servers/rendering/shader_types.cpp.\n'
                  + '# Source SHA256: ' + hashlib.sha256(source.encode()).hexdigest() + '\n'
                  + 'const BUILTINS = ' + json.dumps(builtins, indent='\t') + '\n', encoding='utf-8')
