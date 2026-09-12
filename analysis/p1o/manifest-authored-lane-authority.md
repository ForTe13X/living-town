# P1-o authored CargoManifest lane authority

Status: candidate verified on 2026-08-13; not an anchor rebake or merge receipt.

## Purpose and contract

P1-o closes one authority gap: a pending CargoManifest previously proved only its own shallow
shape.  A schema-1/2 save or live record could change route, node, good, quantity, arrival day,
or price while still reaching unload commit.  One pure validator now binds every record to the
same saved/live `logistics.import_lanes[lane_index]` contract:

- strict String/int field types;
- lane exists and is well formed;
- canonical `manifest_<route>_<arrival-day>_<lane-index>` identity;
- route, node, good, whole batch, price numerator/denominator match the authored lane;
- `1 <= arrived_day <= current day` and `arrived_day % every_days == 0`;
- ready cargo remains a whole authored batch; complete cargo remains zero.

The validator is deterministic, side-effect free, dictionary-order independent, and uses only
integer operations.  It is consumed by arrival construction, save/load validation, legacy
complete-record compaction, unload candidate selection, atomic commit preflight, hard #44, player
port/warehouse status, and the exterior carrier projection.  It validates against the save's own
logistics snapshot during load; this preserves transitional schema-1 self-consistency and does not
silently substitute today's repository data.

Invalid live cargo is explicit rather than disguised as empty: gameplay candidates and commit are
zero, the carrier disappears, and player UI shows `货单异常·暂停卸货` without exposing the bad
manifest id, good, quantity, price, or worker.  No per-frame error is logged.

## Adversarial teeth

`p1g_manifest_transaction_test` mutates one field at a time across id, route, lane index, node,
good, arrival day, initial/remaining quantity, both price fields, and String/int type confusion.
Each live arm requires invalid player projection, zero candidate/commit, exact money/stock/cargo/
event/id/digest preservation, hard #44 red, and recovery after restoring the field.  Each offline
schema-2 arm mutates a valid envelope and must make `peek_save` empty and be rejected before a
polluted quickload receiver is touched.  A coherent dictionary-key/order/record-id rekey is a
separate negative control.  Future-day and off-cadence canonical ids are separate teeth.  Exact
arrival receipts also cover actor, target, subject, accepted and note/quantity mutations at load
and hard-#44 time.

The existing P1-n runtime-error profile remains unchanged: offline load rejection is warning-only,
commit corruption is a silent fail-closed return with #44/test evidence, and the one intentional
writer refusal remains the same exact family.

## Player-position visual proof

The reusable SpaceShot fixture gained a presentation-only `--rt-corrupt-manifest price_per` arm.
It mutates only the bench instance after normal seed/tick warmup; product code never injects this.
`tools/assert_p1o_manifest_authority.py` compares valid/corrupt runs at seed 3, tick 600, player
`[57,8]`, 1280x768, portal roundtrip into `port_warehouse/1f`:

- valid: `ready`, `柴薪 x4`, carrier count 1;
- corrupt: `invalid`, empty trusted good, quantity 0, carrier count 0;
- exterior changed 26,931 pixels, bbox `(859,272)-(1100,441)` (carrier + port hint);
- warehouse changed 3,046 pixels, bbox `(597,305)-(737,335)` (status-board row);
- both arms retain real player enter/return receipts and town-before == town-after pixel identity.

Local candidate frames are generated/rebuildable under
`%TEMP%/p1o-visual-{valid,corrupt}-candidate`; they are not pixel goldens and are not committed.
Runner: `gamecraft-runner:4.6.2`, local image digest
`sha256:90eaf3f8b60e15ea95de0c3e87e3276414c4cae1355b49471e9d2f52dddaa33d`.
All art is repository procedural art; no external asset or license entered the product.

## Verification receipts

- P1-g final authority/receipt/rekey matrix: supervised candidate PASS
  `20260813T053606967Z_eaaf95f57abb43b288d7cbca3c902392`.
- P1-c carrier authority/recovery: PASS
  `20260813T053620155Z_ba71cfd2bb474d2388e8ec7fa1e432c6`.
- save migration: PASS `20260813T053623664Z_35bbd836c7b549e48069c497b34b9091`.
- state projection after the final arrival-receipt validator: PASS
  `20260813T054744485Z_ec1e1d588d494dc7b862c94d5e453f09`.
- P1-b manifest regression: PASS `20260813T052011676Z_09b9f1c7adad45a5a67401a138350846`.
- standard seeds 1-12, 60 days, det3, no golden: PASS
  `20260813T052917835Z_3faf095368734d01a89ba4cdfb081c51`; hard and #40/#44/#45/#46
  12/12, import 156 and export 57 across 12/12 seeds, determinism 3/3.
- total-N24 seeds 1-9 each produced a passing S0 row before the 300 s outer timeout; seeds 10-12
  then completed PASS under `20260813T054221253Z_bc269d2bf0a4406db1442271ef42491d`.
  Combined hard 12/12; seed10 retained the known #40 oversupply-only soft failure; the completed
  final three seeds had #44/#45/#46 3/3 and import/export 47/17 across 3/3.  The timeout receipt
  `20260813T053648197Z_bc1678c7e245488f91ff1add83b31b4e` verified source stability and cleanup.

All supervised receipts report stable dirty-candidate fingerprints and verified cleanup.  Exact
committed-tree reruns follow the topic commit.  Golden/modelpath/complement remain deliberately
stale and are not modified here; PR #6 therefore remains draft/unmergeable.

## Known limits and reuse

This is internal consistency, not a cryptographic save signature: coordinated mutation of both a
saved lane and its manifest can remain self-consistent.  Provenance/authentication is a separate
future contract.  `tools/assert_p1o_manifest_authority.py` is reusable for any future UI treatment
as long as valid/corrupt SpaceShot metadata retains the semantic ready/invalid contract.
