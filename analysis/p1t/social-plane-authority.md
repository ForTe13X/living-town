# P1-t social plane authority

Status: implemented and exact-commit verified on 2026-08-14. This is a player/social authority
repair, not an anchor rebake, merge receipt, visual-redesign claim or approval of Draft PR #6.

Implementation commit: `6f6c5e132810abe1e084604bf3fb8ca9fa7f10d5`  
Exact game tree: `0859b1adff1367a534da4e83eeb44fae42326243`

## Single delivery target

Make every social transaction interpret `area` and grid coordinates only inside an authenticated
`(space,floor)` plane. Player preflight, external/backend apply, timed advance, final commit and
immediate mediation now share this rule, so a stale or malformed area cache cannot authorize a
cross-plane mutation. At the same time, the existing player promise — same non-empty area **or**
Manhattan distance at most two — is finally honored by all transaction layers.

The 2026-08-13 21:10 CST independent review was still in progress when this batch started. Its
provisional audit correctly noted that `player_act`, `_apply_social` and `_commit_social` did not
explicitly authenticate the plane. Live inspection refined that concern into two concrete defects:

- `player_act` accepted a one-tile same-plane pair straddling an area boundary, then `_apply_social`
  rejected it because only the cached area strings differed. The player received the misleading
  second-stage message `现在开不了口（对方刚走开？）` even though nobody moved.
- `_apply_social`, `_advance_social`, `_commit_social` and `player_mediate` trusted equal cached
  area strings. When the cache collided across another space/floor, the apply/commit paths bound a
  conversation or changed needs, relations, memories, conflict state and the event ledger.

This does not claim a canonical save currently emits such a collision: P1-p already validates
loaded agent addresses. The boundary still matters because `agent_apply` is an external-backend
surface and commit-time authority must not depend on every upstream cache writer remaining perfect.

## Twelve coherent strides

1. Froze branch, PR, review cutoff, exact product tree and dirty ownership.
2. Mapped player action, mediation, candidate, apply, advance and commit entry points.
3. Reproduced the area-boundary false-positive through the public `player_act` API.
4. Reproduced cross-space and cross-floor area-cache collisions at apply and commit.
5. Reused the established `_same_plane` address primitive rather than adding a second graph model.
6. Defined `_socially_reachable`: same plane, then same non-empty area or distance at most two.
7. Routed player preflight, apply, timed advance and commit through that single predicate.
8. Added the same-plane prerequisite to immediate three-party mediation.
9. Added exact no-op snapshots for entry, apply, commit, timed cancellation and mediation denial.
10. Added same-plane, adjacent cross-area, distance-negative and recovery-positive calibration arms.
11. Wired the focused scene into CI and ran adjacent player/portal/save/story plus deterministic grids.
12. Bound exact receipts, limitations, hygiene, Git/PR stop rules and next recovery trigger here.

## Contract and reusable fixture

`Sim._same_plane(a,b)` remains the address authority. `_socially_reachable(a,b)` first calls it;
only then can plane-local area/coordinate values participate. This ordering is intentional: two
identical `(x,y)` values in different floors have no spatial relationship.

NPC candidate enumeration remains the established `_nearby_agents` path, which already requires
same plane and same non-empty area. Therefore the default no-player candidate set is unchanged.
The distance alternative serves the existing player contract and fixes the natural area-edge case.
Mediation remains stricter: player and both parties must share one authenticated non-empty area;
the batch adds plane authority without silently redesigning mediation range.

`p1t_social_plane_test.gd` is the reusable adversarial fixture. Its projection snapshots actor
address/option/talking state, needs, inventory, relations, beliefs, memory, conflicts, commitments,
event log/digest and next-id/counter state. The matrix covers:

- direct same-plane positive, other-space negative and same-space/other-floor negative;
- candidate enumeration under a hostile cross-plane area collision;
- apply denial for cross-space and cross-floor collisions;
- truthful player-entry denial plus an exact no-op;
- adjacent same-plane actors on opposite sides of an area boundary;
- same-plane distance denial plus an exact no-op;
- independent commit denial under a hostile cache collision;
- timed transaction cancellation after plane divergence without ledger/relation mutation;
- cross-plane mediation denial with exact conflict/social state preservation;
- same-plane mediation recovery, proving the gate is not a permanent mask.

The pre-fix run `20260814T012227745Z_250d57c377d74b8690c7c44e2612bb78` printed nine failed
assertions. Its initial nonstandard final label did not match the supervisor's `*_test: FAIL`
sentinel, so the receipt outcome itself is **not** cited as a pass; the fixture was renamed to the
standard marker before integration. After the implementation, all sixteen assertions pass.

## Verification receipts

Exact implementation receipts under the canonical Windows supervisor, Godot 4.6.2:

- focused P1-t: `20260814T014119286Z_4d12fb4559264818b9a04fb6804f6d78`, `exact_commit`,
  source/game-tree stable, cleanup verified, no logic/native-crash marker, stdout SHA-256
  `1d3c02e923e803fc9dd388fc0f75dd98cb9f945d46f52d0f4446968a4be28e24`;
- standard seeds `1-12 × 60d × det3`, no `--golden`:
  `20260814T014129974Z_b667faa8918745a0b799c43bbabe4848`, `exact_commit`, source/game-tree
  stable, cleanup verified, hard `12/12`, soft/#40 `12/12`, #44/#45/#46 `12/12`, all seventeen
  liveness families present and deterministic repeats `3/3`. Stdout SHA-256 is
  `237e28d07fce5bb6c0310df904194896999c3476db20c4f24ffaee45fefc1a06`.

The exact standard stdout is byte-identical to the final dirty-candidate grid
`20260814T013414072Z_7aaa25ed90ac49c798aab0fe95ed0348`. All twelve seed rows also retain the
same digest/event-digest/chain values as the candidate, supporting the construction argument that
the default no-player trajectory is unchanged.

Adjacent focused receipts passed for `player_agency_test`, `player_touch_test`, `space_test`,
`save_load_test`, `save_migration_test`, `story_test` and `goals_test`; the post-fix P1-t receipt in
that same batch is `20260814T012432260Z_7d117b793b104e98a8184329935e5d59`. Static gates passed:
24 JSON files/13 agents, 64×48 map with all reachability/foreign-key checks, 224 Markdown files with
known branch-qualified escape flags only, `git diff --check`, and Docker `bash -n tools/ci.sh`.

An orchestration mistake gave the first standard-grid shell wrapper only 10 seconds. Its Godot child
was identified by the unique run token, allowed to finish once (PASS), and verified absent before
the canonical exact rerun above. It is retained as a failure lesson, not a supervisor receipt.

## Provenance, limitations, hygiene and recovery

No external code, art, research implementation or license enters this batch. Inputs are current
repository contracts, the read-only independent review thread
`019f555f-dfd4-7d91-aa6b-9655caa34871`, and locally generated headless receipts under `%TEMP%`.
No narrative/Jianghu semantic cherry-pick was needed. No sub-agent wrote files; all repository
ownership remained with the primary session.

This batch does not shorten the historical “same named area” social range, redesign the HUD, change
player selection, or add framebuffer evidence because rendering/layout is untouched. The in-progress
review's other provisional questions — East Ocean draw-versus-navigation consistency and whether the
milestone is an observation room or a live warehouse — remain open and are not smuggled into this
authority repair.

README/demo, protected branches, golden/modelpath/complement anchors, unknown-owner worktrees and
generated caches remain untouched. No archive or clean action occurred. Draft PR #6 must remain
draft/unmergeable: the latest completed review is still the stale 2026-08-13 09:00 REQUEST CHANGES,
the 21:10 review has not posted a completed verdict, and existing four evidence anchors remain stale.
The next recovery trigger is the completed review verdict; if it confirms the remaining East Ocean
product choice as a blocker, the next coherent batch should close that single draw/nav/milestone
contract before any R12 anchor-finalize run.
