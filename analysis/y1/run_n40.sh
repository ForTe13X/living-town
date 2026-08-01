#!/usr/bin/env bash
# Y1 — N=40 arm fleet.  One process per (arm, seed block); unique output path each.
# NOTE: we never kill godot by name — other worktrees have their own running.
cd "$(dirname "$0")"
GODOT=/c/Users/yp/.local/bin/godot
mkdir -p out
PIDS=""
for arm in base null bsoc_05 bsoc_10 bsoc_15 bsoc_20 bsoc_30 ball_10 bnon_10; do
  for blk in 1-12 49-60; do
    f="out/${arm}_n40_s${blk}.txt"
    rm -f "$f"
    "$GODOT" --headless --path "arms/$arm" -s res://bench/x1_margin.gd -- \
      --agents 40 --seeds "$blk" --days 60 > "$f" 2>&1 &
    PIDS="$PIDS $!"
    echo "launched $arm $blk pid=$!"
  done
done
echo "=== waiting on:$PIDS ==="
for p in $PIDS; do wait "$p"; done
echo "=== N40 FLEET DONE ==="
for f in out/*_n40_s*.txt; do
  printf '%-28s lines=%3d  summaries=%d\n' "$f" "$(grep -c '\[X1M\]' "$f")" "$(grep -c 'X1 margin done' "$f")"
done
