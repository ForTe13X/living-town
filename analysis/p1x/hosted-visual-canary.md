# P1-x hosted visual canary

## Goal and boundary

Close the evidence gap where GitHub Actions deliberately reports the visual gate as `SKIP`
because its native GL stack was not identified. This batch is an observation lane, not an anchor
rebake and not yet a required pixel-golden gate. It changes only the CI workflow and this resource
card; it does not modify `game/`, README, any golden/ModelPath/complement anchor, a protected
branch, or the independent review worktree.

## Runtime contract

The new `visual_canary` job runs in parallel with the unchanged core `ci` job. It selects
`ubuntu-24.04` explicitly, installs the minimal Mesa GLX software stack plus Xvfb, and emits one
rebuildable runtime receipt containing:

- GitHub runner image OS/version/architecture;
- the Godot 4.6.2 archive/executable SHA-256 and reported version;
- the exact hosted Python and Pillow versions used by the assertion readers;
- exact dpkg versions for `libgl1`, `libglx-mesa0`, `libgl1-mesa-dri`, `mesa-utils`, `xauth`, and
  `xvfb`;
- `glxinfo -B` under Xvfb with `LIBGL_ALWAYS_SOFTWARE=1`.

`tools/visual_gate.sh` is reused unchanged with `LT_VISUAL_RUNNER=native` and `LT_VISUAL=auto`.
That distinction is intentional for the first hosted observation:

- when frames render, all existing property assertions remain hard and return 0/1 normally;
- when the native capture itself cannot start, the existing script returns the explicit skip code
  77 instead of inventing a product failure;
- the canary output, framebuffer set, and `visual.log` are uploaded for 14 days even though the
  core job currently ends red on the four intentionally stale anchors.

The canary preserves its first product verdict as `pass`, `skip`, or `candidate_fail` together
with the raw return code, PNG count, runtime-error count, complete log, and artifact SHA-256
manifest. That observation does not yet change merge policy: the canary command exits zero after
recording any product verdict, while checkout, dependency installation, fingerprinting, or
artifact-upload failures still make the job red. Keeping this work in a separate job prevents the
frame collection from consuming the core job's existing 35-minute budget.

Promotion to `LT_VISUAL=require` is a later, separate decision. It requires a terminal hosted run
showing a stable software renderer, complete non-empty framebuffer artifacts, every visual
assertion passing, no `SCRIPT ERROR`, signal 11, fatal, or out-of-bounds line, and a negative tooth
that fails for the intended visual defect under the same runtime. This batch does not weaken the
existing pinned local `gamecraft-runner:4.6.2` / Mesa 23.2.1 / tolerance-zero lane.

## Acceptance matrix

| Arm | Expected result |
| --- | --- |
| workflow syntax/data lint | parse cleanly; core job unchanged; no unrelated workflow or game edit |
| hosted identity | PR head, synthetic merge parents, and `HEAD:game` remain exact |
| runtime fingerprint | image, Godot hash/version, six package versions, and GL renderer printed |
| native canary positive | `verdict=pass`; non-empty PNG set; property gates pass; hash manifest uploaded |
| unavailable renderer | explicit `VISUAL GATE SKIP` / rc 77, never silently labeled PASS |
| product/runtime error scan | no undeclared `SCRIPT ERROR`, signal 11, fatal, or out-of-bounds |
| delivery boundary | PR remains Draft/UNSTABLE; anchors remain byte-identical |

Stop and revert this batch if package installation cannot be reproduced, if the canary perturbs
the core job or simulation results, or if its evidence cannot be downloaded and classified. An
empty artifact set or renderer-dependent assertion failure is preserved as `candidate_fail` and
blocks later promotion to `require`; it is not mislabeled as a passed visual gate.

## Provenance

- GitHub `actions/runner-images`, checked 2026-08-14: the explicit `ubuntu-24.04` label avoids a
  future `ubuntu-latest` OS migration, while GitHub still updates that image on a regular cadence.
  Source: <https://github.com/actions/runner-images>
- GitHub Ubuntu 24.04 inventory, checked 2026-08-14: image metadata and installed-software source.
  Source: <https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md>
- Godot 4.6.2 stable release, checked 2026-08-14: official maintenance release used by the
  existing workflow. Source: <https://github.com/godotengine/godot/releases/tag/4.6.2-stable>

No external art, code, or asset license enters the product. The workflow composes existing GitHub,
Ubuntu, Mesa, Xvfb, and official Godot runtime components and records their exact hosted identity.
