# P1-h CargoManifest live-queue compaction + backlog UX

Date: 2026-08-12 CST

Branch: `codex/p1a-takeover`

Purpose: stop completed cargo records from accumulating forever in the authoritative live queue while preserving a strict, replayable import audit trail and giving the player one compact indication when several deliveries are waiting.

## Authority and transaction contract

- `cargo_manifests` and `cargo_manifest_order` now contain only cargo that can still affect future decisions: positive-quantity `ready` records. A successful unload still commits the P1-g adjacent `pay → import stock → cargo_unload` receipts first, then retires the completed record from both live containers.
- Retirement is part of the atomic boundary. A fifth fault-injection point, `after_retire`, restores town/external money, stock key/value, event log, event id/digest, manifest record and its exact authored order index. An order orphan fails closed without erasing the dictionary record.
- Hard #44 no longer treats a completed live record as historical proof. It reconstructs every completed import from one `cargo_arrive` receipt, one authored import lane and one exact manifest-bound transaction; every arrival must be either a current pending record or an exact completed transaction. Live dictionary/order divergence, duplicates, malformed routes and unverifiable histories are red.
- A 33-day focused run commits eleven imports and proves the live queue returns to empty after each one while all eleven histories remain auditable. This bounds the CargoManifest decision surface; the global append-only `event_log` deliberately remains historical and still grows under its existing retention policy.

## Save compatibility

- Schema remains 2. Older P1-g schema-2 saves may contain `state=complete` records. Loading works on the prepared deep copy and retires such records only when the save itself contains a canonical `manifest_<route>_<day>_<lane>` identity, matching authored lane, unique arrival and exact adjacent transaction receipts.
- Missing proof, a non-canonical identity or an inconsistent receipt rejects the load before touching the receiver. Ready manifests and authorized in-progress unloads retain the established P1-e migration contract.

## Player / UI / visual contract

- `cargo_status_for_node()` still presents the earliest ready manifest, but now also reports `ready_count` and `ready_qty` over the same ordered live queue used by the carrier projection. The top-line hint adds `共N单M件` only for a real backlog greater than one; the common one-manifest composition stays unchanged.
- The focused carrier scene proves a three-manifest queue appears as one vessel and `3单/12件` in both projections, deterministically rebinds after the first completion, and is visually unchanged after that completed record is retired.
- Player-position reference: seed 3, tick 600, player `[58,8]`, selected `player`, 1280×768 real Windows/OpenGL frame. It keeps the avatar, East Ocean vessel, berth crates, NPC ownership hint, event feed, needs/coin dossier, seven social actions and timeline readable in one composition. Later naturally simulated frames were inspected through day 22; no fake backlog was injected for presentation. PNGs are generated/rebuildable under `%TEMP%/p1h-player-east-ocean-frames`, not pixel goldens.

## Verification and causal evidence

- Focused: `p1g_manifest_transaction_test`, `p1b_cargo_manifest_test`, `p1c_east_ocean_carrier_test`, and `save_migration_test` pass under `tools/run-godot-supervised.ps1`; all receipts report `cleanup_verified=true` and no native-crash pattern.
- Candidate standard grid, seeds 1–12 × 60 days, det3: hard and #40/#44/#45/#46 all `12/12`; import/export `156/57`, both covering `12/12`; deterministic `3/3`; PASS.
- Candidate held-out grid, seeds 13–30 × 60 days, det3: hard/#44/#45/#46 `18/18`; #40 `17/18` with known tolerated seed14; import/export `252/59`, both covering `18/18`; deterministic `3/3`; PASS.
- Candidate total N24, seeds 1–12 × 60 days, det1: hard/#44/#45/#46 `12/12`; #40 `11/12`; import/export `167/82`, both covering `12/12`; deterministic `1/1`; PASS.
- Against the preceding P1-g standard receipt, all twelve seeds retain exact `digest`, `event_digest`, event count and pass result. Only `chain` changes, as intended, because completed manifest records no longer remain in future-driving state.
- The first focused candidate exposed a GDScript type-inference parser error and was discarded; an early screenshot command omitted `--player`, producing a fit view rather than player framing, and was likewise not accepted. Both were corrected before evidence was recorded.

## Provenance, limits and recovery

- Implementation, tests and UI copy are original repository work. Existing CargoManifest, carrier art, HUD palette and supervised Godot pipeline are reused; there are no external code/assets or new license obligations.
- This batch compacts completed CargoManifest authority only. It does not compact the global event log, change carrier animation, add player-operated unloading, or authorize golden/modelpath/complement rebakes.
- Rebuild from the P1-h topic commit, run the four focused scenes and the three Harness grids through the supervised runner, then capture `--player --player-pos 58 8 --warmup-tick 600 --select player --shot <abs.png>` on a real framebuffer.
