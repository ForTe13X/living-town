# Slice 235 — Plaza-facing mixed-use blocks

## Outcome

The civic center now reads as a town square held by street walls rather than a paved rectangle surrounded by unrelated buildings.

- A coordinated PixelLab frontage family replaces five weak generic façades on the north and south approaches.
- The chapel and mairie remain civic anchors. Attached shopfronts, a chamfered corner, narrow townhouses, and an arcade now form two denser supporting groups around them.
- The plaza stays deliberately larger than the surrounding lots. Its north–south spine, side approaches, seven facility doors, two plaza worksites, landmarks, and all interaction cells are unchanged.
- The change is presentation-only: existing lot positions, footprints, doors, navigation blockers, and simulation data remain intact.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All four reviewed frames were promoted; no temporary drawn substitutes were introduced.

Final common prompt:

> cohesive mixed-use frontage architecture for a refined French Atlantic coastal town square, low top-down pixel art game sprite, transparent background, warm natural summer light, pale weathered stone and cream stucco, slate and muted terracotta roofs, attached urban massing, detailed shutters, wrought iron balconies, awnings, flower boxes, gutters, shop windows and corner articulation, readable at game scale, no people, no vehicles, no signs, no text

| Saved asset | PixelLab object | Role |
|---|---|---|
| `game/assets/art/houses/plaza_mixed_block.png` | `cc214872-fd0c-44d0-bfaa-4644e3e27f7c` | long mixed-use shopfront block |
| `game/assets/art/houses/plaza_corner_block.png` | `e8e1c317-6f12-4c55-94ef-becbde402462` | civic-adjacent chamfered corner |
| `game/assets/art/houses/plaza_townhouse_pair.png` | `1a48319b-d347-4b88-94f8-c2d8cdd63091` | narrow attached townhouse pair |
| `game/assets/art/houses/plaza_arcade_frontage.png` | `3ab81a3c-5607-4d1a-9c12-f40ea90fcfbc` | arcaded market-side frontage |

Review pack: `93471b76-1946-4c40-816b-15c26d1dbfce`.

## Evidence

- [Plaza and its north/south frontage groups](media/235_plaza_blocks.png)
- [Whole-town massing and plaza hierarchy](media/235_town_blocks.png)

## Route and interaction contract

- Town walkable cells: 2,059, unchanged.
- Typed blockers: 582, unchanged.
- Seven town doors remain reachable and continue to enter real interior spaces.
- Plaza worksites at `[29,25]`, `[32,22]`, and `[34,22]` remain in place.
- `lint_data.py`, `audit_map.py`, `space_test`, and `player_touch_test` all pass.

## Simulation impact

The frontage swap has no simulation authority, and the monitored results confirm zero behavioral drift.

- N=12, seeds 1–12, 60 days: all hard invariants pass 12/12; all twelve seed digests and per-tick chains match the existing goldens.
- Repeat determinism passes 3/3.
- Soft invariant #40 remains 11/12, with the same known seed-6 seafood shortfall (0.48 satisfaction); no new abnormality appeared.
- Activity counts are byte-identical to Slice 234: civic duty 23 occurrences across 10/12 seeds, production 2,008, shortages 469, invitations 610, and every gated event class remains live.
- DetGate passes 16/16 across default, faction, betrayal, and free-rider tracks: hard invariants, repeat runs, data fingerprint `1763487750`, and goldens all match.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Whole-slice progress

- Landscape frame and road hierarchy: complete at the current macro level.
- Building diversity and street blocks: north frontage, upper town, seasonal coastal buildings, and the civic-center pair are now coherent; remaining loose areas are secondary neighborhoods.
- Plaza hierarchy: enlarged civic space retained and now framed by denser mixed-use architecture.
- Traversable elevation: two upper terraces and three distinct approaches are live.
- Interior direction: adaptive room scale, semantic room divisions, dense furniture, and multi-floor examples are live.
- Simulation monitoring: all recent visual/spatial slices are deterministic and covered by route, interaction, long-run, and authored-scenario gates.

## Coherent next candidates

1. **Beach civic life:** add bath cabins, promenade steps, café terraces, shade, and social interactions so the enlarged coast becomes a destination rather than scenery.
2. **Occupied-home specialization:** apply the two-floor room vocabulary to one resident household with owner access and resident-specific rooms.
3. **Secondary-neighborhood consolidation:** tighten the remaining loose southern rows with smaller attached pairs, without changing the main civic hierarchy.
4. **Elevation material polish:** improve cliff-to-street transitions and parapet continuity using the existing routes rather than adding more stairs.
