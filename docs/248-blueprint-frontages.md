# Blueprint implementation: facing and frontage alignment

The 247 blueprint is the layout anchor. The renderer now consumes each building's explicit facing, aligns its visible bounds to the appropriate street edge, and selects front versus rear terrace elevations. North-facing narrow lots no longer fall back to a south-facing courtyard sprite. Decorative workshops use a south-front asset while the functional north-entry workshop uses its rear elevation.

Long terrace lots render continuously instead of repeating detached, diagonally oriented blocks. Narrow plots select one to four actual facade bays. Architectural mirroring is removed, including the east-facing coastal pavilion; mirroring a sprite reverses its light and signs and does not produce a physical turn.

Two aligned PixelLab terrace images replace inconsistent diagonal street walls. Their source PNGs contain transparent plaster areas; explicit opaque wall planes are rendered underneath the original window, balcony and roof detail. The exterior background stays transparent. Library, baths and grocery use dedicated orthographic views to preserve curved silhouettes. Remaining pitched-roof assets use calibrated frontage projection, preserving vertical walls and uniform scale within their visible alpha bounds.

The navigation footprint, entrances, garden belts and interior plans are retained. The facing audit checks the seven functional entrances against facade direction. Render tests verify street-edge placement, continuous lot coverage, front/rear asset selection, upright walls and visible bounds. Captures include opposite sides of the garden boulevard.

| New source | PixelLab job | Size |
| --- | --- | --- |
| row_front_aligned.png | c1688cd8-3171-4ed5-8982-2551e3162f42 | 688 × 384 |
| row_rear_aligned.png | 8b05a46f-9f0b-4729-aef3-7c76f61359df | 688 × 384 |
| library_aligned.png | 6c780919-773c-4afc-af1b-4f4830606f38 | 512 × 384 |
| bathhouse_aligned.png | 1b49c7b9-cdc6-4d7b-8c44-e42d8a7e9e75 | 512 × 384 |
| shop_aligned.png | 7190c1fc-078e-488e-aed6-d7a3ace0ce67 | 512 × 384 |

Validation: map, coastal-plan, neighborhood and data-lint audits pass; regeneration is idempotent. The rendered exterior regression reports zero failures for 45 facade instances and seven functional buildings; the character-camera regression reports zero failures. Existing local optional NobodyWho extension warnings remain. This revision changes presentation and facing metadata, not navigation geometry or simulation rules.

Evidence: [town overview](../analysis/248/town.png), [opposite street frontages](../analysis/248/south_frontages.png), [upper-town rows](../analysis/248/north_frontages.png), [market quarter](../analysis/248/market.png).
