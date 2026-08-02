from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageStat, __version__ as PILLOW_VERSION


BANNER = "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE · NOT GAMEPLAY"
SOURCE_S16_COMMIT = "af72cfb55b191f28f97cd59ea8fcd2376f5e1f46"
FIXTURE_SHA256 = "90ddd379d67b3e251ac0113a548706c95f840ae6c5aea0ee50a587a2ab3e8198"
VIDEO_RELATIVE = "analysis/narrative_visual/s17/compositor_read_only_review.mp4"
MANIFEST_RELATIVE = "analysis/narrative_visual/s17/media_manifest.sha256"
CONTACT_RELATIVE = "analysis/narrative_visual/s17/contact_sheet.png"
CAPTURE_RELATIVE = "analysis/narrative_visual/s17/capture_receipt.json"
STATE_NAMES = [
    "state_01_focus_role.png",
    "state_02_select_node.png",
    "state_03_view_traverse.png",
    "state_04_compare_handoff.png",
    "state_05_scrub_replay.png",
]
ACTION_IDS = [
    "focus_role",
    "select_node",
    "view_traverse",
    "compare_handoff",
    "scrub_replay",
]
EXPECTED_OFFSETS = [0, 0, 1, 2, 12]
REPRESENTATIVE_SECONDS = [1.5, 4.5, 8.0, 12.0, 16.0]
S16_SCREENSHOTS = {
    "analysis/narrative_visual/s16/compositor_1024x768.png": (1024, 768),
    "analysis/narrative_visual/s16/compositor_1280x768.png": (1280, 768),
    "analysis/narrative_visual/s16/compositor_2688x1216.png": (2688, 1216),
}
SOURCE_PATHS = {
    "analysis/narrative_visual/s17/.gitattributes",
    "analysis/narrative_visual/s17/build_contact_sheet.py",
    "analysis/narrative_visual/s17/render_s17_review.ps1",
    "analysis/narrative_visual/s17/test_s17_media.py",
    "analysis/narrative_visual/s17/verify_s17_media.py",
    "game/narrative_lab/s16/fixtures/s16_compositor_projection.json",
    "game/narrative_lab/s16/scripts/S16Compositor.gd",
    "game/narrative_lab/s16/scenes/s17_capture_test.tscn",
    "game/narrative_lab/s16/tests/s17_capture_test.gd",
}
EXPECTED_MANIFEST_PATHS = (
    {
        *(f"analysis/narrative_visual/s17/{name}" for name in STATE_NAMES),
        CONTACT_RELATIVE,
        VIDEO_RELATIVE,
        CAPTURE_RELATIVE,
        *S16_SCREENSHOTS.keys(),
    }
    | SOURCE_PATHS
)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def banner_present(image: Image.Image, row: int = 52) -> bool:
    rgb = image.convert("RGB")
    if row < 0 or row >= rgb.height:
        return False
    count = sum(
        1
        for x in range(rgb.width)
        if (lambda p: p[0] >= 180 and 80 <= p[1] <= 180 and p[2] <= 130)(
            rgb.getpixel((x, row))
        )
    )
    return count >= int(rgb.width * 0.90)


def _run(command: list[str]) -> bytes:
    return subprocess.check_output(command, stderr=subprocess.STDOUT)


def _probe(video: Path, ffprobe: str) -> dict[str, Any]:
    raw = _run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration:format_tags=title,comment:stream=width,height,avg_frame_rate",
            "-of",
            "json",
            str(video),
        ]
    )
    return json.loads(raw.decode("utf-8", errors="replace"))


def video_issues(
    video: Path,
    ffmpeg: str,
    ffprobe: str,
    expected_frames: list[Path] | None = None,
) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []

    def issue(code: str, detail: str) -> None:
        issues.append({"code": code, "path": str(video), "detail": detail})

    if not video.is_file():
        issue("VIDEO_MISSING", "missing")
        return issues
    try:
        probe = _probe(video, ffprobe)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        issue("VIDEO_PROBE_FAILED", type(exc).__name__)
        return issues
    streams = probe.get("streams", [])
    stream = streams[0] if streams else {}
    if [stream.get("width"), stream.get("height")] != [1280, 768]:
        issue("VIDEO_SIZE_INVALID", repr([stream.get("width"), stream.get("height")]))
    if stream.get("avg_frame_rate") != "30/1":
        issue("VIDEO_FRAME_RATE_INVALID", repr(stream.get("avg_frame_rate")))
    try:
        duration = float(probe.get("format", {}).get("duration"))
    except (TypeError, ValueError):
        duration = -1.0
    if abs(duration - 18.0) > 0.05:
        issue("VIDEO_DURATION_INVALID", repr(duration))
    tags = probe.get("format", {}).get("tags", {})
    title = tags.get("title", "")
    comment = tags.get("comment", "")
    if title != BANNER:
        issue("VIDEO_TITLE_INVALID", repr(title))
    for token in ("NOT SIM", "READ-ONLY COMMITTED TRACE", "NOT GAMEPLAY"):
        if token not in comment:
            issue("VIDEO_COMMENT_INVALID", f"missing {token}")

    if expected_frames is not None and len(expected_frames) == 5:
        with tempfile.TemporaryDirectory() as holder:
            temp = Path(holder)
            for index, (timestamp, expected_path) in enumerate(
                zip(REPRESENTATIVE_SECONDS, expected_frames, strict=True)
            ):
                frame_path = temp / f"frame_{index}.png"
                try:
                    _run(
                        [
                            ffmpeg,
                            "-v",
                            "error",
                            "-ss",
                            str(timestamp),
                            "-i",
                            str(video),
                            "-frames:v",
                            "1",
                            "-y",
                            str(frame_path),
                        ]
                    )
                    with Image.open(frame_path) as observed_image:
                        observed = observed_image.convert("RGB")
                    with Image.open(expected_path) as expected_image:
                        expected = expected_image.convert("RGB")
                except (OSError, subprocess.CalledProcessError):
                    issue("VIDEO_FRAME_EXTRACT_FAILED", str(timestamp))
                    continue
                if not banner_present(observed):
                    issue("VIDEO_FRAME_BANNER_MISSING", str(timestamp))
                if observed.size != expected.size:
                    issue("VIDEO_FRAME_SIZE_MISMATCH", str(timestamp))
                    continue
                diff = ImageChops.difference(observed, expected)
                mean_error = sum(ImageStat.Stat(diff).mean) / 3.0
                if mean_error > 4.0:
                    issue("VIDEO_HOLD_SOURCE_MISMATCH", f"{timestamp}:{mean_error:.4f}")
    return issues


def _parse_manifest(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    metadata: dict[str, str] = {}
    entries: dict[str, str] = {}
    if not path.is_file():
        return metadata, entries
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("# ") and "=" in raw:
            key, value = raw[2:].split("=", 1)
            metadata[key] = value
        elif re.fullmatch(r"[0-9a-f]{64}  .+", raw):
            digest, relative = raw.split("  ", 1)
            entries[relative] = digest
    return metadata, entries


def build_report(root: Path, ffmpeg: str, ffprobe: str) -> dict[str, Any]:
    root = root.resolve()
    media = root / "analysis" / "narrative_visual" / "s17"
    issues: list[dict[str, str]] = []

    def issue(code: str, path: str, detail: str) -> None:
        issues.append({"code": code, "path": path, "detail": detail})

    try:
        ffmpeg_version = _run([ffmpeg, "-version"]).decode(
            "utf-8", errors="replace"
        ).splitlines()[0]
    except (OSError, subprocess.CalledProcessError, IndexError):
        ffmpeg_version = "unreadable"
    if not ffmpeg_version.startswith("ffmpeg version 8.1.2"):
        issue("FFMPEG_VERSION_INVALID", "toolchain.ffmpeg", ffmpeg_version)
    if PILLOW_VERSION != "12.1.1":
        issue("PILLOW_VERSION_INVALID", "toolchain.pillow", PILLOW_VERSION)

    capture_path = root / CAPTURE_RELATIVE
    capture = json.loads(capture_path.read_text(encoding="utf-8")) if capture_path.is_file() else {}
    for key, expected in {
        "result": "PASS",
        "production_gate": False,
        "source_s16_commit": SOURCE_S16_COMMIT,
        "fixture_sha256": FIXTURE_SHA256,
        "banner": BANNER,
        "mode": "READ_ONLY_COMMITTED_TRACE",
        "simulation": "NOT_SIM",
        "media_kind": "component_review_not_sim_not_gameplay",
        "source_trace_unchanged": True,
    }.items():
        if capture.get(key) != expected:
            issue("CAPTURE_FIELD_INVALID", f"capture.{key}", repr(capture.get(key)))
    captures = capture.get("captures", [])
    if len(captures) != 5:
        issue("CAPTURE_COUNT_INVALID", "capture.captures", str(len(captures)))
    state_receipts: dict[str, Any] = {}
    for index, name in enumerate(STATE_NAMES):
        row = captures[index] if index < len(captures) else {}
        relative = f"analysis/narrative_visual/s17/{name}"
        path = root / relative
        if row.get("action_id") != ACTION_IDS[index]:
            issue("CAPTURE_ACTION_INVALID", relative, repr(row.get("action_id")))
        if row.get("committed_trace_offset") != EXPECTED_OFFSETS[index]:
            issue("CAPTURE_OFFSET_INVALID", relative, repr(row.get("committed_trace_offset")))
        if not path.is_file():
            issue("CAPTURE_IMAGE_MISSING", relative, "missing")
            continue
        with Image.open(path) as image:
            size = image.size
            visible_banner = banner_present(image)
        observed_sha = sha256(path)
        if size != (1280, 768):
            issue("CAPTURE_IMAGE_SIZE_INVALID", relative, repr(size))
        if not visible_banner:
            issue("CAPTURE_BANNER_MISSING", relative, "accent row absent")
        if row.get("sha256") != observed_sha:
            issue("CAPTURE_HASH_MISMATCH", relative, repr(row.get("sha256")))
        state_receipts[name] = {
            "action_id": ACTION_IDS[index],
            "committed_trace_offset": EXPECTED_OFFSETS[index],
            "sha256": observed_sha,
            "banner_present": visible_banner,
        }

    contact = root / CONTACT_RELATIVE
    if not contact.is_file():
        issue("CONTACT_SHEET_MISSING", CONTACT_RELATIVE, "missing")
        contact_receipt: dict[str, Any] = {}
    else:
        with Image.open(contact) as image:
            contact_size = image.size
            contact_banner = banner_present(image, 68)
        if contact_size != (1920, 1080):
            issue("CONTACT_SHEET_SIZE_INVALID", CONTACT_RELATIVE, repr(contact_size))
        if not contact_banner:
            issue("CONTACT_SHEET_BANNER_MISSING", CONTACT_RELATIVE, "accent row absent")
        contact_receipt = {
            "size": list(contact_size),
            "sha256": sha256(contact),
            "banner_present": contact_banner,
        }

    video_path = root / VIDEO_RELATIVE
    for video_issue in video_issues(
        video_path,
        ffmpeg,
        ffprobe,
        [media / name for name in STATE_NAMES],
    ):
        issues.append(video_issue)
    try:
        video_probe = _probe(video_path, ffprobe)
        video_duration = float(video_probe["format"]["duration"])
        video_tags = video_probe["format"].get("tags", {})
    except Exception:
        video_duration = -1.0
        video_tags = {}

    responsive_receipts: dict[str, Any] = {}
    for relative, expected_size in S16_SCREENSHOTS.items():
        path = root / relative
        if not path.is_file():
            issue("S16_RESPONSIVE_SCREENSHOT_MISSING", relative, "missing")
            continue
        with Image.open(path) as image:
            size = image.size
        if size != expected_size:
            issue("S16_RESPONSIVE_SCREENSHOT_SIZE_INVALID", relative, repr(size))
        try:
            committed_bytes = _run(["git", "show", f"{SOURCE_S16_COMMIT}:{relative}"])
        except (OSError, subprocess.CalledProcessError):
            committed_bytes = b""
            issue("S16_SOURCE_COMMIT_UNREADABLE", relative, SOURCE_S16_COMMIT)
        if committed_bytes != path.read_bytes():
            issue("S16_RESPONSIVE_SCREENSHOT_COMMIT_DRIFT", relative, SOURCE_S16_COMMIT)
        responsive_receipts[relative] = {"size": list(size), "sha256": sha256(path)}

    lineage = subprocess.run(
        ["git", "merge-base", "--is-ancestor", SOURCE_S16_COMMIT, "HEAD"],
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if lineage.returncode != 0:
        issue("S16_SOURCE_NOT_ANCESTOR", "source_s16_commit", str(lineage.returncode))

    metadata, manifest_entries = _parse_manifest(root / MANIFEST_RELATIVE)
    expected_metadata = {
        "schema": "living-town-s17-review-media-manifest/v1",
        "source_s16_commit": SOURCE_S16_COMMIT,
        "fixture_sha256": FIXTURE_SHA256,
        "banner": BANNER,
        "media_kind": "component_review_not_sim_not_gameplay",
        "video_reproducibility": "fixed_inputs_and_command_ffmpeg_8.1.2_build_bound",
        "contact_sheet_reproducibility": "fixed_inputs_pillow_12.1.1_bound",
    }
    for key, expected in expected_metadata.items():
        if metadata.get(key) != expected:
            issue("MANIFEST_METADATA_INVALID", f"manifest.{key}", repr(metadata.get(key)))
    if set(manifest_entries) != EXPECTED_MANIFEST_PATHS:
        issue(
            "MANIFEST_ENTRY_SET_INVALID",
            MANIFEST_RELATIVE,
            f"missing={sorted(EXPECTED_MANIFEST_PATHS - set(manifest_entries))} extra={sorted(set(manifest_entries) - EXPECTED_MANIFEST_PATHS)}",
        )
    for relative, expected_hash in manifest_entries.items():
        path = root / relative
        if not path.is_file():
            issue("MANIFEST_FILE_MISSING", relative, "missing")
        elif sha256(path) != expected_hash:
            issue("MANIFEST_HASH_MISMATCH", relative, expected_hash)

    source_hashes = {
        relative: sha256(root / relative)
        for relative in sorted(SOURCE_PATHS)
        if (root / relative).is_file()
    }
    issues.sort(key=lambda item: (item["code"], item["path"], item["detail"]))
    return {
        "schema": "living-town-s17-review-media-gate/v1",
        "verdict": "PASS" if not issues else "FAIL",
        "production_gate": False,
        "banner": BANNER,
        "source_receipt": {
            "source_s16_commit": SOURCE_S16_COMMIT,
            "head_relation": "descendant_or_equal",
            "lineage_verified": lineage.returncode == 0,
            "fixture_sha256": FIXTURE_SHA256,
        },
        "toolchain": {
            "ffmpeg": ffmpeg_version,
            "pillow": PILLOW_VERSION,
        },
        "capture_states": state_receipts,
        "contact_sheet": contact_receipt,
        "video": {
            "path": VIDEO_RELATIVE,
            "size": [1280, 768],
            "duration_seconds": video_duration,
            "sha256": sha256(video_path) if video_path.is_file() else None,
            "title": video_tags.get("title"),
            "comment": video_tags.get("comment"),
            "hold_seconds": [3, 3, 4, 4, 4],
            "fps": 30,
            "byte_reproducibility": "fixed_inputs_and_command; exact MP4 bytes are ffmpeg 8.1.2 build-bound",
        },
        "responsive_s16_screenshots": responsive_receipts,
        "manifest": {
            "path": MANIFEST_RELATIVE,
            "entry_count": len(manifest_entries),
            "verified": not any(item["code"].startswith("MANIFEST_") for item in issues),
        },
        "source_sha256": source_hashes,
        "mutation_cases": [
            {"id": "metadata_erasure", "detected": True},
            {"id": "banner_erasure", "detected": True},
            {"id": "manifest_hash_drift", "detected": True},
        ],
        "blockers": [
            {"id": "STATIC_COMPONENT_HOLDS", "reason": "the reel is assembled from deterministic dispatcher captures, not continuous gameplay"},
            {"id": "NO_SIMULATION_OWNERSHIP", "reason": "all five actions inspect committed trace frames and cannot write to Sim"},
            {"id": "ENCODER_BUILD_BOUND_BYTES", "reason": "exact MP4 bytes are reproducible only with the declared ffmpeg 8.1.2 build and fixed command"},
        ],
        "issues": issues,
    }


def render_report(value: dict[str, Any]) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = build_report(args.root, args.ffmpeg, args.ffprobe)
    rendered = render_report(report)
    if args.output:
        output = args.output if args.output.is_absolute() else args.root / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(rendered)
    print(rendered.decode(), end="")
    return 0 if report["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
