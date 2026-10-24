# Runtime performance evidence

The current 62-resident simulation uses an ordered room-plane index and cached
physical portal paths. Room bounds and privacy remain live; every cached path
rechecks each exact portal's current permission, falling back to the original BFS
when needed. These derived caches do not enter saves. Separate and combined
oracle runs matched room queries, routes, all 90 ticks, complete sampled actor
state, event bytes and the project event chain.

An ordinary graphical Main run on the same horticulture assets, 1280×768,
Mobile/Vulkan, 62 residents and the same cameras recorded:

| View | Before mean FPS | Current mean FPS | Current p95 frame time |
|---|---:|---:|---:|
| Upper home, paused | 136.8 | 126.0 | 10.0 ms |
| Upper home, 1× | 122.7 | 120.3 | 14.0 ms |
| Upper home, 4× | 74.6 | 100.1 | 22.4 ms |
| Outdoor, paused | 33.4 | 32.1 | 40.1 ms |
| Outdoor, 1× | 29.3 | 30.1 | 42.4 ms |
| Outdoor, 4× | 11.2 | 24.2 | 77.0 ms |

This is a sequential diagnostic comparison, without MovieWriter or an FPS cap.
All controlled actors, cells, camera poses and phase starting ticks matched.
Geometry and population were retained. Outdoor rendering
and accelerated-simulation spikes still need improvement. The complete current
report is `normal_frame_sim_cache_mobile_v16_002/frame_report.json`, SHA256
`fda96d66e092ff3f884166bc37bf87eb614f3d66db3df5fb348b72dfdbb0fc35`.
Its independent source, private-file and owned-process cleanup checks passed.

Startup is improved but remains long. An initial isolated cache hit did not
transfer to Main: duplicate imported chunk roots had process-dependent names,
so Main correctly rejected their cached registry paths and rebuilt the batches.
Unique asset-derived chunk names fixed that mismatch. A freshly generated cache
now hits in actual Main, with all 2,880 groups, 19,197 sources and the unchanged
geometry/buffer/ray validator passing. Synchronous setup fell from 80.3 to 66.3
seconds; first completed draw fell from 95.6 to 81.7 seconds. These timings exclude
engine/autoload initialization. Model loading still takes 30.7 seconds and cache
preparation/validation 31.0 seconds. A fresh Windows export separately passed
normal Main, the default Mobile/Vulkan backend and this exact cache hit with
151 buildings and62mesh residents. Its stage timers recorded31.4seconds model
loading and26.9seconds batch preparation; they are not a total first-frame
measurement. The capped binary smoke run does not measure ordinary FPS.

The Windows export includes eleven checksum-verified raw GLBs through
`game/addons/town_raw_sources/`, alongside their normal imported scenes.
Godot's include filter alone omitted those imported source files, causing a
safe cache miss in the first export. Actual PCK readback and the unchanged
runtime source/buffer checks now pass. The source-project timings above remain
separate from this packaged proof.

All eight existing logical regression groups passed after this integration:
save/load, resume, migration, save budget, space, café access, player journey and
whole-town integration. Summary:
`performance_acceptance_v16_003/regressions/regression_summary.json`, SHA256
`59ccf720531d293b479e7acb73684871c25eb6176e6e9fa3f2a4718fcdb4b602`.
The required cache pair is included in the 51-file local runtime/release contract;
41 offline toolbox, package and asset tests also passed.

On the current horticulture native, an optional Blender exterior working Scene
preserves the canonical Scene and the full-interior geometry-node Scene. It
excludes 263 audited interior floor collections only in the exterior Scene;
all 6,739 source furniture objects, 137 materials and 97 packed images remain.
An actual save and GUI reopen passed the source and placement checks.

| Matched Blender GUI case | Canonical median redraw | Exterior working median redraw |
|---|---:|---:|
| Saved viewport | 296.6 ms | 77.4 ms |
| Core, Solid | 413.1 ms | 107.0 ms |
| Core, Material Preview | 627.2 ms | 169.6 ms |
| Overview, Solid | 429.5 ms | 109.4 ms |
| Overview, Material Preview | 627.2 ms | 169.2 ms |

These five cases show 73–75% lower redraw latency, including the redraw
operator's overhead. They do not measure navigation FPS or establish identical
interior lighting through windows. Select the full-interior Scene for interior
work and export from the canonical native. Evidence:
`exterior005_gui_redraw_v16_001/gui_redraw_report.json`, SHA256
`ced8c0c3fdb604f69921a68721b4ca0f23fd414ad63329e24d8183dbf5ac70db`.

The Windows launcher targets **60 FPS**. Use `./tools/run-town3d.ps1 -MaxFps 30`
for a lower cap, or `-MaxFps 0` for an uncapped diagnostic. Import preparation
retains its separate 30 FPS cap.

The desktop project default now requests Godot's **Mobile** renderer for new
Windows exports, direct EXE launch and editor play (F5/F6). The 3D PowerShell
launcher and walkthrough recorder also explicitly select Mobile. The existing
mobile-host override remains Compatibility for the Android policy; that feature
tag describes the host OS, rather than the Mobile rendering backend.

The package includes `Play_Compatibility.cmd` for older GPUs. It selects
`gl_compatibility` / `opengl3` before the engine/game argument separator, then
uses the same offline 3D resident-selection arguments as `Play_Offline.cmd`.
The PowerShell options `-Renderer Compatibility` and `-Legacy` remain available.
Automatic OpenGL fallback is explicitly enabled through
`rendering/rendering_device/fallback_to_opengl3`. Godot may choose a different
actual renderer or driver when a backend is unavailable; verify the startup
method/driver before comparing results. [Godot renderer documentation](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html),
[Godot 4.6 fallback setting](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-fallback-to-opengl3).

An actual source-project Main launch with no renderer/driver override selected
Mobile / Vulkan 1.4.359 on the AMD Radeon 8060S. Public stairs and doors exercised
the home → café → outdoors → café sequence: original rendering remained active
indoors and all 2,880 exterior groups became active outdoors. The independent
source/save/cleanup guards passed. This is source-project evidence; a fresh
packaged EXE and literal editor F6 launch remain separate checks.

The new horticulture assets were measured at 1280×768 with the default **62
residents**, VSync disabled, no FPS cap and no MovieWriter:

| View | Mean FPS | 95th percentile frame time |
|---|---:|---:|
| Upper home, paused | 136.8 | 9.8 ms |
| Upper home, 1× | 122.7 | 20.7 ms |
| Upper home, 4× | 74.6 | 55.2 ms |
| Outdoor, 75 m camera, paused | 33.4 | 39.7 ms |
| Outdoor, 1× | 29.3 | 74.0 ms |
| Outdoor, 4× | 11.2 | 154.9 ms |

Outdoor performance, especially accelerated simulation, remains unresolved.
The earlier 38.2 FPS outdoor result below used **14 actual residents** from
`--agents 12 --seed 7`; its outdoor camera also differs. It is not a matched
before/after comparison with this default-population run. The process-time
monitor records a preceding interval maximum, not per-frame CPU samples, so
it cannot attribute the slowdown to one simulation function or asset.

Current evidence under `F:/Living Town/2026-10-20_Refined_Town/`:

- `normal_frame_horticulture_mobile_001/frame_report.json`, SHA256
  `e38ccdb33a75bd977c8aa9ce8c096712839af43a4590353a3a833d1b2155cb8e`.
- `default_renderer_proof_v16_002/probe/default_renderer_report.json`, SHA256
  `81c8732d325b6e5e8d835c57c2cd219d5f76d2b9580000a90dbcf79da144e0e9`.
- `final_delivery_h002_001/regressions/regression_summary.json`, SHA256
  `a47c88b8eb4b62e6c7c5681b38cdae51b3068844e09468e7af9a3dde8cdf6b32`:
  all eight logical regression groups passed on these assets.

The portable002 asset manifest is
`007a2b506f3e3456a589c87b139cb48a3b85de432f6e616603620aa43cbb2e9d`;
the staged manifest is
`14841567aa0172536446f1ac95e161b8dda3249d72a5956f83802e6711f429d0`.
The following measurements are retained historical experiments on earlier
assets and workloads. They do not establish final-asset performance acceptance.

The earlier staged Mobile exterior batcher, route reuse and ray index recorded
the following normal-game results with an explicit Mobile CLI override on the
AMD Radeon 8060S at 1280×768, with VSync disabled, no FPS cap and no MovieWriter:

| View | Mean FPS | 95th percentile frame time |
|---|---:|---:|
| Upper home, paused | 156.6 | 8.4 ms |
| Upper home, 1× | 145.3 | 10.5 ms |
| Upper home, 4× | 125.1 | 20.8 ms |
| Outdoor, 75 m camera, paused | 41.9 | 30.7 ms |
| Outdoor, 1× | 38.2 | 44.1 ms |
| Outdoor, 4× | 36.6 | 43.8 ms |

The home begins at night; the legal stair/door route and normal simulation
reach the outdoor sample at tick129, about12:54. These are not all night samples.
The separate strict run confirmed source stability, clean process cleanup and
unchanged private files. The batcher retains original rendering indoors and
automatically resumes outdoors. Its actual-owned lifecycle run passed 300 checks,
including real doors/stairs, original interior rendering, synchronous fallback
on a newly added local light, reload and exit cleanup. Existing shadow settings,
plant placements and authored mesh/texture data remain intact. Aggregated
derivative normals/tangents use the declared packed-format conversion below.

Normal report: `normal_frame_exterior_coarse_mobile_001/frame_report.json`
(`932af0fbde1843e685174d861096ea3eb614b76297b5f3255540a43b6267e1c2`).
Lifecycle report: `exterior_coarse_product_lifecycle_mobile_v16_002/coarse_product_lifecycle_report.json`
(`fe33c7a3ae1ff543c125708d7c7c0d96ce190e965757e9e728b91a00d875c267`).
New final-asset checks remain required after the native/export freeze.

All eight headless regression groups also passed on this installed source and
asset profile: save/load, resume, migration, save budget, space, café access,
player journey and whole-town integration. The fresh summary is
`regressions_exterior_coarse_product_001/regression_summary.json`
(`1e5300d3bd056b7daf4327c64705e9d2a047c979c702e4a71727a88372e02f34`).
The actual whole-town report was then copied into the tracked runtime report.

This batching pass increases startup preparation: the measured preparation was
about 46.4 seconds, compared with about 27.1 seconds for the earlier batcher.
The FPS samples exclude that work. Earlier nested diagnostic metadata shares a
live dictionary; use the immediate lifecycle checks and captured frames when
reviewing past phase status. The mairie transition's first capture has an
unsettled camera; its subsequent centered portal capture shows the cutaway.

The current fixes preserve the authored assets and simulation decisions:

- Journey evaluation builds an ordered portal search once per synchronous
  candidate evaluation and reuses its first hops. Each call has a fresh access
  context; permissions are not cached across decisions or ticks. Other route
  callers retain their existing behavior.
- Static geometry queries use a conservative spatial index before the original
  visibility, owner, distance and exact triangle tests. Candidate order preserves
  nearest-hit ties. Call `TownModel3D.invalidate_geometry_queries(reason)` before
  and after changing static geometry, mesh/ancestor transforms, materials or
  source-array membership/order, without yielding between those operations.
  This restores original rendering before edits and invalidates the query cache.
  Visibility and vegetation range changes are read live.

On the local AMD Radeon 8060S, Godot 4.6.2 Compatibility, 1280×768, with no
MovieWriter, disabled VSync and no FPS cap, the actual Main/LifeMode probe
recorded:

| View | Before: mean FPS | Current: mean FPS | Current 95th percentile frame time |
|---|---:|---:|---:|
| Upper home, paused | 48.8 | 67.1 | 25.3 ms |
| Upper home, 1× | 41.2 | 66.4 | 25.3 ms |
| Upper home, 4× | 12.6 | 62.9 | 28.2 ms |
| Outdoor, 75 m camera, paused | 5.6 | 6.9 | 148.7 ms |

With the same source assets, camera, four shadow splits and normal simulation,
the separate Vulkan Mobile run recorded:

| View | Mobile mean FPS | 95th percentile frame time |
|---|---:|---:|
| Upper home, paused | 137.1 | 10.7 ms |
| Upper home, 1× | 131.9 | 11.9 ms |
| Upper home, 4× | 107.6 | 22.0 ms |
| Outdoor, 75 m camera, paused | 14.3 | 77.9 ms |
| Outdoor, 1× | 13.5 | 96.2 ms |
| Outdoor, 4× | 12.4 | 104.2 ms |

The strict supervisor confirmed a clean exit, stable source and cleanup; the
probe also confirmed unchanged existing private-file hashes. This establishes
an improvement on this AMD 8060S, not a general renderer ranking. Paired actual
outdoor images retain the scene; lighting differs slightly between backends.
The recorder's new backend still requires a fresh complete route recording.

The outdoor scene remains slow: Compatibility submits approximately 42,000
draw calls. Counts from different rendering backends are not directly comparable.
The first conservative packed-buffer pilot passed 115 technical checks in actual Main,
but changed outdoor mean FPS only from 7.179 to 7.186 (7.167 after restoration).
Its 40 eligible groups covered just 90 original sources; compressed source
formats were outside that experiment. The difference is too small to establish
a practical improvement, so that pilot remains uninstalled. The existing
botanical instancing already covers all 30,176 plant placements in 3,483 spatial batches;
the raw draw count does not mean those plants are all separate draw nodes.
These short diagnostic samples are not a hardware-independent FPS guarantee or
final performance acceptance. Simulation progress and NPC poses differ between
wall-clock runs. Some unrelated host preparation overlapped the investigation;
repeat the final comparison after the asset and source freeze.

A subsequent compressed-source batcher was tested for graphical Mobile only;
Compatibility and headless runs retain original rendering. Its actual paused
outdoor comparison covered 8,478 sources in 3,099 batches and recorded
15.695 → 19.644 → 15.699 FPS for original, batched and restored phases.
Draw submissions fell from 10,480 to 8,280; world-render CPU time fell from
39.39 to 31.55 ms. World GPU time stayed near 6.8 ms. The original and batched
world images differed in 31 pixels by at most one 8-bit channel value; the
restored image matched the original. This is a bounded comparison, not final
whole-route performance acceptance.

The batcher preserves canonical mesh nodes for ownership, cutaways and ray
queries, and preserves source positions, UVs, colors and topology. Normal and
tangent conversion follows the pinned Godot packed-format model; it is not
bitwise identity (the maximum observed tangent difference was 0.0106 degrees).
Material and visibility partitions remain separate. Static edits discard the
derivative and restore original render flags; reload and exit also restore
originals before freeing nodes. There is no per-frame rebuild or buffer scan.
That earlier installed 13 m home comparison passed 153 checks and restored its entry
state, with no new visible shading difference in the actual close-up images.
The fresh normal-frame run measured:

| View | Installed batches: mean FPS | 95th percentile frame time |
|---|---:|---:|
| Upper home, paused | 162.6 | 8.2 ms |
| Upper home, 1× | 157.4 | 9.1 ms |
| Upper home, 4× | 127.1 | 20.9 ms |
| Outdoor, 75 m camera, paused | 19.5 | 58.8 ms |
| Outdoor, 1× | 18.3 | 72.2 ms |
| Outdoor, 4× | 16.9 | 83.2 ms |

That actual Main run used no MovieWriter, retained the original private-file
hashes and passed strict source/cleanup supervision. All eight regression
groups also passed on the installed source. The corrected installed lifecycle
check passed 254 checks: real café stairs, café and town-hall doors, visibility
fallback, invalidation before edits, full reload and exit cleanup. The first
attempt is retained as a failed diagnostic because its town-hall click landed
on the objectives HUD. These captures are early night (the lifecycle HUD reads
02:54); day and night lighting require separate review. Room furnishing and
foliage artifacts remain art work, and the outdoor rate still needs improvement.

Evidence: `compressed_batch_main_mobile_v16_001/compressed_batch_report.json`
(`670438db45278f73ecac6166790f641619ca508dbd6e03de6c0e484a165957a7`)
and `compressed_batch_home13_installed_mobile_v16_001/close_batch_report.json`
(`f1b20dc360dd0a881f547e85c2ba037c64b0326bcb3dcb6c23a42193995065a2`).
The normal-frame report is `normal_frame_static_batch_mobile_001/frame_report.json`
(`7cf3d406377697c7291a95b08b7f1c0aa4a2d51795d16e2deca71c0596c92307`);
the eight-run summary is `regressions_static_batch_product_001/regression_summary.json`.
Installed lifecycle evidence is
`compressed_batch_product_lifecycle_mobile_v16_002/lifecycle_report.json`
(`fe6b7d0b22d6b0e23a84e6ed02c0fe1436b1938a7c6e64d0959f60819b10cae9`).

The installed exterior derivative omits only the semantic dictionary
from its batch key while retaining the original semantic nodes. It admitted
19,200 sources in 2,881 groups, including sources formerly excluded as singleton
groups. The actual original/on/restored comparison recorded 15.39/44.71/15.16
FPS and 10,488/3,484/10,488 draw submissions. World CPU render time fell from
41.48 to 12.62 ms; GPU time stayed near 6.8 ms. All 213 checks passed, including
disabling the installed owner before constructing the candidate and rejecting
an actual mixed-visibility home cutaway. The three reviewed world images showed
no obvious new regression: 237 pixels changed by at most 5/255, and restoration
matched the original decoded pixels. A separate brighter-day control passed 278
checks, retained the existing shadows/sun angle and covered the primary view plus
two pan positions. Root reviewed all nine world images without an obvious new
artifact; all three restored images matched their originals. Those finite poses
do not establish every possible moving-camera or local-light configuration.
The installed product therefore falls back on unsupported lighting/GI contexts.
Evidence: `exterior_coarse_batch_mobile_v16_001/coarse_batch_report.json`
(`6f6ac82cf9c0338b598f0d505e267f29b066b3c10ccf0473de3eb58ccc8fafc4`).

The installed route source passed 458 experiment checks, including **78,144**
ordered route queries and 90 ticks with identical semantic/event state chains.
Paired instrumented Sim tick time was 13.632 seconds versus 0.971 seconds;
worst tick was 3.732 seconds versus 0.143 seconds. This is CPU tick evidence
without Main listeners or rendering. The ray experiment passed 63 checks with
identical hit identities, positions, normals and distances; its warm home batch
was 2.986 seconds versus 0.358 seconds for 41 queries. Neither microbenchmark
by itself establishes normal gameplay FPS.

The room/object membership prototype also preserved behavior, but improved
total tick time by only 1.74%. It remains an ignored experiment rather than an
installed fix. The deeper profile identified repeated portal searches as the
dominant CPU cost.

Run the actual frame diagnostic with a fresh absolute output folder and an
already imported local town:

```powershell
$repo = (Get-Location).Path
$godot = 'C:/path/to/Godot_v4.6.2-stable_win64_console.exe'
$out = 'F:/Living Town/frame_probe_fresh'
& './tools/run-godot-supervised.ps1' -Godot $godot -AllowDirtyCandidate -TimeoutSec 600 -GodotArgs @(
  '--single-threaded-scene', '--rendering-method', 'mobile', '--max-fps', '0', '--script',
  (Join-Path $repo 'tools/town_upgrade/runtime_frame_probe.gd'), '--',
  '--town3d', '--life', '--backend', 'logic', '--seed', '7', '--agents', '12',
  '--speed', '0', '--frame-probe-dir', $out
)
if ($LASTEXITCODE -ne 0) { throw 'Retain and inspect the failed diagnostic.' }
```

The probe uses real monotonic frame intervals. Godot's `TIME_PROCESS` and
`TIME_PHYSICS_PROCESS` monitors hold an approximately one-second peak; their
repeated samples are labeled as held peaks and must not be interpreted as
per-frame CPU distributions. The probe selects a resident through LifeMode,
sends actual pause/speed input, and uses legal screen-click stairs and doors
when an eligible outdoor resident is unavailable. It checks the actual
controlled resident and viewed plane before sampling. It does not relocate
actors, skip ticks, save or load private files, or disable normal view updates.
It observes settings/quicksave hashes before and after.

Local evidence is retained under `F:/Living Town/2026-10-20_Refined_Town`:

| Evidence | SHA-256 |
|---|---|
| `normal_frame_product_001/frame_report.json` | `c48318a5132cfec4afd7c59de3854ef2aec8cbdb5c01bd046ef37111e0662236` |
| `route_tree_experiment_002_ticks90.json` | `900f393d2aae18d31d422dc05beeb002d1a06c6737955f9abf346495897350a7` |

Earlier camera-only outdoor attempts repeatedly fought LifeMode's active
plane and are retained as flawed diagnostics. The third attempt retained valid
home samples but explicitly failed to find an eligible outdoor resident. The
fourth baseline used real Aria stair/door input and verified town/outdoor plane
agreement; it is the outdoor baseline above. Failed iterations are not accepted
as completed runs. Blender viewport responsiveness is measured separately;
these Godot numbers do not describe Blender.

The separate Blender 5.2.2 GUI diagnostic completed 20 actual redraw samples
per view on the same AMD 8060S/OpenGL driver. At a 1572×833 editor region, the
core view recorded a median 386 ms in Solid and 594 ms in Material Preview;
the overview recorded 403 ms and 593 ms respectively. These are wall times of
`wm.redraw_timer(DRAW_WIN_SWAP)`, including its operator overhead, rather than
normal navigation FPS or GPU-only timings. The full native file, object/mesh
registry, transforms, visibility and material slots remained unchanged, and
the initial viewport settings were restored. The as-opened factory-session
viewport was Solid; this does not identify the user's prior open workspace.

Evidence: `blender_gui_redraw_002/gui_redraw_report.json` under the same local
evidence root. A saved working copy using exact geometry-node instances passed
its independent reopen proof: all 30,176 prototype/matrix instances matched,
and nonbotanical membership, prototype geometry, UVs, shaded corners and
materials remained intact. Its four matched GUI cases recorded:

| Blender view | Original median redraw | Working copy median redraw |
|---|---:|---:|
| Core, Solid | 385.9 ms | 299.2 ms |
| Core, Material Preview | 593.9 ms | 505.2 ms |
| Overview, Solid | 402.7 ms | 314.7 ms |
| Overview, Material Preview | 593.0 ms | 504.1 ms |

These are approximately 22% and 15% latency reductions, respectively, with
the same measurement limitations above. The dark foliage remains visible in
both original and working Material Preview images; the instancing change is
not an art fix. Evidence is in `blender_gn_exact_gui_002/` and its adjacent
`blender_gn_exact_gui_002.reopened_proof.json`.

The optional working file is
`blender_gn_exact_candidate_002/living_town_working_exact_gn.blend`, SHA-256
`9e19660e90a1a3ac2e4c9d283bd5ee6b7896124779a6fd0b4d7f86251ca0f323`.
It retains the original scene and uses 3,156 working hosts for all plants,
with a catalog resolving each point to its original ID and placement. No
density, LOD or geometry reduction is included. It is a snapshot for viewport
work; rebuild it after changing plant placements. Continue exporting from the
canonical native, rather than this working representation. The first saved
pilot lost its working Scene on reopen and remains rejected; only candidate002
passed the full reopened proof.

The same original native was also measured on Blender's actual Vulkan backend.
Its core Material Preview median was 631.4 ms and overview median 635.5 ms,
versus 593.9/593.0 ms on OpenGL. Solid medians were 373.9/387.9 ms, only a small
change. Vulkan retained the distant black-canopy appearance and is not adopted
as a Blender performance fix. That backend result differs from Godot's measured
Mobile improvement; the two applications have separate rendering pipelines.

A separate paused outdoor comparison retained shadows throughout four, one,
two and restored-four split phases. Compatibility recorded 6.90, 8.70, 7.31 and
6.97 FPS; Vulkan Mobile recorded 14.49, 19.14, 15.95 and 14.24 FPS. Each run
passed 172 checks, retained exact runtime asset/material/camera bindings and
restored its original settings. Fewer splits are **not installed**: these short
stationary views do not establish moving-camera shadow quality or sufficient
outdoor performance. Disabling shadows was only an earlier diagnostic.

Additional local evidence:

| Evidence | SHA-256 |
|---|---|
| `normal_frame_mobile_vulkan_001/frame_report.json` | `17d12fc307c56230a67304e69619d5f0260ef4c50cc73810b39a8e881d570ae3` |
| `shadow_cascades_v16_001/shadow_report.json` | `80184409697a4dad51f1d285daef5ad1e11d1949514d969879a612b4c4d53d5a` |
| `shadow_cascades_mobile_v16_001/shadow_report.json` | `fbe33fa8402f96cd54455bbb67a6b21f12f3036ba5c899fac575c0ad92fe1b0d` |

A roof-only occlusion pilot passed 178 technical checks on Mobile, including
exact triangle readback, source preservation and safe disable before its bounded
cutaway test. Eleven roofs (220 triangles) were eligible; 25 LOD-bearing roofs
were conservatively skipped. The three actual world PNGs were identical, but
off/on/restored timing was 14.33/14.22/14.73 FPS. This scope brought no practical
gain and remains uninstalled. It does not establish that broader occlusion is
ineffective.

That instrumented run exposed about 42.8 ms of CPU world-render work versus
8.4 ms of GPU world-render work in the original phase. Those are public
RenderingServer last-frame measurements for the world viewport; other viewport
times and script work are not included, so they are not a complete frame-time
sum. They support investigating CPU draw submission further. Source:
`roof_occlusion_mobile_v16_001/occlusion_report.json`, SHA-256
`1027a006891751967ab14e1155aee609ec68fe22f24f745bbf5ee1ae33dafba1`.
