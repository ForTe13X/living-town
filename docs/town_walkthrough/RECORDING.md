# Record and compose the actual game walkthrough

The recording is the editable game's real `Main`/`LifeMode` view. The harness directs public selection, mouse/key input, legal stairs and doors, fixture use, a social attempt, autonomy, and save/load. Architectural tours change camera and local covers only. They are explicitly labelled inspection and do not imply resident traversal. The complete route is 600 seconds at 24 FPS, or 14,400 tour frames.

The authoring script, `tools/build_town_walkthrough.py`, has three explicit phases. Importing it or requesting help does not synthesize speech, launch Godot, or run a media process. Delivery evidence records technical verification and a separate actual encoded-frame review by the recording owner or agent. Human audio listening remains separately identified as pending unless a real listening report is supplied. Script readiness alone is not recording evidence.

## Inputs and prerequisites

Use Python 3.11 or later, `ffmpeg`/`ffprobe` on PATH (FFmpeg must include libx264, AAC, libass subtitles, and loudnorm), and `edge-tts==7.2.8`. Edge TTS requires network access; playback of the finished movie does not. The project currently installs the Python dependency into the ignored `build/town_walkthrough/python_deps` directory. To reproduce that dependency setup deliberately:

```powershell
python -m pip install --target build/town_walkthrough/python_deps edge-tts==7.2.8
```

The current [narration.json](narration.json) contains 22 normal-rate `en-US-AriaNeural` paragraphs. An initial longer paragraph actually measured 21.768 seconds against a 19-second window. The shorter revision keeps the same ten-minute route and must still pass measurement for every take. [route_plan.json](route_plan.json) supplies the eleven chapter windows; [chapter_outline.md](chapter_outline.md) explains the capture contract.

Complete the intended source merge and freeze before the full capture. Do not record an earlier worktree and promote its footage to the new source. Keep the preview and full output directories separate, and run the heavy stages serially. A MovieWriter recording proves the recorded frames and actions, not real-time hardware performance.

## Actual game capture

The preferred entry is the supervised [record-town-walkthrough.ps1](../../tools/record-town-walkthrough.ps1) launcher. It invokes the editable source harness, applies the serial engine limits, and preserves the actual town3d quicksave. It verifies the backup hash, restores the prior save in a finally block, or removes only the checked recording save if no prior save existed. The recording save is retained separately and `save_guard.json` records restoration and report validation.

```powershell
./tools/record-town-walkthrough.ps1 -Godot "C:/path/to/Godot_v4.6.2-stable_win64.exe" `
  -Preview -OutputDir build/town_walkthrough/preview_v2
# After the preview is accepted, record the full route serially:
./tools/record-town-walkthrough.ps1 -Godot "C:/path/to/Godot_v4.6.2-stable_win64.exe" `
  -OutputDir build/town_walkthrough/full
```

The launcher refuses to overwrite existing capture/report evidence; choose a fresh output directory for a rerun and pass that directory to the composition phases. Voice assets alone do not prevent the full capture. It independently parses fresh JSON and requires the correct schema, mode, complete frame/time counts, route completion, nonempty boolean passing checks, and zero failures. An operating-system exit code alone is insufficient.

For advanced manual capture, the source harness is `res://scenes/town_walkthrough.tscn`. The stock release template does not support the alternative command-line test-scene entry. Manual launch bypasses the save guard and supervision; preserve the actual quicksave and apply the same serial limits yourself. The equivalent engine invocation is:

```powershell
$townGodot = 'C:/path/to/Godot_v4.6.2-stable_win64.exe'
$townFull = [IO.Path]::GetFullPath('build/town_walkthrough/full')
New-Item -ItemType Directory -Force -Path $townFull | Out-Null
$townRaw = Join-Path $townFull 'capture.ogv'
& $townGodot --path game --windowed --resolution 1280x768 `
  --fixed-fps 24 --write-movie $townRaw `
  res://scenes/town_walkthrough.tscn -- `
  --town3d --backend logic --agents 12 --no-player --seed 7 `
  --walkthrough-dir $townFull
```

The supervised launcher's limits and actual source/engine invocation belong in the capture evidence. The harness invokes the existing town3d F5/F8 namespace; use the launcher's backup/restore guard for that actual user directory rather than assuming an unsupported alternate-user-data flag provides isolation.

Before the tour starts, the current harness selects Aria through the public LifeMode API, uses the real speed-key input, and waits until at least 90 simulation ticks have advanced. It then pauses and calls begin_select() to restore the resident selector. This establishes morning light without assigning the clock or relocating residents. All of this pre-roll is inside the reported boot-frame prefix, before the fixed ten-minute tour; composition trims it rather than shifting the narration. The route pauses after the meal so long inspection sections do not drift into night. In the full closing chapter, ordinary speed key 4 and live simulation waiting target the following morning, bounded by 578 seconds, then key 0 pauses the clock. `closing_real_clock_wait` records the target and actual ticks; verify the actual morning result in the capture rather than treating a camera/light override as evidence.

Wait for engine exit and MovieWriter finalization. The full `walkthrough_report.json` must report `PASS`, `preview: false`, `route_complete: true`, zero failures, 24 FPS, 14,400 expected tour frames, and `direct_agent_writes: false`. It records the actual boot prefix as `movie_boot_frames_to_trim`; the builder also accepts the equivalent `movie_boot_frame_offset` if present and rejects conflicting values. Video trimming uses exact frame indices, and captured game audio uses the corresponding offset divided by 24.

The builder checks the current harness, route, projection, and staged GLB SHA-256 values against the capture report. Changed source requires a fresh recording. It also binds the raw OGV and report hashes into composition evidence. A successful preview is useful for route debugging but is deliberately rejected as the full input.

## Phase 1: measured voice and captions

```powershell
python tools/build_town_walkthrough.py voice --outdir build/town_walkthrough/full
```

Synthesis is sequential, with at most three attempts per paragraph and bounded stream timeouts/backoff. The process-local endpoint shim assigns `edge_tts.communicate.WSS_URL` to `wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1`, using the installed library's public trusted-client token as `Ocp-Apim-Subscription-Key`. This follows the endpoint migration in [upstream edge-tts PR 491](https://github.com/rany2/edge-tts/pull/491), inspected on 2026-10-12. The change is confined to this process; installed library files are not edited or vendored. `voice_report.json` records the version, endpoint, shim scope, and reference. The installed endpoint can be selected explicitly with `--endpoint installed` when appropriate.

The cache key includes text, voice, rate, WordBoundary mode, endpoint, and edge-tts version. Cached MP3 and timing sidecars are reused only after their hashes and request match. `--refresh-voice` requests new takes; editing one paragraph changes only that paragraph's key. Direct network access is the default used by the successful local probe; `--respect-proxy` retains proxy environment settings if needed.

Every take is measured with ffprobe. Any duration exceeding its paragraph window fails the phase. No take is clipped, silently sped up, or pushed into the next paragraph. After the duration gate, each MP3 is decoded with two FFmpeg threads and streamed into a mono, signed-16-bit, 24 kHz WAV. Zero samples fill the real gaps. The result is exactly 600 seconds; the builder does not hold the whole PCM file in memory.

Actual `WordBoundary` offsets and durations produce the SRT and ASS. Original punctuation is aligned back to the source text; missing or mismatched words fail instead of receiving guessed timings. Cues target about five seconds and at most 90 characters, split into no more than two lines. The ASS uses Arial 25, bottom-center alignment, side margins 48, and bottom margin 18 on a 1280 × 864 canvas.

Outputs include `voice_cache/`, `narration.wav`, `narration.ass`, `narration.srt`, `captions.json`, and `voice_report.json`. Check the measured take durations before starting full composition. The generated voices and word metadata are cached evidence, not a guarantee that a future service request will produce identical audio.

## Phase 2: compose the final MP4

```powershell
python tools/build_town_walkthrough.py compose `
  --raw build/town_walkthrough/full/capture.ogv `
  --report build/town_walkthrough/full/walkthrough_report.json `
  --outdir build/town_walkthrough/full
```

This phase rejects stale narration assets, preview/failed capture reports, changed bound sources, or an incomplete raw capture. It trims the actual boot frames, keeps the complete 1280 × 768 game image, and appends a 96-pixel dark subtitle matte below it. The bottom HUD is preserved. Captions burn into that matte using the measured ASS sidecar. Eleven chapter markers cover the whole 600-second timeline.

Godot's Theora capture contains zero-byte packets that repeat the previous picture. The builder checks every packet timestamp and duration before reconstructing 24 FPS, restores only the proven trailing repeat packets, and then trims the boot prefix by frame index. The accepted capture contains 14,709 contiguous packets, including 51 trailing repeats; its 307-frame prefix leaves the complete 14,400-frame tour. The packet table and reconstruction recipe are hash-bound in the composition report. Two FFmpeg regression tests in `tools/tests/test_town_walkthrough_timing.py` cover sparse frames and actual Theora repeat packets, including rejection of broken cadence.

Narration normalization is a separate measured two-pass loudnorm operation, targeting -16 LUFS and -1.5 dB true peak. The actual trimmed game audio is decoded and measured. A non-silent bed is reduced and sidechain-ducked under narration, with a final limiter. A silent or absent capture track produces honestly labelled narration-only audio. The tool adds no invented music or game sounds. The report records the measured game-bed RMS/peak and thresholds, allowing a sparse track to be reviewed rather than advertised as music.

Encoding uses H.264, yuv420p, CRF 20, medium preset, six video encoder threads, AAC 160 kbps, and faststart. The default output is `build/town_walkthrough/full/LivingTown_Walkthrough.mp4`. `composition_report.json` binds source/report/audio/caption/output hashes, exact trimming, filter recipe, command arguments, loudness measurements, and audio mode. Encoding completion is separate from final technical verification, actual encoded-frame inspection, and any later human listening acceptance.

## Phase 3: technical verification and actual encoded-frame review

```powershell
python tools/build_town_walkthrough.py verify `
  --raw build/town_walkthrough/full/capture.ogv `
  --report build/town_walkthrough/full/walkthrough_report.json `
  --outdir build/town_walkthrough/full
```

Verification rehashes bound inputs and output, probes the actual MP4, counts decoded frames, and requires 600 seconds ±0.1, 24 FPS, 14,400 frames, H.264/yuv420p at 1280 × 864, an AAC track, all eleven contiguous chapters, and valid caption sidecars. It fully decodes the movie with FFmpeg error checking, streams decoded PCM to calculate RMS and peak, rejects a silent narration result or full-scale peak, and records the output SHA-256. The decode error scan and measured audio are retained in logs and `verification_report.json`.

By default, verification extracts one actual encoded frame from the midpoint of each chapter into `qa/chapter_01.png` through `qa/chapter_11.png`, plus `qa/contact_sheet.png`. `--no-qa-images` skips only that optional extraction. These generated frames are explicitly marked **not visually reviewed**. Technical PASS does not establish visual review or human listening. An agent may separately open the actual encoded frames and inspect caption layout; that review must bind the exact final MP4 and image hashes. Human audio listening remains pending unless performed and recorded.

The recording owner or agent should open the actual encoded chapter frames and inspect the stair/meal sequence, counter menu and completion, exterior gold silhouette, room inspection labels, pond banks, social response, autonomy, and F5/F8 restoration. Record observed visual readability and truthful event narration with the exact movie/report/image hashes. The audio report separately records decode integrity, duration, RMS and peak. Human listening for voice clarity, pacing, pronunciation, and perceived sync is a recommended follow-up and must remain marked pending until actually performed; never infer listening acceptance from technical measurements or image inspection.

The walkthrough demonstrates selected places and outcomes. It does not make every one of the 753 decorative assemblies interactive. Only explicitly mapped functional objects participate in gameplay; use the current compiled profile for their exact count. The source logical suite has 36 passing checks, the actual GPU suite has 28, and the current hosted regression report records 35 passing legacy scenes. The earlier 11 selected regressions remain historical evidence. The Windows package has separate normal boot/render proof. No general balance, collision/navmesh, streaming/LOD, population scale, or hardware-performance certification follows from this recording.

## Paths and failure handling

Every phase accepts `--raw`, `--report`, `--outdir`, `--output`, `--narration`, `--route`, `--ffmpeg`, `--ffprobe`, and `--edge-deps`. Relative `--output` paths resolve inside `--outdir`; other paths resolve from the invoking directory. The defaults keep full capture inputs and deliverables under `build/town_walkthrough/full`, while dependencies remain under `build/town_walkthrough/python_deps`.

Arguments are passed directly to subprocesses without a shell. Each phase writes bounded command logs and a separate failure JSON on an error. An overlong take requires a wording/timing revision and voice rerun; an invalid source binding requires a new source-matched recording. Do not waive a failure by changing a report to PASS. Freeze the final tool, script, route, and source before the accepted run, then preserve the measured cache and reports beside the movie.
