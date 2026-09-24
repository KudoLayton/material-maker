#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('capabilities','create','inspect','validate','export')][string]$Command,
    [string]$App,
    [string]$InputFile,
    [string]$Output,
    [string]$Template,
    [string]$EffectId,
    [int]$Capacity,
    [string]$Report
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Windows command-line quoting, not shell evaluation.
function Quote-Argument([string]$Text) {
    return '"' + [regex]::Replace([regex]::Replace($Text,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}
try {
    if (-not $App) { $App = $env:MM_VFX_APP }
    if (-not $App) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../MaterialMaker.exe'))
        if ([IO.File]::Exists($candidate)) { $App = $candidate }
    }
    if (-not $App -or -not [IO.Path]::IsPathRooted($App) -or -not [IO.File]::Exists($App)) { throw 'Specify the compatible portable MaterialMaker.exe using -App or MM_VFX_APP.' }
    $run = Join-Path ([IO.Path]::GetTempPath()) ('mm-vfx-call-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run)
    if (-not $Report) { $Report = Join-Path $run 'report.json' }
    if (-not [IO.Path]::IsPathRooted($Report) -or [IO.File]::Exists($Report) -or [IO.Directory]::Exists($Report)) { throw 'Report must be a new absolute file path.' }
    $arguments = @('--log-file',(Join-Path $run 'engine.log'))
    if ($Command -eq 'export') { $arguments += @('--rendering-method','forward_plus','--rendering-driver','vulkan','--position','-32000,-32000') }
    else { $arguments += '--headless' }
    $arguments += @('--','--mpfx-command',$Command)
    $values = @{input=$InputFile;output=$Output;template=$Template;'effect-id'=$EffectId;report=$Report}
    foreach ($name in @('input','output','template','effect-id','report')) {
        if ($values[$name]) { $arguments += @(('--' + $name),([string]$values[$name])) }
    }
    if ($PSBoundParameters.ContainsKey('Capacity')) { $arguments += @('--capacity',[string]$Capacity) }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $App
    $start.Arguments = ($arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(180000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "VFX command timed out; inspect logs/staging before retry: $run"
    }
    [IO.File]::WriteAllText((Join-Path $run 'process.log'),$stdout.Result + $stderr.Result)
    $code = $process.ExitCode
    $process.Dispose()
    if ([IO.File]::Exists($Report)) {
        $json = [IO.File]::ReadAllText($Report)
        $result = ConvertFrom-Json $json
        if ($result.contract_version -ne 1 -or $result.command -ne $Command -or $result.exit_code -ne $code) { throw "CLI report mismatch; inspect $run" }
        $json
    } else {
        # Early argument/report-path errors may only be in the engine log.
        $log = Join-Path $run 'engine.log'
        $records = @([IO.File]::ReadAllLines($log) | Where-Object { $_.StartsWith('MM_VFX_REPORT ') })
        if ($records.Count -eq 0) { throw "No CLI report; wrong app or startup failure. Logs: $run" }
        $records[-1].Substring('MM_VFX_REPORT '.Length)
    }
    exit $code
} catch {
    @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Compress
    exit 1
}
