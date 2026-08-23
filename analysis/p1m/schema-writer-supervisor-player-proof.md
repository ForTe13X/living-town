# P1-m schema writer, supervised verdict, and player proof

Date: 2026-08-13 CST

Branch: `codex/p1a-takeover`

## Single delivery target

Make the strict schema-2 writer and the CargoManifest adversarial fixture agree without
weakening production validation, make the canonical Windows supervisor fail closed on a
standard red test verdict even when Godot returns process exit zero, and bind the repaired
candidate to the existing player-position East Ocean warehouse presentation.

The batch owns only the P1-g fixture, the supervised-runner verdict contract and its tests,
this evidence card, and the baton ledger. `Sim.gd`, gameplay data, UI, art, map, README,
golden, ModelPath, complement ledger, protected branches, merge and release are outside the
batch. Stop/rollback condition: any production-writer weakening, source drift, native crash,
behavior-grid regression, player-route regression, or visual delta outside the warehouse
status crop.

## CI counterexample and root cause

PR #6 run `31653814665` checked out the pull-request synthetic merge
`547a196...` for head `e01c5a1`. Its first new code/test failure was
`p1g_manifest_transaction_test: FAIL (1 fail)`: the fixture expected the current schema-2
writer to serialize a deliberately noncanonical completed manifest id. The writer correctly
rejected it. The same scene was a local false green because Windows Godot printed the red
terminal verdict after `get_tree().quit(1)` but returned OS exit zero; supervisor v2 observed
only exit/native-crash state.

The run also retained the already-known delivery failures: stale complement schema/tree,
stale golden values and stale ModelPath anchors. Those anchors are not rebaked here, and a
green candidate grid is not represented as merge readiness.

## Accepted contract

- The P1-g test now requires `save_game()` to refuse the noncanonical live state and leave no
  half-written file. It then makes the adversarial file by deep-copying a valid store-var
  envelope and mutating only `cargo_manifests[id].id` offline. The loader must reject that
  envelope atomically. Production `Sim.gd` is unchanged.
- `run-godot-supervised.ps1` contract v3 preserves v2's exact/candidate source fingerprint,
  drift, timeout, crash and process-tree cleanup fields. It additionally scans combined
  Godot/stdout/stderr for standard terminal verdicts `*_test: FAIL` and `... GATE: FAIL`.
  A zero-exit process with such a verdict becomes `logic_failure_pattern`, exit 72.
- `SupervisorLogicFailure.gd` is the permanent red control: it deliberately prints a standard
  failure verdict and quits zero. The supervisor self-test requires that arm to exit 72 while
  its ordinary focused scene remains green. The regex is anchored to repository verdict
  shapes rather than every occurrence of the word `FAIL`.

## Reusable verification evidence

Candidate source stayed stable in every receipt. Focused and supervisor teeth:

- original pre-fix local false-green log ended in `p1g_manifest_transaction_test: FAIL (1 fail)`;
- red control `20260813T010312314Z_9f8a2b49f6d84b2487c44b43e0fe3234` ->
  `logic_failure_pattern/72`;
- fixed P1-g receipt `20260813T010326853Z_d412f76ae66c4e3ba4d5d29bc6ad625d` -> PASS;
- supervisor positive/logic/timeout/concurrent-owner receipts
  `20260813T010353413Z_c31014e4364a424e89de13814f646542`,
  `20260813T010355180Z_aa3c1cf8d38740d7b8326e33843b1f20`,
  `20260813T010356530Z_a95672a1bb834dcda968ded22e801eba`, and
  `20260813T010401415Z_5119091f53aa4a3287569530cf20d3d3` all matched their expected outcomes;
- the provenance self-test retained dirty rejection, explicit stable candidate execution and
  in-run source-drift exit 79;
- save migration/load, state projection, P1-b manifest, P1-c carrier, P1-d export, P1-g
  transaction and indoor-space focused scenes all passed under v3; `lint_data`, `audit_map`,
  `lint_links`, `git diff --check` and player-touch also passed.

Behavior grids, no `--golden` claim:

- standard 1-12 x 60 days, det3:
  `20260813T011147151Z_8b294a96173342bc9b574170a6887bf0`; S0 PASS, hard/soft
  12/12, #40/#44/#45/#46 12/12, determinism 3/3;
- held-out 13-30 x 60 days, det3:
  `20260813T011442470Z_ae7d46b2198e4806b3ff7365c0d75729`; S0 PASS, hard
  18/18, #40 17/18 (allowed threshold; seed 14 bean shortage), #44/#45/#46 18/18,
  determinism 3/3;
- exact total N24 (core23 + affiliate1), 1-12 x 60 days, det1:
  `20260813T011818316Z_3a452c2880c84479acf668b955af63bc`; S0 PASS, hard
  12/12, #40 11/12, #44/#45/#46 12/12, import/export 167/82 over all 12 seeds,
  determinism 1/1.

## Player-position UI / UX / art evidence

Using pinned `gamecraft-runner:4.6.2` (image digest
`sha256:90eaf3f8b60e15ea95de0c3e87e3276414c4cae1355b49471e9d2f52ddaaa33d`),
seed 3, tick 600 and the real player at East Ocean `[57,8]`, the portal roundtrip captured
town-before -> `port_warehouse/1f` -> town-after. Both ON and `warehouse_status`-OFF arms
passed `assert_space_roundtrip.py`; the returned town frame is byte-identical to the departure
frame, while the interior is 98.59% different from the town. The property delta is 56,048
pixels, bbox `(512,156)-(778,367)`, wholly within crop `(505,147)-(784,371)`.

Manual inspection confirms the exterior communicates the player, warehouse door, cargo
carrier/crates, shoreline, HUD, needs, money, time and interaction affordances in one frame.
The interior communicates the East-port arrival ledger, three stock gauges, berth cargo and
return door without hiding the global HUD. The three-frame journey demonstrates actual play,
not a teleported beauty shot. SHA-256:

- exterior before/after:
  `2346d32d825f597bbc448d05283df213e07e48879925216bbec385a30ac4a60f`;
- warehouse ON:
  `8265f061bdc84ca44ae8772255645540cc967b07e7bed27a1beb74c0e4dd2ae1`;
- warehouse OFF:
  `7b63282bd5e3da90257a5ac740dfaf8f5becef6be9699fc87b68df4c3e4ad98c`.

The ON exterior/interior hashes exactly match the canonical, already tracked P1-i presentation
pool `docs/media/p1i_east_ocean_{player,warehouse}.png`; P1-m therefore reuses rather than
duplicates those assets. Candidate output is generated/rebuildable under
`%TEMP%/p1m-player-warehouse-2e8b8435f73f4c6d95b68b167514dbfd`, not a pixel golden.

## Provenance, limitations, hygiene and recovery

All code, test envelopes and visuals are repository-generated under the project's existing
license; no external code or asset was copied. NobodyWho's optional missing extension and the
known ObjectDB/VSync warnings appeared in visual runs but did not cause a parser/native crash.
The visual capture is local pinned-GL evidence, not a GitHub Actions visual receipt. The PR
must remain draft until committed exact-tip checks and the separate anchor-finalize protocol
are satisfied.

No branches/worktrees/tasks were archived or cleaned. The old v1 runner receipt language is
historical/audit material; v3 is canonical. Recover by checking out the P1-m topic commit,
running both PowerShell self-tests and P1-g focused from a clean tree, requiring
`source_identity=exact_commit`, then rebuilding the three-frame player roundtrip with the
fixed seed/tick/position and requiring the hashes and property-delta assertions above.
