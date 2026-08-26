# P1-w post-semantic-freeze anchor-finalize readiness refresh

Date: 2026-08-14 CST

Frozen product head: `70f7575fd7e5c1ff07be0a1f4c5679928c53dcc9`

Frozen game tree: `8dfd5dec5990274daffdec106476828b5f87daa5`

Status: `prepared_not_authorized`; protected anchors were not written.

## Single delivery target and boundary

Refresh P1-r's no-golden readiness evidence after P1-t/u/v closed the three provisional semantic
freeze blockers, then make the remaining review dependency machine-visible and fail-closed. This
batch owns only `analysis/p1w/`, this short ledger entry, and PR/hosted handoff metadata. It does not
modify `game/`, README, any golden/ModelPath/complement anchor, a protected branch, a review branch,
or release state.

Internal DAG: freeze identities and review -> compare P1-r with P1-t/u/v -> exact held-out -> exact
total-N24 -> isolated logistics ON -> true-zero OFF -> freeze anchor hashes/reachability -> write
evidence manifest and verifier -> negative teeth -> commit/push -> exact-tip hosted classification.

Stop conditions are any hard/determinism/runtime regression, a vacuous ON arm, non-zero OFF arm,
anchor drift during the batch, mismatched Git identity, a fifth hosted failure family, or no fresh
completed independent review. The last condition is active, so this batch cannot authorize rebaking.

## Why the refresh was required

P1-r froze game tree `d3668111...`. P1-t then made social eligibility exact-plane aware, P1-u made
East Ocean drawn props and navigation share authored cells, and P1-v explicitly chose and shipped a
read-only cargo observatory rather than an ambiguous live warehouse. These directly answer the
in-progress review's three provisional semantic-freeze concerns, but P1-t is an intentional behavior
change. P1-r's trajectory counts therefore cannot be reused as current-tree evidence.

The current exact tree changes the held-out counts from import/export `252/59` to `248/82`; import
still covers `18/18` seeds while export covers `17/18`. #40 improves from `17/18` to `18/18`, and all
hard trade invariants remain `18/18`. The isolated total-N24 ON arm still supplies the stronger
non-vacuity proof: every seed has every arrival/import/export/unload family. No threshold or
conditional invariant was relaxed.

## Exact no-golden grids

Canonical Windows supervisor receipts bind clean/stable exact commit `70f7575`, game tree
`8dfd5dec`, and verified cleanup:

- held-out `13-30 x 60d x det1`: receipt
  `20260814T053846082Z_4ad6be1ef7654f6888edd81fd7368945`, PASS, hard `18/18`, #40
  `18/18`, #44/#45/#46 `18/18`, import `248` over `18/18` seeds, export `82` over
  `17/18`, det `1/1`, Godot log SHA-256
  `D8619FED1CCECEC495CD5E30D9A11439AC351C6AD8BD57821FA81E7B8BCB9D46`;
- exact total N24 (`--total-agents 24`): receipt
  `20260814T052330969Z_2dc7d8429ea144c3a637963cf353d795`, every row reports
  `{mode:total, requested:24, core:23, total:24}`, PASS, hard `12/12`, #40 `11/12`
  (seed 6 upper arm), #44/#45/#46 `12/12`, det `1/1`, Godot log SHA-256
  `26D32E12FBC44A2F4A08905C5844236A052E7A6677D54ED7663F75D59648D251`.

Both logs have zero `SCRIPT ERROR`, signal 11, FATAL, or out-of-bounds rows. The first held-out launch
survived a five-second desktop caller timeout and produced the same complete Godot log hash, but its
supervisor was no longer present to seal `receipt.json`; it is not cited as canonical. The second run
above is the canonical receipt.

## Current-tree non-vacuous ON/OFF pair

`analysis/p1r/logistics_arm_probe.gd` was copied into isolated `git archive` game trees; it never
entered the product tree. Pinned runner
`gamecraft-runner@sha256:90eaf3f8b60e15ea95de0c3e87e3276414c4cae1355b49471e9d2f52dddaa33d`
ran both arms:

- ON, core23 + affiliate = total24, seeds 1-12 x 60d: every family covers `12/12`; totals are
  arrival `240`, import `126`, export `84`, unload `126`; #44/#45/#46 pass per seed; exit 0; log
  SHA-256 `080675839F486E9C5DCC6C778C887A8E322BE8FFDC60454A5CF78909F205C612`;
- OFF removes only the resolved isolated `game/data/logistics.json`: seeds 1-3 x 20d, each twice,
  compile no logistics or cargo queue, all four totals are exactly zero, conditional #44/#45/#46
  remain green, and summaries repeat exactly; exit 0; log SHA-256
  `32D9D91C9612603E34667DA47182922BC90C48A26F4395E326299D64B7B1DF3C`.

P1-r's ON totals were `240/167/82/167`; the current `240/126/84/126` is real trajectory drift after
the exact-plane social contract, not an engine/hash accident. Per-seed four-family coverage, atomic
transaction tests, hard invariants, and true-zero removal all remain intact.

## Frozen anchor and hosted state

The three protected files are unchanged:

| Path | SHA-256 | baked game tree |
|---|---|---|
| `tools/gate_complement_ledger.json` | `D7C481DF...A189` | `eabcb07d...98dd` |
| `game/bench/golden_digests.json` | `575ECBD1...CB87` | `935b2361...5d94` |
| `game/bench/modelpath_anchor.json` | `FEBCB2A4...40D8` | `935b2361...5d94` |

All anchor commits exist and are ancestors of the current head; none matches the current game tree.
Hosted run `31770888448` is terminal failure on exact product head `70f7575`, synthetic merge
`8b7ec894`, and game tree `8dfd5dec`. Its only four `FAIL:` families are complement stale, Harness
golden stale, DetGate golden stale, and ModelPath anchor stale; 19 focused scenes and all non-anchor
gates pass, with no fifth product/infrastructure failure.

## Fail-closed verifier and decision

`readiness-evidence.json` is the small reusable evidence contract.
`verify-anchor-finalize-readiness.ps1` checks exact HEAD/branch/game tree, clean worktree, optional
upstream equality, frozen product ancestry, every protected anchor hash/tree/reachability, held-out
and N24 population/threshold contracts, non-vacuous ON, exact-zero OFF, hosted four-family
classification, and the review gate. `-RefreshHostedIdentity` composes the existing P1-s GitHub
run/merge verifier rather than duplicating that protocol.

The current positive result is deliberately `prepared_not_authorized` with `authorized=false`.
Requesting `ready_to_finalize` fails because `review_gate.authorizing_completed` is null. Wrong
HEAD/game tree, stale upstream, dirty worktree, modified anchor, missing family, and fabricated
review state all stop before a receipt is emitted.

The latest completed review remains the stale 2026-08-13 09:00 REQUEST CHANGES brief. The scheduled
2026-08-13 21:10 review is still in progress; its provisional concerns motivated P1-t/u/v, but an
in-progress task is not approval. Recovery trigger: a completed independent review that explicitly
covers game tree `8dfd5dec` and approves controlled anchor finalization, followed by one dedicated
committed-tree Harness + DetGate + ModelPath + complement rebake batch and hosted CI. Until then PR
#6 stays draft/unmergeable.

## Provenance, limits, hygiene, and recovery

No external code or asset was copied. Evidence uses repository contracts, local exact receipts, the
pinned existing runner, Git objects, GitHub metadata, and the read-only review task. README/demo,
protected branches, review worktree, unknown-owner worktrees, and anchors remain untouched. One
failed full-repository `tar.exe` expansion exposed a Windows Unicode-path limitation; it left only a
generated/rebuildable `%TEMP%/p1w-exact-*` fragment and caused no checkout edit. No broad cleanup was
performed after the safety policy rejected prefix-based recursive deletion.
