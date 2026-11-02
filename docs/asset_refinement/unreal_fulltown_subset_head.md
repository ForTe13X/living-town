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

The complete 178-file source snapshot, including the scheduling and
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
failure, not a successful movement check. A fresh run with progress logging
that permits concurrent reads is still required. These diagnostic settings do
not change the saved town maps.

The tests exercise production validators, cancellation reservation behavior and
safe assembly refusal. They do not prove a successful animated head attachment,
physical traversal, unload/re-entry, collision coverage across the town,
character appearance, startup time, frame rate or cooked packaging. Those
remain separate checks with actual assets and runtime observations.
Physical keyboard movement and unload/re-entry still require successful live
checks. Repository CI passed all nine checks at source commit `b536ccd`.

The Blender preview investigation also isolated a source of broad black hair
patches: the saved Cycles transparency depth was eight. Matched front/rear renders
at depth 64 removed the broad patches with the same geometry and textures,
including a neutral-emission control. That is a Blender preview finding, not an
Unreal shader or runtime-performance result. A separate Blender copy now saves
that GPU preview profile and passes independent reopening and eight matched
renders covering front, side, three-quarter and rear views. Hairline, underlayer
edges, side strands and final character art remain under refinement.
