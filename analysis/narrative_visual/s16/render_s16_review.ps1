param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")),
    [string]$LabRoot = "E:\Documents\Dev\living-town-narrative-lab",
    [string]$Godot = "godot",
    [string]$Uv = "uv",
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$resolvedLab = (Resolve-Path -LiteralPath $LabRoot).Path
$gameRoot = Join-Path $resolvedRoot "game"
$mediaDir = Join-Path $resolvedRoot "analysis\narrative_visual\s16"
$scene = "res://narrative_lab/s16/scenes/s16_compositor_test.tscn"

function Assert-ExitCode {
    param([int]$Expected, [string]$Label)
    if ($LASTEXITCODE -ne $Expected) {
        throw "$Label exited $LASTEXITCODE; expected $Expected"
    }
}

Write-Host "[S16] headless committed-trace logic gate"
& $Godot --headless --path $gameRoot $scene -- --logic-only --no-output
Assert-ExitCode -Expected 0 -Label "S16 headless logic"

Write-Host "[S16] handoff half-commit negative control"
& $Godot --headless --path $gameRoot $scene -- --negative-control --no-output
Assert-ExitCode -Expected 7 -Label "S16 negative control"

if (-not $Check) {
    Write-Host "[S16] real framebuffer component-layout review"
    & $Godot --path $gameRoot $scene -- --out $mediaDir
    Assert-ExitCode -Expected 0 -Label "S16 framebuffer gate"
}

Write-Host "[S16] source/media gate"
$verifier = Join-Path $mediaDir "verify_s16_artifacts.py"
$gate = Join-Path $mediaDir "media_gate.json"
& $Uv run python $verifier --root $resolvedRoot --lab-root $resolvedLab --output $gate
Assert-ExitCode -Expected 0 -Label "S16 source/media gate"

Write-Host "[S16] targeted Python artifact tests"
Push-Location $resolvedRoot
try {
    & $Uv run python -m unittest -q analysis.narrative_visual.s16.test_s16_compositor
    Assert-ExitCode -Expected 0 -Label "S16 Python tests"
}
finally {
    Pop-Location
}

Write-Host "[S16] PASS - component review only; NOT SIM; no gameplay claim"
