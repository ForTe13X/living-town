[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RunDir,
  [Parameter(Mandatory)][ValidateRange(0, 999999)][int]$Seq,
  [Parameter(Mandatory)][ValidateSet('key', 'click', 'wait', 'quit')][string]$Action,
  [string]$Code = '',
  [double]$X = -1,
  [double]$Y = -1,
  [ValidateRange(0, 500)][int]$HoldMs = 80,
  [ValidateRange(0, 2000)][int]$SettleMs = 160,
  [ValidateRange(0, 2000)][int]$DurationMs = 0
)

$ErrorActionPreference = 'Stop'
$commands = Join-Path ([IO.Path]::GetFullPath($RunDir)) 'commands'
[IO.Directory]::CreateDirectory($commands) | Out-Null
$name = '{0:D6}.json' -f $Seq
$published = Join-Path $commands $name
if (Test-Path -LiteralPath $published) { throw "Command already exists: $published" }
$command = [ordered]@{
  schema = 'living-town.agent-command/1'
  seq = $Seq
  action = $Action
  settle_ms = $SettleMs
}
switch ($Action) {
  key { $command.code = $Code; $command.hold_ms = $HoldMs }
  click { $command.x = $X; $command.y = $Y }
  wait { $command.duration_ms = $DurationMs }
}
$temporary = $published + '.tmp-' + [guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText($temporary, ($command | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temporary -Destination $published
Write-Output $published
