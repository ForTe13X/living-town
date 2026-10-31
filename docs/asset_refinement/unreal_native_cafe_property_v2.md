# Native cafe property v2

One authored ground-floor cafe can now be offered for sale, bought and explicitly offered for a prepaid lease through an opt-in Unreal/C++ scenario. A single active ledger records the payments and event-derived title/operator rights. The original v1 scenario and save format remain available; canonical map/GameMode defaults stay unchanged.

F1 selects authored Aria and F2 selects Ben through native possession at the source spawn. Walk to the real counter before offering, buying or leasing. O opens a sale offer, L opens a lease offer, B buys, E leases, R ends the lease, F5 saves and F9 loads. Aria currently uses a simple functional owner-persona proxy. Her final model, hand contact and presentation remain work in progress.

The default HUD shows the current resident, coins, owner/operator and active offer in a compact card. Counter actions appear when relevant. **I** opens wrapped diagnostic details; **[ / ]** selects detail pages. Current unavailable-state warnings take priority over historical success feedback. Presentation labels derive from the existing observed view; commands still use the native authority boundary. Layout/text measurements are cached until their inputs change.

The controller reserves F1/F2/F5/F9 from their exact stock development debug-view commands on its own input instance. Other debug/custom bindings remain available. Game startup also enables per-monitor DPI handling, including unattended development launches, through the two `Engine.UserInterfaceSettings` flags in DefaultEngine.ini.

The new-world opening is 12 coins each, Aria's commercial title and an initial lease listing. A 12-coin sale needs her explicit offer; the new owner must list again before a 4-coin, 720-tick prepaid lease. Identity, clock, amount, payee and physical reach come from native authority. The command carries only request/property IDs and an action. The source floor/counter, facing, proximity and first-hit rays determine reach. This unit excludes upstairs residential rights.

## Evidence and limits

| Check | Actual result |
| --- | --- |
| Portable core | 16 cases / 1,316 checks, including direct frozen-v1 overlap, rollback, strict replay and file readback. |
| Native foundations | 12 foundation/selection tests and 11 SHA-256 known answers. |
| Actual public-boundary journey | 190 natural samples across Aria→Ben→Aria walks;12+12→24/0 after sale→20/4 after lease.75.656 seconds; independent audit passed. |
| Separate cold process | Fresh 12+12/event0→public LoadSlot→20+4/event7, Ben owner/Aria operator. Exact incoming slot, complete payload and clock/fraction restored; current persona/pawn/transform and offsite reach unchanged.58.015 seconds; independent audit passed. |

The journey submits typed commands through the production public boundary after real source-bound walks. It records a declared physical in-place facing step at the old qualified route endpoint. The cold test uses a new owned process and UserDir. These checks establish this one unit's authority/payment/save behavior. Final avatar/contact art, interior lighting, packaged performance and full-town migration remain open. Recurring rent, broader titles, payroll/capital, cultivation and railway/cultural visitors remain on the roadmap. [Sanitized evidence and receipt hashes](evidence/native_cafe_property_v2.json).

### Presentation validation

The integrated canonical project passed a fresh UE5.8.4 Editor build: source SHA256 `22d2f05481f6d7f7a02de094be7187b4769a64f750ede7385862c9c90815626c`, build receipt `257e3046da69fbeeb1910aa0b9fe8599cd989c6958edd2a646e5e4688a5944e4`. Its 61 runtime files are identical to the previously tested Native95 family; the canonical inspection module is compiled independently in this integrated cut.

A normal visible game using that actual build passed nine real keyboard actions: I/open, next/previous, I/close, F1/Aria, F2/Ben, an out-of-range B refusal, F5/save and F9/load. Thirteen native 1920×1080 captures were individually reviewed: an early witness, twelve accepted-route images including the corrected unobscured plaster closeup. Persona changes retained shaded rendering, refusal left coins unchanged, and save/load preserved the tested journal and position. The details contained one page; actual multi-page advancement remains untested. The transient native disabled flag and final renderer ViewMode enum were not exposed to the observer.

The game's 217 live OS samples observed per-monitor process/window awareness at DPI144. Private generated Engine.ini bytes were bound immediately before launch; persistence of that generated file after exit is not an immutable-source requirement. All 777 source packages, runtime DLL, source/config/global custody, temporary-camera cleanup and normal walking checks passed, with a normal exit and all owned processes reaped. Proof SHA256: `5569218adcef0015f4e6e11661fe39a91358829e77e6fd5fe8e804f510481037`.

Its screenshot-free moving CSV recorded 1,969 frames over 23.0689 seconds: mean 11.7161ms (85.35 FPS), p95 16.3577ms, GPU mean 9.8528ms, on AMD Radeon 8060S / D3D12 SM6. This is one prepared-cache, uncooked development route after a loading barrier. It establishes neither a performance improvement nor a cold-load, cooked-game or whole-town target. Typed possession took 42.20s in this run; the first accepted textured image completed at 46.14s after a 1.103s presentation barrier. Earlier runs varied substantially. The barrier's void return does not prove zero pending mips or GPU readiness; product loading time and packaged startup remain open.

## Reproduce

Use the matching compiled native source, UE5.8.4 and the checksum-bound original 405-package cafe/Ben asset closure. The 2 authored property/roster JSON files stay under Content/LivingTown. Normal opt-in play uses the Entry map with `?game=/Script/LivingTownNative.LivingTownCafePropertyV2GameMode`, `-game -LivingTownCafePropertyV2 -CafePropertyPersona=aria`. Editor Automation uses plain `/Engine/Maps/Entry` plus the same mode in an owned private GameMapsSettings config. Keep shared project/global defaults unchanged.

Run exactly `LivingTown.PropertyV2.ActualPublicBoundaryJourney` with propertyV2 and `LivingTownCafePropertyJourney` flags. Run `LivingTown.PropertyV2.ColdPublicBoundaryRestore` in a separate process with propertyV2 and `LivingTownCafePropertyColdRestore`; omit the Journey/LegacyV1/worker-preview flags for that run. FParse treats presence as enabled, including a `=false` spelling.

The optional cold regression input is the exact [producer slot](../../tools/tests/cafe_property_v2/fixtures/producer-slot.json), 3,599 bytes / SHA742029949dca6bb6c2d418ee030ee9cd46e97b351b51fab5b59bd1e38801e4e7. Copy it to the fresh owned `Saved/CafePropertyV2/CafePropertyTitleV2.slot.json` before startup; retain the fixed [Content metadata receipt](../../unreal/Content/LivingTown/PropertyV2ColdRestoreReceipt.json). The native test proves a fresh seed before public LoadSlot. Its historical producerPID/receipt hashes are regression provenance; host custody must also verify a new actual process and source/build/asset/Saved mapping.

The save envelope binds source/physical identities, canonical base64 payload, payload SHA256 and whole-envelope SHA256 including clock/fraction. Load performs full replay/cache checks before one swap. The shared atomic-slot helper writes and verifies a temporary file before same-directory replacement on its qualified filesystem. FNV64 is a deterministic internal diagnostic. Source and save custody use SHA256. A v1 or whole-world save is refused.

The [portable16-case consumer](../../tools/tests/cafe_property_v2/CafePropertyV2Cases.cpp) changes only its 2 includes to canonical core paths; its body is byte-identical to the original fixture. The canonical adaptation also compiles with strict MSVC warnings and passes all 16 cases / 1,316 checks, including actual journal readback. From a configured MSVC 14.44 / SDK 22621 developer environment, compile it with C++17 `/EHsc /permissive- /W4 /WX /O2 /MT`, explicit fresh output/TEMP paths and owned resource supervision, then run the executable with a fresh case-output directory. The portable-core CI also compiles and runs this consumer on Linux. Build.cs locks both core header hashes; intentional source versions require a reviewed guard/receipt update.

The fixed core retains its historical candidate banner under the locked byte hash. Actual build/runtime receipts in the evidence record establish the current qualification.
