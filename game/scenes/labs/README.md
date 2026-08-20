# Map Tile Lab

An isolated two-scale gameplay spike for deciding whether Living Town should grow beyond one continuous town map.

The lab keeps the current production scene untouched. It owns a private deterministic model and never calls `Sim.start_new()`, writes `Sim.world`, or makes simulation state depend on what the player is viewing.

## Play the slice

```bash
godot --path game res://scenes/labs/MapTileLab.tscn
```

World map:

- Mouse or `WASD` / arrows: select a hex and plan the lowest-cost route.
- Right-click, `Enter`, or `Space`: start caravan travel.
- Double-click the caravan's current tile: enter its local map.

Local map:

- `WASD` / arrows: one-cell tactical step.
- `E` / `Space`: loot or interact with the extraction marker.
- `F`: strike an adjacent contact.
- `X` / `Esc`: extract when standing at the striped west-edge marker.

## What the references contribute

- **RimWorld:** a strategic hex surface where biome, road, risk, forage, supply, and elapsed time make a tile choice consequential.
- **Project Zomboid:** authored building footprints, doors/windows, room dividers, and per-building roof groups that cut away only after crossing a threshold.
- **Zero Sievert:** compact raid pressure through noise, contact alerting, carried weight/value, loot categories, and a visible extraction route.
- **Stoneshard:** crisp orthogonal steps, sparse high-contrast information, and a turn ledger that keeps every action readable.

These are interaction and readability references, not asset copies. The current art is drawn procedurally from Living Town's own palette family.

## Focused verification

```bash
godot --headless --path game res://scenes/labs/map_tile_lab_test.tscn
```

The gate checks fixed-seed receipts, hex route continuity, travel settlement, local-map determinism, loot reachability, solid walls, roof reveal, looting, and extraction round-trip state.

Screenshot hooks are intentionally deterministic:

```bash
godot --path game res://scenes/labs/MapTileLab.tscn -- --lab-seed 260814 --lab-shot /tmp/world.png
godot --path game res://scenes/labs/MapTileLab.tscn -- --lab-seed 260814 --lab-local --lab-shot /tmp/local.png
```

## Deliberately not promoted yet

- No link to `Main.tscn`, save migration, or production HUD.
- No attempt to encode world tiles as `SpaceGraph` rooms.
- No claim that four authored shells constitute a production procedural-building generator.
- No caravan roster, social consequences, persistent tile depletion, ranged combat, or multi-floor local sites yet.

The next promotion decision should be evidence-led: whether traveling, entering a roofed site, taking a noisy loot risk, and extracting back to the caravan is already a compelling loop before any of those systems are connected to the town simulation.
