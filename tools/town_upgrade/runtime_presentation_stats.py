"""Measure captured display RGB; descriptive statistics never confer visual PASS."""
from io import BytesIO
from pathlib import Path
import argparse
import hashlib
import json
import sys

import numpy as np
from PIL import Image, __version__ as pillow_version


def sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def analyse(directory: Path) -> dict:
    directory = directory.resolve()
    output = directory / "clipping_histograms.json"
    if output.exists():
        raise FileExistsError("Preserve prior histogram evidence: " + str(output))
    report_path = directory / "calibration_report.json"
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes.decode("utf-8-sig"))
    if report.get("schema") != "living_town.runtime_presentation_calibration.v1":
        raise ValueError("Unsupported presentation calibration report")
    captures = report.get("captures", [])
    if not captures:
        raise ValueError("No raw SubViewport captures to measure")
    rows = []
    for capture in captures:
        source = capture["raw_subviewport"]
        path = Path(source["path"]).resolve()
        if not path.is_relative_to(directory):
            raise ValueError("Capture is outside its evidence directory: " + str(path))
        payload = path.read_bytes()
        digest = sha(payload)
        if digest != source["sha256"] or len(payload) != source["bytes"]:
            raise ValueError("Capture identity changed: " + str(path))
        # Decode the exact bytes whose identity was checked, not a second read.
        with Image.open(BytesIO(payload)) as image:
            if image.format != "PNG" or list(image.size) != capture["dimensions"]:
                raise ValueError("Capture format or dimensions changed: " + str(path))
            pixels = np.asarray(image.convert("RGB"))
        rgb = pixels.reshape(-1, 3)
        if not len(rgb):
            raise ValueError("Empty capture: " + str(path))
        luma = rgb @ np.array([0.2126, 0.7152, 0.0722])
        rows.append({
            "variant": capture["variant"], "shot": capture["shot"], "path": str(path),
            "sha256": digest, "pixels": len(rgb), "dimensions": capture["dimensions"],
            "camera_transform": capture.get("camera_transform"),
            "actual_camera_size_m": capture.get("actual_camera_size_m"),
            "rgb_mean": rgb.mean(axis=0).tolist(),
            "rgb_p01_p50_p95_p99": np.percentile(rgb, [1, 50, 95, 99], axis=0).tolist(),
            "luma_p01_p50_p95_p99": np.percentile(luma, [1, 50, 95, 99]).tolist(),
            "all_rgb_ge_250_fraction": np.all(rgb >= 250, axis=1).mean().item(),
            "any_rgb_ge_250_fraction": np.any(rgb >= 250, axis=1).mean().item(),
            "all_rgb_le_8_fraction": np.all(rgb <= 8, axis=1).mean().item(),
            "channel_histograms": [np.bincount(rgb[:, channel], minlength=256).tolist() for channel in range(3)],
        })
    if report_path.read_bytes() != report_bytes:
        raise ValueError("Calibration report changed during measurement")
    evidence = {
        "schema": "living_town.presentation_clipping_histograms.v1", "status": "DESCRIPTIVE_ONLY",
        "calibration_report_sha256": sha(report_bytes), "calibration_status": report.get("status"),
        "tool_sha256": sha(Path(__file__).read_bytes()),
        "runtime": {"python": sys.version, "numpy": np.__version__, "pillow": pillow_version},
        "limits": "Display-encoded 8-bit RGB, not HDR radiance. Luma is a weighted RGB proxy. Bright pixels can be intentional; ratios are not aesthetic verdicts. Camera identities are retained for human comparison; this tool does not approve camera equivalence, art, actor alignment or gameplay.",
        "frames": rows,
    }
    with output.open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(evidence, indent=2) + "\n")
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Fresh calibration evidence directory")
    args = parser.parse_args()
    evidence = analyse(args.directory)
    for row in evidence["frames"]:
        print(row["variant"]["name"], row["shot"]["name"], "white", round(row["all_rgb_ge_250_fraction"], 6),
              "anyclip", round(row["any_rgb_ge_250_fraction"], 6), "mean", [round(v, 2) for v in row["rgb_mean"]])
    output = args.directory / "clipping_histograms.json"
    print("HISTOGRAM_REPORT=" + str(output), "SHA256=" + sha(output.read_bytes()))


if __name__ == "__main__":
    main()
