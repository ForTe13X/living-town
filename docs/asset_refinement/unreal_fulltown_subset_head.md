# Native town subset and optional head assembly

The native source now supports an opt-in, uncooked integration map containing
three independently saved town sections around the existing cafe. It also adds
optional hair and underlayer followers for the Current61 body. Neither feature
changes the default map or automatically adopts a new character asset.

## Streaming scope

`ULivingTownFullTownData` describes exactly U0131, U0142 and ground U0151:
66, 80 and 155 static components respectively. The existing cafe owns its 262
parts separately. The descriptor rejects duplicate cafe geometry, altered
ordered material slots, missing saved-map identities, and unsupported profiles.
The initial profile rejects HISM components and a whole-town scope; the larger
vegetation import remains a separate asset qualification task.

`ALivingTownFullTownDriver` is disabled by default. An enabled driver requires
the existing cafe GameMode, a standalone uncooked world, an otherwise empty
streaming root and exact saved descriptor bytes. The subsystem loads ground
before its dependent sections, starts levels hidden, validates their components,
and waits for the engine's visible/registered state before releasing movement.
Its owned movement lock is balanced across possession because Unreal resets
input flags during that transition.

At most two level transitions may remain reserved. A cancelled operation retains
its reservation until unloading is observed. Validation has component, instance
and elapsed-time budgets; level-loading and engine registration costs still
require runtime measurement. Load/unload radii use hysteresis. Ground remains
pinned, and retiring another section requires both simple and complex traces to
show that it does not support the player. A live failure retains resident support
and locks movement; it does not pretend that world teardown has completed.

Pending tickets now rotate through one shared validation window, starting after
the owner and cafe checks. Resident sections cannot consume a pending section's
turn. A separate scan checks ticket deadlines and retirement on every tick, so
an exhausted validation budget cannot hide a timeout. Diagnostics report those
phases separately; the 1 ms validation target does not bound engine work or an
individual component check.

This implementation deliberately refuses cooked-data mode. It is an integration
step toward a streamed town, not a packaged whole-town release or evidence of
improved frame rate.

## Head assembly and editor helpers

The optional transient `FLivingTownCurrent61HeadBinding` names separate hair-card
and underlayer meshes. The existing V1-V3 file-binding parser is unchanged;
writing an arbitrary head field in a binding file does not enable this feature.
The body remains the sole pose evaluator, with two skeletal followers using its
leader-bone mapping. Assembly checks the shared skeleton and hierarchy, material
profile, render triangle count and UV channels before exposing the followers.
It refuses aliased components and off-thread mutation; a refused valid request
clears only the follower components.

Editor-only head-cap and fine-hair helpers inspect the imported render data and
request shader-resource preparation for already-saved, explicitly named
derivative materials. The fine-hair reader covers the
14,400-triangle, 61-source-joint candidate and its finer UV atlas. Its two-map
Default Lit material uses pigment/coverage and a tangent-space normal map, with
the declared normal convention and alpha threshold. These helpers do not run in
the game target or repair original materials at runtime. Their named candidate
packages are not supplied by this source change.

The fine-hair preparation helper requires an isolated Editor startup profile
with `r.ShaderCompiler.JobCacheDDC=0`, enabling complete material-map compilation
for that process. It reads the policy before requesting work and never changes
the console variable itself. The intake profile affects all materials loaded by
that Editor process. Both fine-hair and head-cap readiness checks require
successful, finalized compilation in addition to their resource checks.

## Observed validation, 2026-11-02

The earlier 178-file source snapshot, including the scheduling and
shader-readiness corrections, compiled in Unreal 5.8.4, changelist
58902052, on Windows. Six native automation tests passed with zero test errors
and zero test warnings on the AMD Radeon 8060S D3D12/SM6 device:

- `LivingTown.FullTown.TransformAndDistance`
- `LivingTown.FullTown.SubsetSchemaRefusals`
- `LivingTown.FullTown.CancelledLoadRetainsReservation`
- `LivingTown.Current61.HeadAssembly.SafeRefusal`
- `LivingTown.Current61.HeadAssembly.DeclaredShadingProfiles`
- `LivingTown.FullTown.FairValidationBudgetAndDeadlines`

The two new subset assets were authored and independently reopened with all 301
roles, 262 external cafe parts and ordered material slots accounted for. The
reopen check made no saves and preserved all 4,987 input packages, including the
two new subset assets. This is saved-data evidence. After the scheduling fix,
Runtime003 reached all three resident sections in 11.69 seconds from native
streaming activation and completed a 15-waypoint scripted route with grounded,
walkable simple and complex footing traces. Its separate physical-input phase
timed out with zero recorded displacement, so the overall run remains failed.

Runtime004 made the navigation view readable with one diagnostic sun and an
explicit transient camera exposure range. Its recorded source camera used the
legacy maximum luminance of 8; the diagnostic override used 20,000 with zero
exposure bias. The exterior plaster, door frame and character became visible,
although the interior still needs lighting work. The manual phase later failed
with Windows `Access is denied` while replacing its frequently updated progress
JSON; a concurrent reader can prevent that replacement. This is a test-observer
failure, not a successful movement check. Runtime005 corrected the observer with
append-only progress logging, but its manual-input phase timed out without
movement. These diagnostic settings do not change the saved town maps.

Runtime009 completed the route and an automatic held-input check through stock
EnhancedInput `Input.+key W` and `Input.-key W` commands. The request lasted
1.011 seconds, with 65 observed held frames spanning 0.991 seconds, 175.79 cm of
horizontal movement and two subsequent released frames. The character remained
grounded on walkable, source-bound terrain with simple and complex footing
traces. No direct movement or transform setters ran during that input phase.
There was one explicit release; the process exited with code zero, all owned
processes were reaped and all five closing guards passed. This checks synthetic
engine input, with no OS or physical keyboard claim. The stock release also
flushes pressed keys on the isolated test controller. It changes no saved input
settings. The view still has an overly dark interior.

The corrected Runtime005 CSV covers all 675 route frames at 1920x1080:
14.30 ms mean, 15.35 ms p95 and 68.59 ms maximum frame time. This short
three-section observation may include background compilation and does not
qualify whole-town or production performance.

The tests exercise production validators, cancellation reservation behavior and
safe assembly refusal. These six tests alone do not prove successful animated
head attachment. The later diagnostic below supplies a separate, bounded
idle/walk observation. OS keyboard handling, whole-town unload/re-entry and collision coverage,
final character appearance, startup time, frame rate and cooked
packaging remain separate checks.
Repository CI passed all nine checks at documentation commit `d425460`, which
retained the qualified native source.

Fine009's saved 29-package closure also passed an independent fresh-process
reopen check. Geometry, skin, UV/tangent basis, the saved material graph and
byte-exact source texture pixels passed; source and staged packages each
retained their own byte and modification-time baseline. The material's own
shader resource was complete, finalized and successful without fallback, with
global compilation idle. This establishes saved data and resource readiness.
The later diagnostic below supplies two rendered frames and selected animated
follower observations. Whole-mesh GPU skinning, physical contact, production
activation and final appearance remain pending.

The Blender preview investigation also isolated a source of broad black hair
patches: the saved Cycles transparency depth was eight. Matched front/rear renders
at depth 64 removed the broad patches with the same geometry and textures,
including a neutral-emission control. That is a Blender preview finding, not an
Unreal shader or runtime-performance result. A separate Blender copy now saves
that GPU preview profile and passes independent reopening and eight matched
renders covering front, side, three-quarter and rear views. Hairline, underlayer
edges, side strands and final character art remain under refinement.

## Native118007 diagnostic head check

A later qualified snapshot contains 180 source files, including 131 native
build inputs. Its Editor Development build completed in 383.844 seconds with
all nine closing guards passing. The same six native regressions completed in
32.125 seconds: six successes, zero test errors and zero test warnings. Two
unrelated engine warnings were retained; this is not a zero-warning engine log.
The repository's complete 131 native inputs match that build's source family,
`4ea6ade4953a5f3e4e72e49640e4fd7e86f0c5ff459205817aa6a79290a53d1c`.
The new source adds the development observer and its private RHI dependency;
the two inspection-source newline changes preserve the qualified file bytes.
The earlier 178-file observations retain their original scope.

The observer creates a transient body and two head followers through the
existing production `Configure` function. It applies the body's eight saved
baked materials as component overrides after checking their ordered imported
slots. Serialized mesh defaults and saved assets remain unchanged. One body
animation player evaluates the idle and walk clips; the followers retain their
leader pose and have no independent animation instances.

The actual uncooked diagnostic closed successfully after 57.938 seconds, with
all owned processes reaped and all five closing guards passing. It recorded
32 natural samples across idle and walk, compared every name-resolved follower
bone with its body leader, and observed nonconstant motion in both followers.
Across 512 selected point observations, CPU linear-skin reconstruction differed
from stock component selected-vertex readbacks by at most 0.000359236 mm
(the existing budget is 0.01 mm). No forced pose evaluation or whole-mesh GPU
readback was used. This result establishes those sampled follower relationships,
not full GPU deformation or physical contact.

Both actual idle/walk PNGs were reviewed. Character art remains held: the hair
is a compact near-black shape with a straight fringe, the shirt/apron lack
convincing fabric detail, and upper-chest folds need repair. An unrelated Entry
sphere intrudes into the view. Front/rear views are still missing. Cap raw
independent Cold is **UNOBSERVED**. The preview used a warm cache from the
qualified Cap004 author run, so its duration is not a cold-start benchmark.
Unrelated EditorToolset Python startup errors were observed and retained; no
zero-runtime-error claim is made.

Activation requires the explicit `-LivingTownHeadFollowersProof` flag,
`LT_HEAD_FOLLOWERS_PROOF_ROOT`, and the exact
`-LivingTownHeadFollowersProofSHA=<manifest SHA256>` argument in an isolated
owned Game world. `-LivingTownHeadFollowersArtPreview` selects the diagnostic
author-only cap mode and preserves its missing-Cold status. Shipping/Test
subsystem creation and commandlets are refused. The observer's transient camera,
lights, components and output handling are development tooling; these switches
do not activate a production avatar or change the saved town's presentation.
The required host/manifest/assets are not bundled by this source change.

The [sanitized source, build, test and capture evidence](evidence/native118_head_followers_diagnostic_v001.json)
binds the actual artifacts and their limitations. Full-town residency and unload/re-entry, production character integration,
final hair/skin/fabric art,
whole-mesh GPU skinning, contact, FPS and cooking/packaging remain unqualified.

## Native118004 subset retirement and reentry

The uncooked three-map subset completed an actual 215.843-second host run with natural exit code 0, every owned process waited/reaped, and all five closing guards passing. Independent closed-data replay verified the original source, all 4,987 source packages and their staged copies, private configuration, captured global custody, and complete lifecycle/query/sample associations. The run uses Native118004 family `9d1e11b86ab484399aca53b894b25cb2e78ae27e35b106ed2ddfd6c1e2941e5f`. Its six production FullTown source files match the current implementation byte-for-byte. The complete 004 and 007 build families differ; this result does not claim full source-family equivalence.

The scripted route used ordinary `AddMovementInput` with `force=false`, controller yaw and natural character physics. It travelled 171.195 m horizontally over 151.830 seconds of world time, with 10,047 grounded/walkable samples and actual simple/complex support checks throughout. No pawn transform, floor, speed, radius or streaming-state setters were used. It returned within 1.878 cm of the source café spawn. This is a normal-movement harness observation; OS keyboard handling remains separate.

| Observation | Active source roles | Native ticket tokens |
| --- | ---: | --- |
| Initial and outward hysteresis | 301 | U0131:2, U0142:3, pinned U0151:1 |
| Far retirement and return through hysteresis | 155 | pinned U0151:1 |
| Reentry and café return | 301 | U0131:4, U0142:5, pinned U0151:1 |

All six ordered milestones retained 262 café parts. The peak transition reservation count was two. Each original section produced an actual HIDDEN callback and a native terminal `Removed` snapshot with no loaded level. A window of 134 frames then recorded 2.001 seconds of world time and 2.001 seconds of QPC time with the old levels null, loaded/visible/pending flags false, both old instances absent from World streaming lookup and actor roster, no reservations, and the same pinned section's exact 155-role roster. The pinned section comprises 154 terrain meshes and one ocean context role; pedestrian support checks rejected the ocean plane.

`OnLevelUnloaded` recorded zero callbacks for both retired instances and remains **NOT_OBSERVED_NOT_PROMISED_AFTER_REMOVAL**. Installed engine code broadcasts that notification during conditional/delayed GC preparation through streaming objects still in the World array; it is not a required recipient event after removal. No callback was invented. A direct post-removal state getter is nonreflected; actual terminal `Removed` snapshots and current null-level/World-absence readbacks establish this scoped retirement observation. Package GC and physical memory release remain unobserved.

Reentry loaded and validated both sections under new tokens, restored all 301 unique source roles without duplicate ownership, retained the pinned token, and returned to the café. The descriptor and native retirement/support/cancellation/deadline policies were unchanged. This profile exercises three static-only maps and the external café. It does not qualify HISM lifecycle, all 193 maps, whole-town collision coverage, cooking/packaging, final appearance, production avatar activation, GPU/render quality or performance.

The [sanitized lifecycle evidence](evidence/native118_subset_lifecycle_v001.json) binds the actual source/build/test/capture artifacts and the independent review's scope.
