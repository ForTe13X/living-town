# P1-n expected runtime-error contract

## Delivery target

Close the GitHub CI ambiguity where a negative-control scene can print a correct final `PASS`
while the global runtime-error sentinel independently sees deliberate `push_error` records and
marks the same scene red. The product writer and cargo arrival guards remain fail-closed and loud;
only the owning test boundary may interpret a fixed set of error messages as expected evidence.

This is one integration batch with two real consumers:

- `p1g_manifest_transaction_test` exercises three corrupted arrival histories and one malformed
  current-save writer input;
- `state_projection_gate` generically mutates four authoritative save fields into states that the
  current writer must refuse.

## Root cause and failed route

GitHub Actions run `31659112066` checked product head `f7c8f4d` through its pull-request synthetic
merge. P1-g printed `p1g_manifest_transaction_test: PASS`, then `tools/ci.sh` reported four
unexplained errors and failed the scene:

1. live manifest without its arrival receipt;
2. conflicting arrival history;
3. duplicate arrival history;
4. schema-2 writer rejection for non-canonical cargo identity.

The old scene result and the global error scan were each correct in isolation; the missing
artifact was an explicit contract joining them. Weak alternatives were rejected:

- downgrading product `push_error` to a warning would hide real corruption outside tests;
- accepting every error from a scene would turn the test into a log blind spot;
- using one alternation with a total count of four would let one duplicate family replace a
  missing family and still pass;
- trusting the final `PASS` line alone would recreate the supervisor-v2 false green.

## Accepted reusable contract

`scan_exact_once_set` pairs Godot error lines with their `at:` context, removes only the existing
NobodyWho environment allowance, and then requires every declared message family exactly once.
Missing, duplicated or substituted families fail. Any fifth `ERROR`, any unrelated
`SCRIPT ERROR`, and all other runtime records also fail.

The scanner has an independent fast entry point:

```powershell
$env:CI_SCAN_SELF_TEST_ONLY='1'
& 'E:\Program Files\Git\bin\bash.exe' tools/ci.sh
```

Its fixture proves the green set, duplicate-plus-missing, unexpected `ERROR`, and unexpected
`SCRIPT ERROR` arms. `CI_SCAN_LOG_ONLY` plus `CI_SCAN_PROFILE=p1g|state_projection` can replay the
same contract against a captured Godot log without rerunning the whole CI suite.

## Verification evidence

Candidate source remained stable under the canonical Windows supervisor:

- P1-g: `20260813T040856931Z_725f524aa8914afcbcf7b09cf5398ac7`, PASS, four declared error
  families each once, final `0 fail`, no native/logic failure, cleanup verified;
- state projection: `20260813T041055054Z_7b73b369915e4bf2b5eb3090511516ee`, PASS in 41.2 s,
  four writer refusal families each once, final `0 fail`, cleanup verified;
- save migration: `20260813T040913600Z_092ed9a223da435982d3099ec612f84c`, PASS.

A shortened CI integration run reached and passed the P1-g and state-projection runtime profiles;
it later exceeded the outer 10-minute shell budget while running unrelated one-day story fixtures.
No scoped Godot/bash process survived. That timeout is not presented as a full-CI receipt.

Existing no-golden behavior grids from the immediately preceding P1-m candidate remain applicable
because this batch changes only test comments and CI interpretation, not `game/scripts/Sim.gd`,
data or invariants: standard 1-12/d60/det3 passed 12/12; held-out 13-30 passed 18/18 with #40 at
17/18; total N24 passed 12/12 with non-vacuous import/export 167/82. P1-n does not rebake or claim
golden/modelpath/complement freshness.

## Player-position presentation check

The batch revalidated the existing P1-i presentation pool from exact product head rather than
adding duplicate images. Pinned `gamecraft-runner:4.6.2`, seed 3, tick 600, player `[57,8]`:

- exterior → `port_warehouse/1f` → exterior portal roundtrip passed;
- returned exterior was byte-identical to departure;
- interior differed from exterior by 98.59%;
- tracked images retained SHA-256
  `2346d32d...4a60f` (exterior) and `8265f061...2ae1` (warehouse);
- an 8-second 1280×768/30 fps H.264 proof was generated under `%TEMP%` and is
  generated/rebuildable, not a pixel golden.

Player-view review confirms the carrier, crates, warehouse door, cargo status and global HUD are
readable. Remaining non-blocking UX risks are recorded rather than hidden: the right dossier
presses against the warehouse return door/player; social-action buttons remain visible with no NPC
target; the exterior warehouse identity relies heavily on its small sign. These belong to a later
player-shell polish batch, not to this CI-contract fix.

## Provenance, limitations and recovery

No external art or code was copied. Visuals use repository procedural art and the pinned runner.
No README or protected first-screen `demo.gif` block was changed. No branches, worktrees, tasks,
caches or unknown files were archived or deleted.

The remaining delivery blocker is evidence freshness: PR #6 must stay draft until its committed
exact-tip CI proves that P1-g and state projection are no longer red for unexplained errors, and
the separate authorized golden/modelpath/complement rebake protocol closes the stale anchors.
Recover this batch by reverting its topic commit; product runtime behavior remains unchanged.
