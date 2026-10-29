# Carry the selected native normal strength into portable assets

The cafe worker's selected Unreal material reduces harsh facial, hair and neck relief with a normalized blend toward a flat normal at strength 0.35. A glTF `normalTexture.scale` of 0.35 applies a different operation. This derivative bakes the saved native shader and carries its result through a core glTF normal image, retaining the original mesh and animations.

| Previous portable material | Native 0.35 material carried into glTF |
| --- | --- |
| ![Previous portable face and neck](evidence/cafe_worker_v002_portable_normal035_original_v001.png) | ![Portable native-strength face and neck](evidence/cafe_worker_v002_portable_normal035_refined_v001.png) |

Both actual Blender views use the same rest pose, camera, light, AgX settings and geometry, at 1280 × 1280 and 64 Cycles samples. They run serially on the AMD 8060S HIP device, with CPU rendering disabled. Root selects the new result as a bounded face/hair/neck improvement: forehead, eyelid and neck breakup is reduced, while the source color and hair flow remain readable. Collar and garment relief is softer. Hair silhouette protrusions, eye/hand anatomy, final garment finish, deformation and physical contact remain open. These views do not establish pixel equivalence between Unreal and Blender or approve final character art.

## Native export and preservation

The saved `M_Normal035` graph evaluates:

```hlsl
float3 n = normalize((lerp(OriginalRGB, BakedRGB, Confidence) * 2.0 - 1.0)
                    * float3(1.0, -1.0, 1.0));
return normalize(lerp(float3(0.0, 0.0, 1.0), n, 0.35));
```

The material-only native export loads no character mesh and saves no native asset. A fresh 64-pixel gradient control distinguishes normal orientation errors: maximum angular error is **0.3932°**, versus **38.0144°** with wrong green and **39.6004°** with a vertical flip. The 4096 × 4096 linear-data PNG is exported directly; no CPU normal transform or green flip is applied.

The [append-only writer](append_normal_image.md) preserves all **27,349,912 original BIN bytes**, original JSON outside its declared additions, **378 bufferViews, 374 accessors**, geometry, UVs, skeleton, two clips and all prior images. One image, bufferView and texture are added. The sampler is reused; the new binding uses UV0 and strength 1. Fresh readback and asset inspection pass. The source and native packages remain unchanged.

The delivered GLB is **40,037,224 bytes**, SHA-256 `dd9bc81d8f96b271e7ed6de64903d02db12a402d3d2879fe190588376b958655`. It derives from the **27,447,988-byte** portable bundle `df5a226c7491898a4674f7d36322a709c431b19e813fb16d7543f7caee22001d`. Its new normal PNG is `7be2071026d3b0b184141eae155f7b3e7cb19b9f1fbcf0234bc5af7d528ec88c`.

The original portable normal was already an 8-bit native bake. This new image adds another explicit 8-bit bake; it does not restore pre-quantization data. Compared with the normalized 0.35 prediction of that quantized baseline, the angular difference averages **0.1819°**, with **0.4880°** maximum. The new decoded unit-length error is at most **0.005784**, below the retained 0.02 limit. This numerical comparison measures the export; it does not author the image or establish consumer tangent/compression behavior.

## Native scheduling repair

The first export crashes when material baking streams textures and reenters Unreal's CoreTicker from an MCP operation already running there. Installed source and the retained stack support that diagnosis; the failed attempt remains failed. The continuation uses a public one-shot Slate post-tick callback, unregistering it before baking. Actual observations record begin at frame **97**, callback at **98**, the same thread **41048**, and native game-thread readback true. The status endpoint only observes progress; cleanup is permitted after a terminal callback with no handle.

All **29 focused host controls** pass. The actual native continuation completes in **67.437 seconds**, peaking at **5,949,059,072 private bytes**. The two Blender reviews complete in **20.219 / 13.657 seconds**, peaking at **3,233,329,152 / 3,222,429,696 private bytes**. All owned processes are reaped and source hashes remain exact. Timing describes these export/review jobs, not gameplay performance.

The retained evidence root is `F:\Living Town\2026-10-20_Refined_Town`. Native observations and output are in `native_normal035_portable_actual_v1_002`; the GLB is `Portable/cafe_worker_breton_v002_portable_normal035_idle_walk.glb`. Matched GPU observations are in `native_normal035_portable_hip_actual_v1_002`. The earlier `v1_001` crash and partials remain separate. The [native alignment adapter](native_root_correction.md) is a separate runtime operation; this material derivative does not alter clip alignment or bind the new character into Game.
