# Slice 231 — Landscape frame, street blocks, and room plans

## Outcome

This slice changes the town at composition scale rather than polishing isolated props:

- The west edge is now one quiet two-way land entrance connected to the main street. The former multi-lane / switchback reading is gone.
- A PixelLab mountain-and-woodland crown frames the north, west, and south edges. The east remains open to the sea.
- The beach is five tiles deep and the plaza paving grows one tile into all four approaches, so both read as civic landscape rather than building-sized objects.
- Decorative façades may overhang their navigation lots by an authored scale. This tightens street walls without moving doors or collision footprints.
- Four seasonal coastal façades, an attached Parisian street wall, a corner block, and two cliff-house compositions replace repeated house silhouettes.
- Furniture may use a separate `art` field while keeping its semantic slot, interaction, and footprint. Large 128 px sofa, dining, library, and market compositions now provide visual mass.
- The hotel has a public second floor. Three guest rooms are separated by real blocking partition walls, connected by door gaps to a corridor, and reached through a bidirectional stair portal.

## Visual translation

The Rohmer references are translated as design principles, not copied imagery: pale Atlantic stone, slate roofs, warm natural summer light, vegetation against masonry, and a readable beach-town skyline. The Paris street reference contributes continuous façades, narrow frontage rhythm, iron balconies, arcaded ground floors, and corner massing.

The elevation pass deliberately has two levels of commitment:

1. Existing authored terrace cells still draw real cliff faces and remain part of the outdoor layout.
2. PixelLab cliff-house compounds make the elevation legible immediately. A future slice can turn the upper town into a separate traversable height plane after stair/ramp routing is designed and tested.

## PixelLab asset receipt

Mode for all assets: 1-direction review packs, 128 × 128 px, transparent background, promoted after visual review.

### Landscape boundary kit

Source review: `5109ce6f-0f88-44eb-adb2-16d8998cf77d`

Prompt: `cohesive landscape boundary props for a refined coastal French pixel-art town, low top-down view, transparent background, painterly natural light, granite and deep layered foliage, readable silhouette, no road, no buildings`

- `6112e4c8-03a7-431e-953a-189d470d63fc` → `boundary_mountain_ridge.png`
- `64a06a9a-3160-4997-a5f1-f3bde8733d7c` → `boundary_woodland_grove.png`
- `a90b2c61-06cf-4954-8e1c-a608ea1d3190` → `boundary_granite_outcrop.png`
- `e6ac2c7d-8222-4e58-826e-768113a83480` → `boundary_wooded_hill.png`

### Seasonal façade kit

Source review: `866e39af-8421-446d-ad2a-45b026c64e7b`

Prompt: `cohesive polished small French coastal village buildings inspired by natural-light seasonal cinema, low top-down pixel art, transparent background, quiet lived-in realism, distinct texture and silhouette, no signs or text`

- spring cottage `19641927-554f-4f77-a4a3-3357319b530d`
- summer shop `5d571d14-8d6d-4de1-b506-69983b2c6b30`
- autumn townhouse `f1c13692-e058-4b73-a4c6-1815d83df913`
- winter house `454d93f5-0e74-4132-8626-b82a3787031d`

### Large furniture kit

Source review: `514bc6b0-906e-4602-98fe-0a1e83e945bd`

Prompt: `cohesive large-scale furniture for a sophisticated coastal French pixel-art town, low top-down view, transparent background, walnut muted teal cream brass palette, detailed lived-in props, each designed to occupy roughly two by two 48px gameplay tiles`

- sofa composition `28aa9b6b-0e2b-43ae-bdc6-c5a5bdbc764c`
- dining composition `af940a4c-2e48-4232-86a1-ece3cd786634`
- market display `09d996cf-2c78-442a-94d5-93a492833155`
- library wall `418b17cc-70af-4efc-acf1-db6432935f30`

### Cliff-town and street-wall kit

Source review: `f4b957d2-a0c7-4e05-b8fd-e66e9817763a`

Prompt: `cohesive architectural set for a refined French Atlantic beach town, low top-down pixel art, transparent background, warm natural summer light, weathered pale stone and slate, dense attached street wall massing, detailed windows balconies shutters gutters and climbing plants, no text no people`

- attached street wall `417e1f22-b954-496c-9c36-f910196c03be`
- corner apartment block `94d74a12-a743-49dc-89db-c96a6401bd60`
- cliff villas `e8cfe07f-1620-456b-87e8-8a18d82cbb92`
- stepped cliff row `8803e0d2-c0f5-4602-976e-0031a64405d4`

## Evidence

- [Town composition](media/231_mountain_town.png)
- [Attached street wall](media/231_paris_streetwall.png)
- [Cliff villas](media/231_cliff_villas.png)
- [Beach cliff row](media/231_beach_cliff_row.png)
- [Hotel lobby furniture](media/231_hotel_large_furniture.png)
- [Hotel guest rooms](media/231_hotel_rooms_2f.png)
- [Library wall furniture](media/231_library_large_furniture.png)
- [Shop display island](media/231_shop_large_furniture.png)

## Verification and impact

- `lint_data.py`: pass.
- `audit_map.py`: pass; the new cliff-villa footprint removes 15 walkable cells while preserving full reachability.
- Godot import and parse: pass. The pre-existing missing NobodyWho GDExtension warning remains non-blocking.
- `space_test`: 0 failures; the added hotel stair validates through the canonical portal graph.
- `player_touch_test`: pass.
- `banking_test`: pass.
- N=12, seeds 1–12, 60 days: all 47 invariants green, golden digests and tick chains 12/12 unchanged.
- Scenario determinism: 16/16 hard, repeat, data-fingerprint, and golden comparisons pass.
- N=16 targeted seeds 1–4: hard invariants 4/4 and repeat 1/1; seed 3 retains the known soft seafood supply miss (#40). The four-seed civic-duty quorum is 1/4 and therefore below the small-grid 2/4 threshold; the full 12-seed N=16 run immediately before the final visual-only additions passed at 7/12, and the four current digests are byte-identical to that run.

## Whole-slice progress

- P4 civic/governance presentation: implemented and regression-covered.
- P5 cooperative bank and receipts: implemented and regression-covered.
- Adaptive interiors: large Halles exploration, semantic furniture art overrides, denser hotel/library/shop composition, and a first multi-room public second floor are implemented.
- Town composition: single land entrance, natural boundary frame, larger beach/plaza, tighter street walls, façade diversity, and visible cliff housing are implemented.

## Coherent next candidates

1. **Traversable upper town:** model cliff stairs/ramps as explicit portals or a height-aware outdoor graph, then place two or three true upper streets. This is the correct next step if elevation should affect play rather than only composition.
2. **Room-plan vocabulary:** add authored doorway/arch slots and room-purpose tags, then extend the hotel pattern to homes with kitchens, bedrooms, bathrooms, and private upper floors.
3. **Street-block consolidation:** regenerate a few more 4–6 frontage attached blocks and intentionally re-author lot footprints around the plaza and north avenue, with a route heat-map check after every moved footprint.
4. **Beach civic life:** enlarge the promenade/beach program with bath cabins, café terraces, steps, and overlook interactions before adding vehicles or more roads.
