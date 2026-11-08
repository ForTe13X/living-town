# MetaHuman meal physical source v2

The root admitted one actual native meal journey and the separate strict parser
test on 8 November 2026 UTC (7 November local time). The 034 Game/Editor pair
compiled source `509951c52382ca0e564ecb93a8990dad7e5efbdb`, native family
`b7c34fccd86024019f8bf0029f097c3ec4a3466a69e82f1beddbb7d047c1976f`.
The admitted scope is natural native input, playback ownership and authoritative
meal state; rendered contact and final art remain open. See the actual results
below and the [small evidence index](../evidence/metahuman_meal034_semantics.json).

The WorldV3 owner configures the physical source only with verified external v2
files and preloaded roles. No recipe, certificate or calibrated binary asset is
shipped in this repository. Missing or unqualified inputs retain the default
MetaHuman refusal and hide E. The legacy v1 provider remains separate; the
financial/care cores were not changed for the 034 validation.

`ULivingTownMetaHumanMealProducer` observes one owned bread component and the
original Assembly Body/Face/Outfit. It never creates a second animation player,
sets a pose/curve/time, refreshes bones, calls a needs API or grants progress.
The prerequisite calibration supplies verified assets and native pose/spatial
anchors. It never pre-certifies natural playback, lip collision or grants.
Those claims still require the independent live runtime observations and root
review. Duration and phases come from the verified calibration certificate, so
retiming does not require another hardcoded C++ duration.

## Files and trust boundary

`FLivingTownMetaHumanMealRecipeV2::ReadQualified` accepts a Content-relative
JSON recipe. It reads and hashes the same recipe buffer that it parses, checks
the actual certificate's bytes and SHA-256, then checks all declared package and
proof files. Package aliases are checked for identical bytes/hash and hashed
once per configuration. This uncooked loose-package route refuses missing
files; it does not waive hashes for a cooked build.

The owner verifies optional v2 files once during scenario preparation and starts
an owned asynchronous Streamable role preload. Other session/game operations
continue while meals remain unavailable. A weak owner/epoch guard cancels stale
completion on persona change/teardown. The handle survives until the producer's
strong role references exist. The private owner-only `ConfigureVerified` seam
accepts that cached `ReadQualified` result without another large file hash pass.
Public `Configure(file)` shares the same final configuration after independently
verifying its file input; it cannot reconfigure an existing producer.

The optional owner entry is `Content/LivingTown/MetaHumanMealContactV2.json`.
Legacy `Content/LivingTown/CafeWorldV3MealContact.json` remains a separate v1
source; staging a v2 capability must never replace it.

Final configuration only resolves already preloaded UObjects, checks exact object paths,
skeletons, nonadditive/root-motion-free clip, duration, ordered bread materials
and complete used-texture roster, and caches strong object references. It does
not reload a package whose UObject was already resolved. Preload and source
immutability therefore remain the root-owned host's responsibility. SHA/status
strings alone are not qualification: actual files and the loaded/live physical
observations must all agree. Root admissions are trusted local source records,
not signed or adversarial cryptographic certificates.

Startup performs file verification, hashes and texture enumeration once. Active
frames use the cached role map and component/player references, bounded grip
and material comparisons, station queries, pose revisions, time and curves.
There is no per-frame package hashing, load, asset or component enumeration.

There is deliberately no public/Blueprint setter for a qualifying boolean.
Only the friend `ULivingTownCafeWorldV3Subsystem` can bind the private
`BindTrustedSessionObserver` callback. The owner continuously checks its actual
SessionPawn/controller, active reserved use/grant, current rights and
eligibility, including the no-grant exit policy. The callback must
be read-only and must not mutate or stop the producer while it is observing.
The owner now wires this check to its real SessionPawn/controller, exact active
reserved grant and current operator. Its cached grant index is revalidated by
event/request identity, avoiding per-frame grant scans. The no-grant tail only
accepts the exact completed 18-tick release, not an active or cancelled grant.
Cached presentation flags are additional diagnostics and cannot replace this
authority observation.

## Exact JSON contracts

All keys below are required; additional or duplicate keys, nonfinite/fractional
integer values, zero hashes, absolute/traversing paths and unspecified anchors
are refused. Hashes are 64 lowercase hex characters. Versions are JSON strings.
Scalar helpers require actual JSON string/number types before UE conversions:
numeric versions and quoted numbers are refused rather than coerced.
Recipe/certificate/proof files are at most 128 KiB; package roles at most 512 MiB
each. JSON path references are contained Content-relative `.json` paths.

The recipe has exactly eight keys:

| Key | Required value |
| --- | --- |
| `format`, `version` | `LivingTown.CafeWorldV3.MealContact`, `2` |
| `binding_sha256` | Current cafe binding file hash |
| `visual_descriptor_sha256` | Exact current v2 actor descriptor hash |
| `source_closure_sha256` | Descriptor's admitted source closure hash |
| `certificate_file`, `certificate_bytes`, `certificate_sha256` | Actual accepted certificate file |

The certificate has exactly fifteen keys: `format`, `version`, `status`, the
three binding hashes above, `assets`, `proofs`, `bread_materials`, `bread_bitten_materials`,
`bread_textures`, `anchors`, `station`, `timing`, `jaw`.
Its format/version/status are `LivingTown.MetaHumanMeal.PhysicalCertificate`,
`2`, `ROOT_ACCEPTED_NATIVE_POSE_CALIBRATION`. Pending or generic acceptance
statuses are refused; the calibration status does not bypass any live guard.

`assets` rows contain exactly `role`, `asset`, `bytes`, `sha256`. Paths must be
full top-level object paths under `/Game/` or `/MetaHumanCharacter/`. Required
roles are `actor_class`, `clip`, `body`, `face`, `outfit`, `body_skeleton`,
`face_skeleton`, `bread`, `bread_bitten`, `body_post`, `face_main`, `face_post`, plus exactly one
`bread_material/N` per Whole material slot, `bread_bitten_material/N` per Bitten
material slot and `bread_texture/N` per unique texture. Each ordered material
roster has 1–8 paths and preserves repeated slots independently. `bread_textures`
is the exact unique union of both variants' used textures (1–32 paths). Required
role count is twelve base roles plus both material counts plus the texture-union
count. No fixed third material slot or shared material identity is assumed.
Body/Outfit/clip share the declared Body skeleton. Face is checked against its
own declared skeleton; the two skeleton paths may alias with identical bytes.
Whole and bitten bread must be distinct actual meshes with the same explicit
grip. Each mesh is checked against its own ordered materials; live prop checks
select that variant's exact slot count, role prefix and material identities.
Both packages and every material/map in the union are verified and loaded.

`proofs` has exactly the distinct `jaw`, `grip`, `bite` rows, each with `kind`,
`file`, `bytes`, `sha256`. Each actual proof JSON has exactly `format`,
`version`, `kind`, `status`, `binding_sha256`, `visual_descriptor_sha256`,
`clip_sha256`, `bread_sha256`, `native_pose_samples`. Values must use format
`LivingTown.MetaHumanMeal.PhysicalProof`, version `1`, status
`ROOT_ACCEPTED_NATIVE_POSE_CALIBRATION`, matching roles/bindings and at least
two actual native pose samples. The root must supply and review that underlying
calibration evidence;
the producer independently observes the live action rather than replaying
these proof summaries as contact.

| Object | Exact fields and bounds |
| --- | --- |
| `anchors` | `hand_body_bone`, `mouth_face_bone`, `jaw_face_bone`, `jaw_parent_face_bone`; `grip_relative`; `food_bite_point_cm`, `mouth_offset_cm`; `transform_tolerance` >0 and ≤0.01; `max_bite_distance_cm` >0 and ≤15; `holding_probes` |
| `grip_relative` | `translation_cm` finite xyz, `rotation_xyzw` normalized quaternion, `scale` positive finite xyz |
| `holding_probes` | 2–8 distinct Body bones; each row exactly `body_bone`, `food_point_cm`, `max_distance_cm` (>0 and ≤30) |
| `station` | `feet_cm`, `counter_point_cm`; `radius_cm` (>0 and ≤500), `height_tolerance_cm` (>0 and ≤100), `facing_min_dot` (0–1) |
| `timing` | `duration` (1–120 s), `bite_start`, `bite_end`, `min_bite_span`, `min_bite_samples` (integer 2–120), `chew_start`, `chew_end`, `tail_start`, `first_progress_delay` (1–5 s), `max_frame_gap` (>0 and ≤0.25 s), `time_error` (>0 and ≤max frame gap) |
| `jaw` | `curve`, `min_bite_value` (>0 and ≤10), `min_chew_curve_delta` (>0 and ≤10), `min_chew_jaw_degrees` (>0 and ≤180), `max_chew_static_span` (at least max frame gap, at most 1 s and the chew duration), `curve_tolerance` (>0 and ≤1) |

Timing requires a nonempty bite interval/span, then a nonempty chew interval,
then an exit starting no earlier than chew end and strictly before clip end.
These parser ceilings are finite refusal limits, not recommended calibrations.
All actual values must come from the bound native evidence, including whether
the chosen tolerances remain valid at the observed frame rate.

## Natural physical observation and cancellation

Start resolves the original Assembly parts once, verifies the actual Body hand
bone and Face mouth/jaw/parent bones, exact Face ABP/post-process instances and
Outfit leader, then attaches one collisionless bread component using the
certified transform. Assembly `BeginActionClip` owns playback on its original
single-node player. The source keeps a continuous grounded/facing/eyes-to-counter
station test; it does not require the raised hand to remain at the counter.
Initial entry reach/rays and paid reservation remain the existing authority's
upstream responsibility.

Observation ticks in `TG_PostUpdateWork` with Body and Face tick prerequisites.
Both actual `OnBoneTransformsFinalized` callbacks must occur in the current
`GFrameCounter`, and both bone revisions must advance. UE's skeletal completion
task participates in the tick completion handle; the finalized callback runs
after evaluation and animation notify dispatch. No socket is read as fresh
merely because a component tick was requested.

Finalized observers are installed at configuration and remain prewarmed between
uses. Start may occur before or after animation ticks, so Entry can supply a
separate holding-only observation from the actual current naturally finalized
Body/Face transforms and unchanged grip probes. This may still be the prior idle
pose: it qualifies holding only if the real fingers/food/station measurements
pass. Attachment or a new clip alone never qualifies it. Entry always clears
bite, first-progress and consumption flags. The source still waits at most the
certified `max_frame_gap` for a later naturally finalized, advancing frame to
anchor playback time; only subsequent frames prove motion. No clock reset,
timewarp, forced evaluation or invented holding bridges this boundary.

Every sample also requires unpaused standalone ownership, advancing real world
and clip time with the certified gap/error bounds, original player/asset/rate,
Face ABP/post-process/Outfit leader, exact bread identity/materials/grip and
fresh Body/Face curve values matching the bound clip's curve at the actual
playback time. The chew phase also rejects a curve or parent-relative jaw that
fails to show the certified movement amplitude within `max_chew_static_span`;
an early movement sample cannot qualify a later frozen jaw. Holding probes compare actual Body finger/hand
bones with measured points on the owned bread. Mouth contact uses the actual
Face anchor and actual bread bite point, not `ACharacter::GetMesh()` or the
Body's neck/head bones. During the bite interval, every sample must meet the
explicit contact and jaw bounds until the bite latch; latching requires a measured
multi-frame span. Only after that actual latch and `clip_seconds > bite_end`
does the component swap its own Whole mesh to the qualified bitten mesh. The
removed Whole-tip point is not claimed as continuing bitten-mesh mouth contact.

Before this latch, `bFirstProgressEligible` and `bConsumptionPhase` are false.
They also remain false until the certified real-time delay has elapsed and
natural Body/Face curve variation plus Face parent-relative jaw rotation have
actually been witnessed in the chew interval. They are false in the exit.
These flags are physical observations only: this component cannot grant needs
and does not know how many care increments were applied.

`ReadLatest` accepts only a still-active current-frame sample, rechecks live
identity/prop and unchanged sampled revisions/time, and clears its output on
refusal. The owner consumes after this producer and uses a frame
stamp at most once. Explicit stop, failure, pause/stale pose, action takeover,
end play and normal clip completion invalidate all latest benefit evidence.
Use cleanup destroys only its own bread and invalidates observations. Teardown
also removes this component's persistent pose delegates/prerequisites;
Assembly restores only a still-owned same-player/clip action. A foreign player's
asset is never overwritten. No physical observation is saved or restored.

## WorldV3 composition

The admitted 034 fixture uses the root-adopted held-pose calibration and actual
22-role closure, including the distinct Whole/OneBite bread materials and eight
maps. Its 24.5-second action is
`/Game/LivingTown_UEPilot/MetaHumanFinalMealCandidate_v003/AS_EatBread_24p5_Candidate.AS_EatBread_24p5_Candidate`,
3,761,145 bytes, SHA256
`67a9470c7eb4d7f23bf7ab83fa78dc0846d3a8dbba905d513a6f484c22ec66b5`.
Held-pose calibration remains the source of the measured anchors and finite
thresholds; the successful natural journey supplies separate live observations.
Neither establishes finger-pad or lip-surface collision or final animation art.

The owner uses `OnWorldPostActorTick` (UE 5.8 `LevelTick.cpp:1906`), after
`TG_PostUpdateWork` and tick task completion. Its ordinary subsystem Tick runs
too early (`LevelTick.cpp:1821`) and therefore only handles paused cleanup for
this family. Each natural frame is processed once; the global clock remainder
is neither reset nor stretched. The actual calibrated first eligible sample
must fit the care core's maximum five waiting
ticks for every admitted global-clock remainder, including the initial idle-to-
action holding transition. E retains the original floor/hand/eye entry reach.
The unchanged core stages the exact price, stock and reservation; the owner
publishes that real grant for physical start within one game-thread transaction
and rolls both books back if start refuses. Continuous use instead checks the
measured feet/facing/eyes station and actual grip; the raised hand need not stay
at the counter. Before the first eligible bite-plus-delay/chew sample it applies
only bounded zero-benefit waiting with ordinary needs decay. Afterwards it uses
eighteen ordinary increments, at most one per fresh frame/tick. Budget/rights/
contact loss interrupts with decay; no fallback contact earns benefits.

Completion releases the reservation once and leaves only a bounded visual tail
on the same owned clip/prop, with normal idle needs decay and no grants. X,
movement/action loss, pause, unpossess/persona change and successful load stop
owned food/action. Saved physical observations, the tail and preload handles
are never resumed. F9 retains replayed earned progress and releases loaded use.
Recipe SHA binds the full certificate/role/proof closure into current paired
save sources; adding/changing this capability does not waive old source checks.
No global clock, animation rate or core increment count is changed to fit a clip.

`LivingTown.WorldV3.MetaHumanMealV2Parser` provides C++ parser controls
for strict recipe/certificate fields, aliases/order, absent calibration,
traversal/duplicate keys, zero hashes, phase bounds, and refusal without real
files. Its synthetic fixture is intentionally not a physical qualification
artifact. It passed separately under NullRHI on the actual 034 Editor build.

`LivingTown.WorldV3.MetaHumanMealJourneyInput` is the one focused real-input
fixture. It requires a fresh private Entry PIE, `-LivingTownCafeWorldV3`, the
qualified `-LivingTownMetaHumanBen=<descriptor>`, `-CafeWorldPersona=ben` and
`-LivingTownMetaHumanMealJourney`. It uses ordinary owner preload (no test asset
loading), real controller W/E/F5/F9/X and natural frames. It walks to the
certified station, starts E near a clock boundary, verifies paid zero-benefit
waiting, saves/cancels/loads before the bite with no physical resume, then purchases the
second ration and checks actual bite/delay, Whole-to-bitten change, 18 increments
and no-grant tail cleanup. Public journal inspection supplies request/history
facts without a new authority API. The resulting
`Saved/CafeWorldV3/MetaHumanMealJourney.json` is a test observation, not an art or
physical capability certificate. Separate movement/pause/unpossess/foreign-
takeover care negatives and native rendered contact review remain required.

## Actual 034 results and remaining limits

The fresh Game and Editor builds passed in 274.437 and 493.141 seconds. The
independent pair review verified 164 native source files, the full 213-file
source closure and 426 metadata records, matching runtime modules and all nine
build custody checks. Both build processes exited 0, were waited and had no
remaining owned descendants. The review and exact receipt hashes are indexed
in [metahuman_meal034_semantics.json](../evidence/metahuman_meal034_semantics.json).

| Actual case | Native result | Host/native test time | Warning scope |
| --- | --- | --- | --- |
| `Meal034Journey_v003` | Exactly one `MetaHumanMealJourneyInput`, Success, 0 errors; D3D12/SM6 on Radeon 8060S | 87.219 s / 49.879841 s | Raw automation: 0 succeeded, 1 succeededWithWarnings; exactly one admitted external HTTP connectivity timeout |
| `Meal034Parser_v003` | Exactly one `MetaHumanMealV2Parser`, Success, 0 errors; NullRHI, synthetic data only | 16.938 s / 0.016177 s | 1 succeeded, 0 succeededWithWarnings; 0 test warnings |

Both hosts passed SOURCE, STAGED, CANONICAL, GLOBAL, PRIVATE_CONFIG and QUEUE
closure checks, exited 0 and reaped empty. Raw Engine startup warnings remain
in the reports: seven observed lines for the meal, including an earlier HTTP
timeout, and five for the parser, including its NullRHI support warning. The
sole exported meal test warning is exactly
`LogHttp: HTTP request timed out after 3.00 seconds URL=https://www.google.com/generate_204`;
it was disclosed, not suppressed. No material-readiness retry, blocking shader
warmup or threshold waiver was added. Ordinary GPU preload reached
`configure_ready`, followed by all nine journey stages.

The saved 774-byte `MetaHumanMealJourney.json`, SHA256
`1182c21860d49fbd291f9d1d3215952386861e502f34b97d1edacd1a6b508f88`,
records two requests and 18 completed ordinary ticks. The first actual bite was
observed at world time 7.964070503 s and the first benefit at 10.080758203 s:
2.116687700 s later, beyond the certified minimum 1 s. Test assertions also
checked pre-bite decay without benefit; actual W/E/F5/X/F9 callbacks; one paid
pre-bite save/cancel/load without physical resume; a second paid meal; exact
coin/stock changes and +3 fun; actual Whole-to-Bitten change; original Body
player, Face/PP and Outfit ownership; and no-grant tail/owned cleanup.

This is one naturally advancing near-clock-boundary run, not coverage of every
clock phase or frame stall. Software `InputKey` events are not hardware keyboard
input. The host used a GPU, but captured no screenshots or continuous video and
measured no FPS. Final food/hand/Face appearance, lip/finger surface clearance,
rendered contact, movement/pause/unpossess/foreign-takeover meal negatives,
cooked/IoStore operation, and the home/sleep/full-town journey remain open.
The host records natural process exit/reap; it explicitly leaves a distinct
PIE EndPlay completion unknown where the raw log does not name it.

The root's semantic admission is
`F:/Living Town/2026-10-20_Refined_Town/root_character_pipeline_macro_review_v1_001/METAHUMAN_MEAL034_ROOT_SEMANTIC_ADMISSION.json`.
Its scope does not promote final art or complete the broader game goal. Prior
failed build/parser/NullRHI-journey reports remain retained.

## Reproduce the qualified scope

The exact frozen host is
`F:/Living Town/2026-10-20_Refined_Town/metahuman_meal_journey_prepare_v1_003`,
freeze SHA256 `c262b875ecd0776feb36f71c2d4c7d9a06bd13f8227888a76ca3ca46d9b7d72a`.
Its `ROOT_COMMANDS.json` preserves both actual execution argument arrays;
`binding/BUILD_BINDING034.json` binds the actual positive build pair. Default
commands validate without launching or staging:

```powershell
$MealPython = 'C:/Users/yp/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$MealHost = 'F:/Living Town/2026-10-20_Refined_Town/metahuman_meal_journey_prepare_v1_003'
$MealFreeze = 'c262b875ecd0776feb36f71c2d4c7d9a06bd13f8227888a76ca3ca46d9b7d72a'
& $MealPython -B -X utf8 -W error "$MealHost/run_automation.py" --case meal_journey --expected-preparation-sha256 $MealFreeze
& $MealPython -B -X utf8 -W error "$MealHost/run_automation.py" --case parser --expected-preparation-sha256 $MealFreeze
```

The retained actual output paths must not be reused. A new execution needs a
fresh root-owned consumer/output with the same explicit sources and build
binding; do not edit the sealed kit or substitute failed Project/DDC outputs.
The original finite host policy is an aggregate 600 native seconds, a 180-second
journey deadline, 16 GiB native job cap, 24 GiB reserve, full 32 logical CPUs and
at most two shader workers. The parser remains a separate explicit case;
ActionClipOwnership was not rerun or relabelled as a 034 result.

Developer diagnostics log source/preload/configuration refusal tags at Display
and report the journey's initial stage and each transition once. Journey failure
and timeout messages include the stage, current pawn position, source presence,
availability and reach. These diagnostics add no retries, readiness changes,
HUD text or deadline extension.
