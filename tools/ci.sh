#!/usr/bin/env bash
# Living Town CI — runs locally and in GitHub Actions. Fails (exit 1) on any red step.
#   GODOT     path to the Godot 4.6.2 headless binary (default: godot on PATH)
#   CI_SEEDS  S0 seed range (default 1-12)      CI_DAYS  S0 days (default 60)   CI_DET  det seeds (default 3)
# Fast local plumbing check: CI_SEEDS=1-3 CI_DAYS=20 bash tools/ci.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
CI_SEEDS="${CI_SEEDS:-1-12}"; CI_DAYS="${CI_DAYS:-60}"; CI_DET="${CI_DET:-3}"
PY="${PYTHON:-python}"
FAIL=0
ok(){ echo "  ✅ $1"; }
bad(){ echo "  ❌ FAIL: $1"; FAIL=1; }

echo "### 1. data lint (json parse + foreign keys)"
"$PY" tools/lint_data.py && ok "lint_data" || bad "lint_data"

echo "### 2. link lint (markdown relative links)"
"$PY" tools/lint_links.py && ok "lint_links" || bad "lint_links"

echo "### 3. godot import + parse smoke"
"$GODOT" --headless --path game --import >/tmp/lt_import.log 2>&1 || true
if grep -qiE 'SCRIPT ERROR|Parse Error|Failed to load script' /tmp/lt_import.log; then
  grep -iE 'SCRIPT ERROR|Parse Error|Failed to load script' /tmp/lt_import.log | head; bad "godot parse"
else ok "import/parse clean"; fi

echo "### 4. S0 gate (invariants + determinism; seeds=$CI_SEEDS days=$CI_DAYS det=$CI_DET)"
"$GODOT" --headless --path game --script res://bench/Harness.gd -- --seeds "$CI_SEEDS" --days "$CI_DAYS" --det "$CI_DET"
[ $? -eq 0 ] && ok "S0 gate" || bad "S0 gate"

echo "### 5. unit / integration scenes"
for scene in m2_test reqlife_test player_agency_test s4_replay_test space_test save_load_test; do
  "$GODOT" --headless --path game "res://scenes/$scene.tscn" >/tmp/lt_$scene.log 2>&1
  code=$?
  if [ $code -eq 0 ]; then ok "$scene"; else tail -8 /tmp/lt_$scene.log; bad "$scene (exit $code)"; fi
done

echo
[ $FAIL -eq 0 ] && echo "=== CI PASS ✅ ===" || echo "=== CI FAIL ❌ ==="
exit $FAIL
