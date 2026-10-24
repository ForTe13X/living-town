# Refined town asset sources

These records accompany the native town, portable glTF assets and playable
packages. They describe the actual selected assets, rather than licensing every
component of an upstream project under a single label.

Powered by [Poly Haven](https://polyhaven.com).

- Botanical meshes and photographed bark/leaf/grass/fern/flower maps are from
  Poly Haven: `island_tree_02`, `tree_small_02`, `pine_sapling_medium`, `fern_02`,
  `celandine_01`, `grass_medium_01`, plus selected `pine_tree_01` maps. The assets
  are CC0-1.0; see [the asset license](https://polyhaven.com/license), the included
  `CC0_1.0.txt` and `REFINED_BOTANICAL_SOURCES.json` for exact source URLs and
  downloaded hashes. Source tree meshes are adapted into shared near/far LODs;
  photographed alpha masks remain part of the leaf materials. Fictional planting
  labels in the town do not identify the biological species of a source model.
- Ground photographs are Poly Haven `leafy_grass`, `forest_leaves_02` and
  `aerial_grass_rock`, CC0-1.0. `REFINED_TERRAIN_SOURCES.json` binds the originals.
  The common-UV0 terrain atlas blends and grades those sources; the summer grass
  tint and anti-tiling recipe are artistic adaptations. Its planimetric texture
  density is approximately 8–10 cm per texel, and does not retain every detail
  of the original 2K scans over the entire territory.
- Building/interior scans use Poly Haven `white_plaster_02`, `oak_veneer_01`
  and `terrazzo_tiles`, and ambientCG `Granite002A`, all CC0-1.0. Their ordinary
  PBR maps, physical repeats and authored finish adjustments are documented in
  `REFINED_PBR_SOURCES.json`. See [ambientCG's license](https://docs.ambientcg.com/license/).
- Character anatomical data, macro targets, rig weights and selected authored
  system garments, footwear, skin, hair, eyes, brows and lashes are MakeHuman
  Community CC0 assets. The [official system asset table](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)
  lists the selected system assets as CC0. Exact downloaded members and hashes
  are in `REFINED_CHARACTER_SOURCES.json`; anatomical provenance and licenses
  accompany `tools/town_upgrade/characters/vendor/makehuman`. The project adds
  fitting, palette derivatives, aprons, accessories, skinning and animation.
  The MakeHuman application is not included.
- Apron fabric uses Poly Haven `rough_linen`, photographed by colormass and
  processed by Rico Cilliers, CC0-1.0. `REFINED_LINEN_SOURCES.json` records the
  actual diffuse/OpenGL-normal/ARM files and their hashes. The original blue
  fabric is palette-adapted for the town; its approximately 27.07 x 27.13 cm
  source repeat supplies metric cloth UVs rather than garment-pattern tiling.
- The retained Infinigen contribution is a bounded planter factory from the
  pinned upstream source, with its BSD-3-Clause notices in
  `INFINIGEN_NOTICES.txt`. The town planner, terrain and complete architecture
  are project generators. This does not describe the complete Infinigen
  dependency tree as CC0.

The character concept was generated with the built-in image generation tool
before the character rebuild. Concept imagery is separate from actual model
renders and gameplay footage. No PixelArtistry/ComfyUI model weights or inference
output are included in this refinement pass; its source-map preparation,
ordinary PBR material and export-verification route uses the repository's
dedicated asset refinement pipeline.
