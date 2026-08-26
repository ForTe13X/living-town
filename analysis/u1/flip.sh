#!/usr/bin/env bash
# U1：故意复现 T1 那条「同 seed 两跑分歧」——在 DetGate 跑到一半时把 production.stock_pull 摘掉。
# DetGate._run 每一跑都调 S._load_data() 重读磁盘 ⇒ 两跑之间改数据 = 两跑读到两份世界。
set -u
ROOT="$1"; DELAY="$2"; OUT="$3"
GODOT="C:/Users/yp/.local/bin/godot"
python "$ROOT/_u1scratch/setkey.py" "$ROOT/_u1scratch/g_flip" 110 90 100
"$GODOT" --headless --path "$ROOT/_u1scratch/g_flip" --script res://bench/DetGate.gd -- --seeds 1 --days 20 >"$OUT" 2>&1 &
PID=$!
sleep "$DELAY"
python "$ROOT/_u1scratch/setkey.py" "$ROOT/_u1scratch/g_flip" off
echo "[flip] key removed at t=${DELAY}s" >>"$OUT"
wait $PID
echo "[flip] exit=$?" >>"$OUT"
