# Record the expanded town in actual gameplay

The current route is **840 seconds (14:00), 18 FPS, 15,120 actual tour frames**. Record Godot MovieWriter **AVI** with a **44,100 Hz** capture mix rate: exactly 2,450 audio samples per video frame. The finished movie has 12 chapters and 24 measured Edge TTS paragraphs.

The completed Full3 capture passed **64/64** actual input/action checks. Its corrected encoded movie passed **13/13** technical checks: 840.0 seconds, 15,120 decoded frames, 12 chapters, H.264/yuv420p with limited TV range, AAC and complete decode. The exact movie is 528,362,448 bytes, SHA-256 `9c72fa15426706d76307fd1eebaec77404de3cbabb67c80e9928d83ecbf4e252`. Twenty-four verified cached normal-rate Edge TTS takes supply 95 measured subtitle cues. Actual sampled visual review passed its declared scope with P2 limitations; audio review is technical only, with no recorded human listening. Preserve the exact reports/cache used; those results do not promise byte-identical future service output.

The source harness instantiates the product's real `Main.tscn`, `LifeMode`, and authoritative `Sim`. It demonstrates the core cafe, expanded district, reserve bathhouse, detailed camping trailer, a walked return to the core, and F5/F8 continuity. Labelled architecture inspections change presentation state only. They do not establish resident traversal of the inspected bridges, stairs, or planting.

## Prepare and freeze the exact runtime

Run commands from the repository root. Use Python 3.11 or later, FFmpeg/ffprobe with H.264, AAC, libass and loudnorm, and the configured Godot 4.6.2 engine. The existing voice setup uses `edge-tts==7.2.8` in the ignored `build/town_walkthrough/python_deps` directory:

```powershell
python -m pip install --target build/town_walkthrough/python_deps edge-tts==7.2.8
```

Edge TTS requires network access during synthesis; local playback and the logic game backend work offline. The builder supports the process-local migrated endpoint and records its configuration. It does not edit the installed library. Requesting Python module help does not launch Godot or synthesize narration.

Before capturing:

1. Finalize the native town chunks and all character exports. Stage and compile the complete v2 runtime using [PLAYABLE_INTEGRATION.md](../../tools/town_upgrade/PLAYABLE_INTEGRATION.md), retaining the explicit pre-upgrade profile snapshot.
2. Freeze `Main.gd`, `TownModel3D.gd`, `WorldView3D.gd`, `TownWorldProfile.gd`, `TownCharacter3D.gd`, `LifeMode.gd`, `Sim.gd`, and the HUD scripts under `game/scripts/ui/` **before** the final profile compilation. The compiled profile records their SHA-256 values. Freeze the director, [route_plan.json](route_plan.json), [narration.json](narration.json), and media builder for the accepted recording and composition.
3. Import and verify the exact staged runtime serially. The new logical integration arm is `res://scenes/town_upgrade_integration_test.tscn`. Its report covers topology, legal fixtures, access, long actual stepwise travel, and deterministic save/load; it does not replace GPU/input evidence.
4. Confirm `game/project.godot` has `movie_writer/mix_rate=44100` under `[editor]`. Use a real display/GPU renderer for MovieWriter, not `--headless`.

The full recording binds the profile/projection, exact staged chunk set, character manifest, director, and route. Composition rejects changed bound sources and presentation code changed after profile compilation. Recompile and repeat the affected verification/capture after a runtime change. Do not certify the expanded town with historical core-only reports.

## Record preview, then the full route

Prefer the supervised launcher. It preserves the existing `town3d_quicksave.dat`, verifies the backup, restores the prior save in its `finally` block, and retains `save_guard.json` plus the recording save. It validates the fresh director report independently of the engine exit code.

```powershell
$townGodot = 'C:/path/to/Godot_v4.6.2-stable_win64_console.exe'
$townPreview = 'D:/TownRuns/preview_001'
$townFull = 'D:/TownRuns/full_001'

./tools/record-town-walkthrough.ps1 -Godot $townGodot -Preview -Agents 60 -OutputDir $townPreview
# Inspect the preview before starting the full, serial recording.
./tools/record-town-walkthrough.ps1 -Godot $townGodot -Agents 60 -OutputDir $townFull
```

Choose fresh output directories for retries; the launcher refuses to overwrite capture/report evidence. The preview is 90 seconds, 18 FPS, and 1,620 tour frames. It compresses or skips long journeys and uses the existing public 8x shortcut for the short café-action chapter, including the walked approach before its 24-tick use. The actual clock setting is checked after input. It is a framing/startup check, not full-route acceptance.

The launcher passes `--single-threaded-scene --disable-vsync --windowed --resolution 1280x768 --fixed-fps 18 --write-movie <absolute>/capture.avi`, the source scene `res://scenes/town_walkthrough.tscn`, then user arguments `--town3d --backend logic --agents 60 --no-player --seed 7 --walkthrough-dir <absolute>`. `-Agents` is configurable from12to120; the explicit/default60 produces62actual residents in this profile. Older captures used `-Agents 12` and 14 actual residents. The accepted full recording uses the same62-resident population as the current ordinary-framerate checks. Keep engine/render/export stages serialized under the coordinator's supervisor. A release executable's normal-entry smoke run is separate from this source test-scene capture.

Before the timed tour, public LifeMode selection, actual speed-key input and live waiting establish at least 90 simulation ticks of morning. The harness pauses and restores the resident selector without assigning the clock or moving Aria. This setup remains in the recorded boot prefix. The 840-second tour starts afterward; composition removes exactly the reported prefix.

Wait for normal engine exit and AVI finalization under the supervisor's time/file-size bounds. Preserve shutdown failures and their logs; an incomplete file is not accepted. The full `walkthrough_report.json` must contain:

- `status: PASS`, `preview: false`, `route_complete: true`, zero failures and nonempty, passing boolean checks;
- `fps: 18`, `expected_tour_frames: 15120`, `tour_frames_elapsed: 15120`, and 840 seconds elapsed;
- `direct_agent_writes: false`, actual input/action receipts and source-bound framebuffer PNGs;
- a consistent integer `movie_boot_frames_to_trim` (or its accepted equivalent `movie_boot_frame_offset`).

The report must show actual expanded-town travel and reserve use, including the walked return. A camera pan, selected scene, visible furnishing, or menu alone does not prove completion. The resident-follow camera shows the journeys; labelled inspection shots remain separate.

## Generate measured narration and subtitles

```powershell
python tools/build_town_walkthrough.py voice --outdir $townFull
```

Use the current 24 normal-rate `en-US-AriaNeural` segments. Synthesis is sequential, with bounded retries/timeouts. The request cache includes text, voice, rate, WordBoundary mode, endpoint and library version. Verified matching takes are reused; changing a paragraph invalidates that paragraph's request. `--refresh-voice` regenerates takes, while `--respect-proxy` retains proxy settings when required.

Every take is measured with ffprobe and must fit its own editorial window. An overrun fails; no take is clipped, accelerated, or pushed into the next paragraph. Real gaps become silence in an exactly **840-second, mono, signed-16-bit, 24 kHz** narration WAV. This composition rate is distinct from MovieWriter's 44,100 Hz capture rate.

Actual Edge TTS WordBoundary data produces `captions.json`, SRT and ASS. Missing or mismatched words fail rather than receiving guessed timing. Captions use at most two lines, 54 characters per line and 90 characters per cue. Keep the complete 1280 × 768 game frame and append the 96-pixel subtitle matte, giving a 1280 × 864 output. Caption timing comes from measured speech, not chapter boundaries.

The accepted composition reused all 24 verified cached takes. The pond paragraph uses the actual714–734.5 second window; its719-second active-caption frame shows the pond. Text and cached take bytes were retained when retiming; new timing requires fresh voice/subtitle bindings and encoded verification.

Retain `voice_cache/`, `voice_report.json`, `narration.wav`, `narration.ass`, `narration.srt` and `captions.json`. Service output need not be byte-identical on a future request; the accepted cache/report binds the actual takes used.

## Compose and verify the MP4

```powershell
python tools/build_town_walkthrough.py compose --outdir $townFull `
  --raw "$townFull/capture.avi" --report "$townFull/walkthrough_report.json"

python tools/build_town_walkthrough.py verify --outdir $townFull `
  --raw "$townFull/capture.avi" --report "$townFull/walkthrough_report.json"
```

Current composition accepts **AVI only**. It decodes/counts the actual raw frames, checks the 18 FPS cadence and sufficient boot-plus-tour frames, then trims the exact recorded range. There is **no video padding, trailing-picture repair, synthetic frame reconstruction, or conversion of an incomplete recording into a complete tour**. Captured game audio is trimmed by the same boot offset divided by 18.

The builder burns measured subtitles beneath the unchanged HUD and writes 12 contiguous chapter markers across 840 seconds. A separate two-pass loudnorm targets -16 LUFS and -1.5 dB true peak. A non-silent real game bed is reduced and ducked under narration; an absent/silent track is honestly labelled narration-only. No invented music or effects are added.

The default `LivingTown_Walkthrough.mp4` uses H.264/yuv420p, **limited TV range**, 1280×864,18 FPS, 15,120 frames, AAC audio and faststart. The current builder explicitly converts video with `scale=1280:768:flags=lanczos:out_range=tv` and supplies `-pix_fmt yuv420p -color_range tv` to FFmpeg. Both conversion and metadata matter: the earlier full-range `yuvj420p` encode was rejected and retained separately, not relabeled as a pass. `composition_report.json` binds input/output hashes, trimming, filters, audio measurements and command arguments. `verification_report.json` rehashes those inputs, probes and fully decodes the output, checks 840 seconds ±0.1, all 12 chapters, captions, frame count and measured audio integrity.

Verification normally extracts actual encoded midpoint frames into `qa/chapter_01.png` through `qa/chapter_12.png` and a contact sheet. Extraction alone leaves these images marked **not visually reviewed**. For the accepted Full3 movie, actual review covered all 12 chapter PNGs individually, the contact sheet, three active-caption frames at 25/83/719 seconds and six sparse strips containing30 one-FPS samples. Active captions are readable beneath the game/HUD; the pond caption matches its visible context. No complete 18 FPS playback or full-film motion acceptance is implied.

Decoded final audio spans 840.021 seconds, RMS -20.415 dBFS and peak -1.414 dBFS with no full-scale PCM sample. Human listening for pronunciation, clarity, pacing and perceptual sync was **not recorded**. Keep technical audio validity, sampled visual review and any future listening review distinct; never turn measured levels into a listening claim. Record all reviews against the exact movie/image hashes.

Before packaging, archive the current completed report/cues and reviewed PNGs at the paths required by [PLAYABLE_INTEGRATION.md](../../tools/town_upgrade/PLAYABLE_INTEGRATION.md). The Windows executable/PCK requires its own exact normal-entry runtime proof. Counts and verdicts come from the new reports, not from this guide. The route demonstrates selected interactions; every decorative object and every modeled room is not claimed as player-traversed.

## Failure handling and archival recordings

Each phase writes bounded command logs and a failure JSON on error. Repair an overlong take, failed action, stale source binding or incomplete capture, then rerun the appropriate stage. Keep rejected evidence labelled and separate. Do not change a report to PASS or patch missing gameplay with repeated frames.

Earlier ten-minute **600-second / 24 FPS / 14,400-frame OGV/Theora** recordings and their packet-reconstruction receipts are **archival evidence of the previous core-only runtime**. The historical timing regression tests retain that narrow reconstruction behavior. It is not the current capture format or compose path, and those old media/test counts do not certify the expanded town. The current Full3 AVI/action and corrected MP4 technical reports are complete and source-bound. Sampled visual acceptance has the explicit limits above; human listening/full-film playback acceptance is not recorded.

## Accepted Full3 identities and review limits

The actual input/action report is `f1d9e3d026f7189da354504e3fbf6f535d14162846e7821df717dce8ae5c1240`; final encoded verification is `e3abee4f3dbd10deb61af89932160cc28f253235b6f348639ac16171196a7215`; measured voice report is `17b83a15b01239307bcafb86f3c765a8e41472c5b0eb6c02f9719f77017d76be`. The independent image review is `36c1a4d473441fb436c2c9cdf8a62d1c898e90a864d2193c70f7e9f3f138a0f9`. See [current walkthrough evidence](README.md) and [the release proof index](https://github.com/ForTe13X/living-town/releases/download/town-refinement-2026-10-23/LivingTown_Refinement_Proof_Index.json) for the bound source/asset/profile/movie identities and public-retrieval records.

Known P2 findings are dark evening/night detail, sparse venue/amenity/pond dressing, a truncated internal-looking place label and real need depletion on return/resume. The recording does not establish a balanced-needs success, all-room decoration, all-character portrait fidelity or complete concept match. Architecture/terrain camera inspection stays explicitly separate from resident use/traversal.

The current GIF is 30.0 seconds/120 frames/640×384/4 FPS/infinite loop, no audio, SHA-256 `b68f52e7aef6f6c39fd02247db23491142d9fdface9a06aee030951eb1c91e24`. It samples six 5-second movie intervals, removes only the appended subtitle matte and remains at the existing first-screen image path. Its decoded/palette samples were reviewed; this is not a full-motion viewing claim.
