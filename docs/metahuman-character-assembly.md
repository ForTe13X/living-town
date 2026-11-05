# Native MetaHuman assembly checkpoint

Changing the character's source texture resolution does not bound the textures
produced by Unreal's assembly pipeline. In the installed Unreal 5.8.4 High
pipeline, the observed body normal and packed maps were exported at 8192 pixels,
even though the character's acquired source textures were 2048 pixels. Assembly
then exhausted the bounded Editor process during shared dependency copying.

`ULivingTownMetaHumanBakeBudget` provides three Editor-only methods:

| Method | Behavior |
| --- | --- |
| `InspectPipeline` | Reads the actual baking settings and named graph outputs. |
| `Configure2KOutputs` | Sets five measured oversized outputs to `Res2048` on an owned transient High pipeline. |
| `BuildConfiguredHigh` | Binds that pipeline through native build parameters, retains High quality and wardrobe validation, and starts assembly. |

The five outputs are `T_Head_LOD1_N`, `T_Head_LOD1_SRMF`, `T_Body_BC`,
`T_Body_N`, and `T_Body_SRMF`. All other overrides and the pipeline class defaults
are preserved. These are output-specific settings, not a global texture cap.
The helper refuses unsupported contexts and pipeline instances, missing settings
or output names, and an assembly call without all five native resolution values.
It does not request authentication, acquire a rig, or download textures.

`PipelineOverride` is protected from Python property writes in this engine build;
the C++ build method supplies it directly. Assembly and Common destinations are
restricted to the separate `LivingTown_UEPilot/MetaHumanAssembled_v*` and
`MetaHumanCommon_v*` namespaces. An empty Common path uses the SDK's optional-copy
behavior: it produces the core character while retaining references to shared
plugin assets. The caller must inspect generated assets, save them, and verify
them in a fresh process. A returned assembly call alone proves none of those.

The project enables `MetaHumanCharacter` for Editor targets. Direct module
dependencies include the owners of the pipeline types, Editor utility base
class, character build API and character class; transitive headers alone did not
supply the required link library. This feature does not add assembly work to game
startup. It is separate from the [passive sign-in launcher](metahuman-native-signin.md).

## Recorded validation on November 5, 2026

- A fresh Unreal Editor build completed with the pinned MSVC 14.44 toolchain and
  Windows SDK 22621. The native configuration and build calls ran through MCP.
  The four implementation paths match that local checkpoint after line-ending
  normalization and JSON formatting. The containing checkpoint has other native
  work, so this is not an exact whole-PR or packaged Game build claim. Repository
  CI does not compile Unreal.
- Native texture getters read all five saved outputs back as **2048 × 2048**.
  The core output contained **102 packages**, including the actor Blueprint,
  meshes, DNA, materials, textures, grooms and bindings: 142,333,341 bytes total.
- A fresh Editor staged only those core packages, without the 145 MB editing
  character or generation caches. It loaded and spawned the saved Blueprint and
  produced full-character and face perspective renders. It restored the exact
  viewport state, preserved source packages and passed the global settings check.
- That cold-consumer run took 98.047 seconds including Editor startup and fresh
  compilation, with 9,217,626,112 bytes peak aggregate private memory. The log
  identified the Radeon 8060S, D3D12 SM6 and two shader workers. These are Editor
  measurements, not packaged-game startup or full-town frame-rate results.

The assembly host's final global audit separately reported a changed timestamp
on an Epic Launcher settings file. That host remains failed; the completed core
asset phase was sealed separately, and the subsequent independent cold consumer
passed. Equal file sizes do not establish unchanged bytes or explain the cause.

A later experimental SDK common-copy wrapper compiled, but its runtime call
reported Control Rig graph-link errors while duplicating shared rigs. That
wrapper and its partial output are excluded from this change. Shared dependency
closure remains open; the checkpoint is not self-contained.

The inspected renders show coherent skin and eye materials with visible facial
detail. Bright hair highlights, stock white clothing, bare feet, café workwear,
actions, game integration and performance still need work. This checkpoint is
not final character approval. Native MetaHuman packages remain subject to Epic's
terms; the repository contains the helper and evidence metadata, not those raw
packages. Engine-independent character delivery remains a separate requirement.

The compact [evidence record](evidence/metahuman-core-2k-2026-11-05.json) binds the
local receipts and closed asset packet by hash. It does not make private local
outputs available from a repository checkout.
