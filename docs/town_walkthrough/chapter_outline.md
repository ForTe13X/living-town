# Expanded-town walkthrough contract

**Current target: 14:00, 18 FPS, 15,120 actual tour frames, MovieWriter AVI at 44,100 Hz.** There are 12 chapters and 24 Edge TTS paragraphs. The new full gameplay capture, composed MP4 and encoded-media review are pending. Current voice measurements fit; the final two paragraphs measure 11.064 and 10.224 seconds in 14.875-second windows. This is voice evidence only.

[route_plan.json](route_plan.json) defines the windows below; [narration.json](narration.json) defines the speech. [RECORDING.md](RECORDING.md) gives the reproducible commands and evidence gates. The director instantiates actual `Main`/`LifeMode`, while `Sim` owns movement, access, needs, actions and saved state. It loads the complete staged town, including the expansion and reserve, rather than a separate asset viewer.

Before 00:00, public LifeMode selection and real speed-key input establish morning through live waiting. The harness pauses and restores the selector. This setup is captured in the measured boot prefix and trimmed from the tour; it does not assign the clock or relocate Aria.

| Time | Chapter | Mode | Required evidence |
|---|---|---|---|
| 00:00–00:45 | 01. Town, woodland and coast | Camera inspection | Real Main overview; complete v2 chunk set and all 151 buildings loaded; at least 12 actual mesh residents. Keep the inspection label visible. |
| 00:45–01:40 | 02. Meet Aria in her upper home | Actual gameplay and home camera study | Choose original Aria through public LifeMode selection; retain her cafe upper-floor address, identity, needs and money. Use actual viewport clicks to open and close activity history and wishes while paused. |
| 01:40–02:35 | 03. Rooms, stairs and needs | Actual gameplay | Walk to the genuine owner stair portal, descend, and use the physical cafe table through the existing legal menu. Record actual completion and need effect. |
| 02:35–03:35 | 04. The actual cafe and street | Actual gameplay | Use the real cafe counter, then traverse its exterior door. Preserve resident-follow camera and geometry-based occlusion visibility. |
| 03:35–04:45 | 05. Walk into the expanded town | Actual gameplay | Click a real expansion entrance and show the continuous stepwise journey from the original core. No resident relocation or camera-only substitution. |
| 04:45–05:55 | 06. Use a new venue and its upper floor | Actual gameplay | Complete a new venue's legal fixture action; traverse its genuine upper stairs when present, return and exit. |
| 05:55–07:35 | 07. Walk to the reserve bathhouse | Actual gameplay | Follow connected authored paths into the actual bathhouse, complete a legal hygiene action and exit through its visitor door. |
| 07:35–09:15 | 08. Visit a detailed camping trailer | Actual gameplay | Walk to a detailed trailer and its actual offset entrance; use a legal bed, basin or toilet fixture and exit. |
| 09:15–11:05 | 09. Walk back from the reserve to town | Actual gameplay | Show the resident-follow return across reserve/expansion routes; enter the original cafe and return to the core street. This closes the physical outward-and-return trip. |
| 11:05–12:15 | 10. Inspection: forest, bridges and horticulture | Camera inspection | Inspect the ravine bridge/woodland, stone stair topography and pond planting. These camera cuts do not claim resident traversal of those inspected structures. |
| 12:15–13:25 | 11. Save, resume and resident agency | Actual gameplay | Dispatch actual F5, continue, then F8; verify the saved tick/address. Enable existing free will and observe live core decisions. |
| 13:25–14:00 | 12. Complete town and scope | Camera inspection | Final actual whole-town overview; finish narration and exactly 15,120 tour frames. Keep verification limits explicit. |

## Timing and source freeze

The current 24 normal-rate `en-US-AriaNeural` segments contain 857 spoken word tokens. Editorial speech windows total 692.528 seconds; these are allowed windows, not measured audio duration. Each actual take must fit its own window. Subtitles use measured WordBoundary data. The MovieWriter capture rate is 44,100 Hz / 18 FPS = 2,450 samples per frame; the composed narration WAV is separately 24 kHz.

Freeze the native chunks, character manifest/models, profile, projection, director, route and media inputs before acceptance. Compile the final profile after freezing `Main`, `TownModel3D`, `WorldView3D`, `TownWorldProfile`, `TownCharacter3D`, `LifeMode`, `Sim` and every script under `game/scripts/ui`. Their hashes belong to that profile. A runtime change requires recompilation and fresh matching verification/capture. A historical source or media PASS cannot be carried across the freeze.

The current full route receives generous walking/action time, including the return journey. Its 90-second preview compresses/skips long trips and cannot certify them. Camera inspections are labelled and modify presentation only. Genuine input, public selection and legal portal transitions are allowed; direct resident-address, need, money, action-result or clock writes by the director are prohibited.

## Acceptance boundaries

Require the completed exact-source logical report and actual Main/LifeMode report, including all route checks, 840 seconds, 18 FPS, 15,120 frames, `preview: false`, `route_complete: true`, zero failures and `direct_agent_writes: false`. Keep actual screenshots, action completions, source hashes and F5/F8 restoration receipts. MovieWriter AVI must contain the boot prefix plus every tour frame; missing footage is rejected rather than padded or reconstructed.

The MP4 must decode with the specified duration/frame count, 12 chapter markers and measured subtitles beneath the preserved HUD. Actual encoded-frame inspection and audio listening remain separate recorded reviews. A release executable's normal Main/GPU boot evidence is also separate and must bind its exact executable and PCK.

This route checks representative places and actions, not every modeled room or decorative assembly. Use the current staged inventory and runtime reports for exact building/interior/vegetation counts and outcomes. It does not certify universal performance, physics navigation, construction, or game balance.

Earlier 10:00, 24 FPS, 14,400-frame OGV/Theora movies, eleven-chapter tables, old sprite/inventory counts and reconstruction receipts are **archival previous-runtime evidence**. They are not the current route or acceptance evidence. Keep the new capture status pending until the new source-bound recording and reviews are complete.
