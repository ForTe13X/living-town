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
& $editor $project $mapUrl '-game' '-NoLiveCoding' '-DisablePlugins=AndroidFileServer'
```

This recipe does not execute the editor or auto-change configuration. The native GameMode creates exactly289 café components and Ben; do not add a second editor venue or preview pawn. WASD/mouse look and native lease/end/save-ledger/load-ledger controls remain real runtime code. The review shot's down12 control look was transient; ordinary launch uses the native binding spawn rotation and free mouse look, not a saved artificial pose.

The first source/build/content combination still needs a fresh owned normal-play validation before being labelled runnable delivery. Source data are preserved even when art remains provisional. This record does not relabel the café slice as the complete town or claim a packaged-game framerate.
