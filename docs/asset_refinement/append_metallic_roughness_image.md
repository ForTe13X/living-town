# Append a portable metallic-roughness image without re-exporting geometry

`tools/asset_refinement/append_metallic_roughness_image.py` replaces one existing embedded metallic-roughness image reference by appending an 8-bit RGB/RGBA PNG to the original GLB BIN. It does not bake, paint, resample, remesh or invoke Blender. Supply an already reviewed, UV-registered data PNG.

```powershell
python -B tools/asset_refinement/append_metallic_roughness_image.py `
  --source-glb SOURCE.glb --orm-png REVIEWED_ORM.png --output-glb NEW_DERIVATIVE.glb `
  --expected-source-sha256 SOURCE_SHA256 --expected-png-sha256 PNG_SHA256
```

The source and PNG hashes are mandatory. The output must be new and its parent must already exist. `--material-index` defaults to 0; its material must have an existing metallic-roughness texture and embedded JPEG/PNG image. Shared image consumers are refused because repointing an image would also affect those consumers.

The entire original BIN chunk remains byte-for-byte at the beginning of the new BIN. JSON changes are limited to one appended bufferView, the selected image's bufferView/mimeType, and the buffer byteLength. Accessor/index/UV/normal data, node transforms, scenes, materials/factors and sampler settings remain unchanged. Construction and compact JSON serialization match the tested v002 native-bake worker exactly. The container checks refuse external buffers, malformed extents/chunks, duplicate/non-finite JSON, target aliases and invalid PNG header/chunk CRC structure. PNG pixel decoding, color-space semantics, mask boundaries, UV registration and material quality require their own source inspector/review; this helper does not qualify them.

Existing output and input-alias paths are refused; exclusive creation also protects against a racing output owner. Failed validation creates no output. Original inputs are read-only and checked by size, mtime and expected hash before output creation. A write failure can leave a partial new file, which the caller should retain and inspect rather than overwrite. The helper is bounded to one embedded GLB2 buffer, source 256 MiB, PNG 128 MiB and JSON 8 MiB; it is not a general glTF converter.

## Actual source reproduction

The final helper was independently run on the actual cafe-worker v002 source (`dcbec3404706965bb8924c489f48466394b31daefb59b363906317427441609e`) and native-baked ORM (`253cc8337c3cea6df9e93c4fef355c16cd298edd385a8e630f224fa098968047`). Its output is **fully byte-identical**, not merely structurally similar, to the 53.188 s HIP comparison's portable GLB:

- **74,850,764 bytes**, SHA-256 `f6f5cc4e1df6ba12c4792a81cbb8183f7d85977becce91eda077a107a316e235`.
- Original BIN prefix 64,554,204 bytes, SHA-256 `185c25743eb1c5ed8bd5c0a127972b3fad61ef0181c7ac3d5705fdce3a4f34ec`.
- Original source, ORM PNG and actual native artifact all retained unchanged by size/mtime/hash.

The lower-orbital PBR correction was provisionally selected after a matched Face review. Whole-face anatomy, forearm grooves, hair, runtime topology, rigging, animation, engine/performance and physical-scale acceptance remain separate. Reproducing the container does not add any artistic qualification.

`tools/tests/test_asset_refinement_append_metallic_roughness_image.py` has eight CPU control groups. They assert exact old BIN and unrelated JSON preservation, original input preservation, malformed-container refusals, source-hash refusal, cross-role image-alias refusal, existing/input-alias refusal and a simulated output-creation race. No network or engine is used. The retained F-only packet includes final actual-reproduction and test receipts; external asset bytes are not repository fixtures.
