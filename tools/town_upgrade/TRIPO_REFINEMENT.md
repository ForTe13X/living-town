# Tripo refinement pilot

Tripo is an optional comparison route for the refined stylized town. The first
pilot retextures a duplicate of Aria's current engine-independent GLB, using
the recorded CC0 MakeHuman graphical sources and an original generated concept.
Do not upload the film clips or extracted film frames. The approved visual goal
is a calm Breton summer with legible cloth, skin and architectural materials.
Tripo does not replace the town generator or establish artistic acceptance.

The October 2026 pilot used CLI 0.7.2 and texture model `v3.0-20250812`.
Two completed static-avatar trials consumed 40 API credits in total. Neither
candidate was accepted into the game. The second trial retained overlapping
material-local UV coordinates while collapsing ten materials into one, removed
the four alpha-mask material boundaries, and normalized stature to one unit.
Its texture conflicts are documented in the private output diagnostic; a
successful API task did not satisfy preservation or visual checks. The current
CC0 residents remain the production path. Opaque props or individual garments
with a deliberate single atlas are better bounded future inputs.

The current 25 residents, stable IDs, rest rigs, seven native clips and
`SeatContact` morph remain the comparison baseline. A candidate that loses
these can still inform manual look development, but is not a drop-in retexture.
Do not automatically replace all 25 rigs, unwrap registered atlases, retopologize,
or rerig during this preservation pilot. Unique props are another bounded use;
trees still need shared materials, alpha cards, collision and LOD review.

## Account and command evidence

The [official CLI page](https://studio.tripo3d.ai/cli) says the CLI uses **API
credits**, separately from Studio. Its paid-subscriber API-credit offer is a
one-time eligible-account benefit, not proof of available balance. Check the
matching account, entitlement, previous claim and API balance before submitting.
The user selected the `ov` international account region after correcting an
initial mainland-region choice. Browser device authorization is handled
by the coordinator; never paste keys into a prompt, source file, report or log.

The local CLI is installed under `build/tripo_cli/node_modules/tripo-cli`.
Its recorded version at preparation is 0.7.2. Read the installed
`skill/SKILL.md`, `skill/commands/make.md` and `skill/commands/process.md` before
constructing a job. [Current official CLI documentation](https://developers.tripo3d.ai/en/docs/cli)
can differ from the installed version; do not invent flags from newer API docs.
In particular the installed CLI rig default differs from the server default.
The retexture pilot needs neither rigging nor mesh processing.

Preparation and comparison in this module are entirely local. They never call
Tripo, read credentials, launch an engine, upload a model or spend credits.
The coordinator owns actual authentication, offline CLI plan validation,
submission, waiting and download. In the installed CLI, a noninteractive `make`
can submit without an interactive confirmation; preserve `--dry-run --json`
during plan validation. Do not treat the plan as a successful generation receipt.

The [texture endpoint](https://developers.tripo3d.ai/en/docs/models-texture)
supports existing models, PBR, text with a style image, a single image, or
multiple views. `detailed` is a reasonable bounded trial; `extreme` has an extra
credit cost. The reviewed docs do not promise byte-identical existing topology,
UVs, weights or clips. Tripo's de-lighting option is model-version dependent.
Use native GLB/PBR output; retain the original rather than overwriting it.

The separate Studio DCC Bridge 1.0.34 was installed from the user-supplied ZIP
after its SHA-256 matched the official download. Registration and a local
WebSocket handshake/ping passed in Blender 5.2.2. This verifies the installed
addon. Chrome's Studio DCC switch was subsequently confirmed by the user, and
the staging process recorded an active connected client. The in-app browser
did not establish a reliable connection. No model transfer has been certified.
The clean staging launcher and
private installation receipts are delivered beside the art outputs; no addon
source is redistributed in this repository and no startup preference is changed.

## Actual exported-file comparison

Run from the repository root, substituting real files and a new report path:

```powershell
py -3.12 tools/town_upgrade/tripo_refinement.py inspect "F:/Living Town/2026-10-20_Refined_Town/characters_final_v1/models/aria.glb" --report build/tripo_aria_source.json
py -3.12 tools/town_upgrade/tripo_refinement.py compare "F:/Living Town/2026-10-20_Refined_Town/characters_final_v1/models/aria.glb" "F:/Living Town/tripo_aria_candidate/model.glb" --report build/tripo_aria_comparison.json
py -3.12 -m unittest tools.tests.test_town_tripo_refinement
```

Exit 0 means the local inspection or preservation comparison passed. Exit 1
means a changed contract, unsupported representation, malformed span or invalid
data; inspect the report. Reports are created exclusively and never overwritten.
The example candidate path is a placeholder, not an existing generated asset.

The verifier hashes both complete files, embedded buffers and parsed JSON, then decodes the
actual BIN accessor values. Buffer offsets, padding and accessor IDs do not
establish equality. Dense, interleaved and standard sparse accessors are
supported, including zero-base sparse morphs, integer skin attributes and padded
small-component matrices. Finite bounds come from mesh-local rest `POSITION`
values, not untrusted accessor min/max metadata. They are not world or posed
bounds. It records byte sizes, triangle/vertex counts, clips, material JSON,
embedded image SHA-256 and image dimensions/pixel hashes when Pillow can decode
them. Invalid/unsupported image encoding is recorded and does not prove texture
validity. An absent Pillow installation leaves pixel inspection explicitly undone.

Preservation fails for changes to primitive topology, indices, position, UVs,
joint indices, weights, inverse binds, morph data/defaults/names, node rest
hierarchy, scene roots or animation data/targets/names. Mesh/node/clip ordering is
conservative: a reordered or renamed equivalent candidate can fail and needs a
deliberate integration review. Material/texture changes are permitted and
fingerprinted; normal/tangent changes are reported separately for shading
inspection. Compression (Draco/meshopt), external resources, unsupported required
extensions (including unknown optional geometry extensions), invalid spans and
nonfinite values fail closed. Inputs changing during inspection are rejected. This is a bounded
GLB preservation verifier, not a complete Khronos conformance validator.

A numerical PASS never approves appearance. Render the untouched source and
candidate under the same neutral and summer lighting, camera and scale. Inspect
front/three-quarter/side/back portraits, garment seams, alpha hair/brows/lashes,
normal-map direction and surface finish, then all seven poses and the seated
corrective. Check density, compression, real texture dimensions, silhouette and
engine-neutral glTF import. The coordinator owns Blender and optional Godot
checks. Preserve source/candidate screenshots and an explicit comparison verdict.

## Provenance and delivery

Paid Tripo output is **not CC0**. The [terms, section 5.2.2](https://www.tripo3d.ai/terms)
grant paid users broad use, modification and distribution rights, subject to the
agreement and third-party rights. Studio subscription alone does not establish
the specific API account's paid-output entitlement. Confirm it for the account
and task before public redistribution. Keep the existing CC0 upstream licenses
with source derivatives; do not relabel generated material as CC0.

Store the source/concept hashes and provenance, CLI version and offline plan,
actual task IDs and complete task receipts, model/texture versions and seeds,
actual credits consumed, entitlement evidence without secrets, generation date,
terms URL/date or snapshot, downloaded-file hashes, this comparison report and
render verdict together. A failed/timed-out submission is not a safe reason to
resubmit blindly: recover the existing task and balance first as described in
the CLI docs. Do not fabricate task success, credits, license approval or quality.
