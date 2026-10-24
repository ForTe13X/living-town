# Living Town: refined town in actual gameplay

[Full MP4,14:00](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Walkthrough.mp4) · [English subtitles](final/narration.srt) · [Chapter contact sheet](final/contact_sheet.png) · [Downloads/checksums](ASSET_RELEASE.md) · [Current proof index](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json)

This completed Full3 recording shows the actual Main/LifeMode game: **840 seconds, 18 FPS, 15,120 decoded frames, 1280×864 and 12 embedded chapters**. The full 1280×768 game image remains above a 96-pixel subtitle band. The logic backend, actual viewport input and authoritative Sim handle resident selection, stairs/doors, fixtures, outward/return travel and F5/F8 save/load. Labelled architecture/terrain shots change presentation only.

The first-screen README GIF is a **30.0-second silent excerpt** from this exact MP4: 120 decoded frames, 640×384, 4 FPS, infinite loop. It stays at the original `docs/media/town3d-walkthrough.gif` path. [Preview metadata](../media/town3d-walkthrough-preview.json) records source intervals, cropping, hashes and sampled review. A GIF excerpt is not the complete journey or a runtime-FPS measurement.

| Evidence | Actual result and scope |
| --- | --- |
| Full3 input/action report | 64/64; complete 840-second route, no direct resident-address writes |
| Final encoded MP4 | 13/13; H.264, yuv420p, limited TV range, AAC, 840.0 s, 15,120 frames |
| Runtime population/assets | 62 mesh residents; 11 town GLBs; 25 rigged character templates; 151 buildings and 263 floor interiors |
| Voice/captions | 24 verified cached normal-rate `en-US-AriaNeural` takes; 95 WordBoundary cues |
| Save/source/private/cache guards | Prior save/private bytes preserved; source/owned-process guards passed; actual Main cache hit retained |
| Actual sampled visual review | All 12 chapter PNGs, contact sheet, three active-caption frames and six sparse strips/30 samples; scoped PASS with P2 limitations |
| Decoded audio | 840.021 s; RMS -20.415 dBFS; peak -1.414 dBFS; no full-scale PCM sample |
| Listening/full playback | Human listening and continuous full-film playback acceptance are not recorded |

## Chapters

Times and titles follow the current frozen [route plan](route_plan.json). Gameplay chapters contain actual verified actions and may include clearly labelled camera-inspection inserts; the chapter label on screen identifies the current mode. A view of a bridge, staircase or room does not itself prove resident traversal/use.

| Chapter | Time | Title | Scope |
| --- | --- | --- | --- |
| 1 | 00:00–00:45 | Town, woodland and coast | Camera inspection |
| 2 | 00:45–01:40 | Meet Aria in her upper home | Resident input; labelled inspection inserts |
| 3 | 01:40–02:35 | Rooms, stairs and needs | Resident input; labelled inspection inserts |
| 4 | 02:35–03:35 | The actual cafe and street | Resident input; labelled inspection inserts |
| 5 | 03:35–04:45 | Walk into the expanded town | Resident input; labelled inspection inserts |
| 6 | 04:45–05:55 | Use a new venue and its upper floor | Resident input; labelled inspection inserts |
| 7 | 05:55–07:35 | Walk to the reserve bathhouse | Resident input; labelled inspection inserts |
| 8 | 07:35–09:15 | Visit a detailed camping trailer | Resident input; labelled inspection inserts |
| 9 | 09:15–11:05 | Walk back from the reserve to town | Resident input; labelled inspection inserts |
| 10 | 11:05–12:15 | Inspection: forest, bridges and horticulture | Camera inspection |
| 11 | 12:15–13:25 | Save, resume and resident agency | Resident input; labelled inspection inserts |
| 12 | 13:25–14:00 | Complete town and scope | Camera inspection |

The outward trip enters an expanded venue, its upper floor, the reserve bathhouse and a furnished trailer; the return walks back through the connected town. Real fixture menus/actions and the saved tick/spatial address are checked separately from cinematic views. The director does not force a desired social response or relocate Aria to create travel success. HUD controls and optional activity/wishes panels remain the existing game interface.

## What the review establishes

The actual sampled encoded images show readable room segmentation, stairs, cafe seating/counter/kitchen, bathhouse zones, trailer facilities, roads, reserve canopy/cliffs/bridges and pond context. Three active-caption frames show the one/two-line subtitles below the full game/HUD, including the retimed pond paragraph at 719 seconds. The six 1-FPS strips support only sparse subject/framing continuity, not fluidity at 18 FPS or a complete film watch.

Known P2 limitations from the independent review:

| Observation | Reviewed examples | Limit on claims |
| --- | --- | --- |
| Dark evening/night material/canopy/interior detail | Chapters 6,10,11 | Not a proof of fine-texture readability under every lighting condition |
| Sparse upper-venue and amenity/pond dressing | Chapters 5,6; pond719 s | Does not establish lush horticulture or fully detailed decoration throughout |
| Raw/truncated internal-looking location label | Chapter 5 | HUD needs/controls remain readable; place-name presentation needs refinement |
| Real need depletion on return/resume | Chapters 9,11; four gauges reach0 | Not a healthy-life/balance-success demonstration |

The model has151 buildings, 263 floor interiors, 1,582room zones, 2,089furnishing assemblies and 784new legal fixture bindings. Native furniture objects and runtime furnishing assemblies are different counts. Decorative assets do not automatically gain gameplay effects; access remains subject to authored public/private permissions. These totals and the sampled review do not grade all rooms, all 25character portraits or complete idealized-concept fidelity. [Runtime and performance scope](../town_bridge/README.md).

Audio mode is `narration_plus_actual_game_bed`. The pipeline reuses 24 verified cached Edge TTS takes at normal rate, derives 95 subtitle cues from measured WordBoundary data, normalizes narration and ducks the real captured game bed. No invented music/effects are added. Full video/audio decode, duration and PCM levels passed; **no human listening, pronunciation or perceptual-sync acceptance is recorded**. Technical audio validity and sampled visual acceptance are distinct.

## Exact evidence and file identities

- [Full input/action/capture report](final/walkthrough_report.json)
- [Composition and measured audio report](final/composition_report.json)
- [Final frame/decode/audio/hash verification](final/verification_report.json)
- [Measured voice/word timings](final/voice_report.json)
- [Sampled visual review](final/visual_review.json)
- [Save restoration guard](final/save_guard.json)
- [Stable-source supervisor receipt](final/supervised_receipt.json)
- [Small evidence manifest](final/evidence_manifest.json)
- [Reproduce the recording](RECORDING.md)

| Artifact | Bytes / SHA-256 |
| --- | --- |
| Full MP4 | 528,362,448 bytes;`9c72fa15426706d76307fd1eebaec77404de3cbabb67c80e9928d83ecbf4e252` |
| GIF | 14,736,629 bytes;`b68f52e7aef6f6c39fd02247db23491142d9fdface9a06aee030951eb1c91e24` |
| Full3 raw report | `f1d9e3d026f7189da354504e3fbf6f535d14162846e7821df717dce8ae5c1240` |
| Final encoded report | `e3abee4f3dbd10deb61af89932160cc28f253235b6f348639ac16171196a7215` |
| Independent image review | `36c1a4d473441fb436c2c9cdf8a62d1c898e90a864d2193c70f7e9f3f138a0f9` |
| Town asset set | `d21e4f94d6d3a5c9599027e45ce919f0777a271b96bd2815c4b7856ad817a41a` |
| Canonical native | `3162c204689cdb7888a5e0d21bb5dde9be04a89ac6253ba03a88d7f5ddd86274` |
| Profile | `8499a7d376739dcb759d5e404c277a707c8443230763dcfd7962fe730b1fcb4e` |
| Projection | `98146b008f130870d0067a7c1e0940f6ab373b5f255e5ba66ac24ca0ed48b3bc` |

Large raw capture, WAV/MP3 cache and MP4 bytes stay outside ordinary Git history. The linked release/proof-index destinations identify this version; successful public retrieval is recorded separately. Exact source-runtime regressions, uncapped normal-game FPS, Blender redraw and exported Windows boot/cache checks have their own bound reports. The 18 FPS MovieWriter setting is not a gameplay performance result.
