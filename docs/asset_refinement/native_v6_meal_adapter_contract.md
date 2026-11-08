# Native v6 meal adapter candidate

This source-only adapter consumes portable residential-world v6 and care journal
v4 while preserving the existing meal command, physical producer, action owner,
natural clock and public scenario interfaces. It adds no sleep producer, command,
bed qualification or residential activation. Registry presence grants no rights.

The current native wrapper remains `LivingTown.CafeWorldMealCare.NativeJournal`
with the string version `6` and capability `cafe.world_residential_care.v6`.
Its separate current slot is
`Saved/CafeWorldV3/CafeWorldResidentialCareV6.slot.json`. It never overwrites the
previous `CafeWorldRentCareV5.slot.json` or `CafeWorldMealCareV4.slot.json`.

Before constructing the sole scenario authority, `AuthoredSources` verifies the
actual `Content/LivingTown/ResidentialRegistryV1.json` bytes against the reviewed
registry SHA256. The observed hash is cached in `State->Sources`. No additional
file reads or hashing occur in the natural-frame/authority-tick paths. Native v6
source hashing includes all world bindings, the care core hash, the registry hash
and the sleep-recipe hash. That last field is empty in this meal-only consumer.

## Explicit older saves

`ImportLegacyV5Journal` / `ImportLegacyV5Slot` are separate explicit APIs. The old
source family pins core `9c31b82a...`, care core `57726bcf...` and the previous
`ba807df9...` envelope-derived fixture fingerprint. The physical, visual, roster
and actual current meal recipe bindings must still match. Source fields in an
incoming save cannot select an old family or substitute current source pins.

`ImportLegacyV4Journal` / `ImportLegacyV4Slot` remain explicit. Their original
core/fixture family and old care hash are retained independently. Ordinary
`LoadJournal` / `LoadSlot` accept only native v6 plus portable v6/care-v4. There is
no fallback on parse, source, replay or migration failure.

Both import paths use the exact legacy native source-hash shape before invoking
the corresponding portable importer. Current hashing never truncates the new
fields to match an old save. Candidate replays preserve financial event bytes,
balances, ration stock, earned needs, progress and clock. Publication happens
only after both journals reconcile. Historical use is released before the
current physical meal is stopped and state is published; saved persona and pawn
transform never replace the live session.

The native meal-only consumer refuses a v6 payload containing any residential
activation history or sleep grant, even if its portable replay is valid. A future
reviewed native sleep owner must deliberately extend this boundary together with
actual bed/clip qualification and source hashing. The check cannot be removed by
setting a UI boolean or merely adding the registry file.

## Source fingerprints

| Current input | Exact SHA256 |
| --- | --- |
| `CafeWorldV3.hpp` | `93dc3e8ec181ce3de1071d36335257ee8d6a2c57fce61f56c2282dffb05f9724` |
| `DailyLifeUseV1.hpp` | `4125cb255d220dfb41c7a72953c2a90623c7f5f7b3fbc2418d633955b8cb23e6` |
| `CafeWorldV3Envelope.hpp` | `562b39067b5b78ec24456dc56ac83dab772adf6c476a7a56074041ca1d6640ce` |
| `ResidentialRegistryV1.json` | `cb9ac15a3ebdd7fb3e371583b49d510a954ef9eae546adead63ecf5af7223011` |

The public `GetBinding()` and `IsPrepared()` interface is unchanged. The existing
meal and boundary journey tests receive current-slot path changes only. Their
controller behavior, readiness predicates, timing and physical thresholds are
unchanged. Legacy v4/v5 import paths continue to refer to their original slots.

## Native verification pending

`LivingTown.WorldV6.NativePersistenceSchemaAndMigration` is a focused automation
test included from `Private/Tests/LivingTownCafeWorldV6PersistenceTest.inl` by the
same implementation unit. It directly exercises the production native JSON,
source-hash and candidate-replay helpers, without a public test-only authority
API. The `.inl` must be included in root's new immutable source closure.

Stage the unchanged baseline fixture at
`Content/LivingTown/Tests/active_meal_v5.paired` and the real registry at its usual
content path. The test verifies both file hashes. For the native migration unit
control only, it rebinds the fixture's source metadata in memory to the exact
compiled old family. The original fixture file, financial events and needs
history remain unchanged. This synthetic control does not qualify an actual old
native slot, pawn, asset, animation or bed.

The test covers paid current meal save/load, numeric/wrong-string versions,
wrong source, malformed payload, duplicate/unknown JSON fields, no partial
publication, explicit v5 migration, pinned v4/v5 families, unchanged historical
events and refusal of residential activation through the incomplete consumer.
It does not create a world or validate physical action restoration. Existing
natural meal/parser/journey checks are still required against root's fresh build.

The portable workflow now compiles and runs `CafeWorldV3SleepCases.cpp` with strict
GCC warnings and the preserved v5 fixture. All native builds, this native test and
GCC CI execution remain pending. This source handoff claims no native PASS.

Static source checks verified all three current header pins and the registry
against their actual bytes, and all three old v5 pins against the preserved meal
delivery checkout. Full old journey files were compared after only the selected
slot-name replacement; no other bytes changed semantically. `git diff --check`
passed. The receipt is
`D:/Dev/LivingTownPortableRuns/native-v6-adapter-v001/SOURCE_VALIDATION.json`.
