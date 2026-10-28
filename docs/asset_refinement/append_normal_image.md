# Append a portable normal image without re-exporting geometry

`tools/asset_refinement/append_normal_image.py` appends a reviewed normal PNG to an embedded GLB and binds the selected material to it. It uses Python's standard library. It does not invoke Unreal or Blender, bake, resample, normalize, flip green, re-export geometry, or add an extension. Supply an already registered, convention-correct linear normal image and caller evidence for its provenance, calibration and visual review.

```powershell
python -B tools/asset_refinement/append_normal_image.py `
  --source-glb SOURCE.glb --normal-png REVIEWED_NORMAL.png --output-glb NEW_DERIVATIVE.glb `
  --expected-source-sha256 SOURCE_SHA256 --expected-png-sha256 PNG_SHA256 `
  --dimensions 4096 4096 --sampler-json '{"minFilter":9987,"magFilter":9729}'
```

Both input hashes, dimensions and the core glTF sampler object are mandatory. Filters are not inferred from filenames or the old normal. `--material-index` defaults to 0. The existing normal binding must use UV0, strength 1 and an absent or identity `KHR_texture_transform`. Its original normal image must be an embedded JPEG/PNG with no other material texture consumer. Source texture extensions are outside this operation. The output binding is explicit `{index: NEW_TEXTURE, texCoord: 0, scale: 1}`. The original normal image, texture descriptor and bytes remain present; the old image no longer has a material texture consumer. This is a statement about the checked JSON texture bindings, not arbitrary custom shader behavior.

The writer appends one bufferView, one image and one texture. It reuses a sampler only when its JSON object equals the caller's sampler exactly; otherwise it appends one. Only these additions, `buffers[0].byteLength` and the chosen `normalTexture` may change. All original BIN bytes, including GLB padding, remain an exact prefix. Every old accessor, view, node, hierarchy, skin, clip, image and other material property remains unchanged. `--image-name` is optional metadata; it is not derived from a personal path or trial identifier.

`verify_normal_append(...)`, also available with `--verify-only`, freshly reads the delivered file. It checks the PNG bytes at their exact new offset, sampler and binding, complete old BIN prefix, alignment/padding and complete original JSON after reversing only the declared additions. An altered skin, animation channel, position byte, UV accessor, other map, image offset or unexpected extension is refused. This does not perform glTF-wide schema or artistic validation; the input asset requires its own inspector.

The PNG check validates signature, dimensions, chunk types/order/CRCs, the entire bounded zlib stream, decoded scanline count and legal row filters. This bounded version accepts noninterlaced 8-bit RGB/RGBA PNG, at most 8192 per dimension. It does not decide normal convention, linear sampling, vector quality, alpha meaning, UV registration or gamma metadata semantics. Original source GLB is limited to 256 MiB, PNG to 128 MiB and JSON to 8 MiB, with one JSON chunk and one embedded BIN chunk. External buffers and malformed, duplicate or non-finite JSON are refused.

The output must be new and its parent must exist. Input alias paths, existing outputs and output-creation races are refused using exclusive creation. Inputs are checked by SHA-256, size and mtime before creation and again after fresh readback. Validation failures create no output. A later write/readback failure can leave a new partial artifact; retain it for diagnosis instead of overwriting it.

## Actual reproduction and its limits

The extracted writer reproduced the accepted portable Face plus central-neck derivative **byte for byte**: 27,447,988 bytes, SHA-256 `df5a226c7491898a4674f7d36322a709c431b19e813fb16d7543f7caee22001d`. Inputs were the idle/walk bundle `aafd74a3a713c997b20a3d054e4950c04ab2b7eeca3a05316640fc187d98375f` and native-exported PNG `d8cb1975254b199064e362a785d5e8a35b395cb3a8abd52937f05357ccfa039c`. Sampler `{minFilter:9987, magFilter:9729}` reused the original sampler. Caller-supplied image name `FaceNormal_NativeExport_Linear8bit_v001` retained the already reviewed serialization exactly. All 377 old bufferViews, 374 accessors and the 7,592,052-byte BIN prefix remain unchanged, including the skin and both clips. Input and accepted artifact size/mtime/hash remained unchanged during reproduction.

The upstream exporter calibration measured maximum angular error 0.393167 degrees and maximum decoded unit-length error 0.005536; wrong-green and vertical-flip controls failed distinctly. That evidence belongs to the upstream native export adapter, not this writer. The 4K normal is a new resampled 8-bit lineage. Original-normal samples outside confidence are not byte-exact in this baked map.

The matched portable rest views show smoother facial and central-neck shading with consistent hair, collar, shirt and apron. See [original](evidence/cafe_worker_v002_portable_normal_original_v002.png) and [refined](evidence/cafe_worker_v002_portable_normal_refined_v002.png). Acceptance is limited to this rest view and surface change. Side-neck, under-ear, hair protrusions, eye anatomy, deformation, physical contact, final art, runtime replacement and performance remain open. Consumer tangent reconstruction, compression and mip sampling are separate boundaries.

## Host controls

```powershell
python -B tools/tests/test_asset_refinement_append_normal_image.py -v
```

The 13 standard-library test groups use a tiny embedded fixture with geometry, skin and two clips. They cover prefix/full-JSON/input preservation; sampler reuse/append; RGB/RGBA data; input/output aliases, existing output and a competing writer; changed input/hash/dimensions; PNG CRC, compressed stream, scanline filter and truncation errors; malformed GLB extents, external buffers and non-finite/duplicate JSON; normal UV/strength/transform/alias errors; invalid sampler policy; and fresh-file tampering with geometry, skin, clips, other material properties, PNG bytes, texture sources, offsets, bindings and extensions. No external asset, engine, network or GPU is required. Actual asset bytes and reproduction receipts remain external evidence, not repository test fixtures.
