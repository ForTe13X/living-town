# Slice 234 — Upper-town street pair

## Outcome

The upper town is now a connected two-terrace district rather than one scenic platform.

- `upper_lane` adds a second ten-by-five public terrace immediately beneath the existing north frontage.
- The existing Paris corner block and the former generic terrace now read as one attached street wall; the latter uses the PixelLab `paris_streetwall` façade at an authored scale.
- Eight typed cliff-wall cells create the second parapet while preserving two distinct crossings: a central switchback stair and an eastern arched passage.
- The earlier grand stair remains the primary western approach. The two terraces connect laterally, so the district has route choice rather than isolated destinations.
- PixelLab hydrangea planters and floor lanterns establish façade/parapet rhythm across the broad paving without adding another road.
- A real upper-lane bench advertises `坐看街景` (`fun +32`, duration 16), making the new street simulation-active.

## PixelLab reuse receipt

No new generation was needed. This slice deliberately consumes retained asset-factory output instead of generating near-duplicates or drawing temporary substitutes.

- `cliff_switchback_stairs.png` — PixelLab object `6b044399-cf5d-420a-9180-9b996122464a` from Slice 232.
- `cliff_arch_passage.png` — PixelLab object `40d8f138-93e3-4676-a176-89824a2d64d7` from Slice 232.
- `public_hydrangea_planter.png` — PixelLab object `f2208815-d828-498d-9d1d-7dcf33824909` from Slice 230.
- `public_floor_lantern.png` — PixelLab object `2d6b0de8-a784-430f-867a-29a31d25c7cf` from Slice 230.
- `paris_streetwall.png` — PixelLab object `417e1f22-b954-496c-9c36-f910196c03be` from Slice 231.

## Evidence

- [Connected upper-town terraces, frontage, stairs, arch, and street furniture](media/234_upper_lane.png)

## Route and map contract

- Town walkable cells: 2,059.
- Typed blockers: 582.
- New solid cells: eight parapet cells plus one advertised bench cell.
- Both stair gaps and the arched eastern approach remain connected to the lower town.
- `audit_map.py` passes full reachability, object interaction-neighbour, typed-layer, lot, worksite, and redundant-route checks.

## Simulation impact

The new bench intentionally changes free-running behavior, so both standard and scenario goldens were reviewed and rebased.

- N=12, seeds 1–12, 60 days: all hard invariants pass 12/12; determinism passes 3/3.
- Soft invariant #40 remains 11/12. Seed 6 now reports seafood satisfaction 0.48 instead of the previous pastry fluctuation; the overall threshold and one-seed scope are unchanged.
- Civic-duty coverage improves from 8/12 to 10/12 seeds, with occurrences rising from 14 to 23.
- Production occurrences rise from 1,971 to 2,008; shortage events fall from 546 to 469.
- Invitations fall from 839 to 610, but remain live in every seed. Confide remains live in 11/12 seeds and all 21 gated event classes remain active.
- Scenario impact is localized: three of four default seeds change; faction, betrayal, and free-rider tracks remain byte-identical.
- Final scenario gate: hard 16/16, repeat 16/16, data fingerprint 16/16, golden 16/16.
- Space and player-touch gates pass; the pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Whole-slice progress

- Landscape frame and road hierarchy: implemented.
- Dense street blocks and façade diversity: implemented, with the upper north frontage now reading as an attached block.
- Traversable elevation: two linked terraces, three visually distinct lower-town approaches, and two simulation-active upper destinations are implemented.
- Interior vocabulary: semantic rooms, walkable doors/arches, dense furniture, and two-floor examples are implemented.
- Simulation monitoring: all current spatial additions are deterministic and covered by long-run and authored-scenario gates.

## Coherent next candidates

1. **Street-block consolidation around the plaza:** replace loose frontage with two continuous mixed-use blocks while preserving all doors and worksites.
2. **Beach civic life:** give the enlarged shore bath cabins, promenade steps, café terraces, and social interactions.
3. **Occupied-home specialization:** apply the two-floor room vocabulary to one resident household with owner access and resident-specific rooms.
4. **Elevation polish without new routes:** improve cliff material transitions and parapet continuity using the current three approaches rather than adding more stairs.
