# Fixed Pond landcover replay and diagnostics

This is an Editor-only replay tool for one qualified Pond006 scene, plus a portable four-channel weight fixture. It is **not** a generic one-shot town/Landscape producer. The current helper requires the exact map, Landscape/edit-layer GUIDs and Actual229 scene family below; it explicitly refuses the added-density500 actors. A fresh call to the existing Landscape creator generates new GUIDs, so its result does not automatically satisfy this replay contract. Runtime qualification flags remain false.

The source adoption includes the additive read-only HISM inspector, a fixed landcover Apply/Read pair and the inspection module's direct RHI dependency. The scene/material packages, photo assets and private capture harness are separate retained prerequisites, not shipped by this code/data adoption. Final art and game performance remain held.

## Portable source data

[The fixture descriptor](../unreal/Content/ReserveLandcoverSource_v001/source.json) defines the closed `LivingTown.ReserveLandcoverSource.v1` schema. The `.rgba8` source file is 1,020,100 bytes: 505×505 headerless, interleaved uint8 channels in order `Meadow`, `WoodlandLitter`, `SteepRock`, `PondSoil`. Every four-byte vertex sums to255. SHA256: `d83c74821b884ad75a80a9efa278374fcfa3674f8a8cf40c27db3bd59ba69ad9`.

Row0 is minimum UnrealY / maximum canonicalY. Columns run east. UE centimetres are X=−60000+100c, Y=−22400+100r; canonical metres are `(X/100,−Y/100,Z/100)`. Elevation uses the existing [505R16 fixture](../unreal/Content/ReserveLandscapeSource_v001/Height505.r16), SHA `2b5839619c03277cc4e73bb97e0d250661e9aec1efe5efe61850e5c16170b5cb`, and Z=4000+(u16−32768)×25/128cm. The weights are authored landcover masks, not PBR images or a claim of ecological survey accuracy. Blender or another engine may consume the same byte layout without Unreal.

Run the stdlib-only verifier from the repository root:

```text
python tools/verify_reserve_landcover.py --self-test
```

It checks every partition/hash, coordinate/schema binding and a nonidentity four-role→five-slot packing fixture with a distinct prior Visibility plane. Changed bytes (including partition-preserving edits), truncation, foreign keys, duplicate/nativeVisibility collisions and an extra native slot are refused. This CPU test is not native painting or art validation. The descriptor documents the file; the current native prototype still pins its source paths/hashes in C++.

The repository stores this project-authored raster as `.rgba8`, matching its format. The unchanged qualified native helper expects a `.bin` intake in the private replay project. Materialize that byte-exact copy before starting the Editor:

```text
python tools/verify_reserve_landcover.py --materialize-project "F:\path\to\Author\Project"
```

The explicit directory must contain one `.uproject`. The command validates the entire source before copying, refuses the tracked source project and any different existing intake, and accepts an identical existing intake. The self-test exercises the copy, idempotence and refusal cases. No model-weight or executable guard exception is added; its filename and content checks remain unchanged. The native source/build identity and qualified raster bytes are unchanged.

## Fixed native prerequisites and calls

The private scene must use `/Game/LivingTown_UEPilot/TownSlice_v003/ReserveLandscape_v001/L_ReserveLandscape_v001`, its exact standalone opaque Surface `M_ReserveLandscape_v001`, Landscape GUID `43D98B784ED85B59DCB8E8A35B77809F` and single edit-layer GUID `ACD1BFF8470AC16A8FFF82965B8FD569`. The required grid/physics is the existing16-component505 Landscape described in [the Landscape importer documentation](unreal_native_reserve_landscape.md). Four explicit native WeightBlend inputs, the six new source photos and four LayerInfo assets are authored by the separate scene pipeline.

```python
import json
import unreal

# Prepared fixed world only, Editor game thread, outside PIE:
paint = json.loads(unreal.LivingTownReserveLandcover.apply_reserve_landcover_preview())
observed = json.loads(unreal.LivingTownReserveLandcover.read_reserve_landcover_preview())
```

Apply requires `-LivingTownReserveLandcoverAuthor=d83c74821b884ad75a80a9efa278374fcfa3674f8a8cf40c27db3bd59ba69ad9`, a private project directory ending `/Author/Project`, and is allowed only once per process. It does not save assets or the map. It checks exact source height/weight bytes and maps semantic roles to actual Landscape Info indices. The exact stock Visibility singleton is a narrow exception: all edit/merged bytes must be zero **and** no Visibility allocation may exist. Existing holes/foreign layers are refused. The packer retains prior Visibility in its actual slot and writes only the four intended roles.

Read validates edit and merged weights, every source height, component allocations, inherited child→combination→fixed-base materials and actual compiled terrain IDs. The authoritative map-readiness check is current-owner/platform/quality + map-present + game-thread semantic completeness + empty compile errors; per-shader-DDC compiler lifecycle flags remain raw observations. Pending data/resources stay pending. The read never submits compilation, paints, flushes or saves; it writes bounded diagnostic byte dumps below `Saved/ReserveLandcover_v001`. The caller owns any explicit compile barrier and later asset save.

The same source adds `LivingTownReserveLandscape.read_reserve_hism_component(component)`. It snapshots native tree/build/instance/permutation/ownership fields without registration/rebuild/tick/flush/save, restricted to the exact native CDO or owned fixed-map `LT_RESERVE_DENSITY500_00`…`11` root components. That separate500-plant lineage is not integrated into the fixed229 landcover reader by this adoption.

`LivingTown.ReserveLandcover.ClosedSourceFixture` is compiled into development automation and requires both raw source fixtures. Its case checks source bytes and nonidentity Info/Visibility packing. This adoption's proof is the actual Author/cold round trip; no separate execution of that automation case is claimed.

## Observed result and limits

The85-input source SHA is `c15343b2bb4fe827b6b5526b2d90a29c48ad3e641e465f0d6ea76645b49430d7`; native build receipt SHA is `920bd51166b735fd7716ec2aecefa66d6c1571f509bb4786002913d61d9e3a07`. [Sanitized evidence](asset_refinement/evidence/reserve_landcover_v001.json) records actual Author208.078s and new-process cold159.468s,136 saved package bytes preserved on reopen, all1,020,100 weight bytes and255,025 heights exact, six exact original-decode→losslessRGB8PNG→nativeSource pixel checks, and owned process cleanup. The actual cold manifest proof is `8421c212dae950c22d148b0ddb9ff01af87844a99cbb0b2f0c79b45043ddf292`.

The retained stock graph uses one nativeRGBA one-hot weight blend shared by color/roughness/normals,12 source photos/15 sample nodes and SharedWrap. All22 child/combination observations covered six effective variants: maximum6 samplers and19 estimated PS texture samples, within14/22 ceilings. These are compiler estimates, not hardware fetch counts or GPU pass timings. Instruction budget700 remains held because ordinary MEL representative0 is unavailable. Some sparse-layer variants cost more than the previous pruned graph; no uniform gain is claimed.

Five before/after views and five cold views were captured at1014×550 with closed native pose and texture-mip observations. They do not qualify final art: meadow repetition/tan read, stepped shoreline, rough woodland materials and the foliage-obstructed Cliff camera remain held. No source photos are recolored to imply a fix. A profile-bound reusable authority, Actual729 integration, clearer cliff review, stochastic meadow treatment, full-town assembly, navigation and game performance are separate next steps.
