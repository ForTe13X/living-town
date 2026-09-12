#!/usr/bin/env bash
set -u
G="C:/Users/yp/.local/bin/godot"
cd "$(dirname "$0")/../.."
tag="$1"; shift
"$G" --headless --path game -s res://bench/w1_pact_clock.gd -- \
    --agents 12 --seeds 1-12 --days 60 "$@" > "analysis/w1/clock_${tag}.txt" 2>&1
echo "clock_${tag} rc=$?" >> analysis/w1/rc.txt
