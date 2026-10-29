# Unreal and Blender responsibilities

Choose the implementation that improves the playable town and its art. Existing code and assets may be replaced; interoperability comes from preserving documented source data, units, material inputs and asset identities.

| Work | Preferred implementation | Required evidence |
| --- | --- | --- |
| Reserve terrain | Unreal Landscape, component LOD, edit layers and collision; portable R16 as the source | Exact height readback, terrain contacts, visible surface quality and an actual walk |
| Repeated vegetation | Native ISM/HISM; a bounded Landscape Grass trial after biome qualification | Instance identity, actual mesh LODs, cull/fade behavior, canopy composition and measured moving-view cost |
| Ground surfaces and water | Unreal materials, native layer weights, lighting and water shading | Correct normal direction, ready component shader variants, texture residency, matched views and GPU cost |
| Buildings and interiors | Blender for room geometry, openings, furniture proportions, joinery, UVs and shading basis; Unreal for assembly, materials and physical clearance | Useful room layouts, legible detail, correct texture scale and capsule/camera clearance |
| Characters | Blender for silhouette, UVs, weights, rig and source clips; Unreal for animation, movement, camera and interactions | Protected source invariants, matched appearance review and actual possessed-character actions |
| Loading and lifetime | Unreal's existing native asynchronous ownership and placement paths, qualified in the chosen playable scene | Correct package closure, cancellation/unload behavior and time to first playable frame |
| Gameplay and HUD | Native runtime presentation and the portable simulation kernel | Player-visible consequences, persistence and completed journeys |

Python remains an asset-authoring and Editor orchestration tool. A broad runtime rewrite needs a measured bottleneck or a concrete correctness improvement.

## Current evidence and limits

The repository's [native Landscape importer](../unreal_native_reserve_landscape.md) and portable height fixture are adopted. Later pond, biome and HISM scene trials remain separate asset families until explicitly integrated. Their same-path maps and texture aliases must not be combined by concatenating manifests or overwriting assets.

The separate HISM500 FullHD trial observed 729 placed instances and 5,000 retained frames at 1920 × 1080. Frame median/p95 was 13.727/18.359 ms; Render thread 13.717/18.335 ms, GPU 11.197/14.545 ms and Game thread 2.605/3.077 ms. This is one static, uncooked reserve view, with the older ground material. It supports investigating rendering, materials and visibility before a broad gameplay rewrite. It does not establish moving-town performance, displayed frame rate, packaged startup or the cost of the new biome material.

Landscape's material instances can initially have deferred shader compilation. The authoring pipeline must explicitly submit the actual instances once before requiring complete shader maps. Readiness must follow the actual material's shader completeness and compile errors: whole-map compilation lifecycle flags can remain false in per-shader job-cache mode even when the material is complete. Retain those flags as diagnostics. The readback validator stays read-only. An unavailable representative instruction count is not zero shader cost.

## Next physical integration

Connect the café/Courtyard approach to the reserve with the selected stair route and supporting terrain or retaining structures. The sources leave at least 66.407 m of missing horizontal support; the chosen endpoints rise about 26.335 m. The final flight also intersects the existing reserve slope. New support geometry and a bounded, recorded terrain derivative are required before claiming a traversable route.

Use authored stone stair, landing and rail modules with native collision and CharacterMovement. Preserve the pawn and camera dimensions. Verify the complete outward and return journey, including café egress, continuous floor support, landings and terrain transitions. Keep the currently incompatible streaming configuration disabled until its ownership and scene requirements are resolved. A successful mesh export or proposed stair dimension does not establish walkability.

Review the route and moving-view performance before replacing the narrated walkthrough and README showcase.
