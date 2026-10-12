# Slice 240 — Courtyard access language

## Outcome

Three of the new perimeter blocks now have real, authored courtyard access instead of gates that are only painted into a solid collision rectangle.

- The west plaza market block opens a two-cell arched passage at `[17,23] → [17,22]`.
- The east plaza residential block opens a two-cell planted gate at `[40,23] → [40,22]`.
- The southern garden row opens a two-cell shared entrance at `[42,38] → [42,37]`.
- All surrounding building cells remain solid, so these read as restrained entries into small shared courts rather than holes through entire façades.
- The openings reuse the gates, arches, planting, and paving already authored into the Slice 237 PixelLab blocks. No disposable hard-coded gate art was added.

## Navigation contract

`solid_lots` now accepts an optional `open_cells` list. It is deliberately separate from `door`:

- `door` remains a functional building/portal threshold;
- `open_cells` describes public exterior space inside a decorative block footprint;
- runtime navigation and static map audit read the same authored cells;
- malformed or out-of-footprint entries fail the map audit;
- `space_test` asserts all six courtyard cells are walkable and three neighboring shell cells remain blocked.

This keeps access data in the lot definition rather than embedding one-off coordinate exceptions in pathfinding.

## PixelLab reuse receipt

No new generation was needed. This slice reuses three reviewed 128 px PixelLab compositions from Slice 237 and aligns navigation to their visible openings:

| Reused asset | PixelLab object | Access cue |
|---|---|---|
| `infill_market_block.png` | `63ed2cd0-b021-450a-b85b-bcc25c655c0b` | right-hand ground-floor arch |
| `infill_residential_courtyard.png` | `02c06002-ea67-4a46-a756-af3c180657a3` | central planted courtyard gate |
| `infill_garden_row.png` | `78a598f7-21c5-4452-9d94-d84405b80244` | central shared passage |

## Evidence

- [Plaza-facing market and residential courtyard entrances](media/240_plaza_courtyard_passages.png)
- [Southern garden-row shared entrance](media/240_garden_courtyard_passage.png)

## Simulation impact

- Visual lots and simulation `solid_lots` remain in 50/50 parity.
- Six cells reopen inside the three authored blocks; walkable cells move from 1,980 to 1,986. Typed terrain blockers remain 582.
- `lint_data.py`, `audit_map.py`, and `space_test` pass; all residents, worksites, objects, functional doors, and map areas remain connected.
- N=12, seeds 1–12, 60 days: hard invariants 12/12, every soft invariant 12/12, all 21 gated event classes live, and repeat determinism 3/3.
- Outcome and event digests remain identical to Slices 238–239. Production stays 1,977, shortages 438, invitations 750, aid coverage 9/12, and civic-duty coverage 8/12.
- Per-tick movement chains change in all 12 seeds, as expected for genuine route openings. Only those chains changed; the reviewed deterministic baseline was rebaked rather than hiding the route change.
- DetGate passes 16/16 across default, faction, betrayal, and free-rider tracks after the same movement-chain-only rebase. Data fingerprint: `70821154`.
- The pre-existing missing NobodyWho GDExtension warning remains non-blocking.

## Ordered-slice progress

1. **Occupied-home specialization:** delivered in Slice 238 as Coco's two-floor named-home prototype; live residency remains held behind household logistics.
2. **Beach civic-life district:** delivered in Slice 239 with four new PixelLab compositions and a coherent south promenade.
3. **Courtyard access language:** delivered here with three real gate/passage pockets and a reusable data contract.
4. **Street-corner activity props:** next — PixelLab-authored market, café, delivery, bicycle/cart, and flower-display kits placed only at meaningful junctions.
