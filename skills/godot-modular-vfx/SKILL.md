---
name: godot-modular-vfx
description: Create and edit Material Maker Modular VFX (.mpfx) effects and module graphs, compile them with the portable VFX CLI, and safely integrate them into other Godot projects with dynamic User parameters. Use for MMGPUParticles2D and MMGPUParticles3D workflows with shared v3 simulation, not ordinary Godot shader editing or Unreal Niagara asset conversion.
---

# Godot Modular VFX

Use the compatible **portable Material Maker fork**, not an arbitrary upstream executable. The game uses the standalone addon; it does not load authoring graphs or require Material Maker autoloads.

## Start with the environment and intent

- Locate the game's `project.godot`, existing effects/addon, source `.mpfx` and version control state. Preserve unrelated changes.
- Resolve every bundled script/reference relative to this skill directory. Use PowerShell on Windows.
- Resolve the app from the user's explicit path, `MM_VFX_APP`, or this skill's enclosing portable package. Do not assume a developer checkout or machine-specific path. If missing/ambiguous, ask for the package location; do not clone private repositories or install software implicitly.
- Run `scripts/Invoke-Vfx.ps1 -Command capabilities`. Require CLI `contract_version: 1`, `document_version: 2`, new compiled `effect_version: 3`, target Godot 4.7.2, and `render_targets: ["3d","2d"]`. Check `runtime_effect_versions`: 3D accepts v2/v3; 2D requires v3. **Do not relabel a .mpfx as v3 or migrate v1 by changing its version.** Module metadata/export manifests have separate version 1 formats.
- Clarify missing high-impact intent: 2D/3D target, visual behavior, rate/burst schedule, lifetime/count/capacity, Local/World, gameplay-controlled values, effect ID and target scene. For 2D, also resolve Pixels Per Unit, Flip Y, blend mode and optional PNG. Do not ask facts discoverable from files.

## Choose the relevant workflow

1. **Create/edit source:** read [authoring.md](references/authoring.md). Start from a matching packaged template, preserve IDs and bindings, and edit only requested behavior. Defaults for new work are `vfx_sources/<effect-id>/effect.mpfx` and lowercase effect IDs; preserve existing user paths.
2. **Compile/export:** read [cli.md](references/cli.md). Validate with the real compiler, then export to a separate staging folder with an explicit effect ID. Omitted `-RenderTarget` means 3D; use `-RenderTarget 2d` for 2D. Target/output options do not change the source document or its vec3 simulation. Do not reuse a staging folder for a different target. Headless validation is not GPU compilation or a visual approval.
3. **Install/update:** read [installation.md](references/installation.md). Run the checksum installer dry-run, review the intended changes, then apply within the user's authorized project scope. Never force-copy over a conflicting addon/effect or remove its manifest to bypass a conflict.
4. **Game control/test:** read [runtime.md](references/runtime.md). Instance the generated 2D or 3D scene, wire actual typed User names/IDs, and test per-node overrides plus reset. 2D projects still use Forward+, not Compatibility/Mobile; User vec3 values do not become Vector2.

Module/Attribute/User labels do not automatically bind. Keep simulation definitions in the effect source, runtime overrides on individual game nodes, and game wrapper scripts outside managed export files.

## Verification and reporting

- Read structured diagnostics and exit codes. Correct the narrow cause and rerun the relevant check; do not repeatedly overwrite/retry a conflicted destination.
- Verify source changes, document v2 to compiled v3 export, manifest `render_target`, independent resource load, actual GPU behavior and scene integration. Existing v2 compiled effects remain supported by the new 3D runtime only; re-export from .mpfx for 2D. Older addons reject v3, so review runtime identity before installing rather than silently upgrading.
- For visual changes, distinguish automated numeric checks from visual inspection. Material Maker's authoring preview is still 3D; inspect the exported 2D result in a Godot 2D scene, including projection, pixel scale, bounds and sprite appearance.
- A failed edit/compile is not permission to discard the last good effect, user override, source, or export.
- Report source/output/scene paths, format/app/runtime identities, changed behavior, executed checks and remaining limits. If GPU or the intended agent is unavailable, report that part as unverified rather than success.
- Installing this skill does not install Material Maker, Godot or an effect. Normal use does not authorize git push, release publication, automatic dependency upgrades, global installation or unrelated configuration changes.

## Invocation

Codex: `$godot-modular-vfx` with the requested effect/game task.
Pi: `/skill:godot-modular-vfx` with the requested effect/game task.

Use only the tools available in the current agent; this skill does not require an MCP server or agent-specific executable integration.
