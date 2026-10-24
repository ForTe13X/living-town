param(
    [string]$EnginePath = '',
    [switch]$Legacy,
    [switch]$Local,
    [string]$LocalSource = '',
    [ValidateSet('Mobile', 'Compatibility')][string]$Renderer = 'Mobile',
    [ValidateRange(0, 240)][int]$MaxFps = 60,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$GameArguments = @()
)
$ErrorActionPreference = 'Stop'
$townRoot = Split-Path -Parent $PSScriptRoot
$townGame = Join-Path $townRoot 'game'
if (-not $EnginePath) {
    foreach ($candidate in @('godot', 'godot4', 'Godot_v4.6.2-stable_win64_console.exe')) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($found) { $EnginePath = $found.Source; break }
    }
}
if (-not $EnginePath) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $candidate) { $EnginePath = $candidate }
}
if (-not $EnginePath -or -not (Test-Path -LiteralPath $EnginePath)) {
    throw 'Pass -EnginePath with the path to a Godot 4.6 executable.'
}
function Test-TownAssets([string]$Root) {
    $stagePath = Join-Path $Root 'game/assets/town3d/stage_manifest.json'
    if (-not (Test-Path -LiteralPath $stagePath -PathType Leaf)) { return $false }
    $stage = Get-Content -LiteralPath $stagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($stage.status -cne 'PASS') { return $false }
    $records = @()
    foreach ($row in $stage.files) {
        if ($row.file -match '(^[\\/]|\.\.|:|\\)') { throw 'Unsafe staged asset path.' }
        $records += @{ path=(Join-Path $Root ('game/assets/town3d/' + $row.file)); bytes=$row.bytes; sha256=$row.sha256 }
    }
    if ($stage.schema -ceq 'living_town.game_stage.v2') {
        $charactersPath = Join-Path $Root 'game/data/town3d/characters.json'
        if (-not (Test-Path -LiteralPath $charactersPath -PathType Leaf)) { return $false }
        $characters = Get-Content -LiteralPath $charactersPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($characters.characters.PSObject.Properties).Count -lt 25) { return $false }
        foreach ($entry in $characters.characters.PSObject.Properties.Value) {
            if ($entry.model -notmatch '^res://assets/characters3d/[A-Za-z0-9_-]+\.glb$' -or -not $entry.model_sha256 -or -not $entry.model_bytes) { return $false }
            $records += @{ path=(Join-Path $Root ('game/' + $entry.model.Substring(6))); bytes=$entry.model_bytes; sha256=$entry.model_sha256 }
        }
    }
    foreach ($row in $records) {
        if (-not (Test-Path -LiteralPath $row.path -PathType Leaf)) { return $false }
        if ((Get-Item -LiteralPath $row.path).Length -ne $row.bytes) { return $false }
        if ((Get-FileHash -LiteralPath $row.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256) { return $false }
    }
    return $true
}
if (-not $Legacy -and -not (Test-TownAssets $townRoot)) {
    $townFetch = Join-Path $PSScriptRoot 'fetch_town_assets.py'
    if (-not (Test-Path -LiteralPath $townFetch -PathType Leaf)) { throw 'Restore the source package asset downloader.' }
    $townFetchArgs = @($townFetch, '--root', $townRoot)
    if ($Local) { $townFetchArgs += '--local' }
    if ($LocalSource) { $townFetchArgs += @('--local-source', [IO.Path]::GetFullPath($LocalSource)) }
    $townPython = Get-Command 'py' -ErrorAction SilentlyContinue
    if ($townPython) {
        & $townPython.Source -3 @townFetchArgs
    } else {
        $townPython = Get-Command 'python' -ErrorAction SilentlyContinue
        if (-not $townPython) { throw 'Python3 is needed to retrieve missing assets. A complete verified offline package runs without Python.' }
        & $townPython.Source @townFetchArgs
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-TownAssets $townRoot)) { throw 'Complete town/character verification failed; Godot was not started.' }
}
# Prepare imported textures/scripts on a fresh checkout. Import and play are serial.
& (Join-Path $PSScriptRoot 'prepare-godot-optional.ps1') -GamePath $townGame
& $EnginePath --headless --editor --path $townGame --single-threaded-scene --max-fps 30 --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot project import failed.' }
$mode = if ($Legacy) { '--legacy-2d' } else { '--town3d' }
$townRenderer = if ($Legacy -or $Renderer -eq 'Compatibility') { 'gl_compatibility' } else { 'mobile' }
& $EnginePath --path $townGame --single-threaded-scene --rendering-method $townRenderer --max-fps $MaxFps -- $mode --life @GameArguments
exit $LASTEXITCODE
