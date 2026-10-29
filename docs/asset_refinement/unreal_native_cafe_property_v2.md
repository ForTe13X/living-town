# Native cafe property v2

One authored ground-floor cafe can now be offered for sale, bought and explicitly offered for a prepaid lease through an opt-in Unreal/C++ scenario. A single active ledger records the payments and event-derived title/operator rights. The original v1 scenario and save format remain available; canonical map/GameMode defaults stay unchanged.

F1 selects authored Aria and F2 selects Ben through native possession at the source spawn. Walk to the real counter before offering, buying or leasing. O opens a sale offer, L opens a lease offer, B buys, E leases, R ends the lease, F5 saves and F9 loads. Aria currently uses a simple functional owner-persona proxy. Her final model, hand contact and presentation remain work in progress.

The new-world opening is 12 coins each, Aria's commercial title and an initial lease listing. A 12-coin sale needs her explicit offer; the new owner must list again before a 4-coin, 720-tick prepaid lease. Identity, clock, amount, payee and physical reach come from native authority. The command carries only request/property IDs and an action. The source floor/counter, facing, proximity and first-hit rays determine reach. This unit excludes upstairs residential rights.

## Evidence and limits

| Check | Actual result |
| --- | --- |
| Portable core | 16 cases / 1,316 checks, including direct frozen-v1 overlap, rollback, strict replay and file readback. |
| Native foundations | 12 foundation/selection tests and 11 SHA-256 known answers. |
| Actual public-boundary journey | 190 natural samples across Aria→Ben→Aria walks;12+12→24/0 after sale→20/4 after lease.75.656 seconds; independent audit passed. |
| Separate cold process | Fresh 12+12/event0→public LoadSlot→20+4/event7, Ben owner/Aria operator. Exact incoming slot, complete payload and clock/fraction restored; current persona/pawn/transform and offsite reach unchanged.58.015 seconds; independent audit passed. |

The journey submits typed commands through the production public boundary after real source-bound walks. It records a declared physical in-place facing step at the old qualified route endpoint. The cold test uses a new owned process and UserDir. These checks establish this one unit's authority/payment/save behavior. Keyboard interaction, final avatar/contact art, readable lit presentation, FPS and full-town migration remain open. Recurring rent, broader titles, payroll/capital, cultivation and railway/cultural visitors remain on the roadmap. [Sanitized evidence and receipt hashes](evidence/native_cafe_property_v2.json).

## Reproduce

Use the matching compiled native source, UE5.8.4 and the checksum-bound original 405-package cafe/Ben asset closure. The 2 authored property/roster JSON files stay under Content/LivingTown. Normal opt-in play uses the Entry map with `?game=/Script/LivingTownNative.LivingTownCafePropertyV2GameMode`, `-game -LivingTownCafePropertyV2 -CafePropertyPersona=aria`. Editor Automation uses plain `/Engine/Maps/Entry` plus the same mode in an owned private GameMapsSettings config. Keep shared project/global defaults unchanged.

Run exactly `LivingTown.PropertyV2.ActualPublicBoundaryJourney` with propertyV2 and `LivingTownCafePropertyJourney` flags. Run `LivingTown.PropertyV2.ColdPublicBoundaryRestore` in a separate process with propertyV2 and `LivingTownCafePropertyColdRestore`; omit the Journey/LegacyV1/worker-preview flags for that run. FParse treats presence as enabled, including a `=false` spelling.

The optional cold regression input is the exact [producer slot](../../tools/tests/cafe_property_v2/fixtures/producer-slot.json), 3,599 bytes / SHA742029949dca6bb6c2d418ee030ee9cd46e97b351b51fab5b59bd1e38801e4e7. Copy it to the fresh owned `Saved/CafePropertyV2/CafePropertyTitleV2.slot.json` before startup; retain the fixed [Content metadata receipt](../../unreal/Content/LivingTown/PropertyV2ColdRestoreReceipt.json). The native test proves a fresh seed before public LoadSlot. Its historical producerPID/receipt hashes are regression provenance; host custody must also verify a new actual process and source/build/asset/Saved mapping.

The save envelope binds source/physical identities, canonical base64 payload, payload SHA256 and whole-envelope SHA256 including clock/fraction. Load performs full replay/cache checks before one swap. The shared atomic-slot helper writes and verifies a temporary file before same-directory replacement on its qualified filesystem. FNV64 is a deterministic internal diagnostic. Source and save custody use SHA256. A v1 or whole-world save is refused.

The [portable16-case consumer](../../tools/tests/cafe_property_v2/CafePropertyV2Cases.cpp) changes only its 2 includes to canonical core paths; its body is byte-identical to the original fixture. The canonical adaptation also compiles with strict MSVC warnings and passes all 16 cases / 1,316 checks, including actual journal readback. From a configured MSVC 14.44 / SDK 22621 developer environment, compile it with C++17 `/EHsc /permissive- /W4 /WX /O2 /MT`, explicit fresh output/TEMP paths and owned resource supervision, then run the executable with a fresh case-output directory. The portable-core CI also compiles and runs this consumer on Linux. Build.cs locks both core header hashes; intentional source versions require a reviewed guard/receipt update.

The fixed core retains its historical candidate banner under the locked byte hash. Actual build/runtime receipts in the evidence record establish the current qualification.
