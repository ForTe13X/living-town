# P1-y hosted visual negative tooth

## Goal and delivery boundary

Prove that the P1-x hosted visual canary is sensitive to a real visual regression under the same
GitHub runner, Godot, Mesa/llvmpipe, Xvfb, Python, and assertion code as its positive arm. This is
still a canary-confidence batch, not a golden rebake and not a promotion to a required product
pixel gate. It does not modify `game/`, README, the core `ci` job, or any golden, ModelPath, or
complement anchor.

The positive arm remains observation-only because GitHub's `ubuntu-24.04` image and apt package
revisions roll over time. A passing positive arm now enables one mandatory self-test: if the
known fault is not caught with the expected semantic failure shape, the *canary job* turns red as
a broken measuring instrument. A skipped or failed positive arm records `not_run` instead of
pretending the tooth was exercised.

## Reusable fault fixture

`tools/prepare_visual_canary_negative.py` takes a source `game/` and a new, disjoint destination.
It omits only the rebuildable `.godot` cache, binds the startup `CanvasModulate` construction to
the first subsequent `_modulate.color = _daylight(...)` assignment, and changes that one copied
line to `Color.WHITE`. The source is hashed before and after and must remain byte-identical. The
injector refuses existing destinations, overlapping paths, ambiguous anchors, a changed count of
daylight assignments, or an already-mutated source.

`tools/visual_canary_negative.sh` then uses the existing hardened `vg_shoot` wrapper to render
seed 3 at tick 488 (night) and tick 600 (noon) from the isolated copy on one real X11 framebuffer.
The existing `assert_daynight.py` is the sole ruler. A useful red has this exact shape:

- both framebuffer files are non-empty and both Godot commands return zero;
- the assertion returns one;
- exactly one `FAIL A1`, one `FAIL A2`, and one `DAYNIGHT GATE: FAIL (2)` appear;
- no `SCRIPT ERROR`, signal 11, segmentation fault, fatal error, or out-of-bounds marker appears.

Anything else is `unexpected_failure`, including a crash, missing image, parse error, wrong
assertion, or false green. The receipt, two PNGs, Godot/Xvfb/assertion logs, verdict, and SHA-256
manifest join the positive P1-x artifact for 14 days.

## Acceptance matrix

| Arm | Expected result |
| --- | --- |
| injector contract | exact one-line mutation in a new tree; source hash before/after equal |
| clean positive hosted arm | `VISUAL_CANARY verdict=pass`, non-empty existing framebuffer set |
| same-runtime negative capture | two non-empty 1280x768 frames; no engine/runtime fatal marker |
| semantic tooth | assertion rc 1; exactly A1 + A2 + aggregate `FAIL (2)` |
| false-green control | assertion rc 0 makes `visual_canary` job fail |
| unrelated-red control | shot/parse/crash/wrong-failure shape makes `visual_canary` job fail |
| delivery boundary | core job unchanged; four anchors byte-identical; PR remains Draft/UNSTABLE |

Stop without promotion if the hosted positive arm is not terminal pass, the negative defect is
not caught exactly, the source tree changes, or the hosted raster identity cannot be recorded.
Even after this tooth passes, changing the lane to a required product gate is a separate batch:
it needs an explicit policy for the rolling GitHub image/Mesa revisions and a fresh completed
review over the exact product tree.

## Provenance, version, and limits

- Project-native C3 daylight defect and ruler: `docs/43-wave-c-plan.md`, `docs/41-baton-contract.md`,
  `tools/visual_gate.sh`, and `tools/assert_daynight.py`; no external code copied.
- Runtime identity and upstream sources remain those recorded by P1-x in
  `analysis/p1x/hosted-visual-canary.md` (GitHub `ubuntu-24.04`, official Godot 4.6.2,
  Ubuntu Mesa/Xvfb packages), checked 2026-08-14.
- Fixture schema: `p1y-hosted-visual-negative/v1`.
- Known limit: this tooth proves the hosted lane detects the historical first-frame daylight
  regression. It does not by itself prove every other visual assertion has an equally strong
  negative control, nor does it pin GitHub's raster stack.
