[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$ReceiptRoot
)
$ErrorActionPreference='Stop'
$townRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not [IO.Path]::IsPathRooted($Godot) -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'An installed absolute Godot executable is required.' }
if (-not [IO.Path]::IsPathRooted($Output) -or (Test-Path -LiteralPath $Output)) { throw 'Choose a fresh absolute output directory; prior attempts are preserved.' }
if (-not $ReceiptRoot) { $ReceiptRoot=$Output+'.receipts' }
if (-not [IO.Path]::IsPathRooted($ReceiptRoot)) { throw 'ReceiptRoot must be absolute.' }
$townArguments=@('--windowed','--resolution','320x240','--single-threaded-scene','--script',
    (Join-Path $townRepo 'tools/town_upgrade/build_static_render_cache.gd'),'--','--cache-output',$Output)
& (Join-Path $townRepo 'tools/run-godot-supervised.ps1') -Godot $Godot -AllowDirtyCandidate -ReceiptRoot $ReceiptRoot -TimeoutSec 1200 -GodotArgs $townArguments
if ($LASTEXITCODE -ne 0) { throw 'Static-cache production failed; preserve the supervisor receipts.' }
$townReport=Get-Content -LiteralPath (Join-Path $Output 'cache_build_report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($townReport.status -cne 'PASS_ACTUAL_FULL_BUILDER_RESOURCE_READBACK') { throw 'Full builder and independent saved-resource readback must pass.' }
Write-Output "STATIC_CACHE_REPORT=$Output/cache_build_report.json"
