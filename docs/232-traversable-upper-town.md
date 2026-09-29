# Slice 232 — Traversable upper town

## Outcome

The western cliff compound is now a playable destination rather than a façade-only elevation cue.

- `cliff_walk` is an authored public area above a five-cell blocking cliff lip.
- A single open cell at `[4,13]` forms the canonical stair crossing; normal town pathfinding uses it without a second outdoor plane or a decorative portal.
- The overlook at `[7,12]` is a real world object advertising the low-intensity `看海` leisure action (`fun +36`, duration 18).
- The grand stairs and overlook use large PixelLab compositions with transparent alpha, grounded shadows, and footprint-independent presentation scale.
- The last decorative west terrace bands were removed after full-town review: they still looked like parallel highways. The boundary now shows one two-way entrance road only, with elevation carried by the mountain, grove, and cliff-house silhouettes.

## PixelLab asset receipt

Mode: 1-direction review pack, 128 × 128 px, transparent background; all four candidates were reviewed and promoted as reusable production objects.

Source review: `72aa730b-41e7-4894-a2e9-7a194306c997`

Prompt: `cohesive public access kit for a refined French Atlantic cliff town, low top-down pixel art, transparent background, pale weathered granite, ironwork and summer hydrangeas, detailed but readable at game scale, no people no text`

- `398c08cf-41ab-46a7-9969-da7d048d6769` → `game/assets/art/props/cliff_grand_stairs.png`
- `b5b4bffa-c358-4ae3-8420-5e85c4b86ff5` → `game/assets/art/props/cliff_overlook.png`
- `6b044399-cf5d-420a-9180-9b996122464a` → `game/assets/art/props/cliff_switchback_stairs.png`
- `40d8f138-93e3-4676-a176-89824a2d64d7` → `game/assets/art/props/cliff_arch_passage.png`

The first two are integrated in this slice. The switchback and arch are retained as coherent factory assets for later terrace streets; they are not duplicated as disposable hard-coded drawings.

## Evidence

- [Upper-town access close view](media/232_upper_town_access.png)
- [Whole-town composition with the single west road](media/232_upper_town_full.png)

## Verification and simulation impact

- `lint_data.py`: pass; 25 JSON files parsed and foreign keys resolve.
- `audit_map.py`: pass; 2,068 walkable cells, 574 typed blockers, nine world objects, and all authored destinations reachable.
- `space_test`: 0 failures; existing doors, stairs, owner-only access, and portal authority remain intact.
- `player_touch_test`: pass; player controls and banking UI paths remain equivalent to their canonical simulation calls.
- N=12, seeds 1–12, 60 days: hard invariants 12/12; every soft invariant passes 12/12 except the known pastry-supply fluctuation #40 at 11/12 (seed 6); all 21 gated event classes remain live.
- Determinism: 3/3 repeated summaries, incremental digests, and tick-prefix chains match.
- Civic duty remains active in 8/12 seeds, so the new leisure action does not crowd governance out of the default simulation.
- Scenario gate after rebaking the intentional new default traces: hard 16/16, repeat 16/16, data fingerprint 16/16, golden 16/16. Only three of four default-scenario seeds changed; faction, betrayal, and free-rider tracks remained byte-identical.
- Godot still prints the pre-existing missing NobodyWho GDExtension warning; it is unrelated and non-blocking for logic/render gates.

## Whole-slice progress

- Town frame: mountain/forest boundary, open coast, and one land entrance are implemented; residual road-like terrace bands are gone.
- Urban composition: larger beach/plaza, tighter blocks, varied seasonal façades, and cliff housing are implemented.
- Interiors: semantic large furniture, denser room composition, a segmented hotel floor, and bidirectional stairs are implemented.
- Elevation: one upper-town destination is now physically traversable and simulation-active; a general height-aware street network is not yet implemented.
- Simulation: the new destination is deterministic, reachable, live, and does not create a detected economic, social, governance, or portal regression.

## Coherent next candidates

1. **Room-plan vocabulary:** authored doorway and arch slots, room-purpose tags, and multi-floor private homes with kitchens, bedrooms, bathrooms, and living rooms.
2. **Upper-town street pair:** use the retained switchback and arch assets for a second terrace route and two or three compact attached blocks, with route heat-map review before expanding further.
3. **Street-block consolidation:** re-author the loose plaza and north-avenue frontages into continuous 4–6 façade blocks while preserving door and worksite access.
4. **Beach civic life:** cabins, café terraces, promenade steps, and social objects that make the enlarged shore function as a district rather than scenery.
