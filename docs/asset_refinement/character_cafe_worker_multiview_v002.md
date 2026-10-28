# Cafe worker v002: two-view Tripo source candidate

One original high-detail candidate has been generated and preserved for visual review. It is **not an accepted game character**. Provider task `183abe00-c177-48f4-b834-6c25e65784bd` succeeded and charged **60 API credits**. The account readback after completion, at `2026-10-28T03:24:37.548Z`, recorded **900 available / 0 frozen**; this is an observed balance, not a live value. Credentials were unchanged.

![Provider preview of the new source candidate; Blender review follows](evidence/cafe_worker_multiview_provider_v002.png)

## Generation request

The installed Tripo CLI 0.7.2 official client submitted exactly one `POST /v3/generation/multiview-to-model` request with explicit `front` and `back` image slots. The references are a concept pair, **not calibrated views from the same capture**. Their clothing, lighting, pose and perspective may therefore disagree.

| Slot | Repository reference | SHA-256 |
| --- | --- | --- |
| Front | `docs/asset_refinement/concepts/cafe_worker_breton_v001/reference_front.png` | `5c54987ab21f00401ca5807041e4bc2243cd9a97578371f280dbea3a456c89d8` |
| Back | `docs/asset_refinement/concepts/cafe_worker_breton_v001/reference_rear_v001.png` | `adde894b0483b74f9893b914624c060fb59c9670f5f5d43d94ee276891317632` |

The transmitted generation settings were:

```json
{
  "model": "v3.1-20260211",
  "texture": true,
  "pbr": true,
  "texture_version": "v3.5-20260815",
  "texture_quality": "detailed",
  "delight": true,
  "geometry_quality": "detailed",
  "texture_alignment": "original_image",
  "export_uv": true,
  "model_seed": 20261028,
  "texture_seed": 20261028
}
```

No text prompt was transmitted. The artistic brief was retained separately; the H-series multiview endpoint does not document a prompt parameter, and CLI 0.7.2's multiview builder does not forward `--prompt`. No `face_limit`, `auto_size`, `export_orientation`, smart low-poly, quad or parts option was sent. `auto_size` was left unset (documented default false), so physical stature and metric calibration remain unqualified. No rigging, retopology, animation or conversion task was queued.

The current official [H3.1 model page](https://developers.tripo3d.ai/en/models/v3-1) and [pricing page](https://developers.tripo3d.ai/en/pricing) estimated 60 credits: detailed multiview texture 40 plus detailed geometry 20. That was an estimate, not a server quote; the completed task independently recorded the same charge. The [H-series multiview API](https://developers.tripo3d.ai/en/docs/generation-multiview-to-model/standard) documents the image slots and texture-model settings.

## Preserved original and CPU facts

Delivery files remain outside the repository, under `tripo_cafe_multiview_actual_v1_001` in the retained delivery root.

- Original: `source/cafe_worker_breton_v002_original.glb`, **64,556,396 bytes**.
- SHA-256: `dcbec3404706965bb8924c489f48466394b31daefb59b363906317427441609e`.
- One mesh/primitive and one PBR material; **1,014,595 vertices / 1,969,262 triangles**.
- Three actual embedded **4096 × 4096** images: base color **RGB JPEG**, metallic-roughness **RGB JPEG**, normal **RGB PNG**. These are present source maps; their appearance and effective material behavior are not yet accepted.
- No skin, skeleton or animation clips.

The canonical CPU inspector's `CHARACTER_SOURCE_FACTS.json` returned `FACTS_ONLY`, with no refusals and unchanged source bytes/size/mtime/hash. It found no degenerate or near-zero-area triangles in the declared primitive. This is structural evidence; it does not qualify anatomy, topology for deformation, art, physical scale, performance or engine behavior. Raw active-scene rest extent is approximately `(0.18551, 0.98082, 0.50505)` glTF coordinate units; it does not establish a 1.79 m adult.

The provider's preview is `preview/provider_preview.png`, an original **512 × 512 PNG**. The returned URL used a `.webp` suffix, but the downloaded signature is PNG. The original mislabeled download and stopped watch receipt remain preserved; a byte-exact copy with the correct PNG suffix required no re-encoding or second download. This provider image is **not a Blender render or Blender review**. Private task metadata may contain expiring signed URLs and is not copied into repository documentation.

## Actual Blender review and remaining detail

| Three-quarter source view | Rear construction |
| --- | --- |
| ![Actual HIP source view](evidence/cafe_worker_multiview_threequarter_v002.png) | ![Open rear apron over trousers](evidence/cafe_worker_multiview_rear_v002.png) |

| Face and hair detail | Hand detail still held |
| --- | --- |
| ![Actual source face](evidence/cafe_worker_multiview_face_v002.png) | ![Actual source hand](evidence/cafe_worker_multiview_hand_right_v002.png) |

Six actual HIP views inspect Front, ThreeQuarter, Rear, Face and both hands. Each uses a fresh Blender process, original PBR links and declared neutral studio lighting; each process is reaped before the next. The six runs total 164.515 seconds, peaking at 5,279,961,088 aggregate private bytes per job. Source bytes, decoded topology/UV/corner normals, material graph and packed maps remain unchanged. Cameras receive a declared 90-degree yaw for this source's orientation; the unapplied parent sets nominal viewing height to 1.79 m without qualifying actual stature.

This is provisionally selected as a source base for detail repair. Clothing seams, apron pockets/buckle, trousers and shoes read clearly. The rear exposes trousers beneath the waist belt instead of a closed rear apron skirt. Hair-tip stubs, eye-rim material response and forearm appearance require refinement or attribution. Later lateral views resolve the earlier frontal finger ambiguity, as recorded below. Final retopology/UV review, bake, rig/deformation, walk/eat/sleep contact, metric scale, engine integration and measured performance remain pending. The nearly two-million-triangle source is not a runtime budget.

Generated-output rights follow the provider account terms; this candidate is not represented as CC0. No Tripo bridge/vendor code, credentials or signed URLs are redistributed by this document.

The retained `COMPLETION_RECEIPT.json`, `SOURCE_FACTS.json` and `CHARACTER_SOURCE_FACTS.json` bind task, source and maps. Actual GPU evidence is `character_multiview_source_review_actual_v1_001/SIX_VIEW_SOURCE_REVIEW.json`, SHA-256 `204e06c585997f58515ce0e73d09910f3784bd7b90c74c0fae4b56e865038ae7`, alongside the per-view receipts and root visual review.

## Local material derivative and hand clarification

| Lower-orbital material candidate | Unedited source hand, lateral view |
| --- | --- |
| ![Localized PBR candidate](evidence/cafe_worker_v002_orbital_pbr_face_v001.png) | ![Five separated source digits](evidence/cafe_worker_v002_hand_lateral_v001.png) |

Actual lower-lid probes sampled roughness about .145/.161 and metallic .059/.067. A source-bound CORNER mask was baked into the existing 4K UV layout, then used to raise skin roughness toward .48 and remove metallic response locally. Only 5,179 texels have positive mask weight. Outside-mask RGB8 values, the red channel and 1,943,604 protected used-UV samples remain unchanged. Albedo and normal maps are untouched. The matched 53.188-second HIP Face view provisionally selects this restrained local correction; it does not finish eye anatomy or whole-face art.

The portable GLB appends the derived ORM PNG and repoints its existing image reference. Its complete original BIN prefix, accessors, indices, UVs, normals, nodes, scenes and material factors remain intact. The independent texture-only comparator passes, and the [reusable writer](append_metallic_roughness_image.md) reproduces the actual 74,850,764-byte output exactly, SHA-256 `f6f5cc4e1df6ba12c4792a81cbb8183f7d85977becce91eda077a107a316e235`. Native bake and pixel evidence is `character_v002_pbr_refinement_actual_v1_001`; seam/mip and engine review remain open.

Fixed lateral views show five distinct digits with nails and joint contours on both hands. Source plane sections independently find five separated loops proximally and four distal finger loops. Earlier frontal crops stacked fingers in depth; they did not establish fused anatomy. Hands remain unedited, and rig/deformation still needs testing. Forearm normal samples are nearly flat, while geometric residuals are mostly sub-millimetre at nominal view scale; neither supports a broad smoothing or normal-map correction. The first sparse hair-tip deformation remains held because its visible improvement was too mild. A local topology repair is being prepared, with the original source retained.

## Separate runtime retopology trial

| Runtime trial, three-quarter | Close shading regression: held |
| --- | --- |
| ![Actual 18,425-triangle HIP candidate](evidence/cafe_worker_v002_runtime_threequarter_v001.png) | ![Triangular face/neck shading requires attribution](evidence/cafe_worker_v002_runtime_face_held_v001.png) |

One [Tripo v3.0 retopology request](https://developers.tripo3d.ai/en/docs/mesh-decimate) used the portable lower-orbital PBR derivative, a 20,000-triangle limit, smart UVs, texture baking and triangle output. Task `6464b3a3-249c-4ff2-89c5-b422ec896eee` completed for **35 credits**. It returned **18,425 triangles / 10,703 vertices**, 99.064% fewer triangles than the high-detail source. The untouched downloaded GLB is **6,950,588 bytes**, SHA-256 `097839e26460c98c0fb25128c148e70271abe233f0b60c66de3943c9cf42e589`.

This is a new geometry/UV/bake lineage. It has 4K JPEG albedo, 2K JPEG normal and 2K PNG ORM, with no rig or clips. Original maps cannot simply be repointed onto its new UVs. Its rest bounds also changed; nominal 1.79 m review framing does not qualify physical scale. A file-size or triangle reduction does not establish game FPS.

Six fresh-process HIP views completed in **86.406 seconds**, with **3,895,869,440 peak aggregate private bytes**, preserving the downloaded source and decoded mesh/material/maps. Clothing construction remains readable in full views. Close face/neck and hair show triangular shading patches; hand silhouettes are coarse and forearm shading remains uneven. Root holds final art and is isolating normal-map response from albedo before correction. The candidate can support a separate compatibility/deformation experiment while that work continues.

The first download observer stopped before writing output bytes and remains preserved. Bounded GET recovery downloaded the same successful task output without creating another task. The post-task balance at `2026-10-28T05:30:51Z` was **865 available / 0 frozen**, with unchanged credentials. Actual intake is `character_v002_runtime_retopo_actual_v1_001`; GPU evidence is `character_v002_runtime_review_actual_v1_001/SIX_VIEW_SOURCE_REVIEW.json`, SHA-256 `d1fb1d3c88bdbc80ff305f27f2612f8f9f26ebacc0bba0020fbea09a48369917`, plus root visual review. No production character, animation or engine adoption follows from this trial.

Two additional matched Face renders disconnect only the normal map, then display the existing albedo through emission. Both remove the pronounced lit face/neck patches, implicating the normal-map/tangent-space path. They do not isolate compression, channel convention, projection or tangent basis individually. No repaint, smoothing, UV rebuild or source export was performed. These controls are retained under `character_v002_runtime_shading_diagnostic_actual_v1_001`.

The exact downloaded model also passed Tripo's separate [riggability check](https://developers.tripo3d.ai/en/docs/animations-rig-check): task `097eb686-6011-41d1-9fcd-ca47a68fe71f` returned `riggable=true`, recommended `biped`, and charged **0 credits**. Compatibility does not establish weights, deformation, contact or art acceptance. An experimental motion path remains separate from final surface acceptance.
