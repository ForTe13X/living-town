# Encoded confidence normal material

[encoded_normal_material.py](../../tools/unreal/encoded_normal_material.py) is the reusable Unreal Editor portion of the café-worker normal refinement. It duplicates an explicitly supplied material and adds a Normal graph using original encoded RGB, a new bake and a confidence mask. It leaves source assets untouched and does not save packages, assign actors or enable runtime systems.

The helper was actually called in `native_character_neck_material_actual_v1_001`, with exact SHA-256 `2b6c9550032037c96f3526bc3c0cb161b02110fd996ce18b94c3ec3d5b2c37cd`. Native authoring and independent reopening pass graph, texture-policy and original-package guards. That run's first visual pair remains held because the baseline is blurred across unchanged hair and shirt. A later review of the same saved materials, `native_character_neck_material_review_actual_v1_002`, passes three stable frames at each baseline/candidate/baseline-return stage. Root selects only the central neck improvement under its scoped diagnostic AA requests; final renderer AA, final art and gameplay remain separate.

Run this inside the tested UE 5.8 editor environment. The caller supplies owned textures, input provenance and a fresh `/Game/` destination:

```python
import encoded_normal_material as normals

textures = {
    "original": encoded_original_texture,
    "baked": baked_normal_texture,
    "confidence": confidence_texture,
}
for role, texture in textures.items():
    normals.configure_encoded_texture(texture, role)

material, readback = normals.create_confidence_material(
    source_material,
    "/Game/LivingTown/Derived/M_ConfidenceNormal",
    textures,
)
```

Only pass texture copies or newly imported data to `configure_encoded_texture`: it modifies the provided object. Original and baked RGB use linear data policies, confidence uses linear grayscale, and all green-flip settings are off. The shader performs the glTF-to-Unreal Y conversion once after mixing encoded RGB and decoding. Existing native BC5 sampling is a different baseline; its reconstructed blue channel is intentionally avoided.

The supported source contract is the tested connected glTF shared-body material, UV0, unit normal strength and no normal UV transform. The original connected PBR nodes must remain reachable unchanged. The helper refuses missing connections, incompatible texture settings, an existing destination or shader errors. It returns the new object and graph readback; it creates no files directly and contains no project-specific paths or trial IDs.

The caller owns source/package preservation checks, source-specific projection confidence, actual texture readiness, camera and pose stability, save/reopen validation and visual review. A zero-confidence pixel samples the original encoded map in this new shader; this does not promise equality with another engine's compressed normal path. A separate built-in native bake now carries the reviewed face/central-neck result through core glTF, with explicit resampling/precision limits and matched portable reimport. It does not change this helper or establish general cross-engine equality. See the [actual character evidence](character_cafe_worker_multiview_v002.md).
