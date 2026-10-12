"""Package and independently verify the portable Blender artifact.

Run with normal Python + Pillow and --blender PATH for required native reopen.
The archive preserves art/living_town so documented rebuild commands also work.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "Living_Town_Blender_Delivery"
ARCHIVE = ROOT.parent / "Living_Town_Blender_Delivery.zip"
TEMP_ARCHIVE = ARCHIVE.with_suffix('.zip.tmp')
REPORT = ROOT / "evidence/package_verification.json"


def sha_stream(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def sha_file(path):
    with path.open('rb') as stream:
        return sha_stream(stream)


def include(path):
    rel = path.relative_to(ROOT)
    excluded_dirs={"__pycache__", ".godot", "flythrough_frames", "export_preview", "export_probe", "export_history"}
    return (not excluded_dirs.intersection(rel.parts) and path.suffix not in {".blend1", ".tmp", ".interrupted"}
            and not path.name.endswith("_preview.png")
            and not path.name.endswith("_preview.json")
            and path != REPORT and path.stat().st_size > 0)


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--blender", type=Path, required=True,
                      help="Required Blender executable for the extracted native reopen.")
    opts = args.parse_args()
    inventory = []
    with ZipFile(TEMP_ARCHIVE, "w", ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(p for p in ROOT.rglob("*") if p.is_file() and include(p)):
            relative = path.relative_to(ROOT).as_posix()
            name = f"{PREFIX}/art/living_town/{relative}"
            z.write(path, name)
            inventory.append({"path": f"art/living_town/{relative}", "bytes": path.stat().st_size,
                              "sha256": sha_file(path)})
        z.writestr(f"{PREFIX}/FILE_MANIFEST.json", json.dumps({"files": inventory}, indent=2))
        z.writestr(f"{PREFIX}/START_HERE.html", '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Living Town</title><body style="font:18px system-ui;max-width:720px;margin:8vh auto;padding:24px;background:#f5f2e8;color:#283b36"><h1>Living Town</h1><p><a href="art/living_town/PRESENTATION.html">Open the complete visual presentation</a></p><p><a href="art/living_town/living_town_complete.blend">Open the editable Blender town</a></p><p><a href="art/living_town/DELIVERY_GUIDE.md">Read the delivery and editing guide</a></p><p>Extract the whole archive before opening. All presentation images are local. The native Blender scenes contain packed textures and fonts.</p></body></html>''')
        z.writestr(f"{PREFIX}/START_HERE.txt", "Extract the complete archive.\nOpen START_HERE.html or art/living_town/PRESENTATION.html.\nOpen art/living_town/living_town_complete.blend in Blender 5.2.2 LTS.\nSee art/living_town/DELIVERY_GUIDE.md for cameras, local sections and contour review.\nRun the documented rebuild commands from this directory. Rebuilding replaces generated files; save manual edits separately.\n")
    with TEMP_ARCHIVE.open('rb+') as stream:os.fsync(stream.fileno())
    report = {"schema": "living_town.portable_package.v1", "generated_utc": datetime.now(timezone.utc).isoformat(),
              "archive": ARCHIVE.name, "archive_bytes": TEMP_ARCHIVE.stat().st_size,
              "archive_sha256": sha_file(TEMP_ARCHIVE), "artifact_file_count": len(inventory)}
    with tempfile.TemporaryDirectory(prefix="living_town_portable_") as temp:
        base = Path(temp).resolve()
        with ZipFile(TEMP_ARCHIVE) as z:
            assert z.testzip() is None, "Archive CRC failed"
            for info in z.infolist():
                target = (base / info.filename).resolve()
                assert target.is_relative_to(base), "Archive path escaped extraction directory"
            for item in inventory:
                with z.open(f"{PREFIX}/{item['path']}") as stream:
                    assert sha_stream(stream) == item["sha256"], item["path"]
            z.extractall(base)
        report.update({"archive_crc": "PASS", "per_file_hashes": "PASS"})
        portable = base / PREFIX / "art/living_town"
        if opts.blender:
            result = subprocess.run([str(opts.blender), "--background", "--threads", "8", str(portable / "living_town_complete.blend"),
                                     "--python-exit-code", "1", "--python", str(portable / "tools/audit_native_scene.py")],
                                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
            assert result.returncode == 0, result.stdout[-2000:] + result.stderr[-2000:]
            native = json.loads((portable / "evidence/native_scene_audit.json").read_text(encoding="utf-8"))
            assert native["status"] == "PASS", native
            report["extracted_native_reopen"] = {"status": native["status"], "checks": len(native["checks"]),
                                                  "source_blend_sha256": native["source_blend_sha256"]}
        result = subprocess.run([sys.executable, str(portable / "tools/verify_delivery.py")],
                                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
        assert result.returncode == 0, result.stdout[-2000:] + result.stderr[-2000:]
        audit = json.loads((portable / "evidence/delivery_verification.json").read_text(encoding="utf-8"))
        assert audit["status"] == "PASS", audit["counts"]
        report["extracted_artifact_audit"] = {"status": audit["status"], "counts": audit["counts"],
                                                "source_mode": "portable_source_snapshot"}
    TEMP_ARCHIVE.replace(ARCHIVE)
    report["status"] = "PASS"
    temporary = REPORT.with_suffix('.tmp')
    with temporary.open('w',encoding='utf-8') as stream:
        json.dump(report,stream,indent=2);stream.flush();os.fsync(stream.fileno())
    temporary.replace(REPORT)
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
