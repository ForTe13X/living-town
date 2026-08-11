# P1-c East Ocean visible carrier — reusable delivery card

Date: 2026-08-11 (CST)  
Branch: `codex/p1a-takeover`  
Code commit: `c56f31e`  
Purpose: make the existing P1-b CargoManifest causally visible at the user-selected physical East Ocean port without creating a second simulation authority.

## Contract and reusable seams

- Input: authored `logistics.carriers[]`, `Sim.cargo_manifests`, and `Sim.cargo_manifest_order`.
- Pure output: `WorldView.carrier_projections_for(...)` returns at most one projection per authored route/node, bound to the earliest ready manifest; backlog is represented by bounded `ready_count/ready_qty` metadata.
- No output-side mutation: no world object, event, RNG/clock, nav blocker, save field, digest, or chain field is created. Removing only `carriers[]` hides the ship while leaving manifests/events/chain unchanged.
- Physical interface: ocean `x60..63`, freight dock `[56,7,4,2]`, Tao home+spawn/port/berth `[58,8]/[59,8]/[60,8]`; fishing is a separate `north_pier=[30,7,4,2] / bench=[31,7]` with no logistics reference.
- Scale interface: `population_anchor=true` on north_pier and `false` on the East freight dock preserves the historical nine authored clone anchors, their order and centroids. `_area_at()` still sees both areas; the flag only governs N>12 bootstrap placement.
- Visual interface: `--draw-skip carrier` is the negative-control switch. `tools/assert_east_ocean_carrier.py` compares same seed/tick ON/OFF frames and requires a substantial difference localized to the East Ocean berth.

## Decision / rejected alternative

The prior design proposed copying festival spawn/despawn for a carrier. That was rejected for this slice: festivals are ephemeral authored world objects, while a cargo vessel would need to persist exactly as long as a ready manifest and rebind across a FIFO backlog. A second `_carrier_objects` lifecycle would duplicate manifest truth, add load-rebuild/event-order/nav risks, and permit cargo-without-ship or ship-without-cargo drift. A pure derived projection is smaller, loose-coupled, save-safe, and directly testable.

## Verification evidence

- `python tools/lint_data.py`: PASS, 24 JSON files, 13 agents.
- `python tools/audit_map.py`: PASS; walkable 2485, blockers 569, 10 worksites, 13 agents; exact East Ocean cross-file contract active.
- Focused Godot: `p1c_east_ocean_carrier_test` PASS (zero/arrival/FIFO/backlog/save/off/determinism).
- Regressions: `p1a_affiliate_test`, `p1b_cargo_manifest_test`, `space_test`, `save_load_test` PASS.
- Real framebuffer, 1280x768, seed 3, tick 600: carrier ON/OFF diff=443 px, bbox `(948,199)-(979,221)`, outside expected berth crop=0. Same-image negative control returns rc=1.
- Causal matrix: with fishing bench57 at the East dock, `home58/spawn58` failed #40 on seeds17/19/20/27 (`0/4`); home-only changes were byte-identical, while spawn32 made those four green but the full held-out grid then exposed seeds16/24/26. A legal north_pier+bench31 with spawn32 fixed `6/7`; final K (north_pier+bench31, Tao home+spawn58) fixed all seven, with hard/#44/#46 `7/7`, import/export `101/29` over `7/7`. The chosen seam therefore removes the fishing/freight spatial coupling instead of hiding it behind a legacy spawn.
- Final strict-anchor Harness at code commit `c56f31e` (all without golden): default N13 standard PASS (`#40/#44/#46=12/12`, import/export `156/57` over `12/12`, det3/3); held-out 13–30 PASS (`#40=17/18`, sole red seed14, `#44/#46=18/18`, import/export `252/59` over `18/18`, det3/3); total N16 PASS (`#40=12/12`, import `179/12`, det1/1); total N24 PASS (`#40=11/12`, sole red seed10, import `157/12`, det1/1); total N60 PASS (`#40=11/12`, sole red seed12 on the over-supply arm, import `149/12`, det1/1). N16/N24/N60 export remains zero under the existing scale gate, so #46 is explicitly vacuous there.

## Provenance / license / limits

- Code and procedural ship geometry are original project work; no external asset or code was copied. Existing repository palette/font/procedural helpers are reused.
- Godot validation follows the installed pipeline's pinned-engine + real-frame + crash-pattern discipline. Windows Godot 4.6.2 produced the focused ON/OFF pair; the available `gamecraft-runner:4.6.2` Docker/Xvfb path also completed the full visual collection and property assertions.
- The carrier is a docked projection, not a moving ocean voyage simulation. The old north-facing renderer remains a legacy fallback. PNGs are TEMP evidence, not committed goldens.
- Golden digests, modelpath anchor and complement ledger are intentionally not rebaked. Any delivery statement must wait for an authorized committed-tree finalize plus exact-tip CI.

## Hygiene / recovery

- `tools/gen_town.py --write` exposed stale interior templates: it rewrites `interiors.json` beyond this batch. That unrelated output was restored exactly; generator/template reconciliation remains a separate stale-candidate.
- On this Windows host, invoking `visual_gate.sh` through Git Bash captured all frames but the outer assertion phase exited 127 because `python` was absent from Git Bash's PATH. The retained PNG set was passed unchanged to the same 12 Python assertions from PowerShell and every gate passed. Future local runs should export `PYTHON` to the concrete interpreter or reuse this split capture/assert lane; this is runner plumbing, not a visual false-green.
- Rebuild: rerun the focused scene, `audit_map.py`, and the ON/OFF visual fixture. Recovery of source changes is by the P1-c topic commit; no generated PNG is required.
