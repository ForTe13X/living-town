#!/usr/bin/env bash
# Same-runtime negative tooth for the hosted visual canary (P1-y).
#
# This deliberately disables the one startup daylight assignment whose absence
# used to make all static shots render as noon. It accepts success only when
# the existing day/night ruler reports the exact A1+A2 failure shape. Capture,
# parse, engine, or framebuffer failures are not accepted as a useful red.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-python3}"
GBIN="${GODOT:-godot}"
SOURCE="${LT_VISUAL_NEG_SOURCE:-$REPO/game}"
WORK="${LT_VISUAL_NEG_WORK:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/visual-negative-game}"
OUT="${LT_VISUAL_NEG_OUT:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/visual-negative-evidence}"
DISP="${LT_VISUAL_NEG_DISPLAY:-:95}"
W=1280
H=768
SEED=3
NIGHT_TICK=488
NOON_TICK=600
TOL="${LT_VISUAL_NEG_TOL:-4}"

mkdir -p "$OUT"
"$PY" "$REPO/tools/prepare_visual_canary_negative.py" "$SOURCE" "$WORK" \
  | tee "$OUT/prepare-receipt.json"
PREP_RC=${PIPESTATUS[0]}
if [ "$PREP_RC" -ne 0 ]; then
  printf 'VISUAL_NEGATIVE verdict=setup_fail prepare_rc=%s\n' "$PREP_RC" \
    | tee "$OUT/negative-verdict.txt"
  exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
export GBIN VG_GODOT_LOG="$OUT/godot.log"
. "$REPO/tools/vg_shoot.sh"
: >"$VG_GODOT_LOG"

Xvfb "$DISP" -screen 0 ${W}x${H}x24 -nolisten tcp >"$OUT/xvfb.log" 2>&1 &
XV=$!
trap 'kill "$XV" 2>/dev/null || true; wait "$XV" 2>/dev/null || true' EXIT
sleep 1.5
export DISPLAY="$DISP"

SHOT_RC=0
vg_shoot "$OUT/negative-night.png" --path "$WORK" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- \
  --backend logic --shot "$OUT/negative-night.png" --seed "$SEED" --warmup-tick "$NIGHT_TICK" --shot-fit \
  || SHOT_RC=1
vg_shoot "$OUT/negative-noon.png" --path "$WORK" --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --resolution ${W}x${H} --single-window -- \
  --backend logic --shot "$OUT/negative-noon.png" --seed "$SEED" --warmup-tick "$NOON_TICK" --shot-fit \
  || SHOT_RC=1

kill "$XV" 2>/dev/null || true
wait "$XV" 2>/dev/null || true
trap - EXIT

ASSERT_RC=99
if [ "$SHOT_RC" -eq 0 ]; then
  set +e
  "$PY" "$REPO/tools/assert_daynight.py" \
    "$OUT/negative-night.png" "$OUT/negative-noon.png" \
    "$NIGHT_TICK" "$NOON_TICK" --tol "$TOL" \
    2>&1 | tee "$OUT/daynight-negative.log"
  ASSERT_RC=${PIPESTATUS[0]}
  set -e
else
  : >"$OUT/daynight-negative.log"
fi

A1_COUNT="$(grep -c 'FAIL A1' "$OUT/daynight-negative.log" 2>/dev/null || true)"
A2_COUNT="$(grep -c 'FAIL A2' "$OUT/daynight-negative.log" 2>/dev/null || true)"
GATE_COUNT="$(grep -c '=== DAYNIGHT GATE: FAIL (2) ===' "$OUT/daynight-negative.log" 2>/dev/null || true)"
RUNTIME_ERRORS="$(grep -Eic \
  'SCRIPT ERROR|signal 11|segmentation fault|fatal error|out of bounds' \
  "$OUT/godot.log" 2>/dev/null || true)"

VERDICT=unexpected_failure
if [ "$SHOT_RC" -eq 0 ] && [ "$ASSERT_RC" -eq 1 ] \
   && [ "$A1_COUNT" -eq 1 ] && [ "$A2_COUNT" -eq 1 ] \
   && [ "$GATE_COUNT" -eq 1 ] && [ "$RUNTIME_ERRORS" -eq 0 ]; then
  VERDICT=caught_expected_daynight_fault
fi

printf 'VISUAL_NEGATIVE verdict=%s shot_rc=%s assert_rc=%s a1=%s a2=%s gate=%s runtime_errors=%s\n' \
  "$VERDICT" "$SHOT_RC" "$ASSERT_RC" "$A1_COUNT" "$A2_COUNT" "$GATE_COUNT" "$RUNTIME_ERRORS" \
  | tee "$OUT/negative-verdict.txt"

find "$OUT" -type f ! -name 'artifacts.sha256' -print0 \
  | sort -z \
  | xargs -0 -r sha256sum >"$OUT/artifacts.sha256"

[ "$VERDICT" = caught_expected_daynight_fault ]
