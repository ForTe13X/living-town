<#
.SYNOPSIS
  在真 Godot 4.6.2 里跑 sim_soak（确定性社交底座的不变量门），复用《小鱼岛》(June/22nd) 已构建的镜像。
  起一个【独立的一次性容器】(--rm + 专属名字，只挂 26th 的 game/)，不碰 22nd 的 pipeline / 常驻容器。

.EXAMPLE
  .\tools\soak-godot.ps1                 # 30 天 seed=20260626
  .\tools\soak-godot.ps1 -Days 60 -Seed 42
  # 退出码 = Godot 的 quit(code)：0=全部不变量通过，1=有断言失败（可当 bench build_check）。
#>
param(
  [int]$Days = 30,
  [int]$Seed = 20260626,
  [string]$Image = "gamecraft-runner:4.6.2",   # 复用 22nd pipeline/Dockerfile 构建出的镜像
  [string]$Name = "livingtown-soak"
)
$ErrorActionPreference = "Stop"
$game = (Resolve-Path (Join-Path $PSScriptRoot "..\game")).Path -replace '\\', '/'
docker rm -f $Name 2>&1 | Out-Null
docker run --rm --name $Name -v "${game}:/game" $Image `
  bash -lc "godot --headless --path /game --script res://scripts/sim_soak.gd -- --days $Days --seed $Seed 2>&1"
exit $LASTEXITCODE
