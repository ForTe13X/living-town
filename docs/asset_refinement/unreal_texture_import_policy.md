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

The adopted helper is byte-identical to the tested source, SHA-256 `162cd1ef588c914d397cda7fea92b17d2c673bae4ed099152463a32bc2771f15`. Local fixture evidence is `native_interchange_npot_smoke_actual_v1_007` under the retained delivery root.

A subsequent full definition rebuild used the patched producer and saved 1,740 packages. Native inspection covered all 93 main-source materials, 153 texture roles and 71 source images, including the four recovered non-power-of-two aliases and 38 texture transforms. Named role bindings, factory dependencies, source-image identities, dimensions and connected transform constants passed. Unconnected transform defaults are recorded as translator elisions; their effective shader evaluation remains a separate check. The 467.625-second rebuild peaked at 9,529,548,800 bytes aggregate private memory, preserved its sources and reaped all owned processes. Evidence is `town_native_npot_rebuild_actual_v1_001`.

All 1,488 render hashes and material-slot arrays match the prior definitions, while regenerated collision GUIDs and metadata require fresh typed bindings. The original geometry-basis holds remain. These results establish import and source-role coverage; art quality, scalar/function evaluation, normal orientation, pixel identity, alpha, collision, mip streaming and runtime performance still require their own checks.
