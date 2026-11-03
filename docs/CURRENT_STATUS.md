# Living Town current status

**3 November 2026: Unreal migration is active; the requested town is unfinished.** Unreal is the primary runtime target. Godot remains a reference archive. The full [active roadmap](active-town-roadmap.md) includes production characters and everyday actions, varied furnished interiors, contour-led terrain and vegetation, broader simulation slices, performance, and a new narrated walkthrough.

The latest merged native gameplay baseline is [PR #115](https://github.com/ForTe13X/living-town/pull/115), commit `654e46424ce930c7bd352a68457e571fb407e8bf`. Its opt-in café WorldV3 mode uses one property, coin, stock and care authority with paired V4 saves. Editor and Game builds plus six native tests passed. The reachable counter refuses a meal without charging while a reviewed eating provider is absent. See [scope and evidence](asset_refinement/native_cafe_world_v3_adoption.md). This is a bounded café slice; it does not establish completed eating, full-town play or performance.

| Area | Current evidence | Next required result |
| --- | --- | --- |
| Character | The original Tripo worker remains the visual baseline. Actual FBX inspection preserves visible geometry, UVs, original bones and up to seven body influences. Source-rate raw idle/walk comparisons pass; compressed animation still fails the stricter reference tolerance. The generic replacement head was rejected after whole-character review. | Preserve the original identity with suitable facial topology, UVs and baking; complete a visible textured native resident with credible cloth and actions. Then replace the roster and UI portraits. |
| Interiors | Local room/linen work has actual Blender reviews. Authored bedding retains its folds at 48,000 triangles, reduced from 111,744. | Verify portable PBR roundtrips and distance LODs, adopt assets in Unreal, and finish room variety, decoration, lighting and playable routes. |
| Terrain and reserve | Local pond-bank grading and woodland composition have reviewed Blender results. | Complete reserve coverage, planting and transitions, then verify native collision, navigation, streaming, startup and frame cost. |
| Broader simulation | Native café property/meal-care foundations are merged. | Complete remaining civic, property/work, seasonal production, visitors and cultural journeys in Unreal. Source or portable tests alone do not close the roadmap rows. |
| Delivery | Earlier packages and recordings remain recoverable references. | Produce a new lengthy MP4 with narration/subtitles, derive its README GIF, and verify the current playable delivery. |

[Character pipeline findings and local evidence](asset_refinement/character_pipeline_convergence.md) record stopped approaches, accepted local improvements and remaining work. Local authoring inspection is distinct from product adoption. Full-town ordinary-game frame rate, loading duration and final visual acceptance remain open.

The preceding [3 October Godot candidate status](history/rcb_candidate_status_2026-10-03.md) is preserved as historical evidence. Its package, captures and pending acceptance statements describe that older candidate.
