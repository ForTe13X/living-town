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

The additional green-channel-only flip does not remove the triangular shading and exaggerates some hair/neck ridges. It remains a diagnostic, with no portable map change. A lossless bake on the target tangent basis is being prepared after source/target registration.

## Rig and walking experiment

One explicit v3.0 biped rig request used Unreal bone naming and portable GLB output. Task `39fc76bc-289e-471d-a454-a61c351fc146` charged **25 credits** and returned a **61-joint** skin with at most four influences per vertex and weight-sum error at most `1.0361e-7`. The original rig GLB is **7,184,004 bytes**, SHA-256 `9cc396e73869a4b17777851dff72e4b0f5d889e82019af1b8efb14417b22b77b`, retained in `character_v002_runtime_rig_actual_v1_001`.

Direct accessor hashes differ after rigging. A separate exact-UV bijection covers all 10,703 vertices and preserves the oriented triangle multiset; all three image-role encoded bytes, samplers and normal scale match. Positions fit a measured uniform scale/translation with maximum residual `1.579e-6` source units. Normals differ slightly, so this is not a byte-preservation claim or a deformation qualification.

One [in-place walking retarget](https://developers.tripo3d.ai/en/docs/animations-retarget), task `9af45f45-f155-4ad3-b78d-cdb3462acaad`, charged **10 credits**. Its untouched GLB is **7,255,492 bytes**, SHA-256 `cff40bcce82395e8ed8e9bd2c7cb9c7cce9989f0d1e94f45461568c96b39a1ec`. The inspector finds one `walk` clip spanning about **2.333 seconds**, with 183 channels. Actual pose, apron/limb deformation, contact, looping and engine review remain required. Evidence is retained under `character_v002_runtime_walk_actual_v1_001`; the observed post-task balance at `2026-10-28T06:03:18.788Z` is **830 available / 0 frozen**. No further cloud operation is implied by these receipts.

![Actual walking phase; garment and surface art remain held](evidence/cafe_worker_v002_walk_phase75_held_v001.png)

Four fresh HIP processes now render 0/25/50/75% of the clip, with actual evaluated vertices and bone positions. They total **69.578 seconds**, peak at **3,703,197,696 private bytes**, preserve the source mesh/maps/action and restore pose/frame/parent state. The first failed attempt counted Blender's bone-display Icosphere as a character mesh. Its no-image failure is retained; actual import inventory identified the helper and the corrected attempt selects the real skinned body while preserving the helper.

The reviewed frames show distinct leg/arm poses and readable clothing. The end/start boundary has maximum vertex difference about **0.924 mm** at nominal review scale and zero root-bone difference. Phase75 shows a dark break near the front pocket and a curled apron hem; the cause requires garment/normal-path review. A weighted sole proxy also reaches about 10.34 mm below the studio plane. These are not physics contacts or final animation acceptance. Evidence is `character_v002_walk_motion_actual_v1_002`; native Unreal playback is the next integration check.

Seven isolated native assets now import and reopen successfully. The separate Unreal review observes **48 samples over 0.7956 seconds** with naturally advancing animation time and distinct limb poses; it injects no manual time or bone updates. The 61 source joints are present, and native LOD0 has 10,707 vertices, including four additional tangent splits. Native animation length is 2.366667 seconds, whereas the portable clip's first-to-last-key span is 2.333333 seconds; identical timeline duration is not claimed. The review completes in **53.484 seconds**, peaks at **5,587,161,088 private bytes**, preserves sources and reaps its processes. Evidence is `character_v002_walk_native_intake_actual_v1_002`. Dark studio lighting and editor overlays prevent final presentation acceptance; this is editor playback, not a player-character replacement or game-performance result.

![Readable native walking review with original character materials](evidence/cafe_worker_v002_native_walk_readable_v004.png)

A later review uses native atmosphere/skylight, a camera-side diagnostic fill, explicit directional-light priorities, Game View and cleared selection. Both distinct-pose frames are now readable, with no light-priority warning or selected-object overlays. Root accepts this limited native lighting baseline. The same seven assets and original character materials remain unchanged; the floor's stretched checker is diagnostic scenery, and skin/hair/garment art stays held. `character_v002_walk_native_intake_actual_v1_004` completes in **53.313 seconds** with **5,482,799,104 peak private bytes**, then restores camera, show flags, selection, background throttle and actor inventory before reaping. The constrained face-normal candidate below is not yet applied in this native frame.

## Constrained face normal refinement

![Matched face shading with explicit projection confidence](evidence/cafe_worker_v002_confidence_face_v001.png)

A lossless normal bake on the final rig's target tangent basis removes the strong facial patches, but a whole-map replacement introduces dark responses around hair and collar. The retained full-map trial is rejected. The constrained candidate instead mixes the original and baked normals through a complete source-space face ROI, excluding independently measured projection misses and ambiguous samples. A 16-pixel inward guard and eight-pixel feather protect those boundaries. Original normal samples remain the direct input wherever confidence is zero; source geometry, UVs, albedo and ORM remain unchanged.

Root selects the visible facial-shading improvement only. The unchanged neck artifacts, hair protrusions, eye anatomy and final character quality remain open. All four actual phases—ROI mask, CPU confidence, ROI preview and matched HIP Face render—pass and are reaped, with source guards preserved. Evidence is `character_v002_confidence_masked_face_actual_v1_001`; the displayed PNG has SHA-256 `bcea77c0fb83010dd5c9fe3b2d7fca76d1396b44ed0fdb037a65d21fcf528cda`. This is a Blender material candidate: no portable composite or native Unreal material has yet been adopted. The source maps, explicit mask and bake recipe remain available for a native material adapter.
