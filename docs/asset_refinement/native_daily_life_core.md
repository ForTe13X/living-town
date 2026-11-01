# Portable daily-life authority

The next native care journey needs meal payments, café stock and resident actions
to agree with the existing property ledger. The portable C++17 components now
provide that transaction boundary and a separate deterministic action-progress
primitive. The current Unreal scenario continues to use property V2; its physical
care adapter, animations and save-slot integration remain pending.

`CafeWorldV3.hpp` owns one property/payment ledger together with ration stock,
meal requests and resident/site reservations. A paid meal transfers two coins to
the current café operator and consumes one ration exactly once. Explicit public
provision records stock use or shortage without fabricating payment. Care starts
disabled; an explicit versioned activation supplies the two-ration pilot opening.
Accepted grants describe the authored meal effects; they do not apply needs or
claim that the resident has eaten.

`DailyLifeUseV1.hpp` progresses an approved eat, sleep or face-wash action on
observed authority ticks. Losing fresh contact or permission interrupts the use.
An identical accepted request remains replayable after progress, completion or
interruption without starting again. Native code must supply real observations
and couple this state to the sole world authority.

V3 accepts an explicit validated V2 import with care disabled. Its portable
envelope uses a labeled FNV corruption check for the fixture; native adoption
must use the existing source-bound SHA-256 and atomic slot path. Load invalidates
recorded spatial reservations. The shared backend selector is supplied for later
integration at every native entry point.

Strict MSVC C++17 builds passed the original property suite (16 cases, 1,316
checks), the same assertions against V3 (16/1,316), meal/rollback/replay/import
checks (19/3,342), and 11 care-progress groups. The contexts in these tests are
synthetic. The [sanitized evidence](evidence/native_daily_life_core.json) identifies
the exact source versions. Independent Linux CI jobs compile the canonical files.

The original V2 and lease core bytes remain unchanged. Native walking, meal
completion, auxiliary fun effects, persistent needs, controller/HUD integration
and the broader simulation roadmap require further implementation and tests.
