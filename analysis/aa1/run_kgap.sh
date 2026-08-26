#!/bin/sh
# AA1 · Z1 明写的盲区：k ∈ (1.5, 1.8519) 这一段【金标那一侧】没人量过。
# Z1 §六.2 原话：「在 k=1.6 / 1.7 上跑 `Harness --seeds 1-12 --days 60 --golden`，看金标那一侧拦不拦得住。」
# 本脚本把那一段夹起来跑：1.6 / 1.7 / 1.8 / 1.85（1.85 的比值 0.99900，是 #42 咬合点【下方】的最后一档）。
# ⚠ 全部在【仓库之外】的隔离副本里跑；工作树的 game/** 一个字节不碰。
# ⚠ 输出写文件再读 —— `tee | tail` 会吃掉退出码（docs/41）。
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
SP="$1"     # 隔离副本的父目录
OUT="$2"    # 输出目录
mkdir -p "$OUT"
for arm in kbase k1_60 k1_70 k1_80 k1_85; do
  (
    cd "$SP/$arm" || exit 1
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds 1-12 --days 60 --det 1 --golden game/bench/golden_digests.json \
      > "$OUT/$arm.txt" 2>&1
    echo "rc=$? arm=$arm" >> "$OUT/$arm.rc"
  ) &
done
wait
echo "=== kgap done ==="
