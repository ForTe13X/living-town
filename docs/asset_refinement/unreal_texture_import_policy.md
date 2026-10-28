# Source-sized textures in custom Unreal imports

The town's exterior definition importer constructed a fresh `InterchangeGenericAssetsPipeline`. Its texture policy rejected a valid 1536 × 1536 albedo, leaving four material aliases without their source texture. The configured glTF pipeline asset already enables non-power-of-two images; its default-stack wrapper requires no repair.

[The tested helper](../../unreal/Content/Python/livingtown_interchange_texture_policy.py) enables this setting on a caller-owned transient pipeline and checks the actual Boolean readback. It refuses a saved pipeline asset or class default. It changes no geometry, material mode, image dimensions, compression, global configuration or source files.

Call it when constructing the custom definition pipeline, retaining the existing pinned settings:

```python
from livingtown_interchange_texture_policy import enable_owned_npot_textures

pipeline = unreal.InterchangeGenericAssetsPipeline()
# Apply the definition importer's existing mesh/material settings here.
enable_owned_npot_textures(pipeline)
override = unreal.InterchangePipelineStackOverride()
override.add_pipeline(pipeline)
```

The actual exterior owner uses its existing `_set` logger through the helper's optional `set_option` callback. Its single-pipeline stack and `IMPORT_AS_MATERIALS` mode remain intact. The original frozen producer is preserved; the patched staging producer and helper were exercised together.

An actual UE 5.8.4 hardware test imported a 1536-square image shared by four source materials and a separate 1024-square control. All five real `Material` objects passed direct BaseColor-output/function-input/texture-object checks, native factory dependency and source-image UID checks, source-sized readiness, save and fresh-editor reopening. Authoring took 43.609 seconds; reload took 18.672 seconds. Both processes and their descendants were reaped, and source/configuration guards passed. The maximum aggregate private memory was 4,539,379,712 bytes.

The prior identical-source flag-disabled fixture demonstrated the expected missing texture while its power-of-two control survived. That negative used configured material instances and establishes the texture-factory mechanism; it is not a separately executed custom-material negative. Earlier failed API/default/staging assumptions remain recorded.

The adopted helper is byte-identical to the tested source, SHA-256 `162cd1ef588c914d397cda7fea92b17d2c673bae4ed099152463a32bc2771f15`. Local evidence is `native_interchange_npot_smoke_actual_v1_007` under the retained delivery root. This fixes import policy, not art quality, arbitrary material mapping, normal orientation, pixel identity, mip streaming or runtime performance. A full-town rebuild must use the patched producer and inspect its resulting materials before adoption.
