# Slice 237 — Reference-led perimeter blocks and courtyards

## Outcome

The broad lawn belts around the plaza and southern avenue now contain four compact, attached-building compositions instead of reading as leftover space.

- A three-bay commercial block extends the west plaza approach.
- An L-shaped residential block gives the east plaza edge an inhabited courtyard frontage.
- A varied-height garden row closes the open gap beside the southern workshops.
- A granite-and-timber workshop row strengthens the Harbor Works street wall near the beach.
- Each composition contains several attached façades, varied roofs, gates, planting, or work clutter, so one solid navigation footprint reads as a small urban block rather than one oversized house.
- The plaza, functional-building doors, beach access, and the two main cross-town movement bands remain open.

The reference images were used for spatial principles rather than copied literally: dense perimeter blocks, irregular planted voids, continuous street edges, mixed roof heights, and a readable hierarchy between main avenues and smaller approaches.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All four reviewed frames were promoted and used directly.

Common prompt:

> compact perimeter-block architecture for a warm French Atlantic seaside town, low top-down pixel art game sprite, transparent background, coherent pale stucco and weathered granite, muted terracotta and slate roofs, attached urban massing, small planted courtyard glimpses, refined shutters balconies awnings gutters and roof variation, natural summer light, no people, no vehicles, no text

| Saved asset | PixelLab object | Placement and role |
|---|---|---|
| `game/assets/art/houses/infill_residential_courtyard.png` | `02c06002-ea67-4a46-a756-af3c180657a3` | `[38,21]`, 4×3; east plaza residential courtyard |
| `game/assets/art/houses/infill_market_block.png` | `63ed2cd0-b021-450a-b85b-bcc25c655c0b` | `[14,21]`, 4×3; west plaza commercial frontage |
| `game/assets/art/houses/infill_garden_row.png` | `78a598f7-21c5-4452-9d94-d84405b80244` | `[40,36]`, 4×3; Garden Quarter attached homes |
| `game/assets/art/houses/infill_harbor_workshops.png` | `e600646e-8b7f-4fa2-b77d-42fed5c0f838` | `[52,35]`, 3×4; Harbor Works attached sheds |

Review pack: `43b2e197-c648-4f73-a46d-bb4acaf9eccb`.

## Evidence

- [Whole-town block structure](media/237_perimeter_blocks.png)
- [Plaza-edge market and residential courtyards](media/237_market_courtyards.png)
- [Southern garden row and harbor workshops](media/237_south_infill.png)

## Navigation and simulation impact

- Visual lots and simulation `solid_lots` remain in exact 46/46 parity.
- The four new blocks occupy 48 cells; walkable cells move from 2,059 to 2,011. Static typed blockers remain 582.
- `audit_map.py` confirms full reachability, all object/worksite approaches, and all seven functional building doors.
- `space_test`: 0 failures. `player_touch_test`: pass.
- N=12, seeds 1–12, 60 days: hard invariants 12/12, all soft invariants at 12/12, all 21 gated event classes live, repeat determinism 3/3, and rebased goldens 12/12.
- Supply soft invariant #40 improves from 11/12 to 12/12; the former seed-6 seafood-satisfaction miss does not recur.
- Aggregate production shifts 2,008 → 1,977 and shortages 469 → 438. Invitations rise 610 → 750. Civic-duty frequency shifts 23 → 16 but remains live in 8/12 seeds, above its required 6/12 coverage.
- DetGate passes 16/16 across default, faction, betrayal, and free-rider tracks. The reviewed route change intentionally rebases the data fingerprint to `3490703449`.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Whole-slice progress

- Landscape boundary, forest/mountain enclosure, and single land entrance: implemented.
- Four district identities and three main-street axes: implemented.
- Dense building language: upper-town rows, plaza frontages, garden-quarter rows, harbor workshops, and planted courtyard blocks are now represented.
- Building scale and façade coverage: normalized, with district-specific and block-specific PixelLab assets.
- Interior richness: representative homes, commerce, civic, and service spaces have rooms, larger furniture, stairs, and multi-floor navigation.
- Simulation monitoring: navigation, portals, interaction equivalence, long-run economy, deterministic replay, and four scenario tracks remain green after the new detours.

## Coherent next candidates

1. **Beach civic-life district:** promenade cafés, changing cabins, shade structures, steps, seating, and social interactions so the enlarged coast becomes an active fifth district.
2. **Street-corner activity:** reusable PixelLab prop kits for market tables, café chairs, delivery stacks, bicycles, handcarts, and flower displays at the three main-street junctions.
3. **Courtyard access language:** restrained arches, gates, short passages, and one or two explorable shared courtyards without opening every decorative building.
4. **Occupied-home specialization:** apply the mature room and multi-floor vocabulary to a named resident household connected to the denser street block.
