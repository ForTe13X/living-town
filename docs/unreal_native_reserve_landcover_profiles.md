# Profile-bound native landcover

The Editor can apply and inspect landcover on an existing native Landscape whose actual GUIDs differ from the original Pond006 replay fixture. A versioned profile binds its Map, actor label, Landscape/edit GUIDs, material, source height/weight bytes and four LayerInfo paths. This removes the need to recompile the helper for each newly created Landscape GUID. It does not generate the town, assemble its buildings, qualify a729-instance reserve or implement runtime painting.

The capability remains bounded:505×505 vertices,16 components arranged4×4,63×2 subsections, scale100/100/25, zero rotation and four named semantic channels. The existing fixed replay methods remain explicit separate entrypoints. There is one shared painter/reader and no automatic fallback between authorities. All four runtime qualification flags remain false.

## Prepare actual identity and source data

Create the Landscape through the existing Editor/native producer and wait for `READY_NATIVE_LANDSCAPE_SOURCE_HEIGHT_COMPONENTS_AND_COLLISION`. The receipt contains the actual `guid`, `edit_layers[0].guid`, transform and source-height proof. Save the private source scene and retain its package manifest and population census. The scene host must qualify that census separately; the native landcover reader records its hash without claiming to validate population or art.

[The stdlib writer](../tools/prepare_reserve_landcover_profile.py) consumes those explicit evidence files and expected SHA256 values, checks their file custody and copies the GUIDs from the ready receipt. It has no GUID override, engine launch, asset-save or painting command. Source weights must contain505×505 interleaved uint8RGBA samples in order `Meadow`, `WoodlandLitter`, `SteepRock`, `PondSoil`, with every sample summing255. Its height source is505×505 little-endian uint16 values.

```text
python tools/prepare_reserve_landcover_profile.py --self-test
python tools/prepare_reserve_landcover_profile.py --validate profile.json
```

To produce a profile, pass `--native-read`, `--source-scene-manifest`, `--population-census` and their corresponding `--expected-…-sha256` arguments, plus `--height`, `--weights`, `--lineage`, `--layer-namespace` and `--output`. The native ready receipt must agree with the supplied height bytes. The output and adjacent provenance file must be absent. The writer prints the exact raw profile SHA for the next process.

The [JSON Schema](schemas/reserve_landcover_profile_v2.schema.json) describes its closed structural format; the writer/native parser also enforce cross-field identities and source custody. Associate the schema externally: adding a `$schema` key to runtime profile data is refused. [The example](asset_refinement/examples/reserve_landcover_profile_v2.example.json) has the same parsed fields as the qualified private profile, serialized with deterministic LF. The retained native world case used CRLF; `--line-ending crlf` reproduces those exact bytes. Formatting changes the raw SHA, so always launch with the SHA printed for the actual file. The source scene's serialized assets and harness are not included in this adoption.

The portable repository mask remains `.rgba8`; the descriptor's `native_runtime_raw` remains `.bin`. No fixture bytes or descriptor schema change accompanies this feature. For the existing fixed source, [the existing verifier](../tools/verify_reserve_landcover.py) materializes the byte-exact private native intake. A new profile may name its own contained `Content/…` source paths, whose bytes and hashes must match the staged project before starting the Editor. Merely writing a profile does not stage the scene assets or source files.

## Invoke the explicit profile authority

Place the exact raw profile at the fixed project-relative path `Config/ReserveLandcoverProfile_v2.json`. It must be ASCII UTF8 without BOM, at most64KiB, contain only the versioned fields and have the exact raw SHA supplied at launch. Duplicate JSON keys, unknown fields, malformed paths, zero/duplicate GUIDs, different source bytes and unmeasured layouts are refused. The reader recomputes authority per call; a bad profile never falls back to the fixed replay.

Both operations require:

```text
-LivingTownReserveLandcoverProfileSHA256=<raw-profile-SHA256>
```

Apply additionally requires the same SHA in `-LivingTownReserveLandcoverAuthor=<raw-profile-SHA256>`, an owned project directory ending `/Author/Project` and once-per-process authorization. A source-weight SHA cannot authorize profile paint. Flags must be unique. The profile/source files are rechecked immediately before mutation and after the operation. A failed operation retains its partial state and reports the failure; it does not silently retry or overwrite assets.

```python
import json
import unreal

applied = json.loads(unreal.LivingTownReserveLandcover.apply_reserve_landcover_profile_preview())
observed = json.loads(unreal.LivingTownReserveLandcover.read_reserve_landcover_profile_preview())
```

Apply uses actual Landscape Info indices and the full native row stride. It modifies only the four intended semantic roles, preserves every height and requires the exact stock Visibility singleton to be zero in edit/merged data and unallocated. Existing/foreign LayerInfos or source holes are refused. Four new profile-named LayerInfo packages must be absent before Apply. No native operation saves assets or the Map.

Read checks the bound terrain, every height/edit/merged weight byte, actual allocations and inherited child→combination→base compiled terrain permutations. It uses current-owner/platform/quality, map presence, game-thread semantic completeness and empty compile errors; compiler lifecycle flags remain raw diagnostics. It does not paint, submit compilation, flush, wait or save native assets. Diagnostic raster dumps use the full profile SHA below `Saved/ReserveLandcover_v002/<SHA>/`. The scene host owns any explicit one-shot compile entry, later saves and independent reopen proof.

The profile reader validates its target independently of unrelated density labels. That is not an Actual729 qualification: the only complete profile world case currently uses the accepted Actual229 scene. The fixed replay continues its original exact-Pond/229 policy, including its500-label refusal.

## Qualified result and limits

The native85 source SHA is `fe4af826a16d60948a4316ba1697eab8d0ecf7a3e7a299f004981434913fa522`; only the landcover `.h/.cpp` change from canonical `c15343…`. The actual Editor build and both `LivingTown.ReserveLandcover.ClosedSourceFixture` and `LivingTown.ReserveLandcover.ProfileBoundary` automation tests passed. Those fixture tests do **not** constitute a fixed-Pond006 world replay under the new binary; that separate legacy world case has not been rerun. Its prior c153 Author/cold evidence remains historical.

The actual profile path has a full separate-process case: a stock native creator produced Landscape GUID `6E9A54714DEC1F04C0D8339CAB9071E3` and edit GUID `E1B73144492C666337F74B9A8301B841`; Source saved136 packages, Author painted and saved140, and a new cold process reopened all140 byte exact. Existing135 packages, all229 scene instances, pond, sky and cameras remained exact. All1,020,100 weights,255,025 heights, stock Visibility, actual compiled permutations and six native Texture.Source RGB arrays passed. Five Author and five cold views have closed native pose/mip observations. [Sanitized evidence](asset_refinement/evidence/reserve_landcover_profiles_v002.json) records the scoped results.

The preserved268-node material retains12 photos/15 explicit photo samples and SharedWrap. All22 child/combination rows observed6 samplers and at most19 estimated PS texture samples; instruction budget700 remains held because ordinary MEL representatives are unavailable. Compiler estimates do not prove GPU timings or uniform gains.

Owned source/Author/cold sessions took95.625/93.391/60.094 seconds. These are complete Editor evidence runs, not game startup measurements. Private filesystem-DDC copies avoided repeated source work: verified terminal donor bytes were copied into each fresh process's private cache, with donor hashes unchanged after the child stopped. No configuration/profile/shared C cache was copied, and every source/package/compiled-resource/texture proof still ran. These warm-cache conditions differ from older uncached runs, so no causal FPS/startup comparison is claimed.

The profile case deliberately preserves the earlier006 art. Meadow repetition/tan read, stepped shoreline, rough woodland appearance and the foliage-obstructed Cliff camera remain held. Full town assembly, wider terrain capabilities, Actual729 integration, navigation, Game behavior and performance are not qualified by this adoption.
