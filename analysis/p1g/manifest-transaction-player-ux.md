# P1-g CargoManifest transaction + player-facing port status

Date: 2026-08-12 CST

Branch: `codex/p1a-takeover`

Purpose: close the review counterexample where an import payment could survive a later stock failure, and present the same authoritative cargo state to a player standing at the East Ocean dock.

## Transaction contract

- One successful unload owns deterministic `txid=cargo_unload/<manifest_id>`.
- A paid unload emits exactly three adjacent receipts with that txid: `town→external pay(import*N)` → `port_dock→town import(import*N)` → `cargo_unload:<manifest>*N`.
- The commit rechecks worker authorization, manifest/node/state/quantity, whole-batch capacity and funds before mutation. Faults after pay, stock, manifest completion or receipt restore town/external coin, stock/key presence, manifest record, event-log length, next event id and rolling event digest exactly.
- Wage remains an intentionally separate best-effort transaction after cargo commit. A wage failure cannot corrupt the import, and the import does not claim employee compensation as part of money/cargo atomicity.
- Hard invariant #44 now binds txid, strict receipt order and adjacency, manifest identity, node, good, quantity and exact completion. Mutation teeth cover missing txid, wrong cargo quantity, non-adjacent ids and receipt rebinding to another manifest.

## Player / UI / UX contract

- `Sim.cargo_status_for_node()` is a read-only projection of the earliest ready manifest in authored arrival order. It reports `empty`, `ready`, `working`, `blocked_capacity` or `blocked_funds`; UI never owns or copies cargo state.
- The player sees a compact cyan port hint only within three Manhattan cells of `port_dock`. It names the good, quantity, state and responsible dock worker. No fake unload button is added: the current mechanic is an NPC job, while the player can observe its consequences and use the existing seven social actions.
- Canonical presentation is player position `[58,8]`, seed 3, ticks 580/600/620. At 10:00 and 12:00 the hint reads `柴薪×4 待卸·阿涛负责`; at 14:00 it changes to `卸货中`. The vessel, berth crates, player avatar, event feed, needs/coin panel, action bar and timeline remain visible in one 1280×768 composition.
- The hint fits the existing two-line status scrim and uses the established cyan information color, preserving HUD hierarchy: yellow remains player controls, cyan is local system state, right-side panel remains the selected-agent dossier.

## Verification evidence

- `p1g_manifest_transaction_test`: four rollback failpoints + exact retry, tx group and #44 mutations, port-status ready/blocked/working/empty states — PASS.
- Regressions: `p1b_cargo_manifest_test`, `p1c_east_ocean_carrier_test`, `save_migration_test` — PASS.
- Standard S0, seeds 1–12 × 60 days, det3: hard/#40/#44/#45/#46 `12/12`, import/export `156/57` covering `12/12`, deterministic `3/3`, PASS.
- Held-out seeds 13–30 × 60 days, det3: hard/#44/#45/#46 `18/18`; #40 `17/18` (known tolerated seed14); import/export `252/59` covering `18/18`; deterministic `3/3`, PASS.
- Total N24, seeds 1–12 × 60 days, det1: hard/#44/#45/#46 `12/12`; #40 `11/12` (known tolerated seed10); import/export `167/82` covering `12/12`; deterministic `1/1`, PASS. This closes the prior large-N vacuity risk on real scale providers.
- Supervised receipts: standard `20260812T101210211Z_d68b3a20f33e4717adeba894ba85a197`; held-out `20260812T101529623Z_56f69208b2f94c71b174f0a2cacaf56f`; all `cleanup_verified=true`, no native-crash pattern.
- Scale receipt: N24 `20260812T102951349Z_0bdf94515281425fa0fe1a4abee03fee`, `cleanup_verified=true`, no native-crash pattern.
- Real Windows/OpenGL frame receipts: tick580 `20260812T102053244Z_4b4fd2d3f68f4d249a1ed76a2088bee9`; tick600 `20260812T102057480Z_66fccb5c4723456fa6592915bd641a89`; tick620 `20260812T102101516Z_29dd0798dbc44c45bc689ac77327978b`. PNGs live in `%TEMP%/p1g-player-east-ocean-frames`, are `generated/rebuildable`, and are not pixel goldens.
- The first frame attempt exposed a real `Vector2i`/`Array` runtime mismatch; supervisor receipt `20260812T101955944Z_2f27bc6df072429e95122af5d788b89c` failed with `native_crash_pattern`, cleaned the scoped process tree, and was fixed before any visual evidence was accepted.

## Provenance / limitations / recovery

- Code, test and UI copy are original repository work. Existing procedural carrier art, HUD palette/font and Godot pipeline are reused; no external asset or code was copied.
- Screenshots demonstrate stable states across a short sequence. No animation or camera behavior changed, so a new video/GIF would add little evidence; future moving-carrier or player-operated cargo work must use the existing Xvfb/ffmpeg recording lane.
- Manifest records remain append-only and are not compacted in this batch. Golden/modelpath/complement anchors remain stale and were not rebaked; Draft PR #6 is not merge-ready without the authorized exact-tree finalize protocol.
- Rebuild by running the focused scene, standard/held-out Harness grids through `tools/run-godot-supervised.ps1`, then the canonical three `--shot --player-pos 58 8 --select player` frames. Source recovery is by the P1-g topic commit; generated PNGs are optional.
