"""Create only user_parameters.mpfx; existing standard examples/mmtest are untouched."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from build_standard_examples import effect
from build_standard_modules import recipes

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'material_maker/examples/modular_particles/user_parameters.mpfx'


def make_example():
    modules = {g.id: g.finish() for g in recipes()}
    doc = effect('user_parameters', ['initialize_particle', 'add_velocity_in_cone'],
                 ['gravity', 'solve_motion', 'color_over_life', 'scale_over_life'], modules)
    doc['version'] = 2
    doc['preview_capacity'] = 256
    doc['user_parameters'] = []
    ids = {}
    for name, type, default in [('Speed','float',3.0),('Gravity','vec3',[0.0,-9.81,0.0]),('Tint','vec4',[1.0,1.0,1.0,1.0])]:
        ids[name] = hashlib.sha256(('mm.user.example.v1.' + name).encode()).hexdigest()[:32]
        doc['user_parameters'].append(dict(id=ids[name],name=name,type=type,default=default))
    mapping = {'add_velocity_in_cone': {'speed_min':'Speed','speed_max':'Speed'},
               'gravity': {'gravity':'Gravity'}, 'color_over_life': {'multiplier':'Tint'}}
    for stage in doc['stages'].values():
        for item in stage:
            module = doc['modules'][item['module']]['standard_module']['catalog_id']
            if module in mapping:
                item['input_bindings'] = {key:dict(kind='user',id=ids[name]) for key,name in mapping[module].items()}
    return doc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--update',action='store_true')
    args = parser.parse_args()
    text = json.dumps(make_example(),indent=2,ensure_ascii=False)+'\n'
    if not OUT.exists() or OUT.read_text(encoding='utf-8') != text:
        if args.check: raise SystemExit('User example differs: '+str(OUT))
        if OUT.exists() and not args.update: raise SystemExit('Refusing overwrite without --update: '+str(OUT))
        OUT.parent.mkdir(parents=True,exist_ok=True)
        OUT.write_text(text,encoding='utf-8',newline='\n')
    print('USER EXAMPLE PASS count=1')


if __name__ == '__main__':
    main()
