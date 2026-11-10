# Research scope for texture and character workflows

The offline customizer can record the project's declared noncommercial research purpose without treating the selected noncommercial model terms as an automatic rejection. This declaration remains separate from backend qualification, execution, output review and redistribution. The command prepares source-bound workflow layouts; it does not install nodes, download models, queue ComfyUI or generate assets.

```powershell
python -m tools.asset_refinement.workflows `
  --mesh <owned-mesh.glb> --reference <front.png> --sheet <turnaround_sheet.png> `
  --output <fresh-review-directory> --usage-purpose noncommercial-research
```

The prepared input directory must also contain the owned `front`, `left`, `back` and `right` RGBA views expected by the existing adapter. Add `--atlas-validated` only after a separate audit accepts the exact input mesh's unique, nonoverlapping 0–1 atlas. A research declaration does not validate UVs or preserve a rig through remeshing.

Omitting the new option retains the existing unspecified-purpose behavior. The manifest's `usage_policy` identifies the reviewed model-use scope, still-unqualified runtime and separate redistribution review. The selected FLUX/Qwen gates become `RESEARCH_ELIGIBLE_RUNTIME_UNQUALIFIED`; all execution flags stay false. Other checkpoints and dependencies still require their own review. Legacy `*_BLOCKED.json` filenames remain compatible with existing consumers; they do not mean research use is categorically forbidden.

## Pinned workflow audit

Audited 2026-11-09 against actual JSONs and node source. The Animated Characters commit is `77f1462dab427cb95a7b1585a65c8f286a2c3898`; UltraTex is `64eb9ad10454a51be1c88a7a879b839ced0475c9`, matching the existing vendored standard workflow.

| Workflow | Nodes | Downloaded JSON SHA-256 |
|---|---:|---|
| Animated Characters 05 | 107 | `b01f51f61a08ca8ecf85672a688134a180575da7d1feee9b1a27cac7610fb2f8` |
| Animated Props 05p | 107 | `66517e257c59367022f9cdb31cd64cc1cb2753609ec6f951445970095e663afc` |
| UltraTex standard, six views | 26 | `bdc592e8804e502ae4e8db584bb3b1f2e8804f43d2ef13aef3b106604303133c` |
| UltraTex advanced, ten views | 30 | `eaf47639cd737a62b74782b19bc2aead3343474b9d1b555ddb24faf0cb36ddb4` |
| UltraTex low-VRAM GGUF | 34 | `24e0b27583500c9e85df6dc0e4d213265d8532a47cb5f93f8041d822457238a1` |

The combined graph generates shape, makes it watertight, reduces it, bakes a normal map, paints albedo/metal-rough and exports a **static unrigged GLB**. It contains no skinning, humanoid rig, animation clip or video-generation stage. Its character/prop targets are 12k/2k triangles; its UltraTex passes use twelve guided albedo views and six MR views with existing UVs. Rigging and motion export are a subsequent ActionForge step, not output from the downloaded graph. [Pinned graphs](https://github.com/pixelartistry/PixelArtistry-Animated-Characters/tree/77f1462dab427cb95a7b1585a65c8f286a2c3898/workflows), [documented next step](https://github.com/pixelartistry/PixelArtistry-Animated-Characters/blob/77f1462dab427cb95a7b1585a65c8f286a2c3898/README.md).

The existing static validator accepts the three standalone UltraTex layouts. It rejects the combined graphs at link 1299: a MemoryCleaner `*` passthrough feeds a `MESH` input. This is an uncovered wildcard contract, not proof that the upstream graph is broken. This change does not loosen graph validation or adopt the combined graph as the default.

## Reuse on the current character pipeline

The full combined graph targets NVIDIA/CUDA. Its WTiVo binary is tied to Python 3.12, torch 2.8 and CUDA 12. A GGUF model does not supply an AMD implementation of those dependencies. The current Radeon 8060S host's Cycles HIP support therefore does not qualify the complete generator. [Pinned compatibility table](https://github.com/pixelartistry/PixelArtistry-Animated-Characters/blob/77f1462dab427cb95a7b1585a65c8f286a2c3898/docs/COMPATIBILITY.md).

A smaller useful component is Bake Forger at `f13589c22558e3ca49dfa87dce709233eb3cc86b`. Its embedded Blender worker supports HIP and CPU fallback and transfers existing high-detail surfaces onto a UV-matched low-detail target. It joins imported mesh objects and exports selected geometry, so use disposable surface proxies and transfer **maps back to the original rigged asset**. Do not replace Snow/MetaHuman with that proxy GLB. Its ComfyUI wrapper also removes a shared `latest` directory and waits on a subprocess without a timeout; keep the project's existing owned-process/resource/source guards when reusing the worker. No baker code or new dependency is vendored by this change. [Exact source](https://github.com/Mstafa-awad/LODTailor-Bake-Forger/blob/f13589c22558e3ca49dfa87dce709233eb3cc86b/__init__.py).

A bounded next comparison can use one garment region, 2K normal/basecolor/roughness maps and the existing rest-pose/UV proxy. Keep original skeleton hierarchy, bind matrices, vertex order, weights, morphs and material slots. Compare the maps at gameplay distance and through idle/walk/eat/sleep poses. Baking transfers available detail; it does not fix a rejected silhouette or invent missing source detail.

For motion, preserve accepted clips first. ActionForge supports existing-skeleton mapping and animation-only FBX/GLB exports; its app code is proprietary while the Quaternius rig/animations are CC0. Native Unreal IK retargeting can consume a donor while preserving the MetaHuman target. Snow's original control/deform rig remains the Blender authoring source. Exact free-pack coverage for eat/sleep was not verified here: those states still need a real clip and table/utensil/bed contact checks, not a promotional video or still pose. [ActionForge exports](https://actionforge.app/help/main-page), [tool and asset terms](https://actionforge.app/THIRD-PARTY-NOTICES.txt), [MetaHuman retargeting](https://dev.epicgames.com/documentation/metahuman/create-a-custom-ik-retargeter).

## Terms remain component-specific

| Layer | Research and redistribution distinction |
|---|---|
| PixelArtistry layouts/helper/docs | MIT; existing full workflow notices and pinned hashes remain required. |
| FLUX Klein base 9B/GGUF | NC v2.1 permits the declared offline noncommercial research purpose. Model redistribution and output restrictions remain separate; released 9B LoRAs do not become compatible with an Apache 4B replacement. [BFL terms](https://raw.githubusercontent.com/black-forest-labs/flux2/main/model_licenses/LICENSE-FLUX-NON-COMMERICAL). |
| Qwen Image 2.1 | Research agreement is eligible for the declared research purpose; it does not relicense weights as MIT. [Actual agreement](https://huggingface.co/Qwen/Qwen-Image-2.1/raw/main/LICENSE). |
| DINOv3-derived encoder | Custom agreement permits use and requires its agreement for material redistribution and acknowledgment in research publications. Map the exact repackaged encoder's terms separately; a custom license is not a blanket NC prohibition. [Primary license](https://raw.githubusercontent.com/facebookresearch/dinov3/main/LICENSE.md). |
| UltraTex LoRA/decoder and node packs | Verify the exact checkpoint release and individual node terms; layout MIT alone does not clear them. Inspected MostAadTech components use GPLv3. Keep external tool code/notices separate from Unreal code. |

The dated component-license registry remains historical evidence rather than a blanket license decision for a newly declared purpose. This adapter does not distribute weights or grant rights to generated outputs. Input rights, matching checkpoint terms and output review remain independent.

Verification uses the existing CPU-only workflow suite, including source hashes, real graph links, full MIT notices, UV guard behavior, no-overwrite behavior and no-network/no-subprocess checks. Research-specific tests check that eligibility never enables execution or clears redistribution, and that only policy notes/metadata change. No visual quality, inference or live-engine result is asserted by these tests.
