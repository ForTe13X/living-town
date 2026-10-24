# Upgraded town in the real game

`compile_playable_town.py` stages the final native builder's SHA-bound chunks and
compiles the existing `Main.tscn` / `LifeMode` / authoritative `Sim` integration.
It is not the standalone territory inspection viewer.

Preserve the pre-upgrade profile before replacing `game/data/town3d`. The current
snapshot is `build/town_upgrade/legacy_profile_before_v7`; its manifest binds all
13 original files. Keep that snapshot as the explicit compiler input on repeats.

```powershell
& $python tools/town_upgrade/compile_playable_town.py `
  --upgrade-manifest "$finalNative/upgrade_manifest.json" `
  --legacy-profile build/town_upgrade/legacy_profile_before_v7
```

The native manifest supplies all151 normalized building and interior records,
with exact room/furniture identities and physical footprints, plus all chunk
paths and SHA256. Compilation preserves original resident/persona metadata,
original action values, original portal IDs/access rules, jobs and housing.
It adds selected reachable fixtures using compatible existing action definitions.
Unreachable decorative fixture candidates are disclosed; no interaction is
placed inside furniture and no corridor is carved through a wall.

Outdoor navigation is1m; interiors remain0.25m. The connected outdoor raster uses
actual core streets, graded expansion roads, reserve paths, bridge decks, stair
flights/landings and entrance terraces. Undeveloped steep forest is not a flat
walk-through plane. Natural terrain uses a4m authority sample between exact
route profiles. The whole visual terrain remains the native exported geometry.

The sealed food-truck driver's cab remains detailed nonpublic display geometry;
the source driver seat is explicitly `nonpublic`. Its prep/service compartment
has a real pedestrian entrance. The compile report distinguishes these scopes.

## Verification and recording

Run engines serially under the coordinator's supervisor. First import the game,
then run the logical arm against these exact staged bytes:

```powershell
& $godot --headless --path game --single-threaded-scene `
  res://scenes/town_upgrade_integration_test.tscn
```

The logical arm checks all151 spaces, every floor and portal endpoint, original
permissions/actions/identities, actual Sim object registration, substantial
new fixture interaction coverage and deterministic save/load continuation.
It does not claim GPU or input coverage.

```powershell
& ./tools/record-town-walkthrough.ps1 -Godot $godot `
  -OutputDir 'F:/Living Town/2026-10-20_Refined_Town/gameplay/full'
& $python tools/build_town_walkthrough.py voice --outdir $capture
& $python tools/build_town_walkthrough.py compose --outdir $capture `
  --raw "$capture/capture.avi" --report "$capture/walkthrough_report.json"
& $python tools/build_town_walkthrough.py verify --outdir $capture `
  --raw "$capture/capture.avi" --report "$capture/walkthrough_report.json"
```

The full route is 840 seconds (14 minutes), with 15120 actual recorded frames at18FPS. Godot's
MovieWriter audio mix rate is44100Hz, exactly2450samples per video frame. AVI is
required. Composition decodes and counts the raw frames and rejects a shortage;
it performs no video padding or synthetic frame reconstruction.

The route uses actual viewport clicks and keys to select Aria, take her cafe
stairs, complete core and new-venue actions, walk into the expansion and reserve,
visit the bathhouse/trailer, walk back to the core, and save/load. The resident-follow camera shows the
journeys. Architecture cuts are explicitly labelled and never relocate actors.
The preview is only a framing/startup check, not full-route gameplay proof.

EdgeTTS generates 24 independently measured paragraphs. Subtitle times come from
actual word boundaries. The original1280x768HUD is preserved with a96pixel matte
subtitle band beneath it. Inspect and listen to the final MP4 independently.

The stage and gameplay reports bind the exact chunk set, profile, character
manifest and director. A stale historical49-building report cannot certify this
upgrade. The launcher/downloader and both package tools accept the complete v2
chunk/character set while retaining the original v1 release fallback.

## Measured routing

The installed town routing index was compared against an immutable pre-change
run on 2026-10-23. Ninety seed-7 ticks took 225.994 seconds with the original
scanner and 12.235 seconds with the actual product Sim. Initial state, all 90
tick records, final state, and 4,488 ordered portal queries at both endpoints
matched. Live permissions, cache invalidation and an actual warm-cache
save/load also passed; the five derived cache fields are absent from the archive.
The strict run exited normally with stable sources. Its local report is
`F:/Living Town/2026-10-20_Refined_Town/portal_routing_product_v1.json`, SHA-256
`50ad9b522b67c33fbd8102d4560923b15f00a9a26650232c4a905a52ad874a16`.
This measures the staged V14 world on one host, and makes no GPU frame-rate
claim. The full final-asset walkthrough and regressions remain separate gates.

## Offline bootstrap and publication

```powershell
& $python tools/fetch_town_assets.py --local
& ./tools/run-town3d.ps1 -EnginePath $godot -Local
```

A complete source ZIP needs no Python or network to play. The PowerShell launcher
checks every town chunk/catalog and all25character model hashes before starting
Godot. Missing assets can be restored from another complete offline source root:

```powershell
& $python tools/fetch_town_assets.py --local --local-source $offlineSource
```

After final native and character staging, generate a NEW release configuration
and a folder of unique upload filenames. The frozen2026-10-12v1 release is kept:

```powershell
& $python tools/fetch_town_assets.py --write-release-manifest `
  game/assets/town3d/release_manifest.json --prepare-release-assets $uploadFolder
```

The configuration initially has explicit pending URLs; no download is attempted
for missing files until publication URLs are configured. When the actual public
release exists, repeat with `--release-base-url` set to its download base and
retain the same byte hashes. URL configuration itself does not prove publication.

Before source/binary packaging, copy the fresh actual recording report to
`docs/town_walkthrough/final/walkthrough_report.json` and its PNGs to
`docs/town_bridge/captures`. Inspect the images and write
`docs/town_walkthrough/final/visual_review.json` with `status=PASS`,
`walkthrough_report_sha256`, `stage_manifest_sha256` and
`characters_manifest_sha256`. No old visual report substitutes for that review.

The Windows normal-entry export report additionally binds the same
`source_asset_set_sha256`, profile/projection/stage/character hashes, and
`source_runtime_evidence.logical_report_sha256` /
`source_runtime_evidence.visual_report_sha256`. The source ZIP carries all raw
runtime chunks and models; the Windows ZIP carries their imported PCK plus
the corresponding exact metadata and evidence.

The normal exported game provides an optional view-only proof hook. Launch the
actual exported executable with `--town-runtime-proof` pointing to an absolute
JSON path. After at least six real rendered frames, it saves that report and a
matching framebuffer PNG. The existing `--shot` option can supervise a normal
shutdown. This remains the product's Main scene and resident-selection flow.

```powershell
& "$export/LivingTown.exe" -- --town3d --backend logic --town-runtime-proof `
  "$capture/windows_runtime.json" --shot "$capture/windows_exit.png"
$nativeExit = $LASTEXITCODE
& $python tools/town_upgrade/verify_windows_export.py `
  --runtime-proof "$capture/windows_runtime.json" --exit-code $nativeExit
```

The verifier checks the runtime's exact executable and separate PCK hashes,
current profile/chunks/characters, all 151 loaded buildings, actual mesh actors,
the framebuffer hash and full source-gameplay evidence. A source-engine launch
cannot certify the exported binary. Copy the native PNG to the portable capture
folder before packaging. Preserve the observed process exit code and logs.
