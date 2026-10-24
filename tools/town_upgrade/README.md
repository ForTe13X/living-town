# Whole-town refinement pipeline

This pipeline applies the staged town-generation approach to the complete
151-building town, rather than only the expansion. It preserves the authored
terrain, stable building/room/furnishing identities and existing simulation
contracts while replacing coarse vegetation, improving surface detail and
making the full territory available to the playable projection.

Each stage produces source hashes and inspectable artifacts. A native geometry
pass, an image catalogue, a gameplay recording and a visual review are separate
results. Output files are not automatically declared attractive or playable.

The territorial planner and architecture adapters are project code. The retained
Infinigen contribution is the bounded upstream planter factory described in
[the territory edition](../../docs/TERRITORY_EXPANSION.md); this does not claim
that an upstream Infinigen command generated the town or its terrain.

## Inputs and runtime

Use the packed territory-v6 input and its plans from the prior source bundle,
the prepared scanned-PBR library, Blender 5.2.2, and Python 3.12 with NumPy and
Pillow. Keep substantial Blender, Godot and video-encoding jobs serial, with
six CPU threads. There is no model-weight download or inference step.

Create fresh output directories. Do not overwrite canonical native/plan files;
some local canonical inputs may be NTFS hardlinks.

```powershell
$out = 'F:/Living Town/Refined_Build'
$blender = 'D:/Program Files/Blender/blender.exe'
$python = 'C:/path/to/python.exe'

& $python tools/town_upgrade/fetch_botanical_sources.py --output "$out/sources/botanical"
& $python tools/town_upgrade/fetch_terrain_sources.py --output "$out/sources/terrain"
& $blender --background --factory-startup --threads 6 --python-exit-code 1 `
  --python tools/town_upgrade/botanical_source_lods.py -- `
  --sources "$out/sources/botanical" --output "$out/botanical_library"
```

Inspect the actual near/far botanical renders before applying the library.
The original source meshes, photographed leaf masks, maps, licences and
size/MD5/SHA-256 receipts remain available. Adapted LODs retain shared meshes;
source species and the fictional planting-program labels are distinguished.

## Generate and inspect the whole native

```powershell
& $blender --background --factory-startup --threads 6 --python-exit-code 1 `
  --python tools/town_upgrade/build_whole_town.py -- `
  --input build/town_generation/territory_v6/scene/expanded_town.blend `
  --output "$out/native" `
  --botanical-library "$out/botanical_library/botanical_prototypes.blend" `
  --sources "$out/sources/botanical" --terrain-sources "$out/sources/terrain" `
  --texture-python $python --skip-export

& $blender --background --factory-startup --threads 6 --python-exit-code 1 `
  --python tools/town_upgrade/render_building_catalog.py -- `
  --native "$out/native/refined_whole_town.blend" `
  --buildings "$out/native/whole_town_buildings.json" `
  --output "$out/building_views" --size 640 --samples 8
& $python tools/town_upgrade/build_visual_catalog.py `
  --buildings "$out/native/whole_town_buildings.json" `
  --receipts "$out/building_views/render_receipts.json" `
  --native "$out/native/refined_whole_town.blend" --output "$out/catalog"
```

The native audit checks actual mesh apertures and solid controls, entrances,
stair flights, floor ownership, finite geometry, metric architectural UVs and
the original furniture geometry. A single-owner shared-shell ledger covers
attached buildings and measures borrowed walls through every habitable floor.
Decorations require actual supporting walls or furniture surfaces and remain
inside the existing circulation and furnishing constraints.

The complete visual catalogue expects 151 exteriors and 263 floor cuts. It
includes the exact borrowed wall components when isolating an attached house.
Its image-presence result is deliberately distinct from visual acceptance.

The portable export meshes render-visible evaluated lettering and curves in
memory, preserving their source names, materials, ownership and world transforms.
Hidden topographic review overlays remain excluded from production geometry.
The packed native keeps its editable curves. Every prepared visible sign must then
appear as a nonempty mesh with UV0 and matching text/owner extras in the actual
GLB JSON; an empty parent or missing font is rejected. Export helper source hashes
are bound separately from native generation and checked throughout export.

The terrain finish keeps the actual connected surface and protected rock UVs.
For a repeated build with identical terrain, planting guide and bake recipe,
`--terrain-atlas-cache <previous/terrain_materials>` reuses the completed maps
only after every guide, scan, recipe and PNG hash matches. A mismatch fails
before copying any map; omit the option when changing those inputs.
It bakes scanned grass, woodland litter and rock into common-UV0 diffuse,
OpenGL normal and roughness/metal maps. This avoids relying on per-texture UV
selectors ignored by the tested Godot 4.6 importer. Source maps retain their
own resolution in the source bundle; the portable 8K atlas has approximately
8–10 cm planimetric texels over the full territory. Steep surfaces can have
lower effective surface density. No new flat ground plane replaces the terrain.

## Portable export, residents and playable integration

After native and visual review, export the same saved native without rebuilding
its geometry. The exporter rejects changed native/audit/source identities and
existing partial chunks:

```powershell
& $blender --background --factory-startup --threads 6 --python-exit-code 1 `
  --python tools/town_upgrade/export_verified_town.py -- `
  --manifest "$out/native/upgrade_manifest.json"
```

Older combined meshes can contain ngons that prevent Blender from exporting
tangents for their normal maps. Export now triangulates those faces on private
shared mesh copies and checks source positions, corner UVs, material assignments,
smoothing and shaded corner normals. Blender 5.2 float-vector custom normals
retain the native vectors without the legacy short-angle encoding. Tangent
calculation must succeed before chunks are published; the saved native remains
unchanged. Read back the exported GLB payloads independently before staging.

The [asset toolbox](../../docs/ASSET_TOOLBOX.md) composes these existing tools
through JSON recipes, with frozen inputs, fresh iterations, unchanged-only
resume and explicit visual-review decisions. Its portable stage uses a verified
working copy so the reviewed native directory and pre-export manifest stay
immutable.

Build and review the resident concept first, then use the separate
[character pipeline](characters/README.md). It adapts explicitly CC0 anatomical
and tailored graphical assets through the original barycentric fitting data;
the MakeHuman application's AGPL program code is not vendored. Hero static and
motion renders precede the complete 25-model batch. Actual runtime poses still
require rendered gameplay review.

[Playable integration](PLAYABLE_INTEGRATION.md) documents compilation of all
151 buildings and floor/fixture/portal contracts, exact chunk and character
staging, logical tests, actual Main-frame evidence, the narrated AVI-to-MP4
walkthrough, offline asset recovery and normal Windows-export verification.
The engine-neutral Blender/GLB files remain separate from that Godot consumer.

Poly Haven source assets are CC0; their metadata acquisition is credited
**Powered by Poly Haven**. Exact source notices and hashes accompany the
generated artifacts. Existing project and Infinigen notices remain in force.
