# Portable daily-life authority

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
