# Living Town: ten-minute walkthrough narration

The delivered narration contains **945 spoken words** in 22 measured paragraphs across 11 chapters, using normal-rate `en-US-AriaNeural` (`+0%`). The actual game recording lasts 600 seconds at 24 frames per second. See [the final walkthrough evidence](README.md) for the exact movie, source bindings, technical results, and separate encoded-frame review. Human audio listening is not asserted.

The paragraph windows below retain the editorial schedule: 524 seconds of speech windows and 76 seconds of opening, closing, and inter-paragraph space. All 22 current voice takes were generated and measured within those windows; the exact durations and cached audio hashes are in the final voice report. Subtitles use actual Edge TTS word boundaries. Technical audio measurements establish duration, decode integrity, RMS and peak; they do not establish human listening acceptance.

Use only the actual game capture for this walkthrough. At 04:30–07:30, display **INSPECTION — CAMERA ONLY**; moving the camera and opening a cutaway must not relocate a resident. The opening and closing observer views also stay visually distinct from controlled movement. Social outcomes must follow the recorded game; the script does not promise acceptance.

An earlier, longer normal-rate Aria take measured 21.768 seconds against a 19-second window and was rejected. The current shorter revision passed measurement for every take while preserving the ten-minute route and real observation gaps.

## Spoken script

### 01. A town you can enter

**00:02–00:21 · 01a**

Welcome to Living Town. This is the running game, connecting the coastal model to the existing life simulation. Forty-nine buildings contain eighty-nine floors, linked by streets, courts, homes, workshops, and a small harbor.

*Capture note: Paused observer opening. Show the actual imported town in Main, not an offline Blender still. Avoid implying every building already has bespoke gameplay.*

**00:23–00:43 · 01b**

We will play as one resident, then inspect the architecture. Pale walls, dark roofs, stone paving, and planted edges give this town its coastal character. Camera-only inspection will be labelled clearly, separate from the resident's actual movement.

*Capture note: Slow observer camera only; simulation paused. Establish inspection/gameplay distinction before the first transition.*

### 02. Meet Aria and read the HUD

**00:50–01:13 · 02a**

We choose Aria through the existing life mode. Her upper-floor rooms sit above the café, with a real route downstairs. The portrait, name, job, money, wishes, and needs belong to the same resident as before. Her identity and rules are retained.

*Capture note: The selector appears at 45 seconds and public start_life('aria') runs at 50 seconds. Begin this paragraph at that genuine selection transition. Owner apartment above café; no direct agent-state edits.*

**01:14–01:38 · 02b**

The bars track hunger, energy, social contact, fun, and hygiene. Watch them beside the clock. Actions take time. Use the keyboard or a ground click to walk, and E to interact nearby. Zoom changes the view without changing Aria's state.

*Capture note: Keep existing LifeMode HUD readable. Show needs, time, and an available prompt. Camera changes are view-only; no claim that camera motion advances time.*

### 03. Walk the rooms and take the stairs

**01:42–02:06 · 03a**

Walls, furnishings, and stair openings define where Aria can stand. The interior grid is finer than the outdoor grid, allowing reachable approaches beside beds and counters. A click through a wall cannot create a shortcut. Movement must find a legal route around it.

*Capture note: Record real input and visible multi-frame walking. Indoor cells are 0.25m; outdoor cells 0.5m. Do not claim continuous physics navigation or a navmesh.*

**02:09–02:33 · 03b**

The stair transition has brought Aria downstairs through a legal opening. Private stairs are not available to every resident. At the café table, a meal uses the existing action system. We watch for actual completion and its effect on her needs.

*Capture note: Past-tense recap of the actual stair transition just seen. The full route now shows the table meal; record its actual completion and need effect. Do not infer completion from a preview that skips this dwell.*

### 04. Use a real café fixture

**02:37–03:03 · 04a**

We click the visible café counter. The furnishing resolves to an existing functional object and a reachable approach beside it. Its menu offers permitted actions. Aria walks into place and takes time to act. The simulation records the result in her state and history.

*Capture note: Capture actual counter mesh pick, legal menu, walking approach, and completion. Counter aliases can share the physical fixture; do not insist on one alias label if another legal menu resolves.*

**03:06–03:33 · 04b**

The town has seven hundred and fifty-three furnishing assemblies. Only mapped functional objects offer game actions. Decorative shelves and pots do not automatically offer actions. Social attempts retain the existing access checks and the other resident's response. Jobs and wages retain their existing engine rules.

*Capture note: Do not claim all 753 assemblies are interactive. Functional mapping count belongs to the current compiled profile; the compiler may add mapped civic fixtures, so this paragraph deliberately avoids an obsolete total. Social footage must be an actual attempt and acceptance is not guaranteed.*

### 05. Step outside and keep the resident visible

**03:37–04:01 · 05a**

Aria leaves through the real café doorway. Her original directional character sheets now appear inside a three-dimensional world. The body keeps normal depth, so roofs and trees can pass in front of it. Ground markers and interaction prompts remain attached to her actual position.

*Capture note: Use genuine exterior portal. Retain buildings and trees. Do not describe sprite art as new 3D character meshes.*

**04:04–04:28 · 05b**

When geometry blocks the controlled resident, a gold silhouette keeps Aria readable. It appears only during that obstruction. The normal sprite still obeys depth, and the silhouette disappears in clear views. The awning and roof remain in place as we walk toward the plaza.

*Capture note: Show real blocked line of sight under the café awning and a clear view if available. The controlled-only ghost is model-geometry tested at 5 Hz; do not claim all NPCs become visible through buildings.*

### 06. Inspection: rooms and furnishing

**04:32–04:58 · 06a**

This is architectural inspection: camera movement, not Aria's travel. The town has five hundred and sixty-one logical zones, including circulation. Two hundred and twenty-three are activity rooms. Halls, landings, and stairs connect those rooms, giving each interior a usable layout. Each group is named and inspectable.

*Capture note: Display INSPECTION — CAMERA ONLY throughout 270–330 seconds. Camera/probe and local cover changes only; preserve resident positions. Counts are final 561 zones / 223 activity rooms, superseding the earlier 549-zone plan.*

**05:01–05:28 · 06b**

Look for beds and storage, library shelves and tables, and enclosed bathrooms in hotel suites, with bedroom privacy preserved. Kitchens have sinks, hobs, and distinct refrigerators. Room and floor groups let a cutaway expose one interior while neighboring roofs remain intact. These authored dimensions do not establish building-code approval.

*Capture note: Inspect planned library/home/hotel cameras using actual imported geometry. Some asset detail may be small in the game view; do not replace this with offline stills without labeling them. Widths are nominal authored dimensions.*

### 07. Inspection: streets, elevations, and harbor

**05:32–05:58 · 07a**

We remain in inspection mode. Residential rows turn, streets bend, and passages lead into courts. The town has actual surface elevations and gently graded paths rather than a flat board. Roads, plazas, and building pads meet entrance thresholds. The harbor sits at the coastal edge of the same site.

*Capture note: Display INSPECTION — CAMERA ONLY. Show irregular layout and actual surface elevation. No claim of resident traversal along every camera movement.*

**06:01–06:28 · 07b**

This is a fictional engineered site, not a surveyed coast or hydraulic study. Terrain heights ground residents, while authored blockers exclude building footprints and water. The movement contract uses the game's spatial grid. Another engine would still need its own decisions about physics, collision, and navigation.

*Capture note: Do not imply certified drainage, shoreline physics, imported GLB collisions, or a generated navmesh. Current bridge movement uses the canonical grid/profile.*

### 08. Inspection: pond and planted routes

**06:32–06:58 · 08a**

The park pond cuts into the terrain, with level water above a lower bed and graded banks. A continuous shore, reeds, benches, and a connected loop make the edge readable. This is an authored ornamental pond. Movement rules keep residents on accessible ground beside the water, with planted edges.

*Capture note: Display INSPECTION — CAMERA ONLY. Pond water Z is -0.12 m and bed Z is -0.92 m, with a real basin and banks. Avoid unsupported natural hydrology, swimming, or wildlife claims.*

**07:01–07:28 · 08b**

Fifty-two planned landscape trees shape streets, courts, and the park. Broad crowns and willows frame the pond. Flower beds, garden islands, low planting, and coastal grasses add smaller detail. Openings preserve doors, paths, and views. The aim is shade and garden enclosure along useful walking routes. Background woodland adds distant enclosure.

*Capture note: The count of 52 refers to planned local landscape trees, not every background forest tree. Show actual connected canopy and horticulture; do not equate projected crown envelopes with measured opaque shade.*

### 09. Return to life and enable autonomy

**07:32–07:56 · 09a**

We return to Aria for a social attempt. A visible neighbor must also be reachable. Walls, floors, and access rules matter even when both people appear on screen. Acceptance or refusal belongs to the running game. Read the event and need changes to see the outcome.

*Capture note: End INSPECTION label and restore normal resident view. Actual social attempt is at 450–473 seconds, before autonomy. Do not force another agent's state or promise success. If unavailable, record the real access/availability reason.*

**07:59–08:23 · 09b**

Now we enable autonomy. The existing decision system chooses available actions according to needs, jobs, access, and circumstances. The view follows the movement and activity; it does not create a second simulation. This logic backend runs locally without a downloaded language model or required generated dialogue.

*Capture note: Actual autonomy begins at about 473 seconds, after the social attempt. Enable it through existing LifeMode input/public API. No direct writes to resident position, needs, money, or the clock.*

### 10. Save, continue, and load

**08:27–08:51 · 10a**

We save with F five, let the game continue, and load with F eight. Loading rebuilds the view from the saved simulation and resident state. The three-dimensional profile uses a separate quicksave. Incompatible spatial data is rejected instead of loading into a different layout.

*Capture note: Capture real F5/F8 event dispatch and loaded-state evidence. Narration assumes this recorded step succeeds; if it fails, fix/re-record or revise truthfully. Separate user://town3d_quicksave.dat from the legacy save.*

**08:54–09:18 · 10b**

The art remains portable. Blender sources and engine-neutral exports keep named buildings, floors, rooms, materials, and furnishing groups. This bridge binds them to its spatial profile. Frozen file hashes, license credits, and test evidence record the delivered versions, leaving the town usable by other consumers.

*Capture note: Camera can slowly widen while the saved/loaded game remains visible. Engine-agnostic GLB exports are a separate art delivery; avoid implying the runtime loads the high-detail 642 MB GLB. Original maps plus the CC0 HDRI and OFL font are credited in accompanying docs.*

### 11. What the delivery proves

**09:22–09:39 · 11a**

The editable runtime passed thirty-six logical checks and twenty-eight visual checks. Legacy regression scenes also passed. The Windows package separately passed normal launch and screen-render checks, rather than the full interaction suite.

*Capture note: Slow whole-town closing view. Distinguish source-runtime gameplay evidence from exported native boot/render proof; do not claim 28 exported interaction checks.*

**09:42–09:59 · 11b**

This bridge connects places, retained residents, and observable consequences. It does not establish finished balance or broad hardware performance. The full town loads together. Inspect movement, actions, and saved life.

*Capture note: No LOD, streaming, imported collision authority, or performance guarantee. End on the actual game view, not the concept image. Let the last spoken word finish before 600 seconds.*

## Subtitle and audio handoff

Keep the 1280 × 768 game frame intact. Append a 96-pixel dark matte band underneath it, producing a 1280 × 864 master, and place captions in that band. This avoids covering the bottom needs panel, wishes, chronicle, and interaction controls. A widescreen publication version may letterbox this master; it should preserve the complete HUD.

Use ASS PlayRes 1280 × 864, bottom-center alignment 2, Arial at 25 pixels, side margins 48, bottom margin 15, white text, a 2-pixel dark outline, and a subtle 0.7-pixel shadow. Limit captions to two lines, roughly 54 characters per line. Break at phrases and punctuation. Use actual measured word boundaries, usually 1.1–4.5 seconds per cue. Verify the selected font and inspect the finished frames; these are proposed settings, not a rendered subtitle PASS.

Generate each paragraph separately so the chapter route stays stable. Keep a natural, restrained read. If a measured take overruns its window, make a small wording edit and regenerate that take; do not speed up gameplay or invent a completed action. Leave audible breathing room at chapter changes. Retain real game audio only if captured, and duck it beneath narration. Do not add invented interaction sounds as evidence.

## Evidence boundaries

- Authoring inventory: 49 buildings, 89 floors, 561 logical room/circulation zones, 223 activity rooms, 753 furnishing assemblies, 40 stair flights, and 52 specifically planned local landscape trees. Background woodland is separate.
- Gameplay scope: Only explicitly mapped functional objects belong to the existing simulation; the exact total follows the current compiled profile. Decoration alone does not create an economic or needs action. Shared fixture aliases retain the engine’s original identities.
- Current editable-runtime evidence: 36 logical checks and 28 visual interaction checks. The fresh hosted regression report records 35 passing legacy scenes. The older 11 selected regressions are historical evidence.
- Packaged Windows evidence: normal Main entry, actual GPU boot/render capture, and binary hash bindings. It does not repeat the full source-runtime interaction suite.
- Outdoor movement uses authored grid/profile blockers and terrain heights. No claim of a general imported collision system, navmesh, streaming, LODs, building-code certification, natural hydrology, finished balance, or broad hardware performance.
- Engine-neutral art sources/exports and their licenses remain separately delivered. The current bridge consumes the optimized staged model, not the optional high-detail town export.

Authoritative narration data: [narration.json](narration.json). Recording chapter contract: [chapter_outline.md](chapter_outline.md). The route implementation and recording proof are owned by the capture agent/root; no recording, TTS generation, or subtitle burn was performed while writing this script.
