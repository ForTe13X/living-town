<# Captures actual Godot viewport frames and makes a full MP4 plus a 3x GIF.
   Requires Godot 4.6.2 and ffmpeg on PATH. Raw frames remain in a unique temp dir.
   -Frames can reuse a completed capture containing chapters.json (zero failures).
#>
[CmdletBinding()]
param([string]$Godot = '', [string]$Frames = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $Frames) {
  $Frames = Join-Path $env:TEMP ('living-town-tour-' + [guid]::NewGuid().ToString('N'))
  & "$PSScriptRoot/run-godot-supervised.ps1" -Godot $Godot -AllowDirtyCandidate -TimeoutSec 600 -GodotArgs @(
    '--resolution','1280x768','res://scenes/gameplay_tour.tscn','--','--life','--tour-out',$Frames
  )
  if ($LASTEXITCODE -ne 0) { throw 'Supervised capture failed; media was not published.' }
}
$manifest = Get-Content -LiteralPath (Join-Path $Frames 'chapters.json') -Raw | ConvertFrom-Json
if ($manifest.failures -ne 0 -or $manifest.frames -lt 1) { throw 'Incomplete or failed capture.' }
$media = Join-Path $root 'docs/media'
$inputPattern = Join-Path $Frames 'frame_%05d.png'
& ffmpeg -hide_banner -loglevel error -y -framerate $manifest.fps -i $inputPattern -frames:v $manifest.frames -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p -movflags +faststart (Join-Path $media 'gameplay-tour.mp4')
if ($LASTEXITCODE -ne 0) { throw 'MP4 encoding failed.' }
& ffmpeg -hide_banner -loglevel error -y -i (Join-Path $media 'gameplay-tour.mp4') -filter_complex '[0:v]setpts=PTS/3,fps=6,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' -loop 0 (Join-Path $media 'gameplay-tour.gif')
if ($LASTEXITCODE -ne 0) { throw 'GIF encoding failed.' }
Copy-Item -LiteralPath (Join-Path $Frames 'chapters.json') -Destination (Join-Path $media 'gameplay-tour.chapters.json')
Write-Output "Published media to $media; raw frames: $Frames"
