param(
    [string]$EnginePath = '',
    [switch]$Legacy,
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
if (-not $Legacy) {
    $townAsset = Join-Path $townGame 'assets/town3d/living_town_game.glb'
    if (-not (Test-Path -LiteralPath $townAsset -PathType Leaf)) {
        $townFetch = Join-Path $PSScriptRoot 'fetch_town_assets.py'
        if (-not (Test-Path -LiteralPath $townFetch -PathType Leaf)) {
            throw 'Town asset is missing and fetch_town_assets.py was not included. Restore the source package tools or download the pinned release asset.'
        }
        $townPython = Get-Command 'py' -ErrorAction SilentlyContinue
        if ($townPython) {
            & $townPython.Source -3 $townFetch
        } else {
            $townPython = Get-Command 'python' -ErrorAction SilentlyContinue
            if (-not $townPython) {
                throw 'Python 3.10+ is required for the first town asset download. Install Python, or download living_town_game.glb from release town3d-walkthrough-2026-10-12 into game/assets/town3d.'
            }
            & $townPython.Source $townFetch
        }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $townAsset -PathType Leaf)) {
            throw 'Verified town asset retrieval failed. See the downloader message; Godot was not started.'
        }
    }
}
# Prepare imported textures/scripts on a fresh checkout. Import and play are serial.
& (Join-Path $PSScriptRoot 'prepare-godot-optional.ps1') -GamePath $townGame
& $EnginePath --headless --editor --path $townGame --single-threaded-scene --max-fps 30 --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot project import failed.' }
$mode = if ($Legacy) { '--legacy-2d' } else { '--town3d' }
& $EnginePath --path $townGame --single-threaded-scene --max-fps 30 -- $mode --life @GameArguments
exit $LASTEXITCODE
