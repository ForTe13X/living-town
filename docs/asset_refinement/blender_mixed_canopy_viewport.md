# Blender canopy working-copy result

The revised Blender working copy preserves all 30,176 botanical placements and
36 prototypes while reducing Geometry Nodes hosts from 3,156 to 264. Instances
remain unrealized. Actual save and independent reopen checks preserved geometry,
UVs, shaded corners, materials, images, point metadata, other objects and the
original scenes. This is an editing copy; export authority remains separate.

The 587,743,686-byte working file has SHA-256
`af597a9e715976e8e8684ba8a7295370eac4705a03e4b38baecbd8c0fed53a81`.
Its source is `blender_gn_horticulture004`, SHA-256
`d277242cdfd1f1e07097a95ded8e8e624399830b3df65af710e6fc3501f0a049`.

## Matched viewport observation

One matched baseline/mixed pair completed five views on Blender 5.2.2, Radeon
8060S, Vulkan driver 26.10.1, with a 1572×866 editor area. Each view used three
warmups and 20 measured redraws. Views, overlays, presentation, backend and
process-local startup settings matched.

| View | Baseline median, ms | Mixed median, ms | Lower latency |
| --- | ---: | ---: | ---: |
| Saved roof closeup | 183.8 | 157.9 | 14.1% |
| Town core, Solid | 255.4 | 223.4 | 12.5% |
| Town core, Material | 493.5 | 440.1 | 10.8% |
| Overview, Solid | 268.4 | 240.9 | 10.2% |
| Overview, Material | 501.7 | 463.1 | 7.7% |

These are `wm.redraw_timer(DRAW_WIN_SWAP)` wall times including operator
overhead. They establish neither normal navigation FPS nor GPU-only time or
Unreal performance. This was one paired run, not a replicated estimate.
Material preview still costs 440–463 ms in this measurement. Peak private commit
was 17.046 → 16.633 GB decimal, close to the 16 GiB controlled process budget.
Both processes exited naturally with code 0; source files, global settings and
viewport restoration passed their checks.

All eight town/overview Solid and Material images were visually reviewed in
pairs, with no observable layout or coverage loss. The first saved-view image
was byte-identical between arms and free of the startup dialog. It is a roof
closeup, not a presentation image. This does not accept final art or long editing
sessions.

The earlier OpenGL attempts both crashed inside `atio6axx.dll` during the first
Material warmup, near the owned memory limit. The trace cannot separate driver
behavior from allocation pressure. The successful Vulkan pair used the same
memory budget; no global GPU or Blender preference was changed.

## Local editing entry point

The local artifact folder
`F:\Living Town\2026-10-20_Refined_Town\blender_mixed_canopy_working_adoption_v1_001`
contains `OPEN_TOWN.cmd`. An explicit user launch verifies the positive working
file and its evidence, creates a fresh editable copy, and opens Blender with
Vulkan, disabled file auto-execution and private config/cache/TEMP. It never
overwrites the checked master or a previous user copy.

Startup selects the working scene and the observed overview Solid view with
overlays/gizmos off. It changes no camera object, light, material or source
asset, and does not save preferences. The benchmark used overlays on; this
entry-view convenience has no separate timing claim. Save the editable copy
normally or use Save As for a chosen project location.

Raw evidence stays in `blender_mixed_canopy_cells_actual_v1_005` (save/reopen)
and `blender_mixed_canopy_gui_actual_v1_008` (matched Vulkan reports/images).
Remaining work includes Material-preview memory/latency, longer interactive
use, composition, final textures and the Unreal asset derivative.
