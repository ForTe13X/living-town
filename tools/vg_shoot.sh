#!/usr/bin/env bash
# vg_shoot.sh — 硬化的 Godot 拍帧封装（AK1，外审 2026-08-06 P0.5 点名的 fail-open 修复）。
#
# 为什么存在：visual_gate.sh 原来多处按 `if [ -s "$OUT/x.png" ]`（只看图【存在且非空】）判"拍成功"。
# 外审证伪那是 fail-open：**godot 崩了但残留旧图 / 写了半张再崩 / push_error 之后仍退 0
# （ci.sh 抬头明写：GDScript 的 push_error() 不改变进程退出码）**——这几种都会被旧判据读成"拍好了"。
# 本封装把【三个信号】结合，任一不过即判这一帧失败（并打印指向真正病因的原因，不误导）：
#   ① 子进程退出码 rc==0     —— 抓"进程非零退出"。容器里 godot 是真二进制，rc 可信；这是主判据。
#   ② 日志无致命错误标记     —— 抓"rc 不可信的环境（本机 godot.cmd）里报了 SCRIPT ERROR 却退 0"。
#   ③ --shot 落盘的图非空    —— 抓"rc==0 且无报错，但根本没写出图"（旧判据唯一看的那一条，保留）。
#
# ⚠️ 错误标记刻意【不含裸 ERROR:】：gamecraft-runner 容器缺 nobodywho GDExtension，每次开场固定打
#    几行 `Error loading extension` / `Condition "!FileAccess::exists(path)" is true ... open_dynamic_library`
#    ——那是良性的（与 ci.sh 的 ERR_OK 白名单同一批噪声）。只认真正的脚本/引擎级失败标记，
#    否则每一帧都会假红。绿跑一轮核过：clean 帧的日志里这些标记 0 命中。
#
# 用法：先 `. tools/vg_shoot.sh`，再 `vg_shoot <outfile.png> <godot 参数...>`。
#   需要环境里有 $GBIN（godot 可执行；缺省 godot）。日志追加到 ${VG_GODOT_LOG:-/tmp/vg-godot.log}。
#   成功回 0 并打印 "  shot ok   <name>"；失败回 1 并打印 "  shot FAIL <name> (原因)"。
#   调用点自己把非零返回折进它的 rc（visual_gate.sh 用 `|| { [ "$rc" -eq 0 ] && rc=N; }`）。

# 致命标记：一律是真正的脚本/引擎级失败，clean 帧不会打；nobodywho 的良性 ERROR:/Condition 不在内。
VG_GERR='SCRIPT ERROR|USER ERROR|Parse Error|Failed to load script|Failed to instantiate|Segmentation fault|core dumped|Aborted'

vg_shoot() {  # vg_shoot <outfile> <godot args...>
  local out="$1"; shift
  local log="${VG_GODOT_LOG:-/tmp/vg-godot.log}"
  local nm; nm="$(basename "$out")"
  rm -f "$out"                                   # 先删旧图：不让上一轮的残留冒充这一轮的产出
  local slog; slog="$(mktemp 2>/dev/null || echo "/tmp/vgshot-$$-${RANDOM}.log")"
  "${GBIN:-godot}" "$@" >"$slog" 2>&1
  local grc=$?
  cat "$slog" >>"$log" 2>/dev/null               # 汇进共享日志：失败时上层 tail 得到它
  local err; err="$(grep -aE "$VG_GERR" "$slog" 2>/dev/null | head -1)"
  rm -f "$slog"
  if [ "$grc" -ne 0 ]; then
    echo "  shot FAIL $nm (godot rc=$grc —— 子进程非零退出，判红)"; return 1
  fi
  if [ -n "$err" ]; then
    echo "  shot FAIL $nm (godot 日志含致命错误标记: ${err})"; return 1
  fi
  if [ ! -s "$out" ]; then
    echo "  shot FAIL $nm (rc=0 且无报错，但 --shot 产图为空/缺失)"; return 1
  fi
  echo "  shot ok   $nm"; return 0
}
