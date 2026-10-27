# Native café projection

The adopted C++ source passes the first actual café walk/lease/end/ledger journey. It does not complete the town, full-world saves, final art or the broader simulation roadmap. The content closure and a readable software-Lumen map are prepared; fresh normal-game startup remains the delivery gate. Global default GameMode activation stays deferred. The successful journey uses an isolated project and private configuration.

LivingTownNative contains the character, controller, venue, HUD and projection subsystem. The lease subsystem remains the sole lease-state writer around the byte-exact frozen portable kernel. Its loader additionally rejects a restored active lease whose clock has reached its end. LivingTownMaterialInspection is editor-only and contains graph inspection plus explicit motion-asset derivative authoring. InputCore and the engine's bundled static OpenSSL support the runtime code.

The adapter requires a strict fourteen-field Content/LivingTown/CafeProjectionBinding.json, exactly 289 source IDs (8534–8822), exact floor/counter membership and matching full native render-buffer hashes/collision GUIDs. Ben needs his actual skeletal visual, hand bone and same-skeleton idle/walk BlendSpace. Runtime sampling must return the correct idle/walk weights at zero, half and full walking speed. Missing interpolation data refuses before possession and resolver installation.

WASD/mouse drives CharacterMovement and a collision-tested spring arm. E/R submits intent only; possession, café-floor contact, facing and fresh hand/head queries determine reach at command time. Static props do not tick. Display affordances refresh at roughly 10 Hz, and HUD strings rebuild on state changes. All 289 meshes preload before one bounded editor compilation wait; full mesh hashes, GUIDs and collision checks remain mandatory. Explicit EnhancedInput classes preserve the original six mappings and prevent automatic editor config rewriting.

F5/F9 saves/loads the café ledger. Its outer journal binds the physical scene, actual binding-file SHA-256, qualification and visual identity around the unchanged strict inner journal. Loading preserves current physical position. Legacy whole-world saves refuse. Local Windows NTFS/ReFS slot replacement verifies a temporary file and replaces within the same directory; a locked destination preserves the previous bytes. Other backends remain unqualified.

## Actual validation

The original runtime integration build002 compiles both editor modules with UE 5.8.4 / MSVC 14.44 in 71.28 seconds. Hardware test004 passes these four tests with zero test/engine warnings or errors in 24.34 seconds; the latest source/build qualification is recorded below:

- LivingTown.Native.CafeLeaseBoundary
- LivingTown.Native.CafeBindingRefusals
- LivingTown.Native.CafeProjectionJournal
- LivingTown.Native.CafeAtomicSlot

Eleven actual native SHA-256 outputs independently match Python hashlib, including UTF-8, binary, padding boundaries and million-byte/multiblock inputs. Sixty host source/staging checks pass against the adopted canonical sources without launching an engine.

LivingTown.Native.CafeActualWalkLeaseJourney passes in the separate hardware run002. It walks the real CharacterMovement route and checks source/Ben/camera identity, far and occluded refusals, reachable lease/end, conserved payments, ledger replay, invalid-save atomicity and unchanged physical position. Its 58 moving samples have 57 animation-time changes and fresh evaluated limb poses throughout. Independent readback also finds 20 distinct poses and 19 time changes in the final 0.95 seconds of captured movement. The test neither teleports the character nor forces animation ticks. This proves the captured route, not off-camera policy, all clips or final animation quality.

The motion authoring run002 preserves all original 404 asset files and saves one resampled BenIdleWalk_v002 derivative. The resulting 405-file closure is used by the successful walking test. The authoring log retains exactly one mandatory installed MCP notice; every other warning/error rejects. Boundary and walked tests have zero warnings/errors. All source, staged-input, original-config, private-archive and original-editor guards pass; owned processes are reaped.

Evidence under F:/Living Town/2026-10-20_Refined_Town:

- native_cafe_runtime_integration_build_actual_v1_002/BUILD_RECEIPT.json
- native_cafe_authority_tests_actual_v1_004/RUN_REPORT.json
- native_cafe_motion_asset_actual_v1_002/MOTION_AUTHORING_OWNERSHIP.json
- native_cafe_journey_actual_v1_002/RUN_REPORT.json
- native_cafe_walked_qualification_actual_v1_001/QUALIFICATION_RECEIPT.json
- native_cafe_runtime_source_adoption_actual_v1_001/ADOPTION_RECEIPT.json
- native_cafe_runtime_adoption_host_tests_actual_v1_001/REPORT.json

Build/stage commands are in [the Unreal README](../../unreal/README.md). The qualified binding remains in native_cafe_runtime_binding_actual_v1_002; it is not fabricated into canonical content. The [content delivery tool](unreal_cafe_content_delivery.md) packs, verifies and restores the closed asset set. Permanent authoring-recipe integration remains open.

## Current source and startup fixes

Source digest `714bf85459d1667641fa82253056d7ada09407528ed7202c4be50d71335b8a94` includes the compact HUD and two review fixes. Loading an active lease now rejects clocks at or beyond its end before swapping state; the regression compares clock, event count, digest and balances after refusal and retains genuine pre-expiry and expiry-event round trips. The frozen kernel is unchanged. Ordinary editor startup skips the authoring telemetry bootstrap when its owned output directory is absent; explicit automation requires an existing absolute directory before registering tools.

The matching native_cafe_review_fixes_build_actual_v1_001 build passes in 71.828 seconds; BUILD_RECEIPT.json SHA-256 is `9118799315478865ea6d9d406431133632d290eabd7f160b4ab59ffc22efe54f`. Actual authority run005 passes all four native tests and eleven SHA-256 known-answer comparisons in 24.328 seconds with zero warnings/errors. The three-file canonical adoption then passes 60 host source/staging checks. Actual Lumen capture003 uses this same build and passes its material/resource/player-frame qualification. All source/configuration/private archive/original editor guards pass and owned processes are reaped. The earlier walked journey remains separate evidence; these review fixes do not constitute another walking run.

The content packer also binds the selected map's successful native bootstrap to the advertised source digest and exact build receipt. A mismatched map/build pair refuses before packing; nine CPU tests cover the tool, including that refusal. The ZIP contains assets and provenance only. Native modules and the qualified Unreal installation are supplied separately. A normal-game launch from a fresh restored project is still required before calling that combination runnable delivery.

## Startup observation

| Venue phase | Earlier individual readiness waits | Bounded batch readiness |
| --- | ---: | ---: |
| Total | 8.444 s | 3.786 s |
| Asset load | 1.602 s | 3.664 s |
| Inspection, including any implicit waits | 6.739 s | 0.006 s |
| Explicit batch readiness | Not separated | 0.103 s |
| Registration | 0.103 s | 0.013 s |

These are one fresh private-DDC editor observation each with the same 289 source asset bytes, full hash contract and hardware. OS/file/driver caches are uncontrolled. The earlier inspection interval includes 114 individual readiness waits and fresh derived mesh builds; it is not SHA-256 time alone. Packaged startup, representative walking/action performance and the full-town budget still need measurement.

## Instrumented café baseline and presentation

The current-provider native idle capture002 records 611 real editor/PIE frames over 10.209 world seconds on Radeon8060S D3D12/SM6 at1014×550. Raw frame p50/p95 is16.6668/16.67245ms; GameThreadTime is6.3945/7.5406ms; GPUTime is2.2651/2.4673ms. One frame exceeds33.333ms and none exceed50ms. Render/RHI timing columns and all samples remain in the raw CSV. These thread times overlap and are never added. The35MB local trace and1.24MB CSV total36.1MB. This is an instrumented idle editor workload with globalGI0, not a full-town, walking, packaged-game or improvement measurement. Source inspection attributes the near60Hz editor pacing to this installed engine's battery-presence cap: Windows reports battery present even on AC, and the actual Lumen runs observe r.DontLimitOnBattery=0 and r.VSyncEditor=0. No global pacing or power setting is changed.

Actual lighting capture001 exposes a white-clipped world and is rejected. Capture002 uses explicit Manual physical-camera exposure atEV13.5 and is readable but dark; final art remains rejected. A compact cached C++ HUD and an actual controller pitch of-12degrees improve the presentation in capture004. Font legibility and duplicate-hint refinements pass actual capture005; the tested three-file display-cache/HUD update is adopted with a matching71.28s build and60host staging checks. Authority, old status text and the default GameMode remain unchanged. All real captures preserve original assets/configuration and reap owned processes; original editor19740 remains untouched. Saved lighting002 also retains a positional-Rotator sun-axis error, now disclosed in actual readback; its correction belongs to a new lighting derivative.

Evidence: native_cafe_gameplay_perf_actual_v1_002/ACTUAL_RAW_CPU_GPU_READBACK.json, native_cafe_lit_presentation_actual_v1_002/ROOT_VISUAL_REVIEW.json and native_cafe_lit_presentation_actual_v1_004/ROOT_VISUAL_REVIEW.json under the same F-drive evidence root. Performance capture001 fails before sampling because of a tuple dictionary key and is preserved; capture002 corrects that host-tool bug without changing quality or thresholds. Composed capture003 fails because Unreal's positional Rotator constructor maps Roll/Pitch/Yaw; keyword construction and actual angular readback fix capture004.

## Asset scope and retained failures

Imported café geometry preserves all 33,850 nondegenerate source triangles, normalized normals, UV0 and material association. Exactly 1,000 zero-area source triangles are omitted; the strict full-source comparison remains failed with a separate narrow qualification. Café-only Nanite fallback reduction is disabled. Three untextured decorative meshes retain degenerate UV/tangent defects and need refinement.

Ben's eleven-part visual imports on one seventeen-bone skin with seven source clips. His reference visual measures 180.84 cm and fits the radius-28 cm / height-190 cm capsule vertically. Separate static queries verify 289 transforms/collision identities, two clear route sweeps, three endpoints and 27 correct-floor hits. Corrected counter targeting gives first hand/eye hits on the counter at 51.17 cm hand proximity against the unchanged 70 cm bound. This is proximity, not a finished hand-contact animation.

Earlier failures remain preserved: the generic engine SHA hook crashes; the initial stronger walking test detects fixed-pose sliding; raw BlendSpace samples lack runtime interpolation; and automatic input/plugin configuration writes violate staged-byte guards. The new editor helper duplicates/resamples only the named new motion asset, while runtime code only validates existing data. Its first compile also exposes a local Serialize name hidden by UObject::Serialize; the narrowly renamed helper compiles in the qualified build. No test threshold or source-geometry requirement is weakened to turn those failures into passes.

Software-Lumen captures002 and003 use a new map derivative with corrected sun pitch/yaw, actual down12 controller look and manual physical EV11.5 exposure. The actual material census matches all289 components:283 opaque meshes have distance fields; the six source-translucent glass meshes are explicitly ineligible, preserving their source materials. All eleven eligible critical meshes have distance fields. Trial001's original twelve-piece rule and parser failure remain failed evidence. Its replacement uses reflected resolved material modes and the installed engine's translucent exclusion, without weakening opaque coverage. Root inspected the actual capture003 player PNG and accepts a bounded readable café daylight baseline; character and interior materials still need final art work. Single instrumented Lumen GPU events establish execution only, not sustained performance.

Final character/interior art, cooked shipping collision, off-camera/all-clip behavior, normal restored-project startup, full-town streaming and simulation, narration and GIF replacement remain open. PR90 delivers a bounded native foundation rather than completion of the active town goal.
