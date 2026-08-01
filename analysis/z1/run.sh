#!/usr/bin/env bash
# Z1 负对照跑批。⚠ 不用 `tee | tail`（会吃掉退出码，docs/41）：写文件再读。
set -u
GODOT="C:/Users/yp/.local/bin/godot"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO="$ROOT/.z1iso"
SEEDS="${SEEDS:-1}"
DAYS="${DAYS:-20}"
for m in "$@"; do
  d="$ISO/$m"
  [ -d "$d/game" ] || { echo "$m: 没有这个副本"; continue; }
  ( cd "$d" && "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds "$SEEDS" --days "$DAYS" --det 0 > "$ISO/out_$m.txt" 2>&1 )
  rc=$?
  echo "── $m  rc=$rc"
  grep -h "#42" "$ISO/out_$m.txt" | sed 's/^/    /'
  grep -h "首违\|hard_fails" "$ISO/out_$m.txt" | grep -i "42\|hard_fails" | head -3 | sed 's/^/    /'
  grep -h "S0 GATE" "$ISO/out_$m.txt" | sed 's/^/    /'
done
