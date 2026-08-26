# P1-l schema-2 complete-state contract

Date: 2026-08-13 CST

Branch: `codex/p1a-takeover`

Purpose: prevent a current schema-2 save with omitted authoritative fields from inheriting values from the live `Sim` used by quickload.

## Failure and product risk

The P1-e loader validated a hand-maintained subset of 17 state keys. A schema-2 envelope could remove another saved field such as `festival_active`, pass validation, and leave the receiver's pre-load value in place. The same class existed outside `state`: missing `active_commit_ids` silently became `[]`. The resulting world depended on receiver history, so a syntactically current save could become a mixed state rather than an atomic snapshot.

Red control: remove `festival_active` from a real schema-2 save, poison a receiver with `festival_active="__receiver_poison__"`, then load. At P1-k this incorrectly returned true and retained the poison.

## Contract

- `_current_save_state_keys()` derives the current schema state keys from the same reflection and `SAVE_LOAD_DENY` policy used by `save_game`; no second required-field list defines completeness.
- Schema 2 must contain exactly that state-key set. Missing or extra fields, including runtime-handle keys that the current writer never emits, are rejected before any live `Sim` mutation. Historical schema 1 still erases its known null handle remnants during migration.
- The current envelope must contain exactly `magic/schema/game_version/saved_tick/saved_day/seed/meta/active_commit_ids/state`; missing active membership can no longer degrade to an empty workset.
- Envelope fields retain their authored types; tick/day/seed must equal their authoritative state values, while `active_commit_ids` must be the exact unique membership of saved active commitments. UI metadata cannot lie and the reconstructed workset cannot dangle, omit an active row, or point at an inactive row.
- `peek_save()` applies the same current-shape contract before presenting a slot, so the save-list UI does not advertise a file that quickload must reject.
- `save_game()` runs the same validator before opening the destination, so writer, save-list and loader cannot drift into three definitions of a valid current save.
- Schema 1 keeps its explicit migration path and compatibility surface. Exact `d46cbb1` bytes, P1-a ghost-unload gating, and transitional CargoManifest validation do not need to impersonate the current schema-2 shape.
- Adding or excluding a saved authoritative script variable changes the schema-2 field set. Until the codec/migration policy is intentionally updated, an older schema-2 payload fails closed instead of inheriting a receiver default. This is a deliberate compatibility alarm.

## Reusable verification

`save_migration_test` now:

- compares a real current save's state keys against `_current_save_state_keys()`;
- deletes every current state key in turn and requires `_validate_loaded_state(..., 2)` to reject it;
- writes full envelopes missing `festival_active` and `active_commit_ids`, plus schema-2 state/envelope extras, then proves `peek_save()` hides them, load rejects them, and the polluted receiver remains unchanged;
- retains exact legacy fixture migration, schema-2 roundtrip/continuation, runtime-handle ownership, cargo/population cross-field checks, and malformed-envelope negative controls.

Candidate receipts (all `dirty_candidate`, stable source fingerprint, cleanup verified, no native-crash pattern):

- focused completeness matrix before the final writer self-check: `20260813T001222492Z_c44abcba45fe4343b7e6ea62634cd185`;
- final focused matrix with writer self-check and corrected legacy transformer: `20260813T001359529Z_2f52faf25ba44789abd283369e5fa333`;
- schema-2 roundtrip with active commitments: `20260813T000815109Z_5de6b753c96a44e3a5f7fc579cd532a0`;
- full state-projection mutation gate: `20260813T000817011Z_f88e93b297d64cce9d13a7a71563ed01`;
- standard seeds 1–12 × 60 days, det3, no golden: `20260813T000857351Z_d894f898302a4f0cb11fbcbe6687dd44` — hard/soft 12/12, #40/#44/#45/#46 12/12, import/export 156/57 over all seeds, determinism 3/3.

A committed exact focused receipt is required after the topic commit.

## Boundaries and provenance

- This changes save/load validation only; it does not change simulation ticks, player controls, UI, art, map, or framebuffer output. P1-i player/warehouse screenshots remain the relevant visual reference.
- No golden, ModelPath, complement, terrain, or screenshot artifact is rebaked.
- Source is repository-local code and generated test envelopes; no external code, asset, or license input.
- Known limitation: the schema contract is intentionally strict, not a general structural migration language. A future intentional schema-2 shape change should normally advance `SAVE_SCHEMA` and add a named migration rather than weakening completeness.

## Failed route retained

After adding writer self-validation, receipt `20260813T001307506Z_83b9069acdd34ea680a2c1a2376ac856` failed: the P1-a compatibility tooth first placed an unsigned cargo option in a current live `Sim`, then asked the now-strict writer to serialize it. The writer correctly refused; the test's later use of the missing fixture caused `SCRIPT ERROR`, which the supervisor correctly classified as exit 70. The accepted fixture path now writes a valid current save first and injects the historical ghost option only in the offline schema-1 transformer. This preserves the migration counterexample without weakening the production writer.
