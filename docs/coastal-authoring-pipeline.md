# Coastal environment authoring pipeline

This is the first executable slice of the environment and coastal plans supplied on 27 September 2026. It adds a Godot-ready S1 package and an offline Blender proxy exporter without changing the live Living Town simulation or its default scene.

## Open and build the sample

Open `game/scenes/coastal_neighborhood_preview.tscn` in Godot 4.6.2 to view the authored warm-bay neighborhood. The sample is 128 × 128 cells at 48 reference pixels per cell. It shows the frozen F0 coast, the authored public road graph, all 14 building footprints and their district roof families. Press **F2** to inspect room bounds, internal portals and affordance approaches; use the mouse wheel to zoom. The bathhouse remains marked design-only until the courtyard topology/access gate is implemented.

Create a fixed-size floor-plan capture with the normal rendering backend (the headless dummy renderer cannot read viewport textures):

```powershell
& .\build\godot\Godot_v4.6.2-stable_win64.exe --path .\game --script res://scripts/CoastalPreviewCaptureCLI.gd -- .\docs\media\coastal-s1-floorplan.png
```

The capture is a 1600 × 1600 Godot viewport render with the room/slot overlay enabled. It is layout evidence only; it does not establish actor traversal or finished production art.

Current capture: [`coastal-s1-floorplan.png`](media/coastal-s1-floorplan.png).

Enable `res://addons/coastal_authoring/plugin.cfg` in **Project > Project Settings > Plugins** to add the Coastal Town Authoring dock. It validates draft building moves before changing the JSON source, records source edits through Godot Undo/Redo, and publishes only a successfully compiled package. This plug-in is opt-in and does not change the project's startup scene or simulation autoloads.

Build the distributable JSON package from the project root:

```powershell
& .\build\godot\Godot_v4.6.2-stable_win64_console.exe --headless --path .\game --script res://scripts/CoastalBuildCLI.gd
```

The compiler reads `game/coastal/warm_bay_s1/town.spec.json` and publishes `game/coastal/warm_bay_s1/export/package.json`. Pass two Godot user arguments after `--` to select another source and output path. The package stores a manifest, semantic topology and view-only render profile, each with SHA-256 digests. It is self-contained JSON and has no Blender runtime dependency.

To emit an optional Living Town `SpaceGraph` / navigation-grid overlay from that package, run:

```powershell
& .\build\godot\Godot_v4.6.2-stable_win64_console.exe --headless --path .\game --script res://scripts/CoastalSpaceOverlayExportCLI.gd
```

This writes `export/sim_adapter/spaces.overlay.json`, `interiors.overlay.json`, `affordances.overlay.json`, and `manifest.json`. The first two files use the same shapes as `data/spaces.json` and `data/interiors.json`, but remain separate overlay files: copy/merge them deliberately when integrating a town. Outdoor coast and building masks export as `wall` furniture blockers; approved crossings can pass through dune cells, while the high-water/intertidal exclusion always remains blocked. Home-room spaces carry a shared dwelling-domain ID. Private home portals use that ID as `owner_space`, matching Sim's owner check while residents start in the entry room; the affordance overlay exports both addresses for the four authored homes. Sim's home-bound needs and staff checks now read this domain while preserving the old single-space behavior when it is absent. `resident_or_staff` doors in service buildings still map to owner-only and cannot yet provide normal guests/staff with room access under Sim's current public/owner policy. The affordance overlay carries stable slot IDs, room addresses, interaction/approach cells, capacity, access and duration references, and compiled entry routes.

The overlay manifest records canonical SHA-256 hashes for all three artifacts and the source package hashes. To verify those hashes and create a detached merge preview against the current `data/spaces.json` and `data/interiors.json`, run:

```powershell
& .\build\godot\Godot_v4.6.2-stable_win64_console.exe --headless --path .\game --script res://scripts/CoastalOverlayMergeCLI.gd
```

The merged files are written to `export/sim_adapter/merged_preview/`, with a second manifest binding output hashes to the source overlay and base data. `CoastalOverlayBundleImporter.load_and_merge(...)` is the reusable API; it rejects corrupt artifacts, duplicate space/portal/affordance IDs, missing routes, and invalid combined portal graphs. It binds 22 of the 46 sample affordances to existing Sim advertisements (sleep, seat/rest, bath) by copying their current effects; queue, work, and generic activity affordances stay explicitly unbound. The checked-in `activation.example.json` assigns eight authored residents to the four home anchors and is disabled.

To opt in locally, copy `activation.example.json` to `activation.json` in this folder and set `enabled` to `true`. Sim then validates and merges the overlay during data load, checks unique assignments and the declared two-resident home limit, and updates only loaded agent definitions with the coastal entry-room address and dwelling-domain identity. Invalid activation fails closed with a `COAST_ACTIVATION` error. Keep the shipped example disabled.

The current Sim only supports `public` and `owner` portal access. Therefore authored `resident_or_staff` room doors export as owner-only, and authored homes/bathhouse entrances also export as owner-only. Staff access needs a Sim access-policy extension before it can match the source plan. With no `activation.json`, startup, live data, authored agents and replay state remain unchanged; the checked-in example is ignored by runtime.

The preview recalculates the canonical topology and render hashes before drawing. This catches incomplete or hand-edited package changes rather than presenting them as a valid export. Canonical hashing sorts object keys and rounds authored decimal values to six places so a JSON write/read round-trip preserves the digest.

## Authority and data flow

`CoastalPackageCompiler.gd` is the spatial package compiler. Its topology output owns immutable coast bands, road nodes/edges, building segment masks and entrance references. Its render output owns district palette roles and display-profile references. The preview script reads the compiled package only. It does not query camera state for semantics and has no access to `Sim`.

The beach, dune and intertidal bands are authored, interpolated integer-cell controls. In F0, they are presentation masks around frozen passability. The renderer draws a decorative foam edge inside the declared nonwalkable region. Water animation, shader state, resident simulation, tides, flooding and economic effects are not enabled by this slice.

## Blender kit export

Use `tools/blender/export_coastal_kit.py` from Blender's background CLI or Blender Python console. The source file must have an `EXPORT_2D` collection containing mesh proxies with these object custom properties:

| Property | Meaning |
| --- | --- |
| `module_id` | Stable unique module ID |
| `palette_id` | Approved palette role |
| `layer_id` | Draw layer/occlusion role |
| `license_ref` | Asset/provenance record ID |
| `module_revision` | Optional module revision, defaults to `1` |
| `draw_order` | Optional stable draw order, defaults to `0` |
| `allow_cardinal_rotation` | Optional rotation allowance, defaults to true |

Optional `SOCKETS` collection entries are empties tagged with `socket_id`, `module_id` and `socket_type`. Vertices and socket positions must lie on the 1/48-cell q grid; exported module meshes use the XY plane, unit positive scale and cardinal rotations. The tool stages and atomically replaces `coastal_modules.json` and `manifest.json`; it does not rewrite the `.blend` file. Mesh object order is normalized by stable ID. Export provenance includes the saved source `.blend` digest and Blender version.

Example:

```powershell
blender --background path\to\coastal_kit.blend --python tools\blender\export_coastal_kit.py -- --output game\coastal\kit
```

The existing Atlantic residence `.blend` is a visual authoring study, not yet a tagged `EXPORT_2D` kit. Keep its source and renders intact; add reviewed overhead proxies and provenance before invoking this exporter. 3D meshes do not become useful top-down sprites by dropping their height coordinate.

### Procedural roof kit review candidate

`tools/blender/build_coastal_topdown_kit.py` creates a new clean Blender file in an output folder; it does not open or modify the active residence scene. The authored candidate contains four overhead modules (`roof/limewash_clay`, `roof/civic_slate`, `roof/workshop_seam`, `roof/beach_canopy`) and eight entry/ridge sockets. Material custom properties carry palette roles per face into the JSON polygons, while the module's base palette remains the fallback role. Render-only copies in `PREVIEW_RENDER_ONLY` use shallow depth offsets to make the Blender review render readable; only `EXPORT_2D` is exported, and its faces remain on z=0.

The current review deliverable is `out/coastal-2d-kit-review-v3/`. Its `godot-project/` folder is a standalone Godot 4.6 project with the kit JSON, the project's hash-verifying `CoastalModuleKitImporter`, and a small preview scene for polygons, palette roles and sockets. Godot 4.6.2 rendered the scene on the GPU; the preview reports `SHA-256 VERIFIED`, 4 modules and 8 sockets. The Godot capture is `review_evidence/godot-kit-preview.png`, and the Blender render board is `authoring/coastal_kit_reference.png`; the saved `.blend` is `authoring/coastal_topdown_kit_candidate.blend`. The exported kit hash is `5ca006a1607910d522df41f7dbb874531f1f9b98fb88006c75cbc9c12cc3508c`. Its manifest intentionally remains `authoring_export_requires_art_review`; it is a candidate for independent review and development, not yet live coastal runtime art.

Build a new candidate without touching the user's open Blender scene:

```powershell
& 'D:\Program Files\Blender\blender.exe' --background --factory-startup --python tools\blender\build_coastal_topdown_kit.py -- --output out\coastal-2d-kit-review-N\authoring
& 'D:\Program Files\Blender\blender.exe' --background out\coastal-2d-kit-review-N\authoring\coastal_topdown_kit_candidate.blend --python tools\blender\export_coastal_kit.py -- --output out\coastal-2d-kit-review-N\godot-project\coastal\kit
```

Open `out/coastal-2d-kit-review-v3/godot-project/project.godot` in Godot to inspect the exported art as a standalone project. Face-level palette roles are also read by `CoastalNeighborhoodPreview.gd`, so the same kit schema can be used after review without changing the bundle format.

## Godot 3D review export

`tools/blender/export_scene_to_godot_review.py` packages the active Blender scene as a new, standalone Godot 4 project with an orbit camera. It refuses to overwrite an existing folder and does not save or rewrite the source `.blend`. Run it through the connected Blender MCP session:

```python
import runpy
module = runpy.run_path(r"D:\Documents\Dev\living-town\tools\blender\export_scene_to_godot_review.py")
result = module["export_active_scene"](r"D:\Documents\Dev\living-town\out\coastal-mansion-godot-review-v2")
```

The current candidate is `out/coastal-mansion-godot-review-v2/`. It contains a GLB with 295 mesh objects, 5,364 source polygons and 11 materials, plus `project.godot`, `Review.tscn`, and the orbit-camera script. Godot 4.6.2 imported the GLB and loaded `Review.tscn` headlessly with exit code 0. Its manifest records that the source Blender scene was dirty; the saved-file hash does not cover the exported in-memory changes. This candidate is for scene review and further editing, not a modular overhead kit or approved runtime asset.

## Current coverage and next work

Included now: versioned fixture, deterministic compiler, round-trip-verified package hashes, schema, explicit local room bounds, connected portal graphs, stable affordance/approach records and capacity/clearance checks. The S1 export currently carries 40 room records, 26 portals, and 46 one-capacity affordances, including eight sleeping slots. It also includes 46 deterministic cell routes from each building entry to its slot approach, computed with a provisional 20q actor radius and the resident/staff access profile. The package marks these as rectangular-room BFS routes; they omit furniture obstacles and are not bound to the live Sim. The standalone Godot preview can display the floor-plan overlay with F2. It also includes an opt-in authoring dock with undo/redo and atomic file replacement, the Blender JSON module/socket export contract, and a Godot importer that verifies Blender bundle provenance and hashes.

Still required before treating the neighborhood as playable or release-ready: integration and traversal capture with assigned agents, staff-aware access support, current-controller clearance calibration, full road-corridor/parcel derivation, courtyard release acceptance, native art review, texture/normal bundle import, finite shadow adapter, save migration, replay neutrality and target-device performance capture. The current preview is a presentation of authored plans; it does not spawn the eight proposed residents or connect affordances to gameplay actions. The editor dock has source-level parsing coverage but has not been exercised in a live editor session. The procedural roof kit is now present as a tagged review candidate and a standalone Godot project, but remains unapproved for runtime use. The current roof treatment is still an explicitly labeled procedural preview fallback.

PixelLab assets can be added as reviewed visual inputs after the atlas and palette contract is selected. Generated art is not embedded in topology, and no generated image is allowed to create or move a path, entrance, room or interaction slot.
