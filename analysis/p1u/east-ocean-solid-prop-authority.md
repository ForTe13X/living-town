# P1-u East Ocean solid-prop authority

Status: implemented and candidate-verified on 2026-08-14; exact-commit and hosted verification are
pending. This is a draw/navigation consistency
repair, not a warehouse redesign, anchor rebake, merge receipt, or approval of Draft PR #6.

Implementation commit: `6d4a983ceeb16c266675c2e2710a1e42322f5d14`

Exact game tree: `9ef3486cf98e5716d0eb635e9aa0d3585d6c9ace`

## Single delivery target

Make the East Ocean dock's visible solid props use one authored footprint for rendering, navigation,
current-save validation, schema-1 migration, map audit, focused tests, and visual evidence. The
boathouse, crate, barrel, and sacks must no longer be traversable scenery, while the warehouse portal,
functional port object, and Tao's dock position remain reachable.

The latest completed review is still the stale 2026-08-13 09:00 CST REQUEST CHANGES snapshot. The
2026-08-13 21:10 review remained in progress during this batch; its provisional audit separated
mechanical rebake readiness from product-semantic freeze and correctly identified East Ocean
draw-versus-navigation divergence. This batch closes only that concrete divergence. The separate
observation-room versus live-warehouse milestone choice remains open.

## Twelve coherent strides

1. Froze branch, PR, review cutoff, product tip, dirty ownership, and stop rules.
2. Inventoried every dock draw footprint, blocker, portal, interaction, and agent position.
3. Captured a pre-fix counterexample proving all five visibly solid cells were walkable.
4. Defined one minimal ordered `dock.solid_props` contract instead of a parallel collision model.
5. Authored four records/five cells and migrated Tao from sacks `[58,8]` to open dock cell `[59,7]`.
6. Made Sim block those cells and validate the same authored records in current saves.
7. Made WorldView draw the same records without changing the established pixel geometry.
8. Added schema-1 evacuation, current-save corruption teeth, path/interaction positives, and OFF/ON arms.
9. Extended map audit and CI ownership to cover footprint containment, overlap, reachability, and the scene.
10. Captured plain/nav-overlay East Ocean frames and ran the full presentation assertion matrix.
11. Ran focused, migration, carrier, portal, static, shell, and deterministic standard candidate gates.
12. Bound receipts, provenance, limitations, hygiene, Git/PR state, and recovery triggers here.

## Root counterexample and contract

Before the repair, `dock.rect=[56,7,4,2]` drew a 1×2 boathouse at `[56,7]`, a crate at `[57,7]`,
a barrel at `[58,7]`, and sacks at `[58,8]`. All five cells were walkable; only the functional port
object at `[59,8]` blocked navigation. Tao also spawned at `[58,8]`, visibly inside the sacks.
`p1u_port_nav_test` recorded eleven failed pre-fix assertions in supervisor receipt
`20260814T023108558Z_704f4f0f29604d189f4f47c267655d42`.

`map.json.areas.dock.solid_props` is now the canonical ordered record set. Each record has stable
`id`, supported `kind`, integer `pos`, and positive integer `footprint`. Sim expands exactly those
records into blocker cells; WorldView dispatches drawing by the same `kind`; `audit_map.py` checks
shape, uniqueness, containment, disjointness, Tao/portal openness, and connectivity.

Current-schema saves must reproduce the authored dock records exactly. Schema-1 migration injects
the current seam and deterministically evacuates an agent found on a newly solid cell before current
validation. Its bounded breadth-first search never leaves the saved map. Tao's legacy authored
home/position receives the explicit `[59,7]` migration; other legacy occupants use the nearest open,
non-object town cell. The visual OFF arm removes `solid_props` from a test-local world copy and must
remove exactly five blockers; restoring the records must restore exactly those five cells.

## Reusable tests and candidate verification

`p1u_port_nav_test.gd` covers the four exact records and five projected cells; all five live blockers;
open portal and Tao cells; OFF/restore symmetry; Tao migration; player movement denial into adjacent
props; open south movement; exact A* reachability to the warehouse portal; port interaction; valid
current-save roundtrip; and two offline corrupt-save arms (player inside sacks and forged prop kind).
Both corrupt saves are hidden by `peek_save`, rejected by `load_game`, and preserve the receiver
projection exactly.

Candidate receipts under the canonical Windows supervisor and Godot 4.6.2:

- P1-u PASS: `20260814T024648929Z_890cd223f7e2499e89b4977313b9dcc5`;
- save migration PASS: `20260814T024702573Z_383de173f3954c44bbb1d47ece8016a8`;
- East Ocean carrier PASS: `20260814T024721897Z_d9497f3fa8fb4b3dbd2de13430a875d4`;
- portal/space PASS: `20260814T024736251Z_36765ff87a60456c831de454520cde67`;
- standard `1-12 × 60d × det3`, no golden: `20260814T025555299Z_ef4074f42878407eb5b69da74685bafc`,
  hard `12/12`, soft/#40 `11/12` (seed 11 food `0.45`), #44/#45/#46 `12/12`, import/export
  `164/48` covering all twelve seeds, all seventeen liveness families present, determinism `3/3`,
  stdout SHA-256 `EAE92A13E0B723FF8CF5AB58B20DE05B7DDE192379A1A4D8023A1FEF061CDBB9`.

Static gates passed for 24 JSON files/13 agents, the full 64×48 map contract, JSON parsing,
`git diff --check`, Docker shell syntax for CI/visual/roundtrip scripts, and Python compilation with
`PYTHONPYCACHEPREFIX=/tmp/pycache` on the read-only mount.

## Visual resource pool

Both frames are generated/rebuildable repository assets captured with `gamecraft-runner:4.6.2`,
Godot 4.6.2, seed 3, tick 600, player `[57,8]`, 1280×768. They use only existing procedural game
art; no external art, code, or license enters the repository.

- `docs/media/p1u_east_ocean_plain.png`: 240,703 bytes, SHA-256
  `85D74F8DBF067095A40A045B6EC78AD1E063AA07BC63DC970F07A697D0A3E27B`;
- `docs/media/p1u_east_ocean_nav.png`: 247,404 bytes, SHA-256
  `AC79610EBD1A4D539EA7B53D2F8AA255D9C3294770CE46C1E167096CB4AE38A1`.

The nav frame visibly overlays exactly the boathouse's two cells plus crate, barrel, and sacks; the
warehouse portal/player cell and Tao's new dock cell remain open. These are presentation receipts,
not protected pixel goldens.

The pinned image produced all 37 full visual-gate frames. Its internal Python lacks Pillow, so the
all-inside assertion phase correctly stopped as infrastructure-incomplete. The intended split was
then used: Docker captured the frames and the bundled workspace Python asserted them. Day/night,
carrier ON/OFF, town/cafe/warehouse roundtrips, warehouse panel OFF, corrupt-manifest presentation,
pond, seven interiors, furniture roles, trees, precipitation, cafe 2F, and floor roundtrip all PASS
at tolerance zero. This split evidence is green; the failed all-inside invocation is not relabeled.

## Failure lessons, limits, hygiene, and recovery

An initial supervisor invocation put `--headless` in the executable slot and was immediately
corrected. A later `var next :=` parse typo prevented the scene from instantiating, so the supervisor
waited to timeout; its uniquely owned process was cleaned and the typed declaration fixed. A Docker
`py_compile` on a read-only mount first attempted local `__pycache__`; the rerun used a temp prefix.
These are retained as orchestration lessons, not product failures or passes.

This repair changes default navigation and therefore legitimately changes default simulation
digests. It does not decide whether the milestone is an observation room or live warehouse, polish
the warehouse shell, redesign the HUD, or authorize any protected anchor update. README/first-screen
demo, protected branches, unknown-owner worktrees, golden/modelpath/complement anchors, and unrelated
tasks remain untouched. No archive or clean action occurred.

Draft PR #6 must remain draft/unmergeable. The four protected evidence anchors are still stale, the
latest completed review is stale REQUEST CHANGES, and the newer review has not posted a completed
verdict. The next recovery trigger is a completed review covering this product tree; any remaining
warehouse-semantic blocker must close before the controlled anchor-finalize protocol may run.
