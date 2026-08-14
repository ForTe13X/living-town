# P1-v East Ocean cargo observatory

Status: implemented and exact-commit verified on 2026-08-14; hosted verification is pending. This
batch explicitly lands `port_warehouse/1f` as a read-only cargo observation room. It does not add
player unloading, change the worker/economy transaction authority, rebake protected anchors, or
approve Draft PR #6.

Implementation commit: `86a3ebf3ba390f514e7fc9190bf675fd02921427`

Exact game tree: `8dfd5dec5990274daffdec106476828b5f87daa5`

## Single delivery target

Make the East Ocean warehouse a truthful, interactive, auditable cargo observatory: the real player
can enter through the authored portal, see current stocks and the authoritative pending manifest,
query the latest exact unload receipt at one authored console, and return to the dock. Every player
interaction in the room is read-only; only the existing assigned dock worker may unload cargo and
commit stock, pay, and event rows.

The latest completed review available at batch selection was still the stale 2026-08-13 09:00 CST
REQUEST CHANGES snapshot. A later review remained in progress and separated mechanical rebake
readiness from the unresolved observation-room versus live-warehouse product choice. P1-v resolves
that choice conservatively for this milestone: observation/control room now, not player-operated
warehouse. An in-progress review is evidence, not approval.

## Fourteen coherent strides

1. Froze branch, PR, review cutoff, source identity, dirty ownership, and stop conditions.
2. Inventoried warehouse UI, cargo projections, transaction receipts, and existing player frames.
3. Chose a read-only observation-room contract and retained worker-owned atomic unloading.
4. Captured empty, ready, invalid, paid, free, malformed, and duplicate receipt counterexamples.
5. Added one Sim projection for current cargo, three stocks, and the latest unload receipt.
6. Bound receipt projection to exact transaction adjacency, actors, subjects, quantities, and IDs.
7. Made Main report the player's real space/floor instead of a town-only area label.
8. Made one authored interior counter perform a real read-only query with exact Sim no-op proof.
9. Drew the observatory from that shared projection and marked the room and panel read-only.
10. Removed false social/chat affordances and made the return door prompt visible above the HUD.
11. Extended static data ownership, CI scene ownership, and the warehouse framebuffer assertion.
12. Ran focused, adjacent, save, shell, lint, map, and standard candidate gates.
13. Repeated focused, standard, and pinned ON/OFF framebuffer gates on committed exact source.
14. Bound contracts, receipts, hashes, provenance, limitations, hygiene, Git, PR, and recovery here.

## Shared projection and authority boundary

`Sim.warehouse_observatory_projection("port_dock")` is the only product projection consumed by
Main's console and WorldView's board. It returns `mode=read_only`, the three displayed town-stock
values, the already fail-closed `cargo_status_for_node`, and one latest unload receipt projection.
The authored console cell is discovered from `interiors.json` through
`warehouse_observatory_console_cell()`; Main does not carry a second coordinate constant.

For a good receipt, the projection requires the canonical manifest/lane/cadence/arrival proof plus
an exact contiguous event transaction:

- paid unload: stock, import payment, and wage rows share one transaction ID in that order;
- free unload: stock and wage rows share one transaction ID in that order;
- the stock actor is the manifest's assigned unload worker and its quantity equals the manifest;
- pay actors/targets, subjects, deltas, notes, event IDs, and adjacent rows match the existing
  P1-g transaction contract;
- a latest row that looks like an unload receipt but is malformed returns `state=invalid`; it never
  falls back to an older good receipt.

Invalid cargo or receipt projections blank manifest ID, good, quantity, worker, transaction ID, and
event ID instead of presenting untrusted business data. The console click and every social action
inside the room compare exact Sim snapshots and must leave them unchanged. Actual unload selection,
preflight, stock commit, payment, wage, and manifest completion remain in the existing worker-owned
P1-g/P1-o path.

## Reusable focused matrix

`p1v_warehouse_observatory_test.gd` covers:

- empty, canonical ready, and corrupt pending-cargo projections;
- exact paid three-row and free two-row unload receipts;
- wrong stock quantity, malformed unload-note prefix, duplicate transaction ID, forged worker, and
  invalid arrival proof, each fail-closed without leaking business fields;
- real Main portal enter and return, authored console discovery, truthful player plane label, hidden
  social action bar/chat input, and a real console response;
- exact Sim no-op for both the console query and a rejected social action inside the observatory.

The first fixture draft incorrectly reused receipt-only safe-field expectations for corrupt cargo.
The product projection was correct; splitting cargo and receipt assertions fixed that test-only
false failure. Real framebuffer inspection then found two product defects that headless assertions
had missed: the right dossier retained a stale town location after portal travel, and self-chat still
looked actionable. Portal observation refresh and warehouse chat gating close both.

## Verification receipts

Candidate gates passed for P1-v, P1-g, P1-u, player touch, portal/space, save migration, JSON/map/link
lint, Python compilation, Docker shell syntax, and `git diff --check`. The candidate standard grid
`1-12 x 60d x det3`, no golden, passed in supervisor receipt
`20260814T042948287Z_806c7569496f457094b6118bb8825a63`: hard `12/12`, #40 `11/12`
(the established seed-11 food `0.45` tolerance arm), #44/#45/#46 `12/12`, import/export `164/48`
covering all twelve seeds, determinism `3/3`, stdout SHA-256
`EAE92A13E0B723FF8CF5AB58B20DE05B7DDE192379A1A4D8023A1FEF061CDBB9`.

Clean exact-source receipts at implementation commit `86a3ebf` and game tree `8dfd5dec`:

- P1-v focused PASS: `20260814T043633724Z_7bc5784c18cd4caaae15d6fd900f756f`;
- standard PASS: `20260814T043648118Z_3055a1a71dd848038a2ebaa77ae4c72f`, 238.4 seconds,
  exact-commit identity, source/game tree stable, cleanup verified, and stdout SHA-256
  `EAE92A13E0B723FF8CF5AB58B20DE05B7DDE192379A1A4D8023A1FEF061CDBB9`.

The exact standard stdout is byte-identical to both the P1-v candidate and P1-u exact baselines.
P1-v therefore adds no simulation or event-ledger drift; protected anchors were not touched.

## Exact framebuffer receipt

The clean exact tree was rendered through the real product portal with
`gamecraft-runner:4.6.2`, Godot 4.6.2, Mesa llvmpipe 23.2.1, seed 3, tick 600, player `[57,8]`, and
1280x768 output. The generated/rebuildable evidence root is
`%TEMP%/p1v-exact-20260814T124156988`; no temporary frame is tracked as a golden.

- ON town before/after SHA-256:
  `3907EEA4D6F2F6671D19150433FAE67FB0612FC8F61A06AB35484581D3B58A97`;
- ON interior SHA-256:
  `6F8361B0F51DD2B9182CADA0523B6AD660671D1A40AC5D2B67020471A752C91B`;
- `warehouse_status` OFF interior SHA-256:
  `6E42BAFE437133159B9E7AEF1FCF715EE0D9B85A56D660965A444F862BA16081`.

Both real journeys prove player enter/return, town before/after zero-pixel difference, and 98.99%
interior-versus-town difference. The ON/OFF assertion changed 66,954 pixels with bbox
`(512,156,778,408)` wholly inside computed board crop `(505,147,784,413)`. Metadata proves authored
console `[6,1]`, `mode=read_only`, exact Sim no-op, hidden action/chat controls, truthful location,
ready firewood x4, one carrier, and a real read-only console message. Logs contain no signal 11,
FATAL, out-of-bounds, or SCRIPT ERROR. The known missing NobodyWho extension, unsupported VSync, and
ObjectDB warnings remain declared platform noise and are not relabeled as product success.

Only repository procedural art and the pinned runner were used; no external art/code or new license
entered the tree. The frames prove route, state, query interaction, and layout, not action timing;
no short video is claimed.

## Limits, hygiene, and recovery

P1-v intentionally supports only the latest exact unload receipt and a read-only room. It does not
let the player move cargo, assign workers, approve payments, or mutate manifests. Historical receipt
projection relies on the current static authored lane, economy, and job definitions, which is valid
while those records remain immutable; versioned historical policy would need a separate contract.

README/first-screen demo, protected branches, unknown-owner worktrees, other tasks, and all four
golden/modelpath/complement anchors remain untouched. Temporary visual outputs are
generated/rebuildable; no archive or clean action occurred. The branch may be normally pushed, but
Draft PR #6 must stay draft/unmergeable until hosted exact-tip classification, a completed review
covering the current product tree, and the controlled anchor-finalize gate all succeed.

