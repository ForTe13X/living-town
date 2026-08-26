#!/usr/bin/env bash
# DP-A surgery prototype: run all arms + gates, then analyze — ONE script, one pass (no background-then-exit).
set -e
GODOT="C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
ROOT="E:/Documents/Dev/June/26th/.claude/worktrees/agent-ac413009b49c4b0be"
PY="python"
cd "$ROOT"
D="analysis/dpa"
mkdir -p "$D/runs"
# committed baseline in place (CLEAN, no 饼干) — required for the off-gate golden proof
cp "$D/prod/clean.json" game/data/production.json

echo "### STEP 0 · parse smoke (import) ###" | tee "$D/runs/_progress.txt"
"$GODOT" --headless --path game --import > "$D/runs/import.log" 2>&1 || true
grep -iE 'SCRIPT ERROR|Parse Error|Failed to load script' "$D/runs/import.log" > "$D/runs/parse_errs.txt" 2>&1 || true
if [ -s "$D/runs/parse_errs.txt" ]; then echo "PARSE ERRORS FOUND"; cat "$D/runs/parse_errs.txt"; else echo "parse: clean"; fi

echo "### STEP C · off-gate golden gate (committed clean prod through modified Sim.gd) ###" | tee -a "$D/runs/_progress.txt"
"$GODOT" --headless --path game --script res://bench/Harness.gd -- \
  --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json \
  > "$D/runs/offgate_golden.txt" 2>&1 || true
grep -E "S0 GATE|金标" "$D/runs/offgate_golden.txt" | tail -3

runarm () {
  NAME="$1"; N="$2"; SEEDS="$3"
  cp "$D/prod/${NAME%%_n16}.json" game/data/production.json 2>/dev/null || cp "$D/prod/${NAME}.json" game/data/production.json
  echo "### run ${NAME} (agents=$N seeds=$SEEDS) ###" | tee -a "$D/runs/_progress.txt"
  "$GODOT" --headless --path game -s res://bench/ScaleSupply.gd -- \
    --agents "$N" --seeds "$SEEDS" --days 60 \
    --out "$D/runs/${NAME}.jsonl" > "$D/runs/${NAME}.log" 2>&1
  echo "DONE ${NAME}"
}

# N=12 core arms, seeds 1-30 (held-out 13-30 for anchors)
runarm clean   0 1-30
runarm with    0 1-30
runarm dpa     0 1-30
# N=16 4a coexistence check for DP-A (seeds 1-12)
cp "$D/prod/dpa.json" game/data/production.json
echo "### run dpa_n16 (agents=16 seeds=1-12) ###" | tee -a "$D/runs/_progress.txt"
"$GODOT" --headless --path game -s res://bench/ScaleSupply.gd -- \
  --agents 16 --seeds 1-12 --days 60 --out "$D/runs/dpa_n16.jsonl" > "$D/runs/dpa_n16.log" 2>&1
echo "DONE dpa_n16"

# restore committed production.json so working-tree game/ has no data change
cp "$D/prod/clean.json" game/data/production.json

echo "### ANALYSIS ###" | tee -a "$D/runs/_progress.txt"
R="$D/RESULTS.txt"
{
  echo "############ DP-A PROBE RESULTS (held-out 13-30, N=12 unless noted) ############"
  echo
  echo "======== PROBE C · off-gate golden (committed clean prod through modified Sim.gd) ========"
  grep -E "S0 GATE|金标|hash 自检|哈希自检" "$D/runs/offgate_golden.txt" | tail -4
  echo "byte-check: clean.jsonl seed1 digest should == committed golden 3894698000"
  $PY -c "import json; d=[json.loads(l) for l in open('$D/runs/clean.jsonl',encoding='utf-8') if l.strip()]; s1=[x for x in d if x['seed']==1][0]; print('  clean seed1 digest =', s1['digest'], '->', 'MATCH' if s1['digest']=='3894698000' else 'MISMATCH')"
  echo
  echo "======== PROBE A · core neutrality (DP-A vs CLEAN) ========"
  $PY "$D/anchor.py" "$D/runs/clean.jsonl" "$D/runs/dpa.jsonl" 13 30 "DP-A"
  echo
  echo "-------- sanity: WITH vs CLEAN (should reproduce E7 -0.046 dilution) --------"
  $PY "$D/anchor.py" "$D/runs/clean.jsonl" "$D/runs/with.jsonl" 13 30 "WITH"
  echo
  echo "======== ATTRIBUTION (口粮 held-out Δ + paired DP-A recovery vs WITH) ========"
  $PY "$D/attribute.py" "$D/runs/clean.jsonl" "$D/runs/with.jsonl" "$D/runs/dpa.jsonl" 13 30
  echo
  echo "======== PROBE B · drama preserved (DP-A held-out 13-30) ========"
  $PY "$D/probe_b.py" "$D/runs/dpa.jsonl" 13 30 饼干
  echo
  echo "======== PROBE D · #40 coexistence (CLEAN vs DP-A, seeds 1-12 N=12) ========"
  $PY "$D/inv40.py" "$D/runs/clean.jsonl" "$D/runs/dpa.jsonl" 1 12
  echo
  echo "-------- #40 4a: DP-A N=16 seeds 1-12 (soft gate >=11/12) --------"
  $PY -c "import json; d=[json.loads(l) for l in open('$D/runs/dpa_n16.jsonl',encoding='utf-8') if l.strip()]; ok=sum(1 for x in d if x.get('inv40_ok')); hf=[x['seed'] for x in d if x.get('hard_fails')]; print('  inv40_ok %d/%d, seeds with hard_fail: %s'%(ok,len(d),hf or 'NONE'))"
  echo
  echo "======== PROBE E · hard invariants (DP-A seeds 1-30 N=12) ========"
  $PY "$D/hardinv.py" "$D/runs/dpa.jsonl" 1 30
  echo
  echo "############ END ############"
} > "$R" 2>&1
cat "$R"
echo "ALL DONE -> $R"
