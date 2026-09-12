#!/bin/sh
# AA1 · 把 k 盲区的【下边缘】夹出来：1.50（Y1 说这一档 N=12 逐字节不动）与 1.55。
# 与 run_kgap.sh 同一条命令、同一个金标，只换隔离副本。
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
SP="$1"
OUT="$2"
mkdir -p "$OUT"
for arm in k1_50 k1_55; do
  (
    cd "$SP/$arm" || exit 1
    "$GODOT" --headless --path game --script res://bench/Harness.gd -- \
      --seeds 1-12 --days 60 --det 1 --golden game/bench/golden_digests.json \
      > "$OUT/$arm.txt" 2>&1
    echo "rc=$? arm=$arm" >> "$OUT/$arm.rc"
  ) &
done
wait
echo "=== kgap2 done ==="
