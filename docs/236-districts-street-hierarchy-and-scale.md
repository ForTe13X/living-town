# Slice 236 — Districts, street hierarchy, and building scale

## Outcome

The town now reads as a planned coastal settlement rather than a collection of buildings connected by incidental paths.

- Four explicit presentation districts organize the map: Upper Town residential, Market Quarter commercial, Garden Quarter residential, and Harbor Works industrial.
- Three main streets establish hierarchy: Rue des Halles binds the northern frontage, Avenue du Marché links it to the plaza, and Rue des Jardins anchors the southern residential row.
- Main streets use narrow sun-faded surfaces, granite gutters, soft bends, wear patches, and no highway center markings. Existing door paths remain smaller feeder lanes.
- Wide 7–9 tile functional buildings now render as three attached roof masses. Their physical interiors and navigation footprints are unchanged, but they read as coherent street blocks instead of single oversized houses.
- Five excessive authored façade scales were reduced, and the compact plaza frontage pieces were normalized to their two-tile footprints.
- Missing/generic building faces were replaced with district-specific residential, commercial, civic, and industrial PixelLab façades.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All four reviewed frames were promoted and used directly; no disposable placeholder art was added.

Final common prompt:

> architectural front-elevation modules for a French Atlantic seaside town in low top-down pixel art, transparent background, warm natural summer daylight, weathered local materials, refined readable facade depth, compatible with a 48 pixel tile game, no people, no vehicles, no lettering, no signs with text

| Saved asset | PixelLab object | Use |
|---|---|---|
| `game/assets/art/houses/district_residential_facade.png` | `edb7ae1d-1f31-4434-a8f3-3d63dbffbeb1` | southern residential frontage |
| `game/assets/art/houses/district_commercial_facade.png` | `82b05428-fcd3-49f9-9500-c6cf5bfa334b` | Market Quarter shop frontage |
| `game/assets/art/houses/district_civic_facade.png` | `cd4da640-26b6-47c5-9306-21f79a9b77e7` | mairie/civic frontage |
| `game/assets/art/houses/district_industrial_facade.png` | `f4342ae3-f8cc-44c7-83cb-691751533245` | Harbor Works frontage |

Review pack: `6234e4b4-7169-4c0e-a34b-18c64bc321bc`.

## Evidence

- [Whole-town district structure, road hierarchy, and rebalanced massing](media/236_district_plan.png)
- [Market Quarter, Rue des Halles, and Avenue du Marché](media/236_market_streets.png)
- [Garden Quarter and Harbor Works frontage](media/236_south_districts.png)

## Technical contract

- District and main-street definitions live in `assets/art/houses/lots.json`, not simulation map authority.
- Main streets are drawn beneath buildings; they do not create walkable cells, remove blockers, or overwrite doors.
- Town walkable cells remain 2,059; blockers remain 582.
- All 42 visual lots match their `map.json` position, footprint, and sprite metadata.
- Seven town doors remain reachable and enter real interior spaces.

## Verification and simulation impact

- `lint_data.py`, `audit_map.py`, `lint_links.py`, the 42-lot parity check, and the 4-district/3-street plan check pass.
- `space_test`: 0 failures.
- `player_touch_test`: all controls and interaction equivalence checks pass.
- N=12, seeds 1–12, 60 days: all hard invariants pass 12/12; goldens and per-tick chains match 12/12; repeat determinism passes 3/3.
- Soft invariant #40 remains the same known 11/12 result: seed 6 seafood satisfaction is 0.48. No new abnormality appeared.
- Activity is unchanged from Slices 234–235: civic duty 23, production 2,008, shortages 469, invitations 610, and all 21 gated event classes remain live.
- DetGate passes 16/16 across default, faction, betrayal, and free-rider tracks. The presentation metadata changes the data fingerprint to `2927165072`, while every simulation digest and golden remains unchanged.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Whole-slice progress

- Landscape boundary and single land entrance: implemented.
- District structure: four readable quarters now exist as explicit presentation data.
- Street hierarchy: three narrow main streets plus smaller door lanes now organize the map.
- Building blocks: upper-town, civic-center, northern commercial, southern residential, and harbor-work rows all have attached frontage logic.
- Building scale: decorative outliers normalized; oversized functional shells articulated as multi-building blocks.
- Façade coverage: district-specific residential, commercial, civic, and industrial fronts are present.
- Interior richness and multi-floor navigation: implemented in representative buildings.
- Simulation monitoring: route, portal, interaction, long-run, and four-track scenario gates remain green.

## Coherent next candidates

1. **Beach civic-life district:** make the coast a true fifth district with cabins, promenade cafés, shade, steps, and social interactions.
2. **Street-corner activity:** add market tables, café seating, delivery stacks, bicycles, and notice points where main streets meet the plaza.
3. **Occupied-home specialization:** apply the multi-floor room vocabulary to a named resident household.
4. **District navigation language:** add restrained street-name plaques and a compact map overlay without placing large labels over the world.
