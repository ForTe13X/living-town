# Native town streaming pilot

The native port moves outdoor asset loading and component construction out of the legacy eager town startup. It uses cooked, typed root/render-unit data assets, soft mesh references and world-owned asynchronous requests. The portable source assets and simulation kernel remain separate from this presentation layer.

This is an opt-in pilot. The driver defaults to disabled, all new qualification fields default to false, and the default map/GameMode is unchanged. It requires the existing qualified native café before starting. It creates no population, duplicate café or fixture behavior. Authoring the data assets, qualifying collision/materials and testing a real streamed world remain required before activation.

## Runtime behavior

- Root, unit and mesh loads retain their streamable handles. Dependency closure and support reference counts keep shared units alive until their last consumer leaves.
- World ownership, weak callbacks, request tokens and an epoch reject stale completions after cancellation, restart or teardown.
- The pilot permits at most two concurrent incoming units. Registration, collision changes, visibility changes and destruction share a budget of four component operations per tick, serviced across units. Static meshes and ISM groups have no per-object tick. Loading radii use hysteresis.
- Arrival and retirement advance incrementally. Departing geometry stays while the demanded cohort is incomplete or the active driver has no focus. Reacquisition restores surviving component slots without duplicates. Explicit stop cancels requests and drains even without a focus; driver loss also drains. Geometry belongs to a separate world actor so destroying the driver cannot bypass this budget.
- Full native mesh identity is checked when an immutable loaded asset is first installed. The cache also checks lighting/collision GUIDs and material paths, slots and blend modes. It is invalidated on release. It does not promise to detect arbitrary in-place editor mutations without identity changes.
- Original float64 placement matrices are retained alongside qualified native transforms. Shear, reflection, invalid matrices, unsupported ownership and reserved café source IDs refuse.
- An incoming failure stops new work and retains already resident units until explicit stop/teardown. It does not silently substitute missing geometry.

The operation budget counts lifecycle policies rather than every internal engine call. It does not bound milliseconds, shader compilation, mesh hashing, a large registration or teleport landing safety. World/subsystem teardown remains a synchronous cleanup exception. Actual town frame timings and loading observations are still needed.

## Editor readback

The editor-only `LivingTownTownSliceReadbackLibrary` exports closed LOD0 buffers for the fixed exterior pilot namespace into a fresh owned output directory. It records position, normal, tangent, UV, color, index and section data; material slots/modes; precision/build settings; collision identity; and source-package hashes. It neither modifies assets nor places actors. The editor module depends on the runtime module; the game target does not depend on this editor helper.

Unreal's installed Python wrapper returns `None` for a C++ false result when output parameters exist. A successful `ExportTownSliceMeshes` returns `(receipt_json, error)` with its Boolean stripped. A failed Python call cannot expose the native Error output through this signature. Consumers must save raw return diagnostics before parsing and must not assume a three-item tuple.

The new tile-authoring and Westwood-material helpers instead return JSON strings with explicit status/error/readback fields. Tile authoring is restricted to the frozen pilot plan and fresh staging paths. Its preview entries are editor-only, non-ticking and non-colliding; the driver and qualification flags remain disabled. They require an editor view with Game View off and do not establish a playable world. The material helper inspects constant-input semantics and can clear only four named overrides on the marked new Westwood derivative. Compilation establishes neither its shader output nor visual quality.

## Evidence and remaining work

The outdoor/material/lifecycle implementation was verified in the 56-input source cut SHA-256 `f5b0b23d11c630b328631196e5e424d72f0a2bd9ad775c13b639370618f810ba`. It compiled successfully with UE 5.8.4/58902052, MSVC 14.44.35229 and SDK 22621 in 114.875 seconds. All 60 bootstrap/source/receipt checks passed against that build.

Nine native automation tests passed in a separate hardware run: the four existing café authority tests, tile matrix/demand/metadata/unit boundaries and `LivingTown.Native.TileLifecycleBudgetWorld`. The new test observes real transient world/components with a one-operation budget through arrival, cohort hold, partial retirement, reacquisition, cancellation, driver loss and cleanup. It uses synthetic primitives, so it does not qualify imported production assets or frame times. Eleven native SHA known-answer cases also passed; the run had zero errors, warnings or skipped tests.

An actual assets-only hardware D3D12/SM6 run imported and saved all 1,488 outdoor definitions and exported their native buffers in 240.704 seconds. It used the Radeon 8060S, peaked at 11,196,723,200 bytes aggregate RSS, preserved bound source/config/private data and reaped its owned process tree. This measures editor authoring, not game startup or sustained FPS.

The initial saved-buffer comparison failed because its validator incorrectly applied the importer's mirrored-transform winding branch to identity definitions. That failure is retained. The corrected offline comparison matches positive-area geometry, float32 UVs and material assignment on all 1,488 definitions, with zero missing positive faces and zero extra faces. All definitions meet the declared normal/color storage-format checks. The engine omits 5,726 exact source zero-area faces across 116 definitions; full-source geometry equality remains false for those definitions.

Of the 1,488 definitions, 1,486 pass the complete narrow array-format checks. The two original named Mikk derivatives have real zero tangents affecting four positive-area triangles each, despite their recompute flags and preserved finite normals. Those old assets remain refused. This comparison did not reimport or change any source/native assets.

A separate numerical investigation traced the zero weights to rounded dot products on very thin triangles. Two fresh `TangentBasis_MikkStableAngle_f64_v001` derivatives use an explicitly altered Mikk angle calculation and provide their reviewed tangent basis to the importer. This is a new basis lineage: original tangent/sign preservation is not claimed. Their actual assets-only Unreal import took 43.265 seconds on Radeon hardware, created exactly two mesh packages and preserved all 1,736 prior packages. After the editor was reaped, an independent saved-buffer comparison passed all 24 sliver and 2,200 grass triangles, including source geometry/UV/material assignment, normal format and provided derivative tangent/sign fidelity. Both have zero tangent failures; actual full-UV/high-basis precision and CPU access were read back.

The two-buffer comparison SHA-256 is `8070434d9d512b75368a4086d37f8eb9486a7b46e62b423e641fe9398d0fbe3d`. It does not establish the grass source alpha cutoff, normal-map graph/green-channel behavior or rendered shading on 55 flagged grass corners. The typed root has not been remapped to these candidates. Material sampling, collision, rendered views, actual streaming cancellation/teardown and gameplay/performance qualification are pending. No whole-town or final-art acceptance follows from the build, tests or imports.

The seven-cell source slice retains whole-owner closure, exact shared-instance provenance and the external café exclusion. Its current authoring derivation has 116 render units, 1,638 component entries and 587 unique repeated placements using 52 prototype meshes. This offline derivation is not a created or qualified runtime world.

## Current viewport and saved-material review

![Seven-cell editor diagnostic at manual EV12](evidence/native_town_mid_ev12_v001.png)

The current 58-input source cut, SHA-256 `716d7364e8fdcb3ee7872d93ae49003a1185a2c7db3fab8382aebacfc4767e2e`, adds an editor-only exact-current-viewport helper and its `UnrealEd` dependency. The other 55 inputs remain byte-identical to the earlier cut. Its actual build completed in 120.906 seconds, exited with code zero and reaped its owned processes.

The [editor helper](../../unreal/Source/LivingTownMaterialInspection/LivingTownViewportInspection.h) reads the same `GCurrentLevelEditingViewportClient` used by installed MCP `CaptureViewport`. A scoped fixed Mid review sets perspective, Lit mode, scene-driven exposure, lighting flags and a temporary realtime override, then restores both camera transforms, view modes, flags, exposure, widget and realtime state. It refuses an unrelated world, PIE, actor lock or an existing incompatible override. Direct client facts do not observe later render-family adjustments. Background editors can append a later throttle override; the local offscreen review launcher temporarily disabled that setting in its owned editor's CDO memory and restored it without saving configuration.

A fresh hardware run reopened all 1,854 saved package files and captured Unlit plus manual EV12/13/14 frames. Native client facts matched before and after each Lit capture; viewport restoration and the temporary owned-editor background-throttle restoration passed. The run took 186.312 seconds, peaked at 13,125,591,040 aggregate private bytes under a 16 GiB authoring limit, preserved sources and reaped all owned processes. This measures editor review, not game loading or FPS.

The image remains held for presentation work. The camera looks below the horizon across the edge of the seven-cell terrain slice, so surrounding landscape coverage needs review. The original foreground plaster appeared teal; those exact wall meshes have no source or native vertex-color buffer. The image does not establish complete-town or final-art acceptance.

| Original native material bindings | Source atlas bound to two derived materials |
| --- | --- |
| ![Original teal plaster](evidence/native_wall_original_ev12_v001.png) | ![Correct atlas binding](evidence/native_wall_bound_atlas_ev12_v001.png) |

The later matched EV12 comparison isolates a real import defect. Both plaster materials referenced the engine default texture for BaseColor. Their shared source albedo is a valid 1536 x 1536 PNG; the original glTF Interchange import rejected its non-power-of-two dimensions and omitted all four texture aliases. A fresh, explicitly configured legacy TextureFactory import retained the exact source image bytes and dimensions. Two cloned materials change only that texture binding. Both frames were captured after the full scene, original materials and clones were warmed; camera, exposure and source-sized texture readiness were checked for both. The corrected bindings remove the teal streaking. Plaster still reads cool gray at this distance, so color, normal strength and close-range surface quality remain art work.

The review completed both captures and restored all 61 component override arrays, the native viewport scope and the owned background-throttle setting. Original packages were preserved and owned processes were reaped. It took 224.719 seconds and peaked at 13,404,962,816 aggregate private bytes. The log contains one handled engine ensure: a redundant public realtime-enable call attempted to remove a subsystem override that was absent. The editor continued through capture and restoration; this is completed evidence with a warning, not a clean stability qualification. The legacy TextureFactory setting does not fix the separate Interchange pipeline policy. A durable one-shot importer must explicitly allow valid non-power-of-two source images and refuse missing referenced texture bindings.

Separately, the unassigned Westwood material and seven new textures were saved, reopened in a fresh editor and checked independently. The split color/roughness/metallic and normal Custom nodes compile without the earlier `PixelNormalWS` dependency error. Six original expressions, 13 new role nodes, all 12 used textures, full image dimensions and sampler/color-space settings match the declared graph. The six photo maps are 2048 square; the region mask is 512 × 1024. Original packages remain unchanged.

| Macro material, near view | Westwood detail layer, same near view |
| --- | --- |
| ![Macro terrain](evidence/westwood_macro_near_v001.png) | ![Leaf-litter detail](evidence/westwood_detail_near_v001.png) |

Six actual static frames compare Macro/Westwood at 4/15/40 m and 1.7 m eye height, with matched manual EV12. The detail layer resolves nearby leaf litter more clearly; repeated patterns remain visible at middle/far distances. This is a provisional detail selection. Soil close-ups, transitions, additional lighting directions, vegetated reserve context and projected-texture streaming still need review.

The exact terrain test mesh has 82,423 positive source faces. Independent native-buffer comparison matches every face, UV and material assignment, with zero normal/tangent failures. Unreal intentionally omits its redundant all-white color buffer; the declared equivalence uses the installed vertex factory's opaque-white default and does not claim physical color-buffer preservation. Nonwhite or translucent color loss still refuses. A redundant per-triangle full-color conversion was moved outside the loop; the bounded comparison now completes in 9.875 seconds instead of exceeding 60 seconds. No comparison tolerance was changed.
