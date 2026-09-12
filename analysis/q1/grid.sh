#!/usr/bin/env bash
# Q1 派系局部性网格。用法：grid.sh <tag> <N列表> <seed列表>
set -u
ROOT="E:/Documents/Dev/June/26th/.claude/worktrees/agent-ab28d7dd9fe535470"
GODOT="C:/Users/yp/.local/bin/godot"
TAG="$1"; NS="$2"; SEEDS="$3"
OUT="$ROOT/analysis/q1"
mkdir -p "$OUT"
cd "$ROOT/game" || exit 1
for N in $NS; do
  for S in $SEEDS; do
    F="$OUT/${TAG}_n${N}_s${S}.txt"
    "$GODOT" --headless --path . --script bench/q1_faction_probe.gd -- --seed "$S" --days 10 --n "$N" --t0 1200 > "$F" 2>&1
    echo "done $TAG N=$N seed=$S"
  done
done
echo "GRID_DONE $TAG"
