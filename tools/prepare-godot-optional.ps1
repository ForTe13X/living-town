param([string]$GamePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'game'))
$ErrorActionPreference = 'Stop'
$addon = Join-Path $GamePath 'addons/nobodywho'
$descriptor = Join-Path $addon 'nobodywho.gdextension'
if (-not (Test-Path -LiteralPath $descriptor)) { return }
$library = Join-Path $addon 'libnobodywho-godot-x86_64-pc-windows-msvc-release.dll'
$ignore = Join-Path $addon '.gdignore'
$marker = '# Living Town launcher: optional NobodyWho native library is absent.'
$ownedIgnore = (Test-Path -LiteralPath $ignore) -and ([IO.File]::ReadAllText($ignore).Trim() -eq $marker)
$available = (Test-Path -LiteralPath $library) -and ((Get-Item -LiteralPath $library).Length -gt 0)
if ($available) {
    if ($ownedIgnore) { Remove-Item -LiteralPath $ignore }
    return
}
if (-not (Test-Path -LiteralPath $ignore)) {
    [IO.File]::WriteAllText($ignore, $marker + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
# Godot loads this cache before scanning .gdignore. Remove exactly this missing
# optional extension; preserve every other registered extension and its ordering.
$cache = Join-Path $GamePath '.godot/extension_list.cfg'
if (Test-Path -LiteralPath $cache) {
    $lines = [IO.File]::ReadAllLines($cache)
    $kept = @($lines | Where-Object { $_.Trim() -ne 'res://addons/nobodywho/nobodywho.gdextension' })
    if ($kept.Count -ne $lines.Count) {
        [IO.File]::WriteAllLines($cache, $kept, [Text.UTF8Encoding]::new($false))
    }
}
Write-Output 'Optional NobodyWho library is absent; the existing logic/HTTP backends remain available.'
