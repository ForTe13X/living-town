<#
.SYNOPSIS
  Run one local Living Town Godot command with fail-closed source identity and process-tree cleanup.

.DESCRIPTION
  This is the canonical Windows lane for local Godot evidence. It pins the Git/product
  identity, gives every run unique stdout/stderr/Godot logs, rejects concurrent runs for
  this checkout, enforces a timeout, and removes only processes carrying the unique run
  log path. Clean trees produce exact-commit evidence. Dirty trees fail closed unless
  -AllowDirtyCandidate is explicit; candidate receipts bind the full worktree fingerprint.
  Standard `*_test: FAIL` / `... GATE: FAIL` verdicts also fail closed because Windows
  Godot can return process exit 0 after `get_tree().quit(1)`.
  -ProjectPath can supervise an isolated project copy. Such receipts are labeled
  external_project_copy; callers must independently prove the copy's source blobs.

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
  [string]$ProjectPath = '',
  [switch]$AllowDirtyCandidate,
  [string]$CapturePath = '',
  [string]$CaptureReportPath = '',
  [ValidateRange(0, 15120)][int]$CaptureExpectedFrames = 0,
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

function Test-GodotLogicFailure([string]$Log) {
  # Preserve the existing verdict gate, including zero-exit Godot failures.
  if ($Log -match '(?im)^[ \t]*(?:===\s*)?[^\r\n]*(?:_test|gate):[ \t]*FAIL\b') { return $true }
  # These regression scenes use different terminal formats. Match nonzero
  # counts only; passing summaries and ordinary diagnostic FAIL text stay valid.
  if ($Log -match '(?im)^[ \t]*space_test:[ \t]*0*[1-9][0-9]*[ \t]+fail[ \t]*\r?$') { return $true }
  if ($Log -match '(?im)^[ \t]*CAFE_GUEST_ACCESS_TEST_FAILS=[ \t]*0*[1-9][0-9]*[ \t]*\r?$') { return $true }
  if ($Log -match '(?im)^[ \t]*===[ \t]*PLAYER[ \t]+JOURNEY:[ \t]*FAIL\b[^\r\n]*\r?$') { return $true }
  return $false
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
      # Recheck identity immediately before killing; never act on a reused PID.
      $current = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f ([int]$proc.ProcessId))
      if (-not (Test-ScopedProcessIdentity $proc $current)) { continue }
      try { Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop }
      catch [Microsoft.PowerShell.Commands.ProcessCommandException] { }
    }
    Start-Sleep -Milliseconds 250
  }
  return @(Get-ScopedProcesses -ScopeToken $ScopeToken -RootPid $RootPid)
}

function Test-ScopedProcessIdentity($Observed, $Current) {
  return $null -ne $Current -and [int]$Observed.ProcessId -eq [int]$Current.ProcessId `
    -and $Observed.CreationDate -eq $Current.CreationDate `
    -and [int]$Observed.ParentProcessId -eq [int]$Current.ParentProcessId `
    -and [string]$Observed.CommandLine -ceq [string]$Current.CommandLine
}

function Get-CaptureOutputSnapshot([string]$Path, [string]$ReportPath, [datetime]$StartedUtc) {
  $folder = [IO.Path]::GetDirectoryName($Path)
  $captureBytes = [int64]0
  if (Test-Path -LiteralPath $Path -PathType Leaf) { $captureBytes = [int64](Get-Item -LiteralPath $Path).Length }
  $splitFiles = @(Get-ChildItem -LiteralPath $folder -Filter 'capture*.avi' -File | Where-Object {
    -not [string]::Equals($_.FullName, $Path, [StringComparison]::OrdinalIgnoreCase)
  } | ForEach-Object { $_.FullName })
  $disk = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Path))
  $report = $null; $reportHash = ''; $reportState = 'missing'
  if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
    $item = Get-Item -LiteralPath $ReportPath
    if ($item.LastWriteTimeUtc -lt $StartedUtc) { $reportState = 'stale' }
    elseif ($item.Length -gt 0) {
      $reportState = 'writing'
      try {
        $parsed = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['status'] `
            -and [string]$parsed.status -cin @('PASS', 'FAIL')) {
          $digest = (Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
          $report = $parsed; $reportState = 'terminal'; $reportHash = $digest
        }
      } catch { } # A single non-atomic JSON write can be incomplete this poll.
    }
  }
  return [ordered]@{ capture_bytes=$captureBytes; split_files=$splitFiles;
    disk_root=$disk.Name; available_bytes=[int64]$disk.AvailableFreeSpace;
    report_state=$reportState; report=$report; report_sha256=$reportHash }
}

function Get-CaptureGuardDecision($Snapshot, [int]$ExpectedFrames, $Bindings) {
  $result = [ordered]@{ breach=$false; reason=''; report_terminal=$false; report_valid=$false; report_status=''; report_reason='' }
  if ([int64]$Snapshot.capture_bytes -ge 3900000000) { $result.breach=$true; $result.reason='AVI reached the 3900000000-byte limit.' }
  elseif ([int64]$Snapshot.available_bytes -lt 2147483648) { $result.breach=$true; $result.reason='Capture volume has less than the 2 GiB free-space reserve.' }
  elseif (@($Snapshot.split_files).Count -gt 0) { $result.breach=$true; $result.reason='Split capture*.avi files are forbidden: '+(@($Snapshot.split_files) -join ', ') }
  if ($Snapshot.report_state -ne 'terminal') { return $result }
  $result.report_terminal=$true; $report=$Snapshot.report; $result.report_status=[string]$report.status
  try {
    $seconds = $ExpectedFrames / 18
    if ($ExpectedFrames -notin @(1620, 15120) -or $report.schema -cne 'living_town.walkthrough.v1' `
        -or $report.status -cne 'PASS' -or $report.preview -isnot [bool] `
        -or $report.preview -ne ($ExpectedFrames -eq 1620) -or $report.route_complete -isnot [bool] `
        -or -not $report.route_complete -or $report.direct_agent_writes -isnot [bool] `
        -or $report.direct_agent_writes -or $report.failure_count -ne 0 `
        -or $report.fps -ne 18 -or $report.expected_tour_frames -ne $ExpectedFrames `
        -or $report.tour_frames_elapsed -ne $ExpectedFrames -or $report.expected_tour_seconds -ne $seconds `
        -or $report.tour_seconds_elapsed -ne $seconds) { throw 'Terminal walkthrough report failed schema/mode/frame/time/zero-failure checks.' }
    $checks = @($report.checks)
    if ($checks.Count -eq 0) { throw 'Terminal walkthrough report contains no checks.' }
    foreach ($check in $checks) {
      if ($null -eq $check -or $check.passed -isnot [bool] -or -not $check.passed) { throw 'Terminal walkthrough report contains a failed/malformed check.' }
    }
    foreach ($key in @('harness_sha256', 'stage_manifest_sha256', 'characters_manifest_sha256')) {
      if ($report.$key -cne $Bindings[$key]) { throw ('Terminal walkthrough report has a stale binding: '+$key) }
    }
    $result.report_valid=$true
  } catch { $result.report_reason=$_.Exception.Message }
  return $result
}

function Get-CaptureRuntimeFiles([string]$GamePath) {
  # Same strict raw-file convention as town_runtime_assets.runtime_records /
  # verify_runtime: authored lengths and hashes, safe relative paths, no
  # observed-character-hash fallback and no dependency on imported resources.
  $gameRoot = [IO.Path]::GetFullPath($GamePath).TrimEnd([char[]]'\/')
  $records = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
  function RuntimePath([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative.StartsWith('/') -or $Relative.Contains('\') -or $Relative.Contains(':')) { throw ('Unsafe capture runtime-relative path: '+$Relative) }
    $parts = $Relative.Split('/')
    if (@($parts | Where-Object { $_ -in @('','.', '..') }).Count -gt 0) { throw ('Unsafe capture runtime-relative path: '+$Relative) }
    $path = $gameRoot
    foreach ($part in $parts) {
      $path = Join-Path $path $part
      if (-not (Test-Path -LiteralPath $path)) { throw ('Missing raw capture runtime file: '+$Relative) }
      if (((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('Linked capture runtime path is not accepted: '+$Relative) }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Capture runtime file is not a regular file: '+$Relative) }
    return $path
  }
  function AddRuntimeRecord([string]$Relative, $Bytes, $Digest, [bool]$AllowIdentical = $false) {
    if (($Bytes -isnot [int] -and $Bytes -isnot [long]) -or [int64]$Bytes -lt 0 -or $Digest -isnot [string] -or $Digest -cnotmatch '^[0-9a-f]{64}$') { throw ('Missing/invalid explicit runtime SHA/length: '+$Relative) }
    foreach ($known in $records.Keys) {
      if ([string]::Equals($known,$Relative,[StringComparison]::OrdinalIgnoreCase)) {
        if ($AllowIdentical -and $known -ceq $Relative -and $records[$known].bytes -eq $Bytes -and $records[$known].sha256 -ceq $Digest) { return }
        throw ('Duplicate/conflicting capture runtime path: '+$Relative)
      }
    }
    $path = RuntimePath $Relative
    $actualBytes = [int64](Get-Item -LiteralPath $path).Length
    if ($actualBytes -ne [int64]$Bytes) { throw ('Raw capture runtime length differs: '+$Relative) }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $Digest) { throw ('Raw capture runtime checksum differs: '+$Relative) }
    $records.Add($Relative,[ordered]@{path=$Relative;bytes=$actualBytes;sha256=$actualHash})
  }
  $stageRelative = 'assets/town3d/stage_manifest.json'
  $characterRelative = 'data/town3d/characters.json'
  $stagePath = RuntimePath $stageRelative
  $characterPath = RuntimePath $characterRelative
  $stage = Get-Content -LiteralPath $stagePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $characters = Get-Content -LiteralPath $characterPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($stage.schema -cne 'living_town.game_stage.v2' -or $stage.status -cne 'PASS' -or @($stage.files).Count -eq 0 -or @($stage.assets).Count -eq 0) { throw 'Guarded capture requires a passing complete v2 raw town stage.' }
  foreach ($item in $stage.files) {
    AddRuntimeRecord ('assets/town3d/'+[string]$item.file) $item.bytes $item.sha256
  }
  foreach ($asset in $stage.assets) {
    $relative = 'assets/town3d/'+[string]$asset.file
    if ([IO.Path]::GetExtension($relative) -cne '.glb' -or -not $records.ContainsKey($relative) -or $records[$relative].sha256 -cne $asset.sha256) { throw ('Referenced town GLB lacks a matching verified SHA/length record: '+$relative) }
    $catalog = 'assets/town3d/'+[string]$asset.catalog
    if (-not $records.ContainsKey($catalog) -or $records[$catalog].sha256 -cne $asset.catalog_sha256) { throw ('Referenced town catalog lacks a matching verified SHA/length record: '+$catalog) }
  }
  if ($characters.schema -cne 'living_town.characters.v1' -or $null -eq $characters.characters) { throw 'Guarded capture requires the authored character manifest.' }
  $entries = @($characters.characters.PSObject.Properties)
  if ($entries.Count -lt 25 -or $null -eq $characters.characters.PSObject.Properties['player']) { throw 'Guarded capture requires all24personas plus player.' }
  foreach ($property in $entries) {
    $entry = $property.Value
    if ($entry.model -isnot [string] -or -not $entry.model.StartsWith('res://assets/characters3d/',[StringComparison]::Ordinal) -or [IO.Path]::GetExtension($entry.model) -cne '.glb') { throw ('Character model must be a raw res://assets/characters3d/ GLB: '+$property.Name) }
    AddRuntimeRecord $entry.model.Substring(6) $entry.model_bytes $entry.model_sha256 $true
  }
  foreach ($relative in @($stageRelative,$characterRelative)) {
    $path = RuntimePath $relative
    AddRuntimeRecord $relative ([int64](Get-Item -LiteralPath $path).Length) ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())
  }
  $names = [string[]]@($records.Keys)
  [Array]::Sort($names,[StringComparer]::Ordinal)
  return @($names | ForEach-Object { $records[$_] })
}

function Get-CaptureSourceBindings([string]$GamePath) {
  $bindings = [ordered]@{}
  foreach ($entry in @(@('harness_sha256','scripts/town_walkthrough.gd'), @('stage_manifest_sha256','assets/town3d/stage_manifest.json'), @('characters_manifest_sha256','data/town3d/characters.json'))) {
    $path = Join-Path $GamePath $entry[1]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Missing guarded capture source: '+$path) }
    $bindings[$entry[0]]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $runtimeFiles = @(Get-CaptureRuntimeFiles $GamePath)
  $bindings.runtime_assets_sha256 = Get-Sha256Text (ConvertTo-Json -InputObject $runtimeFiles -Depth 4 -Compress)
  $bindings.runtime_file_count = $runtimeFiles.Count
  $bindings.runtime_model_count = @($runtimeFiles | Where-Object { [IO.Path]::GetExtension($_.path) -ceq '.glb' }).Count
  return $bindings
}

function Test-CaptureShutdownGrace([datetime]$ReportSeenUtc, [datetime]$NowUtc) {
  return ($NowUtc-$ReportSeenUtc).TotalSeconds -ge 15
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
$defaultGamePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'game')).Path
$gamePath = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
  $defaultGamePath
} else {
  (Resolve-Path -LiteralPath $ProjectPath).Path
}
if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'project.godot') -PathType Leaf)) {
  throw "Godot project.godot is missing from $gamePath"
}
$externalProjectCopy = -not [string]::Equals($gamePath, $defaultGamePath, [StringComparison]::OrdinalIgnoreCase)
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
$logicFailure = $false
$cleanupVerified = $false
$exitCode = $null
$outcome = 'runner_error'
$errorText = ''
$preflight = @()
$captureEnabled = -not [string]::IsNullOrWhiteSpace($CapturePath) -or -not [string]::IsNullOrWhiteSpace($CaptureReportPath) -or $CaptureExpectedFrames -ne 0
$captureBindingsBefore = $null
$captureReportSeenUtc = $null
$captureGuard = [ordered]@{ enabled=$captureEnabled; max_avi_bytes=[int64]3900000000;
  reserve_disk_bytes=[int64]2147483648; poll_ms=1000; shutdown_grace_seconds=15;
  expected_frames=$CaptureExpectedFrames; source_before=$null; source_after=$null; source_stable=$null;
  peak_capture_bytes=[int64]0; minimum_free_bytes=$null; samples=0; report_seen_utc=$null;
  terminal_report_sha256=''; terminal_report_valid=$false; terminal_report_status='';
  shutdown_grace_expired=$false; stop_reason='' }

$gitHead = (Invoke-GitCapture $repoRoot @('rev-parse', 'HEAD') | Select-Object -First 1)
$gameTree = (Invoke-GitCapture $repoRoot @('rev-parse', 'HEAD:game') | Select-Object -First 1)
$branch = (Invoke-GitCapture $repoRoot @('branch', '--show-current') | Select-Object -First 1)
$worktreeBefore = Get-WorktreeEvidence $repoRoot
$statusBefore = @($worktreeBefore.status)
$sourceIdentity = if ($statusBefore.Count -eq 0) {
  if ($externalProjectCopy) { 'external_project_copy' } else { 'exact_commit' }
} elseif ($AllowDirtyCandidate) { 'dirty_candidate' } else { 'rejected_dirty' }
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

  if ($captureEnabled) {
    $outcome='capture_preflight_blocked'; $exitCode=73
    if ([string]::IsNullOrWhiteSpace($CapturePath) -or [string]::IsNullOrWhiteSpace($CaptureReportPath) -or $CaptureExpectedFrames -notin @(1620,15120)) {
      throw 'Capture guard requires exact AVI/report paths and1620preview or15120full expected frames.'
    }
    if (-not [IO.Path]::IsPathRooted($CapturePath) -or -not [IO.Path]::IsPathRooted($CaptureReportPath)) { throw 'Capture guard paths must be absolute.' }
    $CapturePath=[IO.Path]::GetFullPath($CapturePath); $CaptureReportPath=[IO.Path]::GetFullPath($CaptureReportPath)
    $captureFolder=[IO.Path]::GetDirectoryName($CapturePath)
    if ([IO.Path]::GetFileName($CapturePath) -cne 'capture.avi' -or [IO.Path]::GetFileName($CaptureReportPath) -cne 'walkthrough_report.json' `
        -or -not [string]::Equals($captureFolder,[IO.Path]::GetDirectoryName($CaptureReportPath),[StringComparison]::OrdinalIgnoreCase)) {
      throw 'Capture guard requires capture.avi and walkthrough_report.json in the same exact output directory.'
    }
    if (Test-Path -LiteralPath $CapturePath) { throw 'Existing guarded AVI is preserved; use a fresh output directory.' }
    if (Test-Path -LiteralPath $CaptureReportPath) { throw 'Existing guarded report is preserved; use a fresh output directory.' }
    $movieIndex=[Array]::IndexOf($GodotArgs,'--write-movie')
    $directoryIndex=[Array]::IndexOf($GodotArgs,'--walkthrough-dir')
    $fpsIndex=[Array]::IndexOf($GodotArgs,'--fixed-fps')
    if ($movieIndex -lt 0 -or $movieIndex+1 -ge $GodotArgs.Count -or $GodotArgs[$movieIndex+1] -cne $CapturePath `
        -or $directoryIndex -lt 0 -or $directoryIndex+1 -ge $GodotArgs.Count -or $GodotArgs[$directoryIndex+1] -cne $captureFolder `
        -or $fpsIndex -lt 0 -or $fpsIndex+1 -ge $GodotArgs.Count -or $GodotArgs[$fpsIndex+1] -cne '18' `
        -or ($GodotArgs -contains '--walkthrough-preview') -ne ($CaptureExpectedFrames -eq 1620)) {
      throw 'Guarded output/mode paths or18FPS do not match the actual Godot arguments.'
    }
    $captureBindingsBefore=Get-CaptureSourceBindings $gamePath
    $captureGuard.source_before=$captureBindingsBefore
    $captureGuard.path=$CapturePath; $captureGuard.report_path=$CaptureReportPath
    $initialSnapshot=Get-CaptureOutputSnapshot $CapturePath $CaptureReportPath $startedUtc
    $initialDecision=Get-CaptureGuardDecision $initialSnapshot $CaptureExpectedFrames $captureBindingsBefore
    if ($initialDecision.breach) { throw $initialDecision.reason }
    $captureGuard.minimum_free_bytes=$initialSnapshot.available_bytes
    $outcome='runner_error'; $exitCode=$null
  }

  $allArgs = @('--path', $gamePath, '--log-file', $godotLog) + @($GodotArgs)
  $argumentLine = (($allArgs | ForEach-Object { Quote-WindowsArgument ([string]$_) }) -join ' ')
  $process = Start-Process -FilePath $godotExe -ArgumentList $argumentLine -WorkingDirectory $repoRoot `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -WindowStyle Hidden -PassThru
  $processId = [int]$process.Id
  $processStarted = $true
  if ($captureEnabled) {
    while (-not $process.WaitForExit(1000)) {
      $now=[DateTime]::UtcNow
      if (($now-$startedUtc).TotalSeconds -ge $TimeoutSec) { $timedOut=$true; $outcome='timeout'; $exitCode=124; break }
      $snapshot=Get-CaptureOutputSnapshot $CapturePath $CaptureReportPath $startedUtc
      $decision=Get-CaptureGuardDecision $snapshot $CaptureExpectedFrames $captureBindingsBefore
      $captureGuard.samples++
      $captureGuard.peak_capture_bytes=[Math]::Max([int64]$captureGuard.peak_capture_bytes,[int64]$snapshot.capture_bytes)
      $captureGuard.minimum_free_bytes=[Math]::Min([int64]$captureGuard.minimum_free_bytes,[int64]$snapshot.available_bytes)
      if ($decision.breach) {
        $outcome='capture_guard_limit'; $exitCode=74; $errorText=$decision.reason; $captureGuard.stop_reason=$decision.reason; break
      }
      if ($decision.report_terminal -and $null -eq $captureReportSeenUtc) {
        $captureReportSeenUtc=$now; $captureGuard.report_seen_utc=$now.ToString('o')
        $captureGuard.terminal_report_sha256=$snapshot.report_sha256
        $captureGuard.terminal_report_valid=$decision.report_valid; $captureGuard.terminal_report_status=$decision.report_status
        $captureGuard.stop_reason=$decision.report_reason
      }
      if ($null -ne $captureReportSeenUtc -and (Test-CaptureShutdownGrace $captureReportSeenUtc $now)) {
        $captureGuard.shutdown_grace_expired=$true
        $outcome='capture_shutdown_timeout'; $exitCode=74
        $errorText='Godot did not exit within15seconds after the fresh terminal walkthrough report.'
        break
      }
    }
    if ($null -eq $exitCode) {
      $process.Refresh(); $exitCode=[int]$process.ExitCode
      $outcome=if ($exitCode -eq 0) { 'pass' } else { 'godot_failed' }
    }
  }
  elseif (-not $process.WaitForExit($TimeoutSec * 1000)) {
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
  if ($captureEnabled -and $null -ne $captureBindingsBefore) {
    try {
      $captureGuard.source_after=Get-CaptureSourceBindings $gamePath
      $captureGuard.source_stable=$true
      foreach ($key in $captureBindingsBefore.Keys) {
        if ($captureBindingsBefore[$key] -cne $captureGuard.source_after[$key]) { $captureGuard.source_stable=$false }
      }
      $finalSnapshot=Get-CaptureOutputSnapshot $CapturePath $CaptureReportPath $startedUtc
      $finalDecision=Get-CaptureGuardDecision $finalSnapshot $CaptureExpectedFrames $captureBindingsBefore
      $captureGuard.peak_capture_bytes=[Math]::Max([int64]$captureGuard.peak_capture_bytes,[int64]$finalSnapshot.capture_bytes)
      $captureGuard.minimum_free_bytes=[Math]::Min([int64]$captureGuard.minimum_free_bytes,[int64]$finalSnapshot.available_bytes)
      $captureGuard.final_report_state=$finalSnapshot.report_state
      $captureGuard.final_report_sha256=$finalSnapshot.report_sha256
      if ($finalSnapshot.capture_bytes -le 0) { $finalDecision.report_valid=$false; $finalDecision.report_reason='Actual AVI is missing or empty.' }
      if ($null -ne $captureReportSeenUtc -and $captureGuard.terminal_report_sha256 -cne $finalSnapshot.report_sha256) { $finalDecision.report_valid=$false; $finalDecision.report_reason='Terminal report changed after observation.' }
      if ($exitCode -eq 0 -and (-not $captureGuard.source_stable -or $finalDecision.breach -or -not $finalDecision.report_valid)) {
        $outcome='capture_guard_failed'; $exitCode=74
        $errorText=if (-not $captureGuard.source_stable) { 'Director/stage/character sources changed during guarded capture.' } elseif ($finalDecision.breach) { $finalDecision.reason } else { 'Missing/invalid terminal report: '+$finalDecision.report_reason }
      }
      $captureGuard.terminal_report_valid=$finalDecision.report_valid
      if ($captureGuard.stop_reason -eq '') { $captureGuard.stop_reason=$errorText }
    } catch {
      $captureGuard.source_stable=$false
      if ($exitCode -eq 0) { $outcome='capture_guard_failed'; $exitCode=74; $errorText=$_.Exception.Message }
      $captureGuard.stop_reason=$_.Exception.Message
    }
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
  $logicFailure = [bool](Test-GodotLogicFailure $combined)
  if ($logicFailure -and $exitCode -eq 0) {
    $outcome = 'logic_failure_pattern'
    $exitCode = 72
  }
  if ($processStarted -and -not $sourceStable -and $cleanupVerified -and -not $nativeCrash) {
    $outcome = 'source_drift'
    $exitCode = 79
    $errorText = 'Git HEAD, branch, committed game tree, or worktree fingerprint differs between launch and completion.'
  }
  if ($lockStream) { $lockStream.Dispose() }
  if ($lockOwned -and (Test-Path -LiteralPath $lockPath -PathType Leaf)) { Remove-Item -LiteralPath $lockPath -Force }

  $receipt = [ordered]@{
    contract = 'living-town-supervised-godot-v3'
    run_id = $runId
    outcome = $outcome
    exit_code = $exitCode
    timed_out = $timedOut
    native_crash_pattern = $nativeCrash
    logic_failure_pattern = $logicFailure
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
    external_project_copy = $externalProjectCopy
    arguments = @($GodotArgs)
    injected_log = $godotLog
    timeout_seconds = $TimeoutSec
    capture_guard = $captureGuard
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
