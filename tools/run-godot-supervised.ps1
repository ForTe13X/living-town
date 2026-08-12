<#
.SYNOPSIS
  Run one local Living Town Godot command with fail-closed source identity and process-tree cleanup.

.DESCRIPTION
  This is the canonical Windows lane for local Godot evidence. It pins the Git/product
  identity, gives every run unique stdout/stderr/Godot logs, rejects concurrent runs for
  this checkout, enforces a timeout, and removes only processes carrying the unique run
  log path. Clean trees produce exact-commit evidence. Dirty trees fail closed unless
  -AllowDirtyCandidate is explicit; candidate receipts bind the full worktree fingerprint.

.EXAMPLE
  & .\tools\run-godot-supervised.ps1 -TimeoutSec 180 -GodotArgs @(
    '--headless', 'res://scenes/p1d_scale_export_test.tscn'
  )
#>
[CmdletBinding()]
param(
  [string]$Godot = '',
  [ValidateRange(1, 86400)][int]$TimeoutSec = 300,
  [string]$ReceiptRoot = '',
  [switch]$AllowDirtyCandidate,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$GodotArgs = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-Sha256Text([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  }
  finally { $sha.Dispose() }
}

function Quote-WindowsArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Resolve-GodotExecutable([string]$Requested) {
  $candidate = $Requested
  if ([string]::IsNullOrWhiteSpace($candidate)) {
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT)) { $candidate = $env:GODOT }
    else {
      $onPath = Get-Command godot -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($onPath) { $candidate = $onPath.Source }
      else { $candidate = 'C:\Users\yp\.local\bin\godot.cmd' }
    }
  }
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { $resolved = (Resolve-Path -LiteralPath $candidate).Path }
  else {
    $command = Get-Command $candidate -ErrorAction Stop | Select-Object -First 1
    $resolved = $command.Source
  }
  if ([IO.Path]::GetExtension($resolved).ToLowerInvariant() -eq '.cmd') {
    $line = Get-Content -LiteralPath $resolved | Where-Object { $_ -match '(?i)godot[^"\r\n]*_console\.exe' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '"([^"]+\.exe)"') {
      throw "Could not resolve a Godot console executable from launcher: $resolved"
    }
    $resolved = (Resolve-Path -LiteralPath $Matches[1]).Path
  }
  if ([IO.Path]::GetExtension($resolved).ToLowerInvariant() -ne '.exe') {
    throw "Supervised Windows runs require a concrete Godot .exe, got: $resolved"
  }
  return $resolved
}

function Get-ScopedProcesses([string]$ScopeToken, [int]$RootPid = 0) {
  $all = @(Get-CimInstance Win32_Process)
  $ids = New-Object 'System.Collections.Generic.HashSet[int]'
  if ($RootPid -gt 0) {
    $root = $all | Where-Object {
      [int]$_.ProcessId -eq $RootPid -and $_.CommandLine -and
      $_.CommandLine.IndexOf($ScopeToken, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } | Select-Object -First 1
    if ($root) { [void]$ids.Add($RootPid) }
  }
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($proc in $all) {
      if ($ids.Contains([int]$proc.ParentProcessId) -and -not $ids.Contains([int]$proc.ProcessId)) {
        [void]$ids.Add([int]$proc.ProcessId)
        $changed = $true
      }
    }
  }
  foreach ($proc in $all) {
    if ($proc.CommandLine -and $proc.CommandLine.IndexOf($ScopeToken, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      [void]$ids.Add([int]$proc.ProcessId)
    }
  }
  return @($all | Where-Object { $ids.Contains([int]$_.ProcessId) })
}

function Stop-ScopedProcessTree([string]$ScopeToken, [int]$RootPid = 0) {
  for ($attempt = 0; $attempt -lt 4; $attempt++) {
    $scoped = @(Get-ScopedProcesses -ScopeToken $ScopeToken -RootPid $RootPid)
    if ($scoped.Count -eq 0) { return @() }
    $byPid = @{}
    foreach ($proc in $scoped) { $byPid[[int]$proc.ProcessId] = $proc }
    $leaves = @($scoped | Where-Object {
      $parentId = [int]$_.ProcessId
      -not ($scoped | Where-Object { [int]$_.ParentProcessId -eq $parentId })
    })
    if ($leaves.Count -eq 0) { $leaves = $scoped }
    foreach ($proc in $leaves) {
      try { Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop }
      catch [Microsoft.PowerShell.Commands.ProcessCommandException] { }
    }
    Start-Sleep -Milliseconds 250
  }
  return @(Get-ScopedProcesses -ScopeToken $ScopeToken -RootPid $RootPid)
}

function Get-FileEvidence([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $item = Get-Item -LiteralPath $Path
  return [ordered]@{
    path = $item.FullName
    bytes = [int64]$item.Length
    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Invoke-GitCapture([string]$RepoRoot, [string[]]$GitArgs) {
  $output = @(& git -C $RepoRoot @GitArgs 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw "git $($GitArgs -join ' ') failed with exit $LASTEXITCODE"
  }
  return $output
}

function Get-WorktreeEvidence([string]$RepoRoot) {
  $status = @(Invoke-GitCapture $RepoRoot @('-c', 'core.quotePath=false', 'status', '--porcelain=v1', '--untracked-files=all'))
  $trackedDiff = (@(Invoke-GitCapture $RepoRoot @('-c', 'core.autocrlf=false', 'diff', '--binary', 'HEAD', '--')) -join "`n")
  $untracked = @(Invoke-GitCapture $RepoRoot @('-c', 'core.quotePath=false', 'ls-files', '--others', '--exclude-standard'))
  $untrackedHashes = [ordered]@{}
  foreach ($relativePath in $untracked) {
    $blob = (Invoke-GitCapture $RepoRoot @('hash-object', '--no-filters', '--', $relativePath) | Select-Object -First 1)
    $untrackedHashes[[string]$relativePath] = [string]$blob
  }
  $payload = [ordered]@{
    status = @($status)
    tracked_diff_sha256 = Get-Sha256Text $trackedDiff
    untracked_blob_sha1 = $untrackedHashes
  }
  return [ordered]@{
    status = @($status)
    fingerprint_sha256 = Get-Sha256Text ($payload | ConvertTo-Json -Depth 6 -Compress)
    tracked_diff_sha256 = $payload.tracked_diff_sha256
    untracked_blob_sha1 = $untrackedHashes
  }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$gamePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'game')).Path
$godotExe = Resolve-GodotExecutable $Godot
if ([string]::IsNullOrWhiteSpace($ReceiptRoot)) {
  $ReceiptRoot = Join-Path $env:TEMP 'living-town-godot-runs'
}
$receiptRootFull = [IO.Path]::GetFullPath($ReceiptRoot)
[IO.Directory]::CreateDirectory($receiptRootFull) | Out-Null

foreach ($forbidden in @('--path', '--log-file')) {
  if ($GodotArgs -contains $forbidden) {
    throw "Do not pass $forbidden; the supervisor injects an absolute project path and a unique log."
  }
}

$runId = '{0}_{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')), ([Guid]::NewGuid().ToString('N'))
$runDir = Join-Path $receiptRootFull $runId
[IO.Directory]::CreateDirectory($runDir) | Out-Null
$godotLog = Join-Path $runDir 'godot.log'
$stdoutLog = Join-Path $runDir 'stdout.log'
$stderrLog = Join-Path $runDir 'stderr.log'
$receiptPath = Join-Path $runDir 'receipt.json'
$scopeToken = $godotLog
$repoKey = (Get-Sha256Text $repoRoot).Substring(0, 20)
$lockPath = Join-Path $receiptRootFull ("repo_{0}.lock" -f $repoKey)
$lockStream = $null
$lockOwned = $false
$process = $null
$processId = 0
$processStarted = $false
$startedUtc = [DateTime]::UtcNow
$finishedUtc = $null
$timedOut = $false
$nativeCrash = $false
$cleanupVerified = $false
$exitCode = $null
$outcome = 'runner_error'
$errorText = ''
$preflight = @()

$gitHead = (Invoke-GitCapture $repoRoot @('rev-parse', 'HEAD') | Select-Object -First 1)
$gameTree = (Invoke-GitCapture $repoRoot @('rev-parse', 'HEAD:game') | Select-Object -First 1)
$branch = (Invoke-GitCapture $repoRoot @('branch', '--show-current') | Select-Object -First 1)
$worktreeBefore = Get-WorktreeEvidence $repoRoot
$statusBefore = @($worktreeBefore.status)
$sourceIdentity = if ($statusBefore.Count -eq 0) { 'exact_commit' } elseif ($AllowDirtyCandidate) { 'dirty_candidate' } else { 'rejected_dirty' }
$sourceStable = $false

try {
  if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
    $staleProbe = $null
    try { $staleProbe = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch [IO.IOException] {
      $outcome = 'preflight_blocked'
      $exitCode = 78
      throw "Another supervised run owns this checkout (active lock $lockPath)."
    }
    if ($staleProbe) { $staleProbe.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force
  }
  $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  $lockOwned = $true
  $lockWriter = New-Object IO.StreamWriter($lockStream, (New-Object Text.UTF8Encoding($false)), 1024, $true)
  $lockWriter.Write(([ordered]@{ pid = $PID; run_id = $runId; repo = $repoRoot; started_utc = $startedUtc.ToString('o') } | ConvertTo-Json -Compress))
  $lockWriter.Flush()
  $lockWriter.Dispose()

  $preflight = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like 'Godot*' -and $_.CommandLine -and (
      $_.CommandLine.IndexOf($gamePath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
      $_.CommandLine -match '(?i)(^|\s)--path\s+"?game"?(\s|$)'
    )
  } | Select-Object ProcessId, ParentProcessId, Name, CreationDate, CommandLine)
  if ($preflight.Count -gt 0) {
    $outcome = 'preflight_blocked'
    $exitCode = 78
    throw "Found an existing Godot process scoped to $gamePath (PIDs $($preflight.ProcessId -join ','))."
  }
  if ($statusBefore.Count -gt 0 -and -not $AllowDirtyCandidate) {
    $outcome = 'preflight_blocked'
    $exitCode = 78
    throw "Working tree is dirty; exact evidence requires a clean commit. Use -AllowDirtyCandidate only for explicit candidate runs."
  }

  $allArgs = @('--path', $gamePath, '--log-file', $godotLog) + @($GodotArgs)
  $argumentLine = (($allArgs | ForEach-Object { Quote-WindowsArgument ([string]$_) }) -join ' ')
  $process = Start-Process -FilePath $godotExe -ArgumentList $argumentLine -WorkingDirectory $repoRoot `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -WindowStyle Hidden -PassThru
  $processId = [int]$process.Id
  $processStarted = $true
  if (-not $process.WaitForExit($TimeoutSec * 1000)) {
    $timedOut = $true
    $outcome = 'timeout'
    $exitCode = 124
  }
  else {
    $process.Refresh()
    $exitCode = [int]$process.ExitCode
    $outcome = if ($exitCode -eq 0) { 'pass' } else { 'godot_failed' }
  }
}
catch {
  $errorText = $_.Exception.Message
  if ($null -eq $exitCode) { $exitCode = 70 }
}
finally {
  $survivors = @(Stop-ScopedProcessTree -ScopeToken $scopeToken -RootPid $processId)
  $cleanupVerified = ($survivors.Count -eq 0)
  if (-not $cleanupVerified) {
    $outcome = 'cleanup_failed'
    $exitCode = 71
    $errorText = "Scoped processes survived cleanup: $($survivors.ProcessId -join ',')"
  }
  $finishedUtc = [DateTime]::UtcNow
  $gitHeadAfter = (Invoke-GitCapture $repoRoot @('rev-parse', 'HEAD') | Select-Object -First 1)
  $gameTreeAfter = (Invoke-GitCapture $repoRoot @('rev-parse', 'HEAD:game') | Select-Object -First 1)
  $branchAfter = (Invoke-GitCapture $repoRoot @('branch', '--show-current') | Select-Object -First 1)
  $worktreeAfter = Get-WorktreeEvidence $repoRoot
  $sourceStable = [string]$gitHead -eq [string]$gitHeadAfter -and [string]$gameTree -eq [string]$gameTreeAfter `
    -and [string]$branch -eq [string]$branchAfter `
    -and [string]$worktreeBefore.fingerprint_sha256 -eq [string]$worktreeAfter.fingerprint_sha256
  $combined = ''
  foreach ($path in @($godotLog, $stdoutLog, $stderrLog)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { $combined += "`n" + (Get-Content -LiteralPath $path -Raw) }
  }
  $nativeCrash = [bool]($combined -match '(?i)signal\s*11|sigsegv|segmentation fault|fatal error|out of bounds|access violation|script error|crash')
  if ($nativeCrash -and $exitCode -eq 0) {
    $outcome = 'native_crash_pattern'
    $exitCode = 70
  }
  if ($processStarted -and -not $sourceStable -and $cleanupVerified -and -not $nativeCrash) {
    $outcome = 'source_drift'
    $exitCode = 79
    $errorText = 'Git HEAD, branch, committed game tree, or worktree fingerprint differs between launch and completion.'
  }
  if ($lockStream) { $lockStream.Dispose() }
  if ($lockOwned -and (Test-Path -LiteralPath $lockPath -PathType Leaf)) { Remove-Item -LiteralPath $lockPath -Force }

  $receipt = [ordered]@{
    contract = 'living-town-supervised-godot-v2'
    run_id = $runId
    outcome = $outcome
    exit_code = $exitCode
    timed_out = $timedOut
    native_crash_pattern = $nativeCrash
    cleanup_verified = $cleanupVerified
    started_utc = $startedUtc.ToString('o')
    finished_utc = $finishedUtc.ToString('o')
    duration_ms = [int64]($finishedUtc - $startedUtc).TotalMilliseconds
    supervisor_pid = $PID
    godot_root_pid = $processId
    repo = $repoRoot
    branch = [string]$branch
    source_head = [string]$gitHead
    source_head_after = [string]$gitHeadAfter
    game_tree = [string]$gameTree
    game_tree_after = [string]$gameTreeAfter
    source_identity = $sourceIdentity
    source_stable = $sourceStable
    dirty_candidate_opt_in = [bool]$AllowDirtyCandidate
    status_before = @($statusBefore)
    status_after = @($worktreeAfter.status)
    worktree_fingerprint_before = [string]$worktreeBefore.fingerprint_sha256
    worktree_fingerprint_after = [string]$worktreeAfter.fingerprint_sha256
    tracked_diff_sha256_before = [string]$worktreeBefore.tracked_diff_sha256
    tracked_diff_sha256_after = [string]$worktreeAfter.tracked_diff_sha256
    untracked_blob_sha1_before = $worktreeBefore.untracked_blob_sha1
    untracked_blob_sha1_after = $worktreeAfter.untracked_blob_sha1
    godot_executable = $godotExe
    project_path = $gamePath
    arguments = @($GodotArgs)
    injected_log = $godotLog
    timeout_seconds = $TimeoutSec
    preflight_processes = @($preflight)
    error = $errorText
    files = [ordered]@{
      godot = Get-FileEvidence $godotLog
      stdout = Get-FileEvidence $stdoutLog
      stderr = Get-FileEvidence $stderrLog
    }
  }
  $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}

Write-Output "SUPERVISED_GODOT_RECEIPT=$receiptPath"
Write-Output "SUPERVISED_GODOT_OUTCOME=$outcome"
exit ([int]$exitCode)
