# Living Town model and asset sources

The current work is the **reserve asset edition**: the coastal town plus wooded hills, graded routes/crossings, a 12-trailer court and nine furnished visitor/service units. Town interiors also receive deliberate furniture grouping, wall-facing and working-front clearance planning.

Read [RESERVE_EDITION.md](../../docs/RESERVE_EDITION.md) for the edition scope, exact source files, portable hierarchy, six-thread serial build/export/consumer commands and source-bound evidence. Release target: `town-reserve-2026-10-12`.

[Curated ZIP](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/LivingTown_Reserve_Delivery.zip) · [ZIP checksum](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/LivingTown_Reserve_Delivery.zip.sha256) · [Packager receipt](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/reserve_package_report.json) · [Independent ZIP verification](https://github.com/ForTe13X/living-town/releases/download/town-reserve-2026-10-12/final_zip_verification.json). The external receipts supply final ZIP/member acceptance; the ZIP's own checksum is outside the payload.

**The existing playable game still uses its prior urban 3D stage.** This edition delivers Blender/GLB assets and an isolated Godot consumer. It does not yet place reserve navigation or interactions in the main game. Native/source verification, export verification, Godot checks and actual review of all 19 final images pass.

| Acceptance | Status |
| --- | --- |
| Saved-native geometry audits | PASS: 30 core and 23 reserve checks |
| Final V6 source freeze | PASS: 20 current frozen files |
| Measured portable GLBs and isolated Godot checks | PASS: 72 GLBs, 25 independent checks, 57 logical / 66 renderer checks |
| 15 final native stills | PASS: coordinator actual-image review |
| Four consumer captures and combined 19-image review | PASS: actual review with current source/export/image hashes |
| Curated ZIP and final checksums | Final acceptance supplied by external package and ZIP-verification receipts |

The accepted native SHA256 is `99fca62005524b1c2a331cbe81316b43b8d9622d92a408db6703fe3cf4760191`. The [core audit](evidence/native_scene_audit.json) passes 30 checks and the [reserve audit](evidence/reserve_native_audit.json) passes 23 against the same native bytes, with 19,663 scene objects. The [V6 freeze](evidence/final_source_freeze.json), SHA256 `4aec7be876f094c648a189efb615d8b857e32dd1fec7a54e60d49612e2744df3`, binds 20 current files. The native checks include actual saved triangle quality and all 15,879 eligible convex route faces, with zero same-route coplanar overlap pairs above the unchanged 0.00001 m² limit after the shared cross-section repair at nearly straight stations. Three staff desks also use a rear 0.60 m desktop with the chair clear in front, preserving their IDs and composite footprints. Local front covers own all 82 facade attachment meshes across the 21 units, allowing sign boards and exterior attachments to hide with their wall without leaving interior barriers; ground utilities remain separate.

Both stairs now have excavated continuous land and corrected endpoint approaches. The actual clearance gate passes 2,635 walking/land columns and 3,681 body rays with zero failures, including trail sheets in the 2 m head band. The [compact historical negative control](evidence/reserve_stair_land_negative_control.json) separately records the same audit rejecting the earlier faulty native with 1,950 failures; those bad model bytes are not delivered.

- [living_town_complete.blend](living_town_complete.blend): native scene `Living_Town_Summer`; the filename is reused, so compare source checksums across editions.
- [town_manifest.json](town_manifest.json): core and separate reserve inventories with plan/module bindings.
- [reserve_plan.json](reserve_plan.json): terrain, pads, routes, crossings, woodland and 21 amenity placements.
- [interior_plan.json](interior_plan.json): room, fixture and furniture-composition planning.
- [reserve_amenities.py](tools/reserve_amenities.py): 92 local room/circulation zones, 158 interior furnishing assemblies and 12 picnic assemblies across 21 units.
- [reserve Godot consumer](integration/reserve_godot/README.md): source-driven hierarchy/PBR/shared-mesh checks and optional four real-renderer captures.
- [natural-rock material](textures/natural_rock_material.json): original 4 m fractured granite PBR for exposed cliffs/rocks, separate from built masonry.

The complete GLB preserves `LivingTown/Buildings` for the original town and adds `LivingTown/NaturalReserve` with separate environment/amenity subtrees. Roof and front covers remain local controls; reserve room/asset metadata has its own namespace. The export package includes local-origin prefabs for each amenity, embedded PBR textures and metre coordinates. Collision, navigation and runtime streaming require consumer implementation.

Shared woodland meshes use the detailed near form around town/camp and within 22 m of any authored route; the outer woodland uses simpler far forms. These are fixed authoring choices rather than runtime LOD switching.

Exports go to the separate `game_assets_reserve/` directory. The release recipe uses `--detail game --prefabs all --camera-rig --triangle-budget 5000000 --label final`: one optimized town, 49 original prefabs, 21 reserve prefabs and an 18-camera rig. The optimized town measures 4,976,516 expanded triangles and 321,050,860 bytes, within the 5M ceiling; this is not a frame-rate or streaming measurement. Independent verification passes 25 checks with `--manifest game_assets_reserve/export_manifest.json` explicit. The isolated consumer passes 57 logical and 66 renderer checks with clean stderr. The curated release [packager](../../tools/package_reserve_delivery.py) and [validator](../../tools/verify_reserve_delivery.py) live in the repository's `tools/` directory; their default preflight does not compress a package.

The following images belong to the current 15-image final native batch, actually reviewed and accepted by the coordinator. The four engine captures also pass actual review; the [combined 19-image receipt](evidence/reserve_visual_review.json) binds every current source/export/image hash:

| Image | Inspect |
| --- | --- |
| [Reserve overview](renders/reserve_v6/01_reserve_overview.png) | Woodland coverage, graded routes and town-to-reserve connections |
| [Family trailer interior](renders/reserve_v6/07_trailer_family_interior.png) | Coherent living groups and clear entry/working circulation |
| [Bathhouse interior](renders/reserve_v6/11_bathhouse_interior.png) | Changing, wash and shower compartments with usable approaches |
| [Ravine bridge](renders/reserve_v6/14_ravine_bridge.png) | Continuous deck, supported landings and terrain clearance |

The [presentation board](PRESENTATION.html), [delivery guide](DELIVERY_GUIDE.md), [building study](living_town_building_study.blend) and their existing media document the earlier urban V5 delivery. Keep those showcase artifacts intact, but do not treat their earlier PASS counts or images as reserve-edition evidence. New source-bound records and reviewed reserve renders will identify the completed edition explicitly.
