#!/usr/bin/env bash
# Y1 — §2.5 `detects` must be MEASURED. Does the (rebaked) DetGate anchor actually go red
# when the intervention is removed / widened / overdosed?
# Each arm gets the NEW (rebaked) golden_digests.json so the comparison reference is the shipped one.
cd "$(dirname "$0")"
REPO=E:/Documents/Dev/June/26th/.claude/worktrees/agent-a69d11c522a1efb5b
GODOT=/c/Users/yp/.local/bin/godot
mkdir -p out
PIDS=""
for arm in bmin_00 ball_10 bmin_20 bnon_10; do
  cp "$REPO/game/bench/golden_digests.json" "arms/$arm/bench/golden_digests.json"
  f="out/negctl_detgate_$arm.txt"; rm -f "$f"
  "$GODOT" --headless --path "arms/$arm" --script res://bench/DetGate.gd -- \
    --seeds 1-4 --days 20 > "$f" 2>&1 &
  PIDS="$PIDS $!"; echo "launched DetGate $arm pid=$!"
done
for p in $PIDS; do wait "$p"; done
echo "=== DETGATE NEG-CTL DONE ==="
for arm in bmin_00 ball_10 bmin_20 bnon_10; do
  printf '%-10s %s\n' "$arm" "$(grep -h 'DetGate:' out/negctl_detgate_$arm.txt)"
  grep -h '金标=❌' "out/negctl_detgate_$arm.txt" | sed 's/^/            /'
done
