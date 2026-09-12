# P1-j CargoManifest arrival tombstone

Date: 2026-08-13 CST

Branch: `codex/p1a-takeover`

Purpose: preserve deterministic same-day arrival idempotence after P1-h retires completed manifests from the live queue.

## Root cause and authority contract

- A manifest id is authored as `manifest_<route>_<day>_<lane-index>`. Before P1-j, `_arrive_import_manifest()` treated only a live `cargo_manifests` key as proof that this id had already arrived.
- P1-h deliberately removes a completed record from `cargo_manifests` and `cargo_manifest_order` after the exact import transaction commits. Replaying the authored lane on the same day therefore recreated the retired id, appended a second `cargo_arrive` receipt and made hard #44 red.
- The append-only canonical arrival receipt is now the idempotence tombstone. One exact `world / route / manifest / good / cargo_arrive:<id>*<batch>` row returns the deterministic id without touching live cargo, event id, event digest, stock or money. This applies while cargo is live and after it retires.
- A conflicting receipt, more than one exact receipt, or a live manifest with no arrival receipt fails closed before any mutation. The invariant layer remains responsible for reporting corrupt history; the arrival path must never worsen it by minting another record.

## Focused teeth

`p1g_manifest_transaction_test` now covers:

- healthy same-day replay while the manifest is live;
- missing arrival proof while a live record exists;
- healthy same-day replay after atomic unload and retirement;
- a route-mutated tombstone;
- duplicate exact tombstones.

Every negative arm snapshots money, stock, events, next event id/digest and both live cargo containers, then proves byte-equivalent JSON state after the rejected call.

## Verification and nominal drift

- Red reproduction: the retired replay returned the same id but resurrected live cargo and a second arrival; focused test exited 1.
- Green focused: `p1g_manifest_transaction_test` and `p1b_cargo_manifest_test` exit 0. Supervised receipts require `native_crash_pattern=false` and `cleanup_verified=true`.
- Standard candidate, seeds 1-12 x 60 days, det3: S0 PASS; hard and soft gates pass; deterministic 3/3.
- Against the preceding P1-i standard receipt, all twelve seeds retain exact `digest`, `event_digest`, `chain`, event count and pass result (`Compare-Object` diff count 0). P1-j therefore changes only abnormal repeated/corrupt arrival calls, not the authored nightly trajectory.

## Player and visual boundary

P1-j changes no player interaction, UI layout, art or renderer. The canonical P1-i player-position frames remain the visual integration reference:

- `docs/media/p1i_east_ocean_player.png`
- `docs/media/p1i_east_ocean_warehouse.png`

Those frames already show the real player, East Ocean vessel, crates, warehouse door, live inventory board and action HUD. Re-capturing identical pixels would add no product evidence for this authority-only fix, so no new pixel golden or presentation asset is introduced.

## Provenance, limits and recovery

- Original repository implementation and tests; no external code/assets or new license obligations.
- Arrival lookup scans the append-only event log. It is deliberately stateless and save-compatible, but its cost grows with retained history; global event retention/indexing remains outside this batch.
- No golden, model-path or complement ledger rebake is authorized here. Rebuild from the P1-j topic commit, run the two focused scenes and the standard Harness grid, then compare S0 rows with the P1-i receipt.
