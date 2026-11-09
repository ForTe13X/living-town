# ContinuousCapture003 frozen source

This inactive fixture preserves the exact ten files (84,826 bytes) used by the
accepted disposable capture Editor host. It is outside the active Unreal project.
Its source-family SHA-256 is
`b1150cc9e6c1e7a9363c6052eab774e139fd59a03857fc47aa4866e35249f844`.
The local `.gitattributes` preserves all `HostProject/` bytes, including line endings.

From the repository root, verify without writing or starting any app:

```powershell
python -B tools/unreal/stage_capture_fixture.py
```

Optionally copy only the verified source to a fresh external directory. Its parent
must already exist; existing destinations, Git workspaces, installed engines,
symlinks/reparse points, traversal, and missing/extra/modified source are refused.
Partial staging failures are retained; the helper never deletes or overwrites.

```powershell
python -B tools/unreal/stage_capture_fixture.py --stage-source --artifact-root D:/Dev/LivingTownNativeRuns/CaptureArchiveFresh
python -B tools/unreal/fixtures/continuous_capture_v003/test_archive.py
```

The staged project is `<artifact-root>/project/CapturePilotHost.uproject`.
`SOURCE_MANIFEST.json` provides relative source identities. `PROVENANCE.json`
records historical evidence hashes and the complete installed-dotnet/UBT argument
array, with only engine/artifact roots templated. The accepted target was
`CapturePilotHostEditor Win64 Development`, UE 5.8.4 / CL58902052 / BuildId55116800,
MSVC14.44.35229 and Windows SDK10.0.22621.0. It used direct UBT, not stock
BuildPlugin, with a separately owned compiler/custody procedure. The helper does
not build or launch; compilation requires a fresh reviewed build action.

The plugin remains Editor/PostEngineInit and links engine modules only. It needs
the installed engine headers/libraries, including `RHISurfaceDataConversion.h`;
no proprietary engine files, DLLs, caches, generated receipts or private config
are distributed. Current repository HEAD is not the historically qualified game
build. The matching main source/game build, 6,008 assets and owned pilot/observer
staging are separate dependencies.

No C++ was changed. Runtime ownership deliberately remains fixture-specific:

- `LivingTownContinuousCapture.cpp` pins
  `D:/Dev/LivingTownNativeRuns/2026-11-04/ContinuousCapturePilot_v003`, its
  `ContinuousCapture` child, project/private User paths, `LIVE_JOB.json`,
  `LT_ENTRANCE_OUTPUT` and MCP port20351 in both numeric/string checks.
- `LivingTownCapturePilotLibrary.cpp` requires the saved
  `/Game/LivingTown_UEPilot/FullTownWorldV3_289_v001/L_FullTownWorldV3_289_v001`
  map and exact LivingTownNative controller/character/GameMode classes.
- The separate legacy direct-readback entry point pins
  `D:/Dev/LivingTownNativeRuns/2026-11-04/DirectReadbackProbe_v002/DirectReadback`.

These retained outputs cannot be reused by a new run. A new runtime location/port
or town requires a separately versioned source derivative, matching build and
actual qualification. Do not weaken ownership checks or silently patch the archive.

Root acceptance covers a 15s recording pilot: 360 actual frames from 360 scheduled
24Hz opportunities, zero drops, independently audited full pixels/PTS/timing.
The maximum observed source wall gap was76.285ms, mean writer interval26.664ms and
maximum copy-to-admission37.497ms. These are recording-pipeline observations;
game FPS, capture overhead and isolated causality were not established. The
1014x550 PF_A2B10G10R10 source is converted to8bit; HDR/10bit preservation is false.
The host's163.359s/native65.734s include other phases. Controlled exit92 reaped all
owned processes. Final art, full-town coverage and a final tour remain unqualified.
