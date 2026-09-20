# Slice 233 — Room-plan vocabulary and two-floor seaside home

## Outcome

This slice turns the small `home2` interior from one mixed furniture room into a reusable two-floor residential pattern.

- The ground floor is divided into a living room and a kitchen/dining room by real blocking partitions and a walkable arch.
- The upper floor contains a bedroom/study, enclosed bathroom, and stair landing connected through a walkable framed doorway.
- `rooms[]` metadata now gives authored room purpose, bounds, labels, and restrained floor tinting without creating a second navigation model.
- `doorway` and `archway` are first-class walkable furniture slots. Their appearance no longer depends on unexplained holes in partition walls.
- The home uses the canonical bidirectional portal graph for its stairs; the staircase and upper landing are visible PixelLab compositions on the same authoritative endpoints.
- Furniture density comes from larger compositions, storage, lighting, bathing fixtures, plants, and wall details while preserving a continuous circulation route.
- Furniture art accepts an authored `art_scale`, allowing reusable 128 px assets to fit different spatial roles without destructive image resizing or room-specific draw code.

## PixelLab asset receipt

Mode: 1-direction review pack, 128 × 128 px, transparent background; all four reviewed candidates promoted.

Source review: `dbf061b2-29da-4b8b-bf9d-159e7957f697`

Prompt: `cohesive room transition kit for an elegant lived-in French Atlantic townhouse, low top-down pixel art, transparent background, warm walnut wood, cream plaster, pale weathered stone, muted teal and brass accents, sophisticated domestic details, readable at game scale, no people no text`

- `80f9062f-0763-4a72-b47a-cd681e7e4273` → `game/assets/art/furn/room_archway.png`
- `0ab45e7c-31d5-4f2f-9024-25aa1f49c731` → `game/assets/art/furn/room_doorway.png`
- `ddda3aa4-7b1f-4cfe-9efe-3ec9056261a1` → `game/assets/art/furn/residential_stairs.png`
- `c532f455-8ec5-42e2-8286-d926620a1e0b` → `game/assets/art/furn/residential_landing.png`

## Evidence

- [Ground floor — living room and kitchen/dining room](media/233_home2_1f.png)
- [Upper floor — bedroom/study, bathroom, and landing](media/233_home2_2f.png)

## Navigation and visual review

The first upper-floor draft placed a two-cell bathtub across the only route from the stair landing to the doorway. Full-frame review caught the isolation. The bathtub footprint was reduced to one authored cell and bedroom storage was placed around, rather than across, the remaining route.

Recomputed interior navigation:

- `home2/1f`: 21 open cells; street-door and stair endpoints belong to one connected component.
- `home2/2f`: 20 open cells; every open cell is reachable from the stair endpoint.
- Doorway, archway, stair, rug, and window slots are explicitly walkable; partitions and solid furniture remain blockers.

## Verification and simulation impact

- JSON lint and map audit: pass.
- Godot import and script parse: pass.
- `space_test`: 0 failures; portal schema, access control, bidirectional stairs, and canonical player transactions remain valid.
- `player_touch_test`: pass.
- N=12, seeds 1–12, 60 days: every digest, event digest, tick-prefix chain, and invariant result is byte-identical to Slice 232.
- Hard invariants: 12/12. Determinism: 3/3. Civic duty: 8/12 seeds. The existing pastry-supply soft miss remains #40 at 11/12.
- Scenario gate: hard 16/16, repeat 16/16, data fingerprint 16/16, golden 16/16. No golden rebake was required.
- Godot continues to print the pre-existing missing NobodyWho GDExtension warning; it is unrelated and non-blocking.

## Whole-slice progress

- Outdoor composition: one land road, mountain/forest frame, open coast, larger beach/plaza, denser blocks, and traversable upper-town stairs are implemented.
- Building presentation: seasonal façades, attached street walls, cliff housing, and scale-aware architecture are implemented.
- Interior system: variable bounds/camera support, large semantic furniture art, partition walls, room-purpose zones, walkable arches/doors, and public/private multi-floor examples are implemented.
- Simulation safety: new presentation and room-layout vocabulary remains deterministic and does not alter the established 60-day behavior grid.

## Coherent next candidates

1. **Upper-town street pair:** use the retained cliff switchback and arch-passage assets to create a second traversable terrace and compact attached block.
2. **Residential variety:** apply the room vocabulary to one larger occupied home, with resident-specific bedrooms and owner access rather than cloning this layout everywhere.
3. **Street-block consolidation:** replace loose plaza/north-avenue frontage with two intentionally authored continuous blocks.
4. **Beach civic life:** build promenade steps, bath cabins, café terraces, and social props into a functioning shore district.
