"""Copy a frozen native candidate, then export only the disposable copy.

This bounded adapter accommodates export_verified_town.py's updated coordination
manifest without allowing a later stage to mutate an earlier frozen output.
It never builds native geometry or changes the original candidate.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys

from .cli import ToolboxError, binding, files, read, utc, write


def prepare_copy(source, output):
    source, output = Path(source).resolve(strict=True), Path(output).resolve()
    if not source.is_dir() or source == output or output.is_relative_to(source) or source.is_relative_to(output):
        raise ToolboxError("Native source and fresh export output must be separate directories")
    if output.exists():
        raise ToolboxError("Export working directory already exists; preserve it and choose a fresh iteration")
    manifest = read(source / "upgrade_manifest.json")
    if manifest.get("assets") or (source / "chunks").exists() or (source / "export_working_copy_receipt.json").exists():
        raise ToolboxError("Use a pristine native candidate without previous/partial portable exports")
    native = Path(manifest["native"]["path"])
    if native.is_absolute() or not (source / native).resolve().is_relative_to(source):
        raise ToolboxError("Native manifest must name a relative source member")
    for required in (native, Path("whole_town_buildings.json"), Path("whole_town_native_geometry.json")):
        if not (source / required).is_file():
            raise ToolboxError("Missing native export input: " + str(required))
    before = binding(source)
    output.mkdir(parents=True, exist_ok=False)
    for member in files(source):
        destination = output / member.relative_to(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(member, destination)
    source_after, copied = binding(source), binding(output)
    if source_after != before or copied["files"] != before["files"]:
        raise ToolboxError("Native source/copy file inventory changed during export preparation", 3)
    receipt = {"schema": "living_town.asset_toolbox.export_copy.v1", "status": "COPY_VERIFIED",
               "created_utc": utc(), "source": before, "copy_before_export": copied,
               "scope": "Exact pre-export copy; only the separate working copy may be changed by the exporter."}
    write(output / "export_working_copy_receipt.json", receipt)
    return source, output, receipt


def export(source, output, blender, repo):
    repo, blender = Path(repo).resolve(strict=True), Path(blender).resolve(strict=True)
    if not blender.is_file():
        raise ToolboxError("Blender must be an explicit executable file")
    exporter = repo / "tools/town_upgrade/export_verified_town.py"
    if not exporter.is_file():
        raise ToolboxError("Missing existing town exporter")
    source, output, receipt = prepare_copy(source, output)
    receipt_path = output / "export_working_copy_receipt.json"
    argv = [str(blender), "--background", "--factory-startup", "--threads", "6", "--python-exit-code", "1",
            "--python", str(exporter), "--", "--manifest", str(output / "upgrade_manifest.json")]
    receipt.update(status="EXPORTING", argv=argv)
    try:
        process = subprocess.Popen(argv, cwd=repo, shell=False)
        receipt["engine_pid"] = process.pid
        write(receipt_path, receipt)
        receipt["engine_exit_code"] = process.wait()
        receipt["source_after_export"] = binding(source)
        receipt["source_unchanged"] = receipt["source_after_export"] == receipt["source"]
        if not receipt["source_unchanged"]:
            raise ToolboxError("Exporter changed the immutable original native candidate", 3)
        if receipt["engine_exit_code"] != 0:
            raise ToolboxError("Blender export failed: exit " + str(receipt["engine_exit_code"]), 3)
        if read(output / "portable_export_receipt.json").get("status") != "PASS":
            raise ToolboxError("Existing exporter did not produce its passing byte/visibility receipt", 3)
        receipt["status"] = "EXPORTED_SOURCE_UNCHANGED"
        receipt["finished_utc"] = utc()
        write(receipt_path, receipt)
        return receipt
    except BaseException as exc:
        receipt.update(status="FAILED" if not isinstance(exc, KeyboardInterrupt) else "INTERRUPTED",
                       error=str(exc), finished_utc=utc())
        write(receipt_path, receipt)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--blender", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = export(args.source, args.output, args.blender, args.repo)
        print(result["status"])
        return 0
    except (ToolboxError, OSError, KeyError, TypeError, ValueError) as exc:
        print("EXPORT_COPY_FAILED: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
