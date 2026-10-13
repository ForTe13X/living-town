# Living Town reserve asset edition

This edition extends the authored coastal town with a wooded reserve, graded visitor routes, a serviced trailer court and furnished visitor amenities. It also replaces loose furniture placement with deliberate activity groups and clear working fronts inside the town buildings.

**Native, portable-asset, consumer and actual-image gates: PASS.** These results bind the current reserve bytes; earlier urban-edition gameplay results describe a separate stage. The release target is `town-reserve-2026-10-12`. External package receipts supply final ZIP/member acceptance.

Release files: [curated ZIP](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/LivingTown_Reserve_Delivery.zip), [ZIP SHA256 sidecar](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/LivingTown_Reserve_Delivery.zip.sha256), [packager receipt](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/reserve_package_report.json) and [independent ZIP verification](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/final_zip_verification.json). The ZIP's own hash remains outside its payload.

| Delivery gate | Current result |
| --- | --- |
| Frozen native/source identity | PASS: V6 freeze binds 20 current files and native SHA below |
| Saved-native geometry | PASS: 30 core and 23 reserve checks, including actual stair land/head clearance, triangle quality, same-route coplanar overlap and local facade-cover ownership |
| Portable assets | PASS: 72 GLBs; optimized town 4,976,516 expanded triangles / 321,050,860 bytes; 25 independent checks |
| Isolated Godot consumer | PASS: 57 logical and 66 renderer checks; four actual captures; clean stderr |
| Actual image review | PASS: all 15 native stills and four consumer captures, bound by the combined 19-image receipt |
| Curated ZIP | External `reserve_package_report.json` and `final_zip_verification.json` supply final ZIP/member acceptance |

The accepted native SHA256 is `99fca62005524b1c2a331cbe81316b43b8d9622d92a408db6703fe3cf4760191`. Both the independently reopened [core audit](../art/living_town/evidence/native_scene_audit.json) and [reserve audit](../art/living_town/evidence/reserve_native_audit.json) pass against these saved bytes: 30 and 23 checks respectively, with 19,663 scene objects. The [V6 freeze](../art/living_town/evidence/final_source_freeze.json), SHA256 `4aec7be876f094c648a189efb615d8b857e32dd1fec7a54e60d49612e2744df3`, binds 20 current files. The optimized export, independent GLB verification, isolated consumer and all 19 actual images pass against this source. Archive identity is recorded by the external receipts above.

The existing playable game remains on its previous urban 3D asset stage. This reserve edition is a new Blender/GLB asset delivery with a separate Godot consumer. It does not add reserve navigation, residents, actions, collision authority or save migration to the main game. Existing character and simulation behavior is outside this asset revision.

## Native source and planning

Open [living_town_complete.blend](../art/living_town/living_town_complete.blend), scene `Living_Town_Summer`. The reserve uses the existing native filename; use checksums rather than the filename to distinguish revisions. The separate [building study](../art/living_town/living_town_building_study.blend) remains available, but its earlier images are not evidence for the enlarged reserve scene.

The sources are [reserve_plan.json](../art/living_town/reserve_plan.json), [reserve_plan.py](../art/living_town/tools/reserve_plan.py), [reserve_environment.py](../art/living_town/tools/reserve_environment.py), [reserve_amenities.py](../art/living_town/tools/reserve_amenities.py) and the town [interior kit](../art/living_town/tools/interior_design.py). The canonical [interior_plan.json](../art/living_town/interior_plan.json) records the current room/fixture inventory. Counts in older delivery guides can describe an earlier source revision.

The reserve plan controls building centers, yaw, pads, finished-route profiles, bridges and stairs. Amenity plans add exact local room bounds, partition openings, furniture footprints and approach points. The terrain generator preserves the town's elevation authority in its defined core rectangle, then grades the outer hills, terraces and route shoulders. Coast, quay and pond contact must be verified against their actual saved surfaces; an analytic height is not a substitute for a missing mesh intersection.

## Furniture as usable compositions

The interior planner starts with room purpose and essential fixtures, then arranges related activities together: a table with its seating, a bed with usable side access, a desk with its working front, or a kitchen with the sink, hob and fridge in one coherent run. Cardinal furniture follows the room walls; supported pieces put their actual backs toward the wall. The composition search reserves real door approaches, stairs, circulation and working fronts before accepting a pose.

Semantic IDs and game-bound fixtures are retained. Any omitted optional furnishing is listed in the room's `omitted_optional_assets`, with a reason; an optional omission must not silently replace a required program fixture. The dimensional audit checks groups, facing, density and clearances. The native audit separately compares saved furniture vertices with their source recipe at the intended pose, so stored facing metadata alone cannot make backwards geometry pass.

The three reserve staff-desk assemblies keep their original IDs and composite footprints. Their desktops now occupy the rear 0.60 m of each assembly, leaving the front chair and its back clear of the desktop. This is a bounded furniture-recipe repair; the unit layouts and room divisions are unchanged.

The reserve uses the same principle at a smaller scale. Its audited inventory is **21 units, 92 room/circulation zones and 158 interior furnishing assemblies**, plus 12 outdoor picnic assemblies. The 12 trailers have eight combinations of family layout and reflection: double-bed/booth, twin-bed/booth, family bunks and a double-bed/lounge arrangement. Each includes sleeping, galley circulation, dining/lounge, private bathroom and storage, with supported external entry steps, picnic deck, water and power connections. These are furnishing assemblies, not a count of unique furniture designs.

The nine visitor/service units are reception, convenience store, souvenir store, bathhouse, separate public toilets, food truck, laundry, maintenance and refuse service. The two shops have distinct browsing displays and separate staff/stock areas. The food truck has a staff entrance clear of its serving hatch, food preparation, cold storage, sandwich/hotdog displays and an awning. Bathhouse and toilet plans separate changing, wash areas and private compartments. Door apertures are actual mesh holes; parked hinged or folded leaves remain outside their clear crossings. Authored dimensions and a larger compartment do not establish accessibility or building-code compliance.

## Woodland, routes and crossings

The woodland plan mixes sessile oak, beech, silver birch, Scots pine, maritime pine, rowan, holly, willow and alder across defined zones. Trees use shared mesh datablocks with individual positions, rotations and scales. More detailed near meshes are selected around the authored town/camp area and within 22 m of any authored route, while simpler far meshes serve the outer woodland. These are static authoring choices, not a consumer-side distance LOD system. The actual consumer preserves 3,500 tree instances, comprising 9,928 mesh components sharing 46 runtime mesh resources; species and placement remain bound to the native report.

Exposed cliffs, shore rocks and boulders use an original [natural-granite PBR recipe](../art/living_town/tools/generate_reserve_materials.py) with a [4 m material manifest](../art/living_town/textures/natural_rock_material.json): mineral flecks, weathered veins, irregular fractures and restrained lichen. Built retaining walls and stairs retain the separate masonry material. Texture generation/seam checks do not establish acceptance of their final rendered application.

Planting exclusions preserve the town core, clearings, pads, path edges and crossings. Understorey, rock groups and trail furniture supply smaller landscape scales without filling every opening. Tree count alone does not prove canopy coverage or readable views.

The plan contains 47 connected reserve route records, including an approximately 2.10 km closed jogging belt. Its full planned length is 2,096.788 m; about 2,053.662 m uses new reserve ground ribbon and the remaining 43.126 m reuses urban paving. Its authored maximum grade is about 7.5%; scenic paths have their own limits. These are planned surface profiles, not a gameplay pathfinding or universal-accessibility claim. Ground grading continues beyond the visible trail edges before blending into the hill, so the coarse terrain grid can support the walkway and shoulders.

The saved trail ribbon uses shared cross-sections at effectively straight stations to avoid float32 overlap wedges. Its actual mesh audit includes all 15,879 eligible convex route faces: zero same-route coplanar overlap pairs above the unchanged 0.00001 m² limit, with a 0.0001 m plane tolerance. The saved land/trail triangle check reports zero reversed XY triangles and zero exactly degenerate world-space triangles; 18 vertical-projection slivers are retained as bounded diagnostics. These checks measure the native mesh, rather than accepting only the planning profiles.

The two ravine bridges have visible decks, end supports, rails and suspension/tie-back structures. Their authored endpoints, landing contact and terrain clearance require actual mesh checks. The two optional stone stair routes have discrete tread/landing geometry and handrails; they are separate from the stair-free running belt. A retaining edge expresses the change between graded terrace and lower terrain, with matching wall-face terrain profiles. These are authored visual structures, not structural-engineering certification.

The final continuous land surface is excavated around both stairs, and three endpoint approach links meet their landing heights. The current saved-mesh clearance gate passes 2,635 walking/land columns and 3,681 within-cell body rays, with zero failures; it also checks actual trail sheets within the 2 m head band. The [compact negative-control receipt](../art/living_town/evidence/reserve_stair_land_negative_control.json) records the same audit rejecting a distinct historical bad native with 1,950 failures. That historical rejection is separate from the final native PASS, and the faulty native/full diagnostics are excluded from the release.

## Portable hierarchy and local prefabs

Blender keeps reserve geometry under `06_Natural_Reserve` and `07_Reserve_Amenities`. Each amenity has its own structure, roof, front cover, interior/floor, room and site-utility collections. Hiding one unit's roof/front cover reveals its interior while neighboring units remain intact.

Facade sign boards and their attached exterior details belong to each unit's local front cover, so the cutaway hides them with the wall. Ground utilities remain visible separately. The saved-native ownership check covers all 21 units and 82 facade attachment meshes, with zero orphan attachments; the exterior world geometry is unchanged by this collection repair.

The exporter preserves these subtrees below `LivingTown/NaturalReserve`; the original 49 town buildings retain their separate `Buildings` subtree. Collection nodes use `<source_collection>__Group`. Reserve extras use `reserve_building_id`, `reserve_room_id`, `reserve_asset_id`, `reserve_floor_index` and `reserve_role`, so the new inventory does not inflate the existing core room/fixture counters.

The separate `art/living_town/game_assets_reserve/` package contains `living_town_game.glb`, `export_manifest.json`, the 49 original building prefabs in `buildings/`, 21 local-origin amenity prefabs in `reserve/`, and `cameras.glb`: 72 GLBs in the game-detail release. A high-detail whole-town `living_town.glb` may be exported separately if needed; it is not required for this edition. Each prefab record carries its world placement, yaw, checksum and local bounds. Shared forest meshes remain instanced in the complete scene. Materials use portable metallic/roughness PBR and embedded images; Blender text is converted to mesh. Coordinates are metres: Blender `(X,Y,Z)` becomes glTF/Godot `(X,Z,-Y)`.

The GLBs supply visual geometry and semantic groups. Collision, navigation, streaming and game interaction require explicit consumer work. The included `cameras.glb` is optional for consumers to load and retains saved native camera poses; temporary presentation-camera recipes belong to render evidence and do not alter that rig.

## Optional open-source authoring tools

Review date: 2026-10-12. [Sapling Tree Gen 0.3.7](https://extensions.blender.org/add-ons/sapling-tree-gen/versions/) offers parametric trees under GPLv3 or later; its declared compatibility is Blender 4.4 and newer. The official community listing describes [Archimesh](https://extensions.blender.org/team/community/) as generating rooms, doors, windows and other architectural objects. These are evaluated options: neither add-on was installed or used for this revision, and their behavior in Blender 5.2 was not tested. [Poly Haven assets are CC0](https://polyhaven.com/license); additional library assets were considered, while this edition retains the existing HDRI with its provenance record. Delivered woodland meshes and natural-rock PBR remain original deterministic generators.

## Reproduce with one heavy process at a time

Run these PowerShell commands from the repository root, with Python, Blender and Godot paths adjusted for the host. Keep logs and earlier evidence before rebuilding. A rebuild writes the canonical native file and manifests; archive a previous delivery first. Finish each command and its status gate before starting the next. Blender uses six CPU threads; the reserve Godot project uses six worker threads, single-threaded imports and a 30 FPS cap.

The curated kit rebuilds the delivered canonical plans. Original urban layout-drafting history is excluded. The reference-only [projection JSON](../game/data/town3d/projection.json) is included because furniture regeneration and the native audit preserve its 47 bound fixture IDs; its checksum must match that actual audit. It does not ship or start the game runtime.

```powershell
$townRoot = (Resolve-Path 'art/living_town').Path
$blenderExe = 'D:/Program Files/Blender/blender.exe'
$pythonExe = 'C:/Users/yp/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$godotExe = 'C:/path/to/Godot_console.exe'
$nativeFile = Join-Path $townRoot 'living_town_complete.blend'
$reserveAssets = Join-Path $townRoot 'game_assets_reserve'
```

To regenerate the deterministic planning files when intentionally revising the source:

```powershell
& $pythonExe "$townRoot/tools/interior_design.py"
if ($LASTEXITCODE -ne 0) { throw 'Interior plan generation failed' }
& $pythonExe "$townRoot/tools/reserve_plan.py"
if ($LASTEXITCODE -ne 0) { throw 'Reserve plan generation failed' }
```

Build a new disposable Blender session, then independently reopen the saved file for both native audits:

```powershell
& $blenderExe --background --threads 6 --python-exit-code 1 --python "$townRoot/tools/build_reserve.py"
if ($LASTEXITCODE -ne 0) { throw 'Reserve build failed' }

& $blenderExe --background --threads 6 $nativeFile --python-exit-code 1 --python "$townRoot/tools/audit_native_scene.py"
if ($LASTEXITCODE -ne 0) { throw 'Core native audit process failed' }
$coreAudit = Get-Content "$townRoot/evidence/native_scene_audit.json" -Raw | ConvertFrom-Json
if ($coreAudit.status -ne 'PASS') { throw 'Core native checks failed' }

& $blenderExe --background --threads 6 $nativeFile --python-exit-code 1 --python "$townRoot/tools/audit_reserve_scene.py"
if ($LASTEXITCODE -ne 0) { throw 'Reserve native audit process failed' }
$reserveAudit = Get-Content "$townRoot/evidence/reserve_native_audit.json" -Raw | ConvertFrom-Json
if ($reserveAudit.status -ne 'PASS') { throw 'Reserve native checks failed' }
$nativeSha = (Get-FileHash $nativeFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($coreAudit.source_blend_sha256 -ne $nativeSha -or $reserveAudit.source_blend_sha256 -ne $nativeSha) { throw 'Native audit source mismatch' }
& $pythonExe "$townRoot/tools/freeze_source.py"
if ($LASTEXITCODE -ne 0) { throw 'Current reserve source freeze failed' }
```

The local official Blender Lab MCP can execute the same builder in an inspected empty disposable scene with `LT_STAGE='town'` and `LT_INCLUDE_RESERVE=True`. The CLI recipe above is the complete packaged rebuild route; historical urban connection logs are excluded from the curated reserve delivery. Do not replace an unrelated open Blender session.

Render preview evidence, inspect the actual images, then render the final review set:

```powershell
& $blenderExe --background --threads 6 $nativeFile --python-exit-code 1 --python "$townRoot/tools/render_reserve.py" -- --preview
if ($LASTEXITCODE -ne 0) { throw 'Reserve previews failed' }
# Open the actual previews and resolve concrete blockers before the next command.
& $blenderExe --background --threads 6 $nativeFile --python-exit-code 1 --python "$townRoot/tools/render_reserve.py"
if ($LASTEXITCODE -ne 0) { throw 'Reserve final review renders failed' }
```

Export and independently verify the completed package in its separate reserve directory. The accepted ceiling is **5,000,000 expanded triangles** for the loaded game-detail town, including repeated tree instances. The actual optimized GLB contains **4,976,516 expanded triangles**, 4,176,300 unique-mesh triangles and **321,050,860 bytes**, with 49 materials and 31 embedded images. Independent engine-neutral verification passes 25 checks. This is a complete-scene geometry budget, not a measured frame-rate or streaming result. `--label final` is the verifier's evidence label; the release tag remains `town-reserve-2026-10-12`. The exporter fsyncs completed GLBs and the manifest before engine handoff.

```powershell
& $blenderExe --background --threads 6 $nativeFile --python-exit-code 1 --python "$townRoot/tools/export_game_assets.py" -- --out $reserveAssets --manifest "$townRoot/town_manifest.json" --detail game --prefabs all --camera-rig --triangle-budget 5000000 --label final
if ($LASTEXITCODE -ne 0) { throw 'Reserve export failed' }
& $pythonExe "$townRoot/tools/verify_reserve_exports.py" --root $townRoot --manifest "$reserveAssets/export_manifest.json" --report "$townRoot/evidence/reserve_export_verification.json"
if ($LASTEXITCODE -ne 0) { throw 'Independent reserve export checks failed' }

& $pythonExe "$townRoot/integration/reserve_godot/run_consumer.py" --godot $godotExe --assets $reserveAssets --native-manifest "$townRoot/town_manifest.json" --evidence "$townRoot/integration/reserve_godot/evidence" --capture
if ($LASTEXITCODE -ne 0) { throw 'Reserve Godot consumer failed' }
```

The consumer runs a real parser gate, a headless logical test and a separate GPU capture process serially. Runtime `GLTFDocument` reads the finished package in place. It checks source bindings, actual imported hierarchy/placements, room/furnishing IDs, floor heights, multi-frame local cutaways, shared tree resources/transforms, embedded PBR, bridge endpoints and representative trailer/store/bathhouse/food-truck prefab bounds. The current Godot 4.6.2 run passes 57 logical and 66 renderer checks with clean stderr. Explicit pre-generation source-index stamps map all 20,646 actual nodes and 19,353 unique mesh instances; maximum mesh world-transform component error is 0.000000298 (positions in metres and basis-vector deltas). All four PNGs were opened separately and accepted; a nonblank framebuffer check alone is not visual acceptance.

## Final image review targets

These current images are recorded in `evidence/reserve_renders.json`; all 15 final native stills were actually reviewed by the coordinator and accepted. They do not refer to the older urban presentation images. The four engine captures also pass actual review, with all 19 images bound by `evidence/reserve_visual_review.json`.

| Final image | What to inspect |
| --- | --- |
| [Reserve overview](../art/living_town/renders/reserve_v6/01_reserve_overview.png) | Woodland coverage, town-to-reserve transition, graded routes and visitor clearings |
| [Family trailer interior](../art/living_town/renders/reserve_v6/07_trailer_family_interior.png) | Sleeping, galley, booth, bathroom/storage groups and clear entry circulation |
| [Public bathhouse](../art/living_town/renders/reserve_v6/11_bathhouse_interior.png) | Changing/locker, wash and shower compartments, fixture facing and door approaches |
| [Ravine bridge](../art/living_town/renders/reserve_v6/14_ravine_bridge.png) | Deck continuity, supported landings, rails/suspension and actual terrain clearance |

## Curate and verify the release

The repository-level [packager](../tools/package_reserve_delivery.py) and [validator](../tools/verify_reserve_delivery.py) require the current V6 source freeze, both native audits, the compact stair negative-control receipt, independent reserve export verification, 15 final native images, four consumer captures and a separate `evidence/reserve_visual_review.json` covering all 19 actual images. Those content gates now pass against the same source. The default packager invocation performs preflight only; `--build` explicitly enables serial copying/compression after it passes. External `reserve_package_report.json` and `final_zip_verification.json` supply final ZIP/member acceptance without rewriting this payload.

```powershell
& $pythonExe 'tools/package_reserve_delivery.py' --repo . --assets $reserveAssets --report 'build/reserve_revision/package_preflight.json'
if ($LASTEXITCODE -ne 0) { throw 'Current reserve delivery evidence is incomplete' }
# Only after actual-image review and the preflight above PASS:
& $pythonExe 'tools/package_reserve_delivery.py' --repo . --assets $reserveAssets --build --output 'D:/Dev/2026-10-07/LivingTown_Reserve_Delivery'
if ($LASTEXITCODE -ne 0) { throw 'Curated reserve package failed' }
& $pythonExe 'tools/verify_reserve_delivery.py' --archive 'D:/Dev/2026-10-07/LivingTown_Reserve_Delivery/LivingTown_Reserve_Delivery.zip' --report 'build/reserve_revision/final_zip_verification.json'
if ($LASTEXITCODE -ne 0) { throw 'Final ZIP verification failed' }
```

The ZIP has a `game_assets_reserve/` folder and a curated native/source/material/license/evidence kit. `FILE_MANIFEST.json` lists every payload checksum; the external package report includes its checksum and the ZIP checksum after streaming verification of every archive member. Existing destinations are never overwritten. Reference films, raw recordings, caches and historical urban evidence/media are excluded; the separately frozen older building-study native remains labelled as source.

## Source-bound evidence

| Evidence | Meaning and current status |
| --- | --- |
| `town_manifest.json` | Native scene inventory and exact plan/module bindings for the accepted native SHA |
| `evidence/interior_planning_audit.json` | Dimensional room, fixture and compositional planning evidence; separate from native/render acceptance |
| `evidence/native_scene_audit.json` | PASS: 30 independently reopened core checks, bound to the accepted native SHA |
| `evidence/reserve_native_audit.json` | PASS: 23 actual terrain, stair clearance, triangle/overlap, route, tree, crossing, fixture/body/door and facade-cover ownership checks, bound to the same native SHA |
| `evidence/reserve_stair_land_negative_control.json` | Current audit rejected distinct historical bad bytes with 1,950 failures; final native separately passes the same gate |
| `evidence/reserve_renders.json` | Exact native/input/PNG hashes; coordinator actual review of all 15 final native images PASS |
| `game_assets_reserve/export_manifest.json` | PASS: 72 GLBs; optimized town 4,976,516 expanded triangles and 321,050,860 bytes |
| `evidence/reserve_export_verification.json` | PASS: 25 independent engine-neutral GLB hierarchy/bounds/dependency checks |
| `integration/reserve_godot/evidence/logical_report.json` / `render_report.json` / `runner_report.json` | PASS: 57 logical / 66 renderer checks, serial exit0, clean logs and four screenshot hashes |
| `evidence/final_source_freeze.json` | PASS: V6 native/source authority with 20 current frozen files |
| `evidence/reserve_visual_review.json` | PASS: separate actual review of all 19 final images, bound to current native/export/PNG hashes |

Retain diagnostic checkpoints as history. A report marked PASS is current only when its source, module, manifest and asset hashes agree with the delivered bytes. Publication of `town-reserve-2026-10-12` follows those checks and actual-image review; it is not implied by this document.
