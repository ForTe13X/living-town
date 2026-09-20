# Slice 239 — South-beach civic-life district

## Outcome

The southern coast now reads as a compact fifth district rather than leftover sand beside the Harbor Works edge.

- `Beach Civic Life` is an explicit 13×9 urban-design district at the south-east corner.
- `Promenade de la Plage` extends the southern avenue to the sea as a narrow granite-sett promenade, not another vehicle road.
- A café pavilion and public changing cabins make a continuous civic frontage at the promenade bend.
- A flowered social pergola and a dense deckchair/parasol rental composition form a second, more open band beside the beach.
- The four pieces are deliberately grouped as one destination. They share cream timber, muted navy/coral canvas, granite bases, and summer planting, while remaining distinct in silhouette and utility.
- Harbor Works now stops at the promenade edge, so the industrial quarter and beach quarter no longer claim the same southern band.

This is the spatial and visual beach-civic slice. The already-proven bathing and boat interactions remain at `north_pier`; they were not moved to the distant south coast merely to make the new scenery look active. A later gameplay slice can connect a south-beach activity only when its travel horizon and attendance survive the existing economy and starvation gates.

## PixelLab asset-factory receipt

Mode: `create_1_direction_object`, top-down, 128 px, four-frame review pack. All four reviewed frames were promoted and used directly as reusable compositions.

Common prompt:

> cohesive civic-life architecture and furniture for a warm French Atlantic seaside promenade, low top-down pixel art game sprites, transparent background, pale weathered timber and stucco, striped canvas, muted navy cream coral, granite bases, rich believable summer detail, natural light, no people, no vehicles, no text

| Saved asset | PixelLab object | Placement and role |
|---|---|---|
| `game/assets/art/houses/beach_cafe_pavilion.png` | `ca888715-1558-4eff-82a7-c4dd1f6f3e7b` | `[52,41]`, 4×3; café frontage and terrace tables |
| `game/assets/art/houses/beach_changing_cabins.png` | `e45a70b0-b5de-485b-af65-e45ef113645f` | `[56,41]`, 3×3; public changing and foot-wash cluster |
| `game/assets/art/houses/beach_social_pergola.png` | `890d2622-3168-4703-b10e-63ac2f979688` | `[52,45]`, 3×2; shaded communal seating and flowers |
| `game/assets/art/houses/beach_deckchair_cluster.png` | `a06ad0d9-5afe-4dfb-8f27-a6cc4a2c052d` | `[56,45]`, 3×2; parasols, loungers, rental counter, and beach clutter |

Review pack: `9f5a6a8d-6426-4fdd-9714-3b30c049f5e8`.

## Evidence

- [Whole-town district silhouette](media/239_beach_civic_whole.png)
- [South-beach promenade and four-part civic cluster](media/239_beach_civic_close.png)

## Navigation and simulation impact

- Visual lots and simulation `solid_lots` remain in exact 50/50 parity.
- The four new compositions occupy 31 newly blocked cells after the two authored doors are excluded; walkable cells move from 2,011 to 1,980. Typed terrain blockers remain 582.
- `lint_data.py` and `audit_map.py` pass. Every resident, worksite, object approach, functional door, and map area remains in the main connected component.
- `space_test` passes with zero failures.
- N=12, seeds 1–12, 60 days: hard invariants 12/12, every soft invariant 12/12, all 21 gated event classes live, goldens 12/12, and repeat determinism 3/3.
- The accepted run is behaviorally byte-identical to Slice 238: production 1,977, shortages 438, invitations 750, aid coverage 9/12, and civic-duty coverage 8/12. The new south-beach route did not perturb the simulated economy because no authoritative activity was moved there.
- DetGate passes 16/16 across default, faction, betrayal, and free-rider tracks. The data fingerprint is `2804598460`.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Ordered-slice progress

1. **Occupied-home specialization:** delivered as Coco's two-floor seaside-home prototype in Slice 238. Active resident relocation remains correctly held behind a general household-logistics fix.
2. **Beach civic-life district:** delivered here as a coherent promenade frontage and leisure cluster, with gameplay authority intentionally unchanged.
3. **Courtyard access language:** next — a small number of readable arches, gates, and shared passages through the new perimeter blocks.
4. **Street-corner activity props:** after courtyard access — reusable PixelLab market, café, delivery, bicycle, cart, and flower-display kits at meaningful junctions.

## Coherent follow-on candidates

- Give one southern beach venue a real, bounded social contract only after measuring attendance and return-home travel; do not duplicate the north-pier actions blindly.
- Use the courtyard slice to create two or three shortcuts between long street walls, improving both legibility and route resilience.
- Place street-corner prop kits where main streets change direction or meet the plaza, rather than evenly decorating every road.
