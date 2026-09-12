<# Verify that the supervised runner never labels dirty code as exact commit evidence. #>
[CmdletBinding()]
param([ValidateRange(10, 180)][int]$TimeoutSec = 90)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $PSScriptRoot 'run-godot-supervised.ps1'
$probe = Join-Path $repoRoot ('.p1k-supervised-dirty-{0}.probe' -f [Guid]::NewGuid().ToString('N'))

try {
  [IO.File]::WriteAllText($probe, 'dirty-provenance-negative-control', (New-Object Text.UTF8Encoding($false)))
  $lines = @(& $runner -TimeoutSec $TimeoutSec -GodotArgs @('--headless', 'res://scenes/p1d_scale_export_test.tscn'))
  $actualExit = $LASTEXITCODE
  if ($actualExit -ne 78) {
    throw "Dirty default run must fail closed with exit 78, got $actualExit. Output: $($lines -join ' | ')"
  }
  $receiptLine = $lines | Where-Object { $_ -like 'SUPERVISED_GODOT_RECEIPT=*' } | Select-Object -Last 1
  $rejected = Get-Content -LiteralPath $receiptLine.Substring('SUPERVISED_GODOT_RECEIPT='.Length) -Raw | ConvertFrom-Json
  if ($rejected.source_identity -ne 'rejected_dirty' -or $rejected.outcome -ne 'preflight_blocked') {
    throw "Dirty rejection receipt is mislabeled: $($rejected | ConvertTo-Json -Compress)"
  }

  $candidateLines = @(& $runner -AllowDirtyCandidate -TimeoutSec $TimeoutSec `
    -GodotArgs @('--headless', 'res://scenes/p1d_scale_export_test.tscn'))
  if ($LASTEXITCODE -ne 0) { throw "Explicit dirty candidate failed: $($candidateLines -join ' | ')" }
  $candidateLine = $candidateLines | Where-Object { $_ -like 'SUPERVISED_GODOT_RECEIPT=*' } | Select-Object -Last 1
  $candidate = Get-Content -LiteralPath $candidateLine.Substring('SUPERVISED_GODOT_RECEIPT='.Length) -Raw | ConvertFrom-Json
  if ($candidate.source_identity -ne 'dirty_candidate' -or -not $candidate.source_stable `
    -or $candidate.worktree_fingerprint_before -ne $candidate.worktree_fingerprint_after) {
    throw "Dirty candidate receipt lacks stable fingerprint identity: $($candidate | ConvertTo-Json -Compress)"
  }

  $owner = Start-Job -ScriptBlock {
    param($Path)
    $output = @(& $Path -AllowDirtyCandidate -TimeoutSec 30 -GodotArgs @(
      '--headless', '--script', 'res://bench/Harness.gd', '--',
      '--seeds', '1', '--days', '60', '--det', '0'
    ))
    [pscustomobject]@{ output = $output; exit_code = $LASTEXITCODE }
  } -ArgumentList $runner
  try {
    $receiptRoot = Join-Path $env:TEMP 'living-town-godot-runs'
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
      Start-Sleep -Milliseconds 100
      $lock = Get-ChildItem -LiteralPath $receiptRoot -Filter 'repo_*.lock' -ErrorAction SilentlyContinue | Select-Object -First 1
    } while (-not $lock -and $owner.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
    if (-not $lock) {
      $ownerFailure = @(Receive-Job -Job $owner -Keep -ErrorAction SilentlyContinue)
      throw "Source-drift control did not acquire the checkout lock; state=$($owner.State) output=$($ownerFailure | ConvertTo-Json -Compress)"
    }
    [IO.File]::AppendAllText($probe, '-mutated-during-run', (New-Object Text.UTF8Encoding($false)))
    Wait-Job -Job $owner -Timeout 20 | Out-Null
    $driftResult = Receive-Job -Job $owner
    if ($owner.State -ne 'Completed' -or $driftResult.exit_code -ne 79) {
      throw "Source drift must override the Godot outcome with exit 79: state=$($owner.State) result=$($driftResult | ConvertTo-Json -Compress)"
    }
    $driftLine = $driftResult.output | Where-Object { $_ -like 'SUPERVISED_GODOT_RECEIPT=*' } | Select-Object -Last 1
    $drift = Get-Content -LiteralPath $driftLine.Substring('SUPERVISED_GODOT_RECEIPT='.Length) -Raw | ConvertFrom-Json
    if ($drift.outcome -ne 'source_drift' -or $drift.source_stable `
      -or $drift.worktree_fingerprint_before -eq $drift.worktree_fingerprint_after) {
      throw "Source drift receipt failed contract: $($drift | ConvertTo-Json -Compress)"
    }
  }
  finally {
    if ($owner -and $owner.State -eq 'Running') { Stop-Job -Job $owner }
    if ($owner) { Remove-Job -Job $owner -Force -ErrorAction SilentlyContinue }
  }
}
finally {
  if (Test-Path -LiteralPath $probe -PathType Leaf) { Remove-Item -LiteralPath $probe -Force }
}

Write-Output 'SUPERVISED_GODOT_PROVENANCE_TEST=PASS'
exit 0
