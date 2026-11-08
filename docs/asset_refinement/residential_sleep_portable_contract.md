# Residential sleep authority candidate

This source-only extension gives the current authenticated cafe-worker persona
`ben` one newly authored initial owner-occupancy assignment. It is disabled until
an explicit source-bound authority event. It is not derived from Ben's old
`home/2f/[7,17]` address, the cafe commercial title or a previous payment.
The existing two-account coin ledger and ration book remain the sole books.

The logical site is `mcb_b_upper_single_bed_v1`, corresponding to
`PROPOSED_Core_MillCourt_B / B_Upper / single_bed` in the room plan. This names no
native component or measured mattress location. The source registry is
`unreal/Content/LivingTown/ResidentialRegistryV1.json`, SHA256
`cb9ac15a3ebdd7fb3e371583b49d510a954ef9eae546adead63ecf5af7223011`.
Initial occupancy costs nothing and supplies no transferable title, paid lease,
new account, inventory or public bed policy. Revocation is terminal for this
initial assignment; reactivation requires a future separately declared policy.

## Portable consumer API

The named next consumer is the native `ULivingTownCafeWorldV3Subsystem` owner.
No native integration is supplied in this change.

| API | Trusted input and result |
|---|---|
| `Kernel::activate_residential({tick, true, registry_sha256})` | Caller first verifies actual registry bytes. Appends the explicit initial occupancy event once; changes no coins or rations. |
| `Kernel::has_residential_right(resident, site, tick)` | Exact current resident/site and authority-time check. Does not observe native access. |
| `begin_sleep_use(kernel, use, SleepCommand, SleepContext)` | Atomically reserves bed/resident and begins the typed care grant. UI carries only request ID, site ID and observed world revision. Authenticated identity, clock, current floor/reach and qualified clip come from the owner. |
| `wait_for_sleep_entry(kernel, use, next_tick, SleepEntryObservation)` | At most six consecutive entry ticks, before any progress. Fresh floor/station/entry-motion evidence is distinct from food holding. Applies ordinary decay and zero positive benefit. Failure leaves both values unchanged; the owner must interrupt at the next ordinary tick or explicitly cancel. |
| `advance_sleep_use(kernel, use, next_tick, Contact)` | Forty consecutive observed rest ticks. The authority independently rechecks the occupancy right; contact flags cannot override it. Grants +6200 energy in integer increments before clamping, with normal hunger/energy/hygiene decay and no fun gain. Completion releases the grant. |
| `cancel_care_use(kernel, use, Cancelled or Interrupted)` | Releases the actual recorded grant and stops logical use together, preserving earned needs. It does not restore or stop a native clip. |
| `revoke_residential_use(kernel, use, TrustedResidentialChange)` | Atomically revokes the right and interrupts any active sleep. An unrelated meal is retained. Use this paired API when the care primitive exists. |

One resident cannot eat and sleep simultaneously. Another actor cannot use this
exclusive bed. Repeated accepted or refused requests return their old receipt;
they never reserve again or authorize another physical start. Request IDs share
the meal/property/sleep identity domain. The bounded event book reserves both
grant release and occupancy revocation capacity while the right is active.

The `Contact` supplied for rest must describe fresh physical evidence: actual
floor-supported interaction anchor, reachable/supporting mattress, valid
reservation and current entitlement. A logical ID, prepared pose or true boolean
from a UI is not native evidence. An interrupted observation applies decay on
that tick and no action gain. Long-frame catch-up must interrupt before advancing
idle time; repeated synthetic contact samples remain prohibited.

## Save versions and explicit migration

World schema/capability are `living_town.cafe_world_residential.v6` /
`cafe.world_residential.v6`. Both portable envelopes use version `6`; the care
journal uses version `4` for the distinct sleep-entry operation. Meal preparation
stays its existing Eat-only operation and policy. Existing property/meal event
wire bytes and financial history remain unchanged; new sleep records have
explicit typed extensions and the v6 world adds occupancy caches checked against
full event replay.

`CareBindings` additionally binds the exact residential registry hash and a
`sleep_recipe_sha256`. Meal-only history may leave the sleep recipe empty. A
paired save/load containing sleep grants requires a nonempty valid recipe hash.
Native source hashing must include the new fields and verify the actual recipe;
a syntactically valid portable hash never qualifies an asset.

`load_care_envelope` accepts only current v6/current care-v4 data. Use
`import_v5_care_envelope` with separately verified OLD native SHA/source bindings
to import v5/care-v3 data. It validates and replays the old world, retains all
financial/meal events, needs, progress and clock, then records AfterLoad releases
and invalidates active use before publication. It supplies no residential right.
The caller may activate the new assignment subsequently through its explicit new
source event. The existing explicit v4 import remains available and also stops
old use; there is no ordinary-load fallback or version alias.

The committed `active_meal_v5.paired` fixture was produced before editing these
headers, using the unmodified `752ba4d0` source content. It has a real paid meal,
one consumed ration and three progress ticks at clock 103. SHA256 is
`6ad091423a6feb6dda7895cf8977135f9d9082c744eea39431996f55d5f59bd6`.
This fixture proves portable migration, not native JSON, disk or physical state.

## Native integration still required

The owner must qualify actual B749 upstairs floor/bed component identities,
transforms, collision, safe entry/exit and a current-character clip before it can
submit a trusted `SleepContext`. The source registry does not identify which
current bedding component is the single bed. A walk to the ground floor proves
no upstairs or bed access.

Use the existing MetaHuman normal action owner and preserve Body/Face/outfit pose
ownership. Author measured entry/rest/exit bone tracks rather than moving the
assembled visual outside its fixed prepared transform. Consume final-pose
observations after actor ticks, with natural clip time and bounded frame gaps.
Verify head/shoulder/pelvis mattress support and clothing/bed clearance. The
logical energy effect must begin only when the measured resting phase qualifies.
Completion may retain a physical exit tail with no active grant and no benefit;
the native trusted-owner check must validate that completed grant explicitly.

Pause, movement, X, persona replacement, unpossess, load, source/component loss
and EndPlay require owned physical cleanup and logical interruption. Native
save/load remains source-bound SHA256 plus the existing atomic disk writer; it
must use a new explicit native v6 envelope/slot and preserve current resident and
position. Existing hardcoded native source fingerprints and UI remain v5 until
that integration is implemented. This portable candidate does not claim native
build, traversal, animation, contact, HUD or performance success.

## Verification

Compile `CafeWorldV3SleepCases.cpp` as C++17 with assertions enabled, then pass
`tools/tests/cafe_world_v3/fixtures/active_meal_v5.paired` as its one argument.
The suite covers explicit assignment, identity/source/spatial/clip refusals,
bounded entry, forty rest ticks, ordinary decay, rollback, replay, shared care
reservation, revocation, save quarantine, migration and cleanup capacity.
Existing property, meal, rent and daily-life suites remain required regressions.
Local verification uses MSVC 14.44 C++17 `/W4 /WX /UNDEBUG`. GCC
`-Wall -Wextra -Werror -UNDEBUG` remains pending CI; the native-property workflow
must add the new sleep executable/fixture command before merge. No Docker/WSL
environment or additional compiler was installed for this source pass.

The local source pass completed 12 sleep groups/1241 checks, 16 property
cases/1316 checks, 28 meal groups/3555 checks, 14 recurring-rent groups/4154 checks
and 18 daily-life groups. The CPU observations are synthetic. The final property
regression used a fresh output directory because its disk test correctly refused
to overwrite the first run's existing results.
