"""Reproducible, mmtest-specific module recipe (not a .ptex importer).
Reads the user's reference without changing it. Refuses to replace differing
existing generated files unless --check is used to report a mismatch.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def binding(name, kind, identifier, data_type, x=0, y=0):
    return dict(name=name, type='modular_particle', parameters={}, seed_int=0,
                settings=dict(kind=kind, id=identifier, data_type=data_type, label=identifier),
                node_position=dict(x=x, y=y))


def connection(source, target, port, source_port=0):
    return dict(from_port=source_port, to_port=port, to=target, **{'from': source})


def field(identifier, data_type, default):
    return dict(id=identifier, name=identifier, type=data_type, default=default)


def module(name, stage, nodes, links, outputs, inputs=()):
    fields = [dict(id=i, name=i, type=t) for i, t, _, _ in outputs]
    nodes.append(dict(name='Output', type='modular_particle', parameters={}, seed_int=0,
                      settings=dict(kind='module_output', fields=fields), node_position=dict(x=850,y=0)))
    links += [connection(source, 'Output', port, index) for port, (_, _, source, index) in enumerate(outputs)]
    reads = [n['settings']['id'] for n in nodes if n.get('settings', {}).get('kind') == 'module_read']
    return dict(name=name, stages=[stage], inputs=list(inputs), reads=list(dict.fromkeys(reads)),
                writes=[f['id'] for f in fields], revision=1,
                mm_graph=dict(type='graph', name='Module', seed_int=0, nodes=nodes, connections=links))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source_bytes = args.source.read_bytes()
    source = json.loads(source_bytes)
    original = {n['name']: n for n in source['nodes']}
    take = lambda name: copy.deepcopy(original[name])
    modules = {}
    random = take('Particles_Random')
    nodes = [random, take('uniform_greyscale_2'), take('uniform_greyscale_3'), take('math_v3'),
             binding('Speed', 'module_parameter', 'velocity', 'float', -300, -150),
             binding('Scale', 'module_parameter', 'particle_scale', 'vec3', -300, 150)]
    links = [connection('uniform_greyscale_3','Particles_Random',3),
             connection('uniform_greyscale_2','Particles_Random',4),
             connection('Particles_Random','math_v3',0), connection('Speed','math_v3',1)]
    modules['initialize'] = module('Initialize Particle', 'spawn', nodes, links,
        [('velocity','vec3','math_v3',0),('initial_velocity','vec3','math_v3',0),
         ('direction','vec3','Particles_Random',0),('scale','vec3','Scale',0),('initial_scale','vec3','Scale',0)],
        [field('velocity','float',10.0), field('particle_scale','vec3',[1.0,1.0,1.0])])
    spherical = take('graph_2')
    for node in spherical['nodes']:
        if node.get('settings', {}).get('builtin') == 'PI':
            node['settings'] = dict(kind='constant', data_type='float')
            node['parameters'] = dict(value=3.141592653589793)
    modules['spherical'] = module('Spherical UV', 'spawn',
        [binding('Direction','module_read','direction','vec3',-300,0), spherical],
        [connection('Direction','graph_2',0)], [('spherical_uv','vec2','graph_2',0)])
    nodes = [binding('Position','module_read','position','vec3',-500,-200),
             binding('Velocity','module_read','velocity','vec3',-500,0),
             binding('Delta','module_context','delta','float',-500,200),
             binding('New','module_context','just_spawned','bool',200,200),
             dict(name='Multiply',type='math_v3',parameters=dict(op=2.0,clamp=False)),
             dict(name='Add',type='math_v3',parameters=dict(op=0.0,clamp=False)),
             dict(name='Select',type='particle_node',settings=dict(kind='select',data_type='vec3'),parameters={})]
    links = [connection('Velocity','Multiply',0),connection('Delta','Multiply',1),connection('Position','Add',0),
             connection('Multiply','Add',1),connection('New','Select',0),connection('Position','Select',1),connection('Add','Select',2)]
    modules['integrate'] = module('Integrate Previous Velocity', 'update', nodes, links,[('position','vec3','Select',0)])
    nodes = [binding('Age','module_read','age','float',-400,-100),binding('Lifetime','module_read','lifetime','float',-400,100),
             dict(name='Divide',type='math',parameters=dict(op=3.0,clamp=False))]
    modules['normalized_age'] = module('Normalized Age', 'update', nodes,
        [connection('Age','Divide',0),connection('Lifetime','Divide',1)], [('normalized_age','float','Divide',0)])
    nodes = [binding('Age','module_read','normalized_age','float',-500,-200), take('tonality'),
             binding('InitialVelocity','module_read','initial_velocity','vec3',-500,0),
             binding('InitialScale','module_read','initial_scale','vec3',-500,200),
             take('math_v3_3'),take('math_v3_2')]
    links = [connection('Age','tonality',0),connection('InitialVelocity','math_v3_3',0),connection('tonality','math_v3_3',1),
             connection('InitialScale','math_v3_2',0),connection('tonality','math_v3_2',1)]
    modules['over_life'] = module('Velocity and Scale over Life', 'update', nodes, links,
        [('velocity','vec3','math_v3_3',0),('scale','vec3','math_v3_2',0),('curve_value','float','tonality',0)])
    nodes = [binding('Position','module_read','position','vec3',-1000,900),
             binding('Velocity','module_read','velocity','vec3',-500,1500),
             binding('Frequency','module_parameter','curl_frequency','float',-1000,1200),
             binding('Strength','module_parameter','curl_strength','float',-270,1340),
             take('Curl_Coordinates'),take('Curl_Noise_XY'),take('Curl_Amplitude'),take('Curl_Velocity')]
    links = [connection('Position','Curl_Coordinates',0),connection('Frequency','Curl_Coordinates',1),
             connection('Curl_Coordinates','Curl_Noise_XY',0),connection('Curl_Noise_XY','Curl_Amplitude',0),
             connection('Strength','Curl_Amplitude',1),connection('Velocity','Curl_Velocity',0),connection('Curl_Amplitude','Curl_Velocity',1)]
    modules['curl'] = module('Curl Noise XY', 'update', nodes, links,
        [('velocity','vec3','Curl_Velocity',0),('curl_velocity','vec3','Curl_Amplitude',0)],
        [field('curl_frequency','float',0.25),field('curl_strength','float',2.0)])
    # Compact standard module layouts; preserve reusable subgraph internals.
    for definition in modules.values():
        for i, node in enumerate(definition['mm_graph']['nodes']):
            node['node_position'] = dict(x=(i % 4)*300-500, y=(i // 4)*180)
        definition['mm_graph']['nodes'][-1]['node_position'] = dict(x=850,y=0)
    document = dict(type='mm_particle_effect',version=2,target='4.7.2',user_parameters=[],preview_capacity=128,
        attributes=[field('direction','vec3',[0,0,0]),field('initial_velocity','vec3',[0,0,0]),field('initial_scale','vec3',[1,1,1]),
                    field('spherical_uv','vec2',[0,0]),field('normalized_age','float',0.0),field('curve_value','float',1.0),field('curl_velocity','vec3',[0,0,0])],
        modules=modules,stages={'spawn':[], 'update':[]},
        emitter=dict(rate=0.0,duration=0.7,loop=True,bursts=[dict(time=0.0,count=128)],lifetime=0.7),
        renderer=dict(mode='additive',billboard=True,quad_size=0.1,round_quad=True,custom_attribute='custom'),
        reference=dict(file='mmtest.ptex',sha256=hashlib.sha256(source_bytes).hexdigest(),note='Explicit module recreation, not automatic legacy import.'))
    for stage, identifiers in [('spawn',['initialize','spherical']),('update',['integrate','normalized_age','over_life','curl'])]:
        document['stages'][stage] = [dict(id='mmtest_'+identifier,module=identifier,parameters={},enabled=True) for identifier in identifiers]
    files = {ROOT/'material_maker/examples/modular_particles/mmtest.mpfx': json.dumps(document,indent=2,ensure_ascii=False)+'\n',
             ROOT/'test/modular_particles/fixtures/mmtest_reference.ptex':source_bytes.decode('utf-8')}
    for identifier, definition in modules.items():
        data = copy.deepcopy(definition['mm_graph'])
        metadata = {k:copy.deepcopy(v) for k,v in definition.items() if k != 'mm_graph'}
        data['particle_module'] = dict(version=1,id=identifier,definition=metadata)
        files[ROOT/f'material_maker/examples/modular_particles/modules/{identifier}.mmg'] = json.dumps(data,indent=2,ensure_ascii=False)+'\n'
    for path, content in files.items():
        if path.exists():
            if path.read_text(encoding='utf-8') != content:
                raise SystemExit(f'Refusing to overwrite differing existing file: {path}')
        elif args.check:
            raise SystemExit(f'Missing generated file: {path}')
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            with path.open('x',encoding='utf-8',newline='') as output: output.write(content)
        print(path.relative_to(ROOT))


if __name__ == '__main__': main()
