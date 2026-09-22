"""Independent, reproducible MM graph recipes; no Unreal assets/code are copied.
Existing generated files are never silently replaced: --check verifies, --update
explicitly refreshes this script's owned catalog/module files only.
"""
import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'material_maker/panels/modular_particles/standard'
ROLE = 'mm.standard.v1.'
ATTRS = {
    'acceleration': ('Acceleration', 'vec3', [0., 0., 0.]),
    'drag': ('Drag', 'float', 0.),
    'initial_color': ('InitialColor', 'vec4', [1., 1., 1., 1.]),
    'initial_scale': ('InitialScale', 'vec3', [1., 1., 1.]),
}
BUILTINS = {'position':'vec3','velocity':'vec3','color':'vec4','scale':'vec3',
            'rotation':'vec4','age':'float','lifetime':'float','alive':'bool'}


def link(a, b, port, source_port=0):
    return {'from':a, 'from_port':source_port, 'to':b, 'to_port':port}


class Graph:
    def __init__(self, identifier, name, stage, category, description, inputs_help, order):
        self.id, self.name, self.stage = identifier, name, stage
        self.nodes, self.links, self.inputs, self.reads, self.outputs = [], [], [], [], []
        self.entry = dict(id=identifier, name=name, revision=1, stages=[stage], category=category,
                          description=description, inputs_help=inputs_help, order=order,
                          tags=f'{category} {stage} particle Niagara 기본 입자', file=identifier+'.mmg')

    def node(self, name, kind, data_type, **settings):
        self.nodes.append(dict(name=name, type='particle_node', seed_int=0, parameters={},
                               settings=dict(kind=kind, data_type=data_type, **settings)))
        return name

    def bind(self, name, kind, identifier, type):
        self.nodes.append(dict(name=name, type='modular_particle', seed_int=0, parameters={},
                               settings=dict(kind=kind, id=identifier, data_type=type, label=identifier)))
        return name

    def param(self, identifier, name, type, default):
        self.inputs.append(dict(id=identifier, name=name, type=type, default=default))
        return self.bind('Input_'+identifier, 'module_parameter', identifier, type)

    def read(self, identifier):
        attr = 'std_'+identifier if identifier in ATTRS else identifier
        name = 'Read_'+identifier
        if attr not in self.reads:
            self.reads.append(attr)
            self.bind(name, 'module_read', attr, ATTRS[identifier][1] if identifier in ATTRS else BUILTINS[identifier])
        return name

    def context(self, identifier, type='float'):
        name = 'Context_'+identifier
        if not any(n['name'] == name for n in self.nodes): self.bind(name, 'module_context', identifier, type)
        return name

    def constant(self, name, type, value):
        return self.node(name, 'constant', type, value=value)

    def custom(self, name, type, code, args):
        self.node(name, 'custom', type, code=code, editor_profile='standard_module_v1',
                  input_ports=[dict(name=k, type=t) for k,t,_ in args])
        self.links += [link(source,name,i) for i,(_,_,source) in enumerate(args)]
        return name

    def add(self, name, a, b, type='vec3'):
        return self.custom(name,type,'return a+b;',[('a',type,a),('b',type,b)])

    def random(self, seed, channel=0, shared=False):
        offset = self.custom('SeedOffset_'+str(channel),'uint',f'return seed+{channel}u;', [('seed','uint',seed)])
        name = self.node('Random_'+str(channel),'random','vec4', minimum=0., maximum=1.)
        self.links.append(link(offset,name,2))
        if shared: self.links.append(link(self.constant('SharedFieldID','uint',0),name,0))
        return name

    def output(self, identifier, source):
        self.outputs.append((identifier,source))

    def finish(self):
        fields = [dict(id='std_'+i if i in ATTRS else i,
                       name=ATTRS[i][0] if i in ATTRS else i.capitalize(),
                       type=ATTRS[i][1] if i in ATTRS else BUILTINS[i]) for i,_ in self.outputs]
        self.nodes.append(dict(name='Output',type='modular_particle',parameters={},seed_int=0,
                               settings=dict(kind='module_output',fields=fields)))
        self.links += [link(source,'Output',i) for i,(_,source) in enumerate(self.outputs)]
        # Layered, deterministic, editable graph layout. No transient Godot IDs.
        levels = {}
        for node in self.nodes:
            sources = [l['from'] for l in self.links if l['to'] == node['name']]
            levels[node['name']] = 1+max([levels.get(s,0) for s in sources],default=-1)
        rows = {}
        for node in self.nodes:
            level = levels[node['name']]
            row = rows.get(level,0)
            node['node_position'] = dict(x=level*330, y=row*220)
            rows[level] = row+1
        used = set(self.reads+[f['id'] for f in fields])
        attributes = [dict(id='std_'+key,name=name,type=type,default=default,standard_role=ROLE+key)
                      for key,(name,type,default) in ATTRS.items() if 'std_'+key in used]
        definition = dict(name=self.name, stages=[self.stage], inputs=self.inputs, reads=self.reads,
                          writes=[f['id'] for f in fields], revision=1,
                          standard_module=dict(catalog_id=self.id,revision=1,
                              bindings={a['standard_role']:a['id'] for a in attributes}))
        return dict(type='graph',name='Module',seed_int=0,nodes=self.nodes,connections=self.links,
                    particle_module=dict(version=1,id='standard_'+self.id,definition=definition,attributes=attributes))


def recipes():
    modules=[]
    g=Graph('initialize_particle','Initialize Particle','spawn','Initialization',
        'Initialize visible particle state and capture initial Color/Scale. Emitter lifetime is preserved unless overridden.',
        'Position Offset: m; Velocity: m/s; Color: linear RGBA; Scale: multiplier; Override Lifetime: bool; Lifetime Min/Max: seconds; Seed: uint.',
        'First in Spawn, before Location and Velocity modules.')
    offset=g.param('position_offset','Position Offset','vec3',[0.,0.,0.])
    velocity=g.param('velocity','Velocity','vec3',[0.,0.,0.])
    color=g.param('color','Color','vec4',[1.,1.,1.,1.])
    scale=g.param('scale','Scale','vec3',[1.,1.,1.])
    override=g.param('override_lifetime','Override Lifetime','bool',False)
    lo=g.param('lifetime_min','Lifetime Min','float',1.)
    hi=g.param('lifetime_max','Lifetime Max','float',1.)
    seed=g.param('seed','Seed','uint',0)
    rnd=g.random(seed,11)
    lifetime=g.custom('Lifetime','float','return override_value ? max(0.0,mix(min(lo,hi),max(lo,hi),random_value.x)) : current;',
        [('override_value','bool',override),('lo','float',lo),('hi','float',hi),('random_value','vec4',rnd),('current','float',g.read('lifetime'))])
    g.output('position',g.add('PositionOffset',g.read('position'),offset))
    for attr,source in [('velocity',velocity),('color',color),('scale',scale),('initial_color',color),('initial_scale',scale),('lifetime',lifetime),
                        ('rotation',g.constant('IdentityRotation','vec4',[0.,0.,0.,1.])),
                        ('acceleration',g.constant('ZeroAcceleration','vec3',[0.,0.,0.])),('drag',g.constant('ZeroDrag','float',0.))]: g.output(attr,source)
    modules.append(g)

    g=Graph('box_location','Box Location','spawn','Location','Uniform volume sampling in a box, added to the current Position.',
            'Center and full Size: m; Seed: uint. Absolute Size is used.','After Initialize Particle.')
    center=g.param('center','Center','vec3',[0.,0.,0.]); size=g.param('size','Size','vec3',[1.,1.,1.]); rnd=g.random(g.param('seed','Seed','uint',0),101)
    location=g.custom('BoxSample','vec3','return center+(random_value.xyz-vec3(0.5))*abs(size);',[('center','vec3',center),('size','vec3',size),('random_value','vec4',rnd)])
    g.output('position',g.add('OffsetPosition',g.read('position'),location)); modules.append(g)

    g=Graph('sphere_location','Sphere Location','spawn','Location','Uniform sphere volume or surface sampling, added to current Position.',
            'Center/Radius: m; Surface Only: bool; Seed: uint. Negative radius becomes zero.','After Initialize Particle.')
    center=g.param('center','Center','vec3',[0.,0.,0.]); radius=g.param('radius','Radius','float',1.); surface=g.param('surface_only','Surface Only','bool',False)
    rnd=g.random(g.param('seed','Seed','uint',0),211)
    sample=g.custom('SphereSample','vec3','float z=2.0*random_value.x-1.0; float phi=6.283185307179586*random_value.y; float xy=sqrt(max(0.0,1.0-z*z));\nfloat r=max(radius,0.0)*(surface_only ? 1.0 : pow(random_value.z,1.0/3.0));\nreturn center+r*vec3(xy*cos(phi),z,xy*sin(phi));',
        [('center','vec3',center),('radius','float',radius),('surface_only','bool',surface),('random_value','vec4',rnd)])
    g.output('position',g.add('OffsetPosition',g.read('position'),sample)); modules.append(g)

    g=Graph('add_velocity','Add Velocity','spawn','Velocity','Add a constant velocity in simulation coordinates.','Velocity: m/s.','After Initialize Particle; use Solve Motion in Update to move.')
    g.output('velocity',g.add('AddVelocity',g.read('velocity'),g.param('velocity','Velocity','vec3',[0.,1.,0.]))); modules.append(g)

    g=Graph('add_velocity_in_cone','Add Velocity in Cone','spawn','Velocity','Add velocity uniformly distributed over a cone solid angle.',
            'Axis: direction (+Y fallback); Half Angle: degrees [0,180]; Speed Min/Max: m/s, sorted and nonnegative; Seed: uint.',
            'After Initialize Particle; use Solve Motion in Update to move.')
    axis=g.param('axis','Axis','vec3',[0.,1.,0.]); angle=g.param('half_angle','Half Angle','float',15.)
    lo=g.param('speed_min','Speed Min','float',3.); hi=g.param('speed_max','Speed Max','float',3.); rnd=g.random(g.param('seed','Seed','uint',0),307)
    cone=g.custom('ConeSample','vec3','vec3 axis_n=dot(axis,axis)>1e-12 ? normalize(axis) : vec3(0,1,0);\nvec3 helper=abs(axis_n.y)<0.999 ? vec3(0,1,0) : vec3(1,0,0);\nvec3 tangent=normalize(cross(helper,axis_n)); vec3 bitangent=cross(axis_n,tangent);\nfloat z=mix(1.0,cos(radians(clamp(angle,0.0,180.0))),random_value.x); float phi=6.283185307179586*random_value.y;\nfloat xy=sqrt(max(0.0,1.0-z*z)); float speed=max(0.0,mix(min(lo,hi),max(lo,hi),random_value.z));\nreturn speed*(axis_n*z+xy*(tangent*cos(phi)+bitangent*sin(phi)));',
        [('axis','vec3',axis),('angle','float',angle),('lo','float',lo),('hi','float',hi),('random_value','vec4',rnd)])
    g.output('velocity',g.add('AddVelocity',g.read('velocity'),cone)); modules.append(g)

    g=Graph('gravity','Gravity','update','Forces','Accumulate acceleration without multiplying by delta. No mass is used.','Gravity: m/s², default (0,-9.81,0).','Before exactly one Solve Motion.')
    g.output('acceleration',g.add('Accumulate',g.read('acceleration'),g.param('gravity','Gravity','vec3',[0.,-9.81,0.]))); modules.append(g)
    g=Graph('drag','Drag','update','Forces','Accumulate nonnegative exponential velocity damping.','Drag: seconds⁻¹. Negative values contribute zero.','Before exactly one Solve Motion.')
    drag=g.param('drag','Drag','float',1.)
    g.output('drag',g.custom('Accumulate','float','return current+max(drag,0.0);',[('current','float',g.read('drag')),('drag','float',drag)])); modules.append(g)

    g=Graph('curl_noise','Curl Noise','update','Forces','A shared seeded 3D curl field, not per-particle jitter or the mmtest XY curl. Editable 12-sample central differences of a vector potential.',
            'Strength: acceleration multiplier; Frequency: noise units/m; Pan: noise units/s; Seed: uint. FBM octave/persistence controls are inside the graph.',
            'Before exactly one Solve Motion. More expensive than Gravity; no texture/bake input.')
    strength=g.param('strength','Strength','float',1.); frequency=g.param('frequency','Frequency','float',0.5); pan=g.param('pan','Pan','vec3',[0.,0.2,0.])
    rnd=g.random(g.param('seed','Seed','uint',0),401,True)
    coordinates=g.custom('NoiseCoordinates','vec3','return position*max(frequency,0.0)+pan*time+random_value.xyz*64.0;',
        [('position','vec3',g.read('position')),('frequency','float',frequency),('pan','vec3',pan),('time','float',g.context('time')),('random_value','vec4',rnd)])
    nested_nodes=[dict(name='gen_inputs',type='ios',ports=[dict(name='Coordinates',type='rgb')]),
                  dict(name='gen_outputs',type='ios',ports=[dict(name='Curl',type='rgb')]),dict(name='gen_parameters',type='remote',widgets=[]),
                  dict(name='PotentialNoise',type='tex3d_fbm_3',seed_int=0,parameters=dict(noise=4.,iterations=2.,persistence=0.5,scale_x=1.,scale_y=1.,scale_z=1.))]
    nested_links=[]; samples={}
    # curl(A) = (dAz/dy-dAy/dz, dAx/dz-dAz/dx, dAy/dx-dAx/dy).
    offsets=['vec3(19.1,7.7,3.3)','vec3(47.2,11.8,29.4)','vec3(5.6,61.3,13.9)']
    for component,axes in [(0,[1,2]),(1,[0,2]),(2,[0,1])]:
        for axis_index in axes:
            for sign in [-1,1]:
                name=f'A{component}_D{axis_index}_{"P" if sign>0 else "M"}'
                delta=['0.0']*3; delta[axis_index]=str(sign*0.01)
                coordinate=name+'_Coordinate'
                nested_nodes.append(dict(name=coordinate,type='particle_node',parameters={},settings=dict(kind='custom',data_type='vec4',editor_profile='standard_module_v1',input_ports=[dict(name='point',type='vec3')],code=f'return vec4(point+{offsets[component]}+vec3({",".join(delta)}),0.0);')))
                nested_nodes.append(dict(name=name,type='particle_node',parameters={},settings=dict(kind='evaluate',function_type='tex3d_gs')))
                nested_links += [link('gen_inputs',coordinate,0),link('PotentialNoise',name,0),link(coordinate,name,1)]
                samples[component,axis_index,sign]=name
    terms=[(2,1),(1,2),(0,2),(2,0),(1,0),(0,1)]
    arguments=[]
    for i,(component,axis_index) in enumerate(terms):
        for sign in [1,-1]:
            key=f'v{i}{"p" if sign>0 else "m"}'
            arguments.append(dict(name=key,type='float'))
            nested_links.append(link(samples[component,axis_index,sign],'CurlDifference',len(arguments)-1))
    nested_nodes.append(dict(name='CurlDifference',type='particle_node',parameters={},settings=dict(kind='custom',data_type='vec3',editor_profile='standard_module_v1',input_ports=arguments,
        code='return vec3((v0p-v0m)-(v1p-v1m),(v2p-v2m)-(v3p-v3m),(v4p-v4m)-(v5p-v5m))/0.02;')))
    nested_links.append(link('CurlDifference','gen_outputs',0))
    for i,node in enumerate(nested_nodes): node['node_position']=dict(x=(i%5)*320,y=(i//5)*180)
    g.nodes.append(dict(name='Curl3D',type='graph',seed_int=0,nodes=nested_nodes,connections=nested_links))
    g.links.append(link(coordinates,'Curl3D',0))
    contribution=g.custom('Amplitude','vec3','return frequency>0.0 ? strength*curl_value : vec3(0.0);',[('frequency','float',frequency),('strength','float',strength),('curl_value','vec3','Curl3D')])
    g.output('acceleration',g.add('Accumulate',g.read('acceleration'),contribution)); modules.append(g)

    g=Graph('solve_motion','Solve Motion','update','Solvers','Semi-implicit velocity/position integration with exponential drag; clears both accumulators after use.',
            'Uses Context.delta in seconds. No module inputs.','Exactly once, after all Gravity/Curl/Drag modules. Color/Scale over Life may follow.')
    dt=g.context('delta')
    velocity=g.custom('VelocityStep','vec3','float dt=max(delta,0.0); return (velocity+acceleration*dt)*exp(-max(drag,0.0)*dt);',
        [('velocity','vec3',g.read('velocity')),('acceleration','vec3',g.read('acceleration')),('drag','float',g.read('drag')),('delta','float',dt)])
    position=g.custom('PositionStep','vec3','return position+velocity*max(delta,0.0);',[('position','vec3',g.read('position')),('velocity','vec3',velocity),('delta','float',dt)])
    for attr,source in [('velocity',velocity),('position',position),('acceleration',g.constant('ClearAcceleration','vec3',[0.,0.,0.])),('drag',g.constant('ClearDrag','float',0.))]: g.output(attr,source)
    modules.append(g)

    for color in [True,False]:
        g=Graph('color_over_life' if color else 'scale_over_life','Color over Life' if color else 'Scale over Life','update','Appearance',
                'Evaluate from captured initial state each frame, not from the previous frame result.',
                'Multiplier: linear RGBA.' if color else 'Multiplier: XYZ scale. Edit the Gradient/Curve inside this module.',
                'Requires a Spawn writer for InitialColor.' if color else 'Requires a Spawn writer for InitialScale.')
        normalized=g.custom('NormalizedAge','float','return clamp(age/max(lifetime,0.000001),0.0,1.0);',[('age','float',g.read('age')),('lifetime','float',g.read('lifetime'))])
        if color:
            g.nodes.append(dict(name='LifeGradient',type='colorize',seed_int=0,parameters=dict(gradient=dict(type='Gradient',interpolation=1,points=[dict(pos=0.,r=1.,g=1.,b=1.,a=1.),dict(pos=1.,r=1.,g=1.,b=1.,a=0.)]))))
            g.links.append(link(normalized,'LifeGradient',0))
            out=g.custom('ApplyInitialColor','vec4','return initial*multiplier*gradient_value;', [('initial','vec4',g.read('initial_color')),('multiplier','vec4',g.param('multiplier','Color Multiplier','vec4',[1.,1.,1.,1.])),('gradient_value','vec4','LifeGradient')])
            g.output('color',out)
        else:
            g.nodes.append(dict(name='LifeCurve',type='tonality',seed_int=0,parameters=dict(curve=dict(type='Curve',points=[dict(x=0.,y=1.,ls=-1.,rs=-1.),dict(x=1.,y=0.,ls=-1.,rs=-1.)]))))
            g.links.append(link(normalized,'LifeCurve',0))
            out=g.custom('ApplyInitialScale','vec3','return initial*multiplier*curve_value;', [('initial','vec3',g.read('initial_scale')),('multiplier','vec3',g.param('multiplier','Scale Multiplier','vec3',[1.,1.,1.])),('curve_value','float','LifeCurve')])
            g.output('scale',out)
        modules.append(g)
    g=Graph('kill_particles','Kill Particles','update','Lifetime','Kill without resurrecting dead particles. Replace the Kill connection with a per-particle bool graph for conditional killing.',
            'Kill: bool, default false. A true instance input kills all particles reaching this module.','Usually last in Update. Does not add a volume or event system.')
    g.output('alive',g.custom('Kill','bool','return alive && !kill_value;', [('alive','bool',g.read('alive')),('kill_value','bool',g.param('kill','Kill','bool',False))])); modules.append(g)
    return modules


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--check',action='store_true'); parser.add_argument('--update',action='store_true'); args=parser.parse_args()
    modules=recipes()
    files={g.id+'.mmg':g.finish() for g in modules}
    files['catalog.json']=dict(version=1,modules=[g.entry for g in modules])
    for filename,data in files.items():
        path=OUT/filename; text=json.dumps(data,indent=2,ensure_ascii=False)+'\n'
        if path.exists() and path.read_text(encoding='utf-8') == text: continue
        if args.check: raise SystemExit(f'Recipe mismatch: {path}')
        if path.exists() and not args.update: raise SystemExit(f'Refusing overwrite without --update: {path}')
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(text,encoding='utf-8',newline='\n')
    print(f'STANDARD RECIPES PASS modules={len(modules)}')


if __name__ == '__main__': main()
