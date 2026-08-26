#!/usr/bin/env bash
# trusted_cafe_capture.sh
#
# This script belongs to the protected trust root, not to the candidate tree.
# It treats candidate/game as untrusted input, controls every capture argument,
# records the renderer/toolchain identity, and emits a canonical manifest. The
# caller must attest the final tarball; hashes stored beside untrusted evidence
# are not an authentication boundary by themselves.
set -euo pipefail

usage() {
  echo "usage: $0 <candidate-root> <output-dir> <candidate-sha> <workflow-sha> <repository>" >&2
  exit 2
}

[ "$#" -eq 5 ] || usage
CANDIDATE_ROOT="$(cd "$1" && pwd)"
OUT="$2"
CANDIDATE_SHA="$3"
WORKFLOW_SHA="$4"
REPOSITORY="$5"
TRUSTED_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GBIN="${GODOT:-godot}"
PY="${PYTHON:-python3}"

[[ "$CANDIDATE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid candidate SHA" >&2; exit 2; }
[[ "$WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid workflow SHA" >&2; exit 2; }
[ -f "$CANDIDATE_ROOT/game/project.godot" ] || { echo "candidate game missing" >&2; exit 2; }
[ ! -e "$OUT" ] || { echo "output path already exists: $OUT" >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GODOT_SILENCE_ROOT_WARNING=1
export VG_GODOT_LOG="$OUT/godot-capture.log"
: >"$VG_GODOT_LOG"
GBIN="$GBIN"
. "$TRUSTED_ROOT/tools/vg_shoot.sh"

SEED=3
TICK=600
SPACE=cafe

capture_viewport() ( # width height display
  local width="$1" height="$2" display="$3"
  local viewport="${width}x${height}"
  local dir="$OUT/$viewport"
  mkdir -p "$dir"

  Xvfb "$display" -screen 0 "${width}x${height}x24" -nolisten tcp \
    >"$OUT/xvfb-$viewport.log" 2>&1 &
  local xv=$!
  trap 'kill "$xv" 2>/dev/null || true' EXIT
  sleep 1.5
  export DISPLAY="$display"

  local slot floor mode filename
  local -a draw_skip
  for slot in cafe_1f_normal cafe_1f_bare cafe_2f_normal cafe_2f_bare; do
    case "$slot" in
      cafe_1f_normal) floor=1f; mode=normal; filename=vg_int_cafe.png ;;
      cafe_1f_bare)   floor=1f; mode=bare;   filename=vg_cafe1f_bare.png ;;
      cafe_2f_normal) floor=2f; mode=normal; filename=vg_cafe2f.png ;;
      cafe_2f_bare)   floor=2f; mode=bare;   filename=vg_cafe2f_bare.png ;;
    esac
    draw_skip=()
    [ "$mode" = normal ] || draw_skip=(--draw-skip interior_furniture)
    if ! vg_shoot "$dir/$filename" \
      --path "$CANDIDATE_ROOT/game" \
      --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
      --resolution "$viewport" --single-window -- \
      --backend logic --seed "$SEED" --warmup-tick "$TICK" \
      --probe-space "$SPACE" --probe-floor "$floor" --shot-fit \
      "${draw_skip[@]}" --shot "$dir/$filename"; then
      return 1
    fi
  done

  kill "$xv" 2>/dev/null || true
  wait "$xv" 2>/dev/null || true
  trap - EXIT

  "$PY" - "$dir" "$viewport" "$CANDIDATE_SHA" "$WORKFLOW_SHA" "$REPOSITORY" "$CANDIDATE_ROOT/game" <<'PY'
import hashlib, json, os, struct, sys, tempfile

root, viewport, candidate_sha, workflow_sha, repository, candidate_game = sys.argv[1:]
width, height = (int(v) for v in viewport.split("x", 1))
slots = [
    ("cafe_1f_normal", "vg_int_cafe.png", "1f", "normal", "none"),
    ("cafe_1f_bare", "vg_cafe1f_bare.png", "1f", "bare", "interior_furniture"),
    ("cafe_2f_normal", "vg_cafe2f.png", "2f", "normal", "none"),
    ("cafe_2f_bare", "vg_cafe2f_bare.png", "2f", "bare", "interior_furniture"),
]

captures = []
seen = set()
session = hashlib.sha256((candidate_sha + workflow_sha + viewport).encode("ascii")).hexdigest()[:32]
for slot, filename, floor, mode, draw_skip in slots:
    path = os.path.join(root, filename)
    data = open(path, "rb").read()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"invalid PNG: {filename}")
    actual_width, actual_height = struct.unpack(">II", data[16:24])
    if (actual_width, actual_height) != (width, height):
        raise SystemExit(f"wrong PNG dimensions: {filename}")
    digest = hashlib.sha256(data).hexdigest()
    if digest in seen:
        raise SystemExit(f"duplicate capture payload: {filename}")
    seen.add(digest)
    argv = [
        "--path", candidate_game,
        "--display-driver", "x11", "--rendering-driver", "opengl3",
        "--audio-driver", "Dummy", "--resolution", viewport,
        "--single-window", "--", "--backend", "logic", "--seed", "3",
        "--warmup-tick", "600", "--probe-space", "cafe",
        "--probe-floor", floor, "--shot-fit",
    ]
    if draw_skip != "none":
        argv += ["--draw-skip", draw_skip]
    argv += ["--shot", path]
    captures.append({
        "session": session,
        "slot": slot,
        "file": filename,
        "space": "cafe",
        "floor": floor,
        "mode": mode,
        "draw_skip": draw_skip,
        "width": width,
        "height": height,
        "seed": 3,
        "tick": 600,
        "argv": argv,
        "argv_sha256": hashlib.sha256(json.dumps(argv, separators=(",", ":"), ensure_ascii=True).encode("ascii")).hexdigest(),
        "sha256": digest,
        "bytes": len(data),
    })

receipt = {
    "schema": "cafe-density-receipt-v2",
    "source": "visual_gate.sh",
    "trust_schema": "trusted-cafe-capture-receipt-v1",
    "repository": repository,
    "candidate_sha": candidate_sha,
    "trusted_workflow_sha": workflow_sha,
    "viewport": viewport,
    "session": session,
    "captures": captures,
}
fd, tmp = tempfile.mkstemp(prefix=".receipt-", dir=root)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
    json.dump(receipt, f, sort_keys=True, separators=(",", ":"))
    f.write("\n")
os.replace(tmp, os.path.join(root, "cafe_density_receipt.json"))
PY
)

capture_viewport 1280 768 :95
capture_viewport 320 192 :96

# The candidate verifier is a product assertion, not the provenance root. Its
# exact bytes are nevertheless bound into the signed manifest for reviewers.
for viewport in 1280x768 320x192; do
  "$PY" "$CANDIDATE_ROOT/tools/assert_cafe_interior_density.py" "$OUT/$viewport" \
    | tee "$OUT/density-$viewport.log"
done
"$PY" "$CANDIDATE_ROOT/tools/assert_cafe_2f.py" "$OUT/1280x768" \
  | tee "$OUT/cafe2f-1280x768.log"

runtime_errors="$(grep -aEic \
  'SCRIPT ERROR|signal 11|segmentation fault|fatal error|out of bounds' \
  "$VG_GODOT_LOG" || true)"
[ "$runtime_errors" -eq 0 ] || { echo "runtime error markers: $runtime_errors" >&2; exit 1; }

"$PY" - "$OUT" "$CANDIDATE_ROOT" "$TRUSTED_ROOT" "$CANDIDATE_SHA" "$WORKFLOW_SHA" "$REPOSITORY" <<'PY'
import hashlib, json, os, platform, subprocess, sys, tempfile

out, candidate, trusted, candidate_sha, workflow_sha, repository = sys.argv[1:]

def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

payloads = []
for root, dirs, files in os.walk(out):
    dirs.sort()
    for name in sorted(files):
        if name in ("trusted-cafe-manifest.json", "trusted-cafe-evidence.tar.gz"):
            continue
        path = os.path.join(root, name)
        rel = os.path.relpath(path, out).replace(os.sep, "/")
        payloads.append({"path": rel, "sha256": digest(path), "bytes": os.path.getsize(path)})

def text(cmd):
    return subprocess.check_output(cmd, text=True).strip()

tool_paths = [
    os.path.join(trusted, "tools", "trusted_cafe_capture.sh"),
    os.path.join(trusted, "tools", "vg_shoot.sh"),
    os.path.join(candidate, "tools", "assert_cafe_interior_density.py"),
    os.path.join(candidate, "tools", "assert_cafe_2f.py"),
]
manifest = {
    "schema": "trusted-cafe-evidence-manifest-v1",
    "repository": repository,
    "candidate_sha": candidate_sha,
    "trusted_workflow_sha": workflow_sha,
    "trusted_workflow": ".github/workflows/trusted-cafe-attestation.yml",
    "capture_contract": {
        "space": "cafe", "viewports": ["1280x768", "320x192"],
        "seed": 3, "tick": 600, "renderer": "opengl3",
        "display": "x11/Xvfb", "audio": "Dummy",
        "slots": ["cafe_1f_normal", "cafe_1f_bare", "cafe_2f_normal", "cafe_2f_bare"],
    },
    "runtime": {
        "python": platform.python_version(),
        "godot": text([os.environ.get("GODOT", "godot"), "--version"]),
        "runner_image_os": os.environ.get("ImageOS", "unknown"),
        "runner_image_version": os.environ.get("ImageVersion", "unknown"),
        "runner_arch": os.environ.get("RUNNER_ARCH", "unknown"),
    },
    "tools": [{"path": os.path.relpath(p, trusted if p.startswith(trusted) else candidate).replace(os.sep, "/"),
               "authority": "trusted" if p.startswith(trusted) else "candidate",
               "sha256": digest(p)} for p in tool_paths],
    "payloads": payloads,
}
fd, tmp = tempfile.mkstemp(prefix=".manifest-", dir=out)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
    json.dump(manifest, f, sort_keys=True, separators=(",", ":"))
    f.write("\n")
os.replace(tmp, os.path.join(out, "trusted-cafe-manifest.json"))
PY

bundle_tmp="$(dirname "$OUT")/.trusted-cafe-evidence.$$.tar.gz"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -czf "$bundle_tmp" -C "$OUT" .
mv "$bundle_tmp" "$OUT/trusted-cafe-evidence.tar.gz"
sha256sum "$OUT/trusted-cafe-evidence.tar.gz" "$OUT/trusted-cafe-manifest.json"
echo "TRUSTED_CAFE_CAPTURE PASS candidate=$CANDIDATE_SHA workflow=$WORKFLOW_SHA"
