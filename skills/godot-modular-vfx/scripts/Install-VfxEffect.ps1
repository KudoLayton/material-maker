#requires -Version 5.1
<##
Install one named CLI export into an existing Godot project.
Dry-run is the default. No project.godot or standalone demo is installed.
Recovery is checksum-guarded; concurrent user edits are never rolled back.
##>
[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(Mandatory,ParameterSetName='Install')][string]$Bundle,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(ParameterSetName='Install')][switch]$Apply,
    [Parameter(Mandatory,ParameterSetName='Recover')][switch]$Recover
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lock = $null
$transaction = $null

function Assert-Unlinked([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked path refused: $current" }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Resolve-Root([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Use absolute filesystem paths.' }
    Assert-Unlinked $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Missing directory: $Path" }
    return (Get-Item -LiteralPath $Path).FullName.TrimEnd('\','/')
}
function Child([string]$Root,[string]$Relative) {
    if ($Relative -notmatch '^[A-Za-z0-9_./-]+$' -or $Relative.StartsWith('/') -or $Relative.Split('/') -contains '..' -or $Relative.Split('/') -contains '.') { throw "Unsafe relative path: $Relative" }
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes root: $Relative" }
    Assert-Unlinked $path
    return $path
}
function Hash([string]$Path) {
    Assert-Unlinked $Path
    if (Test-Path -LiteralPath $Path -PathType Container) { throw "Expected file: $Path" }
    if (-not [IO.File]::Exists($Path)) { return '' }
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Map($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($p in $Value.PSObject.Properties) { $result[$p.Name] = Map $p.Value }
        return $result
    }
    if ($Value -is [Array]) { return ,@($Value | ForEach-Object { Map $_ }) }
    return $Value
}
function Read-Json([string]$Path) { return Map (ConvertFrom-Json ([IO.File]::ReadAllText($Path))) }
function Write-Json([string]$Path,$Value) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json $Value -Depth 64))
    [IO.File]::WriteAllBytes($Path,$bytes)
}
function Valid-Id([string]$Id) {
    return $Id -cmatch '^[a-z0-9_-]{1,64}$' -and $Id -notmatch '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$'
}
function Check-Files($Files,[string[]]$Expected) {
    if ($Files -isnot [hashtable] -or $Files.Count -ne $Expected.Count) { throw 'Unexpected managed file set.' }
    foreach ($relative in $Expected) {
        if (-not $Files.ContainsKey($relative) -or $Files[$relative] -cnotmatch '^[0-9a-f]{64}$') { throw "Missing/invalid checksum: $relative" }
    }
}
function Recover-Transaction([string]$Root,[string]$Tx) {
    $journalFile = Child $Tx 'journal.json'
    if (-not [IO.File]::Exists($journalFile)) { throw "Incomplete staging; inspect without deleting user work: $Tx" }
    $journal = Read-Json $journalFile
    if ($journal.format -ne 'mm_vfx_transaction' -or $journal.version -ne 1 -or $journal.project -ne $Root) { throw 'Invalid transaction journal.' }
    # A journal can only own generated VFX paths, never arbitrary project files.
    $seen = @{}
    foreach ($entry in $journal.entries) {
        if ($entry -isnot [hashtable] -or $entry.path -notmatch '^(\.mm-vfx/manifest\.json|addons/mm_gpu_particles/(effect\.gd|gpu_state\.gd|multimesh_lifetime\.gd|particles_3d\.gd|scheduler\.gd|value_codec\.gd|plugin\.gd|plugin\.cfg)|effects/modular_particles/[a-z0-9_-]{1,64}/(effect\.res|effect\.glsl\.txt|particles\.tscn|README\.txt))$' -or $seen.ContainsKey($entry.path) -or $entry.before -cnotmatch '^([0-9a-f]{64})?$' -or $entry.after -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid recovery entry.' }
        $seen[$entry.path] = $true
    }
    # Preflight the whole rollback before restoring any file.
    foreach ($entry in $journal.entries) {
        $target = Child $Root $entry.path
        $current = Hash $target
        if ($current -ne $entry.before -and $current -ne $entry.after) { throw "Concurrent edit prevents recovery: $target; journal: $Tx" }
        if ($entry.before -and (Hash (Child $Tx ('backup/' + $entry.path))) -ne $entry.before) { throw 'Recovery backup checksum mismatch.' }
    }
    foreach ($entry in $journal.entries) {
        $target = Child $Root $entry.path
        if ((Hash $target) -eq $entry.before) { continue }
        if ($entry.before) {
            $backup = Child $Tx ('backup/' + $entry.path)
            $restored = Child $Tx ('restore/' + $entry.path)
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($restored))
            [IO.File]::Copy($backup,$restored,$true)
            if ((Hash $target) -ne $entry.after) { throw 'Concurrent edit during recovery.' }
            $published = Child $Tx ('restored-published/' + $entry.path)
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($published))
            [IO.File]::Replace($restored,$target,$published)
        } else {
            if ((Hash $target) -ne $entry.after) { throw 'Concurrent edit during recovery.' }
            [IO.File]::Delete($target)
        }
    }
    # Retain evidence/backups instead of deleting a possibly user-inspected transaction.
    [IO.Directory]::Move($Tx,$Tx + '-recovered-' + [Guid]::NewGuid().ToString('N'))
}
try {
    $root = Resolve-Root $Project
    $config = Child $root 'project.godot'
    if (-not [IO.File]::Exists($config)) { throw 'Select an existing Godot project root.' }
    $configText = [IO.File]::ReadAllText($config)
    if ($configText -match '(?m)^renderer/rendering_method\s*=\s*"(?!forward_plus")[^"]+"') { throw 'Project requires Forward+; renderer settings are never changed automatically.' }
    $meta = Child $root '.mm-vfx'
    $transaction = Child $root '.mm-vfx/transaction'
    if (-not $Recover -and [IO.Directory]::Exists($transaction)) { throw 'Unfinished installation. Run with -Recover before installing.' }
    if ($Apply -or $Recover) {
        [void][IO.Directory]::CreateDirectory($meta)
        $lockPath = Child $root '.mm-vfx/install.lock'
        $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    }
    if ($Recover) {
        if (-not [IO.Directory]::Exists($transaction)) { throw 'No unfinished transaction exists.' }
        Recover-Transaction $root $transaction
        @{ok=$true;action='recovered';project=$root} | ConvertTo-Json -Compress
        exit 0
    }
    $source = Resolve-Root $Bundle
    if ($source -eq $root -or $source.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($source + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Staging bundle and game project must be separate.' }
    $sourceManifest = Child $source 'mm_particles_manifest.json'
    $sourceManifestHash = Hash $sourceManifest
    $incoming = Read-Json $sourceManifest
    if ($incoming.format -ne 'mm_gpu_particles_export' -or $incoming.version -ne 1 -or $incoming.target -ne '4.7.2' -or -not $incoming.ContainsKey('effect_id') -or -not (Valid-Id $incoming.effect_id)) { throw 'Expected a named latest CLI export manifest.' }
    if ($incoming.source_hash -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid effect source hash.' }
    $id = [string]$incoming.effect_id
    $effectRoot = "effects/modular_particles/$id/"
    $runtimeNames = @('effect.gd','gpu_state.gd','multimesh_lifetime.gd','particles_3d.gd','scheduler.gd','value_codec.gd','plugin.gd','plugin.cfg')
    $runtimePaths = @($runtimeNames | ForEach-Object { 'addons/mm_gpu_particles/' + $_ })
    $effectPaths = @('effect.res','effect.glsl.txt','particles.tscn','README.txt' | ForEach-Object { $effectRoot + $_ })
    $allowed = $runtimePaths + $effectPaths + @(($effectRoot + 'demo.tscn'), ($effectRoot + 'user_demo.gd'))
    if ($incoming.files -isnot [hashtable]) { throw 'Invalid export files.' }
    foreach ($path in $incoming.files.Keys) {
        if ($path -cnotin $allowed -or $incoming.files[$path] -cnotmatch '^[0-9a-f]{64}$' -or (Hash (Child $source $path)) -ne $incoming.files[$path]) { throw "Invalid export path/checksum: $path" }
    }
    foreach ($path in ($runtimePaths + $effectPaths)) { if (-not $incoming.files.ContainsKey($path)) { throw "Incomplete bundle: $path" } }
    $manifestPath = Child $root '.mm-vfx/manifest.json'
    $manifestBefore = Hash $manifestPath
    $installed = @{format='mm_vfx_install';version=1;target='4.7.2';runtime=@{};effects=@{}}
    if ($manifestBefore) {
        $installed = Read-Json $manifestPath
        if ($installed.format -ne 'mm_vfx_install' -or $installed.version -ne 1 -or $installed.target -ne '4.7.2' -or $installed.effects -isnot [hashtable] -or $installed.runtime -isnot [hashtable]) { throw 'Invalid installation manifest.' }
        Check-Files $installed.runtime $runtimePaths
        foreach ($oldId in $installed.effects.Keys) {
            if (-not (Valid-Id $oldId)) { throw 'Invalid installed effect ID.' }
            $oldPaths = @('effect.res','effect.glsl.txt','particles.tscn','README.txt' | ForEach-Object { "effects/modular_particles/$oldId/$_" })
            Check-Files $installed.effects[$oldId].files $oldPaths
        }
    }
    $operations = @()
    $runtime = @{}
    foreach ($path in $runtimePaths) {
        $current = Hash (Child $root $path)
        $expected = $incoming.files[$path]
        if (($installed.runtime.ContainsKey($path) -and $installed.runtime[$path] -ne $expected) -or ($current -and $current -ne $expected)) { throw "Runtime differs; automatic upgrade/replacement refused: $path" }
        if ($installed.runtime.ContainsKey($path) -and -not $current) { throw "Managed runtime file was removed: $path" }
        $runtime[$path] = $expected
        if (-not $current) { $operations += @{path=$path;before='';after=$expected} }
    }
    # An existing addon must match the complete runtime, not a partial overlay.
    $addon = Child $root 'addons/mm_gpu_particles'
    if ([IO.Directory]::Exists($addon) -and @($runtimePaths | Where-Object { -not [IO.File]::Exists((Child $root $_)) }).Count) { throw 'Existing addon is incomplete; refusing to overlay it.' }
    $previous = @{}
    if ($installed.effects.ContainsKey($id)) { $previous = $installed.effects[$id].files }
    $newFiles = @{}
    foreach ($path in $effectPaths) {
        $current = Hash (Child $root $path)
        if ($previous.ContainsKey($path)) {
            if ($current -ne $previous[$path]) { throw "Managed effect was modified/removed: $path" }
        } elseif ($current) { throw "Unmanaged file collision: $path" }
        $newFiles[$path] = $incoming.files[$path]
        if ($current -ne $newFiles[$path]) { $operations += @{path=$path;before=$current;after=$newFiles[$path]} }
    }
    $installed.runtime = $runtime
    $installed.effects[$id] = @{files=$newFiles;source_hash=$incoming.source_hash}
    $result = @{ok=$true;action='dry-run';effect_id=$id;project=$root;files=@($operations | ForEach-Object { $_.path });requires='Godot 4.7.2 stable / Forward+ / Vulkan'}
    if (-not $Apply) { $result | ConvertTo-Json -Depth 8; exit 0 }
    if ((Hash $sourceManifest) -ne $sourceManifestHash -or (Hash $manifestPath) -ne $manifestBefore) { throw 'Manifest changed during preflight.' }
    if ([IO.Directory]::Exists($transaction)) { throw 'Another transaction appeared during preflight.' }
    [void][IO.Directory]::CreateDirectory($transaction)
    foreach ($entry in $operations) {
        $staged = Child $transaction ('stage/' + $entry.path)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($staged))
        [IO.File]::Copy((Child $source $entry.path),$staged,$false)
        if ((Hash $staged) -ne $entry.after) { throw 'Source file changed during staging.' }
    }
    $stagedManifest = Child $transaction 'stage/.mm-vfx/manifest.json'
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($stagedManifest))
    Write-Json $stagedManifest $installed
    $operations += @{path='.mm-vfx/manifest.json';before=$manifestBefore;after=(Hash $stagedManifest)}
    foreach ($entry in $operations) {
        $target = Child $root $entry.path
        if ((Hash $target) -ne $entry.before) { throw 'Target changed during staging.' }
        if ($entry.before) {
            $backup = Child $transaction ('backup/' + $entry.path)
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup))
            [IO.File]::Copy($target,$backup,$false)
            if ((Hash $backup) -ne $entry.before) { throw 'Target changed during backup.' }
        }
    }
    Write-Json (Child $transaction 'journal.json') @{format='mm_vfx_transaction';version=1;project=$root;entries=$operations}
    try {
        foreach ($entry in $operations) {
            $target = Child $root $entry.path
            if ((Hash $target) -ne $entry.before) { throw "Concurrent edit: $target" }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $staged = Child $transaction ('stage/' + $entry.path)
            if ($entry.before) { [IO.File]::Replace($staged,$target,(Child $transaction ('backup/' + $entry.path))) }
            else { [IO.File]::Move($staged,$target) }
        }
    } catch {
        $failure = $_.Exception.Message
        Recover-Transaction $root $transaction
        throw "Install failed and rolled back: $failure"
    }
    [IO.Directory]::Move($transaction,$transaction + '-complete-' + [Guid]::NewGuid().ToString('N'))
    $result.action = 'installed'
    $result | ConvertTo-Json -Depth 8
} catch {
    @{ok=$false;error=$_.Exception.Message;recovery=$transaction} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
