# Map-to-Planet Resource Pool

This pool is an opt-in research surface for Living Town. It exists to answer product and architecture questions without making the owner's production simulation depend on unfinished experiments.

The governing product rule is: **a new scale must add a new decision, not merely a farther camera**.

## Non-interference contract

- New work stays under `scripts/labs/resource_pool` and `scenes/labs/resource_pool` unless the owner explicitly chooses an adapter.
- The pool does not instantiate or mutate `Sim`, `Main`, or `WorldView`.
- Lab receipts are evidence about a contract, not production acceptance or a save migration.
- Every batch owns a disjoint path set, fixed inputs, a deterministic receipt, focused gates, exclusions, and an owner opt-in note.
- Planet, region, tile, site, and cell views may project the same address. Opening a view never advances or rewrites authority.

The machine-readable catalog is [manifest.json](./manifest.json).

## RP-0001 — Planet scale identity contract

Product problem: a caravan destination, generated site, revisited container, rumor source, and planet marker must still name the same place after zooming, saving, or regenerating content.

`ScaleAddress.gd` contributes one strict hierarchy:

```text
planet → region → tile → site → cell
```

Its decoded exchange format is a JSON-safe `Dictionary`; its save/evidence authority is the immutable versioned `psa1|...` string. Persistence seed tokens use the repository's existing SHA-256 primitive, truncate to a positive 63-bit lowercase `s63:` token, and carry an explicit algorithm version. Region membership is derived from the global tile coordinate, so no duplicate parent field can drift.

The canonical delimiter is `|`, not `/`: existing production navigation already uses slash-separated `space/floor` strings. Stable tile identity uses axial coordinates; the MapTileLab adapter converts its current odd-q storage coordinates before naming a place, so a future array-layout change does not silently rename the world.

The contract intentionally does **not** choose a spherical projection. `face` is a stable atlas slot from 0 through 5, suitable for a later cube-sphere, while the current map-tile lab can use face zero without pretending its 11x7 rectangle is already a planet.

### Owner opt-in

The existing lab can name a tile without touching global state:

```gdscript
const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
var address := ScaleAddress.map_tile_lab_address(Vector2i(7, 2), "ashfall", 0)
var address_id := ScaleAddress.canonical_id(address)
```

If this becomes save authority, the owner must choose and gate a real save-schema migration. Missing production fields must not be silently defaulted into V1 addresses.

### Focused gate

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-planet-address-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game res://scenes/labs/resource_pool/scale_address_test.tscn
```

The gate covers exact golden IDs and SHA seed tokens, strict parsing, five-level parent/child roundtrips, negative floor division, JSON integral-number normalization, tamper rejection, odd-q-to-axial MapTileLab adaptation, and a fixed 2,646-address collision regression sample. The sample is a regression signal, not a mathematical no-collision claim.

RP-0001 also freezes two portability details that consumers must preserve: every UTF-8 seed-material part, including the final purpose, has a trailing NUL byte; and canonical receipt JSON comes from `canonical_receipt_json()`, never from decoded Dictionary insertion order. Accepted region bounds are closed under all 16x16 child-tile coordinates. Integral JSON floats are range-checked before conversion, including hostile finite values such as `1e300`.

## RP-0002 - Expedition brief and causal debrief

Product problem: Ash Market already has route cost, readable buildings, loot, injury, extraction, and collapse, but loot alone does not tell the player why an expedition is worth risking. A picked item can also be confused with a delivered result, and a collapse can erase the pack before a result screen explains what was lost.

`ExpeditionContract.gd` contributes a deterministic, owner-independent pipeline:

```text
site address + terms + board slot
              |
              v
       departure brief
              |
        terminal snapshot
              |
              v
 success | strained | partial | retreat | collapse
              |
              v
 authority receipt + player-facing factual debrief
```

The three V1 briefs use the actual authored Ash Market loot distribution, rather than invented quest currency:

| Brief | Promise | Full bundle | Constraint | Product choice |
|---|---:|---:|---|---|
| Field medicine | Extract 2 meds | value 70, 1.4 kg, noise 3 | return at 70+ health | light and valuable, but concentrated inside the east clinic |
| Winter rations | Extract 2 food | value 38, 2.6 kg, noise 4 | extract within 40 turns | split across two roofs; food can repay up to 3.0 supply |
| Relay parts | Extract 2 parts | value 91, 3.5 kg, noise 8 | keep pack at or below 4.0 kg | highest value and exposure; opportunistic loot can breach the weight promise |

Collapse has priority over picked progress: carried objective goods become delivered zero, cargo value moves to `lost_value`, and no supply is credited. Safe extraction can still be partial or an objective-empty retreat. Meeting the objective while breaching its constraint is a visible `success / strained`, not silently clean success. Food settlement records before, applied gain, and after at the existing 24.0 supply cap.

`terms_version` participates in the contract ID. Any authority change to the authored promise must bump that version; the gate pins the resulting contract ID so an accidental unversioned change is visible. Outcome IDs hash canonical authority facts with lexically sorted keys; display labels and prose are validated but do not perturb settlement identity when copy changes. Canonical receipt JSON has a fixed field order. A receipt is a checksum, not a signature or authorization proof.

### Honest MapTile terminal bridge

`MapTileExpeditionAdapter.gd` is deliberately two-phase:

```gdscript
var witness := MapTileExpeditionAdapter.begin_terminal(map_tile_model, tracked_peak_noise)
# The MapTileLab model performs extract_local() or the action that causes collapse.
var snapshot := MapTileExpeditionAdapter.complete_terminal(witness, map_tile_model)
```

The first call requires a consistent LOCAL pack reconstructed from taken loot and neutralized threats. The second requires a real LOCAL-to-WORLD transition and infers extraction or collapse from model state; the caller cannot self-report the result. It verifies the lab's own stash, capped supply, condition, and morale transition without applying them again. On collapse it reconstructs pre-clear carried goods from persistent taken/dead content flags, so lost progress remains visible after the model clears inventory. Both calls are observation-only.

This adapter is evidence for the current authored MapTileLab, not a production authority. A promoted owner must bind accepted brief, site, attempt, and typed action events; validate brief and outcome before accepting the receipt; atomically store one `{settlement_key, outcome_id}`; treat the same pair as a replay no-op and the same key with a different outcome as a conflict. Because the current MapTileLab already applies extraction settlement, its adapter receipt must never pay a second time. Adding active expeditions or a settlement ledger to `Sim` requires a real save-schema migration.

The debrief keeps exposure and injury as separate facts. `peak_noise` and `health_lost` can coexist, but the V1 snapshot does not claim that a particular noise event caused a particular wound. Production-grade causal attribution requires the typed action journal described above.

### Runnable lab and focused gate

Run the pure contract gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-expedition-contract-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game res://scenes/labs/resource_pool/expedition_contract_test.tscn
```

Open the standalone visual lab without loading `Main`, `Sim`, or `WorldView`:

```powershell
godot --path game res://scenes/labs/resource_pool/ExpeditionBriefLab.tscn
```

Keys `1-3` select a brief. Keys `A-E` select deterministic lab fixtures for clean success, strained success, partial delivery, retreat, and collapse. Command-line fixtures use `--expedition-mission`, `--expedition-result`, and `--lab-shot`; these exist for screenshots and do not imply that a player chooses their outcome.

## RP-0003 - Region atlas and persistent caravan route

Product problem: a larger map is not useful by itself. It must make the player choose what to spend on a journey, explain why a route is safe or tight, preserve exactly where the caravan stopped, and keep looking at the atlas from advancing authority.

`RegionRouteModel.gd` contributes an authored 16 by 12 axial window that spans two `ScaleAddress` regions. It contains 192 stable tile identities, 521 explicit undirected edges, the six MapTileLab sites at their exact odd-q-to-axial addresses, a separate discovery/road state, immutable plans, and one-leg journey transitions. The window is an atlas scope, not a claim that either region or face zero is already a complete planet projection.

The three autumn offers to Cinder Crossing are deliberately non-dominated at supply 8.500:

| Route | Time | Supply use | Rig wear | Arrival | Decision |
|---|---:|---:|---:|---:|---|
| Orra Ridge Cut | 11:43 | 7.502 | 6.412 | 0.998 | fastest, but tight; winter closes Ridge Pass |
| Old Market Road | 22:30 | 6.384 | 3.620 | 2.116 | safe and least wear |
| Dunlin Supply Arc | 30:19 | 5.645 | 8.020 | 2.855 | safe and lowest supply use |

Spring changes all three budgets. In winter the ridge plan is `season_closed`; the other destination plans remain reachable but below the 2.000 safe reserve, so the board presents a typed fallback instead of pretending a tight arrival is safe. At zero supply the destination and fallback gates both fail and the board returns `no_plan` while retaining factual route previews.

Route search uses integer-only edge costs and an explicit lexicographic contract: fast compares minutes first, safe compares rig wear then exposure, and frugal compares supply first. Full path identity is the final deterministic tie-break. Road overrides are typed closed-edge deltas; an explicit open override is rejected because it would change `road_revision` without changing the graph.

Journey settlement advances exactly one edge. An unaffordable edge leaves the caravan on the prior tile with no partial debit; exact supply settles the complete leg and can then leave the caravan stranded at zero. Every accepted transition carries the exact before journey/state receipts, its leg receipt, the resulting discovery delta, and a transition receipt. Fallback is a separate causal diversion transition: its child plan is an ordinary immutable plan, while the envelope binds the real parent plan and branch state. Observation APIs never mutate atlas, discovery, plan, or journey data.

### Owner opt-in and save boundary

These receipts are checksums, not signatures or authorization. Production acceptance must:

- retain full atlas, plan, journey, leg, and diversion receipts even when a compact 64-bit-prefixed ID is used as an index, and fail closed on an ID/full-receipt collision;
- validate the exact transition against the stored before-state and atomically compare-and-swap `before_journey_state_receipt`; a standalone `validate_journey()` snapshot is not proof that an action occurred;
- call `validate_route_receipt()` with atlas, atlas state, plan, and journey before accepting evidence; `canonical_receipt_json()` checks grammar and self-hash only;
- freeze the plan's road snapshot for an active journey, or add a typed replan transition. V1 intentionally fails closed if `road_revision` changes mid-journey;
- add a real production save-schema migration and a replay/idempotency ledger. None of the resource-pool DTOs mutate `Sim` or become owner authority by being loaded.

### Runnable lab and focused gate

Run the pure model gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-region-route-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 200 res://scenes/labs/resource_pool/region_route_test.tscn
```

Open the standalone visual lab:

```powershell
godot --path game res://scenes/labs/resource_pool/RegionRouteLab.tscn
```

Keys `1-3` select a route; `A-E` select autumn, spring, winter, two settled legs, and empty-supply fixtures. `Enter` or `Space` begins/advances one leg, `F` accepts a currently affordable fallback, and `R` resets. Screenshot fixtures use `--region-fixture`, `--region-route`, and `--lab-shot`; shot mode freezes animation before capture.

## RP-0004 - Tile promise to durable local site

Product problem: reaching a named region tile cannot keep opening the same Ash
Market T-junction, and revisiting a scavenged site cannot silently refill it.
The region atlas needs to promise a tactical shape that is reproducible before
the player enters it, while the save needs to retain consequences without
serializing a second 32 by 22 world.

`SiteBlueprintModel.gd` contributes two deliberately separate authorities:

```text
deterministic RP-0003 atlas site
              |
              v
       canonical site promise
              |
      compiler + 3 seed streams
              v
 immutable 32x22 blueprint --------------------+
              |                                |
 arrived route + owner journey checkpoint      | observation / roof preview
              |                                | never mutates authority
 owner-accepted idle site checkpoint           |
              |                                |
              v                                |
        idle -> active visit -> idle -----------+
                    trusted terminal facts
                    + monotonic scar IDs
```

The blueprint is JSON-native and integer-only. It binds the exact atlas ID,
full atlas receipt, root seed, canonical tile/site/cell addresses, compiler and
content revisions, row-major cells, buildings, exterior/interior doors, props,
loot, threats, entry, extraction, and a full SHA-256 receipt. Layout,
population, and clutter use three purpose-separated `ScaleAddress` seed
receipts. Route season, remaining supply, plan choice, visit slot, and camera
observation do not enter blueprint entropy.

The six current atlas kinds compile to six tactical recipes rather than six
labels on one map:

| Site kind | Recipe | Buildings | Loot | Threats | Decision added |
|---|---|---:|---:|---:|---|
| ruins | ruined market block | 4 | 8 | 3 | choose which storefront wing is worth road exposure |
| clinic | field clinic campus | 4 | 7 | 2 | commit to deep medicine or preserve a short retreat |
| relay | fenced relay compound | 3 | 6 | 3 | cross one choke for concentrated signal parts |
| quarry | quarry works and pit | 3 | 7 | 4 | trade heavy parts against open exposure and a long haul |
| farm | dispersed homestead | 3 | 7 | 2 | stop after enough food or sweep the whole yard |
| haven | crossing safe stop | 4 | 5 | 1 | spend time on low-pressure resupply rather than combat |

Every building has one exterior threshold; internal partitions retain explicit
doors. Static navigation is derived from cells plus blocking props and treats
threats as tactical occupants, not permanent walls. Independent gates require
entry-to-extraction, every door, every building interior, every loot node, and
every threat spawn to be reachable. Entity IDs derive from canonical site,
semantic kind/label, and cell provenance, then serialize in lexical order. They
do not depend on array ordinal. Cell codes 0 through 9 exactly match
`MapTileLabModel.Cell`; fence, crop, and pit extend the table at 10 through 12.

### Seed plus scars, not a second local world

`SiteBlueprintModel` stores a durable site state as a bounded scar ledger:

- completed visit IDs;
- depleted loot IDs;
- neutralized threat IDs;
- revealed building IDs;
- destroyed destructible-prop IDs;
- an `idle | active` admission header and receipt chain.

Entering is an exact `idle -> active` transition. It validates the full
RP-0003 atlas/state/plan/journey/route receipt, requires `journey.phase ==
arrived`, requires the arrived tile to be the site's parent, and binds an
owner-supplied accepted journey-state receipt plus an independently accepted
idle site-state receipt. Both expected receipts must come from the owner's
stored save/CAS records, never from the candidate DTO being checked. Resolving
requires the exact enter transition and both accepted checkpoints, returns to
`idle`, increments the completed revision by exactly one, and only unions
scars. A strict zero-turn, empty-scar retreat closes an admission as a committed
visit; other zero-turn results fail closed. Admission at the visit cap is
rejected before it can create an unresolvable active state.

The state validator is intentionally named a snapshot/shape validator. A
self-hash is not authorization and cannot prove history. `accept_state_checkpoint()`
only becomes meaningful when its expected receipt comes from the owner's
already accepted save/CAS record rather than the candidate DTO. Likewise,
`make_visit_delta()` is an owner-side constructor for terminal facts supplied
by a trusted action reducer or two-phase gameplay adapter. It proves exact
provenance, order, and monotonicity; it does not prove that a client really
walked to a container, killed a threat, or reached extraction.

### Owner opt-in and promotion boundary

A production integration must:

- store `{site_id, blueprint_receipt, accepted_state_receipt}` in a real save
  schema migration, retain the caravan's independently accepted journey-state
  receipt, and rebuild the blueprint from root seed plus versions;
- atomically CAS the accepted site state from idle-before to active-after on
  enter, then from active-before to idle-after on resolve, rejecting competing
  admissions and stale terminal transitions;
- derive terminal loot/threat facts from a trusted local action reducer or the
  existing two-phase terminal witness before calling the scar constructor;
- commit the resulting site scars and once-only Expedition/Caravan payout in
  the same owner transaction;
- materialize stable IDs into the receiver-owned local model and, if promoted,
  compile building/door structure into `SpaceGraph` without treating a hex as a
  room;
- archive old compiler/content revisions or provide a typed migration. A new
  version must not reinterpret an old scar ID against a different blueprint.

The lab does not mutate `Sim`, settle cargo, authorize raw client terminal
claims, provide a mid-raid player/threat checkpoint, materialize scars back
into a receiver-owned local world, or write site scars into RP-0003 atlas
road/discovery state. Those remain receiver-owned contracts; trusted action
reduction and scarred-site materialization are RP-0005.

### Runnable lab and focused gate

Run the pure compiler/state/causality gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-site-compiler-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 400 res://scenes/labs/resource_pool/site_compiler_test.tscn
```

Open the standalone visual lab without loading production scenes:

```powershell
godot --path game res://scenes/labs/resource_pool/SiteCompilerLab.tscn
```

Keys `A-F` or `1-6` select ruins, clinic, relay, quarry, farm, and haven.
`Tab` or `V` toggles fresh and scarred state without changing the blueprint.
Screenshot fixtures use `--site-fixture`, `--site-state`, and `--lab-shot`.

## RP-0005 - Trusted local journal and no-respawn revisit

Product problem: an immutable site plus a caller-supplied terminal summary still
cannot prove that the player walked to a container, survived a threat tick, or
earned a durable scar. Without a typed local reducer, a revisit either refills
content or trusts a self-rehashed claim.

`SiteVisitJournalModel.gd` contributes a deterministic action boundary:

```text
owner-accepted active site checkpoint
                 |
                 v
      intent-only action journal
 move | loot | attack | destroy | wait | extract | abort
                 |
        reducer-owned effects
                 v
 extracted | collapsed | sequence-zero retreat
                 |
                 v
 exact RP-0004 active -> idle scar settlement
                 |
 immutable blueprint + accepted idle scars
                 v
      disposable revisit projection
```

The caller chooses an action kind and stable target ID only. It cannot submit
damage, noise, threat movement, roof reveal, scar arrays, or a terminal result.
Every accepted journal is replayed from the exact active Site checkpoint and
the owner-held latest journal receipt. Events bind their previous event,
before/after runtime receipts, normalized intent, reducer effects, and full
receipt. Dropped, reordered, duplicated, cross-site, stale-checkpoint, and
self-rehashed chains fail closed.

V1 keeps doors as authored walkable cells rather than inventing a second door
authority. Movement is one cardinal cell; the existing MapTileLab arbitrary
delta cannot become a trusted action. Loot, threat, and prop actions name the
authored RP-0004 entity ID and require local range. Threats advance in lexical
ID order after every successful nonterminal action. Damage records the amount
actually applied, a lethal tick atomically produces collapse, and loot or a
kill committed before that tick still becomes a durable site scar. Roof memory
is derived only after a surviving player reaches a building interior.

Extraction is legal only from the authored extraction cell and consumes no
extra turn. `abort` is a strict sequence-zero, zero-turn, empty-scar admission
recovery that maps to the Site `retreated` resolution; an expedition retreat
after play remains RP-0002's downstream grading of a safe extraction. A hard
512-event replay bound cannot strand an active visit: its final ordinary action
causes a reducer-owned exhaustion collapse.

### Seed plus scars becomes a tactical revisit

`materialize_revisit()` accepts only the immutable blueprint and an
independently owner-accepted idle state receipt. It removes depleted loot,
neutralized threats, and destroyed props by stable ID, retains revealed roofs,
and derives navigation from the remaining blocking props. Surviving threats
return at their authored spawn and health as the same entity; transient combat
positions are not promoted into durable world state. Walls and cells remain
immutable in V1.

This creates a real return decision rather than a cosmetic map variant: the
player can see that a valuable container is gone, a killed threat will not
respawn, an opened choke remains traversable, and a previously entered roof is
known before spending another caravan journey.

### Owner opt-in and promotion boundary

Receipts are integrity checks, not signatures or client authorization. A
production owner must:

- persist root/compiler/rules revisions, the RP-0004 active checkpoint, journal
  start, full ordered events, and the latest accepted journal receipt;
- atomically accept each `(journal_id, sequence)` once, treating a different
  receipt at the same sequence as a conflict;
- validate the original RP-0004 enter transition and independent idle and
  journey checkpoints before resolving the journal;
- commit active-to-idle site scars and once-only expedition/cargo settlement in
  the same owner transaction;
- inject authored stable IDs into receiver-owned local entities rather than
  recovering identity from labels, positions, or counts;
- add fail-early size limits before parsing untrusted nested effects, threat
  states, or strings, plus a real save-schema migration and revision archive.

The lab does not mutate `Sim`, `Main`, `WorldView`, production cargo, RP-0003
roads, or `SpaceGraph`. It does not claim that a checksum prevents a malicious
client, and its disposable revisit DTO is not a second save authority.

### Runnable lab and focused gate

Run the pure reducer/revisit gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-site-visit-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 900 res://scenes/labs/resource_pool/site_visit_journal_test.tscn
```

Open the standalone visual lab:

```powershell
godot --path game res://scenes/labs/resource_pool/ScarredRevisitLab.tscn
```

Keys `A-F` select the six site recipes; keys `1-4` select fresh blueprint,
typed journal, durable scars, and revisit projection. `Enter` or `Space`
advances the stored journal prefix, `Tab` cycles stages, `V` compares fresh and
revisit, and `R` rebuilds the deterministic fixture. Screenshot fixtures use
`--revisit-fixture`, `--revisit-stage`, `--revisit-step`, and `--lab-shot`.

## RP-0006 - Accepted cargo and aggregated settlement network

Product problem: route planning and local raids create cargo and consequences,
but they do not answer the medium-term campaign question: which remote
settlement receives one scarce accepted bundle, and is it spent on relief,
trade, or protection? Representing every distant settlement as another live
town would duplicate stock, residents, beliefs, and save authority.

`SettlementNetworkModel.gd` contributes a deterministic aggregate boundary:

```text
owner-accepted network checkpoint + owner-accepted cargo checkpoint
                              |
                deterministic offer board
                              |
                 caller selects offer_id only
                              |
         exact RP-0003 arrived-journey checkpoint
                              |
                              v
        joint network consequence + owner cargo/reward proposal
                              |
             receiver atomically CAS-commits both owners
                              |
          later distinct settlement releases queued intel
```

The catalog derives exactly four settlement nodes from RP-0003 `safe_stop`
sites: Cinder Crossing, Orra Relay, Saint Vey Clinic, and Dunlin Homestead. Ash
Market and Redglass Quarry remain context and intel subjects; they never gain
remote stock, standing, offers, or simulated residents. The aggregate state
owns only bounded need pressure, security pressure, reciprocity, consumed offer
and cargo-anchor ledgers, and delayed intel records.

The pinned decision fixture starts with one owner-accepted `parts = 2` bundle
and supply `80 / 240`. It exposes three equal-cost, non-dominated choices:

- aid Saint Vey, changing need `3 -> 1` and reciprocity `0 -> 2`, while queuing
  an opaque Ash Market medical-window record;
- trade at Dunlin, applying the unique immediate supply return `80 -> 110`;
- fortify Orra, changing security `3 -> 1` and reciprocity `0 -> 1`, while
  queuing an opaque Redglass route-watch record.

Cinder's food offer is honestly ineligible for a parts bundle. Aid is
suppressed when its need track cannot change, fortification is suppressed when
security cannot change, and trade is suppressed at the supply cap. The board
does not rank the remaining choices or invent a scalar score.

### Causal and replay boundary

Cargo identity is the hash of an externally accepted `(owner_scope,
owner_checkpoint_receipt)` pair. Both values are independent inputs to every
authority-bearing cargo, board, and settlement validation call; changing the
scope cannot mint a second replay key from the same checkpoint. RP-0002 and
RP-0005 receipts may appear only as bounded provenance. They cannot supply
quantities or authorize spending.

A choice binds its exact board, and an arrival binds the full RP-0003 atlas,
atlas state, plan, journey, route receipt, and owner-held arrived journey state
receipt. A settlement is a pure joint proposal: it contains the exact network
before/after state plus a conserving owner cargo/supply delta. It does not
apply either side. Sibling proposals may be recomputed from the same accepted
before state, but after one is committed, the stale checkpoint, board, and
other siblings fail the next acceptance path.

Intel created at revision N has release revision N+1. Projection is pure:
observation, elapsed wall-clock time, and repeated reads cannot advance the
network or reveal a subject early. Only a later, distinct, positive settlement
advances the accepted revision. If an intel-bearing offer is the final usable
offer in this finite V1 catalog, its record remains pending; catalog exhaustion
never turns a delayed consequence into an instant reward. A future terms
revision or receiver migration must introduce another honest opportunity.

### Owner opt-in and promotion boundary

Receipts are deterministic integrity checks, not signatures, capabilities, or
anti-cheat proof. A production owner must:

- persist and independently accept the latest network state receipt, owner
  scope/checkpoint, and RP-0003 arrived journey state receipt;
- build cargo quantities and supply from receiver-owned state rather than from
  provenance labels or client claims;
- atomically compare-and-swap the network state and the cargo/supply owner so
  one accepted checkpoint cannot fund two sibling proposals;
- archive catalog/terms revisions and migrate pending intel and consumed replay
  keys without resetting them;
- define authorization, multiplayer conflict handling, untrusted-input byte
  limits, and a production save-schema migration.

The lab never mutates `Sim`, `Main`, `WorldView`, production cargo, town stock,
coins, resident beliefs, RP-0003 roads, RP-0004/5 site scars, or `SpaceGraph`.
It does not simulate distant settlements continuously and does not promote
ruins or quarries into settlements.

### Runnable lab and focused gate

Run the pure aggregate-network gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-settlement-network-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 900 res://scenes/labs/resource_pool/settlement_network_test.tscn
```

Open the standalone visual lab:

```powershell
godot --path game res://scenes/labs/resource_pool/SettlementNetworkLab.tscn
```

Keys `A-F` select accepted anchor, options, aid settled, trade settled,
fortification settled, and delayed-intel release. Keys `1-3` select the three
branches; `Enter` or `Space` advances the stored real transition, `Tab` cycles
fixtures, `V` compares before/result, and `R` rebuilds. Screenshot fixtures use
`--network-fixture`, `--network-choice`, `--network-step`, and `--lab-shot`.

## RP-0007 - Planet campaign directives and delayed regional consequence

Product problem: region routes and the settlement network expose local and
medium-term tradeoffs, but a planet view still needs one decision that cannot be
expressed inside a single region: which seasonal cross-region directive receives
a scarce command slot and capacity budget? Merely drawing a larger connected map
would add camera distance without adding authority-safe strategy, while calling a
menu choice a convoy launch, arrival, or success would invent physical evidence.

`PlanetCampaignModel.gd` contributes a deterministic two-stage proposal boundary:

```text
accepted campaign + command owner + three accepted region adapters
                              |
                 one shared RP-0006 checkpoint
                       (read-only precondition)
                              |
                  seasonal directive board
                              |
                     caller selects ID
                              v
   stage 1: campaign + command owner + origin-region joint proposal
                              |
              receiver atomically CAS-commits all three
                              |
                 accepted epoch advance makes
                 the consequence deliverable
                              v
 stage 2: campaign + fresh target-region joint delivery proposal
                              |
               receiver atomically CAS-commits both
```

V1 directives are abstract remote allocations. They are not route plans,
physical launches, journeys, arrivals, completion reports, or proof of success.
If a future production design makes execution fallible, it must add a separately
owner-accepted outcome witness rather than reinterpret these receipts.

The authored Ashfall fixture contains three disconnected planet register
windows, not an inferred globe graph: Basin on face 0, Meridian on face 2, and
Nightward on face 5. Faces are stable atlas slots only. Three non-dominated
directives rotate their capacity advantage by epoch:

- spring favors Basin aid, reducing need and scheduling a later Meridian
  logistics consequence;
- autumn favors Meridian trade, reducing logistics and scheduling a later
  Nightward logistics consequence;
- winter favors Nightward fortification, reducing security and scheduling a
  later Basin security consequence.

With one command slot and three capacity units, all three directives remain
eligible and expose different benefit axes. With capacity reduced to two, only
the season-favored directive remains eligible. The board filters feasibility and
orders by stable option identity; it does not collapse relief, commerce, and
defense into a scalar score. An open epoch may also be explicitly deferred, so a
no-option state never becomes a dead end.

### Three-owner commitment and delayed delivery

Each region adapter binds exact bounded signals to an independently accepted
region owner scope/checkpoint and to the same single global RP-0006 scope and
checkpoint. Every authority-bearing call also receives an owner-held expected
adapter receipt. Rehashing changed signals, changing a scope, or slicing the
global network into per-window authorities cannot create accepted evidence.

The command anchor likewise requires its externally held scope, checkpoint, and
expected anchor receipt. Stage 1 returns one pure three-owner proposal: campaign
state advances to `committed`, command slots and capacity are conserved, and the
selected origin region receives its bounded pressure/faction delta. Nothing is
applied by the model. Sibling choices can be recomputed from one accepted before
state, but after the receiver accepts one CAS, the old state, board, command
anchor, replay key, and sibling proposals are stale.

Epoch advancement is explicit and advances exactly one authored season. A
scheduled consequence is `pending` until a distinct accepted advance reaches its
release epoch, then becomes `deliverable`; observation and wall-clock time never
advance it. Stage 2 requires a fresh accepted adapter and checkpoint for the
different target region plus the then-current shared RP-0006 read-only
precondition. It returns a two-owner campaign/target-region proposal. If the
target pressure is already at its bound, the typed result is `superseded` with
requested `-1`, applied `0`, and unchanged target signals; the campaign still
records the delivery and prevents replay. Due delivery remains legal at the
terminal epoch, so the last directive cannot strand an active consequence.

### Owner opt-in and promotion boundary

Receipts are deterministic integrity checks, not signatures, capabilities,
arrival evidence, or anti-cheat proof. A production owner must:

- archive the catalog and terms revision and persist the latest externally
  accepted campaign, command-owner, region-owner, and shared RP-0006 receipts;
- construct command capacity and region signals from receiver-owned state rather
  than accepting caller-authored quantities;
- atomically compare-and-swap campaign, command owner, and origin region for
  stage 1, then campaign and the fresh target region for stage 2;
- retain replay, directive, epoch, consequence, and delivery ledgers across
  save migration without accepting a candidate's self-hash as authority;
- define authorization, multiplayer conflict policy, input byte limits, and a
  production save-schema migration before promotion.

The lab never mutates `Sim`, `Main`, `WorldView`, production command capacity,
regional pressure, RP-0003 roads, RP-0006 network state, local sites, factions,
or `SpaceGraph`. It creates no globe topology and claims no physical travel.

### Runnable lab and focused gate

Run the pure campaign gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-planet-campaign-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 1200 res://scenes/labs/resource_pool/planet_campaign_test.tscn
```

Open the standalone visual lab:

```powershell
godot --path game res://scenes/labs/resource_pool/PlanetCampaignLab.tscn
```

Keys `A-F` select owner scope, the flexible three-option board, spring aid,
autumn trade, winter fortification, and the delayed stage-2 chain. Keys `1-3`
select directives, brackets change epoch, arrows change capacity, `Enter` or
`Space` advances the stored real transition, `V` compares applied and
superseded delivery, `Tab` cycles fixtures, and `R` rebuilds. Screenshot fixtures
use `--campaign-fixture`, `--campaign-epoch`, `--campaign-capacity`,
`--campaign-directive`, `--campaign-stage`, `--campaign-delivery`, and
`--lab-shot`.

## RP-0008 - Multi-epoch faction covenant

Product problem: RP-0007 makes one seasonal allocation meaningful, but nothing
yet makes today's political promise constrain a later epoch. A history panel is
not enough; the player needs a real choice between honoring an obligation,
spending one amendment to move its due season, or withdrawing at a bounded
faction cost. That choice must reuse accepted campaign and region evidence
without turning lab faction labels into production diplomacy authority.

`CampaignCovenantModel.gd` contributes one deterministic covenant lifecycle:

```text
accepted covenant state + accepted RP-0007 spring campaign state
                              |
      three accepted faction-region adapters + one shared RP-0006 anchor
                              |
                     spring covenant board
                              |
                     caller selects ID
                              v
        bind proposal: covenant + selected faction-region owner
                              |
                 receiver atomically CAS-commits both
                              |
          pure projection reads a later accepted RP-0007 state
                   /               |               \
            exact honor       amend once         withdraw
            evidence          and pay -1          and pay -2
                   \               |               /
                 pure covenant + faction-region proposal
                              |
                 receiver atomically CAS-commits both
```

The spring fixture offers three non-dominated promises, each bound to the exact
authored RP-0007 faction, window, region, action, and directive identity:

- Relief Guarantee requires Basin `aid` in autumn; its expected tight-cap cost
  is 3 and its value axis is relief;
- Exchange Charter requires Meridian `trade` in autumn; its expected tight-cap
  cost is 2 and its value axis is commerce;
- Watch Compact requires Nightward `fortify` in autumn; its expected tight-cap
  cost is 3 and its value axis is defense.

Binding requests faction access `+1`. In autumn with capacity 2, Exchange can
be honored immediately through an exact accepted Trade directive record.
Relief may request its one amendment but Aid still costs 3 in winter, so the
amendment does not make it feasible. Watch can pay faction access `-1`, move its
due epoch from autumn to winter, and then match the season-favored Fortify cost
2. This is the new player decision: only one formally available amendment
changes the future feasible set.

### Obligation truth and owner continuity

Projection is a pure read. It reports `not_due`, `due`, `overdue`, or `settled`
from externally accepted RP-0007 epoch state; observation and wall-clock time
cannot mature a covenant. Honor requires one exact durable directive record at
the effective due epoch, including action, directive receipt, faction, window,
region, region-owner scope, and shared-network scope. A semantically similar
record from another owner never honors the covenant. If no exact authoritative
record exists, withdraw remains available even at the terminal epoch, so a
foreign or stale candidate cannot strand the lifecycle.

The same faction-region owner must advance through three independently accepted
evidence points:

```text
R1 / last covenant transition input
        -> R2 / accepted RP-0007 directive origin input
        -> R3 / covenant resolution input
```

Checkpoint and adapter receipts must differ at both links. Reusing R1 for the
RP-0007 directive or R2 for resolution rejects. This is a token-chain guard; the
receiver still owns the authoritative CAS lineage and must apply every proposed
delta atomically.

The default end-to-end Watch chain is deliberately not drawn as a convenient
`2 -> 3` honor. Bind changes access `2 -> 3`, amendment changes `3 -> 2`, the
accepted RP-0007 Fortify origin delta changes `2 -> 3`, and only then does RP-0008
honor request `+1`. At the cap that final region delta is typed `superseded`
with `3 -> 3`, while the abstract covenant ledger still becomes `honored` and
terminal. Exchange produces the same honest at-cap honor. A separately anchored
low-access fixture may demonstrate an applied honor, but it cannot replace this
causal default.

### Owner opt-in and promotion boundary

Receipts are deterministic integrity checks, not authorization, signatures,
physical execution evidence, or proof that a faction changed. A production owner
must:

- persist the accepted covenant state plus the exact RP-0007 campaign,
  faction-region, adapter, and shared RP-0006 checkpoints used by each action;
- derive faction access from receiver-owned regional state and keep stable
  authored faction scopes separate from dynamic production faction medoids;
- atomically compare-and-swap covenant and faction-region owners for bind,
  amendment, honor, and withdrawal;
- preserve the `R1 -> R2 -> R3` owner lineage and prevent one RP-0007 directive
  record from honoring more than one covenant action replay key;
- archive terms and lifecycle ledgers through save migration and enforce
  authorization, conflict policy, and untrusted-input byte budgets.

The lab never mutates `Sim.factions`, resident trust or beliefs, production
commitments, RP-0007 campaign state, RP-0006 network state, command capacity,
regional pressure, roads, cargo, sites, `SpaceGraph`, or save schema. `Honored`
means the promised abstract allocation was recorded; it does not mean aid,
trade, fortification, travel, or any physical operation succeeded.

### Runnable lab and focused gate

Run the pure covenant gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-campaign-covenant-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 1200 res://scenes/labs/resource_pool/campaign_covenant_test.tscn
```

Open the standalone visual lab:

```powershell
godot --path game res://scenes/labs/resource_pool/CampaignCovenantLab.tscn
```

Keys `A-F` select spring board, Watch due, Watch amended, Watch honored,
Relief withdrawn, and Exchange honored/superseded. Keys `1-3` select the spring
covenant; `H`, `M`, and `W` choose only actions exposed by the real projection;
brackets change epoch evidence, arrows change capacity, `Enter` or `Space`
advances the stored proposal/accepted fixture, `V` compares an independently
anchored low-access applied honor, `Tab` cycles fixtures, and `R` rebuilds.
Screenshot fixtures use `--covenant-fixture`, `--covenant-key`,
`--covenant-epoch`, `--covenant-capacity`, `--covenant-action`,
`--covenant-view`, `--covenant-region-delta`, and `--lab-shot`.

## RP-0009 - Limited planet reconnaissance portfolio

Product problem: an active covenant and campaign can say what matters next,
but they do not make uncertainty itself a scarce strategic choice. A planet
player with two reconnaissance points should have to decide which two of three
future-support questions to narrow and which one to leave broad. That choice
must not invent hidden truth, advance the campaign, release intel, or project a
face-0 discovery onto unrelated planet faces.

`PlanetReconPortfolioModel.gd` contributes one deterministic, two-stage
epistemic lifecycle:

```text
accepted RP-0003 atlas/discovery + accepted RP-0006 available intel
                              |
accepted RP-0007 campaign + accepted active RP-0008 obligation
                              |
                 exact read-only evidence envelope
                              |
        three role priors + one external recon-capacity anchor
                              |
               three non-dominated 2-of-3 portfolios
                              |
                  caller selects portfolio ID
                              v
          commit proposal: belief state + capacity 2 -> 0
                              |
                    receiver CAS-commits both
                              |
            externally accepted two-report bundle
                       /                 \
      RP-0007/RP-0008 unchanged       snapshot changed
                 |                         |
        resolve exact bands       stale close / refund 0
                 \                         /
                  terminal belief-only proposal
```

The golden Exchange Charter fixture derives three roles from authored RP-0007
directive identity rather than map distance or labels:

- `duty` is Meridian on face 2, the obligation origin;
- `spillover` is Nightward on face 5, the delayed-consequence target;
- `fallback` is Basin on face 0, the remaining campaign window.

Only Basin has a narrower prior. RP-0006 must expose the exact available
`redglass_route_watch` intel, its Redglass site must parent to tile `(9,0)`, that
tile must exist in the accepted RP-0003 atlas and already be discovered, and
its canonical region parent must be Basin. Pending intel, another topic or
site, an undiscovered tile, another face, or a different root cannot ground the
prior. Basin therefore starts at `[3000,7000]` with width 4000; Meridian and
Nightward start at `[2000,8000]` with width 6000. `grounded` means the prior has
accepted provenance, not that it is more true.

### Three portfolios, no scalar winner

Every portfolio costs exactly two points and reduces selected bands to width
2000. The board publishes a role vector, never a score:

```text
duty + spillover  -> [4000, 4000,    0]
duty + fallback   -> [4000,    0, 2000]
spillover + fallback -> [   0, 4000, 2000]
```

All three are non-dominated because each leaves a different future-support
question broad. Capacity 0 or 1 produces typed `insufficient_recon_capacity`;
capacity 2 or more still exposes the same three choices and no recommended
winner. Commitment changes no band. Only an externally accepted bundle with
exactly the two selected probes, a fresh owner checkpoint, unique sources, and
typed `adverse`, `mixed`, or `favorable` signals can resolve the cycle.

The resulting values are support bands, not probabilities, confidence scores,
success chances, or hidden-world truth. The canonical signal mapping is
`adverse -> [1000,3000]`, `mixed -> [4000,6000]`, and
`favorable -> [7000,9000]`. The unselected role remains byte-identical to its
prior. Re-reading the board or projection cannot change any value.

### Snapshot staleness and owner boundary

Resolution requires the exact RP-0007 campaign and RP-0008 covenant snapshots
captured at commitment. If either accepted snapshot changes first, resolution
rejects and only a typed terminal stale close is available. Stale closure keeps
all three priors unobserved and refunds zero: the reconnaissance capacity was
already spent even though its report cycle no longer answers the original
obligation.

Receipts are deterministic integrity checks, not authorization, report truth,
discovery, or proof that reconnaissance physically happened. A production
owner must:

- persist the accepted atlas, network, campaign, covenant, recon-capacity, and
  report checkpoints independently;
- construct report bundles from receiver-owned evidence and atomically
  compare-and-swap belief plus capacity owners at commitment;
- consume only one terminal belief transition per accepted commitment and
  preserve no-refund stale closure when the campaign or obligation changes;
- keep support bands separate from production resident beliefs, hidden world
  state, success probabilities, and fog-of-war;
- archive terms, evidence provenance, replay, and report ledgers through a
  production save migration with authorization and input-size limits.

The lab never mutates RP-0003 discovery, RP-0006 intel or network state,
RP-0007 epoch or campaign, RP-0008 covenant state, `Sim`, production beliefs,
`SpaceGraph`, or a save. It does not reveal, discover, confirm, route, arrive,
complete, or succeed at anything.

### Runnable lab and focused gate

Run the pure recon gate:

```powershell
$game = (Resolve-Path 'game').Path.Replace('\', '/')
docker run --rm --name codex-planet-recon-gate -v "${game}:/game:ro" gamecraft-runner:4.6.2 godot --headless --path /game --quit-after 1200 res://scenes/labs/resource_pool/planet_recon_portfolio_test.tscn
```

Open the standalone visual lab:

```powershell
godot --path game res://scenes/labs/resource_pool/PlanetReconPortfolioLab.tscn
```

Keys `A-F` select active priors, the portfolio board, three resolved pairs, and
stale-after-spend. Keys `1-3` select the role pair; `Enter` or `Space` advances
prior to committed to terminal without changing bands during commitment; `V`
switches the typed report set, `Tab` or brackets cycle fixtures, and `R`
rebuilds. Screenshot fixtures use `--recon-fixture`, `--recon-portfolio`,
`--recon-stage`, `--recon-signal-set`, and `--lab-shot`.

## Product sequence toward planet scale

1. Proven: mission brief, partial success, retreat, and causal debrief.
2. Proven in the pool: stable region discovery, route tradeoffs, supplies, stranding, fallback, and save/load continuation.
3. Proven in the pool: compile six atlas promises into distinct, reachable local sites.
4. Proven in the pool: persist one active visit and monotonic scars without serializing a second world.
5. Proven in the pool: derive scars through a trusted local action reducer and materialize a no-respawn revisit projection.
6. Proven in the pool: spend one accepted cargo bundle on aggregate aid, trade, or fortification and delay its regional intel consequence.
7. Proven in the pool: commit one seasonal cross-region directive and deliver its bounded consequence only after a distinct accepted epoch advance.
8. Proven in the pool: bind one multi-epoch faction covenant so a later player
   must honor, amend once, or withdraw without inventing a second planet or
   faction authority.
9. Proven in the pool: spend two reconnaissance points on a non-dominated
   two-of-three support-band portfolio, then resolve from accepted reports or
   close stale without changing world truth or campaign time.
10. Next: arbitrate multiple simultaneously owner-accepted covenants that
    compete for one fulfillment slot, making one priority and its durable
    sacrifices explicit before the RP-0007 directive is committed.

Four boundaries remain invariant: a hex is not a `SpaceGraph` room; a caravan is not a second town/cargo authority; generated local sites store seed plus delta; distant settlements remain aggregated and observation-independent.
