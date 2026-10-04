<#
.SYNOPSIS
  Start an interactive rendered Godot capture in an isolated copy of a pinned game tree.

.DESCRIPTION
  The first `session` leg prepares a new copy and unique user:// profile. Run this
  script in one terminal, then use send-command.ps1 in another. A later `resume`
  leg reuses only that copy/profile, so F8 exercises a fresh Godot process.
#>
[CmdletBinding()]
param(
  [ValidateSet('session', 'resume')][string]$Leg = 'session',
  [string]$CaptureRoot = '',
  [string]$SourceCommit = 'HEAD',
  [string]$Godot = '',
  [ValidateRange(10, 900)][int]$IdleTimeoutSec = 900,
  [ValidateRange(30, 3600)][int]$RunTimeoutSec = 1800,
  [switch]$AllowCrlfNormalization
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$scriptDir = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
$python = Get-Command python -ErrorAction Stop | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($CaptureRoot)) {
  if ($Leg -eq 'resume') { throw 'Resume requires -CaptureRoot from the session leg.' }
  $CaptureRoot = Join-Path $env:TEMP ('living-town-capture-' + [guid]::NewGuid().ToString('N'))
}
$captureRootFull = [IO.Path]::GetFullPath($CaptureRoot)
$sourceCopy = Join-Path $scriptDir 'source_copy.py'

if ($Leg -eq 'session') {
  $prepareArgs = @('-X', 'utf8', $sourceCopy, 'prepare', '--repo', $repoRoot,
    '--capture-root', $captureRootFull, '--source-commit', $SourceCommit)
  if ($AllowCrlfNormalization) { $prepareArgs += '--allow-crlf-normalization' }
  & $python.Source @prepareArgs
  if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the pinned capture copy.' }
} elseif (-not (Test-Path -LiteralPath (Join-Path $captureRootFull 'source-manifest.json') -PathType Leaf)) {
  throw "Capture manifest is missing: $captureRootFull"
}

$manifest = Get-Content -LiteralPath (Join-Path $captureRootFull 'source-manifest.json') -Raw | ConvertFrom-Json
$gamePath = Join-Path $captureRootFull 'game'
& $python.Source -X utf8 $sourceCopy verify --capture-root $captureRootFull --phase ($Leg + '-before')
if ($LASTEXITCODE -ne 0) { throw 'Capture copy failed the before-run Git blob proof.' }

$legDir = Join-Path $captureRootFull $Leg
if (Test-Path -LiteralPath $legDir) { throw "Capture leg already exists: $legDir" }

function Get-SavePathFromObservation([string]$ObservationPath, [string]$ExpectedName) {
  $observation = Get-Content -LiteralPath $ObservationPath -Raw | ConvertFrom-Json
  $userDataDir = [string]$observation.user_data_dir
  $actualName = (($userDataDir -replace '\\', '/').TrimEnd('/').Split('/') | Select-Object -Last 1)
  if ($actualName -ne $ExpectedName) { throw "Capture user:// profile mismatch: $userDataDir" }
  return Join-Path $userDataDir 'quicksave.dat'
}

function Write-SaveProof([string]$SavePath, [string]$CopyPath, [string]$ProofPath) {
  $exists = Test-Path -LiteralPath $SavePath -PathType Leaf
  $hash = ''
  $bytes = 0
  if ($exists) {
    Copy-Item -LiteralPath $SavePath -Destination $CopyPath
    $hash = (Get-FileHash -LiteralPath $CopyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $bytes = (Get-Item -LiteralPath $CopyPath).Length
  }
  [ordered]@{
    schema = 'living-town.capture-save-proof/1'
    exists = $exists
    sha256 = $hash
    bytes = $bytes
    copy = if ($exists) { Split-Path $CopyPath -Leaf } else { '' }
  } | ConvertTo-Json -Depth 3 | ForEach-Object {
    [IO.File]::WriteAllText($ProofPath, $_ + "`n", (New-Object Text.UTF8Encoding($false)))
  }
  return $hash
}

if ($Leg -eq 'resume') {
  $sessionDir = Join-Path $captureRootFull 'session'
  $terminalPath = Join-Path $sessionDir 'terminal.json'
  $savedProofPath = Join-Path $sessionDir 'save-after.json'
  if (-not (Test-Path -LiteralPath $terminalPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $savedProofPath -PathType Leaf)) {
    throw 'The session leg has no terminal and saved quicksave proof.'
  }
  $terminal = Get-Content -LiteralPath $terminalPath -Raw | ConvertFrom-Json
  $savedProof = Get-Content -LiteralPath $savedProofPath -Raw | ConvertFrom-Json
  if ($terminal.status -ne 'quit' -or -not $savedProof.exists) {
    throw 'The session leg did not finish with a quicksave.'
  }
  $lastSessionObservation = Get-ChildItem -LiteralPath (Join-Path $sessionDir 'observations') -Filter '*.json' |
    Sort-Object Name | Select-Object -Last 1
  if ($null -eq $lastSessionObservation) { throw 'No final session observation.' }
  $savePath = Get-SavePathFromObservation $lastSessionObservation.FullName ([string]$manifest.user_dir_name)
  if (-not (Test-Path -LiteralPath $savePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $savedProof.sha256) {
    throw 'The isolated quicksave changed before the fresh-process resume leg.'
  }
  [IO.Directory]::CreateDirectory($legDir) | Out-Null
  [void](Write-SaveProof $savePath (Join-Path $legDir 'quicksave-before.dat') (Join-Path $legDir 'save-before.json'))
} else {
  [IO.Directory]::CreateDirectory($legDir) | Out-Null
}

$godotArgs = @(
  '--resolution', '1280x768',
  '--script', (Join-Path $scriptDir 'live_bridge.gd'),
  '--', '--life', '--backend', 'logic', '--agents', '12', '--speed', '1',
  '--bridge-dir', $legDir,
  '--expected-user-dir-name', [string]$manifest.user_dir_name,
  '--idle-timeout-sec', [string]$IdleTimeoutSec
)
Write-Output "CAPTURE_ROOT=$captureRootFull"
Write-Output "CAPTURE_LEG=$Leg"
Write-Output "CAPTURE_COMMAND_DIR=$(Join-Path $legDir 'commands')"
& (Join-Path $repoRoot 'tools\run-godot-supervised.ps1') -Godot $Godot `
  -ProjectPath $gamePath -ReceiptRoot (Join-Path $legDir 'supervisor') `
  -TimeoutSec $RunTimeoutSec -GodotArgs $godotArgs
$runCode = $LASTEXITCODE

$lastObservation = Get-ChildItem -LiteralPath (Join-Path $legDir 'observations') -Filter '*.json' -ErrorAction SilentlyContinue |
  Sort-Object Name | Select-Object -Last 1
if ($null -ne $lastObservation) {
  $savePath = Get-SavePathFromObservation $lastObservation.FullName ([string]$manifest.user_dir_name)
  [void](Write-SaveProof $savePath (Join-Path $legDir 'quicksave-after.dat') (Join-Path $legDir 'save-after.json'))
}
& $python.Source -X utf8 $sourceCopy verify --capture-root $captureRootFull --phase ($Leg + '-after')
if ($LASTEXITCODE -ne 0) { $runCode = 79 }
Write-Output "CAPTURE_EXIT=$runCode"
exit $runCode
