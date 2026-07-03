<#
.SYNOPSIS
  在真 Godot 4.6.2 里跑 Causal Bench（不变量回归门 + 因果 + 规模 LOD），复用《小鱼岛》(June/22nd) 已构建的镜像。
  起一个【独立的一次性容器】(--rm + 专属名字，只挂 26th 的 game/)，不碰 22nd 的 pipeline / 常驻容器。

.EXAMPLE
  .\tools\bench-godot.ps1                       # S0 不变量门：seeds 1-12 × 60 天，确定性抽 3（批量+增量滚动双摘要）
  .\tools\bench-godot.ps1 -Suite S5             # S5 配对反事实+指标：seeds 1-8 × 40 天
  .\tools\bench-godot.ps1 -Suite Scale          # 规模 LOD 矩阵：N=80(保守+激进双门) + N=160(激进门, 证 cost∝cohort)
  .\tools\bench-godot.ps1 -Suite All            # 跨子套件 CI 门：S0 + S5 + Scale 全过才绿（任一红即退出 1）
  # 退出码 = 0 全过 / 1 任一断言失败。CI 门。
#>
param(
  [ValidateSet("S0","S5","Scale","All")][string]$Suite = "S0",
  [string]$Seeds = "",
  [int]$Days = 0,
  [int]$Det = 3,
  [string]$Image = "gamecraft-runner:4.6.2",
  [string]$Name = "livingtown-bench"
)
$ErrorActionPreference = "Stop"
$game = (Resolve-Path (Join-Path $PSScriptRoot "..\game")).Path -replace '\\', '/'

$script:LastBench = 0
function Run-Bench([string]$cmd) {
  try { docker rm -f $Name 2>$null | Out-Null } catch {}   # 容器不存在时 docker 写 stderr；吞掉，别触发 Stop
  docker run --rm --name $Name -v "${game}:/game" $Image bash -lc $cmd   # 作为语句调用 → 输出直接流到控制台
  $script:LastBench = $LASTEXITCODE                                      # 退出码存脚本作用域，避免被函数返回值/管道污染
}

function Suite-Cmd([string]$s) {
  switch ($s) {
    "S5" {
      $sd = if ($Seeds -ne "") { $Seeds } else { "1-8" }; $d = if ($Days -ne 0) { $Days } else { 40 }
      return "godot --headless --path /game --script res://bench/CausalHarness.gd -- --seeds $sd --days $d 2>&1"
    }
    "S0" {
      $sd = if ($Seeds -ne "") { $Seeds } else { "1-12" }; $d = if ($Days -ne 0) { $Days } else { 60 }
      return "godot --headless --path /game --script res://bench/Harness.gd -- --seeds $sd --days $d --det $Det 2>&1"
    }
  }
}

if ($Suite -eq "Scale") {
  # N=80 双门（保守的 metric-保真档 + 激进档都须过）
  Run-Bench "godot --headless --path /game --script res://bench/LodAblation.gd -- --seeds 1-6 --agents 80 --days 40 --cap 12 --gate both 2>&1"
  $c1 = $script:LastBench
  # N=160 只查激进门（超出保守验证档；证明 cost ∝ cohort 而非 N）
  Run-Bench "godot --headless --path /game --script res://bench/LodAblation.gd -- --seeds 1-3 --agents 160 --days 30 --cap 12 --gate agg 2>&1"
  $c2 = $script:LastBench
  if ($c1 -eq 0 -and $c2 -eq 0) { Write-Host "`n=== SCALE SUITE: PASS (N80 both-gates + N160 aggressive-gate) ==="; exit 0 }
  Write-Host "`n=== SCALE SUITE: FAIL (N80=$c1 N160=$c2) ==="; exit 1
}
elseif ($Suite -eq "All") {
  $fail = @()
  foreach ($s in @("S0","S5")) { Run-Bench (Suite-Cmd $s); if ($script:LastBench -ne 0) { $fail += $s } }
  & $PSCommandPath -Suite Scale -Image $Image -Name $Name
  if ($LASTEXITCODE -ne 0) { $fail += "Scale" }
  if ($fail.Count -eq 0) { Write-Host "`n=== ALL SUITES: PASS (S0 + S5 + Scale) ==="; exit 0 }
  Write-Host "`n=== ALL SUITES: FAIL (red: $($fail -join ', ')) ==="; exit 1
}
else {
  Run-Bench (Suite-Cmd $Suite); exit $script:LastBench
}
