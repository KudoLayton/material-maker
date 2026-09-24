# Effect and module authoring

## Latest document contract

`.mpfx` is JSON: `type: mm_particle_effect`, `version: 2`, `target: 4.7.2`, plus `attributes`, `modules`, `stages`, `emitter`, `renderer`, `user_parameters`. Optional `preview_capacity` controls the default export/preview allocation. Create a packaged template rather than reconstructing every required field. Reject v1, missing versions and unknown future versions; changing their version field is not a supported migration.

- `modules` maps stable definition IDs to `name`, allowed `stages`, `inputs`, `reads`, `writes` and an editable `mm_graph`.
- `stages.spawn` / `stages.update` contain ordered instances `{id, module, enabled, parameters, input_bindings}`. Instance ID and module definition ID differ. Several instances can reuse a definition; modifying that definition changes all its instances.
- `parameters` is keyed by input **ID**, not visible label. Defaults are on the module's `inputs` definitions. Preserve an instance's saved constant when binding it to a User.
- Renaming labels must not replace IDs. Copying an independent module/instance requires new unique IDs and corresponding references; duplicating an Attribute ID does not create independent storage.
- JSON types: float/int/uint/bool, vec2/vec3/vec4 arrays of exact length. Values must be finite; uint is 0..4294967295 and int is signed 32-bit. Do not use color objects in authoring JSON: vec4 uses `[r,g,b,a]`.

Namespaces are a UI/API distinction, not strings to insert indiscriminately into stable-ID fields:

| Namespace | Meaning |
|---|---|
| `Module.Position` | An ordinary module input, unrelated to position unless explicitly connected |
| `Particle.Position` | Builtin position attribute (stored ID `position`) |
| `Particle.Custom.Position` | A distinct custom attribute with its own ID |
| `User.Position` | Effect-level readonly external input, bound by User ID |
| `Context.delta` | Simulation step seconds, not a User or stored Attribute |

Builtin IDs/types: position/velocity/scale vec3, rotation/color/custom vec4, age/lifetime float, alive bool, particle_id uint. Age and particle_id are readonly. Custom attributes live in `attributes` as `{id,name,type,default}`. Renderer `custom_attribute` must refer to a vec4 attribute. No automatic matching by name.

## Emission and standard module order

Save schedules in `emitter`, not preferences: `rate`, `duration`, `loop`, `bursts:[{time,count}]`, `lifetime`. Burst times must be nonnegative and less than duration. Use a positive duration for authored effects. Rate 0 with a time-0 burst is a burst effect; `loop:false` is one-shot and `loop:true` repeats each duration. Rate plus multiple/delayed bursts is a custom schedule; preserve it unless the user requests conversion. Capacity overflow drops new particles.

Prefer existing graphs from templates and the packaged standard `.mmg` library (portable `modules/standard_particles/`). Read capabilities descriptions/units when choosing modules:
- Spawn: Initialize Particle first; then Box/Sphere Location and Add Velocity / Add Velocity in Cone as needed.
- Update: Gravity / Curl Noise / Drag accumulate inputs before **exactly one Solve Motion**. Do not multiply forces by delta a second time.
- Color/Scale over Life require captured initial Color/Scale written in Spawn; evaluate from initial state, not the previous frame's value.
- Kill Particles usually runs last. Curl Noise is more expensive than Gravity and is not a texture/bake operation.

Templates cover fountain, box turbulence, sphere burst, dynamic Users and mmtest. Do not silently append Solve/Initialize to a hand-authored stack without checking intent and existing dependencies.

## User defaults and binding

Definitions live at effect level:

```json
{"id":"speed_user","name":"Speed","type":"float","default":3.0}
```

Names match `[A-Za-z_][A-Za-z0-9_]*`, are case-sensitive and exclude `User.` in storage. IDs and names must be unique. Bind an exact matching input type on each selected instance:

```json
"input_bindings": {
  "speed_min": {"kind":"user","id":"speed_user"},
  "speed_max": {"kind":"user","id":"speed_user"}
}
```

Only those instance inputs share the User; other instances remain independent. Changing `default` changes the shared effect default, not game node overrides. Removing a binding restores the retained literal. Do not delete/change the type of a referenced User until its bindings are explicitly removed/replaced, including disabled instances. Missing/invalid bindings block export; never silently fall back to constants.

## Editing reusable module graphs

Keep `mm_graph` for modules intended to remain editable in Material Maker. Do not replace an existing visual graph with compiler-only IR to make validation pass. Follow the packaged graph's node names, port order and settings.

Graph shape is `{type:"graph",name:"Module",seed_int:0,nodes:[],connections:[]}`. Nodes include `name`, `type`, `parameters:{}`, `seed_int:0`, `node_position:{x,y}`, `settings`. Connections are `{from,from_port,to,to_port}`; names must resolve and numeric port indexes must match.

Useful nodes:
- `type: modular_particle`, `settings:{kind:"module_parameter",id:INPUT_ID,data_type:TYPE,label:LABEL}` reads an input.
- Same type with `kind:module_read` reads a declared Particle attribute ID; `module_context` reads `delta`, `time`, `seed`, `index` or `just_spawned` with the correct type.
- Same type with `kind:module_output`, `fields:[{id:ATTRIBUTE_ID,name:LABEL,type:TYPE}]` writes connected ports in field order. Declare writes on the module; do not write readonly attributes. Outputs are the explicit binding, not label-based inference.
- `type:particle_node`, `settings:{kind:"custom",data_type:"vec3",code:"return a+b;",editor_profile:"standard_module_v1",input_ports:[{name:"a",type:"vec3"},{name:"b",type:"vec3"}]}` is a typed Code node. Feed its named input ports and connect output port 0 to the appropriate output field.

When importing a standard `.mmg`, its `particle_module` envelope is version 1 independently of effect v2. Copy the graph without the envelope into `mm_graph`; copy definition metadata and merge required attribute snapshots. Reuse an existing attribute only when its `standard_role`, type and compatible definition match. Remap all attribute references, output fields and `standard_module.bindings`; do not collapse distinct attributes just because their names match. A custom graph should not pretend to be a standard module by retaining incorrect catalog metadata.

Reusable `.mmg` modules contain no effect-specific User definitions/bindings. User links belong on effect instances. Preserve any nested graph and its connection indexes. Validate every graph edit through the real CLI and inspect it in the GUI when layout/readability matters.

Unsupported scope: collision/subemitters, transparent depth sorting, external textures/baked buffers and automatic Unreal/.ptex conversion. Do not fabricate unsupported nodes or APIs to satisfy a visual request; offer a supported approximation explicitly.
