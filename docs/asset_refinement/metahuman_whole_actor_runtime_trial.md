# Prepared MetaHuman whole-actor runtime trial

This opt-in keeps `ALivingTownCafeCharacter`, its controller, camera, capsule,
movement and native backend authoritative. A `UChildActorComponent` owns the
complete saved MetaHuman Blueprint as its visual. Body, face, outfit, SDK and
LOD components remain inside that actor. It creates no replacement pawn and
transplants no skeletal components.

This is a source candidate for a controlled development trial. It does not
approve final workwear, art, eating, asset closure, packaged builds or frame rate.
The complete Build 017 source family passed Editor and Development Game
compilation. The three descriptor/identity/refusal tests below and four existing
backend/original-worker regressions executed successfully. The actual whole-actor
WorldV3 lifecycle test also succeeded with the single expected blocked-placement
warning described below. Possessed movement/render, measured production
calibration and cold Game startup remain required before enabling this visual
in a playable build.

## Explicit opt-in and identity

Pass `-LivingTownMetaHumanBen="<absolute prepared descriptor path>"` with an
otherwise qualified native Cafe/FullTown or WorldV3 producer. The flag applies
only to Ben and cannot coexist with `LivingTownOriginalWorkerBen` or head-part
options. Repeated flags refuse. No flag preserves the previous families.

The existing serialized V1–V3 scene-binding grammar is unchanged. This separate
descriptor supplies an internal `MetaHumanWholeActor` strategy after that parser
finishes. Its exact file SHA-256 becomes `VisualSha256`, so paired saves retain
physical scene identity while rejecting a different prepared visual descriptor.

The version 1 UTF-8 JSON must contain exactly these 15 fields; duplicate and unknown keys
refuse. The maximum file size is 16 KiB. This table describes the schema; it is
not a measured descriptor or a calibration result.

The separate [fitted workwear candidate](metahuman_cc0_workwear_trial.md) adds a
version 2 descriptor with two qualified outfit fields. Its native admission and
runtime verification remain pending.

| Field | Required value or measured bound |
| --- | --- |
| `format` | `LivingTown.MetaHumanBenActorPrepared` |
| `version` | JSON number `1` |
| `status` | `CONTROLLED_GAME_TRIAL_PREPARED` |
| `source_closure_sha256` | Nonzero lowercase SHA-256 of the prepared source closure |
| `core_manifest_sha256` | `2b60d109df4f6a99e0a746b8907fe89f16f5c3aa46aeb1db59f543c23f5b3c5c` |
| `actor_class` | The frozen generated Blueprint class below |
| `idle_animation` | The frozen neutral stand clip below |
| `walk_animation` | The frozen neutral walk clip below |
| `relative_transform` | Exactly `translation_cm` (3 numbers), `rotation_xyzw` (4 normalized quaternion numbers), `scale` (3 unit numbers); yaw only; X/Y within 50 cm; Z from −140 to 20 cm |
| `capsule_radius_cm` | Measured radius, 10–40 cm |
| `capsule_half_height_cm` | Measured half-height, 70–110 cm |
| `walk_speed_cm_s` | Measured positive speed, at most 250 cm/s |
| `camera_arm_cm` | Measured camera distance, 100–600 cm |
| `hand_bone` | `hand_r`; locomotion readback only, no eating grant |
| `preload_deadline_seconds` | Finite bounded load deadline, 1–120 seconds |

Frozen class:

```
/Game/LivingTown_UEPilot/MetaHumanAssembled_v009/CafeWorker_Dominic_Trial/BP_CafeWorker_Dominic_Trial.BP_CafeWorker_Dominic_Trial_C
```

Frozen locomotion clips:

```
/MetaHumanCharacter/Optional/Animation/UEFNAnimPreset/Locomotion/AS_MH_Neutral_Stand_Idle_Loop.AS_MH_Neutral_Stand_Idle_Loop
/MetaHumanCharacter/Optional/Animation/UEFNAnimPreset/Locomotion/AS_MH_Neutral_Walk_Loop_F.AS_MH_Neutral_Walk_Loop_F
```

Descriptor parsing authenticates exact prepared inputs and bounds; it does not
independently prove that the source closure, capsule, facing, gait or camera were
measured correctly. The producer and runtime qualification must supply that
evidence. Arbitrary actor classes, Pawn/Controller classes and alternative clips
cannot enter through this opt-in.

## Loading, lifecycle and capability

The existing GameMode owns an async class/clip preload. `Pending` creates no
qualified pawn and never means a successful selection. WorldV3 retains the
current pawn and paired session while Ben loads; F1/F2 use its tri-state request
API. Its existing bool selection API remains immediate and refuses an unready
Ben. New requests cancel older epochs; weak owners and EndPlay cancel callbacks.
The bounded wall-clock deadline reports failure instead of an indefinite wait.

For this family the exact native pawn finishes normal spawning first. Registering
its child component then runs the whole Blueprint's normal BeginPlay, including
SDK body/face/outfit setup. Qualification checks the actual child, generated
class, three child-owned skeletal components, parent, transform and animation
ownership. No manual BeginPlay, bone evaluation or leader-pose repair is used.

The body loops its ordinary native single-node clip. Actual planar movement
selects walk at 4 cm/s and returns to idle at 2 cm/s, with no repeated clip resets
while the state is unchanged. Face/outfit modes, animation classes and leader
relationships are preserved. Only the possessed player receives full bone tick
and disabled update-rate optimization; UnPossess restores prior policies and
retains its complete visual. Teleport requests supported cloth reset. Reset and
EndPlay destroy the owned child and release references idempotently.

WorldV3 validates a complete candidate before replacing the current resident.
The MetaHuman path refuses a switch while an active meal exists, then publishes
the new session through the existing checked binding API. Failed selection
restores the prior pawn/session without cancelling paired meal authority.

Existing eating/contact recipes target a different body. New MetaHuman requests
explicitly refuse with `metahuman_reviewed_eating_contact_recipe_required`, do
not charge, and remain unavailable in the HUD. Original recorded request replay
keeps its existing idempotence. For this family WorldV3 retains its existing
unavailable-provider source fingerprint instead of consuming a leftover mesh
recipe; a different prepared visual still changes paired-save identity.
A future real recipe needs its own calibrated
clip, socket/contact proof and native acceptance; changing a body accessor does
not supply that proof. Sleeping, seated use and other contact actions likewise
need actual compatible animation and scene-contact qualification. This candidate
supplies intermediate locomotion/player integration, not those journeys or final
goal completion.

`MetaHumanSDK` and `MetaHumanCharacter` are enabled for Editor and Game targets
while the assembled graph retains their runtime classes and plugin content.
`LivingTownNative` adds no Editor assembly-module dependency. Cook/package
closure still requires a separate qualification of these soft references.

## Validation consumers

`LivingTown.MetaHuman.PreparedDescriptorStrictness`,
`LivingTown.MetaHuman.PreparedVisualSaveIdentity` and
`LivingTown.MetaHuman.SafeRefusal` are syntax, identity and refusal tests; they
load no prepared MetaHuman assets and grant no art or runtime acceptance.

On 2026-11-05 the exact seven selected tests completed with zero test warnings
or errors and native exit 0. The inherited report wrapper still admitted only
one or four tests, so it retained a failure at its report-count gate. Root
independently checked all seven exported names, success states, entries and
matching log starts/completions without rerunning the process. That scoped test
acceptance does not convert the original wrapper report into a successful run.
The source/configuration guards and owned-process cleanup also passed.
The [portable qualification record](../evidence/metahuman_runtime_20261105/qualification.json)
retains the exact test names, proof hashes and outstanding acceptance checks.

`LivingTown.MetaHuman.WorldV3PersonaGate` consumes actual prepared assets in a
normally ticking standalone WorldV3 PIE world. Run it explicitly with
`-LivingTownCafeWorldV3 -LivingTownMetaHumanBen="<prepared descriptor>"
-CafeWorldPersona=aria -LivingTownMetaHumanPersonaGateTest`. It checks pending
selection/cancellation, blocked-candidate retention, exact native possession,
complete actor ownership, idle continuity, unsupported meal refusal, paired
save/load and cleanup. On 2026-11-05 it completed successfully in 19.913 seconds
inside a 55.625-second native process, with native exit 0, no test errors and one
warning: `actual_persona_spawn_capsule_overlap`. That exact warning belongs to
the deliberate blocked-candidate case, which must retain Aria and her session.
The inherited host required zero warnings and retained its failure; independent
root review admitted only this exact single diagnostic, with no native rerun or
change to the original report. Source/global custody and process cleanup passed.

This lifecycle fixture uses explicitly test-only inherited capsule, speed and
camera values. Passive actor measurements established the anatomical forward
direction, but did not measure production surface/sole fit or stride. The test
qualifies mechanical ownership and switching with those reference parameters;
it does not establish a production prepared descriptor, movement presentation,
frame rate, final art or cooked content closure.

The existing FullTown exact GameMode/pawn/profile guards are unchanged. A native
FullTown possessed-player consumer must still verify that route, motion, body /
face / clothing coherence, camera and cleanup with the prepared calibration.
