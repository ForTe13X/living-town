# Mill Court prototype generator

Generate two furnished houses from the engine-agnostic Mill Court floor plans. The Python geometry compiler needs only the standard library. Blender can save the procedural master, render selected views and optionally export provisional geometry.

The current model is an architectural prototype. It has real door/window openings, room partitions, stair and ceiling voids, fourteen risers/thirteen treads per house, fitted furniture, folded bedding, and procedural PBR materials. Coarser grain is now visible on floors and furniture, but remains stylized and linear. Pillows/mattresses retain a stylized shape, and exterior threshold/terrain route contacts need work. These are not final art assets.

## Compile without Blender

From the repository root, with Python 3.11 or later:

```sh
python tools/mill_court/generate.py --geometry-only --output output/mill-court-geometry
python -m unittest discover -s tools/tests -p 'test_mill_court_generator.py'
```

The output directory must be new. The generator never deletes or reuses it. `COMPILED_GEOMETRY.json` contains metre-space meshes/primitives and owner/room/asset IDs; `GENERATION.json` records the exact inputs. It is not a game-ready asset package.

The default plan is `art/planning_revision/mill_court/v1/floorplans.json`, including the coordinated 4.50 m child-partition endpoint and explicit stair/slab opening records. `--floorplans`, `--site`, `--terrain` and `--views-json` select alternate files. The bundled site has only two owner/pad bindings; the compact terrain grid contains the local study surface. No external terrain module, scene file or downloaded asset is required.

## Save and render with Blender

Use a fresh background process; existing `.blend` files are refused:

```sh
blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/mill_court/generate.py -- --output output/mill-court-master --render
```

Without `--render`, Blender saves the master without initializing a GPU render device. Rendering selects one available Cycles GPU. `--cycles-backend HIP` or another installed backend and `--cycles-device-name NAME_OR_ID` make selection explicit. It fails if no matching GPU is available; CPU rendering requires the explicit `--cpu-render` option. The currently reviewed native source used Blender 5.2.2 with HIP. Other backend options need validation on their own systems. No preference file is saved.

Four views are bundled: exterior, B ground cutaway, B ground eye-level and B bedroom eye-level. Repeat `--view VIEW_ID` to select a subset. Defaults match the reviewed source: 64 samples, 1800×1200, AgX and two render CPU threads. `--samples`, `--width`, `--height` and `--render-threads` override those settings. Cutaway visibility affects renders; the saved master retains complete shells.

Custom view IDs must be unique, including case-insensitive filesystems, and use letters, digits, underscores or hyphens. Reserved device names are refused. Invalid or empty view lists fail before creating output. The generation receipt records the exact views input and selected IDs. The Blender commands use `--python-exit-code 1` so Python failures return a nonzero process status.

Reopen the saved master in a separate fresh process:

```sh
blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/mill_court/reopen.py -- --floorplans art/planning_revision/mill_court/v1/floorplans.json --source-output output/mill-court-master --output output/mill-court-reopen
```

The reader compares actual saved geometry, UVs, transforms, material graphs and lighting; it checks real stair holes/headroom and unchanged source-file bytes/mtime. The new reader output must also be fresh. Automated shape checks do not replace visual review, capsule/nav checks or building-code assessment.

The saved output folder can be copied or moved. The reader resolves the known blend filename inside `--source-output` and checks its authored hash; the old absolute author path remains provenance only. Furniture counts are derived from the bound floorplans and compiled geometry rather than assuming the bundled 47 items.

## Export status

`--export-geometry-glb` creates `MillCourt.geometry-only.glb` using evaluated modifiers and semantic extras. It exports placeholder material groups, preserving slots, with no procedural material/texture appearance. This optional export route is source/API prepared; it requires its own native reimport validation. It is useful for geometry integration, not a finished visual delivery.

The `.blend` master uses metre-scaled procedural plaster, wood, tile and linen. Portable visual assets still need export-only unique UVs and BaseColor/Roughness/Metallic/Normal baking, padding and a matched reimport comparison. Collision, navigation, LOD/HLOD and performance budgets remain separate. See [the prototype notes](../../docs/asset_refinement/mill_court_generator.md).

The portable entrypoint has no machine-specific paths, environment token or localhost launcher dependency. Resource-bounded execution remains a separate caller responsibility; the reviewed root runner supplies owned process, memory, disk, private-config and finite-time guards. The module itself makes no performance or final-art claim.
