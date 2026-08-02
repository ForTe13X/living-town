#!/bin/sh
# AA1 · 金标覆盖的【下边缘】：1.10 / 1.25。
# 由来：1.50 出乎意料地已经破金标（Y1 在【它那棵树】上量的是 1.5 逐字节不动），
# ⇒ "金标从哪一档开始拦得住"这个问题在今天这棵树上还没有答案，而它比 (1.5,1.852) 那一段更有用。
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
SP="$1"
OUT="$2"
mkdir -p "$OUT"
for arm in k1_10 k1_25; do
  (
    cd "$SP/$arm" || exit 1
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds 1-12 --days 60 --det 1 --golden game/bench/golden_digests.json \
      > "$OUT/$arm.txt" 2>&1
    echo "rc=$? arm=$arm" >> "$OUT/$arm.rc"
  ) &
done
wait
echo "=== kgap3 done ==="
