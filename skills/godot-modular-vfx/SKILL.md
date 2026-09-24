---
name: godot-modular-vfx
description: Create and edit Material Maker Modular VFX (.mpfx) effects and module graphs, compile them with the portable VFX CLI, and safely integrate them into other Godot projects with dynamic User parameters. Use for MMGPUParticles3D workflows, not ordinary Godot shader editing or Unreal Niagara asset conversion.
---

# Godot Modular VFX

Use the compatible **portable Material Maker fork**, not an arbitrary upstream executable. The game uses the standalone addon; it does not load authoring graphs or require Material Maker autoloads.

## Start with the environment and intent

- Locate the game's `project.godot`, existing effects/addon, source `.mpfx` and version control state. Preserve unrelated changes.
- Resolve every bundled script/reference relative to this skill directory. Use PowerShell on Windows.
- Resolve the app from the user's explicit path, `MM_VFX_APP`, or this skill's enclosing portable package. Do not assume a developer checkout or machine-specific path. If missing/ambiguous, ask for the package location; do not clone private repositories or install software implicitly.
- Run `scripts/Invoke-Vfx.ps1 -Command capabilities`. Require CLI contract 1, document/effect format 2, target Godot 4.7.2. **No v1 migration/fallback.** Module metadata/export manifests have separate version 1 formats.
- Clarify missing high-impact intent: visual behavior, rate/burst schedule, lifetime/count/capacity, Local/World, gameplay-controlled values, effect ID and target scene. Do not ask facts discoverable from files.

## Choose the relevant workflow

1. **Create/edit source:** read [authoring.md](references/authoring.md). Start from a matching packaged template, preserve IDs and bindings, and edit only requested behavior. Defaults for new work are `vfx_sources/<effect-id>/effect.mpfx` and lowercase effect IDs; preserve existing user paths.
2. **Compile/export:** read [cli.md](references/cli.md). Validate with the real compiler, then export to a separate staging folder with an explicit effect ID. Headless validation is not GPU compilation or a visual approval.
3. **Install/update:** read [installation.md](references/installation.md). Run the checksum installer dry-run, review the intended changes, then apply within the user's authorized project scope. Never force-copy over a conflicting addon/effect or remove its manifest to bypass a conflict.
4. **Game control/test:** read [runtime.md](references/runtime.md). Instance the generated scene, wire actual typed User names/IDs, and test per-node overrides plus reset.

Module/Attribute/User labels do not automatically bind. Keep simulation definitions in the effect source, runtime overrides on individual game nodes, and game wrapper scripts outside managed export files.

## Verification and reporting

- Read structured diagnostics and exit codes. Correct the narrow cause and rerun the relevant check; do not repeatedly overwrite/retry a conflicted destination.
- Verify source changes, v2 compile/export, independent resource load, actual GPU behavior and scene integration. For visual changes, preview in Material Maker or the game and distinguish automated numeric checks from visual inspection.
- A failed edit/compile is not permission to discard the last good effect, user override, source, or export.
- Report source/output/scene paths, format/app/runtime identities, changed behavior, executed checks and remaining limits. If GPU or the intended agent is unavailable, report that part as unverified rather than success.
- Installing this skill does not install Material Maker, Godot or an effect. Normal use does not authorize git push, release publication, automatic dependency upgrades, global installation or unrelated configuration changes.

## Invocation

Codex: `$godot-modular-vfx` with the requested effect/game task.
Pi: `/skill:godot-modular-vfx` with the requested effect/game task.

Use only the tools available in the current agent; this skill does not require an MCP server or agent-specific executable integration.
