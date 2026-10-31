# Authored café furniture trials

The original café binding requires exactly 289 distinct source meshes. A furnished revision needs repeated instances of the same chair and table. The new optional `part_contract` declares the complete instance roster while retaining source geometry, collision, role and material checks. Files without this field keep the original 289-part contract.

An authored binding must use `UE_ASSET_QUALIFIED_TRIAL`, declare 1–512 instances, and provide the exact floor and counter subsets. IDs must be canonical source IDs or `authored_cafe:instance:` IDs. Duplicate IDs and case aliases, conflicting shared-mesh render hashes or collision GUIDs, undeclared materials, invalid transforms and nonpositive scales refuse. The source-context digest binds the parent binding, layout plan, independent asset-load proof and source geometry manifest. A trial tag does not imply finished art or shipping acceptance.

The venue checks every actual loaded mesh and all default material slots before creating its components. Each instance retains its own ID, transform and `BlockAll` collision. Repeated prototypes therefore remain individually observable for layout and movement checks.

## Player camera

Both café controllers disable automatic camera-target replacement. The original café GameMode selects Ben as the view target only after physical attachment succeeds. The property scenario retains its existing selection path. Failed attachment returns before selecting the destroyed pawn.

The optional viewport CSV observer records the controller, possessed pawn, view target, camera-manager target, automatic-management flag, finite player-view coordinates/rotation/FOV and one sample per natural tick. Its first valid player-view log retains full coordinate precision. It rechecks the exact world scope during capture and does not move a pawn or select a camera.

## Editor readback

`LivingTownTownSliceReadbackLibrary.export_cafe_furniture_meshes` exports exactly the qualified chair/table pair, in either order, through the existing bounded raw-buffer implementation. The town-slice endpoint keeps its original namespace. The C++ function returns a bool and two FString outputs; stock Unreal Python returns a two-element tuple on success and `None` on failure.

`LivingTownStaticMeshCollisionInspection.read_static_mesh_collision` observes an already-loaded exact `UStaticMesh`. It returns bounded source, render-provider and cooked Chaos collision information, reports unavailable data as pending, and does not create a body, cook, repair or save an asset. The caller must bind the returned asset and arrays to its intended source. Asset defaults are separate from live component collision policy.

## Recorded validation and limits

The integrated 140-file source roster is byte-identical to the qualified Native98 Editor003 source family `0e65a9555e823cc471cbbbe30f510c262d1c3025c0661420320bb0d1ed8bfb73`. Existing PR104 HUD and DPI behavior is retained.

| Evidence | Scope |
| --- | --- |
| Editor003 build receipt `e0801d52e556863aefd9d45a5848f3c76ba171c75a893e3f9c0ee68d3eb548d7` | Actual successful Editor build, matching loaded module, closed process ownership and source guards. |
| Game002 build receipt `e5869e2717116d625e3a69ddf4d0a8030f48498ee90db86471efda94a6613407` | Parent source family `a63358dabe337923155cb7830c41427fbac46a0ba918a1bb4a396375f27d5dfa`; the successor adds only two Editor inspection files. This is not a newly built Game003 receipt. |
| Independent furniture reload | Two CC0 source models, ten native packages, source/render/collision/material and texture readback in a fresh process. |
| Room005 native run | 261 instances, 257 unique meshes, six 1920×1080 views, six interior walks and a 22.789-second exterior route; normal Unreal exit code 0. |

The Room005 host's original overall result remains failed: its final CPU predicate incorrectly demanded opaque distance-field residency for the translucent counter glass. The original failure is preserved. A separate read-only recovery checks retained evidence using source and native material eligibility, with explicit requirements for all five repaired shell meshes and both furniture meshes. Its result must be recorded separately from a native rerun.

The exterior route recorded 1,752 frame samples, mean frame time 13.007 ms, p95 15.602 ms and mean GPU time 11.052 ms on Radeon 8060S/D3D12. This is one controlled Editor Development `-game` route. It does not establish a shipping target, full-town frame rate, cold-loading time or an improvement over the previous layout.

The reviewed views show conventional opposing seating and visible plaster/ceiling texture. Floor-highlight clipping, coarse food and cup props, unfinished signage/cabinets, the legacy resident appearance and exterior presentation remain open. The head atlas, new outfit, broader interiors, terrain, full-town performance, packaged furniture delivery and narrated walkthrough are outside this source change's acceptance.

The existing native tests `LivingTown.Native.CafeBindingRefusals`, `LivingTown.Native.CafeAuthoredPartContractRefusals` and `LivingTown.StaticMeshCollisionInspection.BoundedReadOnly` cover metadata/refusal boundaries. Their execution result is separate from compiling them and from the actual asset/room observations above.
