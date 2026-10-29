# Native post-sampling root alignment

The café worker's idle and walk clips place the body at different horizontal offsets. Reauthoring the idle root through the public animation controller preserved its intended translation but changed small parts of the evaluated pose after rebuilding derived data. Those failed comparisons remain failed. The new Unreal adapter applies alignment after the original player evaluates its pose, keeping the original mesh and clip files as the portable source.

## Runtime behavior

`ULivingTownRootCorrectedSingleNodeInstance` uses Unreal's existing single-node player and BlendSpace. Its proxy calls the base evaluation once, reads that evaluation's current public sample-cache weights, and adds `component_delta_cm * actual_idle_weight` to the parentless root translation. Every root rotation/scale and every non-root local transform stays unchanged. The weight comes from the actual player cache.

Configuration requires the same mesh skeleton, two distinct non-additive idle/walk samples, a parentless `root`, finite translation and source clips with root motion disabled. Missing/ambiguous records, unknown clips, per-bone weights, mirrors and invalid roots preserve the base pose and produce a refusal state instead of applying the correction. Configuration is copied on the game thread; diagnostic reads wait for worker completion. Cache pointers are not retained. Full pose-array capture is opt-in; the production correction step performs no JSON or UObject allocation.

An explicit consumer installs the class and calls `ConfigureRootCorrection`, passing its reviewed source assets and component-space delta. Use `bCaptureDiagnosticPose=false` for a production consumer. `GetSingleNodeInstance()` recognizes the subclass. A later `PlayAnimation` call can reset the animation class, so preserve the explicitly configured instance through its intended playback API. This change does not bind the new family into the game.

The reviewed worker delta is `[-0.45119449496269226, 10.242915153503418, 0]` component centimeters. It belongs to this source family and its scale/orientation contract; it is not a generic offset for other characters.

## Actual qualification

The adopted **66-input source digest** is `de2c8eb270d87ba8480a03ed4748bc0e113612ad8e73485051c0b0e25fdd4917`. All original 60 inputs, material safeguards, Game/café/kernel code, Build.cs files and four runtime-enable flags stay unchanged. Six additions comprise the runtime instance/proxy, editor proof reader and qualified avatar helper pair.

- The actual native Editor build passes in **151.484 seconds**, peaking at **4,168,421,376 private bytes**.
- All **ten native foundation tests** and **eleven SHA known answers** pass in **47.562 seconds**, peaking at **3,998,494,720 private bytes**.
- Five actual idle/walk/mixed controls compare the base, disabled and enabled players at matching observed cache times/weights. Disabled/base vertex differences are **zero**. Reconstructed-after skin matches all **10,707 actual native vertices** exactly. The largest enabled rigid-translation residual is **0.000004773 component cm**, within the unchanged 0.002 cm limit.
- All 61 local transforms are captured; rotation/scale and 60 non-root local translations remain exact. Initial-zero, repeated-zero and reverse-order zero-return controls are exact to the main zero pose. Position/angle/scale limits remain **0.002 cm / 0.01° / 0.000001**.

The first cold comparison differed while derived animation compression completed during collection. The next fixture finishes native asset compilation after configuring all three components and before capture. Both clips build/store derived cache data inside that barrier; source asset/package bytes stay unchanged. The effective extraction branch is not directly instrumented.

That fixture completes all **15 main plus nine readiness captures** and exact cleanup, but its 15-second control connection times out after collection. A separate CPU recovery verifies all retained files, unchanged source/staged packages, native binaries, resource limits, D3D12/SM6, two shader workers, the actual 73-character F-drive writable DDC and every skipped numerical/readiness check. The old transport FAIL stays intact. No editor rerun supplies replacement observations.

Evidence under the retained F-drive root is `native_postroot_build_actual_v1_002`, `native_postroot_tests_actual_v1_001`, `native_rootproof_actual_v1_002` and `native_postroot_proof_recovery_v1_001`. Selective adoption is recorded in `root_native_review_acceptance_v1_001/native_postsample_SOURCE_ADOPTION_v001.json`.

Full 561-pose/body-fit coverage, the separate 110 cm/s stride family, natural transitions, floor/hand/counter/route contacts, Game binding, final art and performance remain pending. The [character review](character_cafe_worker_multiview_v002.md) tracks the separate material and anatomy work.
