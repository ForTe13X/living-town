# MetaHuman meal physical source v2

This is an unregistered source candidate, not an eating capability admission.
The legacy v1 provider, MetaHuman refusal, E availability, paid reservation,
stock, needs, clock, waiting, save/replay and release paths are unchanged.
There is no recipe, certificate, calibrated asset or registration in this commit.

`ULivingTownMetaHumanMealProducer` observes one owned bread component and the
original Assembly Body/Face/Outfit. It never creates a second animation player,
sets a pose/curve/time, refreshes bones, calls a needs API or grants progress.
The final clip, food grip, mouth offset, physical contact and natural timing
remain pending independent native proof and root review. The planned 24.5 s
clip is not an accepted calibration; duration and phases come from the verified
certificate, so retiming does not require another hardcoded C++ duration.

## Files and trust boundary

`FLivingTownMetaHumanMealRecipeV2::ReadQualified` accepts a Content-relative
JSON recipe. It reads and hashes the same recipe buffer that it parses, checks
the actual certificate's bytes and SHA-256, then checks all declared package and
proof files. Package aliases are checked for identical bytes/hash and hashed
once per configuration. This uncooked loose-package route refuses missing
files; it does not waive hashes for a cooked build.

`Configure` only resolves already preloaded UObjects, checks exact object paths,
skeletons, nonadditive/root-motion-free clip, duration, ordered bread materials
and complete used-texture roster, and caches strong object references. It does
not reload a package whose UObject was already resolved. Preload and source
immutability therefore remain the root-owned host's responsibility. SHA/status
strings alone are not qualification: actual files and the loaded/live physical
observations must all agree. Root admissions are trusted local source records,
not signed or adversarial cryptographic certificates.

Configuration performs file IO, hashes and texture enumeration once. Active
frames use the cached role map and component/player references, bounded grip
and material comparisons, station queries, pose revisions, time and curves.
There is no per-frame package hashing, load, asset or component enumeration.

There is deliberately no public/Blueprint setter for a qualifying boolean.
Only the friend `ULivingTownCafeWorldV3Subsystem` can bind the private
`BindTrustedSessionObserver` callback. That future owner must continuously
check its actual SessionPawn/controller, active reserved use/grant, current
rights and eligibility, including the no-grant exit policy. The callback must
be read-only and must not mutate or stop the producer while it is observing.
No callback is wired here. Without it, `BeginPhysicalUse` refuses even if all
file/calibration checks pass. Cached presentation flags are only additional
diagnostics and cannot replace this authority observation.

## Exact JSON contracts

All keys below are required; additional or duplicate keys, nonfinite/fractional
integer values, zero hashes, absolute/traversing paths and unspecified anchors
are refused. Hashes are 64 lowercase hex characters. Versions are JSON strings.
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

The certificate has exactly fourteen keys: `format`, `version`, `status`, the
three binding hashes above, `assets`, `proofs`, `bread_materials`,
`bread_textures`, `anchors`, `station`, `timing`, `jaw`.
Its format/version/status are `LivingTown.MetaHumanMeal.PhysicalCertificate`,
`2`, `ROOT_ACCEPTED_NATIVE_PHYSICAL_EATING`.

`assets` rows contain exactly `role`, `asset`, `bytes`, `sha256`. Paths must be
full top-level object paths under `/Game/` or `/MetaHumanCharacter/`. Required
roles are `actor_class`, `clip`, `body`, `face`, `outfit`, `body_skeleton`,
`face_skeleton`, `bread`, `body_post`, `face_main`, `face_post`, plus exactly one
`bread_material/N` per ordered material slot and `bread_texture/N` per unique
texture. `bread_materials` has 1–8 paths and preserves repeated slots;
`bread_textures` has 1–32 unique paths. No fixed third material slot is assumed.
Body/Outfit/clip share the declared Body skeleton. Face is checked against its
own declared skeleton; the two skeleton paths may alias with identical bytes.

`proofs` has exactly the distinct `jaw`, `grip`, `bite` rows, each with `kind`,
`file`, `bytes`, `sha256`. Each actual proof JSON has exactly `format`,
`version`, `kind`, `status`, `binding_sha256`, `visual_descriptor_sha256`,
`clip_sha256`, `bread_sha256`, `native_pose_samples`. Values must use format
`LivingTown.MetaHumanMeal.PhysicalProof`, version `1`, status
`ROOT_ACCEPTED_NATIVE`, matching roles/bindings and at least two actual native
pose samples. The root must supply and review the underlying native evidence;
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

Start may occur before or after the first animation ticks in its frame. The
producer emits no observation in that frame, then waits at most the certified
`max_frame_gap` for a later naturally finalized, advancing Body and Face frame.
It anchors world/clip time there without treating a partial initial tick as a
full frame. Only the following naturally completed frame can produce a fresh
sample. This entry wait cannot expose holding or consumption evidence, cannot
force pose evaluation and cancels on its finite deadline.

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
explicit contact and jaw bounds; latching requires a measured multi-frame span.

Before this latch, `bFirstProgressEligible` and `bConsumptionPhase` are false.
They also remain false until the certified real-time delay has elapsed and
natural Body/Face curve variation plus Face parent-relative jaw rotation have
actually been witnessed in the chew interval. They are false in the exit.
These flags are physical observations only: this component cannot grant needs
and does not know how many care increments were applied.

`ReadLatest` accepts only a still-active current-frame sample, rechecks live
identity/prop and unchanged sampled revisions/time, and clears its output on
refusal. A future consumer must execute after this producer and consume a frame
stamp at most once. Explicit stop, failure, pause/stale pose, action takeover,
end play and normal clip completion invalidate all latest benefit evidence.
Cleanup removes only this component's delegates/prerequisites and its own bread;
Assembly restores only a still-owned same-player/clip action. A foreign player's
asset is never overwritten. No physical observation is saved or restored.

## Remaining admission work

Root still needs the final authored asset and role/proof files, measured bread
grip/bite geometry and tolerances, natural Body-to-Face curve/jaw/contact proof,
the trusted owner callback and a post-producer consumption ordering. The actual
calibrated first eligible sample must fit the care core's maximum five waiting
ticks for every admitted global-clock remainder. E-time charge/reservation,
wait-with-decay, eighteen ordinary increments, cancellation/save policy and the
no-grant tail remain a separate authority integration slice. No global clock,
animation rate, core increment count or current refusal is changed to fit a clip.

`LivingTown.WorldV3.MetaHumanMealV2Parser` adds source-only C++ parser controls
for strict recipe/certificate fields, aliases/order, absent calibration,
traversal/duplicate keys, zero hashes, phase bounds, and refusal without real
files. Its synthetic fixture is intentionally not a qualification artifact.
UHT, compilation, these native tests and live physical/cleanup tests have not
run for this source candidate; root owns the next native build/run.
