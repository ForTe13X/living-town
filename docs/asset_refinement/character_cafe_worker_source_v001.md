# Breton cafe worker: source model review

The selected [front concept](concepts/cafe_worker_breton_v001/README.md) now has an archived Tripo Studio H3.1 source candidate. Its fabric, stitching, collar, pockets, waist knot and shoes are visible in actual Blender Cycles/HIP renders. The candidate is held for refinement before final rigging or runtime adoption.

![Actual GPU source review](concepts/cafe_worker_breton_v001/review_front.png)

## Source and measurements

The original Studio GLB is retained locally as `cafe_worker_breton_v001_studio_original.glb`, 73,311,132 bytes, SHA-256 `b9f1abeb198adf6536439a9383bb03eefc2fbd449db60796cec1dfe93d2cb875`. This commit contains the reference and review images; it does not include the large GLB or claim an engine-ready asset release. Studio asset identity is `801bf01e-5be6-45bf-87a1-1664f51512a1`. Generated-source provenance is recorded; no CC0 claim is made.

Read-only GLB inspection measured one mesh/material, 991,378 vertices and 1,928,055 triangles, with no exact degenerate or near-zero-area triangles under the inspector's stated calculation. The source has no skeleton or animation clips. These are source facts, not topology, deformation or art acceptance.

| Map | Actual encoded image | Size |
| --- | --- | --- |
| Basecolor | JPEG, RGB8 | 8192 × 8192 |
| Metallic/roughness | JPEG, RGB8; glTF G/B links | 4096 × 4096 |
| Tangent normal | PNG, RGB8 | 4096 × 4096 |

The three embedded image payloads were extracted without resizing, re-encoding or channel changes. Blender's packed-image hashes match the original payloads; basecolor reads as sRGB and normal/metallic-roughness as Non-Color. Imported vertex and triangle counts match the source. Original GLB and review Blend hashes remain unchanged through the later view renders.

The source height is approximately 0.97946 glTF units; physical stature is unqualified. An unapplied parent scale of 1.8275345069 gives a nominal 1.79 m review figure. That is an explicit staging choice, not a calibrated source measurement.

## Visual hold and next work

![Eye and hair inspection](concepts/cafe_worker_breton_v001/review_face.png)

- Correct the conspicuous white crescents beneath the lower lids and irregular eye-opening highlights. Determine the geometry, texture and shading contributions on the mesh before editing.
- Verify independent digits and anatomical joint/tip forms. The hand views show flattened, tightly stacked fingers; they do not prove welded topology.
- Refine the heavy parallel hair grooves and blunt pale spikes while retaining the broad hairstyle.
- Reconstruct the rear garment as a conventional front bib apron with waist ties and visible rear trousers. The generated rear currently reads as a closed skirt.
- Derive and compare runtime topology/LODs, freeze UVs and perform any required texture/normal rebakes before final rigging. Then verify distinct idle, walk, use, eating and sleeping actions with actual deformation and contact.

Six actual GPU images cover front, three-quarter, rear, face and both hands. The initial multi-view process completed the front image and failed with an out-of-memory error on the next render. Five fresh, single-view processes subsequently completed and reaped successfully, with sampled private memory below 5.09 GB each and a 6 GiB hard job limit. Each selected Radeon 8060S HIP with CPU ray-tracing disabled; this is authoring evidence, not game performance or a system-stability guarantee. The failed attempt remains recorded.

No new resident appearance, skeleton, clips, engine binding or qualification flags have been promoted. Continue through the [staged asset pipeline](staged_asset_pipeline.md).
