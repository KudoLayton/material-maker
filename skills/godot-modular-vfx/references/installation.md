# Safe game-project installation

Read this when applying a **named CLI export** to an existing Godot project. Use an explicit `--effect-id` when exporting; the older GUI's unnamed staging layout is not accepted by the installer.

## Install

Resolve the script relative to this skill directory (not the game's working directory).

```powershell
# Default: validate and show the changes, without creating any project files.
& '<skill>/scripts/Install-VfxEffect.ps1' -Bundle 'C:/Work/staging-fountain' -Project 'C:/Games/MyGame'
# After confirming the intended project/effect and reviewing conflicts:
& '<skill>/scripts/Install-VfxEffect.ps1' -Bundle 'C:/Work/staging-fountain' -Project 'C:/Games/MyGame' -Apply
```

Supports Windows PowerShell 5.1 and PowerShell 7. Python and a source checkout are not needed. Treat downloaded scripts and runtime bundles as executable code: inspect unfamiliar sources before running. Checksums detect changes; they are not publisher signatures.

- Game runtime must be Godot **4.7.2 stable / Forward+ / Vulkan**. The helper rejects an explicitly incompatible renderer but does not prove the installed engine/GPU version. Verify those separately.
- Install `addons/mm_gpu_particles/` once. An existing **complete, byte-identical** addon is reusable. Missing/modified/different-version addon files are not automatically repaired or upgraded.
- Each effect installs `effect.res`, `particles.tscn`, diagnostic `effect.glsl.txt` and `README.txt` below `effects/modular_particles/<id>/`.
- `project.godot`, standalone `demo.tscn`/`user_demo.gd`, cameras, autoloads and main-scene settings are not installed or modified.
- Instance `effects/modular_particles/<id>/particles.tscn` in the user's 3D scene or assign its `effect.res` to `MMGPUParticles3D`. Keep user wrapper scenes and game scripts outside the managed effect folder.
- `.mm-vfx/manifest.json` records effect ownership/checksums and the shared runtime's exact file set. An unrelated effect is never rewritten by updating another.
- Unmanaged collisions and edits/removals to managed files block replacement even if the intended new output seems equivalent. Do not delete manifests or use force-copy to bypass this protection.
- Paths must be absolute, with no linked ancestors; bundle and project roots must be separate. A lock serializes installers. Checksums are rechecked before publish.

## Interrupted writes / recovery

Publishing uses staged files, original backups, and a write-ahead journal inside `.mm-vfx/transaction/`. The manifest is published last. An ordinary mid-publish error triggers a checksum-guarded rollback. Completed/recovered transactions are retained as evidence, rather than deleting files a user might be inspecting.

If a process was interrupted, the next install stops. Review the diagnostic and journal, then explicitly request recovery:

```powershell
& '<skill>/scripts/Install-VfxEffect.ps1' -Project 'C:/Games/MyGame' -Recover
```

Recovery preflights every managed target and backup before changing anything. If a user modified a target after interruption, recovery stops instead of discarding that edit. Missing/corrupt journals or backups require manual review; never delete them to retry blindly. Recovery does not change renderer/project settings.

The helper emits JSON and exits 0 on success, 1 on error. `action: dry-run` is **not** evidence of installed or working particles. Follow installation with an independent Godot load/run and actual GPU validation.
