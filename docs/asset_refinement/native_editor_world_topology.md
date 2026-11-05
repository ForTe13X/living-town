`LivingTownViewportInspection.read_current_editor_world_topology()` is a passive native observer for the existing clean Editor World. Editor019 compiled it successfully, and the material176 producer subsequently observed the LightFix source World through it. That producer saved a family containing 859 files while preserving its 851 inputs. Independent cold validation of the new 859-file family, final art, performance and cooking remain **pending**. [qualification.json](../evidence/native_editor_topology_20261105/qualification.json) records portable proof hashes and the scope of each result.

The new method is separate from the existing map-specific B topology reader. Existing texture readers, viewport configuration/restoration APIs, map allowlists and shared scope ownership remain unchanged. See the [declaration](../../unreal/Source/LivingTownMaterialInspection/LivingTownViewportInspection.h) and [implementation](../../unreal/Source/LivingTownMaterialInspection/LivingTownViewportInspection.cpp).

The observer requires the Editor game thread, no commandlet/PIE or game context, exactly one valid existing Editor context, and its live registered current level viewport. It enumerates const `GetWorldContexts()` rather than calling `GetEditorWorldContext()`, whose missing-context fallback asserts and can create a context. It then requires a clean non-PIE package, an owned PersistentLevel in that package and valid WorldSettings. The WorldSettings check prevents unavailable settings from being reported as proof of partition absence. A nonnull invalid build-data reference refuses.

Its JSON string has this **nested** contract:

```text
schema: LivingTown.CurrentEditorWorldTopology.v1
status: READ_CURRENT_EDITOR_WORLD_TOPOLOGY | REFUSED
error: empty on success, otherwise the refusal explanation
readback: observed fields on success, empty on refusal
```

| Successful `readback` field | Meaning |
| --- | --- |
| `world`, `world_package` | Actual loaded object path and logical package name |
| `world_package_dirty` | false after the clean-package guard |
| `persistent_level`, `persistent_level_outer_is_world` | Actual native level path and validated ownership |
| `loaded_level_count`, `persistent_level_in_loaded_levels` | Native level-array count and membership |
| `uses_external_actors`, `has_world_partition` | Native topology flags |
| `map_build_data_present`, `map_build_data` | Native presence and object path, or null |
| `client_identity_diagnostic_only`, `viewport_identity_diagnostic_only` | Process-local correspondence diagnostics; values omitted from portable evidence |
| `asset_loaded_duplicated_edited_or_saved` | false; this observer performs none of those operations |

The observer reports level count rather than imposing a single-level authoring rule. Callers must check success before reading `readback`, bind their exact expected World/package and admitted on-disk package hash, and apply their own authoring policy. Material176 required count 1, PersistentLevel membership/ownership, no external actors or partition, and absent/null build data. Logical names, clean flags and diagnostic pointers do not prove that loaded memory is identical to a particular asset file. Hash/staging custody and scene validation remain separate caller responsibilities. The method neither reads a disk hash nor authorizes a save.

The actual source observation was:

```text
/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_LightFix_v001/MillCourtB_LightFixInspection_v001.MillCourtB_LightFixInspection_v001
```

It returned the success status, a clean package, one owned/member PersistentLevel, false external-actor/partition/build-data flags and null build data. This qualifies the material176 **source preflight** observation; the new material map was not activated or cold reopened in that producer.

Editor019 completed in 458.781 seconds with root exit 0, empty owned reap, all nine declared custody guards passing and 410 source-metadata witnesses. Its source family contains 205 full files and 156 native inputs. Only the two ViewportInspection files differ from positive018; all 203 others and previous viewport/B APIs match. This is an Editor build result, with no Game019 qualification.

The material176 producer completed in 121.437 seconds with controlled exit 92, empty reap and all declared source/global custody checks passing. Its 851 source files remained byte/mtime exact. It added four textures, three materials and one map, and changed exactly 176 copied component material overrides while preserving the accepted 205. The 750 placements, 760 protected actor states apart from the authorized material delta, point-light properties and source actor roster were preserved. Meshes, UVs, TBN, LODs and geometry were not changed. The packet contains 859 files and is bound by the root review/admission hashes in the evidence record.

The new saved map is:

```text
/Game/LivingTown_UEPilot/TownSlice_v003/MillCourtB_Material176_v001/MillCourtB_Material176Inspection_v001
```

The producer finished with its LightFix source World active and the saved duplicate retained. It performed no same-process map reload and makes no viewport-restoration claim across a World switch. The next consumer must independently reopen the exact admitted 859-file family and read the saved graphs/textures and scene state. Producer shader records and successful saving do not establish final appearance, texture residency, frame rate, navigation/collision, cooking or whole-town readiness.
