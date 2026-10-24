<# Pure predicates and tiny temporary files only. No Godot, Git, process launch or kill. #>
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools/run-godot-supervised.ps1'),[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw ($errors.Message -join '; ') }
$names=@('Get-Sha256Text','Test-ScopedProcessIdentity','Get-CaptureOutputSnapshot','Get-CaptureGuardDecision','Get-CaptureRuntimeFiles','Get-CaptureSourceBindings','Test-CaptureShutdownGrace')
$functions=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names},$true))
if ($functions.Count -ne $names.Count) { throw 'Expected only the seven leased guard functions.' }
foreach ($function in $functions) { . ([scriptblock]::Create($function.Extent.Text)) }
$count=0
function Check([string]$Name,[bool]$Passed) {
  if (-not $Passed) { throw ('FAIL '+$Name) }
  $script:count++; Write-Output ('PASS '+$Name)
}
function CheckThrows([string]$Name,[scriptblock]$Action,[string]$Message) {
  $caught=$null
  try { & $Action | Out-Null } catch { $caught=$_.Exception.Message }
  Check $Name ($null -ne $caught -and $caught -like ('*'+$Message+'*'))
}
function Snapshot {
  return [ordered]@{capture_bytes=[int64]1;available_bytes=[int64]4000000000;split_files=@();report_state='missing';report=$null;report_sha256=''}
}
$bindings=[ordered]@{harness_sha256=('a'*64);stage_manifest_sha256=('b'*64);characters_manifest_sha256=('c'*64)}
function Report([int]$Frames=15120) {
  return [pscustomobject]@{schema='living_town.walkthrough.v1';status='PASS';preview=($Frames -eq 1620);route_complete=$true;
    direct_agent_writes=$false;failure_count=0;fps=18;expected_tour_frames=$Frames;tour_frames_elapsed=$Frames;
    expected_tour_seconds=($Frames/18);tour_seconds_elapsed=($Frames/18);checks=@([pscustomobject]@{passed=$true});
    harness_sha256=$bindings.harness_sha256;stage_manifest_sha256=$bindings.stage_manifest_sha256;characters_manifest_sha256=$bindings.characters_manifest_sha256}
}
foreach ($frames in @(1620,15120)) {
  $s=Snapshot; $s.report_state='terminal'; $s.report=Report $frames
  $d=Get-CaptureGuardDecision $s $frames $bindings
  Check "complete matching $frames frame report accepted" ($d.report_terminal -and $d.report_valid -and -not $d.breach)
}
$s=Snapshot; $s.capture_bytes=3899999999; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'AVI below cap allowed' (-not $d.breach)
$s.capture_bytes=3900000000; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'AVI at cap stops immediately' $d.breach
$s=Snapshot; $s.available_bytes=2147483648; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'exact disk reserve allowed' (-not $d.breach)
$s.available_bytes=2147483647; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'disk below reserve stops' $d.breach
$s=Snapshot; $s.split_files=@('F:/unit-only/capture0001.avi'); $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'split AVI rejected' $d.breach
$s=Snapshot; $s.report_state='terminal'; $s.report=[pscustomobject]@{status='FAIL'}; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'early FAIL is terminal even with incomplete route fields' ($d.report_terminal -and -not $d.report_valid)
$s.report=Report; $s.report.expected_tour_frames=6480; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'old 6480 frame guard cannot certify current route' ($d.report_terminal -and -not $d.report_valid)
$s.report=Report; $s.report.characters_manifest_sha256='changed'; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'wrong current character set rejected' (-not $d.report_valid)
$s.report=Report 1620; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'preview cannot certify full route' (-not $d.report_valid)
$s.report=Report; $s.report.checks[0].passed=$false; $d=Get-CaptureGuardDecision $s 15120 $bindings
Check 'failed route predicate rejected despite PASS string' (-not $d.report_valid)
$now=[DateTime]::UtcNow
Check 'shutdown grace is not shortened' (-not (Test-CaptureShutdownGrace $now $now.AddMilliseconds(14999)))
Check 'shutdown grace expires at 15seconds' (Test-CaptureShutdownGrace $now $now.AddSeconds(15))
$observed=[pscustomobject]@{ProcessId=1234;ParentProcessId=999;CreationDate=$now;CommandLine='unit-only-unique-token'}
$same=[pscustomobject]@{ProcessId=1234;ParentProcessId=999;CreationDate=$now;CommandLine='unit-only-unique-token'}
Check 'matching scoped identity verified' (Test-ScopedProcessIdentity $observed $same)
$same.CreationDate=$now.AddSeconds(1)
Check 'reused PID never verified for kill' (-not (Test-ScopedProcessIdentity $observed $same))

$scratch=Join-Path ([IO.Path]::GetTempPath()) ('town-capture-guard-unit-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
  $capture=Join-Path $scratch 'capture.avi';$reportPath=Join-Path $scratch 'walkthrough_report.json'
  [IO.File]::WriteAllBytes($capture,[byte[]](1,2,3))
  [IO.File]::WriteAllText($reportPath,'{"status":')
  $snapshot=Get-CaptureOutputSnapshot $capture $reportPath $now.AddMinutes(-1)
  Check 'partial JSON waits without false terminal report' ($snapshot.report_state -eq 'writing')
  [IO.File]::WriteAllText($reportPath,([pscustomobject]@{status='FAIL'} | ConvertTo-Json))
  $snapshot=Get-CaptureOutputSnapshot $capture $reportPath $now.AddMinutes(-1)
  Check 'fresh actual FAIL detected and hashed' ($snapshot.report_state -eq 'terminal' -and $snapshot.report_sha256.Length -eq 64)
  $snapshot=Get-CaptureOutputSnapshot $capture $reportPath $now.AddMinutes(1)
  Check 'stale prior report never triggers shutdown timer' ($snapshot.report_state -eq 'stale' -and $null -eq $snapshot.report)
  $split=Join-Path $scratch 'capture0001.avi';[IO.File]::WriteAllBytes($split,[byte[]](1))
  $snapshot=Get-CaptureOutputSnapshot $capture $reportPath $now.AddMinutes(-1)
  Check 'actual sibling split detected' (@($snapshot.split_files).Count -eq 1 -and $snapshot.capture_bytes -eq 3)
  $game=Join-Path $scratch 'game'
  foreach ($relative in @('scripts','assets/town3d','assets/characters3d','data/town3d')) { New-Item -ItemType Directory -Force -Path (Join-Path $game $relative) | Out-Null }
  [IO.File]::WriteAllText((Join-Path $game 'scripts/town_walkthrough.gd'),'unit-only-original-source')
  $townModel=Join-Path $game 'assets/town3d/town.glb';[IO.File]::WriteAllText($townModel,'unit-only-town-model')
  $townCatalog=Join-Path $game 'assets/town3d/town.catalog.json';[IO.File]::WriteAllText($townCatalog,'unit-only-catalog')
  $townHash=(Get-FileHash -LiteralPath $townModel -Algorithm SHA256).Hash.ToLowerInvariant()
  $catalogHash=(Get-FileHash -LiteralPath $townCatalog -Algorithm SHA256).Hash.ToLowerInvariant()
  $stage=[ordered]@{schema='living_town.game_stage.v2';status='PASS';assets=@([ordered]@{file='town.glb';sha256=$townHash;catalog='town.catalog.json';catalog_sha256=$catalogHash});files=@(
    [ordered]@{file='town.glb';bytes=(Get-Item -LiteralPath $townModel).Length;sha256=$townHash},
    [ordered]@{file='town.catalog.json';bytes=(Get-Item -LiteralPath $townCatalog).Length;sha256=$catalogHash})}
  $characterEntries=[ordered]@{}
  foreach ($key in @('player')+@(0..23 | ForEach-Object { 'persona{0:d2}' -f $_ })) {
    $relative='assets/characters3d/'+$key+'.glb';$path=Join-Path $game $relative
    [IO.File]::WriteAllText($path,('unit-only-character-'+$key))
    $characterEntries[$key]=[ordered]@{model=('res://'+$relative);model_bytes=(Get-Item -LiteralPath $path).Length;model_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
  }
  $characterManifest=[ordered]@{schema='living_town.characters.v1';characters=$characterEntries}
  function WriteRuntimeManifests {
    [IO.File]::WriteAllText((Join-Path $game 'assets/town3d/stage_manifest.json'),($stage | ConvertTo-Json -Depth 6))
    [IO.File]::WriteAllText((Join-Path $game 'data/town3d/characters.json'),($characterManifest | ConvertTo-Json -Depth 6))
  }
  WriteRuntimeManifests
  $before=Get-CaptureSourceBindings $game
  Check 'strict complete tiny runtime file set verified' ($before.runtime_file_count -eq 29 -and $before.runtime_model_count -eq 26 -and $before.runtime_assets_sha256.Length -eq 64)
  $unchanged=Get-CaptureSourceBindings $game
  Check 'identical raw runtime digest is stable across observations' ($before.runtime_assets_sha256 -ceq $unchanged.runtime_assets_sha256)
  $playerPath=Join-Path $game 'assets/characters3d/player.glb';$playerBytes=[IO.File]::ReadAllBytes($playerPath)
  $changed=$playerBytes.Clone();$changed[0]=$changed[0] -bxor 1;[IO.File]::WriteAllBytes($playerPath,$changed)
  CheckThrows 'same-size stale character raw bytes rejected despite unchanged manifest' { Get-CaptureSourceBindings $game } 'checksum differs'
  [IO.File]::WriteAllBytes($playerPath,$playerBytes)
  $townBytes=[IO.File]::ReadAllBytes($townModel);$changed=$townBytes.Clone();$changed[0]=$changed[0] -bxor 1;[IO.File]::WriteAllBytes($townModel,$changed)
  CheckThrows 'same-size stale town raw bytes rejected despite unchanged stage' { Get-CaptureSourceBindings $game } 'checksum differs'
  [IO.File]::WriteAllBytes($townModel,$townBytes)
  $stage.files[0].bytes++;WriteRuntimeManifests
  CheckThrows 'declared town byte length must match actual file' { Get-CaptureSourceBindings $game } 'length differs'
  $stage.files[0].bytes--;WriteRuntimeManifests
  $characterEntries.player.model_bytes++;WriteRuntimeManifests
  CheckThrows 'declared character byte length must match actual file' { Get-CaptureSourceBindings $game } 'length differs'
  $characterEntries.player.model_bytes--;WriteRuntimeManifests
  $playerUri=$characterEntries.player.model;$characterEntries.player.model='res://assets/characters3d/missing.glb';WriteRuntimeManifests
  CheckThrows 'missing raw character cannot fall back to imported resources' { Get-CaptureSourceBindings $game } 'Missing raw capture runtime file'
  $characterEntries.player.model='res://assets/characters3d/../../outside.glb';WriteRuntimeManifests
  CheckThrows 'character traversal rejected before any external file read' { Get-CaptureSourceBindings $game } 'Unsafe capture runtime-relative path'
  $characterEntries.player.model=$playerUri;WriteRuntimeManifests
  $catalogDeclaration=$stage.assets[0].catalog_sha256;$stage.assets[0].catalog_sha256='0'*64;WriteRuntimeManifests
  CheckThrows 'town semantic catalog must have a matching explicit stage file record' { Get-CaptureSourceBindings $game } 'catalog lacks a matching'
  $stage.assets[0].catalog_sha256=$catalogDeclaration;WriteRuntimeManifests
  $characterEntries.player.model_sha256=$null;WriteRuntimeManifests
  CheckThrows 'missing character SHA is never inferred from observed bytes' { Get-CaptureSourceBindings $game } 'Missing/invalid explicit runtime SHA'
  $characterEntries.player.model_sha256=(Get-FileHash -LiteralPath $playerPath -Algorithm SHA256).Hash.ToLowerInvariant();WriteRuntimeManifests
  $changed=$playerBytes.Clone();$changed[0]=$changed[0] -bxor 1;[IO.File]::WriteAllBytes($playerPath,$changed)
  $characterEntries.player.model_sha256=(Get-FileHash -LiteralPath $playerPath -Algorithm SHA256).Hash.ToLowerInvariant();WriteRuntimeManifests
  $after=Get-CaptureSourceBindings $game
  Check 'self-consistent changed character still changes actual runtime digest' ($before.runtime_assets_sha256 -cne $after.runtime_assets_sha256 -and $before.characters_manifest_sha256 -cne $after.characters_manifest_sha256 -and $before.harness_sha256 -ceq $after.harness_sha256)
} finally {
  $resolved=[IO.Path]::GetFullPath($scratch)
  $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'town-capture-guard-unit-*') { throw 'Unsafe unit fixture cleanup target.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output ("RECORDING_OUTPUT_GUARD_TESTS_PASS=$count")
