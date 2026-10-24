# Reusable asset refinement toolbox

`python -m tools.asset_toolbox` coordinates the existing authoring, verification
and evidence tools through small JSON recipes. It uses the Python standard
library, executes argument arrays without a shell, and records exact inputs,
source code, executables, outputs, process exit codes and logs. It installs
nothing. A recipe can finish while its result remains a planning experiment or
an asset review slice; `RECIPE_COMPLETE` never means production readiness or
whole-town concept fidelity.

The town, character and runtime work remains subject to its actual visual and
gameplay evidence. For example, a detail review that verifies gutters or apron
ties while reporting partial concept fidelity does not approve the complete
town. The toolbox makes these iterations repeatable; orchestration itself does
not improve a material, furnish a room, or guarantee unlimited quality.

## Start with the small offline planning stage

Run from the repository root with Python 3.11 or later. Copy
[`config.example.json`](../tools/asset_toolbox/config.example.json), replace the
paths, and remove unused entries. Every configured input and executable is
content-bound, including optional entries. A minimal planning configuration is:

```json
{
  "repo": "C:/path/to/living-town",
  "runtimes": {"python": "C:/path/to/python.exe"},
  "inputs": {}
}
```

Keep this local configuration outside the new iteration directory. A new path
is required for each changed recipe, source, input, runtime or attempted repair.
Use a meaningful date and suffix; these examples are placeholders, not claims
that a final delivery already exists.

```powershell
$python = 'C:/path/to/python.exe'
$config = 'F:/Living Town/toolbox.local.json'
$iteration = 'F:/Living Town/iterations/planning_001'
$recipe = 'tools/asset_toolbox/recipes/town_plan.json'

& $python -m tools.asset_toolbox doctor --recipe $recipe --config $config --iteration $iteration
& $python -m tools.asset_toolbox plan --recipe $recipe --config $config --iteration $iteration
& $python -m tools.asset_toolbox run --recipe $recipe --config $config --iteration $iteration
& $python -m tools.asset_toolbox verify --recipe $recipe --config $config --iteration $iteration
```

This runs the existing `compile_recipe.py`, not Blender or Infinigen. Its
historical core/reserve scope and `COMPILED_NOT_GENERATED` result remain explicit;
it is a short orchestration smoke test, not final 151-building town generation.
`doctor` checks paths and configuration only. It does not execute version
probes, import Pillow/NumPy, validate GPU compatibility or install dependencies.
`inventory` prints content hashes; `plan` and `run --dry-run` execute nothing
and create no iteration. Missing local binaries/assets must be restored through
their existing documented preparation steps before a real build.

## Composable recipes and their boundaries

| Recipe in `tools/asset_toolbox/recipes/` | Existing tools it composes | Result and remaining scope |
| --- | --- | --- |
| `town_plan.json` | `town_generation/compile_recipe.py` | Offline historical planning smoke; explicitly no generation. |
| `whole_town.json` | Whole-town native builder, building/context renderers, visual catalogue, verified portable exporter | Packed Blender source and audited embedded GLB chunks after a separate native-art review; no Godot/gameplay approval. |
| `characters.json` | Approved concept, character builder, independent embedded PBR/UV/alpha verifier, visual review | Separate resident source/GLBs/maps and actual rendered views; deliberately omits `--game-assets` so it does not replace the current game. |
| `godot_preview.json` | Existing independent GLB visual consumer | Real GPU framebuffer and report, then visual review. No physics, navigation, performance or Main gameplay claim. |
| `static_render_cache.json` | Supervised town batch builder and independent binary-resource readback | Engine-specific acceleration beside the native/GLB assets. Requires an imported, staged town and graphical Mobile renderer; actual Main and exported-game cache hits remain separate checks. |
| `gameplay_evidence.json` | Current staged Main/LifeMode logical test, supervised full recording, Edge TTS, composition and media verification | Actual 14-minute AVI/MP4, captions and detailed frames, followed by playback/listening review. Requires a previously compiled/imported and verified game. |
| `offline_workflow_proposals.json` | Existing owned four-view preparation and pinned PixelArtistry workflow customizer | Input images and workflow JSON only. No queue submission, model download, cloud request or inference. |
| `package_inventory.json` | Existing source and Windows package inventory branches | Inventory logs only. No complete source-proof/EXE/PCK validation, ZIP or release is performed. |

Use explicit Blender, Godot, Python, PowerShell, ffmpeg and ffprobe executable
paths for stages that need them. The authoring tools additionally require their
documented NumPy/Pillow/source libraries. Edge TTS must already be installed in
the configured `edge_deps` directory. The toolbox is not a second asset downloader.
Prepared PBR input directories include their maps, manifest and provenance, not
only a detached manifest file. Source licences travel through the existing
source/delivery tools; a public repository or generated image is not a CC0 grant.

The whole-town recipe freezes its **complete native directory**, including the
pre-export `upgrade_manifest.json`, material/provenance files, native scene,
building records and geometry audit. After review, `export_copy.py` copies that
entire immutable directory into a fresh `portable/` output, compares complete
source/copy file inventories byte for byte, and calls the existing exporter on
that working copy. Its updated manifest and new chunks belong to the portable
stage. Both the original native and its coordination metadata remain frozen;
changing an inline building/group/district record after review is rejected.
The copy receipt records the pre-export inventories and actual Blender PID/exit
code, then verifies the original source again. This deliberately costs another
complete native-directory copy and corresponding disk space; reserve that space
before the export. There is no general mutable-output exception.

To add a repeatable stage, copy a recipe and keep `stages` in dependency order.
`argv` is a string array whose first item resolves to a configured runtime.
Supported tokens are `${repo}`, `${iteration}`, `${runtime.NAME}` and
`${input.NAME}`. Declare source code in `source_paths`, consumed generated files
in stage `inputs`, and owned generated files/directories in `outputs`. Output
ownership cannot overlap between stages. `checks` compare a JSON `file` and
`pointer` with an exactly typed `equals` value. `timeout_seconds` bounds the
direct process. A `review` stage instead declares `artifacts`, `criteria` and
optionally its precise `scope` and image/video `extensions`. No expression
language, shell interpolation, package installation or queue adapter is hidden
behind these fields.

Stages run serially. The runner does not reserve a machine-wide engine slot;
the coordinator must keep substantial Blender, Godot and encoding jobs serial
across all terminals/iterations. Blender recipes use six threads and CPU review
rendering. Start a hero/small pilot and review it before a whole batch when
changing a factory, material or outfit. Clone the recipe and use the existing
tools' subset options; changing the recipe requires a new iteration. A full
character batch supplies four body views per person; hero subset builds supply
additional portrait/garment/pose views. Neither substitutes for runtime footage.

The game evidence recipe requires explicit effects:

```powershell
& $python -m tools.asset_toolbox run `
  --recipe tools/asset_toolbox/recipes/gameplay_evidence.json `
  --config $config --iteration 'F:/Living Town/iterations/gameplay_001' `
  --allow-effect workspace_write --allow-effect network
```

`workspace_write` acknowledges the existing consumer/cache/supervisor/save-guard
operations. `network` acknowledges Edge TTS. Their declarations are policy
gates, not a network or filesystem sandbox. Read a recipe and the tools it calls
before running third-party changes. No supplied recipe declares credit spending
or weight downloads; both would need separate explicit `--allow-effect credits`
or `--allow-effect weights` on a future reviewed adapter. Planning and offline
workflow preparation need none of these effects.

## Static render cache

After importing the staged source project, run the reusable producer in a fresh
directory:

```powershell
./tools/build-town-render-cache.ps1 -Godot 'C:/path/to/Godot_console.exe' `
  -Output 'F:/Living Town/iterations/cache_001'
```

The producer runs the complete batch builder, its current-source validation and
an independent saved-resource readback. It derives the expected inventory from
that build. The resulting `static_render_cache.res` and `static_render_cache.json`
belong together. The small manifest is tracked; the binary is a required verified
release/offline-package member whenever that manifest is installed. Generate a
fresh pair after changing the town, import, engine version or model/batcher code.
The runtime rejects a mismatched pair and uses the original builder. It continues
to verify current geometry, materials and semantic ray membership before enabling
cached batches. This cache does not alter engine-agnostic Blender or GLB assets.

The Windows Town3D preset also enables `game/addons/town_raw_sources/`. It
preflights every GLB against the current stage before adding its exact raw bytes
to the PCK. Imported scenes remain the render source; the raw copies support
the existing source-identity and cache checks. An include filter alone does not
retain these imported source files. The actual Windows003 PCK readback verified
all11 raw GLBs and their imported remaps, followed by a normal-Main cache hit.
The addon uses Godot's [EditorExportPlugin.add_file](https://docs.godotengine.org/en/4.6/classes/class_editorexportplugin.html#class-editorexportplugin-method-add-file).

## Receipts, recovery and art review

Each iteration carries `freeze.json`, `plan.json`, `state.json`, per-stage
stdout/stderr logs and, where requested, `reviews/<stage>.json`. The freeze binds
the recipe/config, all configured runtimes/inputs, declared source paths and
the runner itself, and all external literal stage inputs/artifacts even before
their first stage runs. Future generated paths inside the iteration are bound
when produced/consumed. Directory hashes include relative paths and file bytes;
`.git`, `.godot`, `__pycache__`, `.pyc` and `.pyo` are excluded. Symlinks and
junctions inside bound trees are rejected. This records executable bytes; it is
not a full Python-package, Blender-add-on, GPU-driver or operating-system lock.
Existing stage-specific receipts still establish their detailed source/map and
engine contracts.

Use `--stop-after native` to stop at a completed checkpoint. Later continue with
the identical invocation plus `--resume`. Completed stages are skipped only when
the freeze, their actual inputs, outputs, JSON checks and accepted review still
match. Later stages are also checked against previously completed outputs, so a
tool cannot silently change a frozen native or prior image. Status/verification
rehash current bytes instead of trusting a historic green state file.

An art-review stage creates a **PENDING** template and exits with code 4. Open the
actual bound images/video, inspect the concept comparison and listen to requested
audio before editing that template. Set a named `reviewer`, the explicit decision,
observations for every criterion, and `reviewed_files` to the exact subset-free
`artifact_files` map only after all those files were inspected. A reviewer may be
a person or an agent that actually inspected the visual/audio material; numerical
checks cannot fill this attestation. Keep the scope narrow and truthful. A contact
sheet does not establish full-resolution details unless the declared review is
explicitly limited to that sheet.

Decisions `PARTIAL` and `CHANGES_REQUIRED` persist as `PARTIAL_REVIEW` and
`CHANGES_REQUIRED`; neither unlocks dependent stages. Use them when only some
details or views meet the target. `ACCEPT` requires an observation for every
criterion and exact artifact coverage. Even accepted scope applies only to those
declared artifacts/criteria, not every asset, material, pose or gameplay route.
`production_readiness` remains `NOT_EVALUATED`; concept fidelity is never inferred
from recipe completion. To revise source assets after a partial review, create a
fresh iteration and keep the prior evidence.

Generic failed/partial command stages are never rerun in place. Their partial
outputs, PID, exit code and logs remain inspectable. A running state or stale lock
does not prove a process is alive: inspect the recorded process handle and owned
process identity before another engine job. A runner timeout stops its direct
process; descendant engine processes may need coordinator inspection. An
interrupted parent can leave its child running. Do not launch duplicate work on
an observation timeout. For a tool with its own stronger partial-resume contract
(such as the building renderer), use that documented recovery outside this generic
runner and bind the resulting unchanged evidence in a new recipe/iteration.

| Exit | Meaning |
| --- | --- |
| 0 | Command/checkpoint/status succeeded within its stated scope. |
| 2 | Invalid configuration, missing prerequisites, effect not allowed, or changed bindings. |
| 3 | Process/timeout/technical evidence failure, or preserved failed command requiring a fresh iteration. |
| 4 | Art review pending, partial, changes required, stale or incomplete. |
| 5 | `verify` found a valid bound iteration whose complete recipe has not finished. |

## Improve one concrete discrepancy per iteration

1. Select a visible difference against the concept and name the responsible
   factory, material, UV, placement relationship or camera. Record its exact
   asset/building/room identity and the baseline images.
2. Change that actual source. Keep physical texture scale, registered UVs,
   material boundaries, alpha masks, mesh/skin/animation and navigation contracts
   explicit. Use the current terrain/room authorities when revising placement.
3. Render the same camera plus close and gameplay distances, run relevant actual
   GLB/PBR preservation checks, and inspect the difference. A better RGB proposal
   must be implemented and re-rendered in 3D before it counts as an asset upgrade.
4. Repeat the accepted factory across the intended scope, review all required
   building/floor/pose views, then separately test its real consumer and gameplay.

Near views should expose plaster grain/weathering, stone joins, slate edges,
window depth/hardware, gutters, planted-bed edging, leaf/flower variation,
supports/contact shadows, garment seams/ties and shoe fit. Medium and actual
gameplay distances should retain readable composition and density. Crown-envelope
coverage metrics do not measure alpha-tested apparent leaf cover. Planning,
technical integrity, art acceptance, runtime behavior and delivery remain separate.

## Research adapters: useful ideas without automatic inference

The reviewed [AIxArchviz FLUX2 x LTX25 repository](https://github.com/paulh4x/AIxArchviz_FLUX2xLTX25/tree/306d6d01c6ec23a16785da345b15899b940fe07f)
provides RGB generation/edit/video workflows, not mesh/UV/PBR/skin/collision
export. Its [pinned README](https://github.com/paulh4x/AIxArchviz_FLUX2xLTX25/blob/306d6d01c6ec23a16785da345b15899b940fe07f/README.md)
declares the authored workflow layouts CC BY-SA 4.0. No upstream graph is copied
into this toolbox. An adapted distributed graph needs its attribution and
ShareAlike terms; that layout licence does not clear its nodes or checkpoints.
The [selected 9B backbone](https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9B/blob/main/LICENSE.md)
and [vegetation LoRA](https://huggingface.co/paulhax/flux2-klein-9b-localforestlab)
have noncommercial conditions. The [pinned Edit graph](https://github.com/paulh4x/AIxArchviz_FLUX2xLTX25/blob/306d6d01c6ec23a16785da345b15899b940fe07f/workflows/ph_flux2_imageedit_V1.json)
also selects an extra VAE absent from its README list. Stock inference is not a
cleared default for this asset route, and local hardware compatibility is unproven.

Useful bounded next adapters are same-camera RGB/depth/edge/material-ID evidence,
masked edits with exact zero changed pixels outside the approved region, and
simple deterministic native camera studies. These are proposals, not implemented
capabilities of this runner. Reuse the current camera/catalogue receipts, owned
four-view preparation, `tripo_refinement.py compare` and embedded PBR verifiers
when implementing them. Label any later generated video as synthetic concept
motion; actual gameplay evidence must retain the real captured frames. See also
[the existing refinement route](../tools/asset_refinement/README.md),
[whole-town pipeline](../tools/town_upgrade/README.md),
[Tripo preservation boundary](../tools/town_upgrade/TRIPO_REFINEMENT.md) and
[Infinigen-informed methods](INFINIGEN_TOWN_GENERATION.md).

## Delivery remains a separate freeze

`package_inventory.json` reports the existing packagers' no-publish inventories.
Inventory success does **not** establish full evidence validity: source proof
linkage and actual EXE/PCK hash validation also occur in their later validation/
publication functions. The inventory may legitimately fail while required files
are missing, and a successful inventory must not unlock publication by itself.
The existing packagers' publication paths are fixed under the repo's
`build/town_bridge`; a generic runner should not silently repurpose that destination
or publish a release. The coordinator chooses a final freeze, calls those existing
`--publish --freeze-id ...` commands under the serial I/O slot, verifies extracted
offline source/Windows packages, and copies the verified artifacts to the requested
delivery directory. Packaging does not retest gameplay. The current
[playable integration guide](../tools/town_upgrade/PLAYABLE_INTEGRATION.md) records
the required actual EXE/PCK and full-tour evidence.

Focused orchestration tests run tiny real Python subprocesses and verify argument
preservation, immutable resumes, output tampering, partial art status, effect
gates, process failure/timeout evidence and all supplied recipe plans:

```powershell
& $python -m unittest tools.tests.test_asset_toolbox -v
```

These tests exercise the toolbox; they do not certify the town's current art or
re-run Blender, Godot, Edge TTS or ffmpeg.
