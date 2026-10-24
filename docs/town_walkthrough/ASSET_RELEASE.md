# Runtime assets and release downloads

Current version: [town-refinement-2026-10-23](https://github.com/ForTe13X/living-town/releases/tag/town-refinement-2026-10-23). Files below are identified by local verification records and checksums. Successful public retrieval is recorded separately in the [proof index](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json).

**Verified local deliveries: ** five authoring/interchange/input ZIPs, the optional Blender working file and the completed 14-minute Full3 movie. The new GIF is already at the original first-screen media path. URL configuration and local hashes do not themselves establish public download availability.

The v2 game uses **11 town GLB chunks**, 11 semantic/material catalogs and **25 rigged character models**, with manifests and the required Godot cache pair: **51 runtime files** in the current contract. The profile covers **151 buildings, 263 floor interiors, 1,582 room zones and 2,089 furnishing assemblies**. The ordinary measured population is **62 residents**. Large binaries remain outside normal Git history.

- [Runtime release manifest](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/release_manifest.json)
- [14-minute narrated MP4](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Walkthrough.mp4)
- [Windows EXE/PCK package: two parts and restoration](#restore-the-complete-windows-archive)
- [Editable Godot source package](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Interactive_Source.zip)
- [Current proof index and package receipts](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json)

The runtime manifest schema is `living_town.runtime_release.v2`. Each member has a repository-relative destination, exact byte count/SHA-256, unique flattened `asset_name` and published URL. It binds the stage and character manifests. The October 12 single `living_town_game.glb` (203,666,604 bytes) is historical and cannot supply this 151-building runtime.

## Verified authoring and interchange deliveries

All sizes/checksums below are **actual verified local artifacts**. Use these identities to verify downloaded files; public-retrieval results are maintained separately.

| Current artifact | Bytes | Contents |
| --- | ---: | --- |
| [LivingTown_Canonical_Capsule.zip](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Canonical_Capsule.zip) | 586,682,351 | Four current native export inputs, 32 frozen recipe files and small derivation/notice set |
| [LivingTown_Refinement_Inputs.zip](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Inputs.zip) | 879,657,487 | 116 audited base/PBR/botanical/terrain input files and restore/config instructions |
| [LivingTown_Portable_Town.zip](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Portable_Town.zip) | 1,137,030,999 | 11 accepted town GLBs, 11 exact staged semantic/material catalogs, export metadata and notices |
| [LivingTown_Characters_GLTF.zip](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Characters_GLTF.zip) | 789,993,405 | 25 accepted rigged V5 GLBs, original/portable manifests and provenance |
| [LivingTown_CharacterSources.zip](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_CharacterSources.zip) | 1,198,251,624 | 25 editable V5 natives, exact frozen recipe/vendor snapshot, registered PBR and authored texture inputs |
| [LivingTown_Working.blend](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Working.blend) | 589,394,417 | Optional faster exterior authoring Scene; full interiors remain selectable; canonical capsule remains export authority |

```text
f251d75c7010b4940281e840167181c04fa9f065ff880692b791ef8c470801b2  LivingTown_Canonical_Capsule.zip
48e7533f65e4092a2eb7fd0aab1f9180b27f437703679195bcdbfcbaf979893e  LivingTown_Refinement_Inputs.zip
78fcab022a092ebf28f15017bf380bc95dcaa9646b7a8d04618f49893e00afbd  LivingTown_Portable_Town.zip
dee17da4687b4e0eb6ef586f9a62554104e6b7ebc3a67b4b28719120d9d7eb0f  LivingTown_Characters_GLTF.zip
445fef234f2269e1f232436706ea808132fd469dd108d1e743f3cbccec749d08  LivingTown_CharacterSources.zip
6a5c11323c79862e4dc71556c9b66681700e9c596df0f2807bf06e04fa6b82c6  LivingTown_Working.blend
```

Every ZIP is under 2 GiB. The archives include the selected source/provider licenses and exact provenance. The GLB/native asset data use the selected CC0 graphical inputs; project code is MIT; the bounded Infinigen planter contribution retains BSD-3-Clause notices. The MakeHuman AGPL application and third-party model weights are not included. License/source records apply to the components described, not to every upstream dependency.

Use the proof index to compare these local verification receipt identities:

| Receipt | SHA-256 | Scope |
| --- | --- | --- |
| `delivery_input_bundle_v16_001/package_verification.json` | `b06f771caebfd1ef9354ecccc4684fe2127453f87f144d97c411d4470cf16b5f` | 116 input files; 127 ZIP members; CRC/member SHA/source preservation PASS |
| `delivery_native_capsule_v16_001/package_verification.json` | `c9dca528b4c43525e54b26075f900df270665cfd47a07e5c4d6ffe2b7c58d4b2` | Four coherent native inputs, 32 recipe files; 48 ZIP members; exact optional working copy |
| `delivery_portable_assets_v16_001/package_verification.json` | `5a7c6f1dbd2dae954fc21ba18196b48a9366378c269add788bd38983255e0890` | 46/43/329 members; 11 town GLBs, 25 resident GLBs, 25 native residents; 440 guarded files unchanged |
| `delivery_portable_assets_v16_001/post_audit.json` | `0be62be1efb876a8479cdca6f1169743ec6ffaa9ec3f9b2287306bfd2af5117f` | Independent inventories/current stage/character pins and frozen V5 digest PASS |
| `working_delivery_summary.json` | `3ad7cbfcc50c8bb293f2079833ae0280936f5c742d31e9df4e915a808c36a968` | Bound actual save, GUI reopen and redraw receipts; Scene choices and limits |

**Canonical/edit/export: ** the canonical native itself is **584,661,611 bytes**, SHA-256 `3162c204689cdb7888a5e0d21bb5dde9be04a89ac6253ba03a88d7f5ddd86274`. Its capsule contains that packed native, upgrade/building/native-audit metadata and 32 exact versioned recipe sources. The inventory includes 137 materials, 97 used packed images, 151 buildings and 263 floor interiors. It is a compact edit/re-export input capsule, not the complete historical 350-file proof directory. A fresh relocated engine export was not executed during packaging.

**Optional faster Blender work: ** open `LivingTown_Working.blend` in its default `Living_Town_Summer_EXTERIOR_WORKING` for exterior editing. The 263 interior floor paths are excluded only in this Scene; use `Living_Town_Summer_WORKING_EXACT_GN` for full interiors, or `Living_Town_Summer` for the original full Scene. Its actual saved/reopened/redraw-bound file is an editing aid, not canonical export authority. Current saved-view redraw median is 77.4 ms; core/overview Material Preview medians are 169.6/169.2 ms. These are operator wall latencies, not navigation FPS. Window-interior contents/practical lights may differ in the faster exterior Scene.

**Engine-neutral import: ** import all 11 town GLBs together at their authored transforms. Use metres, glTF 2.0 right-handed +Y up; Blender source scenes use +Z up. Buffers and images are embedded. Catalogs preserve semantic/material metadata. Native/GLB delivery does not supply universal engine collision, navigation, streaming, lighting, physics or character-controller integration. The Godot binary cache is excluded from these portable archives.

**Characters: ** 25 accepted rigged V5 GLBs include seven native clips (Idle, Walk, Sit, Lie, Work, Talk and Soak), skins, registered maps, alpha cards and corrective metadata. Their glTF frame is +Y up/-Z forward with origin at ground between feet. The separate character-source ZIP includes all 25 same-named native files, exact frozen recipe/vendor inputs and registered PBR/texture folders. Its 20 Python sources retain the original V5 digest `0c0a7fa54a350a42f6a7e77dd7f23ae76b37740a763ca598949c68be58101c02`. Historical project-path command examples remain exact; the new bundle README supplies portable invocation examples. No character rebuild, new relocated native reopen or universal retargeting/physics claim is implied by packaging.

**Generation inputs: ** extract `LivingTown_Refinement_Inputs.zip` into a chosen parent (for example `D:/AssetInputs/`) and follow its `RESTORE_MAP.md` and `toolbox.config.example.json`. Restore the baseline to `<clone>/art/living_town/living_town_complete.blend` only after its SHA matches. Configure `source_blend` as the extracted `territory/scene/expanded_town.blend`, `expansion` as `territory/`, `pbr` as `pbr/`, and the botanical/terrain paths under that same extraction root. No unpublished old `build/town_generation/territory_v6` folder is required when configured explicitly. The bundle contains all 23 directly required older local members plus 93 newer botanical/terrain/library files, with licenses, alias provenance and hashes. The base whole-town recipe is reusable; **exact one-command recreation of every late pass producing the final 3162 scene is unproven**.

The historical [October 20 territory archive](https://github.com/ForTe13X/living-town/releases/download/town-territory-2026-10-20/LivingTown_Territory_Expansion_v1.zip) remains a separate earlier edition. Its required members are already included in the new input bundle; do not substitute that old native for the current canonical 3162 capsule. Private source-path inventories, reference films and historical raw proof directories are not release payloads.

## Runtime cache and source bindings

The required runtime acceleration is Godot-specific, separate from the authoring/interchange libraries. Keep `static_render_cache.res` and `static_render_cache.json` together. The current binary is **23,405,364 bytes**, SHA-256 `ede4da4734e95249c03f529683d1fd246861174347a126ec2dc90072650f2d19`; manifest SHA-256 `1a47f31174ccfeabdddc73e0ebddc733ed6953a22f59856825b94745b1aa5627`; binding `00e711bfa5ab91b29d19b0f9119d9ae0b85711942596389a3c04bd49aa17ca53`. Actual current Main hit cache004 with all 2,880 groups/19,197 source proxies and geometry/buffer/ray checks. A missing/mismatched cache is not silently omitted from the 51-file release/source package contract.

| Authority | SHA-256 |
| --- | --- |
| Staged town | `14841567aa0172536446f1ac95e161b8dda3249d72a5956f83802e6711f429d0` |
| Town asset set | `d21e4f94d6d3a5c9599027e45ce919f0777a271b96bd2815c4b7856ad817a41a` |
| Profile | `8499a7d376739dcb759d5e404c277a707c8443230763dcfd7962fe730b1fcb4e` |
| Projection | `98146b008f130870d0067a7c1e0940f6ab373b5f255e5ba66ac24ca0ed48b3bc` |
| Character manifest | `00b272523dffef832a1025bba68b347d6a7917023898ba4fd6d4d20e48210970` |

Actual source Main performance/startup, eight logical groups and optional Blender metrics are described in [the bridge guide](../town_bridge/README.md#current-performance-and-evidence). Windows normal-entry/cache proof: **PASS: the exported Windows x86_64 executable rendered normal Main with151buildings/62mesh residents, default Mobile/Vulkan and the exact current cache HIT. All11rawGLBbyte ranges and their imported-scene remaps were independently read back from the actual PCK;20existing native verification checks passed. Full process-to-first-frame timing was not measured in this capped smoke run.**.

## Retrieve or run offline

From a fresh checkout with the matching current runtime manifest:

```powershell
py -3 tools/fetch_town_assets.py
./tools/run-town3d.ps1
```

The first retrieval needs Python 3.10+ and internet access. A complete verified source package can run offline now without consulting publication URLs:

```powershell
py -3 tools/fetch_town_assets.py --local
./tools/run-town3d.ps1 -Local
# Install missing members from a complete verified local source root/flat upload folder:
py -3 tools/fetch_town_assets.py --local-source 'D:/verified-runtime-source'
```

Downloads stream to temporary files, verify exact bytes/SHA-256, flush and install atomically. Valid existing files are preserved. Mismatched files are preserved/reported unless replacement is explicit with `--replace-mismatched`. v2 uses each manifest URL rather than the legacy GitHub CLI fallback. `--release-manifest <path>` selects an explicit matching v2 manifest. Local sources/mirrors never change pinned identities; `-Legacy` selects the pixel map.

## Manifest and recorded media identities

The matching manifest/upload inventory can be generated from the accepted source bytes:

```powershell
py -3 tools/fetch_town_assets.py `
  --write-release-manifest game/assets/town3d/release_manifest.json `
  --release-base-url 'https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23' `
  --prepare-release-assets '<fresh-upload-folder>'
```

Upload the exact flattened `asset_name` members and manifest, then independently retrieve/verify the complete set in a fresh root. `LOCAL_VERIFIED_URLS_PENDING` means local bytes only; `URLS_CONFIGURED_PUBLICATION_UNVERIFIED` means URLs are configured, not proven available. Keep that distinction until hosted retrieval passes.

The completed Full3 movie is **840 seconds, 18 FPS and 15,120 frames**, with 12 chapters, 24 verified cached Edge TTS takes and 95 WordBoundary subtitle cues. Raw input/action checks passed 64/64; final encoding verification passed 13/13. Actual input journeys and labelled camera-only inspection retain separate scope. The new GIF is **30.0 seconds, 120 frames, 640×384, 4 FPS, loop 0 (infinite)**, 14,736,629 bytes; it preserves the original game viewport while omitting the appended 96-pixel caption matte. Its decoded/palette samples were reviewed and it remains at `docs/media/town3d-walkthrough.gif`.

Final runtime manifest SHA-256: `6cd13378061d4354d0de19a5e5f6574fee5fa109efe5d3df8c3a7eaf934f7768`. Accepted MP4 SHA-256: `9c72fa15426706d76307fd1eebaec77404de3cbabb67c80e9928d83ecbf4e252`; GIF SHA-256: `b68f52e7aef6f6c39fd02247db23491142d9fdface9a06aee030951eb1c91e24`. Actual normal-entry EXE/PCK source/profile/cache/asset bindings, archive hashes, final art review and media listening/visual proof belong to [the public current proof index](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json). Publication links, a recording's fixed FPS and ZIP byte checks do not establish general gameplay framerate or complete art acceptance.

Actual sampled visual review covers12encoded chapter frames, a contact sheet, three caption-active frames and six five-frame motion strips. Known P2 observations: dark evening/night detail, sparse venue/amenity/pond dressing, a raw/truncated location identifier and depleted need gauges on return/resume. This is scoped prototype presentation evidence, not complete concept-fidelity, balance or full-motion acceptance.

Audio validation fully decoded 840.021 seconds with RMS -20.415 dBFS, peak -1.414 dBFS and no full-scale PCM sample. Human listening, pronunciation and perceptual audio-sync review are not recorded. The actual game bed is mixed under narration; no invented music/effects were added.


## Restore the complete Windows archive

The verified Windows archive exceeds GitHub's2GiB file limit. Download these
four files into one directory from the current release:

- [Part01](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Interactive_Windows.zip.part01)
- [Part02](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Interactive_Windows.zip.part02)
- [Parts/checksum manifest](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/Windows_Archive_Parts.json)
- [Restore script](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/Restore_Windows_Archive.ps1)

Run the script from that directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Restore_Windows_Archive.ps1
```

It checks both parts, reconstructs `LivingTown_Interactive_Windows.zip`, then
checks the complete archive hash. It preserves an existing mismatched archive
or partial file. Extract the restored ZIP and use `Play_Offline.cmd` or
`Play_Compatibility.cmd`. The source package is a separate complete ZIP.
Part sizes and final hashes are recorded in the parts manifest and release
proof index; split files are byte ranges of the complete verified archive.
