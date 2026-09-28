# Godot integration and external parameters

The supported environment is Godot **4.7.2 stable / Windows x64 / Forward+ / Vulkan or D3D12**. Both are regression targets. Select D3D12 with `rendering/rendering_device/driver.windows="d3d12"` (restart editor) or `--rendering-driver d3d12`. Verify the actual driver via `RenderingServer.get_current_rendering_driver_name()`; Vulkan fallback is not D3D12 validation. Other platforms/backends and universal hardware/performance guarantees are outside the tested contract. `effect.res` contains compiled SPIR-V; Material Maker/graphs/CLI are not game dependencies. Do not modify engine source or replace normal Godot particle nodes with guessed APIs.

Install the generated addon/effect using [installation.md](installation.md). Instance the generated `particles.tscn` in the matching 2D/3D scene; it contains no camera. Keep a suitable Camera3D elsewhere for 3D; use the game's existing Canvas/Camera2D setup for 2D (the standalone 2D demo includes a Camera2D). Plugin checkbox activation is optional for class_name registration; no new autoload/Dock is required.

## Shared simulation, distinct output

New compiled `MMParticleEffect` v3 resources/SPIR-V work on both `MMGPUParticles3D` and `MMGPUParticles2D`. Assign `effect` to the resource when creating a node manually. Existing v2 compiled resources work on the new 3D node only; re-export the v2 .mpfx for use in 2D. Older addons reject v3. Do not relabel a resource's version.

- Position, velocity and gravity remain Vector3; rotation is a quaternion. A vec3 User still requires Vector3, not Vector2, in 2D. Spawn/Update, Attributes, random state and User types are shared.
- Set `capacity` deliberately: excess spawns are dropped. 2D submits the full Capacity to the Canvas MultiMesh (dead slots have zero area), not a GPU indirect living count; avoid unnecessarily large allocations.
- `preview_in_editor` defaults false on both nodes; enable only when wanted. Material Maker's authoring preview remains 3D.
- For 3D, set `visibility_aabb`, Local/World, Mesh and Draw Material as appropriate. Built-in 3D modes are additive, opaque and cutout, not sorted transparency.

## 2D projection and appearance

These are node/export output settings, not simulation units or .mpfx fields:

| Setting | Behavior |
|---|---|
| `pixels_per_unit` | Positive finite number; default 100. Scale/quad size use the same pixel conversion. |
| `flip_y` | Default true: `(x,y,z)` projects to `(100x,-100y)`. False preserves the Y sign. |
| `simulation_space` | Local (0) follows node/parent translation, rotation and scale. World (1) applies the emitter's position only, as in 3D; already emitted particles do not follow later node transforms. World output inverse transforms also refresh while paused; node transforms must remain invertible. |
| `visibility_rect` | Local pixels in Local mode, Canvas/world pixels in World mode. Default `Rect2(-10000,-10000,20000,20000)`; set manually to cover the effect. Insufficient bounds can cull it. |
| `blend_mode` | Effect (0), Alpha (1), Additive (2), Opaque (3), Cutout (4); Cutout threshold 0.5. |
| `texture` | Optional Texture2D; PNG export stores embedded `sprite.res`. Untextured output uses quad/round_quad. Size is original quad_size × particle Scale × Pixels Per Unit, not the PNG's pixel dimensions. |
| `draw_material` | Only CanvasItemMaterial or a canvas_item ShaderMaterial. No spatial materials. |

Z remains in the simulation but is not screen depth. Quaternion/scale XY basis is orthographically projected, so 3D tilt can flatten a quad or make it edge-on. No 3D billboard or lighting is applied. Default 2D materials are unshaded and use Color, CustomData/INSTANCE_CUSTOM, Canvas modulate/self_modulate and node z_index. Per-particle depth/Y sorting, sprite sheets, collision, Mobile/Compatibility/Web and automatic vec2 graph conversion are unsupported.

## Game control (both nodes)

The API below is identical for 2D; change the annotation to `MMGPUParticles2D` for a 2D scene. Do not change the User value types.

```gdscript
@onready var particles: MMGPUParticles3D = $Particles

func activate() -> void:
    particles.restart() # resets particle state and scheduler

func update_inputs(speed: float, tint: Color) -> void:
    if not particles.set_user_parameter("User.Speed", speed):
        push_warning("Effect has no compatible User.Speed")
    particles.set_user_parameter("User.Tint", tint) # requires vec4 User.Tint

func reset_inputs() -> void:
    particles.reset_user_parameter("User.Speed")
    particles.reset_user_parameter("User.Tint")
```

These names are examples, not universally present. Read `inspect`/compiled User definitions first. Types: float, int, uint, bool, Vector2/3/4; vec4 also accepts Color. ID-based `set/get/reset_user_parameter_by_id` supports stable bindings when labels change.

- Inspector **User Parameters** stores per-node overrides in the scene; changing one node must not mutate the shared effect default or another node.
- Values reach the existing parameter buffer on the next simulation step, without recompilation/restart. Paused particles do not advance until resumed.
- `set_parameter("instance_id/input_id", value)` controls only unbound Constant inputs. It returns false for User-bound inputs; call the User API instead.
- `pause()` pauses simulation; `play()` resumes and enables emission; `stop()` stops new emission but lets living particles update; `emit_burst(count)` explicitly queues particles. `restart()` resets effect state.

Verify in an isolated scene first: resource loads without errors, expected GPU particles appear, rate/burst/repeat behavior matches, User changes affect intended inputs, two nodes remain independent, reset restores defaults, stop/restart work and bounds/space fit the target camera. For 2D, also check Pixels Per Unit/Y sign, Local/World under parent transforms and paused movement, PNG UV/alpha, blend/material and Canvas/Camera2D placement. A success return from the installer is not a GPU or visual test. Integrate into an existing game scene only within the user's requested scope; do not set a generated demo as the game's main scene.
