#!/usr/bin/env python3
"""Build a narrated recording of the actual Living Town game, in explicit phases.

No engine, network, or media process runs at import time. See --help and
docs/town_walkthrough/RECORDING.md. External commands always use argv, never a shell.
"""
from __future__ import annotations

import argparse
import array
import asyncio
import contextlib
import hashlib
import html
import importlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import uuid
import wave
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
DURATION = 840
FPS = 18
SAMPLE_RATE = 24000
FRAME_COUNT = DURATION * FPS
ENDPOINT = "wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1"
UPSTREAM_FIX = "https://github.com/rany2/edge-tts/pull/491"
TICKS_PER_SECOND = 10_000_000
CHUNK = 1024 * 1024


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(CHUNK), b""):
            digest.update(data)
    return digest.hexdigest()


def signature(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(",", ":")).encode()).hexdigest()


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                    encoding="utf-8")
    os.replace(temp, path)


def binding(path: Path) -> dict:
    return {"path": str(path.resolve()), "bytes": path.stat().st_size, "sha256": sha(path)}


def tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return str(Path(found).resolve())
    path = Path(name)
    if path.is_file():
        return str(path.resolve())
    raise ValueError(f"Executable not found: {name}")


def run(argv: list[str], log: Path, cwd: Path | None = None,
        timeout: int = 7200) -> str:
    """Capture bounded command output on disk; avoid shell quoting and pipe deadlocks."""
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8", errors="replace") as stream:
        stream.write(json.dumps(argv, ensure_ascii=False) + "\n")
        stream.flush()
        result = subprocess.run(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=timeout, check=False)
    content = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"Command exited {result.returncode}; see {log}\n{content[-3000:]}")
    return content


def probe(path: Path, ffprobe: str, count_frames: bool = False) -> dict:
    argv = [ffprobe, "-v", "error", "-show_format", "-show_streams", "-show_chapters"]
    if count_frames:
        argv.append("-count_frames")
    argv += ["-of", "json", str(path)]
    result = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=7200, check=False)
    if result.returncode:
        raise RuntimeError(f"ffprobe failed on {path}: {result.stderr[-2000:]}")
    return json.loads(result.stdout)


def stream_of(info: dict, kind: str) -> dict | None:
    return next((s for s in info.get("streams", []) if s.get("codec_type") == kind), None)


def media_duration(info: dict) -> float:
    return float(info.get("format", {}).get("duration", 0))


def load_plan(args: argparse.Namespace) -> tuple[dict, dict, list[dict]]:
    narration, route = load_json(args.narration), load_json(args.route)
    segments = narration.get("segments", [])
    if len(segments) != 24 or len(route.get("chapters", [])) != 12:
        raise ValueError("Expected the reviewed 24 paragraphs and 12 chapters")
    if narration.get("planned_duration_seconds") != DURATION or route.get("duration_seconds") != DURATION:
        raise ValueError("This builder requires the reviewed 840-second route")
    if route.get("fps") != FPS:
        raise ValueError("Route must use 18 FPS")
    previous = -1.0
    ids = set()
    chapters = route["chapters"]
    chapter_cursor = 0.0
    for chapter in chapters:
        if float(chapter["start_seconds"]) != chapter_cursor:
            raise ValueError("Route chapters must cover the timeline without gaps")
        chapter_cursor = float(chapter["end_seconds"])
    if chapter_cursor != DURATION:
        raise ValueError("Route chapters do not reach 840 seconds")
    for seg in segments:
        if not all(k in seg for k in ("start", "end", "chapter", "title", "text", "notes")):
            raise ValueError("Narration segment fields are incomplete")
        seg.setdefault("id", f"segment_{len(ids) + 1:02}")
        start, end = float(seg["start"]), float(seg["end"])
        if not 0 <= start < end <= DURATION or start < previous or seg["id"] in ids:
            raise ValueError(f"Overlapping/invalid paragraph: {seg['id']}")
        chapter = chapters[int(seg["chapter"]) - 1]
        if start < chapter["start_seconds"] or end > chapter["end_seconds"]:
            raise ValueError(f"Paragraph exceeds chapter: {seg['id']}")
        if not str(seg["text"]).strip():
            raise ValueError("Empty voice paragraph")
        previous = end
        ids.add(seg["id"])
    return narration, route, segments


def normalized_units(text: str) -> list[tuple[str, int]]:
    units = []
    for index, char in enumerate(text):
        for unit in unicodedata.normalize("NFKD", char).casefold():
            if unit.isalnum():
                units.append((unit, index))
    return units


def align_words(text: str, boundaries: list[dict], start: float, end: float) -> list[dict]:
    """Restore original punctuation without inventing word timing or losing contractions."""
    units = normalized_units(text)
    cursor, display_cursor = 0, 0
    words = []
    last_offset = -1.0
    for boundary in boundaries:
        wanted = "".join(c for c, _ in normalized_units(html.unescape(boundary["text"])))
        if not wanted:
            continue
        actual = "".join(c for c, _ in units[cursor:cursor + len(wanted)])
        if actual != wanted:
            raise ValueError(f"Word boundary does not match narration near {boundary['text']!r}")
        offset = float(boundary["offset"]) / TICKS_PER_SECOND
        duration = float(boundary["duration"]) / TICKS_PER_SECOND
        if offset < last_offset or duration < 0 or start + offset + duration > end + 0.001:
            raise ValueError("Word boundary lies outside its measured paragraph window")
        cursor += len(wanted)
        display_end = units[cursor][1] if cursor < len(units) else len(text)
        words.append({"start": start + offset, "end": start + offset + duration,
                      "text": text[display_cursor:display_end]})
        display_cursor, last_offset = display_end, offset
    if not words or cursor != len(units):
        raise ValueError("Incomplete WordBoundary metadata; refusing guessed subtitles")
    return words


def caption_lines(text: str) -> list[str]:
    text = " ".join(text.split())
    if len(text) > 90:
        raise ValueError("Caption group is longer than 90 characters")
    if len(text) <= 54:
        return [text]
    positions = [i for i, c in enumerate(text) if c == " " and i <= 54 and len(text) - i - 1 <= 54]
    if not positions:
        raise ValueError(f"Cannot wrap caption into two readable lines: {text}")
    split = min(positions, key=lambda i: abs(i - (len(text) - i - 1)))
    return [text[:split], text[split + 1:]]


def make_cues(words: list[dict], window_end: float, segment_id: str) -> list[dict]:
    groups, current = [], []
    for word in words:
        candidate = "".join(w["text"] for w in current + [word]).strip()
        sentence_end = current and current[-1]["text"].rstrip().endswith((".", "!", "?"))
        if current and (len(" ".join(candidate.split())) > 90 or
                        word["end"] - current[0]["start"] > 4.8 or
                        (sentence_end and current[-1]["end"] - current[0]["start"] >= 1.4)):
            groups.append(current)
            current = []
        current.append(word)
    if current:
        groups.append(current)
    cues = []
    for index, group in enumerate(groups):
        next_start = groups[index + 1][0]["start"] if index + 1 < len(groups) else window_end + 0.02
        end = min(max(group[-1]["end"] + 0.18, group[0]["start"] + 1.1), next_start - 0.02, window_end)
        if end <= group[0]["start"]:
            raise ValueError("Non-positive subtitle duration")
        cues.append({"start": group[0]["start"], "end": end,
                     "lines": caption_lines("".join(w["text"] for w in group)),
                     "segment_id": segment_id})
    return cues


def stamp(seconds: float, ass: bool = False, end: bool = False) -> str:
    scale = 100 if ass else 1000
    ticks = math.ceil(seconds * scale - 1e-8) if end else math.floor(seconds * scale + 1e-8)
    whole, fraction = divmod(ticks, scale)
    hours, rest = divmod(whole, 3600)
    minutes, sec = divmod(rest, 60)
    return (f"{hours}:{minutes:02}:{sec:02}.{fraction:02}" if ass else
            f"{hours:02}:{minutes:02}:{sec:02},{fraction:03}")


def write_captions(outdir: Path, cues: list[dict]) -> None:
    header = """[Script Info]
Title: Living Town actual-game walkthrough
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 864
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,25,&H00FFFFFF,&H00FFFFFF,&H00101720,&H00101720,0,0,0,0,100,100,0,0,1,2,0.7,2,48,48,18,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ass_lines, srt = [header], []
    previous = 0.0
    for index, cue in enumerate(cues, 1):
        if cue["start"] < previous - 0.001:
            raise ValueError("Overlapping caption groups")
        previous = cue["end"]
        lines = [line.replace("{", "(").replace("}", ")").replace("\\", "/") for line in cue["lines"]]
        ass_lines.append(f"Dialogue: 0,{stamp(cue['start'], True)},{stamp(cue['end'], True, True)},Default,,0,0,0,," + "\\N".join(lines) + "\n")
        srt += [str(index), f"{stamp(cue['start'])} --> {stamp(cue['end'], end=True)}", *cue["lines"], ""]
    (outdir / "narration.ass").write_text("".join(ass_lines), encoding="utf-8")
    (outdir / "narration.srt").write_text("\n".join(srt) + "\n", encoding="utf-8")
    write_json(outdir / "captions.json", {"schema": "living_town.walkthrough.captions.v1",
                                        "timing_source": "actual Edge TTS WordBoundary metadata",
                                        "cues": cues})


@contextlib.contextmanager
def proxy_environment(respect_proxy: bool):
    names = ("HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "https_proxy", "http_proxy", "all_proxy")
    saved = {name: os.environ[name] for name in names if name in os.environ}
    try:
        if not respect_proxy:
            for name in names:
                os.environ.pop(name, None)
        yield
    finally:
        if not respect_proxy:
            os.environ.update(saved)


async def voice_takes(args: argparse.Namespace, narration: dict, segments: list[dict]) -> tuple[list[dict], dict]:
    if args.edge_deps.is_dir():
        sys.path.insert(0, str(args.edge_deps))
    try:
        edge = importlib.import_module("edge_tts")
        communicate = importlib.import_module("edge_tts.communicate")
        constants = importlib.import_module("edge_tts.constants")
    except ImportError as exc:
        raise ValueError("Install edge-tts 7.2.8 into --edge-deps before the voice phase") from exc
    original_endpoint = communicate.WSS_URL
    if args.endpoint == "migrated":
        communicate.WSS_URL = ENDPOINT + "?Ocp-Apim-Subscription-Key=" + constants.TRUSTED_CLIENT_TOKEN
    # The endpoint label deliberately excludes the client's public token from logs.
    endpoint_label = communicate.WSS_URL.split("?", 1)[0]
    provenance = {"edge_tts_version": str(edge.__version__), "endpoint": endpoint_label,
                  "shim_applied": communicate.WSS_URL != original_endpoint,
                  "shim_scope": "process-local edge_tts.communicate.WSS_URL assignment only",
                  "upstream_reference": UPSTREAM_FIX, "reference_reviewed_date": "2026-10-12",
                  "installed_library_sources_modified": False,
                  "proxy_environment_used": bool(args.respect_proxy)}
    cache = args.outdir / "voice_cache"
    cache.mkdir(parents=True, exist_ok=True)
    takes = []
    for seg in segments:
        request = {"text": seg["text"], "voice": narration["voice"], "rate": narration.get("rate", "+0%"),
                   "boundary": "WordBoundary", "endpoint": endpoint_label,
                   "edge_tts_version": str(edge.__version__)}
        key = signature(request)
        mp3, words, meta = (cache / f"{key}{suffix}" for suffix in (".mp3", ".words.json", ".meta.json"))
        cached = False
        if not args.refresh_voice and mp3.is_file() and words.is_file() and meta.is_file():
            old = load_json(meta)
            cached = old.get("request") == request and old.get("mp3_sha256") == sha(mp3) and old.get("words_sha256") == sha(words)
        attempts = []
        if not cached:
            for attempt in range(1, 4):
                temporary = cache / f"{key}.{uuid.uuid4().hex}.mp3.tmp"
                boundaries = []
                try:
                    async def synthesize():
                        tts = edge.Communicate(request["text"], request["voice"], rate=request["rate"],
                                               boundary="WordBoundary", connect_timeout=15, receive_timeout=60)
                        with temporary.open("wb") as audio:
                            async for event in tts.stream():
                                if event["type"] == "audio":
                                    audio.write(event["data"])
                                elif event["type"] == "WordBoundary":
                                    boundaries.append({k: event[k] for k in ("offset", "duration", "text")})
                    await asyncio.wait_for(synthesize(), timeout=150)
                    if temporary.stat().st_size < 1000 or not boundaries:
                        raise ValueError("TTS response has no usable audio or word boundaries")
                    duration = media_duration(probe(temporary, args.ffprobe))
                    if duration <= 0:
                        raise ValueError("TTS MP3 duration is invalid")
                    os.replace(temporary, mp3)
                    write_json(words, {"boundaries": boundaries})
                    write_json(meta, {"request": request, "generated_utc": utc(), "duration_seconds": duration,
                                      "mp3_sha256": sha(mp3), "words_sha256": sha(words), "provenance": provenance})
                    attempts.append({"attempt": attempt, "status": "PASS"})
                    break
                except Exception as exc:
                    temporary.unlink(missing_ok=True)
                    attempts.append({"attempt": attempt, "status": "FAIL", "error": str(exc)[:500]})
                    if attempt == 3:
                        raise RuntimeError(f"TTS failed for paragraph {seg['id']} after 3 attempts: {exc}") from exc
                    await asyncio.sleep(2 ** attempt)
        duration = media_duration(probe(mp3, args.ffprobe))
        budget = float(seg["end"]) - float(seg["start"])
        if duration > budget + 0.0001:
            raise ValueError(f"Paragraph {seg['id']} takes {duration:.3f}s, exceeds {budget:.3f}s window; shorten the script or change the reviewed route, then regenerate")
        boundaries = load_json(words)["boundaries"]
        aligned = align_words(seg["text"], boundaries, float(seg["start"]), float(seg["end"]))
        takes.append({"id": seg["id"], "start": seg["start"], "end": seg["end"], "duration_seconds": duration,
                      "cached": cached, "request_hash": key, "request": request,
                      "mp3": binding(mp3), "word_boundaries": binding(words), "words": aligned, "attempts": attempts})
        print(f"VOICE {seg['id']} {duration:.3f}/{budget:.3f}s {'cache' if cached else 'generated'}", flush=True)
    return takes, provenance


def zeros(audio: wave.Wave_write, frames: int) -> None:
    block = bytes(65536)
    while frames:
        count = min(frames, len(block) // 2)
        audio.writeframesraw(block[:count * 2])
        frames -= count


def build_voice_wav(args: argparse.Namespace, takes: list[dict]) -> Path:
    path = args.outdir / "narration.wav"
    temporary = path.with_suffix(".wav.tmp")
    position = 0
    try:
        with wave.open(str(temporary), "wb") as output:
            output.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
            for take in takes:
                start = round(float(take["start"]) * SAMPLE_RATE)
                end = round(float(take["end"]) * SAMPLE_RATE)
                if position > start:
                    raise ValueError("Decoded voice overlaps next paragraph")
                zeros(output, start - position)
                position = start
                command = [args.ffmpeg, "-hide_banner", "-v", "error", "-threads", "2", "-i", take["mp3"]["path"],
                           "-vn", "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", "-f", "s16le", "pipe:1"]
                with (args.outdir / "logs" / f"decode_voice_{take['id']}.log").open("wb") as error:
                    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=error) as process:
                        carry = b""
                        while True:
                            data = process.stdout.read(65536)
                            if not data:
                                break
                            data = carry + data
                            count = len(data) - len(data) % 2
                            carry = data[count:]
                            if position + count // 2 > end:
                                process.kill()
                                raise ValueError(f"Decoded paragraph {take['id']} exceeds its window; no clipping performed")
                            output.writeframesraw(data[:count])
                            position += count // 2
                        if process.wait(timeout=60) or carry:
                            raise RuntimeError(f"Voice decode failed: {take['id']}")
                take["decoded_samples"] = position - start
            zeros(output, DURATION * SAMPLE_RATE - position)
        with wave.open(str(temporary), "rb") as check:
            if check.getnframes() != DURATION * SAMPLE_RATE:
                raise ValueError("Narration WAV is not exactly 840 seconds")
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return path


def phase_voice(args: argparse.Namespace) -> dict:
    narration, _, segments = load_plan(args)
    with proxy_environment(args.respect_proxy):
        takes, provenance = asyncio.run(voice_takes(args, narration, segments))
    voice_wav = build_voice_wav(args, takes)
    cues = []
    for take in takes:
        cues += make_cues(take["words"], float(take["end"]), take["id"])
    write_captions(args.outdir, cues)
    report = {"schema": "living_town.walkthrough.voice.v1", "status": "PASS", "generated_utc": utc(),
              "narration": binding(args.narration), "route": binding(args.route), "builder": binding(Path(__file__)),
              "voice": narration["voice"], "rate": narration.get("rate", "+0%"), "provenance": provenance,
              "segment_count": len(takes), "caption_count": len(cues), "duration_seconds": DURATION,
              "sample_rate": SAMPLE_RATE, "channels": 1, "sample_format": "s16le", "takes": takes,
              "assets": {p.name: binding(p) for p in (voice_wav, args.outdir / "narration.ass",
                                                     args.outdir / "narration.srt", args.outdir / "captions.json")}}
    write_json(args.outdir / "voice_report.json", report)
    return report


def check_binding(record: dict, label: str) -> Path:
    path = Path(record["path"])
    if not path.is_file() or path.stat().st_size != record["bytes"] or sha(path) != record["sha256"]:
        raise ValueError(f"Changed/missing bound asset: {label}: {path}")
    return path


def capture_contract(args: argparse.Namespace) -> tuple[dict, int]:
    report = load_json(args.report)
    if report.get("status") != "PASS" or report.get("preview", True) or not report.get("route_complete"):
        raise ValueError("Require a completed PASS full route, not a preview or failed recording")
    if report.get("fps") != FPS or report.get("expected_tour_frames") != FRAME_COUNT:
        raise ValueError("Capture report is not the 840-second/18-FPS route")
    if report.get("direct_agent_writes") is not False:
        raise ValueError("Capture must explicitly report no direct agent writes")
    if not report.get("checks") or report.get("failure_count") != 0:
        raise ValueError("Capture must contain passing route checks and zero failures")
    offsets = [report[k] for k in ("movie_boot_frame_offset", "movie_boot_frames_to_trim") if k in report]
    if not offsets or any(not isinstance(x, int) or isinstance(x, bool) or x < 0 for x in offsets) or len(set(offsets)) != 1:
        raise ValueError("Capture must report one consistent non-negative integer boot-frame offset")
    sources = {"harness_sha256": ROOT / "game/scripts/town_walkthrough.gd",
               "route_plan_sha256": args.route, "projection_sha256": ROOT / "game/data/town3d/projection.json",
               "profile_sha256": ROOT / "game/data/town3d/profile.json",
               "stage_manifest_sha256": ROOT / "game/assets/town3d/stage_manifest.json",
               "characters_manifest_sha256": ROOT / "game/data/town3d/characters.json"}
    for key, path in sources.items():
        if not report.get(key) or sha(path) != report[key]:
            raise ValueError(f"Capture source is stale or unbound: {key}")
    stage = load_json(ROOT / "game/assets/town3d/stage_manifest.json")
    profile = load_json(ROOT / "game/data/town3d/profile.json")
    for relative,digest in profile.get("presentation_source_hashes",{}).items():
        source=(ROOT/relative).resolve()
        if not source.is_relative_to(ROOT) or sha(source)!=digest:
            raise ValueError("Presentation code changed after the recorded profile freeze: "+relative)
    if stage.get("schema") != "living_town.game_stage.v2" or report.get("source_glb_sha256") != stage.get("source_asset_set_sha256"):
        raise ValueError("Capture does not bind the exact upgraded whole-town asset set")
    for asset in stage.get("assets", []):
        path = ROOT / "game/assets/town3d" / asset["file"]
        if not path.is_file() or sha(path) != asset["sha256"]:
            raise ValueError("Recorded visual chunk changed: " + asset["file"])
    if any(not bool(check.get("passed", False)) for check in report.get("checks", [])):
        raise ValueError("Capture contains a failed route check")
    return report, offsets[0]


def pcm_stats(chunks) -> dict:
    count = total_square = peak = nonzero = 0
    carry = b""
    for data in chunks:
        data = carry + data
        size = len(data) - len(data) % 2
        carry = data[size:]
        samples = array.array("h")
        samples.frombytes(data[:size])
        if sys.byteorder != "little":
            samples.byteswap()
        if samples:
            peak = max(peak, abs(min(samples)), abs(max(samples)))
            total_square += sum(x * x for x in samples)
            nonzero += sum(x != 0 for x in samples)
            count += len(samples)
    if carry or not count:
        raise ValueError("Incomplete or empty decoded PCM")
    rms = math.sqrt(total_square / count)
    return {"samples": count, "duration_seconds": count / SAMPLE_RATE, "sample_rate": SAMPLE_RATE,
            "peak_amplitude": peak, "peak_dbfs": 20 * math.log10(peak / 32768) if peak else None,
            "rms_dbfs": 20 * math.log10(rms / 32768) if rms else None,
            "nonzero_samples": nonzero, "full_scale_peak": peak >= 32767}


def wav_stats(path: Path) -> dict:
    with wave.open(str(path), "rb") as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, SAMPLE_RATE):
            raise ValueError("Expected mono 24kHz s16 WAV for audio analysis")
        return pcm_stats(iter(lambda: audio.readframes(32768), b""))


def normalized_narration(args: argparse.Namespace) -> tuple[Path, dict]:
    source, target = args.outdir / "narration.wav", args.outdir / "narration_normalized.wav"
    analysis = run([args.ffmpeg, "-hide_banner", "-threads", "2", "-i", str(source), "-vn", "-af",
                    "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                   args.outdir / "logs/loudnorm_analysis.log")
    match = re.findall(r'\{\s*"input_i".*?\}', analysis, re.S)
    if not match:
        raise ValueError("No measured loudnorm analysis; refusing unmeasured normalization")
    measured = json.loads(match[-1])
    keys = ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")
    if any(not math.isfinite(float(measured[k])) for k in keys):
        raise ValueError("Narration loudness is invalid or silent")
    filt = ("loudnorm=I=-16:TP=-1.5:LRA=11:linear=true:print_format=json"
            f":measured_I={measured['input_i']}:measured_TP={measured['input_tp']}"
            f":measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}"
            f":offset={measured['target_offset']},apad=whole_dur={DURATION}")
    run([args.ffmpeg, "-y", "-hide_banner", "-threads", "2", "-i", str(source), "-vn", "-af", filt,
         "-t", str(DURATION), "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le", str(target)],
        args.outdir / "logs/loudnorm_apply.log")
    return target, {"method": "separate two-pass measured loudnorm", "target_i_lufs": -16,
                    "target_true_peak_dbfs": -1.5, "target_lra": 11,
                    "analysis": measured, "normalized_pcm": wav_stats(target)}


def metadata_text(route: dict, narration: dict) -> str:
    def escape(text: str) -> str:
        return text.replace("\\", "\\\\").replace("=", "\\=").replace(";", "\\;").replace("#", "\\#").replace("\n", " ")
    lines = [";FFMETADATA1", "title=Living Town: actual game walkthrough",
             "comment=Actual Main/LifeMode recording; architectural inspection sections are explicitly labelled."]
    for chapter in route["chapters"]:
        title = next(s["title"] for s in narration["segments"] if s["chapter"] == chapter["index"])
        lines += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={round(chapter['start_seconds'] * 1000)}",
                  f"END={round(chapter['end_seconds'] * 1000)}", "title=" + escape(title)]
    return "\n".join(lines) + "\n"


def theora_repeat_timeline(packets: list[dict]) -> dict:
    if not packets or int(packets[0].get("size", 0)) <= 0:
        raise ValueError("Theora timeline must begin with an actual picture")
    for index, packet in enumerate(packets):
        if (packet.get("pts") != index or packet.get("duration") != 1 or
                int(packet.get("size", -1)) < 0):
            raise ValueError("Theora packet timeline is not contiguous at 24 FPS")
    trailing = 0
    for packet in reversed(packets):
        if int(packet["size"]) != 0:
            break
        trailing += 1
    return {"packet_count": len(packets), "repeat_packets": sum(int(p["size"]) == 0 for p in packets),
            "trailing_repeat_packets": trailing, "contiguous_packet_pts_verified": True,
            "repeat_semantics": "Zero-byte Theora packets repeat the previous picture; only the proven trailing repeat count is padded after FPS reconstruction."}


def movie_timeline_trim(boot_frames: int, frame_count: int = FRAME_COUNT,
                        trailing_repeats: int = 0) -> str:
    # Theora can omit repeated decoded pictures while preserving their PTS.
    # Restore MovieWriter's 24-FPS timeline before counting its boot frames.
    tail = f",tpad=stop_mode=clone:stop={trailing_repeats}" if trailing_repeats else ""
    return (f"fps=24:start_time=0{tail},trim=start_frame={boot_frames}:"
            f"end_frame={boot_frames + frame_count},setpts=PTS-STARTPTS")


def phase_compose(args: argparse.Namespace) -> dict:
    narration, route, _ = load_plan(args)
    capture, offset = capture_contract(args)
    voice = load_json(args.outdir / "voice_report.json")
    if voice.get("status") != "PASS" or voice["narration"]["sha256"] != sha(args.narration) or voice["route"]["sha256"] != sha(args.route):
        raise ValueError("Voice phase is missing or stale; regenerate it")
    for name, record in voice["assets"].items():
        check_binding(record, name)
    if args.raw.suffix.lower() != ".avi":
        raise ValueError("Upgraded gameplay accepts the actual Godot AVI recording only")
    raw_info = probe(args.raw, args.ffprobe, count_frames=True)
    video = stream_of(raw_info, "video")
    if not video or (video.get("width"), video.get("height")) != (1280, 768):
        raise ValueError("Raw game capture must retain the complete1280x768HUD frame")
    rate = video.get("avg_frame_rate", video.get("r_frame_rate", "0/1"))
    num, den = (int(x) for x in rate.split("/"))
    decoded = int(video.get("nb_read_frames", 0))
    if den == 0 or abs(num / den - FPS) > 0.001 or decoded < offset + FRAME_COUNT:
        raise ValueError("AVI is missing actual18FPS boot/route frames; no synthetic padding is allowed")
    timeline = {"format":"Godot AVI", "decoded_frames":decoded, "required_frames":offset+FRAME_COUNT,
                "padding_frames":0, "repeated_or_invented_frames":False,
                "trim_policy":"Exact recorded frame range, with original PTS; no FPS reconstruction or tpad"}
    normalized, loudness = normalized_narration(args)
    bed = args.outdir / "game_bed.wav"
    bed_stats = None
    audible = False
    if stream_of(raw_info, "audio"):
        run([args.ffmpeg, "-y", "-hide_banner", "-v", "error", "-threads", "2", "-i", str(args.raw), "-vn",
             "-af", f"atrim=start={offset / FPS:.9f}:duration={DURATION},asetpts=PTS-STARTPTS,apad=whole_dur={DURATION}",
             "-t", str(DURATION), "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le", str(bed)],
            args.outdir / "logs/game_bed_decode.log")
        bed_stats = wav_stats(bed)
        audible = ((bed_stats["rms_dbfs"] is not None and bed_stats["rms_dbfs"] > -75) or
                   (bed_stats["peak_dbfs"] is not None and bed_stats["peak_dbfs"] > -55))
    metadata = args.outdir / "chapters.ffmetadata"
    metadata.write_text(metadata_text(route, narration), encoding="utf-8")
    filters = (f"[0:v]trim=start_frame={offset}:end_frame={offset + FRAME_COUNT},setpts=PTS-STARTPTS,"
               "scale=1280:768:flags=lanczos:out_range=tv,pad=1280:864:0:0:color=0x111722,"
               "subtitles=filename=narration.ass[v]")
    command = [args.ffmpeg, "-y", "-hide_banner", "-threads", "2", "-i", str(args.raw), "-i", str(normalized)]
    if audible:
        command += ["-i", str(bed)]
        filters += (";[1:a]asplit=2[narr][key];[2:a]volume=0.35[bed];"
                    "[bed][key]sidechaincompress=threshold=0.025:ratio=8:attack=15:release=250[duck];"
                    "[narr][duck]amix=inputs=2:duration=first:normalize=0,"
                    "alimiter=limit=0.89:level=0:latency=1[a]")
    metadata_index = 3 if audible else 2
    command += ["-f", "ffmetadata", "-i", str(metadata), "-filter_complex", filters, "-map", "[v]",
                "-map", "[a]" if audible else "1:a:0", "-map_metadata", str(metadata_index),
                "-map_chapters", str(metadata_index), "-frames:v", str(FRAME_COUNT), "-t", str(DURATION),
                "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-color_range", "tv", "-threads:v", "6",
                "-filter_complex_threads", "2", "-c:a", "aac", "-b:a", "160k", "-ar", str(SAMPLE_RATE),
                "-movflags", "+faststart", str(args.output)]
    (args.outdir / "composition_filters.txt").write_text(filters + "\n", encoding="utf-8")
    run(command, args.outdir / "logs/compose.log", cwd=args.outdir)
    report = {"schema": "living_town.walkthrough.composition.v1", "status": "PASS", "generated_utc": utc(),
              "note": "Encoding completed; final verification and human visual/audio review are separate gates.",
              "raw": binding(args.raw), "capture_report": binding(args.report), "voice_report": binding(args.outdir / "voice_report.json"),
              "narration": binding(args.narration), "route": binding(args.route), "builder": binding(Path(__file__)),
              "source_glb_sha256": capture["source_glb_sha256"], "source_blend_sha256": capture.get("source_blend_sha256"),
              "projection_sha256": capture["projection_sha256"], "movie_boot_frames_to_trim": offset,
              "trim_seconds": offset / FPS, "target_frames": FRAME_COUNT, "target_seconds": DURATION,
              "raw_video_timeline": timeline,
              "audio_mode": "narration_plus_actual_game_bed" if audible else "narration_only_raw_capture_silent_or_has_no_audio",
              "game_bed_stats": bed_stats, "game_bed_audibility_thresholds": {"rms_dbfs_above": -75, "or_peak_dbfs_above": -55},
              "invented_music_or_sounds": False, "loudness": loudness, "command": command,
              "assets": {p.name: binding(p) for p in (normalized, metadata, args.outdir / "composition_filters.txt",
                                                     args.outdir / "narration.ass", args.outdir / "narration.srt", args.outdir / "captions.json")},
              "output": binding(args.output), "visually_reviewed": False, "listened_to_by_human": False}
    write_json(args.outdir / "composition_report.json", report)
    return report


def decoded_audio_stats(args: argparse.Namespace) -> dict:
    command = [args.ffmpeg, "-hide_banner", "-v", "error", "-threads", "2", "-i", str(args.output), "-vn",
               "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le", "-f", "s16le", "pipe:1"]
    with (args.outdir / "logs/final_audio_decode.log").open("wb") as error:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=error) as process:
            stats = pcm_stats(iter(lambda: process.stdout.read(65536), b""))
            if process.wait(timeout=60):
                raise RuntimeError("Final audio decode failed")
    return stats


def qa_images(args: argparse.Namespace, route: dict) -> dict:
    folder = args.outdir / "qa"
    folder.mkdir(exist_ok=True)
    samples = []
    for chapter in route["chapters"]:
        when = (chapter["start_seconds"] + chapter["end_seconds"]) / 2
        output = folder / f"chapter_{chapter['index']:02}.png"
        run([args.ffmpeg, "-y", "-hide_banner", "-v", "error", "-threads", "2", "-ss", str(when),
             "-i", str(args.output), "-frames:v", "1", "-an", "-threads:v", "2", str(output)],
            args.outdir / "logs" / f"qa_chapter_{chapter['index']:02}.log")
        samples.append({"chapter": chapter["index"], "seconds": when, "image": binding(output)})
    sheet = folder / "contact_sheet.png"
    run([args.ffmpeg, "-y", "-hide_banner", "-v", "error", "-threads", "2", "-framerate", "1",
         "-start_number", "1", "-i", str(folder / "chapter_%02d.png"), "-vf", "scale=320:216,tile=4x3",
         "-frames:v", "1", "-threads:v", "2", str(sheet)], args.outdir / "logs/qa_contact.log")
    return {"samples": samples, "contact_sheet": binding(sheet), "visually_reviewed": False,
            "note": "Actual encoded MP4 frames for human inspection; generation does not constitute visual acceptance."}


def phase_verify(args: argparse.Namespace) -> dict:
    narration, route, _ = load_plan(args)
    capture, _ = capture_contract(args)
    composition = load_json(args.outdir / "composition_report.json")
    if composition.get("status") != "PASS":
        raise ValueError("Composition did not complete")
    for name in ("raw", "capture_report", "voice_report", "narration", "route", "builder", "output"):
        check_binding(composition[name], name)
    if Path(composition["output"]["path"]).resolve() != args.output:
        raise ValueError("Verification output differs from composed output")
    for name, record in composition["assets"].items():
        check_binding(record, name)
    info = probe(args.output, args.ffprobe, count_frames=True)
    video, audio = stream_of(info, "video"), stream_of(info, "audio")
    checks = []
    def check(name: str, passed: bool, details: object = None) -> None:
        checks.append({"name": name, "passed": bool(passed), "details": details})
    check("duration_840_seconds", abs(media_duration(info) - DURATION) <= 0.1, media_duration(info))
    check("video_H264_yuv420p_1280x864", bool(video) and video.get("codec_name") == "h264" and
          video.get("pix_fmt") == "yuv420p" and (video.get("width"), video.get("height")) == (1280, 864))
    rate = video.get("avg_frame_rate", "0/1") if video else "0/1"
    num, den = (int(x) for x in rate.split("/"))
    check("video_18_fps", den != 0 and abs(num / den - FPS) < 0.00001, rate)
    check("video_15120_decoded_frames", bool(video) and int(video.get("nb_read_frames", 0)) == FRAME_COUNT,
          video.get("nb_read_frames") if video else None)
    check("AAC_audio_present", bool(audio) and audio.get("codec_name") == "aac")
    chapters = info.get("chapters", [])
    expected = route["chapters"]
    chapter_ok = len(chapters) == 12
    if chapter_ok:
        for actual, planned in zip(chapters, expected):
            title = next(s["title"] for s in narration["segments"] if s["chapter"] == planned["index"])
            chapter_ok &= (abs(float(actual["start_time"]) - planned["start_seconds"]) <= 0.02 and
                           abs(float(actual["end_time"]) - planned["end_seconds"]) <= 0.02 and
                           actual.get("tags", {}).get("title") == title)
    check("twelve_chapters_cover_840_seconds", chapter_ok, chapters)
    captions = load_json(args.outdir / "captions.json").get("cues", [])
    cue_ok, prior = bool(captions), 0.0
    for cue in captions:
        cue_ok &= (prior <= cue["start"] < cue["end"] <= DURATION and 1 <= len(cue["lines"]) <= 2 and
                   all(len(line) <= 54 for line in cue["lines"]) and len(" ".join(cue["lines"])) <= 90)
        prior = cue["end"]
    check("measured_caption_sidecars_valid", cue_ok and all((args.outdir / name).stat().st_size > 100
          for name in ("narration.ass", "narration.srt")), len(captions))
    decode_log = args.outdir / "logs/full_decode.log"
    run([args.ffmpeg, "-hide_banner", "-v", "error", "-xerror", "-err_detect", "explode", "-threads", "2",
         "-i", str(args.output), "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-"], decode_log)
    # run() writes the argv on the first line; any further error-level text fails acceptance.
    errors = decode_log.read_text(encoding="utf-8", errors="replace").splitlines()[1:]
    check("full_video_audio_decode_no_errors", not any(line.strip() for line in errors), errors[-20:])
    audio_stats = decoded_audio_stats(args)
    check("decoded_audio_duration", abs(audio_stats["duration_seconds"] - DURATION) <= 0.1, audio_stats["duration_seconds"])
    check("decoded_audio_not_silent", audio_stats["rms_dbfs"] is not None and audio_stats["rms_dbfs"] > -45 and
          audio_stats["peak_dbfs"] is not None and audio_stats["peak_dbfs"] > -35, audio_stats)
    check("decoded_audio_no_fullscale_peak", not audio_stats["full_scale_peak"], audio_stats["peak_amplitude"])
    check("current_source_bound_capture", capture["source_glb_sha256"] == composition["source_glb_sha256"] and
          capture["projection_sha256"] == composition["projection_sha256"])
    check("actual_game_audio_or_honest_narration_only", not composition.get("invented_music_or_sounds", True), composition["audio_mode"])
    pictures = {} if args.no_qa_images else qa_images(args, route)
    report = {"schema": "living_town.walkthrough.verification.v1", "generated_utc": utc(),
              "status": "PASS" if all(c["passed"] for c in checks) else "FAIL", "checks": checks,
              "passed": sum(c["passed"] for c in checks), "failed": sum(not c["passed"] for c in checks),
              "output": binding(args.output), "composition_report": binding(args.outdir / "composition_report.json"),
              "capture_report": binding(args.report), "voice_report": binding(args.outdir / "voice_report.json"),
              "narration": binding(args.narration), "route": binding(args.route), "builder": binding(Path(__file__)),
              "source_glb_sha256": composition["source_glb_sha256"], "source_blend_sha256": composition.get("source_blend_sha256"),
              "projection_sha256": composition["projection_sha256"], "probe": info, "decoded_audio": audio_stats,
              "qa_images": pictures, "visually_reviewed": False, "listened_to_by_human": False,
              "human_review_required": "Inspect actual chapter frames and playback, read captions against HUD, listen for clarity/sync, and reconcile actual gameplay outcomes. Technical PASS does not establish visual/audio acceptance."}
    write_json(args.outdir / "verification_report.json", report)
    if report["status"] != "PASS":
        raise ValueError(f"Final technical verification failed {report['failed']} checks; see verification_report.json")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="phase", required=True)
    for phase in ("voice", "compose", "verify"):
        child = sub.add_parser(phase, help={"voice": "Generate/cache measured Edge TTS and captions",
                                          "compose": "Trim real capture, normalize/mix audio, encode MP4",
                                          "verify": "Decode/hash/check MP4 and extract human QA frames"}[phase])
        child.add_argument("--outdir", type=Path, default=ROOT / "build/town_walkthrough/full")
        child.add_argument("--raw", type=Path, default=ROOT / "build/town_walkthrough/full/capture.avi")
        child.add_argument("--report", type=Path, default=ROOT / "build/town_walkthrough/full/walkthrough_report.json")
        child.add_argument("--output", type=Path, default=Path("LivingTown_Walkthrough.mp4"))
        child.add_argument("--narration", type=Path, default=ROOT / "docs/town_walkthrough/narration.json")
        child.add_argument("--route", type=Path, default=ROOT / "docs/town_walkthrough/route_plan.json")
        child.add_argument("--ffmpeg", default="ffmpeg")
        child.add_argument("--ffprobe", default="ffprobe")
        child.add_argument("--edge-deps", type=Path, default=ROOT / "build/town_walkthrough/python_deps")
        child.add_argument("--endpoint", choices=("migrated", "installed"), default="migrated")
        child.add_argument("--respect-proxy", action="store_true", help="Use existing proxy environment for TTS; default is direct")
        child.add_argument("--refresh-voice", action="store_true", help="Regenerate rather than reuse hash-checked voice cache")
        child.add_argument("--no-qa-images", action="store_true", help="Verify without optional sample/contact extraction")
    args = parser.parse_args()
    for name in ("outdir", "raw", "report", "narration", "route", "edge_deps"):
        setattr(args, name, getattr(args, name).resolve())
    args.output = (args.output if args.output.is_absolute() else args.outdir / args.output).resolve()
    args.ffmpeg, args.ffprobe = tool(args.ffmpeg), tool(args.ffprobe)
    if args.output in (args.raw, args.report, args.narration, args.route) or args.output.suffix.lower() != ".mp4":
        parser.error("--output must be a distinct .mp4 path")
    return args


def main() -> int:
    args = parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    (args.outdir / "logs").mkdir(exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    try:
        result = {"voice": phase_voice, "compose": phase_compose, "verify": phase_verify}[args.phase](args)
        print(json.dumps({"phase": args.phase, "status": result["status"], "elapsed_seconds": round(time.monotonic() - started, 2),
                          "outdir": str(args.outdir), "output": str(args.output) if args.phase != "voice" else None}))
        return 0
    except Exception as exc:
        write_json(args.outdir / f"{args.phase}_failure.json", {"phase": args.phase, "status": "FAIL", "generated_utc": utc(),
                   "error": str(exc), "elapsed_seconds": round(time.monotonic() - started, 2), "builder": binding(Path(__file__))})
        print(f"{args.phase.upper()} FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
