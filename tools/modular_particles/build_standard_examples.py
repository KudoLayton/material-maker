"""Create only the three owned standard-module examples; never rewrite mmtest.
--check compares recipes. --update explicitly refreshes differing owned examples.
"""
import argparse
import copy
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from build_standard_modules import recipes, ROLE

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'material_maker/examples/modular_particles'


def remap(graph, mapping):
    settings = graph.get('settings', {})
    if graph.get('type') == 'modular_particle':
        if settings.get('kind') == 'module_read' and settings.get('id') in mapping:
            settings['id'] = mapping[settings['id']]
        if settings.get('kind') == 'module_output':
            for field in settings.get('fields', []): field['id'] = mapping.get(field['id'], field['id'])
    for node in graph.get('nodes', []): remap(node, mapping)


def effect(name, spawn, update, modules):
    doc = dict(type='mm_particle_effect',version=1,target='4.7.2',attributes=[],modules={},
               stages=dict(spawn=[],update=[]),
               emitter=dict(rate=64.,duration=1.,loop=True,bursts=[],lifetime=1.),
               renderer=dict(mode='additive',billboard=True,quad_size=0.1,custom_attribute='custom'))
    attributes = {}
    for stage, ids in [('spawn',spawn),('update',update)]:
        for id in ids:
            payload = copy.deepcopy(modules[id])
            meta = payload.pop('particle_module')
            module = meta['definition']
            mapping = {}
            for attribute in meta['attributes']:
                role = attribute['standard_role']
                mapping[attribute['id']] = name+'_attr_'+role.removeprefix(ROLE)
                attribute['id'] = mapping[attribute['id']]
                attributes.setdefault(role, attribute)
            remap(payload,mapping)
            module['mm_graph'] = payload
            module['catalog_snapshot'] = True
            for field in ['reads','writes']: module[field] = [mapping.get(a,a) for a in module[field]]
            module['standard_module']['bindings'] = {r:mapping[a] for r,a in module['standard_module']['bindings'].items()}
            module_id = name+'_'+id
            doc['modules'][module_id] = module
            doc['stages'][stage].append(dict(id=name+'_instance_'+id,module=module_id,enabled=True,parameters={}))
    doc['attributes'] = list(attributes.values())
    return doc


def make_examples():
    modules = {g.id:g.finish() for g in recipes()}
    basic = effect('basic_fountain',['initialize_particle','add_velocity_in_cone'],
                   ['gravity','solve_motion','color_over_life','scale_over_life'],modules)
    box = effect('box_turbulence',['initialize_particle','box_location','add_velocity'],
                 ['curl_noise','drag','solve_motion','color_over_life','scale_over_life'],modules)
    box['emitter'].update(rate=128.,duration=3.,lifetime=3.)
    box['stages']['spawn'][1]['parameters'] = dict(size=[1.5,0.5,1.5])
    box['stages']['update'][0]['parameters'] = dict(strength=2.,frequency=0.8)
    box['stages']['update'][1]['parameters'] = dict(drag=0.5)
    sphere = effect('sphere_burst',['initialize_particle','sphere_location'],
                    ['curl_noise','solve_motion','color_over_life','scale_over_life','kill_particles'],modules)
    sphere['emitter'].update(rate=0.,duration=2.,lifetime=2.,bursts=[dict(time=0.,count=128)])
    sphere['preview_capacity'] = 128
    sphere['stages']['spawn'][1]['parameters'] = dict(radius=0.75,surface_only=True)
    # Demonstrate editable per-particle bool binding without adding a new input binding API.
    kill = sphere['modules']['sphere_burst_kill_particles']
    kill['inputs'].append(dict(id='kill_age',name='Kill Age',type='float',default=1.5))
    kill['reads'].append('age')
    graph = kill['mm_graph']
    for name,kind,id in [('Age','module_read','age'),('KillAge','module_parameter','kill_age')]:
        graph['nodes'].append(dict(name=name,type='modular_particle',parameters={},seed_int=0,
                                   node_position=dict(x=0,y=600 if name=='Age' else 800),
                                   settings=dict(kind=kind,id=id,data_type='float',label=id)))
    node = next(n for n in graph['nodes'] if n['name']=='Kill')
    node['settings']['input_ports'] += [dict(name='age',type='float'),dict(name='kill_age',type='float')]
    node['settings']['code'] = 'return alive && !(kill_value || age >= max(kill_age,0.0));'
    graph['connections'] += [{'from':'Age','from_port':0,'to':'Kill','to_port':2},
                            {'from':'KillAge','from_port':0,'to':'Kill','to_port':3}]
    return dict(basic_fountain=basic,box_turbulence=box,sphere_burst=sphere)


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--check',action='store_true'); parser.add_argument('--update',action='store_true'); args=parser.parse_args()
    for name,doc in make_examples().items():
        path=OUT/(name+'.mpfx'); text=json.dumps(doc,indent=2,ensure_ascii=False)+'\n'
        if path.exists() and path.read_text(encoding='utf-8') == text: continue
        if args.check: raise SystemExit(f'Example differs: {path}')
        if path.exists() and not args.update: raise SystemExit(f'Refusing overwrite without --update: {path}')
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(text,encoding='utf-8',newline='\n')
    print('STANDARD EXAMPLES PASS count=3')


if __name__ == '__main__': main()
