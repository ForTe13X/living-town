# Neighborhood massing, planting and room plans

The [visual anchor](../analysis/247/neighborhood-blueprint.png) shows the plan without textures: street-facing arrows, four joined terraces, civic silhouettes, planting belts, three room-plan studies and a varied street elevation. It is a schematic design reference, not a screenshot.

The implementation replaces the repeated courtyard override with type-specific architecture: domed limestone library, turquoise-domed baths, brick sawtooth workshop, market cafe, grocery shop, courtyard home and attached residential fronts. Existing specialist hotel, chapel, bakery and infill sprites retain their distinct appearances. North-facing terraces use rear elevations from the PixelLab typology atlas; long lots repeat attached modules instead of shrinking a single building into the center of the plot.

The circulation plan now includes 122 trees with regular verge planting, low hedges, hydrangeas, lavender, roses, ornamental grasses and perennial flowerbeds. Candidate tree placements are rejected when they disconnect the walkable town. All 914 paved cells remain connected, including 15 functional entrances and two arcades.

Seven interior floors receive purpose-specific zoning and revised partitions. Cafe, library, baths and workshop have actual recesses represented both in rendering and the simulation collision grid. Furniture and portals are audited against these recesses. The grocery stock corner was opened to reconnect a previously isolated aisle.

Regenerate with `python tools/rebuild_neighborhoods.py`, then `python tools/draw_neighborhood_blueprint.py`. Regeneration was checked for identical output on a second run. `audit_neighborhoods.py` independently checks seven interior floors, furniture interactions, entrances and terrace orientations. Map and coastal audits pass. The revised navigation passed the 60-day S0 simulation gate for seeds 1–3 and one repeat determinism check; no golden file was used or updated.

New PixelLab source jobs:

| File | Size | Job |
| --- | --- | --- |
| typologies.png | 688 × 384 | 59878521-a843-4872-b515-c474be2f8ef7 |
| terrace_south.png | 512 × 320 | 58d4a79b-a8ea-4e6d-9a24-630efbaea753 |
| library.png | 512 × 512 | e114a01b-4a5e-4099-9803-794100658398 |
| workshop_north.png | 512 × 384 | 9363e444-0443-48b9-aa09-db4e331af1f2 |
| bathhouse_north.png | 512 × 384 | 375e0e5b-2fa2-4d9b-b2ec-0e198711979e |
| flowerbeds.png | 512 × 512 | d77510f1-ff60-4b3f-bc00-1df160f54376 |
| shop.png | 512 × 512 | 760389e9-8e4b-4e60-a021-9f3271ff6261 |

The independent north-terrace generation bd5245bc-06c4-4af1-bb22-02bc6b2e0689 had damaged transparency and was rejected; the atlas rear elevation is used instead. Atlas regions are selected at runtime, preserving the original source images.

Final visual evidence: [town](../analysis/247/rendered/town.png), [cafe interior](../analysis/247/rendered/interior_cafe.png), [library interior](../analysis/247/rendered/interior_library.png), [bathhouse interior](../analysis/247/rendered/interior_wash.png). Exterior asset checks and runtime recess-collision checks pass; space, life and character-camera tests pass. Existing optional NobodyWho extension warnings remain in this local installation.
