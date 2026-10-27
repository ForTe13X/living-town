# Supply the native project separately

This ZIP is a content closure, not an executable, installer for Unreal, cooked game, complete-town release or final art package. It contains the exact405 imported assets plus binding/route and one technically qualified map. No Engine binaries/source or native DLLs are inside. The source/build/Unreal installation are supplied separately. Raw receipts and editor import records can retain historical local source paths; runtime binding/route and the portable manifest require none of those paths.

Use a fresh destination with asset_delivery.py install-content. It refuses existing directories and never merges into a project. Keep INSTALL_RECEIPT.json and MANIFEST.json. The incomplete marker must be absent. Verification is byte closure only and does not qualify engine startup, cooking or gameplay on a new installation.

For normal play, create a fresh project directory containing only the matching repository LivingTown.uproject, Source and Config. Leave Content absent until the closure is installed; do not copy the repository Content/Python authoring bootstrap into this normal-play project. Verify its Source and LivingTown.uproject against Provenance/NativeBuildReceipt.json source.inputs and source.sha256; the required source digest is in MANIFEST.json. Copy Config unchanged as the baseline. Supply the two project-owned native modules and UnrealEditor.modules from the matching successful build; verify every runtime_files byte/SHA. Their paths are relative to the build receipt's directory. Do not copy Engine files into the project/package.

The provided Unreal installation must match required_engine_version and build ID in MANIFEST.json, currently UE5.8.4 CL58902052 /BuildId55116800. Verify the build receipt's engine.files relative to the user-provided engine root before using its prebuilt DLLs. A different engine/build needs a new source build and qualification; changing a drive path alone does not change identity.

Copy this verified closure's Content directory only into that freshly staged project, and only if the project's Content directory does not exist. Also copy the exact frozen Source/LivingTownNative/ThirdParty/PILOT_CASES.json and PilotWorldBinding.json into Content/LivingTown. They belong to the native source snapshot and are required by the unchanged lease kernel; they are not extra imported assets and are intentionally not duplicated in this asset ZIP.

The matching Config defaults keep Entry/global café activation inactive. In this fresh project only, append one /Script/Engine.RendererSettings section using MANIFEST.json renderer_project_defaults, after confirming the source DefaultEngine.ini has no existing such section. This deliberately creates a local renderer-config derivative; record its before/after hashes. Never change the installed editor/user/global INIs. Manual exposure, sun and native GameMode are already per-map; record the selected map and these renderer requirements. Keep actual map/frame qualifications and art-pending labels.

Select the native map explicitly; no MCP server, Python automation or bridge is needed in normal play. Example variables below are supplied locally by the user, not embedded dependencies:

```powershell
param([string]$EngineRoot, [string]$ProjectRoot, [string]$ClosureRoot)
$manifest = Get-Content -LiteralPath (Join-Path $ClosureRoot 'MANIFEST.json') -Raw | ConvertFrom-Json
$editor = Join-Path $EngineRoot 'Engine/Binaries/Win64/UnrealEditor.exe'
$project = Join-Path $ProjectRoot 'LivingTown.uproject'
if (!(Test-Path -LiteralPath $editor -PathType Leaf) -or !(Test-Path -LiteralPath $project -PathType Leaf)) { throw 'Supply the qualified UE installation and matching fresh native project.' }
$mapUrl = $manifest.map + '?game=/Script/LivingTownNative.LivingTownCafeGameMode'
& $editor $project $mapUrl '-game' '-NoLiveCoding' `
  '-DisablePlugins=AndroidFileServer,ModelContextProtocol,EditorToolset,ToolsetRegistry' `
  '-DisablePython' '-notraceserver' '-ini:Engine:[ConsoleVariables]:TEDS.Enable=0'
```

This recipe does not execute the editor or auto-change configuration. The native GameMode creates exactly289 café components and Ben; do not add a second editor venue or preview pawn. WASD/mouse look and native lease/end/save-ledger/load-ledger controls remain real runtime code. The review shot's down12 control look was transient; ordinary launch uses the native binding spawn rotation and free mouse look, not a saved artificial pose.

These process-local controls avoid installed editor-authoring startup in uncooked game mode. The installed Python plugin otherwise scans mounted editor-tool content whose reflected classes are unavailable in game mode; TEDS otherwise starts without its editor-only UI purposes. The controls disable those flows, retain the project's renderer settings, and leave the installed engine and global configuration unchanged. They are part of the qualified local launch recipe, not a change to the source project's editor authoring setup.

The current combination is verified on this host: source digest 714bf85459d1667641fa82253056d7ada09407528ed7202c4be50d71335b8a94, native build receipt 9118799315478865ea6d9d406431133632d290eabd7f160b4ab59ffc22efe54f and content ZIP 6e25d7cb801a0f409a1170a782a528fbf79ddd2420d734af3df9ed123be4af64. Fresh normal-game actual003 reaches the native GameMode, all 289 venue parts and prepared physical scene, shows the actual HUD/player PNG on Radeon 8060S D3D12/SM6, logs zero warnings/errors/MCP activity and exits through the bounded seconds path. All owned processes are reaped. This qualifies initial uncooked loading on this host; material residency, walking performance, cooking and other installations remain separate checks.

The original actual003 supervisor report remains FAIL because it incorrectly required one persistent crash-monitor analytics file; that run leaves zero new persistent profile files. Corrected observer replay002 independently passes 13 guards and preserves the original failed report bytes. It verifies the saved runtime observations, actual owned monitor identity/session, exact global INI census and six independently demonstrated background-writer paths, removing no profile path. It claims neither unavailable monitor-store counters/MD5 nor natural monitor exit. The corrected observer passes 33 CPU fixtures and launches no new engine. Evidence: native_cafe_normal_game_actual_v1_003 and native_cafe_normal_game_observer_replay_actual_v1_002/OBSERVER_REPLAY_QUALIFICATION.json under F:/Living Town/2026-10-20_Refined_Town; replay receipt SHA379f7ae80e5708b46ab794f2d34d812d7b956cc7e579122bc53e1df1d47e7ffa.

Source data are preserved while art remains provisional. This is a runnable local café foundation, not the complete town or a packaged-game framerate result.
