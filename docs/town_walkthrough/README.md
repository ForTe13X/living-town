# Living Town: actual game walkthrough

[Download the public-release MP4](https://github.com/ForTe13X/living-town/releases/download/town3d-walkthrough-2026-10-12/LivingTown_Walkthrough.mp4) · [English subtitles](final/narration.srt) · [Contact sheet](final/contact_sheet.png)

This is a 600-second recording of the actual Main/LifeMode 3D game bridge: 24 FPS, 14,400 decoded frames, 1280 × 864, and eleven embedded chapters. The complete 1280 × 768 game image is retained above a 96-pixel caption matte. English narration uses normal-rate Edge TTS `en-US-AriaNeural`: 945 words in 22 measured paragraphs, with subtitles derived from actual word boundaries. The release URL is supplied by the publishing owner; this local finalizer does not verify remote availability.

| Evidence | Actual result |
|---|---|
| Full live-capture checks | 32/32 |
| Final encoded-MP4 technical checks | 13/13 |
| Measured voice takes | 22/22 within their windows |
| Save guard | Prior user quicksave restored, or recording-only save removed |
| logical (separate source-runtime suite) | 36/36 |
| visual (separate source-runtime suite) | 28/28 |

The route uses the existing resident selection, keyboard/mouse interaction, real stairs and doorway transitions, fixture approach/use, a social attempt, autonomy, and F5/F8 save/load. Public speed controls and real simulation waiting establish morning light; the measured boot prefix is trimmed. Architectural room, street, harbor, and pond sections are labelled camera inspection. Moving their camera or opening local cutaways does not relocate a resident. Social outcomes are the actual recorded game response, not forced success.

The modeled town contains 49 buildings, 89 floors, 561 room/circulation zones, 223 activity rooms, and 753 furnishing assemblies. Only explicitly mapped functional objects have game actions; their exact total belongs to the compiled profile. Original resident identities and directional 2D sprites are retained in the 3D view, with normal depth and a controlled-resident silhouette only at detected occlusion. The pond has authored graded banks; the terrain, planting, and routes are fictional design rather than hydrological or construction certification.

Audio mode recorded by composition: `narration_plus_actual_game_bed`. The pipeline uses measured narration normalization and includes captured game sound only when the raw track is audible. It adds no invented music or interaction sounds.

A separate, exact-MP4-bound visual review passed; see [visual review](final/visual_review.json). Human audio listening is not recorded in this bundle. Technical PCM/decode checks do not establish listening acceptance.

The capture supervisor reports stable source identity and verified process cleanup. File, source, media, cache, and copied-artifact hashes were independently rechecked by this finalizer. [Evidence manifest](final/evidence_manifest.json) records the exact bindings. Original reports retain their local build paths; large raw capture, MP3 cache, WAV, and MP4 files are not committed in this small bundle.

- [Full input/action/capture report](final/walkthrough_report.json)
- [Composition and measured audio report](final/composition_report.json)
- [Final frame/decode/audio/hash verification](final/verification_report.json)
- [Measured voice and word timings](final/voice_report.json)
- [Save restoration guard](final/save_guard.json)
- [Stable-source supervisor receipt](final/supervised_receipt.json)
- [Reproduction instructions](RECORDING.md)

The recording demonstrates selected actions and places. It does not establish finished balance, population scale, general hardware performance, streaming/LODs, a universal collision/navmesh system, or gameplay for every decorative asset. Separate source-runtime tests and a Windows normal-entry boot/render check have their own evidence; a packaged boot check does not repeat the full interaction suite. Engine-neutral Blender/GLB art delivery remains separate.

MP4 SHA-256: `a1f97fdcc79e232784874c4ebd67c9b52a3ed98cc52982a9baf24872d10184d7`. Bytes: 245,232,169. Source GLB SHA-256: `b90b37e40f6f38e61b095a45671fed40008e9423dfef52ef7db74cb34cb0c00c`. Projection SHA-256: `addae85c82d7dd68f2c5a233a8c6f9353ef702fabc643a4b098b6f6aef71c08a`.
