# Read actual Unreal material-function defaults

The editor-only `ULivingTownMaterialInspection::ReadFunctionInputDefault(UObject*)` returns a bounded JSON snapshot of a real `UMaterialExpressionFunctionInput`. This closes the Python reflection gap where `Vector4f` components are inaccessible. It is a readback API for the asset pipeline; it does not change gameplay or shader settings.

```python
import json
snapshot = json.loads(
    unreal.LivingTownMaterialInspection.read_function_input_default(expression)
)
```

A successful result has status `PASS_TYPED_FUNCTION_INPUT_DEFAULT_SNAPSHOT` and contains the four typed `PreviewValue` components, use-preview-as-default flag, input name/Id/type, direct owner, and literal preview expression/output/masks. `effective_preview_stack_or_compiler_evaluated` is false: a stored preview value does not establish the effective shader input when a preview connection or callsite override exists. Combine it with actual function links, switches and texture consumers before drawing that conclusion.

The reader requires the game thread and a valid input object. It refuses non-finite values, oversized names/paths, invalid types and oversized serialization. It does not set properties, generate identifiers, save assets, request compilation or resolve effective defaults. Existing reroute and static-switch readers remain unchanged.

## Actual build and native MCP probe

The tested 58-input source digest is `f9743220693aaa04ce10486ccb015ba63dc72cbe21a4a521e57619fdc4f65ebc`. UE 5.8.4 compiled it with MSVC 14.44/SDK 22621 in **122.531 seconds**. The two canonical source files are byte-identical to the compiled files; parent copies were checked before adoption.

A separate owned hardware editor then loaded the exact saved 155 room assets and 18 material functions. Actual MCP readback returned **109 function-input snapshots** plus the existing **456-expression graph**. Transient positive/repeated reads were stable, and null, wrong-type and oversized-name controls returned the expected refusals. Non-finite, off-thread and path-limit runtime negatives were not exercised.

The native session completed in **48.594 seconds**, peaking at **4,035,588,096 aggregate private bytes**. Before/after package hashes, dirty flags and Entry-world state matched. No import, graph edit, save, material compile request or render was performed; all owned processes were reaped. The canonical bootstrap suite then passed **92 checks**, including source/build-receipt staging and replay of the actual native discovery transcript without launching an engine. Raw graph edges with inaccessible output/mask fields retain that limitation. This probe does not prove effective texture pixels, UV routing, flat-normal/anisotropy behavior, art or performance.

Retained evidence under the delivery root:

- `native_function_input_defaults_build_actual_v1_001/BUILD_RECEIPT.json`
- `native_function_input_defaults_probe_actual_v1_001/PROBE_OWNERSHIP.json`
- `Probe/TYPED_FUNCTION_INPUT_DEFAULTS.json`, `ACTUAL_LITERAL_CONSUMER_GRAPH.json` and before/after guards within that probe directory.

The [room derivative](interior_living_room_v001.md) consumes these facts for its separate material-route review. The reader itself makes no acceptance decision.

A later exact-texture export session reads the four print materials' actual root output names, tangent-space flags and default normal settings. Supported `TextureExporterPNG` exports Source mip zero, not cooked GPU data. The actual one-texel RGBA8 source is `(127,127,254,255)`, with normal compression, sRGB false and green flip false. Its linear uncompressed RG example has a 0.318-degree residual from ideal Z. Those actual source facts and the explicit cooked-data boundary are retained in `native_default_normal_export_actual_v1_001/Probe/NORMAL_SOURCE_PIXEL_ANALYSIS.json`; no general shader-pixel qualification is inferred.
