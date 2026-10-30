# ConnectorA height source foundation

ConnectorA can now import and read its own fixed height source through the existing native Landscape pipeline. The previous fixed reserve API still uses its original config, map, heightfield and material. The shared parser, stock importer and full height reader are reused; this adds a separate explicit context rather than a second generator.

Only `LivingTownReserveLandscape.cpp/.h` change in the qualified 87-input native source family (`0f34c44c…` → `ae761f4c…`). The other 85 native inputs, including the landcover-v2 implementation, connector collision helper and renderer/HISM observers, are unchanged. The committed source evidence records that exact qualified build family; the portable verifier checks the two changed implementation files and unchanged landcover implementation/header. It does not require unrelated future source work to retain that historical whole-project digest.

## Fixed source and native API

| Input | Identity |
|---|---|
|Legacy config|`Config/ReserveLandscape_v001.json`, SHA256 `7dfec815…`|
|Legacy RAW|`Content/ReserveLandscapeSource_v001/Height505.r16`, SHA256 `2b583961…`|
|ConnectorA config|`Config/ReserveLandscapeConnectorA_v001.json`, 789 B, SHA256 `d5848a11…`|
|ConnectorA RAW|`Content/ReserveConnectorA_v001/Height505_connectorA_v001.r16`, 510,050 B, SHA256 `9184ca30…`|

Both use 505 × 505 little-endian uint16 samples, origin `[-60000,-22400,4000]`cm, scale `[100,100,25]`, and 16 components of 126 quads. Row 0 is minimum UE Y; canonical metres are `(UE_X/100,-UE_Y/100,UE_Z/100)`. The new source differs at exactly 59 samples; 254,966 remain byte-exact. Maximum source cut is 0.85546875 m and fill 0.068359375 m. All four height samples supporting each of the six original bridge-bank anchors remain unchanged, preserving both their bilinear and fixed native-triangle source heights. This is a source constraint, not a bridge-walking proof.

New zero-argument methods:

- C++ `CreateReserveConnectorLandscapePreview` / `ReadReserveConnectorLandscapePreview`.
- Python `create_reserve_connector_landscape_preview` / `read_reserve_connector_landscape_preview` on `unreal.LivingTownReserveLandscape`.

Both require this exact caller flag:

```text
-LivingTownReserveConnectorConfigSHA256=d5848a113e7917516562079eb8f1ca81c6ad22de0dcfb4e2073fd5b8ac125d39
```

Creation additionally requires `-LivingTownReserveConnectorAuthor=<same config SHA>`, once in an owned `/Author/Project`; reading is restricted to owned Author/Review projects. The RAW digest is data, **not** the Author token. Duplicate/malformed intent flags, wrong contexts, source tampering and a second creation are refused. The native code does not rewrite command-line flags, supply a Landscape GUID, fall back to the legacy source, delete actors or save assets. Stock Import generates the actual new GUID; an external owned authoring harness controls staging and saves.

The existing `CreateReserveLandscapePreview` / `ReadReserveLandscapePreview` wrappers and landcover-v2 interface remain unchanged. The exact legacy config/RAW are still present. The existing landcover `.rgba8` descriptor/materializer is unchanged; this addition does not track a new native weight `.bin` alias.

## Recorded native qualification

[Compact machine-readable evidence](evidence/reserve_connector_a_height_context_v001.json) binds the complete retained proofs by byte count/SHA256, without shipping Editor projects, `.uasset` files, caches, binaries or runtime archives.

- The 87-input native build passed in 227.656 s (`f9ea59a0…`).
- All three actual native tests passed (`39e22471…`): `LivingTown.ReserveLandcover.ClosedSourceFixture`, `LivingTown.ReserveLandcover.ProfileBoundary`, `LivingTown.ReserveLandscape.SourceContextBoundary`. The new context case includes 34 assertions; all three had zero error events.
- Actual legacy2b create/read world replay passed (`7142fa69…`, independent audit `a2d7cf03…`), using the old API/config/map/RAW, all 255,025 merged samples exact, and 135 unrelated packages preserved.
- New9184 source Author and separate read-only Cold passed. Saved 137-package manifest `21de9105…`, cold proof `a25ef68f…`, independent Author/Cold audits `cd52cb82…` / `a91f385f…`. All 255,025 source/merged height samples match the revised RAW; 16 native component/collision states were read back, 136 original packages and 229 intrinsic instance values were preserved, 171 original pond contacts and the six shader sources were retained. Author/Cold reused the actual saved Landscape/edit GUIDs, with all 137 saved package bytes exact across reopening.

These are source-foundation results. They do **not** accept profile paint, complete exit/landing grade, rail collision, town-pad integration, full world traversal, native Game behavior, final art or FPS. No completed route or visual town improvement follows from this fixture alone.

## Portable verification

From the repository, using ordinary Python3 with no third-party packages:

```text
python -B tools/verify_reserve_connector_height.py --self-test
```

It checks exact config/RAW/source hashes, the fixed 15-key contexts, all 59 declared deltas, 254,966 unchanged samples, six original anchor stencils, shared parser/import/read shape, unchanged legacy wrappers/landcover source, qualified historical source digests and strict scope holds. Negative controls cover truncated/tampered/swapped heightfields, foreign config identity/transform/path, false derivative data, changed anchor samples, foreign source metadata and false world/art acceptance. No files are written and Unreal is never launched.

`--recorded-evidence-root <retained-artifact-root>` additionally verifies the full 17 retained actual proof/native/merged-RAW artifacts. `--qualified-source-root <root-containing-unreal>` verifies all 87 files of the recorded qualified source copy. These optional local roots are not needed for portable fixture checks; absence of retained artifacts does not represent a new native run. `--base-root` is a read-only fallback for reviewing an unapplied source draft; normal repository verification uses no fallback.
