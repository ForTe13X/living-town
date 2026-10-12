<# Record the actual GPU viewport serially, preserving the existing quicksave. #>
[CmdletBinding()]
param(
    [string]$Godot = '',
    [switch]$Preview,
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'

function Assert-TownWalkthroughReport([string]$Path, [bool]$IsPreview, [datetime]$StartedUtc) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Recording did not write a walkthrough report.'
    }
    $reportFile = Get-Item -LiteralPath $Path
    if ($reportFile.Length -eq 0 -or $reportFile.LastWriteTimeUtc -lt $StartedUtc) {
        throw 'Walkthrough report is empty or predates this recording.'
    }
    try { $report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Walkthrough report is invalid JSON: $($_.Exception.Message)" }
    $expectedSeconds = if ($IsPreview) { 90 } else { 600 }
    $expectedFrames = $expectedSeconds * 24
    if ($report.schema -cne 'living_town.walkthrough.v1' -or $report.status -cne 'PASS' `
            -or $report.preview -isnot [bool] -or $report.preview -ne $IsPreview `
            -or $report.route_complete -isnot [bool] -or -not $report.route_complete `
            -or $report.direct_agent_writes -isnot [bool] -or $report.direct_agent_writes `
            -or $report.failure_count -ne 0) {
        throw 'Walkthrough report failed its schema, mode, route, or zero-failure contract.'
    }
    if ($report.fps -ne 24 -or $report.expected_tour_frames -ne $expectedFrames `
            -or $report.tour_frames_elapsed -ne $expectedFrames `
            -or $report.expected_tour_seconds -ne $expectedSeconds `
            -or $report.tour_seconds_elapsed -ne $expectedSeconds) {
        throw 'Walkthrough report does not contain the complete expected 24-FPS tour.'
    }
    $checks = @($report.checks)
    if ($checks.Count -eq 0) { throw 'Walkthrough report contains no route checks.' }
    foreach ($check in $checks) {
        if ($null -eq $check -or $check.passed -isnot [bool] -or -not $check.passed) {
            throw 'Walkthrough report contains a failed or malformed route check.'
        }
    }
    return $report
}

$townRoot = Split-Path -Parent $PSScriptRoot
$townProject = Join-Path $townRoot 'game'
$townMode = if ($Preview) { 'preview' } else { 'full' }
if (-not $OutputDir) { $OutputDir = Join-Path $townRoot "build/town_walkthrough/$townMode" }
$townOutput = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $townOutput | Out-Null
$townRaw = Join-Path $townOutput 'capture.ogv'
if (Test-Path -LiteralPath $townRaw) { throw 'Capture already exists. Choose a new OutputDir to preserve it.' }
$townReport = Join-Path $townOutput 'walkthrough_report.json'
foreach ($townPriorOutput in @($townReport, (Join-Path $townOutput 'walkthrough_cues.json'))) {
    if (Test-Path -LiteralPath $townPriorOutput) {
        throw 'Walkthrough evidence already exists. Choose a new OutputDir to preserve it.'
    }
}
$townConfig = Get-Content -LiteralPath (Join-Path $townProject 'project.godot') -Raw
if ($townConfig -match 'config/use_custom_user_dir\s*=\s*true') {
    throw 'This Windows save guard requires the standard Godot user directory.'
}
if ($townConfig -notmatch 'config/name="([^"]+)"') { throw 'Project name missing.' }
$townAppName = $Matches[1]
if ($townAppName -match '[\\/]') { throw 'Unexpected project-name path.' }
$townUserDir = [IO.Path]::GetFullPath((Join-Path $env:APPDATA "Godot/app_userdata/$townAppName"))
$townSave = [IO.Path]::GetFullPath((Join-Path $townUserDir 'town3d_quicksave.dat'))
if ([IO.Path]::GetDirectoryName($townSave) -ne $townUserDir) { throw 'Save path escapes intended user directory.' }
$townHadSave = Test-Path -LiteralPath $townSave -PathType Leaf
$townBackup = Join-Path $townOutput ('prior_quicksave.' + [guid]::NewGuid().ToString('N') + '.dat')
$townPriorHash = $null
if ($townHadSave) {
    $townPriorHash = (Get-FileHash -LiteralPath $townSave -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $townSave -Destination $townBackup
    if ((Get-FileHash -LiteralPath $townBackup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $townPriorHash) { throw 'Backup verification failed.' }
}
$townArgs = @('--single-threaded-scene', '--disable-vsync', '--windowed', '--resolution', '1280x768',
    '--fixed-fps', '24', '--write-movie', $townRaw, 'res://scenes/town_walkthrough.tscn', '--',
    '--town3d', '--backend', 'logic', '--agents', '12', '--no-player', '--seed', '7', '--walkthrough-dir', $townOutput)
if ($Preview) { $townArgs += '--walkthrough-preview' }
$townRunExit = 1
$townReportValidated = $false
$townReportHash = $null
$townRunStartedUtc = [DateTime]::UtcNow
try {
    & (Join-Path $PSScriptRoot 'run-godot-supervised.ps1') -Godot $Godot -AllowDirtyCandidate -TimeoutSec 3600 -GodotArgs $townArgs
    $townRunExit = $LASTEXITCODE
    if ($townRunExit -eq 0) {
        # Windows Godot may return zero after quit(1); the fresh director verdict
        # is an independent required gate, including for the compressed preview.
        $null = Assert-TownWalkthroughReport -Path $townReport -IsPreview ([bool]$Preview) -StartedUtc $townRunStartedUtc
        $townReportHash = (Get-FileHash -LiteralPath $townReport -Algorithm SHA256).Hash.ToLowerInvariant()
        $townReportValidated = $true
    }
} finally {
    if (Test-Path -LiteralPath $townSave -PathType Leaf) {
        Copy-Item -LiteralPath $townSave -Destination (Join-Path $townOutput 'recorded_quicksave.dat')
    }
    if ($townHadSave) {
        Copy-Item -LiteralPath $townBackup -Destination $townSave -Force
        if ((Get-FileHash -LiteralPath $townSave -Algorithm SHA256).Hash.ToLowerInvariant() -ne $townPriorHash) { throw 'Prior quicksave restore failed; backup retained.' }
    } elseif (Test-Path -LiteralPath $townSave -PathType Leaf) {
        # Exact checked file only; never remove a directory or other user data.
        Remove-Item -LiteralPath $townSave
    }
    @{ schema='living_town.recording_save_guard.v1'; prior_save_present=$townHadSave;
       prior_sha256=$townPriorHash; prior_save_restored=$true; recording_exit=$townRunExit;
       walkthrough_report_validated=$townReportValidated; walkthrough_report_sha256=$townReportHash;
       user_directory=$townUserDir; output_directory=$townOutput } |
        ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $townOutput 'save_guard.json')
}
if ($townRunExit -ne 0) { throw 'Supervised recording failed; see its receipt and walkthrough report.' }
