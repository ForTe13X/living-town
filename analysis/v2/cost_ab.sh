#!/usr/bin/env bash
# V2：4a 那一格换 N 的【成本】—— 交替跑 N=16 与 N=24 各两轮，同一时刻同一台机器同样的并行负载。
# 契约 §5「对照要等量而非等时」+ ci.sh 自己的教训（同一命令两次 239s/291s，噪声比信号的一半还大）
# ⇒ 只报【区间】与【比值】，不报单点。
set -u
GODOT="C:/Users/yp/.local/bin/godot"
OUT="analysis/v2/cost_ab.txt"
: > "$OUT"
for round in 1 2; do
  for N in 16 24; do
    t0=$(date +%s)
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds 1-12 --days 60 --det 1 --agents "$N" > "analysis/v2/cost_r${round}_n${N}.txt" 2>&1
    rc=$?
    t1=$(date +%s)
    verdict=$(grep -o "S0 GATE: [A-Z]*" "analysis/v2/cost_r${round}_n${N}.txt" | head -1)
    echo "round=$round N=$N wall=$((t1-t0))s rc=$rc $verdict" >> "$OUT"
  done
done
echo "DONE" >> "$OUT"
