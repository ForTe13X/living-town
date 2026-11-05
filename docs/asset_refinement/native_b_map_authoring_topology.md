The Editor-only B topology reader is compiled and has been observed successfully in a native producer. Producer007 then saved a family containing 851 inspection-map files while preserving the original 850 files. Independent cold reopening, PIE capture and final-art approval remain **HELD**. The portable hashes and qualification states are in [qualification.json](../evidence/native_b_topology_20261105/qualification.json).

`LivingTownBMaterialInspection.read_b_source_map_save_topology()` returns a JSON string. It observes only the current, clean **original v002 B Editor World**:

```text
/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_StaticFinish_v002/MillCourtB_StaticFinishInspection_v002.MillCourtB_StaticFinishInspection_v002
```

The call requires the Editor game thread, no commandlet or PIE, the exact Editor World, a clean map package, and its registered current native level viewport. It also requires one valid PersistentLevel with that World's exact outer/path and a single loaded-level array containing the same Level. It loads, duplicates, edits and saves nothing. See the [declaration](../../unreal/Source/LivingTownMaterialInspection/LivingTownBMaterialInspection.h) and [implementation](../../unreal/Source/LivingTownMaterialInspection/LivingTownBMaterialInspection.cpp).

Python could call public `Actor.get_level()`, but attempts002/003 demonstrated that both `World.PersistentLevel` and `Level.MapBuildData` reject Python editor-property reads as protected. A C++ public UPROPERTY declaration alone does not establish scripting access. This typed native observer reads the actual native fields and ownership instead of bypassing Python property protections. Existing B texture-reader and viewport APIs retain their original map/asset guards and semantics; the saved LightFix map is not added to those allowlists.

The schema is `LivingTown.BSourceMapSaveTopology.v1`. An observed response has status `READ_ONLY_B_SOURCE_MAP_SAVE_TOPOLOGY_OBSERVED` and the following fields:

| Field | Meaning |
| --- | --- |
| `world` | Exact original v002 World object path |
| `persistent_level` | Exact `world:PersistentLevel` path |
| `loaded_level_count` | Native loaded-level count, 1 after the ownership guard |
| `persistent_level_outer_is_world` | true after exact outer validation |
| `uses_external_actors` | Native Level external-actor setting |
| `has_world_partition` | Whether the native World partition pointer exists |
| `map_build_data_present` | Whether native Level.MapBuildData exists |
| `map_build_data` | Its actual object path, or JSON null |
| `asset_loaded_duplicated_edited_or_saved` | false |

Invalid context returns `REFUSED` with reason `exact_clean_B_source_Editor_world_viewport_game_thread_no_PIE_required`; invalid level ownership/count returns `exact_single_owned_persistent_level_required`. An observed response is not permission to save: the producer additionally requires external actors, World partition and build-data presence to be false, with a null build-data path. Its native call actually observed those values. Unsupported responses hold before mutation.

Editor018 completed in 463.219 seconds with root exit 0, empty owned reap, all nine declared custody guards passing and 410 source-metadata witnesses. Its source family contains 205 full files and 156 native inputs. Only the two Editor inspection files differ from017; all 203 other files and prior B API bodies/declarations match. This is an Editor build qualification; Game017 remains separate historical evidence.

Saved producer007 completed in 73.110 seconds with controlled exit 92, empty reap and source/global preservation. It retained 750 placements, 205 material overrides and 32 point-light properties, changing only the copied Interior location to `[-3520,-3620,786.3258934020996] cm`. All 760 ordinary actor states remained exact apart from that location, and the original World's 763 raw actor records remained unchanged through finish. The three separately disclosed Engine services are AbstractNavData-Default, BuoyancyManager_0 and GameplayDebuggerPlayerManager_0. Actual005 comparison and primary SDK serialization/spawn evidence explain their omission from the inactive duplicate; the contract covers only those three literal roles and preserves exact numeric comparisons.

The newly saved package is:

```text
/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_LightFix_v001/MillCourtB_LightFixInspection_v001
```

It is 1,355,114 bytes with SHA-256 `587717e29fbc85fdb607db3c15a6022064536d9e661db7574dad0b0012b4f49d`. The closed packet contains the original 850 files plus this one new map. The packet and root-review hashes are recorded in the portable evidence.

The lifecycle deliberately separates saving from cold validation. Attempt006 saved once and confirmed stable bytes, then same-process LoadLevel terminated with EditorServer2544 reporting two World/package memory leaks. That failed map and cache are never donors. Producer007 regenerated from the accepted 850 inputs and Editor018, kept the original World active and retained the saved inactive duplicate, sealed the 851-file packet, then closed through controlled exit 92. It introduced no World-flag, GC, undo or standalone-object manipulation and claims no viewport restoration across a World switch.

A separate fresh consumer must stage the exact admitted 851-file packet, reopen the saved map, verify the 760 ordinary actors, 750 placements, 205 overrides, 32 point properties and three-service contract, read the four graphs/nine textures, and close normal PIE, viewport and source/global custody. Until that evidence is admitted, cold/PIE, final art, production lighting and later material adoption remain held. These results do not establish gameplay, frame rate, residency or a finished town. The README/demo GIF remains reserved for an actual narrated walkthrough.
