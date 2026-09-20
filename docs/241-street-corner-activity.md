# Slice 241 — Street-corner activity compositions

## Outcome

Four important junctions now carry dense, purpose-specific everyday activity instead of another uniform pass of tiny scattered props.

- A produce-and-oyster market display marks the west approach to the plaza.
- A mismatched bistro terrace marks the café-side approach.
- A flower-and-herb bench anchors the residential end of the southern avenue.
- A cargo bicycle, handcart, parcels, baskets, and crates mark the transition into Harbor Works.

The props are authored as four coherent PixelLab compositions. They are not dozens of disposable code-drawn objects, and they are not repeated along every road. Each cluster is placed where a street changes role or meets a district edge.

## Data-driven rendering

`lots.json` now has a `street_details` layer beside districts, streets, lots, and gardens. Each record selects a reusable sprite and controls position, footprint used for visual alignment, scale, and mirroring.

`WorldView` loads this layer from data, trims transparent bounds, grounds each composition to its authored tile rectangle, applies the shared south-east shadow language, and draws it between gardens and building façades. The layer is presentation-only: it creates no invisible collision and never enters simulation objects, candidate actions, save state, or digests.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All four reviewed frames were promoted and used directly.

Common prompt:

> cohesive street-corner activity compositions for a warm French Atlantic beach town, low top-down pixel art game sprites, transparent background, weathered timber, pale stone, muted navy cream coral and leafy green, dense believable everyday detail, natural summer light, no people, no vehicles, no text

| Saved asset | PixelLab object | Placement and role |
|---|---|---|
| `game/assets/art/props/corner_market_display.png` | `23deaf31-f7dc-49a3-a840-c17cf32fdfe8` | `[26,19]`, west-plaza market approach |
| `game/assets/art/props/corner_cafe_terrace.png` | `7949b3d9-0fdd-462d-9e35-f8de03dc852d` | `[36,19]`, café-side plaza approach |
| `game/assets/art/props/corner_delivery_cluster.png` | `ca899cc0-d5c4-4a40-827d-84f923e404f1` | `[44,38]`, Garden Quarter–Harbor Works transition |
| `game/assets/art/props/corner_flower_bench.png` | `1dcb6652-faab-4ca6-8abf-1589b69307bf` | `[26,38]`, residential southern avenue |

Review pack: `807d0a41-ab30-4b85-9ea8-8725d33f2263`.

## Evidence

- [Market and café compositions framing the plaza approaches](media/241_market_corner_activity.png)
- [Flower bench and delivery cluster distinguishing the southern districts](media/241_south_corner_activity.png)

## Simulation impact

- `lint_data.py`, `audit_map.py`, and `space_test` pass. The map remains at 1,986 walkable cells, 582 typed terrain blockers, and exact 50/50 lot/solid-lot parity.
- N=12, seeds 1–12, 60 days remains exactly on the Slice 240 deterministic baseline: hard invariants 12/12, every soft invariant 12/12, all 21 gated event classes live, goldens 12/12, and repeat determinism 3/3.
- Production remains 1,977, shortages 438, invitations 750, aid coverage 9/12, and civic-duty coverage 8/12.
- The four scenario tracks remain on the already accepted Slice 240 16/16 DetGate baseline; Slice 241 changes only the view subscriber and presentation JSON.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Ordered-slice completion: 4 → 1 → 3 → 2

1. **4 · Occupied-home specialization:** Coco's enlarged, room-segmented two-floor home prototype is complete. Unsafe live occupancy was measured and rejected pending household logistics.
2. **1 · Beach civic-life district:** the south promenade is now a fifth visual district with café, changing cabins, pergola, and beach-rental cluster.
3. **3 · Courtyard access language:** three PixelLab perimeter blocks now have real, audited public gate/passage pockets.
4. **2 · Street-corner activity:** four data-driven PixelLab compositions now give the plaza, residential avenue, and Harbor Works transition distinct everyday life.

## Coherent next candidates

1. **South-beach activity contract:** add one bounded social/leisure interaction, then measure actual attendance, return-home travel, and winter/weather suppression before expanding it.
2. **Household logistics:** solve paid home restocking and cross-floor meal/sleep planning generally, then activate Coco's home and future named households without bespoke food exceptions.
3. **District wayfinding:** a small PixelLab sign/lamppost family tied to district and street names, with map/HUD labels appearing at the same authored junctions.
4. **Night identity pass:** authored window-light and closing-state variants for the beach café, market displays, and Harbor Works, driven only by existing time/open-state data.
