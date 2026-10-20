#!/usr/bin/env python3
"""Narrate, compose and verify a six-minute actual Godot architectural tour.

No engine, network or media process runs at import. The voice phase reuses the
project's proven Edge TTS endpoint/cache/word timing helpers. The compose phase
uses the actual complete MovieWriter capture; it never substitutes stills or
pretends the asset inspection is playable game integration.

Example phases share --config inspection.json --scene generated/scene
--output fresh_media_folder. compose and verify also require --raw capture.ogv.
"""
from __future__ import annotations

import argparse
import asyncio
from fractions import Fraction
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import wave


REPO = Path(__file__).resolve().parents[2]
DURATION = 360
FPS = 18
FRAMES = DURATION * FPS
SAMPLE_RATE = 24000
MOVIE_NAME = "expanded_town_architectural_tour.mp4"
GIF_NAME = "expanded_town_tour.gif"
CHAPTER_IDS = ("compound_overview", "D06", "D07", "D08", "D09", "D10",
               "street_materials", "furnished_interior", "terrain_and_reserve")


def helpers():
    spec = importlib.util.spec_from_file_location("expansion_walkthrough_helpers", REPO / "tools/build_town_walkthrough.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


H = helpers()


def number(value):
    """Speak source-derived integer counts unambiguously in English."""
    value = int(value)
    small = ("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
             "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
    tens = ("", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")
    if value < 0:
        return "minus " + number(-value)
    if value < 20:
        return small[value]
    if value < 100:
        return tens[value//10] + (" " + small[value % 10] if value % 10 else "")
    if value < 1000:
        return small[value//100] + " hundred" + (" and " + number(value % 100) if value % 100 else "")
    if value < 1000000:
        return number(value//1000) + " thousand" + (" " + number(value % 1000) if value % 1000 else "")
    raise ValueError("Narration count is outside the bounded town scale")


def context(args):
    scene = args.scene.parent if args.scene.is_file() else args.scene
    manifest_path = scene / "expansion_manifest.json"
    plan_path = scene.parent / "territory_plan.json"
    manifest, plan, config = H.load_json(manifest_path), H.load_json(plan_path), H.load_json(args.config)
    if config.get("schema") != "living_town.territory_inspection_config.v1":
        raise ValueError("Not an architectural inspection configuration")
    if config.get("duration_seconds") != DURATION or config.get("fps") != FPS:
        raise ValueError("This tour requires exactly 360 seconds at 18 FPS")
    if tuple(row["id"] for row in config["cameras"]) != CHAPTER_IDS:
        raise ValueError("Narration and camera chapter order differ")
    if config["source_manifest_sha256"] != H.sha(manifest_path):
        raise ValueError("Inspection configuration is bound to a different scene manifest")
    if manifest.get("status") != "BUILT" or plan.get("validation", {}).get("status") != "PASS":
        raise ValueError("Narration requires an actually built and spatially validated expansion")
    if manifest["building_count"] != len(plan["buildings"]):
        raise ValueError("Plan and generated building counts differ")
    expected = {"schema": "living_town.expansion_tour_context.v1", "config": H.binding(args.config),
                "scene_manifest": H.binding(manifest_path), "territory_plan": H.binding(plan_path),
                "duration_seconds": DURATION, "fps": FPS,
                "scope": "Actual runtime architectural asset inspection; no playable simulation/physics/navigation claim"}
    if args.output == scene or args.output.is_relative_to(scene) or scene.is_relative_to(args.output):
        raise ValueError("Media output must be separate from the generated scene")
    marker = args.output / "media_context.json"
    if marker.exists():
        if H.load_json(marker) != expected:
            raise ValueError("Existing media belongs to different source inputs; use a fresh output folder")
    elif args.output.exists() and any(args.output.iterdir()):
        raise FileExistsError("Use a fresh or matching media output folder")
    elif args.phase != "voice":
        raise FileNotFoundError("Run the voice phase in a fresh media folder first")
    args.output.mkdir(parents=True, exist_ok=True)
    H.write_json(marker, expected)
    args.scene = scene
    return manifest, plan, config, expected


def narration(manifest, plan, config):
    counts = {d["id"]: sum(b["district"] == d["id"] for b in plan["buildings"]) for d in plan["districts"]}
    buildings, districts = number(manifest["building_count"]), number(len(plan["districts"]))
    floors, rooms = number(manifest["floor_count"]), number(manifest["room_count"])
    texts = [
        f"Welcome to Living Town. This is an architectural inspection of the actual exported assets running in Godot. The extension adds {buildings} furnished buildings across {districts} connected districts. The original coastal town and natural reserve remain part of the setting. Slow camera movements reveal the new territory as a connected place, with irregular streets, planted courts, and buildings that respond to their terrain.",
        f"The northern harbor quarter adds {number(counts['D06'])} buildings on the landward side of the coast. Its streets bend between small households, shops, workshops, and cafes. Frontages turn toward their own access streets, while side gaps and rear courts keep the blocks from becoming a rigid grid. Notice how the different roof heights and narrow passages give the settlement a more gradual, believable edge.",
        f"The western market quarter contains {number(counts['D07'])} new buildings. A bent market street and smaller workyard lane organize the neighborhood. Shop rooms, repair spaces, dwellings, and planted courts form a mixed setting rather than isolated repeated boxes. The emphasis is on useful relationships: a clear entrance from the street, service space behind the public rooms, and furniture arranged around the activities inside each building.",
        f"Here the hillside district adds {number(counts['D08'])} buildings along contour streets. The terrain stays uneven beyond the graded road and foundation pads. Stone plinths support the houses where the slope falls away, and the street follows a controlled elevation profile. These are authored fictional earthworks rather than a surveyed site, but their heights are shared by the planning data, the visible ground, and the generated building foundations.",
        f"The orchard edge includes {number(counts['D09'])} new buildings around a quieter lane. Garden houses, small shops, and working buildings create a transition between the denser town and the surrounding reserve. Rear planting, flower pots, and occasional trees break up the building fronts. The district is intended to suggest horticultural life and seasonal variation, while keeping entrances, street corridors, and the underlying terrain legible in the exported geometry.",
        f"The forest trailhead village adds {number(counts['D10'])} buildings beside the retained reserve. Cottages, service rooms, shops, and cycling cafes give this edge a different rhythm from the harbor. Conflicting original vegetation and surface obstacles are cleared around the new development, while the larger woodland remains. One separately generated Infinigen plant prototype is reused in selected courtyards; this is a bounded upstream asset contribution, not an upstream whole town generation run.",
        "At street level, pale plaster, slate, stone, oak, and painted joinery establish the material language. The plaster uses source bound, permissively licensed scanned color, roughness, and normal maps, with restrained weathering baked into a portable color texture. Real window apertures, roof courses, gutters, chimneys, and door surrounds add readable scale. The same conventional material channels travel in the exported glTF assets, rather than depending on Blender procedural shaders.",
        f"The extension contains {floors} furnished floors and {rooms} room zones. Public rooms, preparation spaces, private rooms, stairs, and landings serve different uses. Compact cafes retain required tables and service counters, with an open stair lobby where needed. Furniture backs, usable fronts, privacy, and pedestrian routes are checked before export; selected focus pieces receive detailed bespoke geometry.",
        "The final view returns to terrain, buildings, and woodland. Roads and pads share one height authority, while the coast and reserve remain. The package includes portable glTF chunks, packed Blender source, semantic identifiers, and collision planning metadata. This Godot capture checks imported visuals and camera presentation. It does not establish playable navigation, physics integration, accessibility, or real time performance; those remain separate consumer tasks.",
    ]
    segments = []
    for index, (camera, text) in enumerate(zip(config["cameras"], texts)):
        count = len(text.split())
        if not 60 <= count <= 70:
            raise ValueError(f"Paragraph {camera['id']} is outside its bounded script length: {count}")
        segments.append({"id": camera["id"], "title": camera["title"], "text": text,
                         "start": index*40+1.0, "end": index*40+36.0,
                         "chapter_start": index*40, "chapter_end": (index+1)*40,
                         "word_count": count})
    return {"schema": "living_town.expansion_tour_narration.v1", "voice": "en-US-AriaNeural",
            "rate": "-5%", "duration_seconds": DURATION, "segments": segments,
            "counts_from_generated_manifest": {k: manifest[k] for k in ("building_count", "district_count", "floor_count", "room_count")}}


def voice_wav(args, takes):
    target = args.output / "narration.wav"
    temporary = target.with_suffix(".wav.tmp")
    position = 0
    with wave.open(str(temporary), "wb") as audio:
        audio.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
        for take in takes:
            start, end = round(take["start"]*SAMPLE_RATE), round(take["end"]*SAMPLE_RATE)
            if position > start:
                raise ValueError("Decoded paragraph overlaps its next chapter")
            H.zeros(audio, start-position)
            command = [args.ffmpeg, "-hide_banner", "-v", "error", "-threads", "2", "-i", take["mp3"]["path"],
                       "-vn", "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", "-f", "s16le", "pipe:1"]
            decoded = subprocess.run(command, capture_output=True, timeout=60, check=True).stdout
            if len(decoded) % 2 or start+len(decoded)//2 > end:
                raise ValueError("Voice exceeds measured chapter budget; no clipping is permitted")
            audio.writeframesraw(decoded)
            position = start+len(decoded)//2
            take["decoded_samples"] = len(decoded)//2
        H.zeros(audio, DURATION*SAMPLE_RATE-position)
    with wave.open(str(temporary), "rb") as check:
        if check.getnframes() != DURATION*SAMPLE_RATE:
            raise ValueError("Narration WAV duration differs from six-minute camera route")
    os.replace(temporary, target)
    return target


def phase_voice(args):
    manifest, plan, config, _ = context(args)
    script = narration(manifest, plan, config)
    H.write_json(args.output / "narration_script.json", script)
    (args.output / "logs").mkdir(exist_ok=True)
    voice_args = argparse.Namespace(outdir=args.output, edge_deps=args.edge_deps, endpoint="migrated",
                                    respect_proxy=args.respect_proxy, refresh_voice=args.refresh_voice,
                                    ffprobe=args.ffprobe)
    with H.proxy_environment(args.respect_proxy):
        takes, provenance = asyncio.run(H.voice_takes(voice_args, script, script["segments"]))
    wav = voice_wav(args, takes)
    cues = [cue for take in takes for cue in H.make_cues(take["words"], take["end"], take["id"])]
    H.write_captions(args.output, cues)
    ass = args.output / "narration.ass"
    text = ass.read_text(encoding="utf-8").replace("Living Town actual-game walkthrough", "Living Town architectural asset tour")
    ass.write_text(text.replace("PlayResY: 864", "PlayResY: 896"), encoding="utf-8")
    report = {"schema": "living_town.expansion_tour_voice.v1", "status": "PASS", "generated_utc": H.utc(),
              "config": H.binding(args.config), "scene_manifest": H.binding(args.scene / "expansion_manifest.json"),
              "script": H.binding(args.output / "narration_script.json"), "voice": script["voice"],
              "rate": script["rate"], "provenance": provenance, "duration_seconds": DURATION,
              "takes": takes, "caption_count": len(cues), "audio_stats": H.wav_stats(wav),
              "assets": {p.name: H.binding(p) for p in (wav, ass, args.output / "narration.srt", args.output / "captions.json")},
              "human_listening_status": "PENDING; measured timing and PCM checks do not establish listening acceptance"}
    H.write_json(args.output / "voice_report.json", report)
    return report


def normalized_voice(args):
    source, target = args.output / "narration.wav", args.output / "narration_normalized.wav"
    analysis = H.run([args.ffmpeg, "-hide_banner", "-threads", "2", "-i", str(source), "-vn", "-af",
                      "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                     args.output / "logs/loudnorm_analysis.log")
    matches = re.findall(r'\{\s*"input_i".*?\}', analysis, re.S)
    if not matches:
        raise ValueError("No measured audio loudness analysis")
    measured = json.loads(matches[-1])
    if any(not math.isfinite(float(measured[k])) for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")):
        raise ValueError("Silent or invalid narration loudness")
    filt = ("loudnorm=I=-16:TP=-1.5:LRA=11:linear=true:print_format=json"
            f":measured_I={measured['input_i']}:measured_TP={measured['input_tp']}:measured_LRA={measured['input_lra']}"
            f":measured_thresh={measured['input_thresh']}:offset={measured['target_offset']},apad=whole_dur={DURATION}")
    H.run([args.ffmpeg, "-y", "-hide_banner", "-threads", "2", "-i", str(source), "-vn", "-af", filt,
           "-t", str(DURATION), "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le", str(target)],
          args.output / "logs/loudnorm_apply.log")
    return target, {"method": "separate two-pass measured loudnorm", "analysis": measured, "stats": H.wav_stats(target)}


def capture_timeline(args, config):
    capture_path = Path(config["report"])
    capture = H.load_json(capture_path)
    if capture.get("status") != "PASS" or not capture.get("movie_mode") or capture.get("tour_frames") != FRAMES:
        raise ValueError("A complete successful 6480-frame actual viewer movie is required")
    if capture.get("config_sha256") != H.sha(args.config):
        raise ValueError("Runtime capture belongs to another inspection configuration")
    info = H.probe(args.raw, args.ffprobe, count_frames=True)
    video = H.stream_of(info, "video")
    if not video or abs(float(Fraction(video["avg_frame_rate"]))-FPS) > .001:
        raise ValueError("Raw camera capture is not 18 FPS")
    if (video.get("width"), video.get("height")) != (1280, 800):
        raise ValueError("Raw capture must preserve the complete 1280x800 viewer frame")
    trailing = 0
    packet_proof = None
    if video.get("codec_name") == "theora":
        if video.get("time_base") != "1/18":
            raise ValueError("Theora packet timeline does not use the configured 18 FPS timebase")
        result = subprocess.run([args.ffprobe, "-v", "error", "-select_streams", "v:0", "-show_packets",
                                 "-show_entries", "packet=pts,duration,size", "-of", "json", str(args.raw)],
                                capture_output=True, text=True, encoding="utf-8", timeout=120, check=True)
        table = json.loads(result.stdout)
        packets = table["packets"]
        if not packets or int(packets[0].get("size", 0)) <= 0:
            raise ValueError("Raw Theora timeline has no initial real picture")
        if any(p.get("pts") != i or p.get("duration") != 1 or int(p.get("size", -1)) < 0 for i, p in enumerate(packets)):
            raise ValueError("Noncontiguous actual Theora packet timeline")
        for packet in reversed(packets):
            if int(packet["size"]) != 0:
                break
            trailing += 1
        frame_count = len(packets)
        H.write_json(args.output / "raw_video_packets.json", table)
        packet_proof = {"packet_count": frame_count, "trailing_repeat_packets": trailing,
                        "repeat_packets": sum(int(p["size"]) == 0 for p in packets),
                        "table": H.binding(args.output / "raw_video_packets.json"),
                        "method": "Restore repeated pictures at actual packet PTS before frame-based prefix trim"}
    else:
        frame_count = int(video.get("nb_read_frames", 0))
    prefix = frame_count-FRAMES
    warmup = capture.get("movie_warmup_engine_frames")
    if prefix < 0 or prefix > FPS*30:
        raise ValueError(f"Capture cannot prove a bounded lead-in prefix: {prefix} frames")
    if warmup is not None and abs(prefix-int(warmup)) > 3:
        raise ValueError(f"Read-back frame excess {prefix} differs from viewer warmup {warmup}")
    tail = f",tpad=stop_mode=clone:stop={trailing}" if trailing else ""
    filt = f"fps={FPS}:start_time=0{tail},trim=start_frame={prefix}:end_frame={prefix+FRAMES},setpts=PTS-STARTPTS"
    return capture, capture_path, {"raw_probe": info, "source_timeline_frames": frame_count,
        "expected_route_frames": FRAMES, "lead_in_frames_removed": prefix, "lead_in_seconds": prefix/FPS,
        "viewer_warmup_engine_frames": warmup, "theora_packet_proof": packet_proof, "filter": filt}


def metadata_text(config):
    def escaped(text):
        return str(text).replace("\\", "\\\\").replace("=", "\\=").replace(";", "\\;").replace("#", "\\#").replace("\n", " ")
    lines = [";FFMETADATA1", "title=Living Town: expanded territory architectural tour",
             "comment=Actual Godot asset inspection. Offline MovieWriter capture, not gameplay or real-time performance evidence."]
    for index, camera in enumerate(config["cameras"]):
        lines += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={index*40000}", f"END={(index+1)*40000}", "title="+escaped(camera["title"])]
    return "\n".join(lines)+"\n"


def make_gif(args, movie):
    # Five true excerpts span town scale, two districts, materials and cutaway.
    samples = ((14, 18), (54, 58), (94, 98), (254, 258), (294, 298))
    target = args.output / GIF_NAME
    for fps, colors in ((8, 80), (6, 48)):
        chunks = [f"[0:v]trim=start={start}:end={end},setpts=PTS-STARTPTS,fps={fps},scale=640:-2:flags=lanczos[v{i}]"
                  for i, (start, end) in enumerate(samples)]
        chunks += ["".join(f"[v{i}]" for i in range(len(samples))) +
                   f"concat=n={len(samples)}:v=1:a=0,split[a][b]",
                   f"[a]palettegen=max_colors={colors}:stats_mode=diff[p]", "[b][p]paletteuse=dither=bayer:bayer_scale=3[g]"]
        graph = args.output / "gif_filters.txt"
        graph.write_text(";".join(chunks)+"\n", encoding="utf-8")
        H.run([args.ffmpeg, "-y", "-hide_banner", "-threads", "4", "-i", str(movie),
               "-filter_complex_threads", "1", "-filter_complex_script", str(graph), "-map", "[g]", "-loop", "0", str(target)],
              args.output / "logs" / f"gif_{fps}fps.log")
        if target.stat().st_size <= 10_000_000:
            return {"asset": H.binding(target), "samples_from_actual_mp4_seconds": samples,
                    "duration_seconds": 20, "width": 640, "fps": fps, "palette_colors": colors}
    raise ValueError("Actual-footage GIF still exceeds the ten-megabyte bound")


def phase_compose(args):
    _, _, config, _ = context(args)
    voice = H.load_json(args.output / "voice_report.json")
    if voice.get("status") != "PASS" or voice["config"]["sha256"] != H.sha(args.config):
        raise ValueError("Voice is missing or bound to stale source inputs")
    H.check_binding(voice["script"], "narration script")
    for name, asset in voice["assets"].items():
        H.check_binding(asset, name)
    _, capture_path, timeline = capture_timeline(args, config)
    normalized, loudness = normalized_voice(args)
    metadata = args.output / "chapters.ffmetadata"
    metadata.write_text(metadata_text(config), encoding="utf-8")
    graph = args.output / "composition_filters.txt"
    graph.write_text(f"[0:v]{timeline['filter']},scale=out_range=tv,format=yuv420p,setparams=range=limited,pad=1280:896:0:0:color=0x111b1c,subtitles=filename=narration.ass[v]\n", encoding="utf-8")
    movie = args.output / MOVIE_NAME
    command = [args.ffmpeg, "-y", "-hide_banner", "-threads", "4", "-i", str(args.raw), "-i", str(normalized),
               "-f", "ffmetadata", "-i", str(metadata), "-filter_complex_threads", "2", "-filter_complex_script", str(graph),
               "-map", "[v]", "-map", "1:a:0", "-map_metadata", "2", "-map_chapters", "2",
               "-frames:v", str(FRAMES), "-t", str(DURATION), "-c:v", "libx264", "-threads:v", "6",
               "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-color_range", "tv", "-c:a", "aac", "-b:a", "160k",
               "-ar", str(SAMPLE_RATE), "-movflags", "+faststart", str(movie)]
    H.run(command, args.output / "logs/compose.log", cwd=args.output)
    gif = make_gif(args, movie)
    report = {"schema": "living_town.expansion_tour_composition.v1", "status": "PASS", "generated_utc": H.utc(),
              "builder": H.binding(Path(__file__)), "config": H.binding(args.config), "raw": H.binding(args.raw),
              "capture_report": H.binding(capture_path), "voice_report": H.binding(args.output / "voice_report.json"),
              "timeline": timeline, "loudness": loudness, "output": H.binding(movie), "gif": gif,
              "command": command, "audio_mode": "Measured Edge TTS narration only; no invented game audio or ambience",
              "assets": {p.name: H.binding(p) for p in (normalized, metadata, graph, args.output / "narration.ass", args.output / "narration.srt", args.output / "captions.json")},
              "human_listening_status": "PENDING", "visual_acceptance_status": "PENDING actual-frame review"}
    H.write_json(args.output / "composition_report.json", report)
    return report


def phase_verify(args):
    _, _, config, _ = context(args)
    composition = H.load_json(args.output / "composition_report.json")
    if composition.get("status") != "PASS":
        raise ValueError("Compose the actual capture before verifying")
    for key in ("builder", "config", "raw", "capture_report", "voice_report", "output"):
        H.check_binding(composition[key], key)
    for name, asset in composition["assets"].items():
        H.check_binding(asset, name)
    H.check_binding(composition["gif"]["asset"], "GIF")
    movie = args.output / MOVIE_NAME
    info = H.probe(movie, args.ffprobe, count_frames=True)
    video, audio = H.stream_of(info, "video"), H.stream_of(info, "audio")
    checks = []
    def check(name, passed, detail=None):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})
    check("duration_360_seconds", abs(H.media_duration(info)-DURATION) <= .12, H.media_duration(info))
    check("h264_yuv420p_full_viewer_plus_caption_band", bool(video) and video.get("codec_name") == "h264"
          and video.get("pix_fmt") == "yuv420p" and (video.get("width"), video.get("height")) == (1280, 896))
    check("exact_18fps_6480_frames", bool(video) and float(Fraction(video["avg_frame_rate"])) == FPS
          and int(video.get("nb_read_frames", 0)) == FRAMES, video.get("nb_read_frames") if video else None)
    check("aac_narration", bool(audio) and audio.get("codec_name") == "aac")
    chapters = info.get("chapters", [])
    chapter_ok = len(chapters) == len(config["cameras"])
    if chapter_ok:
        chapter_ok = all(abs(float(row["start_time"])-index*40) < .02 and abs(float(row["end_time"])-(index+1)*40) < .02
                         and row.get("tags", {}).get("title") == config["cameras"][index]["title"] for index, row in enumerate(chapters))
    check("nine_chapters_cover_entire_capture", chapter_ok)
    cues = H.load_json(args.output / "captions.json")["cues"]
    script = H.load_json(args.output / "narration_script.json")
    previous = 0
    caption_ok = bool(cues)
    for cue in cues:
        caption_ok &= previous <= cue["start"] < cue["end"] <= DURATION and 1 <= len(cue["lines"]) <= 2 and all(len(line) <= 54 for line in cue["lines"])
        previous = cue["end"]
    expected_text = "".join(s["text"] for s in script["segments"])
    actual_text = "".join(" ".join(cue["lines"]) for cue in cues)
    caption_ok &= H.normalized_units(expected_text) and "".join(c for c, _ in H.normalized_units(expected_text)) == "".join(c for c, _ in H.normalized_units(actual_text))
    caption_ok &= all(any(c["segment_id"] == segment["id"] for c in cues) for segment in script["segments"])
    check("measured_word_captions_cover_complete_spoken_script", caption_ok, len(cues))
    # Read the MP4 atom order without loading the whole video into memory.
    atoms = []
    with movie.open("rb") as stream:
        while stream.tell() < movie.stat().st_size:
            head = stream.read(8)
            if len(head) < 8:
                break
            size, kind = int.from_bytes(head[:4], "big"), head[4:].decode("ascii", "replace")
            if size == 1:
                size = int.from_bytes(stream.read(8), "big")
                header = 16
            else:
                header = 8
            atoms.append(kind)
            if size < header:
                break
            stream.seek(size-header, 1)
    check("faststart_moov_precedes_media", "moov" in atoms and "mdat" in atoms and atoms.index("moov") < atoms.index("mdat"), atoms)
    qa = args.output / "qa_frames"
    qa.mkdir(exist_ok=True)
    times = [index*40+offset for index in range(9) for offset in (6, 30)]
    selected = "+".join(f"eq(n,{round(t*FPS)})" for t in times)
    H.run([args.ffmpeg, "-y", "-hide_banner", "-v", "error", "-xerror", "-err_detect", "explode", "-threads", "4",
           "-i", str(movie), "-vf", f"select='{selected}',scale=640:-2", "-vsync", "0", "-frames:v", str(len(times)), str(qa / "frame_%02d.png")],
          args.output / "logs/qa_decode.log")
    from PIL import Image, ImageChops, ImageStat
    frame_records, motion = [], []
    previous_image = None
    for index, when in enumerate(times, 1):
        file = qa / f"frame_{index:02d}.png"
        image = Image.open(file).convert("RGB").crop((0, 55, 640, 375))
        variation = sum(ImageStat.Stat(image).stddev)/3
        frame_records.append({"time_seconds": when, "file": H.binding(file), "scene_roi_stddev": variation})
        if index % 2 == 0:
            difference = ImageChops.difference(previous_image, image)
            mean = sum(ImageStat.Stat(difference).mean)/3
            motion.append({"chapter": config["cameras"][(index-1)//2]["id"], "scene_roi_mean_pixel_difference": mean, "passed": mean > .35})
        previous_image = image
    check("actual_scene_frames_nonblank", all(r["scene_roi_stddev"] > 3 for r in frame_records), frame_records)
    check("camera_motion_in_each_chapter_excluding_hud_and_captions", all(row["passed"] for row in motion), motion)
    command = [args.ffmpeg, "-hide_banner", "-v", "error", "-threads", "2", "-i", str(movie), "-vn", "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "s16le", "pipe:1"]
    with (args.output / "logs/audio_decode.log").open("wb") as error:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=error) as process:
            stats = H.pcm_stats(iter(lambda: process.stdout.read(65536), b""))
            if process.wait(timeout=120):
                raise ValueError("Final AAC narration failed decoding")
    check("decoded_audio_covers_route", abs(stats["duration_seconds"]-DURATION) <= .12, stats)
    check("narration_non_silent_and_no_fullscale_clipping", stats["rms_dbfs"] is not None and stats["rms_dbfs"] > -40
          and stats["peak_dbfs"] is not None and stats["peak_dbfs"] > -30 and not stats["full_scale_peak"], stats)
    gif_path = args.output / GIF_NAME
    with Image.open(gif_path) as gif:
        gif_frames, gif_duration = gif.n_frames, 0
        for index in range(gif_frames):
            gif.seek(index)
            gif_duration += gif.info.get("duration", 0)/1000
        gif_width = gif.width
    check("actual_footage_gif_small_and_animated", gif_width == 640 and gif_frames >= 100 and 19.5 <= gif_duration <= 20.5
          and gif_path.stat().st_size <= 10_000_000, {"frames": gif_frames, "seconds": gif_duration, "bytes": gif_path.stat().st_size})
    report = {"schema": "living_town.expansion_tour_verification.v1", "status": "PASS" if all(c["passed"] for c in checks) else "FAIL",
              "generated_utc": H.utc(), "checks": checks, "probe": info, "decoded_audio": stats,
              "output": H.binding(movie), "gif": H.binding(gif_path), "composition_report": H.binding(args.output / "composition_report.json"),
              "qa_frames": frame_records, "actual_camera_motion": motion,
              "human_listening_status": "PENDING; no human listening acceptance is claimed",
              "visual_acceptance_status": "PENDING actual-frame art review; objective nonblank/motion checks alone are insufficient",
              "scope": "Actual offline Godot architectural asset capture. No playable game, navigation, physics, or real-time performance integration claim."}
    H.write_json(args.output / "verification_report.json", report)
    if report["status"] != "PASS":
        raise ValueError("Tour technical verification failed; inspect verification_report.json")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("voice", "compose", "verify"))
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--raw", type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--edge-deps", type=Path, default=REPO / "build/town_walkthrough/python_deps")
    parser.add_argument("--respect-proxy", action="store_true")
    parser.add_argument("--refresh-voice", action="store_true")
    args = parser.parse_args()
    for name in ("config", "scene", "output", "raw", "edge_deps"):
        if getattr(args, name) is not None:
            setattr(args, name, getattr(args, name).resolve())
    if args.phase != "voice" and (args.raw is None or not args.raw.is_file()):
        parser.error("compose and verify require an existing --raw actual MovieWriter capture")
    args.ffmpeg, args.ffprobe = H.tool(args.ffmpeg), H.tool(args.ffprobe)
    result = {"voice": phase_voice, "compose": phase_compose, "verify": phase_verify}[args.phase](args)
    print(json.dumps({"status": result["status"], "phase": args.phase, "output": str(args.output)}, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
