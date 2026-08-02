param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")),
    [string]$Godot = "godot",
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe",
    [string]$Uv = "uv"
)

$ErrorActionPreference = "Stop"
$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$gameRoot = Join-Path $resolvedRoot "game"
$mediaDir = Join-Path $resolvedRoot "analysis\narrative_visual\s13"
$scene = "res://scenes/narrative/s13_visual_test.tscn"
$separator = [char]0x00B7
$watermark = "SYNTHETIC COMPONENT REVIEW $separator NOT GAMEPLAY"

function Assert-ExitCode {
    param(
        [int]$Expected,
        [string]$Label
    )
    if ($LASTEXITCODE -ne $Expected) {
        throw "$Label exited $LASTEXITCODE; expected $Expected"
    }
}

Write-Host "[S13R] headless structure/privacy gate"
& $Godot --headless --path $gameRoot $scene -- --logic-only --no-output
Assert-ExitCode -Expected 0 -Label "Godot headless gate"

Write-Host "[S13R] real framebuffer render"
& $Godot --path $gameRoot $scene -- --out $mediaDir
Assert-ExitCode -Expected 0 -Label "Godot framebuffer gate"

Write-Host "[S13R] real framebuffer negative control"
& $Godot --path $gameRoot $scene -- --negative-control --no-output
Assert-ExitCode -Expected 7 -Label "Godot negative control"

$rolePair = Join-Path $mediaDir "role_pair.png"
$maze = Join-Path $mediaDir "maze.png"
$glyphSheet = Join-Path $mediaDir "glyph_sheet.png"
$reel = Join-Path $mediaDir "component_reel.mp4"
$filter = @(
    "[0:v]scale=1280:768:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1280:768:(ow-iw)/2:(oh-ih)/2:color=0x11131a,setsar=1,fps=30[v0]",
    "[1:v]scale=1280:768:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1280:768:(ow-iw)/2:(oh-ih)/2:color=0x11131a,setsar=1,fps=30[v1]",
    "[2:v]scale=1280:768:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1280:768:(ow-iw)/2:(oh-ih)/2:color=0x11131a,setsar=1,fps=30[v2]",
    "[v0][v1][v2]concat=n=3:v=1:a=0,format=yuv420p[v]"
) -join ";"
$title = $watermark
$comment = "STATIC REVIEW REEL $separator NOT GAMEPLAY $separator three five-second holds from watermarked S13 component PNGs"

Write-Host "[S13R] assemble 15-second static component review reel"
& $Ffmpeg -v error `
    -loop 1 -t 5 -i $rolePair `
    -loop 1 -t 5 -i $maze `
    -loop 1 -t 5 -i $glyphSheet `
    -filter_complex $filter `
    -map "[v]" -an -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r 30 `
    -metadata "title=$title" -metadata "comment=$comment" -movflags +faststart -y $reel
Assert-ExitCode -Expected 0 -Label "ffmpeg review reel"

$sourceCommit = (& git -C $resolvedRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $sourceCommit.Length -ne 40) {
    throw "Could not resolve the main source commit"
}
$sourceReceipt = "source.receipt.s13r.review_media.$($sourceCommit.Substring(0, 12))"
$manifestRelatives = @(
    "analysis/narrative_visual/s13/role_pair.png",
    "analysis/narrative_visual/s13/maze.png",
    "analysis/narrative_visual/s13/glyph_sheet.png",
    "analysis/narrative_visual/s13/component_reel.mp4",
    "analysis/narrative_visual/s13/metrics.json",
    "game/scripts/narrative/WebMazeGraph.gd",
    "game/scripts/narrative/RolePOVCard.gd",
    "game/scripts/narrative/NarrativeGlyphs.gd",
    "game/scripts/narrative/tests/s13_visual_test.gd",
    "game/scenes/narrative/s13_visual_test.tscn",
    "analysis/narrative_visual/s13/render_review_media.ps1",
    "analysis/narrative_visual/s13/verify_review_media.py",
    "analysis/narrative_visual/s13/test_review_media.py",
    "analysis/narrative_visual/s13/report.md"
)
$manifestLines = @(
    "# schema=s13r-review-media-manifest/v1",
    "# main_source_commit=$sourceCommit",
    "# source_receipt_id=$sourceReceipt",
    "# watermark_text=$watermark",
    "# media_kind=static_component_review_not_gameplay"
)
foreach ($relative in $manifestRelatives) {
    $absolute = Join-Path $resolvedRoot ($relative -replace "/", "\")
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        throw "Manifest source missing: $relative"
    }
    $digest = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestLines += "$digest  $relative"
}
$manifestPath = Join-Path $mediaDir "media_manifest.sha256"
[System.IO.File]::WriteAllLines(
    $manifestPath,
    $manifestLines,
    [System.Text.UTF8Encoding]::new($false)
)

$verifier = Join-Path $mediaDir "verify_review_media.py"
$gate = Join-Path $mediaDir "media_gate.json"
Write-Host "[S13R] live media/source gate"
& $Uv run python $verifier --root $resolvedRoot --ffmpeg $Ffmpeg --ffprobe $Ffprobe --out $gate
Assert-ExitCode -Expected 0 -Label "S13R media gate"

Write-Host "[S13R] mutation and exact-artifact tests"
& $Uv run python -m unittest -q analysis.narrative_visual.s13.test_review_media
Assert-ExitCode -Expected 0 -Label "S13R media tests"

Write-Host "[S13R] PASS $sourceReceipt"
