# Portable daily-life authority

## 7 November 2026: bounded preparation wait, care journal3

`ResidentUse::wait_before_first_progress` records `WaitBeforeFirstProgress`
(appended opcode6) with separate `WaitingObservation` identity, fresh holding,
grounding, station, permission and reservation evidence. It is not bite contact.
Only an active Eat grant with0 progressed ticks may wait, one consecutive tick
at a time, for at most5 ticks from the immutable grant tick. The source policy is
`eat_before_first_progress_max5_v1`; its finite budget is not a caller parameter.
Those ticks apply ordinary hunger/energy/hygiene decay, keep fun and progress
unchanged, and preserve the original grant. Five waits plus18 Eat increments fit
within the existing40-observed-tick history budget. Sleep/wash cannot use it.

`wait_before_first_meal_progress` clones the paired WorldV3/care values, rejects
loaded grants, derives the active reservation and current operator from the
actual kernel, checks clock/expiry validity and publishes only after replay
invariants reconcile. A successful wait creates no payment, stock, grant or
release event. Refused evidence, time, phase, rights or budget leaves both values
exact. The native caller still owns interruption/release and clock publication;
after reconciling a due property event it must record an interruption at a valid
consecutive authority tick, rather than release using an older care tick.

The original18 incremental Eat benefits and completion/release contract remain
unchanged. This primitive does not prove a bite or enforce its physical timing;
the future reviewed adapter must withhold progress until an actual bite and its
first full observed second, and must interrupt on lost physical/session evidence.
This source slice does not attach a provider, change E availability/refusals, or
modify the native character/animation owner.

Care journal3 explicitly serializes waiting evidence and validates it during
replay; old care journal2 is refused, including in the existing explicit paired
V4 importer. The old `active_fixed_v4.paired` fixture is preserved and its new
test requires no-partial-publication refusal. The standalone unchanged money
kernel's explicit fixed-rights import still passes. No hash is silently waived
and no old byte stream is relabelled. Paired outer version5 remains source-bound;
the changed care/envelope hashes invalidate prior native source-bound saves.

Actual bounded portable MSVC C++17 validation passes:18 care groups,16 WorldV3
property cases/1316 checks,28 meal groups/3555 checks, and14 rent groups/4154
checks. The single serial compiler pipeline uses `/W4 /WX /UNDEBUG /MP1`, a2GiB
owned-job commit cap and numeric thread limits1, exits0 and reaps empty in12.485s,
peaking at330715136 committed bytes. All observed source bytes/mtimes remain
unchanged. The actual receipt is
`D:/Dev/LivingTownNativeRuns/2026-11-04/CareWaitPortableCPU_v006/PORTABLE_CPU_REPORT.json`,
SHA256 `80b1d97c9a4ce3b40cefd89ba20ae1aa44fb9ff72dd108284aa92d60e089ec60`.
Earlier failed/partial CPU attempts remain retained; only006 qualifies the full
four-suite run. No Unreal build, PIE, Blender, GPU or meal journey ran.

Current core byte pins are care
`57726bcfe8a45cd9db099ad85c8affe325c6538404e0ae2c09acf35bd45da527`
and envelope
`ba807df992a9163dbb26df6fc4b7d582443b74c53403fc7298279ac51b93d63b`.
Build guards and exactly the two embedded native source-hash constants are
updated together. `CafeWorldV3.hpp` stays byte-exact
`9c31b82a263b389457a8d3ea00344f90e24b81f646f66a6b8377ccb4b85be46d`;
the W31 Assembly pair and ActionClipOwnership test also remain unchanged.

## Historical initial core and prior source revisions

The portable C++17 components provide meal payment, stock, reservation and
resident-progress seams for the next native care journey. This source revision
adds completed-meal release, replay-validated durable care state and paired
candidate commits. It has not yet been compiled or executed. The current Unreal
scenario continues to use property V2; the native meal adapter and its physical
journey remain pending.

`CafeWorldV3.hpp` owns one property/payment ledger together with ration stock,
meal requests and resident/site reservations. A paid meal transfers two coins to
the current café operator and consumes one ration exactly once. Explicit public
provision records stock use or shortage without fabricating payment. Care starts
disabled; an explicit versioned activation supplies the two-ration pilot opening.
Accepted grants describe the authored meal effects; they do not apply needs or
claim that the resident has eaten.

`DailyLifeUseV1.hpp` retains its existing APIs and progresses an approved eat,
sleep or face-wash action on observed authority ticks. Losing fresh contact or
permission interrupts the use. Its first durable journal is explicitly version
`2`: it records transitions, elapsed progress, terminal cause and all four needs,
then validates redundant caches by replay into a candidate before publication.
Eat distributes the existing authored hunger +50 and fun +3 over 18 ticks using
integer remainders and 0..100 clamping. No new passive fun decay is introduced.
An accepted request remains replayable after progress, completion, cancellation
or load invalidation without restarting or earning effects again.

`Completed` is a distinct WorldV3 reservation-release cause. The internal
`TrustedRelease` requires the full authored progress count and elapsed authority
time; elapsed clock time alone is insufficient. This trusted input is not a
player command or evidence of contact. `advance_meal_use` derives it only from
the care primitive's recorded `Completed` outcome. A cancelled grant cannot later
be relabelled completed. Cancellation, interruption and load invalidation retain
only effects already earned and never refund or replenish stock.

The helpers in `CafeWorldV3Envelope.hpp` compose **one resident's meals** with
the existing WorldV3 ledger. Begin, observed-tick advance and cancellation clone
both values, reconcile grant IDs and terminal causes, and publish both only on
success. Explicit fixture-only failure hooks exercise rollback after payment,
stock, grant, care begin and care advance. They are not persisted or exposed to
UI. A future native sole-authority owner must also commit its clock, property
expiry and any other resident state in the same transaction.

V3 still accepts an explicit validated V2 import with care disabled. Original V3
envelope functions remain available without a silent care migration. The new
paired envelope is explicitly `LivingTown.CafeWorldMealCare.PortableEnvelope`
version `4`, with a separate care-source binding. V3 lacks progress/needs and is
rejected by the paired reader; the old reader rejects V4. Historical V3 journals
remain readable by this core; older core versions cannot read its new completed
release note and progress amount. Exact source hashes prevent treating those
versions as interchangeable. V1/V2 and lease-core bytes are unchanged.

The paired load validates bindings, checksums, canonical decoding, both logical
replays, clock/fraction and cross-state consistency before publishing anything.
It then releases a saved active reservation as `AfterLoad` and invalidates its
care use together, preserving earned needs and progress history. Completed and
cancelled saves retain their terminal causes and gain no second release/effect.
Restored observations are historical and never grant current spatial access.

Care is bounded to 1,024 accepted requests, 45,057 transitions and a 32 MiB
document; WorldV3 keeps its existing 1,024-event/12 MiB caps. Inactive clock
catch-up coalesces into a single transition and uses bounded integer decay.
Active use requires each consecutive observed tick: a long frame must interrupt
before inactive catch-up, rather than fabricate contact samples. Replay rejects
excess counts before iterating them and stops on the first invalid transition.

The portable envelopes' labeled FNV checksums detect corruption; they are not
authentication. Native adoption must retain source-bound SHA-256 provenance,
strict fields and atomic slot writes under a new declared native save version.
Native code must supply actual fresh physics/contact/permission observations,
real prop/hand interaction and a qualified eating clip. Neither fixture contexts
nor the logical care journal establish any of those properties. The existing
backend selector remains available for the later entry-point integration.

At the preceding source revision, strict MSVC C++17 builds passed the property suite (16 cases, 1,316
checks), the same assertions against V3 (16/1,316), meal/rollback/replay/import
checks (19/3,342), and 11 care-progress groups. The contexts in these tests are
synthetic. The [sanitized evidence](evidence/native_daily_life_core.json) identifies
the exact source versions. Independent Linux CI jobs compile the canonical files.

This revision adds source cases for partial round-trip/continuation, exact-once
fun, cancelled/completed/after-load distinctions, malformed cache/history refusal,
paired rollback, source/version mismatch and refusal without partial publication.
All four portable MSVC C++17 suites now pass: 15 care progress/persistence groups,
25 meal groups with 3,486 checks, and both property suites with 16 cases and 1,316
checks each. The closed compiler/test process preserved its source inputs.
[This revision's sanitized evidence](evidence/native_meal_care_v4.json) binds the
actual code and result receipt. Linux CI and the native integration checks remain
separate; these portable results do not activate the meal gameplay adapter.
