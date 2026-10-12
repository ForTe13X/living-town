# Living Town: playable 3D bridge

The delivered Blender town is the spatial presentation for the existing Living Town simulation. `Main.tscn` reuses the resident selection and LifeMode interface, jobs, needs, social transactions and save system. The 3D view never advances the clock or changes simulation authority.

Run from the repository root with PowerShell:

```powershell
./tools/run-town3d.ps1
# Or specify the installed engine:
./tools/run-town3d.ps1 -EnginePath 'C:/path/to/Godot.exe'
```

For the packaged Windows build, extract `LivingTown_Interactive_Windows.zip` and double-click `LivingTown.exe`. Keep `LivingTown.pck` beside it. This build includes the runtime and opens the 3D resident-selection screen. The separate `LivingTown_Interactive_Source.zip` contains the editable Godot project, staged model, launcher and verification evidence; it requires an installed Godot 4.6.2. The original Blender source and engine-agnostic GLBs remain in the separate completed art delivery.

Choose a resident, walk with WASD/arrows or click the ground, and use E or the interaction button near a furnishing, person or portal. Mouse wheel zooms; middle/right drag pans in observer mode. F5 saves and F8 loads. LifeMode retains the touch joystick, dialogue, autonomy, needs, wishes and relationships. `--life-as ben` skips selection. Use `-Legacy` for the original 2D layout.

The launcher handles an absent optional NobodyWho DLL by suppressing its stale import-cache entry and creating a local, launcher-owned ignore marker. If the DLL is installed later, the launcher removes its own marker and imports the extension again. User-authored ignore files and other extensions are preserved. No model download is required to play using the existing logic backend.

The default argument-free product launch and `--town3d` load the compiled town profile. Existing test/dev arguments retain the legacy profile unless `--town3d` is explicit. Legacy and 3D quicksaves use different files; authored spatial authority rejects incompatible archives.

## Spatial contract

`tools/build_town_profile.py` compiles the frozen masterplan, terrain and interior plans into `game/data/town3d`. Outdoor cells are 0.5 m and interior cells 0.25 m. Each floor has explicit wall, partition, furnishing and stair blockers, real door gaps and deterministic portals. Terrain heights ground the 3D actors; the pond and building footprints block outdoor travel. Floors retain separate simulation planes, so social reach cannot cross walls between buildings or floors.

Legacy functional object IDs and advertisement values remain stable. Their positions bind to matching model furnishings with reachable approaches. Decorative assets do not gain economic effects automatically. All existing residents and logistics affiliates keep their identities and character art. The profile records adaptations where a legacy activity lacks a dedicated mesh, and retains the existing shared functional beds.

`TownWorldProfile.gd` supplies authored spatial data before `Sim.start_new`. `TownModel3D.gd` loads the staged model and handles building cutaways. `WorldView3D.gd` projects canonical cells to meters, grounds the sprites and renders existing speech/selection feedback. `Probe3D.gd` maps screen input back through the camera. The original engine, action permissions and transaction code remain authoritative.

## Rebuild and evidence

Run `tools/stage_town_assets.py`, then `tools/build_town_profile.py` using Python 3. Staging copies the optimized GLB with SHA-256 checks; it does not modify the Blender source or the completed delivery archive. Godot imports and rendering should run serially with the included eight-worker and single-import-worker limits.

Compiler evidence is in `profile_compile_report.json` (16 checks). `logical_test_report.json` records 28 passing gameplay checks, including natural resident travel and café use, all portal/fixture reachability, private-stair denial, save/load continuation and tamper rejection. `visual_test_report.json` records 27 passing checks using actual Main/LifeMode mouse/key input and five distinct GPU captures. `actual_visual_test_review_report.json` binds an independent inspection of those captures. All 11 selected legacy regression scenes pass in `regression_test_report.json`.

The controlled resident receives a gold silhouette only when a throttled geometry ray detects an occluder; the primary body retains normal depth. Clear views hide the silhouette. Counter aliases preserve their original engine identities while sharing one physical fixture, so a click may resolve to either corresponding legal menu.

The existing isolated GLB consumer report in `art/living_town` proves asset import only; it is not evidence of gameplay integration. The new checks validate this bridge, rather than general balance, population scale or every existing backend.

The `Windows Town3D` export preset packages the imported scene and raw JSON data. Godot replaces the raw GLB with its imported scene in the PCK; the loader reports this explicitly and the export is bound by an external file-hash manifest. The editable source package retains the original GLB and checks its SHA-256 directly.

`windows_export_verification.json` binds the Windows EXE/PCK hashes and a real GPU capture from the normal product entry point. The release template refuses a command-line alternate test scene, so this is a packaged boot/render check; the 28 logical and 27 interaction checks above are evidence from the editable runtime. Package verification reports live beside each ZIP to avoid circular archive hashes. Godot redistribution notices are included in `licenses/` from the official 4.6.2-stable source.
