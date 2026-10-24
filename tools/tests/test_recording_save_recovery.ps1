<# Execute the recorder's actual recovery block using only isolated fixture files. #>
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools/record-town-walkthrough.ps1'),[ref]$tokens,[ref]$parseErrors)
if (@($parseErrors).Count) { throw ($parseErrors.Message -join '; ') }
$run=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.TryStatementAst] -and $node.Body.Extent.Text.Contains('-CapturePath $townRaw')},$true))
if ($run.Count -ne 1 -or -not $run[0].Finally) { throw 'Expected the actual recorder recovery block.' }
$body=$run[0].Finally.Extent.Text
$recover=[scriptblock]::Create($body.Substring(1,$body.Length-2))
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('town-save-recovery-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$caseFolders=@()
$checks=0
try {
    foreach ($hadSave in @($true,$false)) {
        foreach ($archiveFailure in @($true,$false)) {
            $townOutput=Join-Path $scratch ($hadSave.ToString()+'-'+$archiveFailure.ToString())
            New-Item -ItemType Directory -Path $townOutput | Out-Null
            $caseFolders+=$townOutput
            $townSave=Join-Path $townOutput 'active.dat'
            $townBackup=Join-Path $townOutput 'backup.dat'
            $archive=Join-Path $townOutput 'recorded_quicksave.dat'
            $townHadSave=$hadSave; $townUserDir=$townOutput
            $townRunExit=0; $townReportValidated=$true; $townReportHash=('a'*64)
            $townRecordedSaveArchived=$false; $townPriorHash=$null
            [IO.File]::WriteAllText($townSave,'recording-save')
            if ($hadSave) {
                [IO.File]::WriteAllText($townBackup,'original-save')
                $townPriorHash=(Get-FileHash -LiteralPath $townBackup -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            if ($archiveFailure) {
                [IO.File]::WriteAllText($archive,'existing-archive')
                (Get-Item -LiteralPath $archive).IsReadOnly=$true
            }
            $failed=$false
            try { & $recover } catch { $failed=$true }
            if ($failed -ne $archiveFailure) { throw 'Archive error was swallowed or unexpected error occurred.' }
            if ($hadSave) {
                if ([IO.File]::ReadAllText($townSave) -cne 'original-save') { throw 'Prior save was not recovered.' }
            } elseif (Test-Path -LiteralPath $townSave) { throw 'Recording save remained live despite no prior save.' }
            $guard=Get-Content -LiteralPath (Join-Path $townOutput 'save_guard.json') -Raw | ConvertFrom-Json
            if (-not $guard.prior_save_restored -or $guard.recorded_save_archived -ne (-not $archiveFailure)) { throw 'Recovery evidence is inaccurate.' }
            if (-not $archiveFailure -and [IO.File]::ReadAllText($archive) -cne 'recording-save') { throw 'Successful archive bytes changed.' }
            $checks++
            Write-Output ('PASS recovery prior='+$hadSave+' archive_failure='+$archiveFailure)
        }
    }
} finally {
    # Only the enumerated fixture files; no recursive delete or user save paths.
    foreach ($folder in $caseFolders) {
        foreach ($name in @('active.dat','backup.dat','recorded_quicksave.dat','save_guard.json')) {
            $file=Join-Path $folder $name
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                (Get-Item -LiteralPath $file).IsReadOnly=$false
                Remove-Item -LiteralPath $file
            }
        }
        Remove-Item -LiteralPath $folder
    }
    Remove-Item -LiteralPath $scratch
}
Write-Output ('recording_save_recovery_test: PASS ('+$checks+' cases)')
