# Untextured vertex color in the Unreal projection

Actual UE 5.8.4 graph readback found that the installed glTF default body's
`bHasBaseColorTexture=false` branch returns the RGB factor directly. The texture
branch multiplies by vertex color. The imported bookshelf therefore retained its
six pigment colors in RenderData but displayed white spines. Section/material
association and effective static overrides were checked before changing shaders.

`unreal/Content/Python/living_town_vertex_color_adapter.py` preserves the qualified
fixture recipe. It clones the body function, master, opaque parent instance,
pigment instance and bookshelf into `/Game/LivingTownVertexAdapter`. Only the
cloned body's false input becomes factor × vertex color. It checks every other
graph edge/function binding, material factor/override, GPU mesh array, RenderData
color and source material slot. Installed engine assets and original saved
fixtures are read only. The function is explicit; importing the module does not
apply or register it automatically. It is bound to this hero fixture and opaque
parent chain, not a universal import adapter.

The editor-only `LivingTownMaterialInspection` C++ module exposes typed readbacks
for a named-reroute declaration and a copied static-parameter set. Python cannot
directly read those protected/non-editable properties in this installation. The
helper has no setter, asset-save or permutation-update operation. The separate
`thumbnail_metadata.py` helper reads the actual native thumbnail class/properties.
Neither editor helper is included in the game target.

Evidence under `F:/Living Town/2026-10-20_Refined_Town`:

| Evidence | Scope |
| --- | --- |
| `unreal_interior_vertex_path_actual_v1_009` | Actual graph, effective overrides and all 1,380 bookshelf RenderData triangles. Zero resource/editor material-slot disagreements. |
| `unreal_vertex_adapter_actual_v1_010` | Five saved derivative assets; original twelve assets and installed dependencies remain exact. Shader/factor/array/color readback passes. Thumbnail preview backgrounds differ, so the pair is not a matched lighting comparison. |
| `unreal_vertex_fixed_scene_actual_v1_015` | Three native 1024² captures from the measured front: original, corrected, original return. Fixed unlit base-color mode; exact camera/exposure/control state. Corrected pixels change at 73,164 locations; source return is byte-identical RGBA with zero changed pixels. Root reviewed both original/corrected images. |
| `unreal_native_inspection_bootstrap_actual_v1_001` | Canonical project actually loads both exact receipt-bound DLLs, BuildId 55116800, Radeon D3D12/SM6 and 20 MCP toolsets. Owned run 16.84 s, all source/private/editor guards pass and descendants are reaped. |
| `unreal_inspection_adoption_host_tests_actual_v1_003` | 92 no-engine source/staging/actual-transcript replay checks pass, including the two-DLL runtime closure. |

The earlier fixed-scene attempts are retained. Source-derived bounds/front
selection corrects a rear-facing view; idempotent mesh setters are checked by
their actual postcondition. Native editable property access replaces Python
methods that the installed bindings do not expose.

This qualifies the opaque RGB compatibility correction. It does not accept
lighting, roughness, furniture geometry, the full room, vertex alpha, every glTF
material variant or the older source/import UV discrepancy. Source Blender/glTF
materials remain engine agnostic; this correction belongs to the Unreal adapter.
