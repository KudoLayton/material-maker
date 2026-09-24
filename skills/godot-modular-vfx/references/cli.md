# Portable CLI

Use `scripts/Invoke-Vfx.ps1`; it waits for the GUI executable to exit, separates engine logs from JSON, and works in PowerShell 5.1/7. Explicit `-App` overrides `MM_VFX_APP`; the last fallback is the enclosing portable package. Never substitute an unrelated executable merely because it is named MaterialMaker.

```powershell
$env:MM_VFX_APP = 'C:/Tools/MaterialMaker/MaterialMaker.exe'
& '<skill>/scripts/Invoke-Vfx.ps1' -Command capabilities
& '<skill>/scripts/Invoke-Vfx.ps1' -Command create -Template basic_fountain -Output C:/Work/fountain.mpfx
& '<skill>/scripts/Invoke-Vfx.ps1' -Command inspect -InputFile C:/Work/fountain.mpfx
& '<skill>/scripts/Invoke-Vfx.ps1' -Command validate -InputFile C:/Work/fountain.mpfx
& '<skill>/scripts/Invoke-Vfx.ps1' -Command export -InputFile C:/Work/fountain.mpfx -Output C:/Work/staging-fountain -EffectId fountain -Capacity 4096
```

The parent directory for `create` must already exist. Input/output/report paths must be absolute and unlinked; `..` traversal is refused. Template names come from capabilities (`basic_fountain`, `box_turbulence`, `sphere_burst`, `user_parameters`, `mmtest`). Effect IDs are lowercase `[a-z0-9_-]{1,64}`, excluding Windows device names.

- `inspect` returns the original JSON structure after shape validation. It is not a semantic compile.
- `validate` loads actual module graphs and compiles structure/types/bindings. It runs headlessly and reports `gpu_compiled=false`.
- `export` requires Forward+ and Vulkan, compiles SPIR-V and reports `gpu_compiled=true`. Capacity defaults to the document's `preview_capacity`, otherwise 4096. GPU memory limits are checked.
- Each staging folder has one effect identity; separate folders allow multiple game effects. Reusing a folder with a different ID or locally modified managed files is refused.
- The app never modifies its GUI preferences/recent files in CLI mode.

JSON: `contract_version`, `command`, `ok`, `exit_code`, `diagnostics`, `data`. Diagnostics have stage/message and available module/node IDs. Capabilities include `runtime_id` and file checksums. Export includes its manifest and checksums.

Exit codes: 0 success; 2 invalid arguments/path/ID; 3 unsupported format/JSON/types/graphs/shader/capacity; 4 engine/GPU environment; 5 I/O/ownership conflict. The wrapper returns 1 for its own setup/process/report failures. Read the diagnostic rather than guessing from 1 alone.

`-Report` optionally selects a **new** report file; otherwise each invocation uses a unique temporary directory. Never overwrite an existing report/input file. The app also emits `MM_VFX_REPORT {JSON}` independently of engine logs. Early argument errors may only have this log report. A timeout stops the wrapper's own process and requires inspecting staging/logs before retry, not an automatic retry loop.

Direct app flags are `-- --mpfx-command COMMAND --input FILE --output PATH --template NAME --effect-id ID --capacity N --report FILE` as applicable. Put engine `--headless` or `--rendering-method forward_plus --rendering-driver vulkan` **before** the `--` separator. Do not pass all command-specific options indiscriminately.
