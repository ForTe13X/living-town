# Living Town: ten-minute walkthrough narration

Script ready; recording and audio measurement pending. This document contains **1,307 spoken words** in 22 paragraphs across 11 chapters. Target voice: `en-US-AriaNeural`, normal rate (`+0%`). The recording route lasts 600 seconds at 24 frames per second.

The paragraph windows below are editorial targets. They provide 525 seconds of speech windows and 75 seconds of opening, closing, and inter-paragraph space. At the target allocation, individual paragraphs require approximately 141–155 words per minute. These are word-budget calculations, not measured TTS performance. Root will generate and measure Edge TTS audio and derive subtitles from actual word boundaries.

Use only the actual game capture for this walkthrough. At 04:30–07:30, display **INSPECTION — CAMERA ONLY**; moving the camera and opening a cutaway must not relocate a resident. The opening and closing observer views also stay visually distinct from controlled movement. Social outcomes must follow the recorded game; the script does not promise acceptance.

## Spoken script

### 01. A town you can enter

**00:02–00:21 · 01a**

Welcome to Living Town. This is the actual game view, with the delivered coastal town connected to the existing life simulation. Forty-nine buildings contain eighty-nine floors. Streets, courtyards, workshops, homes, and a small harbor share one place, shaped around everyday movement and the spaces between buildings.

*Capture note: Paused observer opening. Show the actual imported town in Main, not an offline Blender still. Avoid implying every building already has bespoke gameplay.*

**00:23–00:43 · 01b**

The view can move from a broad town plan to a resident's doorstep. Pale walls, dark roofs, stone paving, and planted edges give the settlement a clear coastal character. This tour will alternate between playing as one resident and inspecting the architecture. We will identify those inspection sections as they begin.

*Capture note: Slow observer camera only; simulation paused. Establish inspection/gameplay distinction before the first transition.*

### 02. Meet Aria and read the HUD

**00:47–01:11 · 02a**

We now take control of Aria through the existing life mode. Her upper-floor rooms sit above the café, with a bedroom, kitchen, bathroom, and a real route downstairs. The portrait, name, job, money, wishes, and needs belong to the same resident as before. The new town changes where her life is shown, while retaining her identity and rules.

*Capture note: Use public start_life('aria'), not direct agent-state edits. Owner apartment above café; do not describe it as an unrelated house.*

**01:14–01:38 · 02b**

The needs display tracks hunger, energy, social contact, fun, and hygiene. Watch it alongside the clock and the event history. Actions take time, and their results come from the simulation. Movement uses the keyboard or a ground click. Nearby people, furnishings, and doors offer interactions through the familiar menu and the E key. Zoom changes the view without changing Aria's state.

*Capture note: Keep existing LifeMode HUD readable. Show needs, time, and an available prompt. Camera changes are view-only; no claim that camera motion advances time.*

### 03. Walk the rooms and take the stairs

**01:42–02:06 · 03a**

Here, movement follows the room layout. Walls, furniture, and stair openings define where Aria can stand. The interior grid is finer than the outdoor grid, so a narrow room can have a reachable approach to its bed or counter. Clicking through a wall does not make a shortcut. The route must find a legal way around the obstruction.

*Capture note: Record real input and visible multi-frame walking. Indoor cells are 0.25m; outdoor cells 0.5m. Do not claim continuous physics navigation or a navmesh.*

**02:09–02:33 · 03b**

The stairs connect separate simulation floors at an authored opening. Aria approaches the stair, uses its transition, and arrives on the level below. That matters for access as well as appearance: a private stair is not automatically available to every resident. The character keeps the original walking animation and directional art, now positioned at the correct height in the three-dimensional rooms.

*Capture note: Use the genuine café owner stair route. No teleporting or direct Sim writes. Permissions remain existing engine authority. Sprite height is 1.7m, grounded from the projection.*

### 04. Use a real café fixture

**02:37–03:03 · 04a**

Downstairs, we choose the café counter itself. A click on the visible furnishing resolves to an existing functional object and a reachable place beside it. The menu offers the actions that the engine permits. Aria walks to the approach and spends time completing the selected action. Its effect appears in her state and event history, rather than being added by the renderer.

*Capture note: Capture actual counter mesh pick, legal menu, walking approach, and completion. Counter aliases can share the physical fixture; do not insist on one alias label if another legal menu resolves.*

**03:06–03:33 · 04b**

The model contains seven hundred and fifty-three furnishing assemblies, but decoration and function are different layers. Sixty-three functional objects are mapped into this town. A shelf or flower pot does not gain an action just because it has geometry. Social interaction also keeps its existing checks: distance, access, and the other resident's response matter. The record lets us see what actually happened, including an unsuccessful attempt.

*Capture note: Do not claim all 753 assemblies are interactive. Social footage must be an actual attempt; acceptance is not guaranteed. If no social event occurs here, show the interaction opportunity and retain the later attempt chapter.*

### 05. Step outside and keep the resident visible

**03:37–04:01 · 05a**

We leave through the café's real doorway and step into the public street. The character remains a two-dimensional sprite, using the retained character sheets inside a three-dimensional world. Its body has normal depth, so a roof or tree can pass in front of it. The ground marker and doorway prompt stay tied to the resident's actual position and nearby opportunity.

*Capture note: Use genuine exterior portal. Retain buildings and trees. Do not describe sprite art as new 3D character meshes.*

**04:04–04:28 · 05b**

When geometry blocks the camera's view of the controlled resident, a gold silhouette makes Aria readable. It appears only for that obstruction; the normal sprite still obeys depth. In a clear view, the silhouette disappears. This keeps the awning and roof in place while helping us follow a person through the street. We now walk toward the plaza with the same controls.

*Capture note: Show real blocked line of sight under the café awning and a clear view if available. The controlled-only ghost is model-geometry tested at 5 Hz; do not claim all NPCs become visible through buildings.*

### 06. Inspection: rooms and furnishing

**04:32–04:58 · 06a**

This next section is architectural inspection. We move the camera and reveal selected floors; we are not moving Aria into these rooms. Across the town, five hundred and sixty-one logical zones include both rooms and circulation. Two hundred and twenty-three are activity rooms. Those distinctions help separate a bedroom or workroom from the hall, landing, and stair space that makes it usable.

*Capture note: Display INSPECTION — CAMERA ONLY throughout 270–330 seconds. Camera/probe and local cover changes only; preserve resident positions. Counts are final 561 zones / 223 activity rooms, superseding the earlier 549-zone plan.*

**05:01–05:28 · 06b**

Look for the practical pieces that explain each room: beds and storage in sleeping rooms, bookshelves and tables in the library, and separate enclosed bathrooms in the hotel suites. Kitchens have a sink, hob, and a distinct small refrigerator. Furnishings are grouped by room and floor, so a cutaway can expose one interior while neighboring buildings retain their roofs. These are authored layouts, not a claim of building-code approval.

*Capture note: Inspect planned library/home/hotel cameras using actual imported geometry. Some asset detail may be small in the game view; do not replace this with offline stills without labeling them. Widths are nominal authored dimensions.*

### 07. Inspection: streets, elevations, and harbor

**05:32–05:58 · 07a**

We remain in inspection mode as the camera follows the town's outdoor structure. Residential rows turn at different angles, streets bend, and small passages lead into courts. The buildings do not sit on one flat board. Roads, plazas, and building pads have authored elevations, while entrance thresholds connect the visible model to the movement grid. The harbor sits at the coastal edge of that same site.

*Capture note: Display INSPECTION — CAMERA ONLY. Show irregular layout and actual surface elevation. No claim of resident traversal along every camera movement.*

**06:01–06:28 · 07b**

These levels describe a fictional engineered site. They give the quay, streets, and planted ground a coherent relationship, but they are not a surveyed coast or a hydraulic study. Terrain heights ground residents, and authored blockers keep them out of building footprints and the pond. That movement contract is distinct from general physics. The model does not supply every collision or navigation feature that another game might need.

*Capture note: Do not imply certified drainage, shoreline physics, imported GLB collisions, or a generated navmesh. Current bridge movement uses the canonical grid/profile.*

### 08. Inspection: pond and planted routes

**06:32–06:58 · 08a**

The park pond is a cut into the terrain, with a level water surface and graded banks around a lower bed. A continuous shore, reeds, benches, and a connected walking loop make its edge readable. This is an ornamental pond with authored geometry. The camera can show its shape, while the movement rules keep residents on accessible ground instead of allowing a path straight across the water.

*Capture note: Display INSPECTION — CAMERA ONLY. Pond water Z is -0.12 m and bed Z is -0.92 m, with a real basin and banks. Avoid unsupported natural hydrology, swimming, or wildlife claims.*

**07:01–07:28 · 08b**

Fifty-two placed landscape trees help shape streets, courts, and the park, with broader crowns and willows around the pond. Layered flower beds, low planting, garden islands, and coastal grasses add another scale of detail. Openings in the planting preserve doors, paths, and views. The aim is a town with shade and garden enclosure, where a walk has edges and destinations, rather than scattered props across an empty lawn.

*Capture note: The count of 52 refers to planned local landscape trees, not every background forest tree. Show actual connected canopy and horticulture; do not equate projected crown envelopes with measured opaque shade.*

### 09. Return to life and enable autonomy

**07:32–07:56 · 09a**

We return to Aria and resume the life simulation. Turning on autonomy lets the existing decision system choose among available actions. Needs, jobs, access, and circumstances shape those choices. The three-dimensional view follows the resulting movement and activity; it does not create a second simulation. The logic backend runs locally without downloading a language model or requiring generated dialogue for an action.

*Capture note: End INSPECTION label, restore controlled resident view, then enable autonomy through existing LifeMode input/public API. No direct writes to agent location, needs, money, or clock.*

**07:59–08:23 · 09b**

Watch a social attempt closely. A visible neighbor must also be reachable in the same valid space. Walls, floors, and access rules still matter when the camera can see both people. Acceptance or refusal belongs to the running game. Read the event and need changes together, and let the recorded result tell us whether this attempt became a completed interaction.

*Capture note: Record actual social attempt and observed outcome. Do not force another agent's state or narrate a guaranteed success. If unavailable, note the real access/availability reason in the recording evidence.*

### 10. Save, continue, and load

**08:27–08:51 · 10a**

Now we save with F five, let the game continue, and load with F eight. The save belongs to the existing simulation and life mode, including the controlled resident and her state. Loading rebuilds the view from that state. The three-dimensional profile uses its own quicksave file. Incompatible spatial data is rejected instead of loading into a different town layout.

*Capture note: Capture real F5/F8 event dispatch and loaded-state evidence. Narration assumes this recorded step succeeds; if it fails, fix/re-record or revise truthfully. Separate user://town3d_quicksave.dat from the legacy save.*

**08:54–09:18 · 10b**

The art also has a portable life. Blender sources and engine-neutral exports retain named buildings, floors, rooms, materials, and furnishing groups. The game bridge binds those assets to its spatial profile. Frozen file hashes, license credits, and test evidence record which versions were delivered. The package remains inspectable and reproducible without making this engine the town's only possible consumer.

*Capture note: Camera can slowly widen while the saved/loaded game remains visible. Engine-agnostic GLB exports are a separate art delivery; avoid implying the runtime loads the high-detail 642 MB GLB. Original maps plus the CC0 HDRI and OFL font are credited in accompanying docs.*

### 11. What the delivery proves

**09:22–09:39 · 11a**

The editable game passed twenty-eight logical checks, twenty-seven visual interaction checks, and eleven selected legacy regressions. The packaged Windows build separately passed a normal launch and actual rendered-screen check. That packaged boot check does not repeat the full interaction suite.

*Capture note: Slow whole-town closing view. Distinguish source-runtime gameplay evidence from exported native boot/render proof; do not claim 27 exported interaction checks.*

**09:42–09:59 · 11b**

This playable bridge connects detailed places, retained residents, and observable consequences. It does not establish finished balance, unlimited population, or broad hardware performance. The full town loads together. You can inspect a resident moving, acting, and saving within the existing rules.

*Capture note: No LOD, streaming, imported collision authority, or performance guarantee. End on the actual game view, not the concept image. Let the last spoken word finish before 600 seconds.*

## Subtitle and audio handoff

Keep the 1280 × 768 game frame intact. Append a 96-pixel dark matte band underneath it, producing a 1280 × 864 master, and place captions in that band. This avoids covering the bottom needs panel, wishes, chronicle, and interaction controls. A widescreen publication version may letterbox this master; it should preserve the complete HUD.

Use ASS PlayRes 1280 × 864, bottom-center alignment 2, Arial at 25 pixels, side margins 48, bottom margin 15, white text, a 2-pixel dark outline, and a subtle 0.7-pixel shadow. Limit captions to two lines, roughly 54 characters per line. Break at phrases and punctuation. Use actual measured word boundaries, usually 1.1–4.5 seconds per cue. Verify the selected font and inspect the finished frames; these are proposed settings, not a rendered subtitle PASS.

Generate each paragraph separately so the chapter route stays stable. Keep a natural, restrained read. If a measured take overruns its window, make a small wording edit and regenerate that take; do not speed up gameplay or invent a completed action. Leave audible breathing room at chapter changes. Retain real game audio only if captured, and duck it beneath narration. Do not add invented interaction sounds as evidence.

## Evidence boundaries

- Authoring inventory: 49 buildings, 89 floors, 561 logical room/circulation zones, 223 activity rooms, 753 furnishing assemblies, 40 stair flights, and 52 specifically planned local landscape trees. Background woodland is separate.
- Gameplay scope: 63 functional objects mapped to the existing simulation. Decoration alone does not create an economic or needs action. Shared fixture aliases retain the engine’s original identities.
- Existing editable-runtime evidence: 28 logical checks, 27 visual interaction checks, and 11 selected legacy regressions.
- Packaged Windows evidence: normal Main entry, actual GPU boot/render capture, and binary hash bindings. It does not repeat the full source-runtime interaction suite.
- Outdoor movement uses authored grid/profile blockers and terrain heights. No claim of a general imported collision system, navmesh, streaming, LODs, building-code certification, natural hydrology, finished balance, or broad hardware performance.
- Engine-neutral art sources/exports and their licenses remain separately delivered. The current bridge consumes the optimized staged model, not the optional high-detail town export.

Authoritative narration data: [narration.json](narration.json). Recording chapter contract: [chapter_outline.md](chapter_outline.md). The route implementation and recording proof are owned by the capture agent/root; no recording, TTS generation, or subtitle burn was performed while writing this script.
