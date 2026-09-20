# Slice 243 — Terrain transition compositions

## Outcome

The irregular procedural terrace from Slice 242 now has authored focal transitions instead of relying on noise everywhere.

- Six data-authored placements connect long cliff runs to existing stairs, upper streets, southern lawns, and the beach approach.
- A planted retaining wall terminates straight terrace stretches.
- A broad cobbled ramp visually crosses the southern terrace face instead of floating in open grass.
- Rock corners and exposed cliff sections break repeated rectangular silhouettes.
- Existing grand stairs, switchback stairs, and arch passage remain the primary northern access landmarks.

The deterministic hash contour remains the connective terrain material. PixelLab pieces are reserved for compositionally important transitions, keeping the landscape rich without turning every tile into a unique disposable asset.

## Data and rendering contract

`lots.json` now contains a `terrain_details` presentation layer. Each record declares sprite, position, visual footprint, scale, and optional mirroring. `WorldView` trims transparent bounds, grounds the sprite to the authored footprint, and applies the shared south-east shadow language after procedural cliff faces.

This layer adds no blockers, portals, traversal cost, simulation objects, or save-state fields.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All reviewed frames were promoted and used.

Common prompt:

> cohesive terrain transition kit for a warm French Atlantic cliffside beach town, low top-down pixel art game sprites, transparent background, three-quarter top-down view, weathered pale granite, moss, hydrangea and summer grasses, irregular natural silhouette, detailed but readable, Eric Rohmer coastal atmosphere, no people, no vehicles, no text

| Saved asset | PixelLab object | Role |
|---|---|---|
| `game/assets/art/houses/terrain_retaining_wall.png` | `376ccd92-5a5c-418b-8138-5eb97b713821` | planted termination for long terrace faces |
| `game/assets/art/houses/terrain_ramp_cut.png` | `4060b7a3-a5bf-43d3-826e-4be70df50ff7` | broad cobbled elevation transition |
| `game/assets/art/houses/terrain_rock_corner.png` | `c257f373-42c0-4ab4-b1af-a304735091c5` | planted corner and silhouette break |
| `game/assets/art/houses/terrain_cliff_face.png` | `d96faa59-5f98-47c3-b898-b24b078cc5ab` | exposed natural rock focal section |

Review pack: `b09a4692-524d-45cd-9bba-6a5621c8c92b`.

## Evidence

- [North upper-street transitions](media/243_north_terrain_transitions.png)
- [South ramp and planted retaining walls](media/243_south_terrain_transitions.png)

## Simulation impact

- `lint_data.py`, `audit_map.py`, and `space_test` pass.
- The map remains at 1,986 walkable cells and 582 typed terrain blockers.
- All existing courtyard openings, doors, stairs, and authority checks remain valid.
- N=12, seeds 1–12, 60 days remains exactly on the accepted golden baseline: every hard and soft invariant is 12/12, all 21 gated event classes remain active, goldens are 12/12, and repeat determinism is 3/3.
- Production remains 1,977, shortages 438, invitations 750, aid coverage 9/12, and civic-duty coverage 8/12.
- The known missing NobodyWho GDExtension warning remains non-blocking.

## Coherent next candidates

1. **Mixed-use block occupancy:** divide the largest exterior blocks into visible household and shop bays tied to existing interior spaces.
2. **Night façade identity:** reusable lit-window and closed-shop states driven by existing time/open-state data.
3. **District wayfinding:** coordinated sign, address plaque, and lamppost family at the authored main-street junctions.
4. **Beach–town seam:** one continuous promenade composition joining plaza activity, changing cabins, sea wall, and cliff approach.
