# Native town streaming pilot

The native port moves outdoor asset loading and component construction out of the legacy eager town startup. It uses cooked, typed root/render-unit data assets, soft mesh references and world-owned asynchronous requests. The portable source assets and simulation kernel remain separate from this presentation layer.

This is an opt-in pilot. The driver defaults to disabled, all new qualification fields default to false, and the default map/GameMode is unchanged. It requires the existing qualified native café before starting. It creates no population, duplicate café or fixture behavior. Authoring the data assets, qualifying collision/materials and testing a real streamed world remain required before activation.

## Runtime behavior

- Root, unit and mesh loads retain their streamable handles. Dependency closure and support reference counts keep shared units alive until their last consumer leaves.
- World ownership, weak callbacks, request tokens and an epoch reject stale completions after cancellation, restart or teardown.
- The pilot permits at most two concurrent incoming units and four component creations per frame. Static meshes and ISM groups have no per-object tick. Loading radii use hysteresis.
- Full native mesh identity is checked when an immutable loaded asset is first installed. The cache also checks lighting/collision GUIDs and material paths, slots and blend modes. It is invalidated on release. It does not promise to detect arbitrary in-place editor mutations without identity changes.
- Original float64 placement matrices are retained alongside qualified native transforms. Shear, reflection, invalid matrices, unsupported ownership and reserved café source IDs refuse.
- An incoming failure stops new work and retains already resident units until explicit stop/teardown. It does not silently substitute missing geometry.

Creation counts alone do not bound shader compilation, a large mesh hash, physics registration, final visibility changes or a burst of component destruction. Actual frame timings and loading observations are still needed.

## Editor readback

The editor-only `LivingTownTownSliceReadbackLibrary` exports closed LOD0 buffers for the fixed exterior pilot namespace into a fresh owned output directory. It records position, normal, tangent, UV, color, index and section data; material slots/modes; precision/build settings; collision identity; and source-package hashes. It neither modifies assets nor places actors. The editor module depends on the runtime module; the game target does not depend on this editor helper.

Unreal's installed Python wrapper returns `None` for a C++ false result when output parameters exist. A successful `ExportTownSliceMeshes` returns `(receipt_json, error)` with its Boolean stripped. A failed Python call cannot expose the native Error output through this signature. Consumers must save raw return diagnostics before parsing and must not assume a three-item tuple.

## Evidence and remaining work

The adopted 51-input native source cut has SHA-256 `9c2ab0d7824b17b2517f2c8ea5d99f388ec3722f633072ea620beccfda60a83d`. It compiled successfully with UE 5.8.4/58902052, MSVC 14.44.35229 and SDK 22621. Eight native automation tests passed: the four existing café authority tests plus tile matrix, demand, metadata and unit boundaries. Eleven native SHA known-answer cases also passed. The canonical source exactly matches that compiled cut, and 60 bootstrap/source/receipt checks pass against its actual build receipt.

An actual assets-only hardware D3D12/SM6 run imported and saved all 1,488 outdoor definitions and exported their native buffers in 240.704 seconds. It used the Radeon 8060S, peaked at 11,196,723,200 bytes aggregate RSS, preserved bound source/config/private data and reaped its owned process tree. This measures editor authoring, not game startup or sustained FPS.

The initial saved-buffer comparison failed because its validator incorrectly applied the importer's mirrored-transform winding branch to identity definitions. That failure is retained. The corrected offline comparison matches positive-area geometry, float32 UVs and material assignment on all 1,488 definitions, with zero missing positive faces and zero extra faces. All definitions meet the declared normal/color storage-format checks. The engine omits 5,726 exact source zero-area faces across 116 definitions; full-source geometry equality remains false for those definitions.

Of the 1,488 definitions, 1,486 pass the complete narrow array-format checks. Both named Mikk derivatives have real zero tangents affecting four positive-area triangles each, despite their recompute flags and preserved finite normals. Both remain refused. This comparison did not reimport or change any source/native assets. Material sampling, collision, rendered views, actual streaming cancellation/teardown and gameplay/performance qualification are pending. No whole-town or final-art acceptance follows from the build, tests or import.

The seven-cell source slice retains whole-owner closure, exact shared-instance provenance and the external café exclusion. Its current authoring derivation has 116 render units, 1,638 component entries and 587 unique repeated placements using 52 prototype meshes. This offline derivation is not a created or qualified runtime world.
