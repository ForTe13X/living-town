# Half-timber home: living-room refinement

This candidate refines the existing segmented `lot_12_halftimber/L00/Living_Room`. It retains the authored walls, openings, stair, real overhead slab and physical material scale. Rounded cushions, detailed furniture and small props replace the earlier block furniture; the sofa/table group moves along its wall while preserving its facing and 0.40 m seating gap. The 1.10 m circulation strip and source entry/stair keepouts remain clear in the architectural checks.

| Earlier room | Candidate, matched camera and light |
| --- | --- |
| ![Earlier furniture](evidence/interior_living_room_before_v001.png) | ![Refined room](evidence/interior_living_room_after_v001.png) |

![Candidate at eye height](evidence/interior_living_room_inside_v001.png)

The candidate keeps distinct plaster, cabinet-oak and plank-floor maps. It increases the declared normal influence without enlarging the photographic pattern. The original source and maps are preserved. This is a provisional furniture/layout selection; fabric microdetail, decoration and lighting still need work, and this one room does not establish town-wide interior variety.

The portable GLB contains 17,295 triangles, 85 meshes, 30 materials and 24 embedded images. It requires `KHR_texture_transform` and selects its populated default scene explicitly. Some source images are non-power-of-two, so native intake must use the [corrected texture policy](unreal_texture_import_policy.md). Runtime texture derivatives and draw-call grouping remain to be measured.

The original render process completed all three HIP frames and wrote the new Blend/GLB. Its outer observer failed while querying an exiting process's image name; that failed report remains unchanged. Separate fresh processes then reopened the saved Blend and imported the GLB without rendering or rewriting either. Both passed object, bounds, UV and fixture/anchor readback with the no-image-name-query supervisor. Source/artifact hashes stayed unchanged, and all owned processes were reaped. This verifies the existing artifacts without relabeling the failed observer run.

Retained delivery files are `interior_refinement_actual_v1_002/IR001_Halftimber_LivingRoom.blend` (113,905,415 bytes, SHA-256 `cc3a0cc314baa4aee608ce90e7e95d730d8e4a6fcc023f189341ec33df4bde36`) and its GLB (93,165,748 bytes, SHA-256 `2a0d019df0e087f32fb26bf551c1479e5c19f631a44b3ac0790ee7d22d37704a`). Independent reopening evidence is `interior_refinement_reopen_actual_v1_001` under the retained delivery root.

The export carries building/floor/room identities and the required fixture/contact-anchor deltas. External gameplay bindings have not yet adopted those deltas. Native material appearance, door/stair/use routes, collision and frame time remain required before gameplay adoption.

## Isolated Unreal intake

| Room under native review lighting | Upholstery close view |
| --- | --- |
| ![Unreal room at EV11](evidence/interior_native_inside_ev11_v001.png) | ![Native fabric weave at EV11](evidence/interior_native_linen_ev11_v001.png) |

The byte-exact GLB was imported into an isolated UE 5.8.4 project and its 155 assets reopened in a fresh editor. Native factory identities, 30 materials, 40 texture aliases, 24 embedded-image identities/dimensions and 24 transformed texture roles passed the declared checks. The corrected policy retained all five non-power-of-two images. The 86 source nodes and their poses/bounds are checked against the portable source. Eighty-five native LOD0 exports are retained for later full array comparison. Tangents are generated Mikk because all source primitives lack authored tangents; secondary `COLOR1` preservation remains held.

The glass material retains native translucent mode and an Opacity connection, but import logged a missing `AlphaMode` input in the legacy material function. That warning and effective glass appearance remain held. The first native attempt also remains failed at its LOD-cache verifier; the corrected intake records both cache lookups and uses source-backed factory lineage where the cached child is absent.

The EV9 views were washed out. Four matched EV11/EV12 frames changed only exposure, retaining the same cameras, materials, 80 klux sun/sky and declared point fill. EV11 is provisionally selected for review: fabric weave, plaster grain and wood detail have clearer tonal separation. Lighting still reads cool and the window/context presentation needs refinement. These Unreal lights differ from the original Blender setup.

Evidence is `native_interior_intake_actual_v1_002` (132.828-second authoring, 43.594-second fresh review) and review-only `native_interior_intake_actual_v1_003` (116.656 seconds, 5,577,236,480 peak aggregate private bytes). Sources and saved packages stayed unchanged; viewport/background state was restored and owned processes were reaped. Native room data, fixture/contact anchors, collision, navigation, normal/alpha behavior, gameplay and performance have not been adopted or qualified by these frames.
