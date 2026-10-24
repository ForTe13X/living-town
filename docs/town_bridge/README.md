# Living Town: playable 3D bridge

The Blender town supplies the metric presentation for the existing Living Town simulation. `Main.tscn`, Sim and LifeMode retain resident selection, needs, jobs, permissions, social transactions and saves. Cameras and rendering do not grant actions or change simulation authority.

The compiled profile contains **151 buildings, 263 floor interiors, 1,582 room zones, 2,089 furnishing assemblies and 784 new legal fixture bindings**. It uses **11 town GLB chunks and 25 rigged character templates**. The current normal-run measurement includes **62 actual residents and 62 mesh actors**. These totals describe inventory and measured population; they do not certify every decorative object as interactive or every room as art-approved.

Five authoring/interchange/input ZIPs, the optional Blender working file and the completed 14-minute Full3 film have locally bound verification records. [Current proof index](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json) · [Asset packages and retrieval](../town_walkthrough/ASSET_RELEASE.md) · [Recorded walkthrough and chapters](../town_walkthrough/README.md). Public retrieval is a separate proof recorded in the index.

## Run

Run from the repository root in PowerShell with Godot 4.6.2:

```powershell
./tools/run-town3d.ps1
# Complete locally staged source package, no download:
./tools/run-town3d.ps1 -Local
# Explicit OpenGL fallback:
./tools/run-town3d.ps1 -Renderer Compatibility
# Original pixel map:
./tools/run-town3d.ps1 -Legacy
```

Use `-EnginePath 'C:/path/to/Godot.exe'` when needed. The desktop project and launcher select Mobile, with Compatibility fallback; `-MaxFps` defaults to 60. First import and startup remain substantial. The optional AI backend is not required: the logic backend runs without an LLM, API key or model weights.

A fresh checkout needs the **matching v2 release manifest and all 51 runtime files**. The launcher retrieves missing files and verifies every size/SHA-256. Python 3.10+ and internet access are needed for first retrieval. A complete verified local source package runs offline. The manifest URLs address the current release tag; public retrieval is recorded separately in the proof index. The launcher manages only its own missing-NobodyWho marker and preserves user-authored markers/extensions.

Restore the complete Windows ZIP from its [two parts and checksum-checked restore script](../town_walkthrough/ASSET_RELEASE.md#restore-the-complete-windows-archive), then extract it with `LivingTown.pck` beside `LivingTown.exe`; `Play_Compatibility.cmd` selects the fallback. The [editable Godot source package](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Interactive_Source.zip) needs an installed engine. The exported normal-entry/cache proof has its own exact EXE/PCK bindings in the [release evidence](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json); source launches and ZIP checks have separate scope.

Choose a resident, move with WASD/arrows or click ground, and use E near a furnishing, person or portal. Mouse wheel zooms; observer mode supports middle/right drag. In-game F5 saves and F8 loads. `--life-as ben` skips selection. Default product launch/`--town3d` use the compiled profile; test/dev arguments use the legacy profile unless explicitly selected. Legacy and 3D quicksaves have separate namespaces.

## Spatial contract

`tools/town_upgrade/compile_playable_town.py` compiles the accepted native building ledger, interior grammar and terrain into `game/data/town3d`. Outdoor cells are **1 m**, interior cells **0.25 m**. Floors have blockers, real door gaps and connected stair portals. Terrain grounds the mesh actors; ponds, building footprints and reserve landforms constrain travel. Floors remain distinct simulation planes, so social reach cannot cross unrelated walls or storeys.

Legacy functional IDs and advertisement values remain stable. Existing activity IDs and the 784 added legal fixture bindings use reachable approaches to compatible authored furnishings. Decorative assets remain presentation-only. Public/private access stays in Sim. Semantic `home2` uses the three-storey `lot_12_halftimber`; its two bed IDs bind different floors, while one-storey `Main_home2` remains a separate modeled space.

`TownWorldProfile.gd` supplies spatial data before `Sim.start_new`. `TownModel3D.gd` verifies chunk/catalog identities, loads the metric town and manages cutaways/render batches. `WorldView3D.gd` maps canonical cells to `Vector3(world_x,elevation,-world_y)` and grounds actors. `Probe3D.gd` maps screen input through the camera. Render proxies preserve authoritative source geometry and semantic addresses.

## Current performance and evidence

Room indexing and physical portal-path caching retain ordered room results, live bounds/privacy and exact-edge permission checks. Invalid or inaccessible cached paths fall back to the original BFS; derived caches do not enter saves. The paired source oracle covered **62 residents, 90 ticks, 6,392 room queries and 16,632 route queries before and after**. State, event bytes and event-chain results matched. The sum of headless `Sim.tick` time was **3.201 → 1.345 seconds across 90 ticks**, excluding oracle/hash work. This is not a Main-render or FPS result. Oracle SHA-256: `e76a3d4a198089585bda8131ac6e82b595b5d76db77de73630b9258cfbcb2c75`.

Actual ordinary Main at **1280×768, Mobile/Vulkan on AMD Radeon 8060S, 62 residents, VSync off, no FPS cap and no MovieWriter** recorded this sequential same-camera diagnostic comparison:

| View | Before mean FPS | Current mean FPS | Current p95 frame time |
| --- | ---: | ---: | ---: |
| Upper home, paused | 136.8 | 126.0 | 10.0 ms |
| Upper home, 1× | 122.7 | 120.3 | 14.0 ms |
| Upper home, 4× | 74.6 | 100.1 | 22.4 ms |
| Outdoor, paused | 33.4 | 32.1 | 40.1 ms |
| Outdoor, 1× | 29.3 | 30.1 | 42.4 ms |
| Outdoor, 4× | 11.2 | 24.2 | 77.0 ms |

Source/private-file/owned-process guards passed. Geometry and population were retained. Outdoor rendering and accelerated-simulation spikes remain limitations; these measurements are hardware/workload-specific. Current frame report SHA-256: `fda96d66e092ff3f884166bc37bf87eb614f3d66db3df5fb348b72dfdbb0fc35`. Detailed historical measurements remain in [PERFORMANCE.md](PERFORMANCE.md).

**Actual Main hits cache004**, with **2,880 groups and 19,197 source proxies**, unchanged geometry/buffer/ray validation and source-node authority. Stable asset-derived chunk names fix process-dependent registry paths. Synchronous Main setup is **66.255 s** versus **80.275 s** in the preceding miss; first completed graphical draw is **81.703 s** versus **95.601 s**. The clock starts at Main instantiate/add_child and excludes process startup, autoload parsing and editor import. Model load is **30.749 s**, cache preparation/validation **31.025 s**. Startup is still long. These source-project timings are separate from the exported-game proof in the release index.

The required Godot-only cache pair belongs in runtime/source/Windows packages. It is excluded from engine-neutral GLB/Blender archives. Resource SHA-256: `ede4da4734e95249c03f529683d1fd246861174347a126ec2dc90072650f2d19`; small manifest: `1a47f31174ccfeabdddc73e0ebddc733ed6953a22f59856825b94745b1aa5627`; cache binding: `00e711bfa5ab91b29d19b0f9119d9ae0b85711942596389a3c04bd49aa17ca53`. The normal loader still verifies current imported source and target buffers/registry. This cache does not become portable asset authority.

All eight current serialized logical groups passed: save/load, resume, migration, save budget, space, café guest access, player journey and whole-town integration. Summary SHA-256: `59ccf720531d293b479e7acb73684871c25eb6176e6e9fa3f2a4718fcdb4b602`. Accepted source status receipt: `2d8b17375be6482fe9c150a54d43fbad26eae9068e2d586b51d5bc28afa13e1a`. These are source correctness and runtime-performance results, not complete town art acceptance.

Current bindings:

| Authority | SHA-256 |
| --- | --- |
| Canonical native | `3162c204689cdb7888a5e0d21bb5dde9be04a89ac6253ba03a88d7f5ddd86274` |
| Town asset set | `d21e4f94d6d3a5c9599027e45ce919f0777a271b96bd2815c4b7856ad817a41a` |
| Stage | `14841567aa0172536446f1ac95e161b8dda3249d72a5956f83802e6711f429d0` |
| Profile | `8499a7d376739dcb759d5e404c277a707c8443230763dcfd7962fe730b1fcb4e` |
| Projection | `98146b008f130870d0067a7c1e0940f6ab373b5f255e5ba66ac24ca0ed48b3bc` |
| Characters | `00b272523dffef832a1025bba68b347d6a7917023898ba4fd6d4d20e48210970` |

The earlier 312-check default-renderer proof remains historical source evidence; the current cache/frame/regression receipts above supersede its old profile binding. A fresh Windows EXE/PCK normal-entry test, literal editor F6 test and complete visual review are distinct evidence scopes, not inferred from those older reports.

## Blender authoring and optional working scene

The separate canonical capsule contains the packed **584,661,611-byte** native (`3162…`), four coherent export inputs and 32 frozen recipe files. Its native has **137 materials, 97 used packed images and 6,739 preserved original furniture objects**; that mesh-object count differs from the 2,089 runtime furnishing assemblies. [Exact bundle hashes and source scope](../town_walkthrough/ASSET_RELEASE.md#verified-authoring-and-interchange-deliveries).

`LivingTown_Working.blend` is an optional exact copy of the actually saved/reopened Exterior005 work file. Its default `Living_Town_Summer_EXTERIOR_WORKING` excludes the 263 Scene-local interior floor paths for editing. Choose `Living_Town_Summer_WORKING_EXACT_GN` for full working interiors or `Living_Town_Summer` for the retained original full Scene. The working file is **not the export authority**; use the canonical capsule for export. Interior contents/practical lights through windows may differ in the faster exterior Scene.

Actual Blender 5.2.2 LTS/OpenGL GUI redraw at a 1572×833 editor region on the AMD 8060S recorded 10 samples per case:

| View | Canonical median redraw | Exterior005 median redraw |
| --- | ---: | ---: |
| As-opened Solid | 296.6 ms | 77.4 ms |
| Core, Solid | 413.1 ms | 107.0 ms |
| Core, Material Preview | 627.2 ms | 169.6 ms |
| Overview, Solid | 429.5 ms | 109.4 ms |
| Overview, Material Preview | 627.2 ms | 169.2 ms |

These are `wm.redraw_timer(DRAW_WIN_SWAP)` wall latencies, including operator overhead, not normal navigation FPS or GPU-only time. Viewport settings and native bytes were restored/unchanged. Build, actual GUI reopen and redraw receipts bind the working file separately. Current redraw report SHA-256: `ced8c0c3fdb604f69921a68721b4ca0f23fd414ad63329e24d8183dbf5ac70db`; scalar working-delivery summary: `3ad7cbfcc50c8bb293f2079833ae0280936f5c742d31e9df4e915a808c36a968`. The packager did not launch another engine or claim a fresh relocated reopen.

## Rebuild and evidence boundaries

For editing/export use the canonical capsule and matching frozen source files. For base whole-town generation restore the refinement input bundle using its `RESTORE_MAP.md`, baseline native and `toolbox.config.example.json`; point inputs to the extracted directories rather than unpublished ignored `build/` paths. See [toolbox](../ASSET_TOOLBOX.md) and [delivery scope](../town_walkthrough/ASSET_RELEASE.md). The input bundle supports base generation inputs and current prepared botanical/terrain work. **Exact one-command replay of every final 3162 late refinement pass remains unproven.**

Recompiling the playable profile also needs the preserved legacy profile and accepted portable upgrade metadata. Run Godot imports/rendering serially through the existing supervisor. The engine-neutral library supplies visual geometry/PBR/skins; collision, navigation, retargeting, physics, lighting and streaming still need engine-specific setup.

The completed Full3 film is **840 seconds, 18 FPS and 15,120 frames**, with 12 embedded chapters, 24 verified cached normal-rate Edge TTS takes and 95 measured subtitle cues. The actual input/action report passed 64/64; final H.264/yuv420p limited-range encoding passed 13/13. MP4 SHA-256: `9c72fa15426706d76307fd1eebaec77404de3cbabb67c80e9928d83ecbf4e252`; encoded report: `e3abee4f3dbd10deb61af89932160cc28f253235b6f348639ac16171196a7215`. The 30-second GIF at the original README path contains 120 frames at 640×384, infinite loop and no audio. The 18 FPS recording setting is not measured gameplay FPS. [Full recording and review scope](../town_walkthrough/README.md).

The coordinator and independent reviewer inspected actual encoded chapter/contact images, three caption-active frames and six sparse motion strips. The independent review binds all 12 chapter PNGs individually and 30 one-FPS samples. Caption bands are legible in the inspected frames. Known P2 limitations include dark evening/night detail, sparse upper-venue and amenity/pond dressing, a truncated internal-looking location label, and real need depletion on return/resume. These reviews do not grade complete concept fidelity, all interiors or character portraits, continuous full-film motion or gameplay balance.

Audio review is technical: the complete 840.021-second decoded PCM has RMS -20.415 dBFS and peak -1.414 dBFS with no full-scale sample. Human listening, pronunciation and perceptual-sync acceptance are not recorded. The movie includes the actual captured game bed beneath narration; no invented music/effects were added.
