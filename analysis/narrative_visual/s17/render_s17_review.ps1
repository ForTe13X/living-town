param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")),
    [string]$Godot = "godot",
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe",
    [string]$Uv = "uv",
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$game = Join-Path $root "game"
$media = Join-Path $root "analysis\narrative_visual\s17"
$scene = "res://narrative_lab/s16/scenes/s17_capture_test.tscn"
$sourceCommit = "af72cfb55b191f28f97cd59ea8fcd2376f5e1f46"
$fixtureHash = "90ddd379d67b3e251ac0113a548706c95f840ae6c5aea0ee50a587a2ab3e8198"
$separator = [char]0x00B7
$banner = "NARRATIVE LAB $separator NOT SIM $separator READ-ONLY COMMITTED TRACE $separator NOT GAMEPLAY"
$comment = "NOT SIM; READ-ONLY COMMITTED TRACE; NOT GAMEPLAY; deterministic S17 component review holds"

function Assert-ExitCode {
    param([int]$Expected, [string]$Label)
    if ($LASTEXITCODE -ne $Expected) {
        throw "$Label exited $LASTEXITCODE; expected $Expected"
    }
}

Write-Host "[S17] headless dispatcher sequence"
& $Godot --headless --path $game $scene -- --logic-only --no-output
Assert-ExitCode -Expected 0 -Label "S17 headless capture gate"

if (-not $Check) {
    Write-Host "[S17] real framebuffer dispatcher captures"
    & $Godot --path $game $scene -- --out $media
    Assert-ExitCode -Expected 0 -Label "S17 framebuffer captures"

    Write-Host "[S17] deterministic contact sheet"
    & $Uv run python (Join-Path $media "build_contact_sheet.py") `
        --media $media --output (Join-Path $media "contact_sheet.png")
    Assert-ExitCode -Expected 0 -Label "S17 contact sheet"

    $states = @(
        (Join-Path $media "state_01_focus_role.png"),
        (Join-Path $media "state_02_select_node.png"),
        (Join-Path $media "state_03_view_traverse.png"),
        (Join-Path $media "state_04_compare_handoff.png"),
        (Join-Path $media "state_05_scrub_replay.png")
    )
    $video = Join-Path $media "compositor_read_only_review.mp4"
    $filter = @(
        "[0:v]fps=30,format=yuv420p[v0]",
        "[1:v]fps=30,format=yuv420p[v1]",
        "[2:v]fps=30,format=yuv420p[v2]",
        "[3:v]fps=30,format=yuv420p[v3]",
        "[4:v]fps=30,format=yuv420p[v4]",
        "[v0][v1][v2][v3][v4]concat=n=5:v=1:a=0,format=yuv420p[v]"
    ) -join ";"
    Write-Host "[S17] assemble 18-second component-review reel"
    & $Ffmpeg -v error `
        -loop 1 -t 3 -i $states[0] `
        -loop 1 -t 3 -i $states[1] `
        -loop 1 -t 4 -i $states[2] `
        -loop 1 -t 4 -i $states[3] `
        -loop 1 -t 4 -i $states[4] `
        -filter_complex $filter -map "[v]" -an `
        -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r 30 -threads 1 `
        -metadata "title=$banner" -metadata "comment=$comment" `
        -movflags +faststart -y $video
    Assert-ExitCode -Expected 0 -Label "S17 review reel"

    $manifestRelatives = @(
        "analysis/narrative_visual/s17/state_01_focus_role.png",
        "analysis/narrative_visual/s17/state_02_select_node.png",
        "analysis/narrative_visual/s17/state_03_view_traverse.png",
        "analysis/narrative_visual/s17/state_04_compare_handoff.png",
        "analysis/narrative_visual/s17/state_05_scrub_replay.png",
        "analysis/narrative_visual/s17/contact_sheet.png",
        "analysis/narrative_visual/s17/compositor_read_only_review.mp4",
        "analysis/narrative_visual/s17/capture_receipt.json",
        "analysis/narrative_visual/s16/compositor_1024x768.png",
        "analysis/narrative_visual/s16/compositor_1280x768.png",
        "analysis/narrative_visual/s16/compositor_2688x1216.png",
        "analysis/narrative_visual/s17/.gitattributes",
        "analysis/narrative_visual/s17/build_contact_sheet.py",
        "analysis/narrative_visual/s17/render_s17_review.ps1",
        "analysis/narrative_visual/s17/test_s17_media.py",
        "analysis/narrative_visual/s17/verify_s17_media.py",
        "game/narrative_lab/s16/fixtures/s16_compositor_projection.json",
        "game/narrative_lab/s16/scripts/S16Compositor.gd",
        "game/narrative_lab/s16/scenes/s17_capture_test.tscn",
        "game/narrative_lab/s16/tests/s17_capture_test.gd"
    )
    $manifestLines = @(
        "# schema=living-town-s17-review-media-manifest/v1",
        "# source_s16_commit=$sourceCommit",
        "# fixture_sha256=$fixtureHash",
        "# banner=$banner",
        "# media_kind=component_review_not_sim_not_gameplay",
        "# video_reproducibility=fixed_inputs_and_command_ffmpeg_8.1.2_build_bound",
        "# contact_sheet_reproducibility=fixed_inputs_pillow_12.1.1_bound"
    )
    foreach ($relative in $manifestRelatives) {
        $absolute = Join-Path $root ($relative -replace "/", "\")
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            throw "Manifest source missing: $relative"
        }
        $digest = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifestLines += "$digest  $relative"
    }
    [IO.File]::WriteAllText(
        (Join-Path $media "media_manifest.sha256"),
        (($manifestLines -join "`n") + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
}

Write-Host "[S17] live source/media verification"
$verifier = Join-Path $media "verify_s17_media.py"
$gate = Join-Path $media "media_gate.json"
if ($Check) {
    & $Uv run python $verifier --root $root --ffmpeg $Ffmpeg --ffprobe $Ffprobe
}
else {
    & $Uv run python $verifier --root $root --ffmpeg $Ffmpeg --ffprobe $Ffprobe --output $gate
}
Assert-ExitCode -Expected 0 -Label "S17 source/media verifier"

Write-Host "[S17] metadata/tamper tests"
Push-Location $root
try {
    & $Uv run python -m unittest -q analysis.narrative_visual.s17.test_s17_media
    Assert-ExitCode -Expected 0 -Label "S17 media tests"
}
finally {
    Pop-Location
}

Write-Host "[S17] PASS - 18s component review; NOT SIM; READ-ONLY COMMITTED TRACE; NOT GAMEPLAY"
