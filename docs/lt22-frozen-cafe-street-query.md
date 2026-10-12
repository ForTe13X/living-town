# LT-22 frozen café and street query boundary

This is a read-only snapshot of the current playable café and its adjoining
`market_walk` frontage. The package is receiver-owned and is never installed
into `Sim`. The query returns detached spatial definitions. `Sim` remains the
authority for movement, owner access, jobs, actions, reservations, TownState,
saves, and RNG.

## Source and identity

The frozen input is the café at `game/data/map.json` area `cafe`, the two
`cafe` floors in `game/data/spaces.json` and `game/data/interiors.json`, and
the `market_walk` segment and café entrance link in
`game/data/coastal_plan.json`. The receiver-owned package is
`game/addons/worldgen/consumers/ai_town_adapter/fixtures/lt22_cafe_street.world.json`.
`native_inventory.json` records the native startup observation from which
the café planes, blockers, compiled interaction objects, and portals were
frozen. `identity_ledger.json` pins their reversible names, source hashes,
and the street segment and link. `host_action_bindings.json` is a detached
copy of the host advertisements; its action effects are not in the package.

| Source identity | Frozen package identity | Unit or policy |
| --- | --- | --- |
| `town/outdoor` in `[37,19,9,4]` | `town/outdoor` plane | 36 sampled cells; origin and size in integer q |
| `cafe/1f`, `cafe/2f` | Same space and floor strings | 48 cells per floor; floor elevation is unspecified |
| `p_cafe_door`, `p_cafe_stairs` | Same portal IDs and reversible `source_id` | Public street door; owner stairs retain `owner_space=cafe` |
| Six compiled café object IDs | Six allocated logical slot IDs with `source_id` | Source cell multiplied by 48 q; source hashes pin authored identity |
| Eight host advertisements | Eight logical affordance IDs | Host binding SHA-256 and capacity; no action grant |
| `market_walk` segment 4 and the `[41,19]` entrance link | `market_walk/cafe_frontage` with `source_id=market_walk` | Path and link in integer q; width is exact `8/5` cells |

Plan +X points east and +Z points south. One authored cell is 48 q.
`pixels_per_cell` belongs to presentation and can change without changing
topology. The street record includes the authored path segment `[36,21]` to
`[44,20]`; its first endpoint lies outside the clipped town sample. The
sample is deliberately a 9×4 rectangle and cannot answer questions about
the rest of the street. The `walkable` query returns false outside it.

The local snapshot envelope has `schema_id=WorldPackage` and
`schema_version=1`, following the proposed v5 artifact shape. It is a
`lt22.cafe_street_snapshot/1` profile. The checked-in worldgen runtime loader
expects its separate `{schema:"WorldPackage/1", semantic:...}` shape, and
its single-floor AI-town importer cannot consume this two-floor café. This
snapshot is **not** external v5 conformance or live runtime activation.

## Compatibility and change rules

`tools/worldpackage_boundary.py` regenerates the frozen package only from
the pinned inventory, ledger, and authored coastal plan. The local native
query revalidates against its embedded receiver-owned reference. It rejects
unknown envelope fields, malformed values, wrong units, changed topology,
changed state compatibility, and stale presentation hashes. A changed
presentation profile and pixel scale are accepted when their own digest is
updated. The active fingerprints are:

The Python interchange checker rejects float tokens, including `48.0`, in
canonical integer fields. Godot's JSON parser presents integral numeric
tokens as floats, so the native query checks integer value, range, and the
trusted semantic digest after parsing; it cannot distinguish the original
`48` spelling from `48.0` by itself.

| Fingerprint | SHA-256 |
| --- | --- |
| Topology | `508cebb8815419f4e0db4e6389825c49090a9bc103037b53595ce5b904ce7620` |
| Host bindings | `65a8eb16e8a627e3bea88515b798b8450ba26ffc17161affcb1a2eae83eb4dd0` |
| Identity ledger | `f38e2b0d82ff7eed5b62227feff36d4bf599dfba261458c2286e62ee00216710` |
| Reference presentation | `5f1eeebfe8ca7710fc3032b93051bb7c0c703c7a6b6efd309c7d3080971d705d` |

The Python checker also reports an occupied portal or affordance ID that a
candidate removed. Topology changes are rejected even when no such ID is
occupied. A structural replacement requires an explicit migration and a
separate activation decision. Decorative rendering changes have not been
shown visually compatible by this slice. Non-advertising furniture still
affects navigation when it blocks a cell, so it cannot be classified as
presentation based only on the absence of an advertisement.

## Reproduce

From the repository root:

```powershell
python -X utf8 -m unittest tools.tests.test_worldpackage_boundary -v
& 'D:\Documents\Dev\living-town\build\godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path game --script res://addons/worldgen/tests/frozen_cafe_street_queries_test.gd
```

The Python suite checks exact fixture regeneration, reversible mappings,
street units and source geometry, separate presentation fingerprints, and
hostile compatibility cases. The Godot test compares 132 package cells with
current `Sim` navigation, the complete café object and advertisement sets,
six source/logical slots, two portal records and their native hop costs,
eight advertisements with host records, and the street segment and
entrance link with `coastal_plan.json`. It rejects eight hostile candidates
and compares the exact café floor and portal ID sets in both authored files
and receiver-owned Sim snapshots. Three detached negative source cases add a
space floor, an interior floor, or a portal; each fails the same set gate.
The test compares native state/event digests and save bytes before and after.
The Godot process does not activate the package.

## Remaining qualification

External v5 schema and clean consumer qualification, walking and actor
clearance, verified approach geometry, full street coverage, rendered
presentation replacement, and safe structural migration are separate work.
The `market_walk` path and café entrance link are static references, not a
new route solver. The package has no live occupancy or TownState copy.
