"""Inventory or atomically publish the portable Windows game binary ZIP.

Never invokes Godot, Blender, an executable, or the network. --publish is an
explicit I/O operation for the coordinator's serial packaging slot. All proof
is supplied by the already-completed normal-entry export and source tests.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import uuid
import zipfile
import zlib
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from town_runtime_assets import (is_v2, validate_upgrade_evidence, runtime_records, sha as runtime_sha,
                                STAGE, CHARACTERS, PROFILE, PROJECTION,
                                UPGRADE_LOGICAL, UPGRADE_CAPTURE, UPGRADE_REVIEW)

CHUNK = 1024 * 1024
TOP = "LivingTown_Interactive_Windows"
BUILD = Path("build/town_bridge/windows_package")
EXPORT = Path("build/town_bridge/windows")
EXPORT_REPORT = "docs/town_bridge/windows_export_verification.json"
ARCHIVE_NAME = "LivingTown_Interactive_Windows.zip"
MANIFEST_NAME = "PACKAGE_FILES.json"
REPORT_NAME = "package_verification.json"

REQUIRED_NOTICES = (
    "LICENSE", "THIRD_PARTY_NOTICES.md", "docs/09-美术资产与版权.md",
    "docs/town_bridge/licenses/GODOT_LICENSE.txt",
    "docs/town_bridge/licenses/GODOT_COPYRIGHT.txt",
    "docs/town_bridge/licenses/PROVENANCE.json",
    "game/assets/fonts/LICENSE-SmileySans.txt",
    "game/assets/art/library/puny-characters/LICENSE.txt",
    "game/assets/art/library/punyworld-overworld/LICENSE.txt",
    "game/assets/art/library/puny-food/LICENSE.txt",
    "game/assets/art/library/puny-emotes/LICENSE.txt",
    "art/living_town/external_assets/fonts/LICENSE.md",
    "art/living_town/external_assets/fonts/PROVENANCE.json",
    "docs/town_bridge/licenses/REFINED_ASSETS.md",
    "docs/town_bridge/licenses/REFINED_BOTANICAL_SOURCES.json",
    "docs/town_bridge/licenses/REFINED_TERRAIN_SOURCES.json",
    "docs/town_bridge/licenses/REFINED_PBR_SOURCES.json",
    "docs/town_bridge/licenses/REFINED_CHARACTER_SOURCES.json",
    "docs/town_bridge/licenses/REFINED_LINEN_SOURCES.json",
    "docs/town_bridge/licenses/CC0_1.0.txt",
    "docs/town_bridge/licenses/INFINIGEN_NOTICES.txt",
)
SOURCE_PROOF = (
    "docs/town_bridge/README.md",
    "docs/town_walkthrough/ASSET_RELEASE.md",
    "docs/town_bridge/logical_test_report.json",
    "docs/town_bridge/visual_test_report.json",
    "docs/town_bridge/regression_test_report.json",
    "docs/town_bridge/actual_visual_test_review_report.json",
)


def encoded(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def read(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def safe_relative(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or any(
        ":" in part or "\\" in part or not part for part in path.parts
    ):
        raise ValueError(f"Unsafe package-relative name: {name!r}")
    return path


def contained(path: Path, parent: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_relative_to(parent.resolve()):
        raise ValueError(f"Path escapes the intended directory: {path}")
    return resolved


def regular_file(path: Path, root: Path) -> Path:
    if path.is_symlink():
        raise ValueError(f"Symlink payload is not permitted: {path}")
    resolved = contained(path, root)
    if not resolved.is_file():
        raise ValueError(f"Required payload file is missing: {path}")
    return resolved


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def passed(report: dict, label: str) -> None:
    checks = report.get("checks", [])
    if (report.get("status") != "PASS" or report.get("failure_count", 0) != 0
            or not checks or not all(check.get("passed") is True for check in checks)):
        raise ValueError(f"{label} evidence is not a passing completed report")


def capture_path(root: Path, record: dict) -> tuple[str, Path]:
    # Source reports may retain the original absolute output directory. The
    # archived portable path is always explicit and inside the capture folder.
    raw = str(record.get("file", ""))
    source = Path(raw)
    portable = root / "docs/town_bridge/captures" / source.name
    if portable.is_file():
        source = portable
    if not source.is_absolute():
        source = root / raw
    source = regular_file(source, root)
    rel = "docs/town_bridge/captures/" + source.name
    safe_relative(rel)
    return rel, source


def choose_files(root: Path) -> tuple[dict[str, Path], dict]:
    report = read(regular_file(root / EXPORT_REPORT, root))
    if report.get("schema") not in {"living_town.bridge.windows_export.v1", "living_town.upgrade.windows_export.v1"}:
        raise ValueError("Unsupported Windows export evidence schema")
    passed(report, "Windows export")
    boot = report.get("boot", {})
    if (boot.get("exit_code") != 0 or boot.get("entry_scene") != "Main"
            or boot.get("normal_product_entry") is not True or boot.get("actual_gpu") is not True):
        raise ValueError("Export evidence must prove normal Main entry with an actual GPU frame")
    binaries = {record.get("file"): record for record in report.get("binaries", [])}
    if len(report.get("binaries", [])) != 2 or set(binaries) != {"LivingTown.exe", "LivingTown.pck"}:
        raise ValueError("Export evidence must bind exactly LivingTown.exe and LivingTown.pck")
    files = {name: regular_file(root / EXPORT / name, root) for name in binaries}
    upgraded=is_v2(root)
    source_proof=("docs/town_bridge/README.md","docs/town_walkthrough/ASSET_RELEASE.md",UPGRADE_LOGICAL,UPGRADE_CAPTURE,UPGRADE_REVIEW,STAGE,CHARACTERS,PROFILE,PROJECTION,"game/scripts/town_walkthrough.gd") if upgraded else SOURCE_PROOF
    for rel in REQUIRED_NOTICES + source_proof + (EXPORT_REPORT,):
        safe_relative(rel)
        files[rel] = regular_file(root / rel, root)
    captures = list(report.get("screenshots", []))
    if not captures:
        raise ValueError("Normal-entry export evidence has no actual screenshot")
    visual = read(root / UPGRADE_CAPTURE) if upgraded else read(root / "docs/town_bridge/visual_test_report.json")
    captures.extend(visual.get("captures" if upgraded else "screenshots", []))
    if upgraded:
        for rel in ('tools/town_upgrade/characters/vendor/makehuman/LICENSE.md','tools/town_upgrade/characters/vendor/makehuman/LICENSE.ASSETS.md','tools/town_upgrade/characters/vendor/makehuman/LICENSE.CODE.md','tools/town_upgrade/characters/vendor/makehuman/provenance.json'):
            files[rel]=regular_file(root/rel,root)
    for record in captures:
        rel, source = capture_path(root, record)
        if rel in files and files[rel] != source:
            raise ValueError(f"Capture basename collision: {rel}")
        files[rel] = source
    names = list(files) + ["README.md", "ASSET_CREDITS.md", "Play_Offline.cmd", "Play_Compatibility.cmd", MANIFEST_NAME]
    if len({name.casefold() for name in names}) != len(names):
        raise ValueError("Archive names collide on a case-insensitive Windows filesystem")
    return dict(sorted(files.items())), report


def validate_sources(root: Path, files: dict[str, Path], hashes: dict[str, str], report: dict) -> dict:
    for binary in report["binaries"]:
        name = binary["file"]
        if files[name].stat().st_size != binary["bytes"] or hashes[name] != binary["sha256"]:
            raise ValueError(f"Current binary differs from exported runtime proof: {name}")
    with files["LivingTown.exe"].open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError("LivingTown.exe has no Windows PE header")
    with files["LivingTown.pck"].open("rb") as stream:
        if stream.read(4) != b"GDPC":
            raise ValueError("LivingTown.pck has no separate Godot pack header")
    if is_v2(root):
        return validate_sources_v2(root,files,hashes,report)
    logical_rel = "docs/town_bridge/logical_test_report.json"
    visual_rel = "docs/town_bridge/visual_test_report.json"
    legacy_rel = "docs/town_bridge/regression_test_report.json"
    logical = read(files[logical_rel])
    visual = read(files[visual_rel])
    legacy = json.loads(files[legacy_rel].read_text(encoding="utf-8"))
    passed(logical, "Source logical gameplay")
    passed(visual, "Source actual Main/LifeMode interaction")
    # Regression runner records a top-level case list, not a report object.
    if (not isinstance(legacy, list) or not legacy or not all(
            case.get("passed") is True and case.get("exit_code") == 0 and not case.get("errors")
            for case in legacy)):
        raise ValueError("Legacy regression evidence is not passing")
    source = report.get("source_runtime_evidence", {})
    for field, rel in (("logical_report_sha256", logical_rel), ("visual_report_sha256", visual_rel)):
        if source.get(field) != hashes[rel]:
            raise ValueError(f"Windows report references stale source proof: {rel}")
    if source.get("logical_checks") != len(logical["checks"]) or source.get("visual_checks") != len(visual["checks"]):
        raise ValueError("Windows report misstates the separate source interaction check counts")
    if source.get("legacy_regressions") != len(legacy):
        raise ValueError("Windows report misstates the separate legacy regression count")
    for label, evidence in (("logical", logical), ("visual", visual)):
        for field in ("source_blend_sha256", "projection_sha256"):
            if evidence.get(field) != report.get(field):
                raise ValueError(f"{label} proof references a different {field}")
    if visual.get("source_glb_sha256") != report.get("source_glb_sha256"):
        raise ValueError("Source interaction evidence references a different model")
    profile = read(root / "game/data/town3d/profile.json")
    if sha(root / "game/data/town3d/profile.json") != report.get("profile_sha256"):
        raise ValueError("Windows report references another spatial profile")
    if (sha(root / "game/data/town3d/projection.json") != report.get("projection_sha256")
            or profile.get("projection_sha256") != report.get("projection_sha256")):
        raise ValueError("Windows report references another projection")
    review = read(files["docs/town_bridge/actual_visual_test_review_report.json"])
    if review.get("status") != "PASS" or review.get("visual_report_sha256") != hashes[visual_rel]:
        raise ValueError("Actual image inspection is stale relative to source visual evidence")
    portable_captures = []
    for origin, evidence in (("native_normal_entry", report), ("source_interaction_harness", visual)):
        for capture in evidence.get("screenshots", []):
            rel, source_path = capture_path(root, capture)
            if hashes[rel] != capture.get("sha256"):
                raise ValueError(f"Actual screenshot differs from its runtime evidence: {rel}")
            if "bytes" in capture and source_path.stat().st_size != capture["bytes"]:
                raise ValueError(f"Actual screenshot size differs from runtime evidence: {rel}")
            portable_captures.append({"package_file": rel, "sha256": hashes[rel], "proof_scope": origin})
    return {
        "native_normal_entry": {"checks": len(report["checks"]), "boot": report["boot"],
                                "source_verification": report.get("source_verification", "")},
        "separate_source_runtime_evidence": source,
        "source_blend_sha256": report.get("source_blend_sha256"),
        "source_glb_sha256": report.get("source_glb_sha256"),
        "profile_sha256": report.get("profile_sha256"),
        "projection_sha256": report.get("projection_sha256"),
        "captures": portable_captures,
        "limits": report.get("limitations", []),
        "packaging_does_not_rerun_game": True,
    }


def validate_sources_v2(root,files,hashes,report):
    # The source package carries raw chunks. The binary package carries their
    # imported PCK plus metadata/evidence, avoiding another duplicate asset set.
    source_hashes={rel:runtime_sha(root/rel) for rel in runtime_records(root)}
    profile=read(root/PROFILE)
    for filename in profile['file_hashes']:
        rel='game/data/town3d/'+safe_relative(filename).as_posix()
        source_hashes[rel]=runtime_sha(root/rel)
    for rel in profile.get('presentation_source_hashes',{}):
        source_hashes[safe_relative(rel).as_posix()]=runtime_sha(root/rel)
    for rel in (PROFILE,PROJECTION,UPGRADE_LOGICAL,UPGRADE_CAPTURE,UPGRADE_REVIEW,'game/scripts/town_walkthrough.gd'):
        source_hashes[rel]=runtime_sha(root/rel)
    source_hashes.update(hashes)
    proof=validate_upgrade_evidence(root,source_hashes)
    for field in ('profile_sha256','projection_sha256','source_asset_set_sha256','characters_manifest_sha256'):
        if report.get(field)!=proof[field]:raise ValueError('Windows export proof belongs to another upgraded runtime: '+field)
    if report.get('stage_manifest_sha256')!=hashes[STAGE]:raise ValueError('Windows export proof belongs to another staged chunk set')
    source=report.get('source_runtime_evidence',{})
    if source.get('logical_report_sha256')!=hashes[UPGRADE_LOGICAL] or source.get('visual_report_sha256')!=hashes[UPGRADE_CAPTURE]:
        raise ValueError('Windows proof does not bind the completed new logical and actual input reports')
    portable=[]
    for origin,rows in (('native_normal_entry',report.get('screenshots',[])),('actual_Main_walkthrough',read(root/UPGRADE_CAPTURE).get('captures',[]))):
        for capture in rows:
            rel,path=capture_path(root,capture)
            if hashes.get(rel)!=capture.get('sha256'):raise ValueError('Packaged actual screenshot differs: '+rel)
            portable.append({'package_file':rel,'sha256':hashes[rel],'proof_scope':origin})
    return {**proof,'native_boot_report_included':True,'native_normal_entry':{'checks':len(report['checks']),'boot':report['boot'],'source_verification':report.get('source_verification','')},
        'separate_source_runtime_evidence':{'logical_checks':proof['logical_check_count'],'visual_checks':proof['visual_check_count'],'legacy_regressions':source.get('legacy_regressions',0)},
        'captures':portable,'limits':report.get('limitations',[]),'packaging_does_not_rerun_game':True}


def readme(proof: dict) -> bytes:
    source = proof["separate_source_runtime_evidence"]
    return f"""# Living Town / 小镇有灵 — Windows interactive 3D game

1. Extract the whole ZIP to a folder on your PC.
2. Keep LivingTown.exe and LivingTown.pck together.
3. Double-click LivingTown.exe. The default launch opens the 3D town and resident
   selection. Choose a resident to live their day.

This is a Windows x86_64 game binary. Godot, Blender, Python, a model download,
an account and the separate source archive are not needed to play. The existing
logic backend works offline. Play_Offline.cmd explicitly selects that backend
and the resident-selection screen if you want a fixed offline launch.

The desktop default requests Godot's Mobile renderer for direct LivingTown.exe
launch and editor play (F5/F6). Older GPUs can use Play_Compatibility.cmd, which
selects OpenGL Compatibility with the same offline 3D resident-selection mode.
Automatic OpenGL fallback is also enabled when RenderingDevice is unavailable.

## Controls

- WASD / arrow keys, or click the ground: walk.
- E / Enter, or the interaction button: nearby furnishing/person/door actions.
- Click a modeled furnishing or person: open its existing action menu.
- Tab: change nearby target. Q: cancel walking/action.
- Mouse wheel or +/-: zoom. Space: pause/resume. 1/2/3/4: speed controls.
- F: toggle resident autonomy. R: relationships. C: choose another life.
- F5: quicksave. F8: quickload. The 3D and legacy saves are separate.
- The existing touch joystick and action buttons remain available.

A gold silhouette identifies the controlled resident only when a real roof,
tree or wall blocks the body. The normal character still uses depth rendering.
The existing needs, jobs, money, wishes, dialogue and interaction permissions
remain authoritative. No external AI backend or weights are bundled.

## Evidence and source

docs/town_bridge/windows_export_verification.json records the exported EXE/PCK
hashes, normal Main launch and one actual GPU capture. It does not claim the
complete interaction harness ran inside the release binary. The separate source
runtime reports record {source["logical_checks"]} logical gameplay checks, {source["visual_checks"]} actual Main/LifeMode input
checks and {source["legacy_regressions"]} legacy regressions; their captures and independent image review
are included for context. Packaging rechecks bytes, not gameplay behavior.
See docs/town_bridge/README.md for the spatial bridge and current limits.

The editable LivingTown_Interactive_Source.zip is a separate delivery. This
binary ZIP contains no editable game source tree, Blender files or reference
movies. General population/FPS scaling and every optional AI backend are not
certified by these bounded checks.

PACKAGE_FILES.json lists payload sizes and SHA-256 hashes, excluding only its
own self-hash. The external package_verification.json records the archive SHA,
streamed CRC checks and exact extracted hashes. It is intentionally outside the
archive so the manifest cannot refer recursively to its own archive checksum.

## Licenses

See LICENSE, THIRD_PARTY_NOTICES.md and ASSET_CREDITS.md. Godot Engine is MIT:
https://godotengine.org/license/ . Its full notice and third-party notices are
included under docs/town_bridge/licenses. Font and CC0 asset notices are also
included; the fonts and art used by the game are packed in LivingTown.pck.
""".encode("utf-8")


def credits(upgraded=False) -> bytes:
    text = """# Packaged asset credits

Game code: MIT, Copyright (c) 2026 Yang Peng; see LICENSE.

Godot Engine 4.6.2: MIT. Full engine and bundled-component notices are retained
in docs/town_bridge/licenses/GODOT_LICENSE.txt and GODOT_COPYRIGHT.txt.
Official license information: https://godotengine.org/license/ .

Pixel art: Puny Characters / PunyWorld by Shade and Food / Emotes by admurin,
CC0. Original notices are included in game/assets/art/library. The project's
edited character sheets and authored art are in the PCK. See
docs/09-美术资产与版权.md for the original provenance narrative.

UI font: unmodified Smiley Sans, atelierAnchor, SIL OFL 1.1. Full copyright,
reserved-name and OFL text: game/assets/fonts/LICENSE-SmileySans.txt.

Town: authored procedural geometry and textures from the Living Town delivery.
Adobe Source Serif 4 was used for modeled signage. Its OFL notice/provenance
are included under art/living_town/external_assets/fonts. The original font
binary, HDRI, Blender sources and reference movies are not bundled or needed.

The package includes no NobodyWho native addon or model weights. Optional
backend installations and their licenses are separate from this binary build.
Historical documentation links may refer to the separate complete repository.
"""
    if upgraded:
        text += "\nRefined mesh residents use the CC0 MakeHuman anatomical base and weights,\nwith original fitted clothes, hair, textures and rig adaptation. Full source\nlicenses/provenance are included under tools/town_upgrade/characters/vendor/makehuman.\nBotanical and photographed surface inputs are CC0; source receipts and exact\ncredits remain in THIRD_PARTY_NOTICES.md and the editable native art delivery.\n"
    return text.encode("utf-8")


def offline_launcher() -> bytes:
    return ("@echo off\r\nsetlocal\r\npushd \"%~dp0\"\r\n"
            "\"LivingTown.exe\" -- --town3d --backend logic --life\r\n"
            "set \"town_exit=%errorlevel%\"\r\npopd\r\nexit /b %town_exit%\r\n").encode("ascii")


def compatibility_launcher() -> bytes:
    return ("@echo off\r\nsetlocal\r\npushd \"%~dp0\"\r\n"
            "\"LivingTown.exe\" --rendering-method gl_compatibility --rendering-driver opengl3 -- --town3d --backend logic --life\r\n"
            "set \"town_exit=%errorlevel%\"\r\npopd\r\nexit /b %town_exit%\r\n").encode("ascii")


def zip_info(rel: str) -> zipfile.ZipInfo:
    safe_relative(rel)
    info = zipfile.ZipInfo(TOP + "/" + rel, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    info.create_system = 3
    return info


def write_atomic_json(path: Path, value: dict) -> None:
    temporary = path.with_name(path.name + ".tmp_" + uuid.uuid4().hex)
    with temporary.open("xb") as stream:
        stream.write(encoded(value))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def publish(root: Path, files: dict[str, Path], report: dict, freeze_id: str) -> dict:
    if report.get("freeze_id") not in (None, freeze_id):
        raise ValueError("Requested freeze-id differs from the exported runtime report")
    hashes = {rel: sha(path) for rel, path in files.items()}
    if read(files[EXPORT_REPORT]) != report:
        raise ValueError("Export report changed after the packaging inventory was selected")
    proof = validate_sources(root, files, hashes, report)
    generated = {"README.md": readme(proof), "ASSET_CREDITS.md": credits(is_v2(root)),
                 "Play_Offline.cmd": offline_launcher(), "Play_Compatibility.cmd": compatibility_launcher()}
    entries = {rel: {"bytes": path.stat().st_size, "sha256": hashes[rel]} for rel, path in files.items()}
    for rel, data in generated.items():
        entries[rel] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    manifest = {"schema": "living_town.windows.package_manifest.v1", "freeze_id": freeze_id,
                "export_report": {"file": EXPORT_REPORT, "sha256": hashes[EXPORT_REPORT]},
                "runtime_proof": proof, "entries": dict(sorted(entries.items())),
                "self_hash_excluded": MANIFEST_NAME}
    generated[MANIFEST_NAME] = encoded(manifest)
    manifest_record = {"bytes": len(generated[MANIFEST_NAME]), "sha256": hashlib.sha256(generated[MANIFEST_NAME]).hexdigest()}
    expected = dict(entries)
    expected[MANIFEST_NAME] = manifest_record
    output = contained(root / BUILD, root / "build/town_bridge")
    output.mkdir(parents=True, exist_ok=True)
    run_id = uuid.uuid4().hex
    extraction = contained(output / ("verify_" + run_id), output)
    extraction.mkdir(exist_ok=False)
    candidate = contained(output / (ARCHIVE_NAME + ".tmp_" + run_id), output)
    final = contained(output / ARCHIVE_NAME, output)
    with candidate.open("xb") as raw:
        with zipfile.ZipFile(raw, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=1, allowZip64=True) as archive:
            for rel in sorted(expected):
                info = zip_info(rel)
                if rel in generated:
                    archive.writestr(info, generated[rel], compresslevel=1)
                    continue
                digest = hashlib.sha256()
                count = 0
                with files[rel].open("rb") as source, archive.open(info, "w", force_zip64=True) as dest:
                    for block in iter(lambda: source.read(CHUNK), b""):
                        digest.update(block)
                        count += len(block)
                        dest.write(block)
                if count != expected[rel]["bytes"] or digest.hexdigest() != expected[rel]["sha256"]:
                    raise ValueError(f"Payload changed while writing archive: {rel}")
        raw.flush()
        os.fsync(raw.fileno())
    verified = {}
    with zipfile.ZipFile(candidate) as archive:
        infos = archive.infolist()
        expected_names = {TOP + "/" + rel for rel in expected}
        if len(infos) != len(expected_names) or {item.filename for item in infos} != expected_names:
            raise ValueError("ZIP has missing, duplicate or unexpected entries")
        for info in infos:
            safe_relative(info.filename)
            rel = info.filename.removeprefix(TOP + "/")
            if info.is_dir() or info.flag_bits & 1 or info.file_size != expected[rel]["bytes"]:
                raise ValueError(f"Invalid archive entry: {info.filename}")
            dest = contained(extraction / Path(*PurePosixPath(info.filename).parts), extraction)
            dest.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            crc = 0
            count = 0
            with archive.open(info) as source, dest.open("xb") as target:
                for block in iter(lambda: source.read(CHUNK), b""):
                    count += len(block)
                    if count > expected[rel]["bytes"]:
                        raise ValueError(f"Archive entry exceeds expected length: {rel}")
                    digest.update(block)
                    crc = zlib.crc32(block, crc)
                    target.write(block)
            crc &= 0xFFFFFFFF
            if count != expected[rel]["bytes"] or digest.hexdigest() != expected[rel]["sha256"] or crc != info.CRC:
                raise ValueError(f"Streamed extracted hash/CRC mismatch: {rel}")
            # Reopen the actual on-disk result, not only the bytes handed to write.
            if dest.stat().st_size != count or sha(dest) != expected[rel]["sha256"]:
                raise ValueError(f"Extracted on-disk hash mismatch: {rel}")
            verified[rel] = {**expected[rel], "crc32": f"{crc:08x}", "extracted_sha256": digest.hexdigest()}
    actual = {path.relative_to(extraction / TOP).as_posix() for path in (extraction / TOP).rglob("*") if path.is_file()}
    if actual != set(expected):
        raise ValueError("Extracted files do not match the exact expected inventory")
    package_report = {
        "schema": "living_town.windows.package_verification.v1", "status": "PASS",
        "generated_utc": datetime.now(timezone.utc).isoformat(), "freeze_id": freeze_id,
        "archive": {"file": str(final.relative_to(root)), "bytes": candidate.stat().st_size,
                    "sha256": sha(candidate)},
        "manifest_sha256": manifest_record["sha256"],
        "export_report_sha256": hashes[EXPORT_REPORT],
        "external_binary_hashes": {name: expected[name] for name in ("LivingTown.exe", "LivingTown.pck")},
        "runtime_proof": proof, "entry_count": len(expected),
        "stream_crc_pass": True, "exact_inventory_pass": True, "extracted_hashes_pass": True,
        "extraction_directory": str(extraction.relative_to(root)), "entries": dict(sorted(verified.items())),
        "report_is_external_to_archive": True, "game_was_not_run_by_packager": True,
    }
    # All byte, CRC, inventory and on-disk extraction checks precede publication.
    os.replace(candidate, final)
    write_atomic_json(output / REPORT_NAME, package_report)
    return package_report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--freeze-id", required=True, help="Explicit coordinator freeze identifier for this publication")
    parser.add_argument("--publish", action="store_true", help="Stream ZIP, verify exact extracted bytes, then atomically publish")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.freeze_id):
        parser.error("--freeze-id must be 1-128 ASCII letters, digits, dot, underscore or hyphen")
    root = args.root.resolve()
    files, report = choose_files(root)
    if not args.publish:
        print(json.dumps({"mode": "inventory_only", "freeze_id": args.freeze_id, "source_files": len(files),
                          "source_bytes": sum(path.stat().st_size for path in files.values()),
                          "output": str(root / BUILD / ARCHIVE_NAME),
                          "publication_requires": "--publish with coordinator's serial I/O slot"}, ensure_ascii=False, indent=2))
        return 0
    result = publish(root, files, report, args.freeze_id)
    print(json.dumps({"status": result["status"], "freeze_id": args.freeze_id,
                      "archive": result["archive"], "entry_count": result["entry_count"],
                      "external_report": str(root / BUILD / REPORT_NAME)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
