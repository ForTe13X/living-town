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

This is provisionally selected as a source base for detail repair. Clothing seams, apron pockets/buckle, trousers and shoes read clearly. The rear exposes trousers beneath the waist belt instead of a closed rear apron skirt. Close inspection still holds blunt hair-tip stubs, soft finger contours/joints, shiny eye rims and exaggerated forearm grooves. Geometry and regional PBR need refinement before final retopology/UV review and bake. Rig/deformation, walk/eat/sleep contact, metric scale, engine integration and measured performance remain pending. The nearly two-million-triangle source is not a runtime budget.

Generated-output rights follow the provider account terms; this candidate is not represented as CC0. No Tripo bridge/vendor code, credentials or signed URLs are redistributed by this document.

The retained `COMPLETION_RECEIPT.json`, `SOURCE_FACTS.json` and `CHARACTER_SOURCE_FACTS.json` bind task, source and maps. Actual GPU evidence is `character_multiview_source_review_actual_v1_001/SIX_VIEW_SOURCE_REVIEW.json`, SHA-256 `204e06c585997f58515ce0e73d09910f3784bd7b90c74c0fae4b56e865038ae7`, alongside the per-view receipts and root visual review.
