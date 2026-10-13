"""Curate the reserve source and engine-neutral GLBs into a verified ZIP.

No recursive workspace copying and no Blender/Godot invocation. Default is a
non-writing preflight; --build explicitly stages, flushes and archives a complete
current delivery. Existing destinations are never overwritten or removed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
import zipfile

import verify_reserve_delivery as verify


DEFAULT_OUTPUT = Path("D:/Dev/2026-10-07/LivingTown_Reserve_Delivery")
PACKAGE_NAME = "LivingTown_Reserve_Delivery"


def flush_file(path):
    with Path(path).open("rb+") as stream:
        os.fsync(stream.fileno())


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def file_record(path):
    with Path(path).open("rb") as stream:
        digest = verify.hash_stream(stream)
    return {"path": str(Path(path).resolve()), "bytes": Path(path).stat().st_size, "sha256": digest}


def start_here(preflight):
    return f"""# Living Town — Reserve Asset Edition

Release tag: `{verify.RELEASE_TAG}`. This is a Blender and engine-neutral GLB
asset/source delivery. The existing playable game's urban model is a separate
earlier stage; this reserve package does not extend its simulation or navigation.

- Open `art/living_town/living_town_complete.blend` for the complete town,
  graded wooded reserve, 12 furnished trailers and nine visitor/service units.
- `game_assets_reserve/living_town_game.glb` is the measured optimized whole
  town, with an accepted ceiling of 5,000,000 expanded instance triangles.
  The manifest contains exact triangle/byte budgets; 49 core and 21 reserve
  units also have prefabs. `living_town.glb` is included only if an optional
  high-detail whole-town variant was exported; it is not required for this edition.
- See `docs/RESERVE_EDITION.md` for design, six-thread serial rebuild recipes,
  terrain/bridge/stair semantics and the limits of this edition.
- `art/living_town/renders/reserve_v6/` contains the 15 current final stills.
- `art/living_town/integration/reserve_godot/` is an isolated GLB consumer,
  with logical/renderer receipts and four actual reviewed PNG captures. It is
  a portability test, not the playable life simulation or a physics certificate.
- `game/data/town3d/projection.json` is reference-only input for the frozen 47
  game-bound fixture audit and furniture regeneration. Its hash matches that
  actual native audit; no game runtime/scripts are shipped.
- `living_town_building_study.blend` is the separately frozen earlier urban
  study included as source. Its historical renders/media are deliberately absent.
- The included GLB camera rig is optional for consumers to load and carries
  native poses. Review renders may use
  temporary cameras documented in their render records; those poses are not
  promised to be part of the GLB rig.

Current town SHA256: `{preflight['source_blend_sha256']}`

Source freeze, both saved-native audits, independent reserve export verification,
the isolated consumer receipts and actual-image review are retained under the
curated evidence paths. Their original machine paths and timestamps remain as
historical execution receipts; portable verification resolves packaged names.
The compact stair negative-control receipt records rejection of a known-bad
checkpoint by the current audit; its faulty native and full diagnostics are
excluded. The delivered native separately passes the same actual stair gate.

Verify without executing any packaged model/source script:

```powershell
python tools/verify_reserve_delivery.py --delivery . --report ../reserve_extracted_verification.json
python tools/verify_reserve_delivery.py --archive ../LivingTown_Reserve_Delivery.zip --report ../reserve_zip_verification.json
```

To rerun the isolated consumer with your own Godot 4.6 binary:

```powershell
python art/living_town/integration/reserve_godot/run_consumer.py --godot <Godot.exe> --assets game_assets_reserve --native-manifest art/living_town/town_manifest.json --capture --evidence <new-evidence-folder>
```

Keep the original evidence unchanged; fresh runs belong in a new directory.
Run one heavy process at a time. Native builders need Blender; procedural texture
regeneration additionally needs NumPy/Pillow, while these package tools use only
the Python standard library. Native images/textures/fonts/HDRI are packed and also
included with original license/provenance records. No reference films, raw movie,
historical V5 media, engine binaries, caches or unrelated game data are included.
The kit rebuilds from the delivered canonical planning JSON; obsolete urban
layout-drafting helpers and their historical inputs are outside this source kit.

`FILE_MANIFEST.json` records every payload file's bytes and SHA256; the external
packager report records the ZIP and checksum-manifest hashes. Hash consistency
does not authenticate a downloaded release against an attacker: compare its
published ZIP checksum using a separately trusted release channel.
"""


def copy_verified(reader, name, destination):
    """Hash while copying, then flush and verify the on-disk destination."""
    expected = reader.record(name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    count = 0
    with reader.open(name) as source, destination.open("xb") as out:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            out.write(block)
            digest.update(block)
            count += len(block)
        out.flush()
        os.fsync(out.fileno())
    verify.require(count == expected["bytes"] and digest.hexdigest() == expected["sha256"], "Source changed while staging: " + name)
    actual = file_record(destination)
    verify.require(actual["bytes"] == expected["bytes"] and actual["sha256"] == expected["sha256"], "Staged bytes differ: " + name)
    return {"path": name, "bytes": count, "sha256": digest.hexdigest()}


def build(reader, output, preflight, compresslevel=3):
    """Called only by explicit --build; failed partials remain for diagnosis."""
    output = output.resolve()
    stage = output / PACKAGE_NAME
    archive = output / (PACKAGE_NAME + ".zip")
    partial_stage = output / (PACKAGE_NAME + ".partial")
    partial_archive = output / (PACKAGE_NAME + ".zip.partial")
    for path in (stage, archive, partial_stage, partial_archive, output / "reserve_package_report.json", output / (PACKAGE_NAME + ".zip.sha256")):
        verify.require(not path.exists(), "Refusing to overwrite existing destination: " + str(path))
    source_root = reader.repo.resolve()
    verify.require(not output.is_relative_to(source_root / "art/living_town"), "Delivery output must be outside the source art tree")
    verify.require(not output.is_relative_to(reader.assets), "Delivery output must be outside the export input directory")
    output.mkdir(parents=True, exist_ok=True)
    partial_stage.mkdir()
    rows = []
    for index, name in enumerate(verify.payload_names(reader), 1):
        rows.append(copy_verified(reader, name, partial_stage / name))
        if index % 25 == 0:
            print(json.dumps({"stage": "copy", "completed_files": index}), flush=True)
    intro = partial_stage / "START_HERE.md"
    with intro.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(start_here(preflight));stream.flush();os.fsync(stream.fileno())
    rows.append(dict(file_record(intro), path="START_HERE.md"))
    rows.sort(key=lambda row: row["path"])
    manifest = {"schema": "living_town.reserve_package.v1", "generated_utc": datetime.now(timezone.utc).isoformat(),
                "release_tag": verify.RELEASE_TAG, "source_blend_sha256": preflight["source_blend_sha256"],
                "source_freeze_sha256": preflight["source_freeze_sha256"],
                "export_manifest_sha256": preflight["export_manifest_sha256"], "files": rows,
                "file_count": len(rows), "payload_bytes": sum(row["bytes"] for row in rows),
                "scope": "Curated reserve edition only; no reference films, historical media, caches or game runtime."}
    write_json(partial_stage / verify.FILE_MANIFEST, manifest)
    staged_reader = verify.Reader(directory=partial_stage)
    staged_proof = verify.validate(staged_reader, packaged=True)
    verify.require(staged_proof["status"] == "PASS", "Staged package verification failed: " + json.dumps(staged_proof))
    print(json.dumps({"stage": "staged_verified", "files": len(rows), "payload_bytes": manifest["payload_bytes"]}), flush=True)
    # One compressor, streaming file I/O, ZIP64 for native/GLB packages >4 GiB.
    with zipfile.ZipFile(partial_archive, "x", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=compresslevel, allowZip64=True) as writer:
        for row in rows + [{"path": verify.FILE_MANIFEST}]:
            name = row["path"]
            writer.write(partial_stage / name, arcname=name)
    flush_file(partial_archive)
    zip_reader = verify.Reader(archive=partial_archive)
    try:
        zip_proof = verify.validate(zip_reader, packaged=True)
    finally:
        zip_reader.close()
    verify.require(zip_proof["status"] == "PASS", "Post-write ZIP entry/hash verification failed: " + json.dumps(zip_proof))
    # Publication is the final step, after staged and streamed ZIP checks PASS.
    partial_stage.rename(stage)
    partial_archive.rename(archive)
    flush_file(archive)
    result = {"schema": "living_town.reserve_packager.v1", "status": "PASS", "generated_utc": datetime.now(timezone.utc).isoformat(),
              "release_tag": verify.RELEASE_TAG, "source_blend_sha256": preflight["source_blend_sha256"],
              "source_freeze_sha256": preflight["source_freeze_sha256"], "export_manifest_sha256": preflight["export_manifest_sha256"],
              "archive": file_record(archive), "file_manifest": file_record(stage / verify.FILE_MANIFEST),
              "staged_directory": str(stage), "file_count": len(rows), "payload_bytes": manifest["payload_bytes"],
              "preflight": preflight, "staged_verification": staged_proof, "zip_verification": zip_proof,
              "execution_policy": "One Python process, serial copy/compression/verification, no Blender/Godot; all payloads and ZIP fsynced."}
    write_json(output / "reserve_package_report.json", result)
    with (output / (PACKAGE_NAME + ".zip.sha256")).open("x", encoding="ascii", newline="\n") as stream:
        stream.write(result["archive"]["sha256"] + "  " + archive.name + "\n");stream.flush();os.fsync(stream.fileno())
    return result


def self_test():
    class PurePackagerChecks(unittest.TestCase):
        def test_verified_copy_and_mutation(self):
            with tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                source = base / "source";source.mkdir()
                (source / "a.bin").write_bytes(b"source")
                reader = verify.Reader(directory=source)
                row = copy_verified(reader, "a.bin", base / "out/a.bin")
                self.assertEqual(row["sha256"], hashlib.sha256(b"source").hexdigest())
                (source / "a.bin").write_bytes(b"changed")
                with self.assertRaises(verify.DeliveryError):
                    copy_verified(reader, "a.bin", base / "out/b.bin")

        def test_generated_scope_is_explicit(self):
            text = start_here({"source_blend_sha256": "a" * 64})
            self.assertIn("separate", text)
            self.assertIn("earlier urban", text)
            self.assertIn("six-thread", text)
            self.assertIn("game_assets_reserve", text)

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PurePackagerChecks))
    return result.wasSuccessful()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--assets", type=Path)
    parser.add_argument("--consumer-evidence", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, help="Optional preflight/build receipt outside the package")
    parser.add_argument("--build", action="store_true", help="Explicitly copy and compress only after current evidence PASS")
    parser.add_argument("--compresslevel", type=int, choices=range(0, 10), default=3)
    parser.add_argument("--self-test", action="store_true")
    opt = parser.parse_args()
    if opt.self_test:
        return 0 if self_test() else 1
    reader = verify.Reader(repo=opt.repo, assets=opt.assets, consumer_evidence=opt.consumer_evidence)
    preflight = verify.validate(reader)
    result = {"schema": "living_town.reserve_packager_preflight.v1", "status": preflight["status"], "build_requested": opt.build,
              "compression_executed": False, "output_directory": str(opt.output.resolve()), "verification": preflight}
    if preflight["status"] == "PASS" and opt.build:
        try:
            result = build(reader, opt.output, preflight, opt.compresslevel)
        except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as exc:
            result = {"schema": "living_town.reserve_packager.v1", "status": "FAIL", "build_requested": True,
                      "error": str(exc), "output_directory": str(opt.output.resolve()), "preflight": preflight,
                      "recovery": "Existing and .partial paths retained. Inspect them; this tool never deletes or overwrites a delivery."}
    if opt.report:
        write_json(opt.report, result)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
