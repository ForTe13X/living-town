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

## Complete fixed-pose range

A later owned fixture evaluates all **561 original task descriptors**: 462 idle keys, 72 walk keys and 27 blend points. Each point captures the base, correction-disabled and correction-enabled players, retaining **1,683 main observations plus nine initial/repeat/return controls**. The fixture explicitly holds non-looping playback. Endpoint clip seconds are mapped through actual native clip lengths into normalized BlendSpace time; observed cache times, clips and weights must agree across all three players. These are explicit diagnostic evaluations, not natural playback.

All 561 numerical comparisons pass with the same **0.002 cm / 0.01° / 0.000001** limits. Disabled/base vertices and reconstructed-after/actual vertices match exactly. The largest enabled rigid-translation residual is **0.000008611 component cm**. Every root rotation/scale and all 60 non-root local transforms remain exact; palm-socket translation, rotation and scale checks also pass. Initial-zero, repeated-zero and reverse-order zero-return controls stay exact, with no configured-clip compression work after the loading barrier.

The native run completes in **479.266 seconds**, peaking at **5,697,101,824 private bytes**. Its bounded, single-thread CPU replay completes in **263.360 seconds**, peaking at **126,296,064 private bytes**. Both processes are reaped. Source packages, native binaries, project overlays, existing configuration and external state remain unchanged. Evidence is `native_root561_actual_v1_001` under the retained F-drive root; the preparation is `native_postroot_full561_prepare_v1_001`, freeze `ce99333a90907f5308fb288795c5cf04364b43206c631610ccd209ca391f0b20`.

Body measurements remain separate from numerical correction acceptance. At the unchanged diagnostic capsule radius/half-height **28 / 95 cm**, corrected head/neck vertices stay inside, with a worst signed distance of **−1.214 cm**. The torso group still reaches **2.133 cm outside**, and arm, hand, leg and foot extents are retained. Majority-weight sole vertices reach **−2.475 / −2.232 cm** relative to the nominal floor. These observations do not qualify collision fit, grounded feet or scene contact.

A separate bounded CPU study checks **2,045,406** head/neck and torso constraints across all corrected poses. One fixed mesh shift of **[−0.376163, +2.201438] cm** contains those sampled groups within the same R28/H95 capsule, with at least **0.1 cm** margin. The proposed total mesh XY calibration is **[−0.376148, +2.201407] cm** after including the previous tiny baseline offset. Z, stature, root correction and source clips stay unchanged. The active torso witness establishes the minimum shift magnitude for this finite clearance target. Whole-render and limb extents remain outside; sole heights do not improve. This placement proposal still requires actual native scene, continuous playback, route and contact checks. Evidence is `native_root561_fixed_xy_audit_v1_001`, freeze `f1884902845d9634ca082fc16c84fa236ae7a69952672716aeced8c9051ea784`.

The frozen CPU adapter also writes `CPU_COMPARISON_ERROR.json` containing its own successful `SystemExit: 0`; it catches that exit through `BaseException`. The actual process exits zero, the full numerical verdict passes and ownership cleanup passes. This bookkeeping artifact is retained unchanged and must not be mistaken for a failed numerical comparison. Future adapters should keep their successful exit outside that exception handler.

The separate 110 cm/s stride family, natural transitions, floor/hand/counter/route contacts, qualified physical fit, Game binding, final art and performance remain pending. The [character review](character_cafe_worker_multiview_v002.md) tracks the separate material and anatomy work.
