# Portable CLI

Use `scripts/Invoke-Vfx.ps1`; it waits for the GUI executable to exit, separates engine logs from JSON, and works in PowerShell 5.1/7. Explicit `-App` overrides `MM_VFX_APP`; the last fallback is the enclosing portable package. Never substitute an unrelated executable merely because it is named MaterialMaker.

```powershell
$env:MM_VFX_APP = 'C:/Tools/MaterialMaker/MaterialMaker.exe'
& '<skill>/scripts/Invoke-Vfx.ps1' -Command capabilities
& '<skill>/scripts/Invoke-Vfx.ps1' -Command create -Template basic_fountain -Output C:/Work/fountain.mpfx
& '<skill>/scripts/Invoke-Vfx.ps1' -Command inspect -InputFile C:/Work/fountain.mpfx
& '<skill>/scripts/Invoke-Vfx.ps1' -Command validate -InputFile C:/Work/fountain.mpfx
# Default 3D export; a separate staging directory for each target/effect.
& '<skill>/scripts/Invoke-Vfx.ps1' -Command export -InputFile C:/Work/fountain.mpfx -Output C:/Work/staging-fountain -EffectId fountain -Capacity 4096
# Same .mpfx, exported as 2D with an optional embedded PNG.
& '<skill>/scripts/Invoke-Vfx.ps1' -Command export -InputFile C:/Work/fountain.mpfx -Output C:/Work/staging-fountain2d -EffectId fountain2d -Capacity 4096 -RenderTarget 2d -PixelsPerUnit 100 -FlipY true -BlendMode alpha -Sprite C:/Art/particle.png
```

The parent directory for `create` must already exist. Input/output/report paths must be absolute and unlinked; `..` traversal is refused. Template names come from capabilities (`basic_fountain`, `box_turbulence`, `sphere_burst`, `user_parameters`, `mmtest`). Effect IDs are lowercase `[a-z0-9_-]{1,64}`, excluding Windows device names.

- `inspect` returns the original JSON structure after shape validation. It is not a semantic compile.
- `validate` loads actual module graphs and compiles structure/types/bindings. It runs headlessly and reports `gpu_compiled=false`.
- `export` requires Forward+ and Vulkan or D3D12 (Windows), compiles SPIR-V and reports `gpu_compiled=true` plus the actual `rendering_driver`. The helper defaults to Vulkan; use `-RenderingDriver d3d12` for D3D12. A backend mismatch fails the helper rather than silently accepting fallback. This requires the matching D3D12-enabled CLI build. Capacity defaults to the document's `preview_capacity`, otherwise 4096. GPU memory limits are checked.
- Each staging folder has one effect identity and render target; separate folders allow multiple game effects. Reusing a folder with a different ID, target or locally modified managed files is refused. Old manifests without `render_target` mean 3D. Use a new staging folder instead of removing the manifest.
- The app never modifies its GUI preferences/recent files in CLI mode.

## Output options (export only)

| Helper parameter | Direct app option | Values / omitted default |
|---|---|---|
| `-RenderTarget` | `--render-target` | `3d` (default) or `2d` |
| `-PixelsPerUnit` | `--pixels-per-unit` | Positive finite number, default `100` |
| `-FlipY` | `--flip-y` | String `true` (default) or `false`, not a PowerShell switch |
| `-BlendMode` | `--blend-mode` | `effect` (default), `alpha`, `additive`, `opaque`, `cutout` |
| `-Sprite` | `--sprite` | Absolute PNG path; omitted means no texture |

All options are optional. The last four require `-RenderTarget 2d`; they are rejected for omitted/explicit 3D. Pass them only to `export`, not create/inspect/validate/capabilities. The helper forwards only explicitly supplied output options and formats Pixels Per Unit with an invariant decimal point. Enum values are passed lowercase. Export options do not mutate .mpfx or convert vec3 simulation/User types.

2D defaults project `(x,y,z)` to `(100x,-100y)` pixels. See [runtime.md](runtime.md) for bounds, World/Local behavior, materials and projection limits. PNG limits are 64 MiB, 8192 pixels per side and 16 megapixels. Image data is embedded in `sprite.res` without an external PNG/import-cache dependency. Invalid or missing PNG input fails export; it is not silently ignored.

## Reports and compatibility

JSON: `contract_version`, `command`, `ok`, `exit_code`, `diagnostics`, `data`. Diagnostics have stage/message and available module/node IDs. Capabilities must report CLI contract 1, `document_version: 2`, `effect_version: 3`, `render_targets: ["3d","2d"]`, `runtime_effect_versions: {"3d":[2,3],"2d":[3]}` and the five `export_optional_options` above. Capabilities also include `runtime_id` and file checksums. The new addon accepts existing v2 compiled effects in 3D only; re-export the source for 2D. Never change a document/resource version to bypass compatibility checks.

Export includes `data.render_target`, `data.effect_version: 3`, and a version 1 manifest with `render_target`, `effect_version`, file checksums and source hash. The same source produces shared v3 simulation for 2D/3D; scene/output settings differ.

Exit codes: 0 success; 2 invalid arguments/path/ID; 3 unsupported format/JSON/types/graphs/shader/capacity; 4 engine/GPU environment; 5 I/O/ownership conflict. The wrapper returns 1 for its own setup/process/report failures. Read the diagnostic rather than guessing from 1 alone.

`-Report` optionally selects a **new** report file; otherwise each invocation uses a unique temporary directory. Never overwrite an existing report/input file. The app also emits `MM_VFX_REPORT {JSON}` independently of engine logs. Early argument errors may only have this log report. A timeout stops the wrapper's own process and requires inspecting staging/logs before retry, not an automatic retry loop.

Direct app flags are `-- --mpfx-command COMMAND --input FILE --output PATH --template NAME --effect-id ID --capacity N --report FILE` as applicable, plus the export-only options listed above. Put engine `--headless` or `--rendering-method forward_plus --rendering-driver vulkan` (or `d3d12`) **before** the `--` separator. Do not pass all command-specific options indiscriminately.
