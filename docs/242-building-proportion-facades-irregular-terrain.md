# Slice 242 — Building proportion, façades, and irregular terrain

## Outcome

The oversized functional footprints now read as attached street blocks rather than single implausibly large buildings.

- Exterior and interior are now explicit camera states. Roofs are fully opaque below zoom `0.74` and cleanly removed at close cutaway scale; the former long semi-transparent transition is gone.
- Wide buildings split into three connected roof bays; deep buildings split around a narrow light court. This preserves authored navigation and interior utility while reducing their apparent mass.
- Residential, commercial, civic, and workshop footprints receive distinct PixelLab façade families, repeated as two or three attached bays according to footprint width.
- Terrain keeps its exact simulation grid, but exposed plateau rims and cliff-face height receive deterministic coordinate-hash variation. Adjacent north-rim endpoints share samples, so the visible contour varies without cracks, RNG, or camera-dependent drift.

## PixelLab asset-factory receipt

Mode: four-frame object review pack, 128 px, transparent background. All reviewed candidates were promoted and used directly.

Common prompt:

> cohesive exterior facade strips for functional buildings in a warm French Atlantic seaside town, low top-down pixel art game sprites, transparent background, three-quarter top-down facade view, pale weathered stucco and granite plinth, slate and muted terracotta roof edge, refined shutters windows doors gutters signs and planters, Eric Rohmer coastal town atmosphere, no people, no vehicles, no readable text

| Saved asset | PixelLab object | Runtime role |
|---|---|---|
| `game/assets/art/houses/functional_residential_facade.png` | `e18843ca-b07c-4764-809d-ec6b5106d6fd` | attached residential townhouse bays |
| `game/assets/art/houses/functional_commercial_facade.png` | `a0d01098-5885-4af5-be3b-b2fec7ee877b` | café and small-shop frontage |
| `game/assets/art/houses/functional_public_facade.png` | `d3361324-0c62-4921-8e03-1f641da9d80d` | bathhouse and library frontage |
| `game/assets/art/houses/functional_workshop_facade.png` | `c7a578f7-48da-4c59-a6eb-36e86c98ba0a` | artisan workshop frontage |

Review pack: `f2deaf41-e801-47b4-97cb-508319c09fbd`.

## Evidence

- [Whole-town proportion and opaque-roof read](media/242_proportion_facades_whole.png)
- [Attached residential and commercial frontage detail](media/242_functional_facades_close.png)
- [Workshop frontage and terrain-edge variation](media/242_irregular_terrace.png)

## Simulation impact

- `lint_data.py`, `audit_map.py`, and `space_test` pass.
- The map remains at 1,986 walkable cells and 582 typed terrain blockers; all six authored courtyard openings still pass.
- N=12, seeds 1–12, 60 days is byte-for-byte on the existing golden baseline: every hard and soft invariant is 12/12, all 21 gated event classes remain live, goldens are 12/12, and repeat determinism is 3/3.
- Production remains 1,977, shortages 438, invitations 750, aid coverage 9/12, and civic-duty coverage 8/12.
- The known missing NobodyWho GDExtension warning remains non-blocking.

## Whole-slice progress

The recent visual program now has a coherent town-scale stack: district hierarchy and main streets; perimeter building blocks and courtyard passages; larger, room-segmented multi-floor interiors; expanded beach civic life; street-corner activity compositions; and now corrected functional-building massing with real façade identities. All art-heavy additions use reusable PixelLab assets, while code is limited to placement, state, lighting, and deterministic composition.

## Coherent next candidates

1. **Terrain continuity:** author two or three reusable PixelLab cliff transition pieces for stairs, ramp cuts, and planted retaining walls; keep the hash contour as the connective system.
2. **Block-scale occupancy:** assign the visual bays of the largest blocks to mixed uses and named households without changing the town footprint.
3. **Night façades:** add window-light and closing-state variants driven by existing time and opening state.
4. **District wayfinding:** place a restrained sign and lamppost family at the already-authored main-street junctions, coordinated with map/HUD district names.
