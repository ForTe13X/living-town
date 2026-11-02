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

## Observed validation, 2026-11-02

The complete 178-file source snapshot compiled in Unreal 5.8.4, changelist
58902052, on Windows. Five native automation tests passed with zero test errors
and zero test warnings on the AMD Radeon 8060S D3D12/SM6 device:

- `LivingTown.FullTown.TransformAndDistance`
- `LivingTown.FullTown.SubsetSchemaRefusals`
- `LivingTown.FullTown.CancelledLoadRetainsReservation`
- `LivingTown.Current61.HeadAssembly.SafeRefusal`
- `LivingTown.Current61.HeadAssembly.DeclaredShadingProfiles`

The two new subset assets were authored and read back with all 301 roles,
262 external cafe parts and ordered material slots accounted for. The 4,985
original source packages remained unchanged. This is saved-data evidence;
independent reopening and the actual movement/streaming journey must still be
completed before gameplay acceptance.

The tests exercise production validators, cancellation reservation behavior and
safe assembly refusal. They do not prove a successful animated head attachment,
physical traversal, unload/re-entry, collision coverage across the town,
character appearance, startup time, frame rate or cooked packaging. Those
remain separate checks with actual assets and runtime observations.

The Blender preview investigation also isolated a source of broad black hair
patches: the saved Cycles transparency depth was eight. Matched front/rear renders
at depth 64 removed the broad patches with the same geometry and textures,
including a neutral-emission control. That is a Blender preview finding, not an
Unreal shader or runtime-performance result. Hairline, underlayer edges, side
strands and final character art remain under refinement.
