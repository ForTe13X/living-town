#!/usr/bin/env bash
# W2 · 4a 那一格换 N 的【成本】—— 把 V2 的 cost_ab.sh 从两个 N 扩到三个（16 / 24 / 40）。
#
# 为什么要重跑 N=16 与 N=24（V2 已经量过一次）：
#   V2 那两轮是在【本机另有 20-30 个 godot 在跑】的时候量的，本棒这一轮机器基本空闲
#   ⇒ 绝对秒数不可比。契约 §5「对照要等量而非等时」的落地方式是**交替跑**：
#   三个 N 在同一轮里首尾相接，负载漂移对三者的影响一致 ⇒ **比值可比，绝对秒数不可抄**。
#
# 判决行从文件里 grep（**不用 `tee | tail`**——它会吃掉退出码，契约 §四）。
set -u
GODOT="C:/Users/yp/.local/bin/godot"
OUT="analysis/w2/cost_ab3.txt"
: > "$OUT"
echo "# 交替跑：每一轮里 N=16 → 24 → 40 首尾相接。命令与 ci.sh 4a 同形（不传 --golden，理由见 4a 注释）。" >> "$OUT"
for round in 1 2; do
  for N in 16 24 40; do
    f="analysis/w2/cost_r${round}_n${N}.txt"
    t0=$(date +%s)
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds 1-12 --days 60 --det 1 --agents "$N" > "$f" 2>&1
    rc=$?
    t1=$(date +%s)
    verdict=$(grep -o "S0 GATE: [A-Z]*" "$f" | head -1)
    soft40=$(grep -o "#40 \[软\][^ ]*  *[0-9]*/[0-9]*" "$f" | head -1)
    echo "round=$round N=$N wall=$((t1-t0))s rc=$rc $verdict | $soft40" >> "$OUT"
  done
done
echo "DONE" >> "$OUT"
