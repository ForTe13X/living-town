#!/usr/bin/env python3
"""Deterministic positive and fail-closed tests for the cafe attestation root."""

from __future__ import annotations

import argparse
import binascii
import copy
import gzip
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zlib
from pathlib import Path
from typing import Any, Callable

import cafe_authored_manifest as authored
import verify_cafe_attested_evidence as verifier


RUNTIME_ARCHIVE_SHA = "a" * 64
OCI_MANIFEST_SHA = "b" * 64
REPOSITORY = "ForTe13X/living-town"
RUN_ID = "9001"
RUN_ATTEMPT = "1"


class SelftestError(RuntimeError):
    pass


def canonical(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def run(*args: str, cwd: Path) -> str:
    environment = dict(os.environ)
    environment.update({"LC_ALL": "C", "TZ": "UTC"})
    if len(args) >= 2 and args[0] == "git" and args[1] == "commit":
        environment.update(
            {
                "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
                "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z",
            }
        )
    try:
        return subprocess.check_output(
            args,
            cwd=cwd,
            text=True,
            stderr=subprocess.STDOUT,
            env=environment,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SelftestError(f"command failed: {' '.join(args)}: {getattr(exc, 'output', '')}") from exc


def write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data.encode("utf-8") if isinstance(data, str) else data)


def png_from_scanlines(width: int, height: int, raw: bytes, *, interlace: int = 0) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, interlace))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def png(width: int, height: int, color: tuple[int, int, int, int]) -> bytes:
    row = b"\0" + bytes(color) * width
    return png_from_scanlines(width, height, row * height)


def make_tar(source: Path, destination: Path) -> None:
    files = sorted(path for path in source.rglob("*") if path.is_file())
    with destination.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path in files:
                    rel = path.relative_to(source).as_posix()
                    data = path.read_bytes()
                    info = tarfile.TarInfo(rel)
                    info.size = len(data)
                    info.mtime = 0
                    info.mode = 0o644
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    archive.addfile(info, __import__("io").BytesIO(data))


def rewrite_tar(
    source: Path,
    destination: Path,
    mutation: Callable[[list[tuple[tarfile.TarInfo, bytes]]], None],
) -> Path:
    records: list[tuple[tarfile.TarInfo, bytes]] = []
    with tarfile.open(source, "r:gz") as archive:
        for member in archive.getmembers():
            extracted = archive.extractfile(member) if member.isfile() else None
            records.append((copy.copy(member), extracted.read() if extracted is not None else b""))
    mutation(records)
    with destination.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for member, data in records:
                    member.mtime = 0
                    member.uid = member.gid = 0
                    member.uname = member.gname = ""
                    if member.isfile():
                        member.size = len(data)
                        archive.addfile(member, __import__("io").BytesIO(data))
                    else:
                        member.size = 0
                        archive.addfile(member)
    return destination


def unpack_tar(bundle: Path, destination: Path) -> None:
    with tarfile.open(bundle, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                raise SelftestError(f"unexpected fixture tar member: {member.name}")
            target = destination / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            source = archive.extractfile(member)
            assert source is not None
            target.write_bytes(source.read())


def initialize_fixture(root: Path, source_root: Path) -> tuple[Path, dict[str, str], dict[str, Any]]:
    repo = root / "fixture-repo"
    repo.mkdir()
    run("git", "init", "-q", cwd=repo)
    run("git", "config", "user.name", "Cafe Selftest", cwd=repo)
    run("git", "config", "user.email", "cafe-selftest@example.invalid", cwd=repo)

    interiors = {
        "cafe": {
            "1f": {"furniture": [{"slot": "counter", "pos": [2, 3]}], "role": "public"},
            "2f": {"furniture": [{"slot": "bed", "pos": [4, 5]}], "role": "private"},
        }
    }
    write(repo / "game/data/interiors.json", json.dumps(interiors, indent=2) + "\n")
    write(
        repo / "game/scripts/WorldView.gd",
        "extends Node\nfunc draw_cafe(floor):\n\treturn ['counter', 'bed'][0 if floor == '1f' else 1]\n",
    )
    write(repo / "game/project.godot", "[application]\nconfig/name=\"Cafe selftest\"\n")

    leased = [
        ".github/workflows/trusted-cafe-attestation.yml",
        "evidence/cafe/runtime-lock.v1.json",
        "tools/cafe_attestation_selftest.py",
        "tools/cafe_authored_manifest.py",
        "tools/trusted_cafe_capture.sh",
        "tools/verify_cafe_attested_evidence.py",
        "tools/vg_shoot.sh",
    ]
    for rel in leased:
        source = source_root / rel
        if not source.is_file():
            raise SelftestError(f"selftest source dependency missing: {rel}")
        write(repo / rel, source.read_bytes())

    ids = {
        "schema": authored.IDS_SCHEMA,
        "space": "cafe",
        "floors": [
            {
                "floor": "1f",
                "normal_slot": "cafe_1f_normal",
                "bare_slot": "cafe_1f_bare",
                "source_ids": ["cafe.1f.semantic", "cafe.renderer"],
            },
            {
                "floor": "2f",
                "normal_slot": "cafe_2f_normal",
                "bare_slot": "cafe_2f_bare",
                "source_ids": ["cafe.2f.semantic", "cafe.renderer"],
            },
        ],
        "sources": [
            {
                "id": "cafe.1f.semantic",
                "path": "game/data/interiors.json",
                "kind": "json-pointer",
                "role": "semantic",
                "floors": ["1f"],
                "json_pointer": "/cafe/1f",
            },
            {
                "id": "cafe.2f.semantic",
                "path": "game/data/interiors.json",
                "kind": "json-pointer",
                "role": "semantic",
                "floors": ["2f"],
                "json_pointer": "/cafe/2f",
            },
            {
                "id": "cafe.renderer",
                "path": "game/scripts/WorldView.gd",
                "kind": "file",
                "role": "renderer",
                "floors": ["1f", "2f"],
            },
        ],
    }
    write(repo / "evidence/cafe/cafe-authored-ids.v1.json", canonical(ids))
    run("git", "add", "--", "game", ".github", "evidence", "tools", cwd=repo)
    run("git", "commit", "-q", "-m", "fixture source", cwd=repo)
    manifest = authored.compile_manifest(
        repo,
        repo / "evidence/cafe/cafe-authored-ids.v1.json",
        compiler_path=repo / "tools/cafe_authored_manifest.py",
    )
    write(repo / "evidence/cafe/cafe-authored-manifest.v1.json", authored.canonical_bytes(manifest))
    run("git", "add", "--", "evidence/cafe/cafe-authored-manifest.v1.json", cwd=repo)
    run("git", "commit", "-q", "-m", "fixture authored manifest", cwd=repo)
    context = {
        "repository": REPOSITORY,
        "candidate_sha": run("git", "rev-parse", "HEAD", cwd=repo),
        "candidate_tree": run("git", "show", "-s", "--format=%T", "HEAD", cwd=repo),
        "workflow_sha": run("git", "rev-parse", "HEAD", cwd=repo),
        "workflow_tree": run("git", "show", "-s", "--format=%T", "HEAD", cwd=repo),
        "run_id": RUN_ID,
        "run_attempt": RUN_ATTEMPT,
    }
    return repo, context, manifest


def build_bundle(root: Path, repo: Path, context: dict[str, str], authored_manifest: dict[str, Any]) -> Path:
    content = root / "bundle-content"
    content.mkdir()
    write(content / "authored/cafe-authored-ids.v1.json", (repo / "evidence/cafe/cafe-authored-ids.v1.json").read_bytes())
    write(content / "authored/cafe-authored-manifest.v1.json", (repo / "evidence/cafe/cafe-authored-manifest.v1.json").read_bytes())
    runtime_lock_path = repo / "evidence/cafe/runtime-lock.v1.json"
    runtime_lock = json.loads(runtime_lock_path.read_text(encoding="utf-8"))
    write(content / "runtime/runtime-lock.v1.json", runtime_lock_path.read_bytes())
    runtime_receipt = {
        "schema": verifier.RUNTIME_RECEIPT_SCHEMA,
        "lock_sha256": file_digest(runtime_lock_path),
        "runtime_archive_sha256": RUNTIME_ARCHIVE_SHA,
        "oci_manifest_digest": OCI_MANIFEST_SHA,
        "base_manifest_digest": runtime_lock["python_image"]["amd64_manifest_digest"],
        "python": runtime_lock["versions"]["python"],
        "pillow": runtime_lock["versions"]["pillow"],
        "godot": runtime_lock["versions"]["godot"],
        "podman": runtime_lock["host_tools"]["podman"],
        "buildah": runtime_lock["host_tools"]["buildah"],
        "skopeo": runtime_lock["host_tools"]["skopeo"],
        "gh": runtime_lock["host_tools"]["gh"],
        "validation_image": runtime_lock["validation_image"]["reference"],
        "validation_oci_manifest_digest": "c" * 64,
        "container_platform": runtime_lock["validation_image"]["platform"],
        "container_network": "none",
        "container_read_only": True,
        "container_cap_drop": "ALL",
        "container_no_new_privileges": True,
        "first_archive_sha256": RUNTIME_ARCHIVE_SHA,
        "second_archive_sha256": RUNTIME_ARCHIVE_SHA,
        "reproducible": True,
    }
    write(content / "runtime/runtime-build-receipt.json", canonical(runtime_receipt))
    for rel in (
        "logs/godot-capture.log",
        "logs/godot-import.log",
        "logs/xvfb-1280x768.log",
        "logs/xvfb-320x192.log",
    ):
        write(content / rel, b"")

    tool_records = []
    for rel in verifier.TRUSTED_TOOL_PATHS:
        source = repo / rel
        write(content / "trust-root" / rel, source.read_bytes())
        tool_records.append({"authority": "protected-master", "path": rel, "sha256": file_digest(source)})

    bindings = {item["floor"]: item["authored_binding_sha256"] for item in authored_manifest["floors"]}
    colors = {
        "cafe_1f_normal": (180, 80, 60, 255),
        "cafe_1f_bare": (80, 80, 60, 255),
        "cafe_2f_normal": (60, 120, 180, 255),
        "cafe_2f_bare": (60, 70, 80, 255),
    }
    receipt_records = []
    for viewport, (width, height) in verifier.VIEWPORTS.items():
        session = verifier._expected_session(context, viewport)
        captures = []
        for slot, (floor, mode, draw_skip, filename) in verifier.SLOTS.items():
            frame = png(width, height, colors[slot])
            write(content / viewport / filename, frame)
            argv = verifier.expected_argv(viewport, floor, mode, filename)
            captures.append(
                {
                    "slot": slot,
                    "file": filename,
                    "floor": floor,
                    "mode": mode,
                    "draw_skip": draw_skip,
                    "width": width,
                    "height": height,
                    "seed": 3,
                    "tick": 600,
                    "pair_id": verifier._expected_pair(session, floor, bindings[floor]),
                    "authored_binding_sha256": bindings[floor],
                    "argv": argv,
                    "argv_sha256": digest(json.dumps(argv, separators=(",", ":"), ensure_ascii=True).encode("ascii")),
                    "sha256": digest(frame),
                    "bytes": len(frame),
                }
            )
        receipt = {
            "schema": verifier.RECEIPT_SCHEMA,
            **context,
            "viewport": viewport,
            "session": session,
            "captures": captures,
        }
        receipt_path = content / viewport / "cafe-capture-receipt.json"
        write(receipt_path, canonical(receipt))
        receipt_records.append(
            {"path": f"{viewport}/cafe-capture-receipt.json", "sha256": file_digest(receipt_path), "viewport": viewport}
        )
    transcript = {
        "schema": verifier.TRANSCRIPT_SCHEMA,
        **context,
        "frame_count": 8,
        "receipts": receipt_records,
    }
    write(content / "capture-transcript.json", canonical(transcript))

    payloads = []
    actual_payloads = tuple(
        sorted(path.relative_to(content).as_posix() for path in content.rglob("*") if path.is_file())
    )
    if actual_payloads != verifier.EXPECTED_PAYLOAD_PATHS:
        raise SelftestError(
            f"fixture payload allowlist mismatch: {actual_payloads!r} != {verifier.EXPECTED_PAYLOAD_PATHS!r}"
        )
    for rel in verifier.EXPECTED_PAYLOAD_PATHS:
        path = content.joinpath(*rel.split("/"))
        raw = path.read_bytes()
        payloads.append({"path": rel, "sha256": digest(raw), "bytes": len(raw)})
    manifest = {
        "schema": verifier.BUNDLE_SCHEMA,
        "repository": REPOSITORY,
        "candidate": {"sha": context["candidate_sha"], "tree": context["candidate_tree"]},
        "workflow": {
            "sha": context["workflow_sha"],
            "tree": context["workflow_tree"],
            "path": verifier.WORKFLOW_PATH,
            "ref": f"{REPOSITORY}{verifier.WORKFLOW_REF_SUFFIX}",
        },
        "run": {"id": RUN_ID, "attempt": RUN_ATTEMPT},
        "runtime": {
            "lock_sha256": file_digest(runtime_lock_path),
            "archive_sha256": RUNTIME_ARCHIVE_SHA,
            "oci_manifest_digest": OCI_MANIFEST_SHA,
            "python": runtime_lock["versions"]["python"],
            "pillow": runtime_lock["versions"]["pillow"],
            "godot": runtime_lock["versions"]["godot"],
        },
        "authored": {
            "ids_sha256": file_digest(repo / "evidence/cafe/cafe-authored-ids.v1.json"),
            "manifest_sha256": file_digest(repo / "evidence/cafe/cafe-authored-manifest.v1.json"),
            "render_closure_sha256": authored_manifest["render_closure_sha256"],
            "game_tree_git_oid": authored_manifest["game_tree_git_oid"],
        },
        "capture_contract": {
            "space": "cafe",
            "viewports": ["1280x768", "320x192"],
            "seed": 3,
            "tick": 600,
            "renderer": "opengl3",
            "display": "x11/Xvfb",
            "audio": "Dummy",
            "slots": list(verifier.SLOTS),
            "frames": 8,
        },
        "tools": tool_records,
        "payloads": payloads,
        "evidence_only": True,
        "does_not_authorize": verifier.DOES_NOT_AUTHORIZE,
    }
    write(content / "trusted-cafe-manifest.json", canonical(manifest))
    first = root / "trusted-cafe-evidence.first.tar.gz"
    second = root / "trusted-cafe-evidence.second.tar.gz"
    make_tar(content, first)
    make_tar(content, second)
    if first.read_bytes() != second.read_bytes():
        raise SelftestError("canonical bundle double-run mismatch")
    bundle = root / "trusted-cafe-evidence.tar.gz"
    shutil.copyfile(first, bundle)
    return bundle


def attestation_for(bundle: Path, *, subject_sha: str | None = None, name: str | None = None) -> bytes:
    payload = [
        {
            "attestation": {"fixture": True},
            "verificationResult": {
                "statement": {
                    "predicateType": verifier.SLSA_PREDICATE,
                    "subject": [
                        {
                            "name": name or bundle.name,
                            "digest": {"sha256": subject_sha or file_digest(bundle)},
                        }
                    ],
                    "predicate": {},
                }
            },
        }
    ]
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def refresh_bundle_metadata(content: Path) -> None:
    receipt_records = []
    for viewport in verifier.VIEWPORTS:
        receipt_path = content / viewport / "cafe-capture-receipt.json"
        receipt_records.append(
            {"path": f"{viewport}/cafe-capture-receipt.json", "sha256": file_digest(receipt_path), "viewport": viewport}
        )
    transcript_path = content / "capture-transcript.json"
    transcript = json.loads(transcript_path.read_text(encoding="utf-8"))
    transcript["receipts"] = receipt_records
    write(transcript_path, canonical(transcript))

    manifest_path = content / "trusted-cafe-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    payloads = []
    for path in sorted(item for item in content.rglob("*") if item.is_file() and item != manifest_path):
        raw = path.read_bytes()
        payloads.append({"path": path.relative_to(content).as_posix(), "sha256": digest(raw), "bytes": len(raw)})
    manifest["payloads"] = payloads
    write(manifest_path, canonical(manifest))


def mutate_bundle(base: Path, root: Path, label: str, mutation: Callable[[Path], None], *, refresh: bool) -> Path:
    content = root / f"mut-{label}"
    content.mkdir()
    unpack_tar(base, content)
    mutation(content)
    if refresh:
        refresh_bundle_metadata(content)
    result = root / f"{label}.tar.gz"
    make_tar(content, result)
    return result


def expect_failure(label: str, action: Callable[[], Any], failures: list[str]) -> None:
    try:
        action()
    except (verifier.VerificationError, authored.ContractError, OSError, ValueError):
        failures.append(label)
        return
    raise SelftestError(f"negative control unexpectedly passed: {label}")


def execute(work: Path, source_root: Path) -> dict[str, Any]:
    repo, context, authored_manifest = initialize_fixture(work, source_root)
    compiled_authored_manifest = repo / "evidence/cafe/cafe-authored-manifest.v1.json"
    preverified_checkouts = work / "preverified-checkouts.json"
    write(
        preverified_checkouts,
        canonical(
            {
                "schema": verifier.PREVERIFIED_CHECKOUT_SCHEMA,
                "source": "host-read-only-git",
                "repository": context["repository"],
                "candidate": {
                    "sha": context["candidate_sha"],
                    "tree": context["candidate_tree"],
                    "clean": True,
                },
                "workflow": {
                    "sha": context["workflow_sha"],
                    "tree": context["workflow_tree"],
                    "clean": True,
                },
                "authored_manifest_sha256": file_digest(compiled_authored_manifest),
            }
        ),
    )
    bundle = build_bundle(work, repo, context, authored_manifest)
    positive_attestation = attestation_for(bundle)
    expected = dict(context)
    receipt = verifier.verify_bundle(
        bundle=bundle,
        candidate_root=repo,
        trusted_root=repo,
        expected=expected,
        runtime_archive_sha256=RUNTIME_ARCHIVE_SHA,
        attestation_runner=lambda *_: positive_attestation,
        preverified_checkouts=preverified_checkouts,
        compiled_authored_manifest=compiled_authored_manifest,
    )
    failures: list[str] = []

    workflow = (repo / verifier.WORKFLOW_PATH).read_text(encoding="utf-8")
    verifier.verify_budget_gate_contract(workflow)
    schema = "living-town.cafe-qualification-budget-receipt.v1"
    schema_at = workflow.index(schema)
    step_at = workflow.rfind("      - name: ", 0, schema_at)
    step_end = workflow.find("      - name: ", schema_at)
    step_end = len(workflow) if step_end < 0 else step_end
    budget_step = workflow[step_at:step_end]
    broken_step = budget_step.replace(
        "podman run --pull=never --rm --interactive",
        "podman run --pull=never --rm",
        1,
    )
    if broken_step == budget_step:
        raise SelftestError("budget stdin fixture mutation did not apply")
    expect_failure(
        "budget_stdin_loss",
        lambda: verifier.verify_budget_gate_contract(workflow[:step_at] + broken_step + workflow[step_end:]),
        failures,
    )

    interiors = repo / "game/data/interiors.json"
    original_interiors = interiors.read_bytes()
    interiors.write_bytes(original_interiors + b" \n")
    expect_failure(
        "stale_source_manifest",
        lambda: authored.compile_manifest(repo, repo / "evidence/cafe/cafe-authored-ids.v1.json"),
        failures,
    )
    interiors.write_bytes(original_interiors)
    plausible = repo / "game/scripts/plausible_alias.gd"
    plausible.write_text("extends Node\n", encoding="utf-8")
    expect_failure(
        "unauthored_plausible_source",
        lambda: authored.compile_manifest(repo, repo / "evidence/cafe/cafe-authored-ids.v1.json"),
        failures,
    )
    plausible.unlink()

    def verify_changed(changed: Path, *, attestation: bytes | None = positive_attestation, changed_expected=None) -> Any:
        return verifier.verify_bundle(
            bundle=changed,
            candidate_root=repo,
            trusted_root=repo,
            expected=changed_expected or expected,
            runtime_archive_sha256=RUNTIME_ARCHIVE_SHA,
            attestation_runner=lambda *_: attestation if attestation is not None else attestation_for(changed),
            preverified_checkouts=preverified_checkouts,
            compiled_authored_manifest=compiled_authored_manifest,
        )

    substituted = mutate_bundle(
        bundle,
        work,
        "substituted-normal",
        lambda c: (c / "1280x768/vg_int_cafe.png").write_bytes((c / "1280x768/vg_cafe1f_bare.png").read_bytes()),
        refresh=False,
    )
    expect_failure("substituted_normal", lambda: verify_changed(substituted), failures)

    def runtime_drift(c: Path) -> None:
        path = c / "runtime/runtime-build-receipt.json"
        value = json.loads(path.read_text(encoding="utf-8")); value["python"] = "3.11.15"
        write(path, canonical(value))
    expect_failure(
        "runtime_drift",
        lambda: verify_changed(mutate_bundle(bundle, work, "runtime-drift", runtime_drift, refresh=True)),
        failures,
    )

    expect_failure(
        "tool_drift",
        lambda: verify_changed(
            mutate_bundle(
                bundle,
                work,
                "tool-drift",
                lambda c: (c / "trust-root/tools/cafe_authored_manifest.py").write_bytes(b"drift\n"),
                refresh=True,
            )
        ),
        failures,
    )

    def crop(c: Path) -> None:
        frame = c / "1280x768/vg_int_cafe.png"
        replacement = png(1279, 768, (180, 80, 60, 255)); frame.write_bytes(replacement)
        receipt_path = c / "1280x768/cafe-capture-receipt.json"
        value = json.loads(receipt_path.read_text(encoding="utf-8"))
        value["captures"][0]["sha256"] = digest(replacement); value["captures"][0]["bytes"] = len(replacement)
        write(receipt_path, canonical(value))
    expect_failure(
        "crop_resize",
        lambda: verify_changed(mutate_bundle(bundle, work, "crop-resize", crop, refresh=True)),
        failures,
    )

    expect_failure(
        "byte_tamper",
        lambda: verify_changed(
            mutate_bundle(
                bundle,
                work,
                "byte-tamper",
                lambda c: (c / "320x192/vg_cafe2f_bare.png").write_bytes(
                    (c / "320x192/vg_cafe2f_bare.png").read_bytes()[:-1] + b"X"
                ),
                refresh=False,
            )
        ),
        failures,
    )

    def floor_swap(c: Path) -> None:
        for viewport in verifier.VIEWPORTS:
            left = c / viewport / "vg_int_cafe.png"; right = c / viewport / "vg_cafe2f.png"
            left_data, right_data = left.read_bytes(), right.read_bytes()
            left.write_bytes(right_data); right.write_bytes(left_data)
            receipt_path = c / viewport / "cafe-capture-receipt.json"
            value = json.loads(receipt_path.read_text(encoding="utf-8"))
            by_slot = {item["slot"]: item for item in value["captures"]}
            by_slot["cafe_1f_normal"]["sha256"] = digest(right_data); by_slot["cafe_1f_normal"]["bytes"] = len(right_data)
            by_slot["cafe_2f_normal"]["sha256"] = digest(left_data); by_slot["cafe_2f_normal"]["bytes"] = len(left_data)
            write(receipt_path, canonical(value))
    expect_failure(
        "floor_swap",
        lambda: verify_changed(mutate_bundle(bundle, work, "floor-swap", floor_swap, refresh=True)),
        failures,
    )

    def pair_mismatch(c: Path) -> None:
        path = c / "320x192/cafe-capture-receipt.json"
        value = json.loads(path.read_text(encoding="utf-8")); value["captures"][1]["pair_id"] = "c" * 64
        write(path, canonical(value))
    expect_failure(
        "normal_bare_pairing_mismatch",
        lambda: verify_changed(mutate_bundle(bundle, work, "pair-mismatch", pair_mismatch, refresh=True)),
        failures,
    )

    replay_expected = dict(expected); replay_expected["run_id"] = "9002"
    expect_failure("receipt_replay", lambda: verify_changed(bundle, changed_expected=replay_expected), failures)
    tree_expected = dict(expected); tree_expected["candidate_tree"] = "d" * 40
    expect_failure("candidate_tree_mismatch", lambda: verify_changed(bundle, changed_expected=tree_expected), failures)
    expect_failure(
        "wrong_workflow_attestation",
        lambda: verifier.verify_bundle(
            bundle=bundle,
            candidate_root=repo,
            trusted_root=repo,
            expected=expected,
            runtime_archive_sha256=RUNTIME_ARCHIVE_SHA,
            attestation_runner=lambda *_: (_ for _ in ()).throw(
                verifier.VerificationError("signer workflow mismatch")
            ),
            preverified_checkouts=preverified_checkouts,
            compiled_authored_manifest=compiled_authored_manifest,
        ),
        failures,
    )
    expect_failure("malformed_attestation", lambda: verify_changed(bundle, attestation=b"{"), failures)
    expect_failure(
        "attestation_subject_mismatch",
        lambda: verify_changed(bundle, attestation=attestation_for(bundle, subject_sha="e" * 64)),
        failures,
    )

    expect_failure(
        "missing_preverified_checkout",
        lambda: verifier.verify_bundle(
            bundle=bundle,
            candidate_root=repo,
            trusted_root=repo,
            expected=expected,
            runtime_archive_sha256=RUNTIME_ARCHIVE_SHA,
            attestation_runner=lambda *_: positive_attestation,
            preverified_checkouts=None,
            compiled_authored_manifest=compiled_authored_manifest,
        ),
        failures,
    )
    inconsistent_preverified = work / "inconsistent-preverified-checkouts.json"
    inconsistent = json.loads(preverified_checkouts.read_text(encoding="utf-8"))
    inconsistent["candidate"]["tree"] = "d" * 40
    write(inconsistent_preverified, canonical(inconsistent))
    expect_failure(
        "inconsistent_preverified_checkout",
        lambda: verifier.verify_bundle(
            bundle=bundle,
            candidate_root=repo,
            trusted_root=repo,
            expected=expected,
            runtime_archive_sha256=RUNTIME_ARCHIVE_SHA,
            attestation_runner=lambda *_: positive_attestation,
            preverified_checkouts=inconsistent_preverified,
            compiled_authored_manifest=compiled_authored_manifest,
        ),
        failures,
    )

    def add_named_extra(label: str, name: str) -> None:
        expect_failure(
            label,
            lambda: (
                lambda changed: verify_changed(changed, attestation=attestation_for(changed))
            )(
                mutate_bundle(
                    bundle,
                    work,
                    label,
                    lambda content: write(content / name, b"unexpected\n"),
                    refresh=True,
                )
            ),
            failures,
        )

    add_named_extra("arbitrary_extra_payload", "arbitrary-extra.txt")

    def mutated_member(
        label: str,
        mutator: Callable[[list[tuple[tarfile.TarInfo, bytes]]], None],
    ) -> None:
        changed = rewrite_tar(bundle, work / f"{label}.tar.gz", mutator)
        expect_failure(
            label,
            lambda: verify_changed(changed, attestation=attestation_for(changed)),
            failures,
        )

    def duplicate(records: list[tuple[tarfile.TarInfo, bytes]]) -> None:
        records.append((copy.copy(records[0][0]), records[0][1]))

    mutated_member("duplicate_archive_member", duplicate)

    def rename_first(name: str) -> Callable[[list[tuple[tarfile.TarInfo, bytes]]], None]:
        def mutate(records: list[tuple[tarfile.TarInfo, bytes]]) -> None:
            records[0][0].name = name

        return mutate

    def rename_named(
        old: str, new: str
    ) -> Callable[[list[tuple[tarfile.TarInfo, bytes]]], None]:
        def mutate(records: list[tuple[tarfile.TarInfo, bytes]]) -> None:
            matches = [member for member, _ in records if member.name == old]
            if len(matches) != 1:
                raise SelftestError(f"archive fixture member mismatch for {old}: {len(matches)}")
            matches[0].name = new

        return mutate

    mutated_member("canonicalization_ambiguity", rename_first("1280x768//vg_int_cafe.png"))
    mutated_member(
        "case_only_payload_name",
        rename_named("runtime/runtime-lock.v1.json", "Runtime/runtime-lock.v1.json"),
    )
    mutated_member(
        "unicode_lookalike_payload_name",
        rename_named(
            "runtime/runtime-lock.v1.json",
            "runtime/runtime-lock.v1.jso\N{CYRILLIC SMALL LETTER EN}",
        ),
    )
    mutated_member(
        "trust_root_lookalike_payload_name",
        rename_named(
            "trust-root/tools/verify_cafe_attested_evidence.py",
            "trust‐root/tools/verify_cafe_attested_evidence.py",
        ),
    )
    mutated_member(
        "newline_payload_name",
        rename_named("logs/godot-capture.log", "logs/godot-capture\n.log"),
    )
    mutated_member("dot_archive_path_variant", rename_first("./1280x768/vg_int_cafe.png"))
    mutated_member("parent_archive_path_variant", rename_first("../1280x768/vg_int_cafe.png"))
    mutated_member("backslash_archive_path_variant", rename_first("1280x768\\vg_int_cafe.png"))

    def link_member(link_type: bytes) -> Callable[[list[tuple[tarfile.TarInfo, bytes]]], None]:
        def mutate(records: list[tuple[tarfile.TarInfo, bytes]]) -> None:
            records[0][0].type = link_type
            records[0][0].linkname = "trusted-cafe-manifest.json"

        return mutate

    mutated_member("symlink_archive_member", link_member(tarfile.SYMTYPE))
    mutated_member("hardlink_archive_member", link_member(tarfile.LNKTYPE))

    def high_expansion(content: Path) -> None:
        frame = content / "1280x768/vg_int_cafe.png"
        replacement = png(2048, 2048, (0, 0, 0, 0))
        frame.write_bytes(replacement)
        receipt_path = content / "1280x768/cafe-capture-receipt.json"
        value = json.loads(receipt_path.read_text(encoding="utf-8"))
        value["captures"][0]["sha256"] = digest(replacement)
        value["captures"][0]["bytes"] = len(replacement)
        write(receipt_path, canonical(value))

    expect_failure(
        "high_expansion_png",
        lambda: (
            lambda changed: verify_changed(changed, attestation=attestation_for(changed))
        )(mutate_bundle(bundle, work, "high-expansion-png", high_expansion, refresh=True)),
        failures,
    )

    width, height = 1280, 768
    row = b"\0" + bytes((180, 80, 60, 255)) * width
    scanlines = row * height

    def malformed_scanlines(label: str, replacement: bytes) -> None:
        def mutation(content: Path) -> None:
            frame = content / "1280x768/vg_int_cafe.png"
            frame.write_bytes(replacement)
            receipt_path = content / "1280x768/cafe-capture-receipt.json"
            value = json.loads(receipt_path.read_text(encoding="utf-8"))
            value["captures"][0]["sha256"] = digest(replacement)
            value["captures"][0]["bytes"] = len(replacement)
            write(receipt_path, canonical(value))

        expect_failure(
            label,
            lambda: (
                lambda changed: verify_changed(changed, attestation=attestation_for(changed))
            )(mutate_bundle(bundle, work, label, mutation, refresh=True)),
            failures,
        )

    malformed_scanlines("zero_decoded_scanlines_png", png_from_scanlines(width, height, b""))
    malformed_scanlines("truncated_scanlines_png", png_from_scanlines(width, height, scanlines[:-1]))
    malformed_scanlines("excess_scanlines_png", png_from_scanlines(width, height, scanlines + b"\0"))
    malformed_scanlines(
        "invalid_filter_png",
        png_from_scanlines(width, height, b"\x05" + scanlines[1:]),
    )
    malformed_scanlines(
        "interlaced_png",
        png_from_scanlines(width, height, scanlines, interlace=1),
    )

    required = {
        "stale_source_manifest",
        "unauthored_plausible_source",
        "substituted_normal",
        "runtime_drift",
        "tool_drift",
        "crop_resize",
        "byte_tamper",
        "floor_swap",
        "normal_bare_pairing_mismatch",
        "receipt_replay",
        "candidate_tree_mismatch",
        "wrong_workflow_attestation",
        "malformed_attestation",
        "attestation_subject_mismatch",
        "missing_preverified_checkout",
        "inconsistent_preverified_checkout",
        "arbitrary_extra_payload",
        "case_only_payload_name",
        "unicode_lookalike_payload_name",
        "trust_root_lookalike_payload_name",
        "newline_payload_name",
        "duplicate_archive_member",
        "canonicalization_ambiguity",
        "dot_archive_path_variant",
        "parent_archive_path_variant",
        "backslash_archive_path_variant",
        "symlink_archive_member",
        "hardlink_archive_member",
        "high_expansion_png",
        "budget_stdin_loss",
        "zero_decoded_scanlines_png",
        "truncated_scanlines_png",
        "excess_scanlines_png",
        "invalid_filter_png",
        "interlaced_png",
    }
    if set(failures) != required:
        raise SelftestError(f"negative control coverage mismatch: {sorted(failures)}")
    return {
        "schema": "living-town.cafe-attestation-selftest-receipt.v1",
        "bundle_sha256": file_digest(bundle),
        "compiled_manifest_sha256": file_digest(repo / "evidence/cafe/cafe-authored-manifest.v1.json"),
        "verification_receipt_sha256": digest(canonical(receipt)),
        "negative_controls": sorted(failures),
        "negative_control_count": len(failures),
        "deterministic_double_run": True,
        "passed": True,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, help="new/existing empty directory outside the repository")
    parser.add_argument("--receipt", type=Path, help="optional receipt output path outside the repository")
    args = parser.parse_args(argv)
    source_root = Path(__file__).resolve().parent.parent
    try:
        if args.work_dir:
            work = args.work_dir.resolve()
            work.mkdir(parents=True, exist_ok=True)
            if any(work.iterdir()):
                raise SelftestError(f"work directory must be empty: {work}")
            result = execute(work, source_root)
        else:
            with tempfile.TemporaryDirectory(prefix="cafe-attestation-selftest-") as temporary:
                result = execute(Path(temporary), source_root)
        encoded = canonical(result)
        if args.receipt:
            args.receipt.parent.mkdir(parents=True, exist_ok=True)
            args.receipt.write_bytes(encoded)
        sys.stdout.buffer.write(encoded)
    except (SelftestError, verifier.VerificationError, authored.ContractError, OSError, ValueError) as exc:
        print(f"CAFE_ATTESTATION_SELFTEST FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
