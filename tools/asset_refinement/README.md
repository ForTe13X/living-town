# Concept-led café texture revision

The user rejected the earlier v6 finishes as too smooth. This revision replaces the prominent provisional materials with provenanced CC0 oak, plaster and terrazzo PBR maps, and an optional CC0 procedural granite. It remains a reviewable café/street texture comparison against the idealized Breton summer concept. Passing technical checks does not establish artistic acceptance or concept parity.

The authored café, framed counter, bentwood seating and geometric foliage may replace older assets where they improve the result. This pilot has not rebuilt the whole town, migrated the playable game, supplied collision/navigation, or recorded a new town walkthrough. The existing repository showcase GIF remains the previous edition.

Native Blender files and embedded GLBs are separate binary assets in the [concept refinement pilot release](https://github.com/ForTe13X/living-town/releases/tag/concept-refinement-pilot-2026-10-20). Use its member manifest and source-bound receipts to identify the delivered files. A version label or a green test alone is not asset approval.

## Texture sources and preparation

| Material | Source and physical repeat | Authored preparation |
| --- | --- | --- |
| Cabinet oak | Poly Haven `oak_veneer_01`, CC0; approximately 1.83 × 1.83 m | 2K game copies; original source maps retained. |
| Pale plaster | Poly Haven `white_plaster_02`, CC0; 1 × 1 m | Pale paint palette baked into basecolor: linear mean shifted toward sRGB `(224, 218, 204)`, retaining 0.65 of the source linear color deviation. Source normal and roughness remain independent. |
| Interior terrazzo | Poly Haven `terrazzo_tiles`, CC0; 2 × 2 m | Distinct interior-floor material; 16-bit grayscale roughness normalized to 8-bit before use. |
| Counter and cut stone, when supplied | ambientCG `Granite002A`, CC0; source classification `PBRProcedural` | The source reports no calibrated physical dimensions. Its 0.5 × 0.5 m repeat is artist-authored. Polished source roughness is adapted explicitly for the counter and architectural trim; it is not a photoscan or calibrated honed stone. |

Untouched originals, including 16-bit maps, stay in the source pack with their license/provenance records. Engine copies use 2048-square RGB8/L8 PNGs. An `I;16` roughness value is normalized by division by 257 and rounding; direct Pillow `convert("L")` would clip many values to white. Basecolor downsampling and the plaster paint bake are recorded transformations. No normal or roughness map is inferred from generated RGB.

The v9 library is `scanned_pbr_v3/library_manifest.json`. With `--hone-stone`, counter roughness is baked as `0.38 + 0.5 × source_roughness`; cut-stone roughness is separately baked as `0.72 + 0.28 × source_roughness`. The counter then uses roughness factor `0.8` and normal strength `0.35`; trim uses factor `1` and normal strength `0.25`. These are artistic finish choices. Normal maps retain their source direction/detail apart from the documented engine-format preparation.

`MetricUV` stores world metres divided by two. `hero_pbr.py` therefore uses a Mapping scale of `2 / repeat_metres`, sRGB basecolor, Non-Color roughness/normal and an OpenGL +Y tangent normal. Tint and roughness are explicit glTF-compatible factors. Optional contextual façade imagery remains unlinked until an explicit basecolor bake; a custom multi-UV shader is not silently exported as a faithful material. Repeating metric UVs are not a validated unique 0–1 atlas.

## Toolkit

| Tool | Responsibility |
| --- | --- |
| `prepare_scans.py` | Checks CC0 source records/hashes, prepares game maps, normalizes 16-bit roughness and explicitly bakes the pale plaster palette and separate stone finishes. |
| `hero_pbr.py` | Builds physical-scale scanned/procedural-source PBR materials and reports source hashes, factors and pending context bakes. |
| `hero_scene.py` | Builds the café/street exemplar, furniture and foliage; binds the PBR library, preserves physical UVs, renders presentation/detail views and exports packed native/GLB files. |
| `hero_furniture.py`, `hero_foliage.py` | Original furniture and botanical geometry. |
| `materials.py`, `hero_surfaces.py` | Reproducible provisional/fallback finishes and authored slate/context maps; these are not model-generated PBR. |
| `prepare_inputs.py`, `workflows.py` | Prepare the owned counter views and pinned MIT workflow adaptations without queuing ComfyUI. |
| `inspect_native.py` | Independently reopens the saved native source without saving it; checks named material UV bindings and floor contact. |
| `verify_outputs.py` | Checks source/file bindings, embedded geometry/resources, counter hierarchy/transforms and owned-view/workflow records. |
| `verify_scanned_exports.py` | Compares actual embedded basecolor/normal pixels and ORM green against prepared source maps; checks physical UV transforms, factors and normal/tangent coverage. |
| `godot_preview/` | Isolated runtime GLB import and framebuffer capture; does not migrate the playable town. |
| `model_benchmark.py` | Separate bounded standalone model experiment; CPU is now the default and the interrupted Vulkan setup is quarantined. |

## Reproduce the CC0 material route

Use Python with NumPy/Pillow, Blender and Godot 4.6. Restore the source texture/license pack, concept image, existing HDRI/font and their provenance from the delivery when working from a source-only checkout. The HDRI and font live under `art/living_town/external_assets/`.

Choose a fresh reproduction directory. The scene, scan preparation, owned-input and report tools reject existing destinations; keep the fallback material generator in its own fresh directory as well. Run Blender, Godot and any other substantial local job serially; the example uses six Blender threads. These commands build assets and evidence, not an AI result.

```powershell
$repo = (Get-Location).Path
$python = "python"
$blender = "D:/Program Files/Blender/blender.exe"
$godot = "C:/Users/yp/AppData/Local/Programs/Godot/4.6.2-stable/Godot_v4.6.2-stable_win64_console.exe"
$pilot = Join-Path $repo "build/concept_refinement/reproduction_20261020"
$sources = Join-Path $repo "art/living_town/refinement_pilot/cc0_sources"
$finishes = Join-Path $pilot "materials"
$surfaces = Join-Path $pilot "hero_surfaces"
$scans = Join-Path $pilot "pbr_library"
$hero = Join-Path $pilot "hero_v9"
$prepared = Join-Path $pilot "prepared_v9"
$workflows = Join-Path $pilot "workflows_v9"

& $python tools/asset_refinement/materials.py --output $finishes --size 512
& $python tools/asset_refinement/hero_surfaces.py --output $surfaces --size 1024
& $python tools/asset_refinement/prepare_scans.py `
  --sources $sources --output $scans --size 2048 `
  --floor terrazzo_tiles --stone Granite002A --paint-plaster --hone-stone
& $blender --background --threads 6 --python-exit-code 1 `
  --python tools/asset_refinement/hero_scene.py -- `
  --output $hero --materials $finishes --surfaces $surfaces `
  --pbr-library (Join-Path $scans "library_manifest.json") `
  --samples 32 --width 1800
```

The stone role requires its delivered CC0 source set; omit `--stone` and `--hone-stone` when reproducing without that optional set. Consult `library_manifest.json` for the actual material roles and authored finish changes. The provisional material inputs remain required by the builder even when the corresponding library roles replace them.

Expected native/render files include `cafe_hero.blend`, `cafe_hero.glb`, `hero_manifest.json`, `input/counter.glb`, the four cardinal counter PNGs, and `renders/01_cafe_street.png`, `02_cafe_interior.png`, `03_counter_detail.png` and `04_facade_detail.png`.

```powershell
& $blender --background --threads 6 --python-exit-code 1 `
  --python tools/asset_refinement/inspect_native.py -- `
  --hero $hero --report (Join-Path $pilot "native_reopen_v9.json")
& $python tools/asset_refinement/prepare_inputs.py `
  --hero $hero --output $prepared --workflows $workflows
& $python tools/asset_refinement/verify_outputs.py `
  --hero $hero --prepared $prepared --workflows $workflows `
  --report (Join-Path $pilot "verification_v9.json")
& $python tools/asset_refinement/verify_scanned_exports.py `
  --hero $hero --report (Join-Path $pilot "scanned_export_v9.json")
```

The owned front/left/back/right views come from one counter at a common orthographic scale. Preparation composites RGB over white, retains original alpha and builds the 4096 × 1024 sheet. Keep the relative arrangement of the prepared and workflow directories when moving them.

`verify_scanned_exports.py` compares against the **prepared** source maps, including the authored plaster palette, rather than falsely requiring those pixels to equal untouched upstream images. Its checks cover basecolor/normal RGB and the combined ORM green channel, with at most one 8-bit value of encoding tolerance. The report records the actual difference. It also checks `KHR_texture_transform`, Blender's V-flip offset, basecolor/roughness factors, normal strength and the matching texture-coordinate/tangent attributes. It does not assess style, prove current-generator freshness for a historical iteration, or substitute for a visual review.

## Isolated Godot preview and review receipts

```powershell
$preview = Join-Path $repo "tools/asset_refinement/godot_preview"
& $godot --headless --path $preview --check-only -s res://main.gd
& $godot --path $preview --resolution 1440x1000 --max-fps 30 -- `
  "--asset=$(Join-Path $hero 'cafe_hero.glb')" `
  "--capture=$(Join-Path $pilot 'godot_v9b.png')" `
  "--report=$(Join-Path $pilot 'godot_v9b.json')"
```

Capture needs a real rendering driver. The consumer records import/material checks, mesh bounds and presentation settings, then saves an actual framebuffer PNG. It has its own lighting and tone response; it does not reproduce Blender's AgX appearance. Successful import/capture needs visual inspection, and does not validate navigation, physics, gameplay or runtime performance.

The scoped revision uses these source-bound receipt paths under `art/living_town/refinement_pilot/`:

| Artifact | Evidence scope |
| --- | --- |
| `hero_v9/hero_manifest.json` | Native/GLB/render hashes, recorded source modules, component records and prepared PBR-library binding. |
| `scanned_pbr_v3/library_manifest.json` | CC0 source bindings, 2K game-copy hashes, palette/finish recipes and authored repeat scales. |
| `prepared_v9/preparation_manifest.json`, `workflows_v9/workflow_manifest.json` | Owned input identity, panel order, alpha handling and component decisions. |
| `verification_v9.json` | Current source, file, geometry and owned-input validation. |
| `native_reopen_v9.json` | Independent native readability and UV/floor checks. |
| `scanned_export_v9.json` | Actual GLB PBR pixel, scale, factor and tangent fidelity. |
| `godot_v9b.json`, `godot_v9b.png` | Isolated consumer checks and actual capture. |
| `visual_review_v9.json` | Human/agent image observations and their exact image/source bindings. |

Read each receipt's status and scope. These names identify an iteration, not a completed artistic acceptance gate.

## Model experiment and PixelArtistry layouts

The separately reviewed Apache-2.0 stack is cached locally: full source BF16 FLUX.2 Klein base 4B and Qwen3 4B weights, plus the original FLUX2 VAE, approximately 16.13 GB in total. This standalone RGB experiment does not load UltraTex's 9B adapters into a 4B backbone.

A 1024-square, 50-step Vulkan test reached the last recorded progress of **7/50**, then the host unexpectedly rebooted. It produced no usable image. The exact cause is unestablished; the log/event evidence does not prove a specific memory or driver cause. `model_slate_v1/interruption_receipt.json` records the interruption and the configuration is quarantined. CPU is now the benchmark default, but a CPU benchmark has **not** been executed. Neither successful local compatibility nor model-output quality is established. Licensing clearance and a downloaded cache are not quality evidence.

No ComfyUI or UltraTex inference was run. The MIT layout adaptations remain inspectable files:

- `multiview_owned_views.json` routes the four owned views directly and bypasses Qwen/background removal. Pixal3D still needs its exact dependency/backend review.
- `multiview_qwen_research_BLOCKED.json` retains the excluded Qwen-Image 2.1 research route.
- `ultratex_standard_9b_BLOCKED.json` retains the excluded UltraTex 9B route.

The names/metadata express project policy, not a ComfyUI security sandbox. Repeating UVs do not justify `--atlas-validated`. See the [component review](../../docs/PIXELARTISTRY_COMPONENT_REVIEW.md) and [license registry](component_licenses.json) for distinct layout, software, weight and dependency terms.

Whole-town application, complete room/service integration, playable-game migration, navigation/physics, performance evidence and a new walkthrough remain subsequent work beyond this pilot.
