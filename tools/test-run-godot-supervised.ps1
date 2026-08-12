<# Run the supervised Godot runner's success and forced-timeout controls. #>
[CmdletBinding()]
param(
  [ValidateRange(10, 300)][int]$PositiveTimeoutSec = 90,
  [ValidateRange(1, 15)][int]$NegativeTimeoutSec = 3
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$runner = Join-Path $PSScriptRoot 'run-godot-supervised.ps1'
$gamePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\game')).Path
$receiptRoot = Join-Path $env:TEMP 'living-town-godot-runs'

function Invoke-Control([int]$TimeoutSec, [string[]]$Arguments, [int]$ExpectedExit) {
  $lines = @(& $runner -TimeoutSec $TimeoutSec -GodotArgs $Arguments)
  $actualExit = $LASTEXITCODE
  $receiptLine = $lines | Where-Object { $_ -like 'SUPERVISED_GODOT_RECEIPT=*' } | Select-Object -Last 1
  if ($actualExit -ne $ExpectedExit) { throw "Expected exit $ExpectedExit, got $actualExit. Output: $($lines -join ' | ')" }
  if (-not $receiptLine) { throw "Runner did not publish a receipt path: $($lines -join ' | ')" }
  $receiptPath = $receiptLine.Substring('SUPERVISED_GODOT_RECEIPT='.Length)
  if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "Receipt is missing: $receiptPath" }
  return (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json)
}

$positive = Invoke-Control -TimeoutSec $PositiveTimeoutSec `
  -Arguments @('--headless', 'res://scenes/p1d_scale_export_test.tscn') -ExpectedExit 0
if ($positive.outcome -ne 'pass' -or -not $positive.cleanup_verified -or $positive.native_crash_pattern) {
  throw "Positive control receipt failed contract: $($positive | ConvertTo-Json -Compress)"
}

$negative = Invoke-Control -TimeoutSec $NegativeTimeoutSec -Arguments @('--headless') -ExpectedExit 124
if ($negative.outcome -ne 'timeout' -or -not $negative.timed_out -or -not $negative.cleanup_verified) {
  throw "Timeout control receipt failed contract: $($negative | ConvertTo-Json -Compress)"
}
if ($positive.run_id -eq $negative.run_id -or $positive.injected_log -eq $negative.injected_log) {
  throw 'Success and timeout controls did not receive unique run identities.'
}

# A second invocation must report a receipt and exit 78 without removing the first run's lock.
$owner = Start-Job -ScriptBlock { param($Path) & $Path -TimeoutSec 8 -GodotArgs @('--headless') } -ArgumentList $runner
try {
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  $lock = $null
  do {
    Start-Sleep -Milliseconds 150
    $lock = Get-ChildItem -LiteralPath $receiptRoot -Filter 'repo_*.lock' -ErrorAction SilentlyContinue | Select-Object -First 1
  } while (-not $lock -and $owner.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
  if (-not $lock) { throw "Owner run did not publish a checkout lock; state=$($owner.State)" }
  $blocked = Invoke-Control -TimeoutSec 3 -Arguments @('--headless') -ExpectedExit 78
  if ($blocked.outcome -ne 'preflight_blocked' -or -not $blocked.cleanup_verified) {
    throw "Concurrent run did not fail closed: $($blocked | ConvertTo-Json -Compress)"
  }
  Wait-Job -Job $owner -Timeout 20 | Out-Null
  $ownerLines = @(Receive-Job -Job $owner)
  if ($owner.State -ne 'Completed') { throw "Owner run did not finish: $($owner.State)" }
  $ownerReceiptLine = $ownerLines | Where-Object { $_ -like 'SUPERVISED_GODOT_RECEIPT=*' } | Select-Object -Last 1
  if (-not $ownerReceiptLine) { throw "Owner receipt is missing: $($ownerLines -join ' | ')" }
  $ownerReceipt = Get-Content -LiteralPath $ownerReceiptLine.Substring('SUPERVISED_GODOT_RECEIPT='.Length) -Raw | ConvertFrom-Json
  if ($ownerReceipt.outcome -ne 'timeout' -or -not $ownerReceipt.cleanup_verified) {
    throw "Owner timeout did not clean up: $($ownerReceipt | ConvertTo-Json -Compress)"
  }
}
finally {
  if ($owner.State -eq 'Running') { Stop-Job -Job $owner }
  Remove-Job -Job $owner -Force -ErrorAction SilentlyContinue
}

$scoped = @(Get-CimInstance Win32_Process | Where-Object {
  $_.Name -like 'Godot*' -and $_.CommandLine -and $_.CommandLine.IndexOf($gamePath, [StringComparison]::OrdinalIgnoreCase) -ge 0
})
if ($scoped.Count -ne 0) { throw "Godot processes survived controls: $($scoped.ProcessId -join ',')" }

Write-Output 'SUPERVISED_GODOT_TEST=PASS'
Write-Output "POSITIVE_RUN=$($positive.run_id)"
Write-Output "TIMEOUT_RUN=$($negative.run_id)"
Write-Output "BLOCKED_RUN=$($blocked.run_id)"
