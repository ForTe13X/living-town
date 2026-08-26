#!/usr/bin/env bash
set -e
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
ROOT="E:/Documents/Dev/June/26th/.claude/worktrees/agent-a88b63618f1e0e767"
cd "$ROOT"
runarm () {
  NAME="$1"
  cp "analysis/e7/prod/${NAME}.json" "game/data/production.json"
  "$GODOT" --headless --path game -s res://bench/ScaleSupply.gd -- \
    --agents 0 --seeds 1-30 --days 60 \
    --out "analysis/e7/runs/${NAME}.jsonl" > "analysis/e7/runs/${NAME}.log" 2>&1
  echo "DONE ${NAME}"
}
for A in clean with arm1_abl_standing arm2_abl_belief arm3_abl_both arm4_dpb_mei; do
  runarm "$A"
done
# restore committed production.json so working tree game/ is clean between analysis
cp "analysis/e7/prod/clean.json" "game/data/production.json"
echo "ALL DONE"
