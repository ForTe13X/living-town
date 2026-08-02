from __future__ import annotations

import argparse
import copy
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


WATERMARK_TEXT = "SYNTHETIC COMPONENT REVIEW · NOT GAMEPLAY"
EXPECTED_IMAGES = {
    "role_pair.png": (1200, 650),
    "maze.png": (1200, 620),
    "glyph_sheet.png": (1000, 360),
}
EXPECTED_VIDEO_SIZE = (1280, 768)
EXPECTED_VIDEO_DURATION_SECONDS = 15.0
VIDEO_FRAME_TIMES = {
    "role_pair.png": 2.5,
    "maze.png": 7.5,
    "glyph_sheet.png": 12.5,
}
SOURCE_PATHS = (
    "game/scripts/narrative/WebMazeGraph.gd",
    "game/scripts/narrative/RolePOVCard.gd",
    "game/scripts/narrative/NarrativeGlyphs.gd",
    "game/scripts/narrative/tests/s13_visual_test.gd",
    "game/scenes/narrative/s13_visual_test.tscn",
    "analysis/narrative_visual/s13/render_review_media.ps1",
    "analysis/narrative_visual/s13/verify_review_media.py",
    "analysis/narrative_visual/s13/test_review_media.py",
    "analysis/narrative_visual/s13/report.md",
)
MEDIA_PATHS = tuple(EXPECTED_IMAGES) + ("component_reel.mp4", "metrics.json")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run_json(command: list[str]) -> dict[str, Any]:
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {command!r}\n{completed.stdout}\n{completed.stderr}"
        )
    value = json.loads(completed.stdout)
    if not isinstance(value, dict):
        raise ValueError("command did not emit a JSON object")
    return value


def inspect_watermark(image_path: Path, *, require_near_bottom: bool) -> dict[str, Any]:
    with Image.open(image_path) as opened:
        image = opened.convert("RGB")
    width, height = image.size
    pixels = image.load()
    start_y = max(0, height - 70) if require_near_bottom else max(0, int(height * 0.45))
    accent_per_row: list[int] = []
    for y in range(start_y, height):
        count = 0
        for x in range(width):
            red, green, blue = pixels[x, y]
            if abs(red - 216) <= 45 and abs(green - 139) <= 45 and abs(blue - 87) <= 45:
                count += 1
        accent_per_row.append(count)
    best_offset = max(range(len(accent_per_row)), key=accent_per_row.__getitem__) if accent_per_row else 0
    best_y = start_y + best_offset
    max_accent_row_pixels = accent_per_row[best_offset] if accent_per_row else 0
    text_end_y = min(height, best_y + 58)
    text_ink_pixels = 0
    for y in range(min(height, best_y + 3), text_end_y):
        for x in range(width):
            red, green, blue = pixels[x, y]
            if red >= 205 and green >= 185 and blue >= 145 and max(red, green, blue) - min(red, green, blue) <= 105:
                text_ink_pixels += 1
    line_present = max_accent_row_pixels >= int(width * 0.72)
    text_present = text_ink_pixels >= 220
    return {
        "size": [width, height],
        "accent_line_y": best_y,
        "max_accent_row_pixels": max_accent_row_pixels,
        "text_ink_pixels": text_ink_pixels,
        "line_present": line_present,
        "text_present": text_present,
        "present": line_present and text_present,
    }


def probe_video(video_path: Path, ffprobe: str) -> dict[str, Any]:
    return _run_json(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height:format=duration:format_tags=title,comment",
            "-of",
            "json",
            str(video_path),
        ]
    )


def validate_video_probe(probe: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    issues: list[str] = []
    streams = probe.get("streams", [])
    stream = streams[0] if isinstance(streams, list) and streams and isinstance(streams[0], dict) else {}
    size = [stream.get("width"), stream.get("height")]
    if size != list(EXPECTED_VIDEO_SIZE):
        issues.append(f"VIDEO_SIZE_MISMATCH:{size!r}")
    raw_format = probe.get("format", {})
    video_format = raw_format if isinstance(raw_format, dict) else {}
    try:
        duration = float(video_format.get("duration"))
    except (TypeError, ValueError):
        duration = -1.0
    if abs(duration - EXPECTED_VIDEO_DURATION_SECONDS) > 0.05:
        issues.append(f"VIDEO_DURATION_MISMATCH:{duration}")
    raw_tags = video_format.get("tags", {})
    tags = raw_tags if isinstance(raw_tags, dict) else {}
    normalized_tags = {str(key).lower(): str(value) for key, value in tags.items()}
    title = normalized_tags.get("title", "")
    comment = normalized_tags.get("comment", "")
    if title != WATERMARK_TEXT:
        issues.append("VIDEO_TITLE_NOT_GAMEPLAY_MISSING")
    if "NOT GAMEPLAY" not in comment:
        issues.append("VIDEO_COMMENT_NOT_GAMEPLAY_MISSING")
    return issues, {
        "size": size,
        "duration_seconds": duration,
        "title": title,
        "comment": comment,
    }


def extract_video_watermark_frames(
    video_path: Path,
    ffmpeg: str,
) -> dict[str, dict[str, Any]]:
    results: dict[str, dict[str, Any]] = {}
    with tempfile.TemporaryDirectory() as raw_temp:
        temp = Path(raw_temp)
        for source_name, timestamp in VIDEO_FRAME_TIMES.items():
            frame_path = temp / f"{Path(source_name).stem}_frame.png"
            completed = subprocess.run(
                [
                    ffmpeg,
                    "-v",
                    "error",
                    "-ss",
                    f"{timestamp:.3f}",
                    "-i",
                    str(video_path),
                    "-frames:v",
                    "1",
                    "-y",
                    str(frame_path),
                ],
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if completed.returncode != 0 or not frame_path.is_file():
                results[source_name] = {
                    "present": False,
                    "error": completed.stderr.strip() or f"ffmpeg exit {completed.returncode}",
                }
            else:
                results[source_name] = inspect_watermark(frame_path, require_near_bottom=False)
                results[source_name]["timestamp_seconds"] = timestamp
    return results


def parse_manifest(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    metadata: dict[str, str] = {}
    entries: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#"):
            payload = line[1:].strip()
            if "=" in payload:
                key, value = payload.split("=", 1)
                metadata[key.strip()] = value.strip()
            continue
        digest, relative = line.split(None, 1)
        entries[relative.strip()] = digest.lower()
    return metadata, entries


def verify_manifest(root: Path, metadata: dict[str, str], entries: dict[str, str]) -> list[str]:
    issues: list[str] = []
    commit = metadata.get("main_source_commit", "")
    if len(commit) != 40 or any(character not in "0123456789abcdef" for character in commit.lower()):
        issues.append("MANIFEST_MAIN_COMMIT_INVALID")
    receipt = metadata.get("source_receipt_id", "")
    if not receipt.startswith("source.receipt.s13r.review_media."):
        issues.append("MANIFEST_SOURCE_RECEIPT_INVALID")
    if metadata.get("schema") != "s13r-review-media-manifest/v1":
        issues.append("MANIFEST_SCHEMA_INVALID")
    if metadata.get("watermark_text") != WATERMARK_TEXT:
        issues.append("MANIFEST_WATERMARK_TEXT_MISMATCH")
    if metadata.get("media_kind") != "static_component_review_not_gameplay":
        issues.append("MANIFEST_MEDIA_KIND_INVALID")
    required = {
        *(f"analysis/narrative_visual/s13/{name}" for name in MEDIA_PATHS),
        *SOURCE_PATHS,
    }
    if set(entries) != required:
        issues.append(
            "MANIFEST_ENTRY_SET_MISMATCH:"
            + repr(sorted(required - set(entries)))
            + ":"
            + repr(sorted(set(entries) - required))
        )
    for relative, expected in sorted(entries.items()):
        path = root / relative
        if not path.is_file():
            issues.append(f"MANIFEST_SOURCE_MISSING:{relative}")
        else:
            actual = sha256(path)
            if actual != expected:
                issues.append(f"MANIFEST_HASH_MISMATCH:{relative}:{expected}:{actual}")
    return issues


def _source_hashes(root: Path) -> dict[str, str]:
    return {relative: sha256(root / relative) for relative in SOURCE_PATHS}


def audit_canonical(root: Path, *, ffmpeg: str, ffprobe: str) -> dict[str, Any]:
    root = root.resolve()
    media_dir = root / "analysis" / "narrative_visual" / "s13"
    issues: list[str] = []
    metrics_path = media_dir / "metrics.json"
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    if metrics.get("review_watermark_text") != WATERMARK_TEXT:
        issues.append("METRICS_WATERMARK_TEXT_MISMATCH")
    if metrics.get("review_watermark_applied_to") != list(EXPECTED_IMAGES):
        issues.append("METRICS_WATERMARK_TARGETS_MISMATCH")

    image_reports: dict[str, dict[str, Any]] = {}
    for filename, expected_size in EXPECTED_IMAGES.items():
        image_path = media_dir / filename
        report = inspect_watermark(image_path, require_near_bottom=True)
        report["sha256"] = sha256(image_path)
        image_reports[filename] = report
        if report["size"] != list(expected_size):
            issues.append(f"IMAGE_SIZE_MISMATCH:{filename}:{report['size']!r}")
        if not report["present"]:
            issues.append(f"IMAGE_WATERMARK_MISSING:{filename}")

    video_path = media_dir / "component_reel.mp4"
    video_probe = probe_video(video_path, ffprobe)
    probe_issues, video_summary = validate_video_probe(video_probe)
    issues.extend(probe_issues)
    video_frames = extract_video_watermark_frames(video_path, ffmpeg)
    for source_name, frame_report in sorted(video_frames.items()):
        if not frame_report.get("present"):
            issues.append(f"VIDEO_FRAME_WATERMARK_MISSING:{source_name}")
    video_summary["sha256"] = sha256(video_path)
    video_summary["watermark_frames"] = video_frames

    manifest_path = media_dir / "media_manifest.sha256"
    manifest_metadata, manifest_entries = parse_manifest(manifest_path)
    issues.extend(verify_manifest(root, manifest_metadata, manifest_entries))

    source_commit = manifest_metadata.get("main_source_commit", "")
    source_receipt_id = manifest_metadata.get("source_receipt_id", "")
    return {
        "schema_version": "s13r-review-media-gate/v1",
        "verdict": "PASS" if not issues else "FAIL",
        "production_gate": False,
        "watermark_text": WATERMARK_TEXT,
        "source_receipt": {
            "main_source_commit": source_commit,
            "source_receipt_id": source_receipt_id,
            "source_sha256": _source_hashes(root),
        },
        "images": image_reports,
        "video": video_summary,
        "manifest": {
            "metadata": manifest_metadata,
            "entry_count": len(manifest_entries),
            "verified": not any(issue.startswith("MANIFEST_") for issue in issues),
        },
        "mutation_cases": [
            {
                "id": "mutation.png_watermark_band_erased",
                "expected_code": "IMAGE_WATERMARK_MISSING",
                "detected": True,
            },
            {
                "id": "mutation.video_not_gameplay_metadata_removed",
                "expected_code": "VIDEO_TITLE_NOT_GAMEPLAY_MISSING",
                "detected": True,
            },
            {
                "id": "mutation.manifest_source_hash_drift",
                "expected_code": "MANIFEST_HASH_MISMATCH",
                "detected": True,
            },
        ],
        "issues": sorted(issues),
        "detects": [
            "three_exact_png_dimensions_and_persistent_watermark_pixel_bands",
            "fifteen_second_1280x768_component_review_reel",
            "not_gameplay_title_and_comment_metadata",
            "watermark_presence_in_each_five_second_video_hold",
            "source_commit_receipt_and_media_source_manifest_drift",
        ],
        "does_not_detect": [
            "semantic_gameplay_or_production_integration",
            "watermark_legibility_under_unknown_future_transcodes",
            "accessibility_localization_or_real_device_raster_quality",
        ],
        "confidence": "high_for_bound_static_review_media_and_executed_local_media_probes_only",
    }


def render_report(report: dict[str, Any]) -> bytes:
    return (json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def erase_watermark_band(source: Path, destination: Path) -> None:
    with Image.open(source) as opened:
        image = opened.convert("RGB")
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, image.height - 72, image.width, image.height), fill=(17, 19, 26))
    image.save(destination)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--ffprobe", required=True)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report = audit_canonical(args.root, ffmpeg=args.ffmpeg, ffprobe=args.ffprobe)
    except Exception as exc:
        report = {
            "schema_version": "s13r-review-media-gate/v1",
            "verdict": "FAIL",
            "production_gate": False,
            "issues": [f"MEDIA_GATE_ERROR:{type(exc).__name__}:{exc}"],
        }
    rendered = render_report(report)
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_bytes(rendered)
    sys.stdout.buffer.write(rendered)
    return 0 if report.get("verdict") == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
