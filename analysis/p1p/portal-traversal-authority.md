# P1-p portal traversal authority and player denial proof

Status: implemented and candidate/exact-product-tree verified on 2026-08-13. This is not an
anchor rebake, merge receipt, or hosted-CI green claim.

## Delivery target

P1-p closes one authority boundary end to end: every player or NPC space transition must resolve
an authored portal from the actor's current plane and position, prove access and navigation, and
then commit the address/cache/signal change atomically. Callers can no longer supply an arbitrary
portal dictionary to teleport an actor.

Three real schema-2 attacks motivated the batch:

- changing the player's saved `home_space` to `cafe` granted owner-stair access;
- changing the saved current plane to a valid but unauthorized `cafe/2f` bypassed the graph;
- changing only saved `_portals[].access` from `owner` to `public` split the disk SpaceGraph from
  Sim authority and let a normal player cross the owner stair through real UI input.

The accepted boundary is `Sim._try_traverse_portal`. It re-resolves a canonical edge, derives the
player/NPC reach rule internally, treats unknown access modes as denied, checks source and
destination navigation, proves owner access from an authored `owner_space`, and performs the
address mutation, path-cache invalidation and transition signal as one commit. Main clicks and NPC
journeys use the same boundary. The former raw `_traverse_portal` mutation surface is gone.

## Twelve coherent strides

1. Reconciled review, PR, worktree and Lore evidence without adopting stale snapshots blindly.
2. Reproduced raw-call, saved-home, saved-plane and saved-portal authorization bypasses.
3. Defined one checked, atomic traversal transaction and stable refusal reasons.
4. Made portal access, ownership and endpoint typing explicit in authored data/static validation.
5. Routed both Main player clicks and NPC journeys through the same authority function.
6. Bound successful commit to exact destination, cache erasure and one transition signal.
7. Made current-schema saved spaces, portals, homes and agent addresses exact authored contracts.
8. Added negative teeth for forged source/target/home, distance, one-way edges and blocked cells.
9. Added public-player and owner-NPC positives; corrected the Probe-only stair false-green label.
10. Re-ran save, projection, cargo, player and standard deterministic behavior gates.
11. Captured exact committed-product-tree positive and denied frames from the player's position.
12. Recorded provenance, limits, recovery, Git/PR boundary and hosted-CI follow-up.

## Contract and adversarial matrix

`space_test` covers public bidirectional travel, authored-owner travel, reverse/one-way behavior,
source mismatch, forged target, nonexistent edge, player-far/NPC-not-at-endpoint, blocked source and
destination cells, unknown access, exact signal count and cache clearing. Its prior warehouse
positive no longer calls a raw mutation helper.

`save_migration_test` mutates a legal schema-2 envelope one field at a time: portal id, access,
bidirectionality, cost, source and target; player home space/floor; current space/floor/position;
area and room; plus a coherent but unauthorized plane. Every arm requires `peek_save` to hide the
save, `load_game` to return false, and the polluted receiver snapshot to remain exact.

`SpaceShot --rt-deny-portal p_port_warehouse_door` is a presentation-only negative fixture. It
changes only the bench Sim instance after normal warmup, then drives the real `Probe.tapped ->
Main._portal_click -> Sim` path. Product data is not edited.

## Player-position presentation proof

Pinned inputs: product/game tree `a48ee586a54f4e7226b2fa53c24d529bdca92d05`, seed 3, tick
600, player `[57,8]`, 1280x768, Godot 4.6.2, Mesa 23.2.1, and
`gamecraft-runner:4.6.2@sha256:90eaf3f8b60e15ea95de0c3e87e3276414c4cae1355b49471e9d2f52dddaa33d`.

- Positive exterior reuses `docs/media/p1i_east_ocean_player.png`, SHA-256
  `2346d32d825f597bbc448d05283df213e07e48879925216bbec385a30ac4a60f`.
- Positive warehouse reuses `docs/media/p1i_east_ocean_warehouse.png`, SHA-256
  `8265f061bdc84ca44ae8772255645540cc967b07e7bed27a1beb74c0e4dd2ae1`.
- Denied exterior is `docs/media/p1p_portal_denied.png`, SHA-256
  `f9a5b306d46bb33eb6aed7e5f078106358a9fafa71be3824e9669406f8bfb669`.

The positive real-click roundtrip records `player_entered=true`, `player_returned=true`, identical
town camera, zero changed pixels between departure/return, and 98.59% interior/exterior difference.
The denied real-click arm leaves player, Probe, camera and cargo exact, shows the specific message
`东海货仓：私人区域，未获通行许可`, and changes 7,191 pixels only inside feedback bbox
`(16,496)-(225,589)` with zero pixels outside its asserted feedback region.

All visuals are real game framebuffer output using repository procedural art. No external art,
code or license entered the product. They are presentation receipts, not pixel goldens.

## Verification receipts

Stable candidate receipts under the canonical Windows supervisor:

- final portal authority scene: `20260813T100403836Z_887986b0c65f4a0ca8e9ff7f6e3a53e4`;
- save migration: `20260813T071148968Z_12b561`;
- state projection: `20260813T071014446Z_84d9`;
- P1-b/P1-c/P1-g/player-touch: `20260813T070613631Z_845d`,
  `20260813T070616274Z_d99e`, `20260813T070618683Z_bcce`,
  `20260813T070621747Z_50e`;
- player agency/P1-a/P1-d: `20260813T071152950Z_360d`,
  `20260813T071159456Z_3de`, `20260813T071203931Z_c9ca`;
- standard seeds 1-12, 60 days, det3, no golden:
  `20260813T071259625Z_b6b` (hard 12/12, no native/logic failure).

Static data lint, Python compilation, shell syntax, diff checks and exact expected-error scanner
self-tests also passed. A clean final-tip supervisor/grid rerun is required after the documentation
commit and is recorded in the baton handoff rather than back-editing this historical card.

## Boundaries, UX debt and recovery

This contract authenticates addresses against repository-authored topology; it is not a
cryptographic save signature. The denied receipt is now truthful and specific, but feedback is
still confined to the lower-left feed. The warehouse return door/prompt remains pressed by the
right and bottom player HUD. A later player-shell polish batch should add a local door-state/toast
and narrow-layout tooth without weakening this authority boundary.

Golden, modelpath and complement remain deliberately stale and untouched. PR #6 must remain draft
until committed exact-tip hosted checks, independent review and the authorized anchor-finalize
protocol close. Recovery is a normal revert of the P1-p topic and evidence commits; no generated
cache, protected branch, unknown-owner worktree or external source is required.
