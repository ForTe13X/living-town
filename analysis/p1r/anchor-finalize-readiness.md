# P1-r exact-tip non-anchor closure and anchor-finalize readiness

Date: 2026-08-13 CST
Branch: `codex/p1a-takeover`
Frozen product head: `b0a501b80694282ae9dbf13a9256106ae5d3f776`
Frozen game tree: `d3668111f41d5384e0ed17efd3f2328d355d927c`

## Single delivery target and ownership

Close the hosted exact-tip evidence gap after P1-q, prove the current product tree is healthy on
held-out, exact-total-N24 and logistics ON/OFF arms, and decide whether the repository is allowed
to enter its controlled three-anchor finalize protocol. This batch owns only this card, the
read-only reusable probe beside it, and the short baton-ledger entry. It does not modify `game/`,
README, golden digests, ModelPath anchor, complement ledger, protected branches or release state.

Internal DAG: freeze identities -> classify every hosted red -> prove Linux scenes -> read R12 ->
run post-tree held-out -> disambiguate legacy `--agents` from exact `--total-agents` -> run exact
N24 -> prove non-vacuous trade ON -> prove true-zero OFF -> run pre-tree held-out -> attribute anchor
drift -> record stop/recovery boundary -> commit/push/update draft PR.

Stop condition: any new hard invariant, focused scene, deterministic repeat, per-seed trade family,
source identity or cleanup failure. Anchor files remain untouched unless the R12 pre/post evidence,
a completed review cutoff covering this tree, a committed finalize tree and all three bake commands
are simultaneously available.

## Hosted exact-tip CI adjudication

PR #6 run `31694970713` is a completed pull-request run for exact head `b0a501b`. GitHub checked out
synthetic merge `233f82ca19b0bb53d0b0a7af6195b14954bc6048`, whose parents are exactly base
`d46cbb132595185c3420bb4eb8fd7f28512baa85` and product head `b0a501b`. All sixteen focused scenes
passed on Linux, including `space_test`, P1-a/b/c/d/g, save/load/migration, state projection and
player agency. This closes P1-q's cross-platform portal-number blocker.

The job contained exactly four `FAIL:` markers:

1. complement ledger stale (`baked_game_tree=eabcb07d8ffe...` versus current `d3668111...`) and no
   valid `_meta.hard_ids_at_bake`;
2. S0: hard 12/12, soft/liveness and det3 all green, golden values stale;
3. DetGate: hard 16/16, same-seed determinism 16/16 and data fingerprint 16/16, golden 0/16;
4. ModelPath: four scenario rows plus the candidate-scale row differ from its submitted anchor.

Expected runtime `ERROR` lines remain owned exact-set teeth: P1-g and state projection passed after
each declared family appeared exactly once and no fifth family survived filtering. NobodyWho import
noise is the existing allowed optional-extension family. The hosted visual lane is still an explicit
SKIP because GitHub's Mesa/GL stack is not pinned; local pinned-container presentation receipts must
not be represented as hosted visual coverage.

## No-golden behavior grids on the frozen post tree

Canonical Windows supervisor receipts are source-exact, clean/stable, cleanup-verified and bind the
same game tree:

- held-out `13-30 x 60d x det1`: run
  `20260813T120647546Z_4970c343a62c434e955b23761f37141b`, PASS, hard `18/18`, #40
  `17/18` (allowed single soft miss: seed 14 bean satisfaction about 0.46), #44/#45/#46 `18/18`,
  import/export `252/59`, both covering `18/18` seeds;
- a diagnostic invocation with legacy `--agents 24` passed but reported
  `{mode:legacy-core, requested:24, core:24, total:25}`. It is deliberately **not** an N=24 receipt;
- exact total N24 uses `--total-agents 24`: run
  `20260813T122036664Z_8c36f56b613f499ab5a3e964bcda4c3a`, PASS, every row reports
  `{mode:total, requested:24, core:23, total:24}`, hard `12/12`, #40 `11/12`, #44/#45/#46 `12/12`,
  det `1/1`;
- focused P1-d provider run `20260813T122831151Z_5267960ed2b34186b9b6ce7fcb68cae0`
  passed on the exact product tree.

The population-mode discovery is a reusable contract: `--agents` is intentionally a legacy core
count and may not be cited as total population. New scale evidence must use `--core-agents` or
`--total-agents` and verify the JSON population object, not only the terminal verdict.

## Non-vacuous ON/OFF causal pair

`analysis/p1r/logistics_arm_probe.gd` is a read-only probe copied into isolated `git archive`
trees; it is not part of `game/` and therefore cannot change product or anchor inputs. It records
arrival/import/export/unload families, live queue size, #44/#45/#46 and two independent digests.

ON arm, exact archive `b0a501b`, pinned
`gamecraft-runner:4.6.2` (`sha256:90eaf3f8b60e15ea95de0c3e87e3276414c4cae1355b49471e9d2f52ddaaa33d`),
core23 + affiliate = total24, seeds 1-12 x 60d:

- every one of the 12 seeds contained all four families;
- totals: arrival `240`, import `167`, export `82`, unload `167`;
- #44/#45/#46 passed per seed; remaining live manifests are the expected arrived-minus-unloaded
  backlog rather than tombstones.

OFF arm removes only the resolved `%TEMP%/<archive>/game/data/logistics.json`, after checking the
absolute target stays beneath the isolated root. Seeds 1-3 x 20d, each run twice:

- logistics and live manifest/order queues are empty;
- arrival/import/export/unload are each exactly zero;
- #44/#45/#46 remain conditionally green;
- both digest summaries are equal between repeats.

Thus the positive grid is not vacuous, and the negative arm proves the subsystem truly disappears
rather than merely passing conditional invariants.

## R12 pre/post attribution and stop decision

The complement ledger was baked from game tree `eabcb07d8ffe6712abab4d46a0c7070aa96498dd`, reachable at
commit `366e37f33e6e06ba7e5fded5c7af0c31aebc2dff`. Between that tree and the frozen product tree,
37 game paths changed (about 5,908 insertions / 771 deletions), including the P1-a through P1-q
port, CargoManifest, atomic unload, live-queue retirement, warehouse, save-schema, authored-lane and
portal-authority vertical slices. Current `HARD_IDS` includes trade authority through #46, while the
old ledger lacks a valid `hard_ids_at_bake`. The drift therefore has an identified product cause; it
is not a random engine hash change.

Pinned Linux, read-only archive of the old anchor tree, held-out `13-30 x 60d x det1` produced S0
PASS, hard `18/18`, #40/#44/#45/#46 `18/18`, import/export `357/87` with full seed coverage. Complete
log SHA-256 is `c38777959be89dc0aa91cd53bfdf2eee0cf6d7de89d5867b3bcbcb04689cb172` under generated temp root
`p1r-pre-3729736e1a0f4a0eb1906e54d75e51e0`. The run printed the terminal PASS; PowerShell treated
Godot's exit-time ObjectDB warning as a native-command exception before the wrapper could print its
captured rc, so this is a complete verdict/log receipt but not claimed as a canonical supervisor rc
receipt. The post tree is independently supervisor-bound above.

Pre/post held-out comparison: hard stays `18/18`; #40 moves `18/18 -> 17/18` but remains within the
registered soft gate; import/export move `357/87 -> 252/59` and retain `18/18` coverage. That direction
is consistent with the intentional migration from nightly direct stock injection to an arrived
manifest that must be authorized and unloaded before stock can participate. The ON/OFF and atomic
transaction tests supply the causal teeth; no threshold was relaxed.

**Decision: anchor-finalize is technically prepared but not authorized in this batch.** R12 requires
Harness golden, DetGate golden and ModelPath anchor together, plus `rebake_history`, and complement
must be baked from the same committed exact tree. The latest completed review brief freezes a tip
before P1-o/p/q and remains REQUEST CHANGES, so it is stale evidence rather than the required fresh
delivery gate. The next trigger is a completed review cutoff that covers at least this committed
product tree and accepts the manifest/portal contracts, followed by one dedicated exact-tree
three-anchor + complement finalize batch and hosted CI. Until then PR #6 stays draft/unmergeable.

## Provenance, limitations, hygiene and recovery

No external code or asset was copied. The probe and conclusions use repository contracts and the
pinned runner. No README, art, map, cache, task, worktree or branch was archived/cleaned. The many
unrelated worktrees remain unknown-owner/active-protected. Generated logs remain under `%TEMP%` and
are rebuildable; only the compact probe/card/ledger are tracked.

Recovery: check out the topic commit containing this card, confirm its parent product tree is
`d3668111...`, copy `logistics_arm_probe.gd` into `game/bench/` of a `git archive` copy, run its ON arm
with `--core 23 --seeds 1-12 --days 60 --expect on --det 1`, then remove only the isolated
`data/logistics.json` and run `--seeds 1-3 --days 20 --expect off --det 2`. Require the exact ON/OFF
totals and per-seed assertions above before considering anchor-finalize.
