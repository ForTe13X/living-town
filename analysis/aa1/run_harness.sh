#!/bin/sh
# AA1 · 门自己的判决行。x1_margin 调的是同一个 Inv.check_all，但**判决行是 Harness 打的**，
# 而"这一格接进 CI 会怎样"这个问题只有判决行能回答（它还跑金标 / 两跑一致 / 活性，x1_margin 一概不跑）。
# 与 W2 §5.1 同一条命令形状；**不传 --golden**，理由与 ci.sh 4a 逐字相同：
#   golden_digests.json 烘在 N=12 上，N≠12 的 digest 与它天生不同。
#   ⇒ 判决行里的「金标」格会印 Z1 修好的那句 `N/A·未传--golden`，那正是它该印的。
# ⚠ 输出写文件再读；`tee | tail` 会吃掉退出码。⚠ godot 退出码在本机是 .cmd 包装，一律按判决行判。
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
ROOT="$1"
OUT="$2"
SEEDS="$3"
TAG="$4"
mkdir -p "$OUT"
cd "$ROOT" || exit 1
for n in 40 48 60; do
  (
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds "$SEEDS" --days 60 --det 1 --agents "$n" \
      > "$OUT/harness_n${n}_${TAG}.txt" 2>&1
    echo "rc=$? n=$n seeds=$SEEDS" >> "$OUT/harness_${TAG}.rc"
  ) &
done
wait
echo "=== harness $TAG done ==="
