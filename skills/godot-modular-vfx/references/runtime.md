# Godot integration and external parameters

The supported environment is Godot **4.7.2 stable / Forward+ / Vulkan**. `effect.res` contains compiled SPIR-V; Material Maker/graphs/CLI are not game dependencies. Do not modify engine source or replace normal Godot particle nodes with guessed APIs.

Install the generated addon/effect using [installation.md](installation.md). Instance the generated `particles.tscn` in the user's scene, keeping a suitable Camera3D elsewhere. Alternatively create `MMGPUParticles3D` and assign `Effect` to the effect resource. Plugin checkbox activation is optional for class_name registration; no new autoload/Dock is required.

- Set `capacity` and `visibility_aabb` to encompass the effect; particles outside an insufficient bound may disappear. Excess spawns over capacity are dropped.
- Select Local/World simulation deliberately. Keep transforms in the intended space.
- `preview_in_editor` defaults false; enable for editor preview only when wanted.
- Additive, opaque and cutout are supported, not sorted transparent particles. Defaults use a quad; Mesh/Draw Material are separate renderer choices.

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

Verify in an isolated scene first: resource loads without errors, expected GPU particles appear, rate/burst/repeat behavior matches, User changes affect intended inputs, two nodes remain independent, reset restores defaults, stop/restart work and bounds/space fit the target camera. A success return from the installer is not a GPU or visual test. Integrate into an existing game scene only within the user's requested scope; do not set a generated demo as the game's main scene.
