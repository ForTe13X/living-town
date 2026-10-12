# Walkthrough chapter and capture contract

**Planned duration:** 10:00 exactly, 24 FPS, 14,400 frames. **Current status:** narration draft validated; route capture, measured audio, final subtitles, and finished-video QA remain pending. This is a recording plan, not evidence that the walkthrough has already run.

The chapter windows below match the capture agent’s proposed route. Chapters 6–8 are explicitly labelled architectural inspection. Those shots may change the probe, camera, and local model covers, but never set resident coordinates. Gameplay chapters use the public Main/LifeMode interaction path.

Before the defined tour begins, the harness establishes morning light through public LifeMode selection, speed-key input, and an actual wait for at least 90 simulation ticks. It pauses and calls begin_select() again; no clock or resident-address assignment is used. This setup belongs to the captured boot prefix and is trimmed before the 00:00 chapter, so it does not shift narration or chapter windows.

| Time | Chapter | Mode | Required visible action |
|---|---|---|---|
| 00:00–00:45 | 01. A town you can enter | Paused observer | Slow whole-town flyover in actual Main. Pause simulation; establish the town and the inspection/gameplay distinction. |
| 00:45–01:40 | 02. Meet Aria and read the HUD | Controlled Aria | Show original selector at 45 seconds; public start_life("aria") at 50 seconds; show upper café apartment, resident identity, job/money, clock, needs, wishes, and input hints. |
| 01:40–02:35 | 03. Walk the rooms and take the stairs | Controlled Aria | Actual multi-frame walking and legal owner stair transition to the café floor; retain art and ground height. |
| 02:35–03:35 | 04. Use a real café fixture | Controlled Aria | Click actual counter mesh; open existing legal menu; use fixture through reachable approach and capture completion/state/event. Show social opportunity or real attempt. |
| 03:35–04:30 | 05. Step outside and keep the resident visible | Controlled Aria | Use real exterior door, walk toward plaza, show normal sprite depth and gold ghost only at actual geometry occlusion. |
| 04:30–05:30 | 06. Inspection: rooms and furnishing | INSPECTION — CAMERA ONLY | Inspect library, home, and hotel rooms by camera/probe and local cutaway controls only; no actor teleport or Sim coordinate mutation. |
| 05:30–06:30 | 07. Inspection: streets, elevations, and harbor | INSPECTION — CAMERA ONLY | Trace irregular streets, passages, courts, real surface elevations, thresholds, and harbor; preserve resident state. |
| 06:30–07:30 | 08. Inspection: pond and planted routes | INSPECTION — CAMERA ONLY | Show recessed pond and level water, continuous graded shore, loop, benches, reeds, willows, flowers, and access gaps. |
| 07:30–08:25 | 09. Return to life and enable autonomy | Controlled Aria | Return camera to Aria; record the actual social attempt at 450–473 seconds and its truthful response, then enable autonomy through LifeMode at about 473 seconds. |
| 08:25–09:20 | 10. Save, continue, and load | Controlled Aria | Dispatch real F5 save, continue, and real F8 load. Record save/load state proof; gently widen view for portability/provenance explanation. |
| 09:20–10:00 | 11. What the delivery proves | Observer close | Slow actual whole-town view; state verified test boundaries and practical limits. Let narration finish before final frame. |

## Timing and narrator contract

- Use [narration.json](narration.json): 22 segments, 945 spoken words, normal-rate `en-US-AriaNeural`. Every segment supplies `start`, `end`, `chapter`, `title`, `text`, and `notes`.
- Paragraph speech windows total 524 seconds; planned gaps total 76 seconds. Paragraph target rates are approximately 102–115 words per minute. The first longer take exceeded its window at 21.768 seconds; this shorter revision targets that measured cadence. Generate and measure every revised take before locking audio.
- Subtitles come from actual voice word boundaries, not guessed chapter timestamps. Preserve at least a short pause between paragraphs when takes fit.
- Prefer a 96-pixel caption matte below the complete 1280 × 768 game image. Suggested ASS settings and audio notes are in [narration_script.md](narration_script.md).
- Keep any chapter/inspection label clear of resident menus, the top status strip, and the bottom HUD. Put the inspection label in the added matte when practical.

## Truthful recording gates

1. Capture actual Main/LifeMode frames. Blender stills, a GLB viewer, and camera-only inspection do not establish resident travel or fixture completion.
2. Do not mutate simulation coordinates, needs, money, social results, or the clock to stage a claim. Legitimate portal transitions and existing input/public APIs are allowed.
3. Show the counter menu, a reachable approach, and actual completion. A physical counter may expose either of its preserved functional aliases.
4. Treat a social refusal or unavailable target as a real outcome. Log it; do not silently replace it with narrated success.
5. Bind real save/load calls to recorded state evidence. If a save/load step fails, fix and recapture or revise the narration rather than keeping a success sentence.
6. Final proof must bind route/action log, captured frames/video, TTS takes, measured word boundaries, and output hashes. The current 36 logical and 28 visual source-runtime checks remain separate from Windows boot proof. The current CI target is 35 legacy scenes; retain the old 11-scene subset as historical rather than promoting it to that full result.
7. Inspect the encoded beginning, stair transition, counter interaction, doorway occlusion, all inspection sections, autonomy/social result, save/load, and ending. Check subtitle readability and HUD visibility as well as audio clipping and sync.

## Claims to retain

49 buildings; 89 floors; 561 logical zones, including circulation; 223 activity rooms; 753 furnishing assemblies; explicitly mapped functional objects counted in the current compiled profile; 52 planned local landscape trees. Original resident identities and 2D directional sprites are retained in the 3D view. Terrain, pond banks, planting, entrances, stairs, private access, and scene cutaways are authored and checked, with their stated limits.

The game uses the existing logic backend and simulation authority. No language-model download is needed for this route. Engine-agnostic art export and provenance are delivered separately. No broad performance, finished balance, certified construction, general physics navigation, or all-decoration-is-gameplay claim is made.
