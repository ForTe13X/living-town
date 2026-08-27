#!/usr/bin/env python3
"""Independently verify a protected cafe evidence bundle and GitHub attestation."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unicodedata
import zlib
from pathlib import Path, PurePosixPath
from typing import Any, Callable

BUNDLE_SCHEMA = "living-town.trusted-cafe-evidence.v1"
RECEIPT_SCHEMA = "living-town.trusted-cafe-capture-receipt.v1"
TRANSCRIPT_SCHEMA = "living-town.trusted-cafe-capture-transcript.v1"
RUNTIME_LOCK_SCHEMA = "living-town.cafe-runtime-lock.v1"
RUNTIME_RECEIPT_SCHEMA = "living-town.cafe-runtime-build-receipt.v1"
PREVERIFIED_CHECKOUT_SCHEMA = "living-town.cafe-preverified-checkouts.v1"
WORKFLOW_PATH = ".github/workflows/trusted-cafe-attestation.yml"
WORKFLOW_REF_SUFFIX = f"/{WORKFLOW_PATH}@refs/heads/master"
SLSA_PREDICATE = "https://slsa.dev/provenance/v1"
HEX_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_RE = re.compile(r"^[0-9a-f]{40}$")
RUN_ID_RE = re.compile(r"^[1-9][0-9]{0,19}$")
VIEWPORTS = {"1280x768": (1280, 768), "320x192": (320, 192)}
SLOTS = {
    "cafe_1f_normal": ("1f", "normal", "none", "vg_int_cafe.png"),
    "cafe_1f_bare": ("1f", "bare", "interior_furniture", "vg_cafe1f_bare.png"),
    "cafe_2f_normal": ("2f", "normal", "none", "vg_cafe2f.png"),
    "cafe_2f_bare": ("2f", "bare", "interior_furniture", "vg_cafe2f_bare.png"),
}
TRUSTED_TOOL_PATHS = (
    WORKFLOW_PATH,
    "evidence/cafe/runtime-lock.v1.json",
    "tools/cafe_attestation_selftest.py",
    "tools/cafe_authored_manifest.py",
    "tools/trusted_cafe_capture.sh",
    "tools/verify_cafe_attested_evidence.py",
    "tools/vg_shoot.sh",
)
EXPECTED_PAYLOAD_PATHS = tuple(
    sorted(
        (
            "authored/cafe-authored-ids.v1.json",
            "authored/cafe-authored-manifest.v1.json",
            "capture-transcript.json",
            "logs/godot-capture.log",
            "logs/godot-import.log",
            "logs/xvfb-1280x768.log",
            "logs/xvfb-320x192.log",
            "runtime/runtime-build-receipt.json",
            "runtime/runtime-lock.v1.json",
            *(f"trust-root/{path}" for path in TRUSTED_TOOL_PATHS),
            *(
                f"{viewport}/{filename}"
                for viewport in VIEWPORTS
                for _, _, _, filename in SLOTS.values()
            ),
            *(f"{viewport}/cafe-capture-receipt.json" for viewport in VIEWPORTS),
        )
    )
)
EXPECTED_BUNDLE_MEMBERS = tuple(sorted((*EXPECTED_PAYLOAD_PATHS, "trusted-cafe-manifest.json")))
MAX_PNG_DECOMPRESSED_BYTES = 8 * 1024 * 1024
OCI_TOOLCHAIN_IMAGE = "quay.io/podman/stable@sha256:e90073d89870417f7bd0f581eed1ee6ddd8e55f0246a746516fd11059eac3335"
SKOPEO_TOOLCHAIN_IMAGE = "quay.io/skopeo/stable@sha256:572747e168b4cb920bc7f5b321ca6c6da13717ff28c8d671a203935d53cf1089"
ATTESTATION_BOOTSTRAP_IMAGE = "docker.io/library/python@sha256:2fc9207f64226cb05ac317cee0bab6fa55a9ea311ce5a086baddd4b4a83c2d3c"
DOES_NOT_AUTHORIZE = [
    "canon",
    "collision",
    "navigation",
    "pixels",
    "portals",
    "replay",
    "save",
    "simulation",
    "view",
]


class VerificationError(ValueError):
    """A fail-closed evidence or provenance violation."""


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise VerificationError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json_bytes(data: bytes, where: str) -> Any:
    try:
        text = data.decode("utf-8")
        return json.loads(
            text,
            object_pairs_hook=_reject_duplicates,
            parse_constant=lambda value: (_ for _ in ()).throw(
                VerificationError(f"non-finite JSON number in {where}: {value}")
            ),
        )
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise VerificationError(f"malformed UTF-8 JSON in {where}: {exc}") from exc


def load_json_file(path: Path) -> Any:
    try:
        return load_json_bytes(path.read_bytes(), str(path))
    except OSError as exc:
        raise VerificationError(f"cannot read {path}: {exc}") from exc


def canonical_bytes(value: Any) -> bytes:
    try:
        return (
            json.dumps(
                value,
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=True,
                allow_nan=False,
            )
            + "\n"
        ).encode("ascii")
    except (TypeError, ValueError) as exc:
        raise VerificationError(f"non-canonical JSON value: {exc}") from exc


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def exact_keys(value: Any, expected: set[str], where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise VerificationError(f"{where} must be an object")
    actual = set(value)
    if actual != expected:
        raise VerificationError(
            f"{where} keys mismatch; missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
        )
    return value


def require_hex(value: Any, where: str, *, git: bool = False) -> str:
    pattern = GIT_RE if git else HEX_RE
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise VerificationError(f"{where} is not a canonical digest")
    return value


def verify_preverified_checkouts(
    path: Path | None,
    expected: dict[str, str],
    compiled_authored_sha256: str,
) -> None:
    if path is None:
        raise VerificationError("explicit preverified-checkout contract is required")
    try:
        raw = path.resolve(strict=True).read_bytes()
    except OSError as exc:
        raise VerificationError(f"cannot read preverified-checkout contract: {exc}") from exc
    contract = load_json_bytes(raw, "preverified-checkout contract")
    if canonical_bytes(contract) != raw:
        raise VerificationError("preverified-checkout contract is not canonical")
    exact_keys(
        contract,
        {"schema", "source", "repository", "candidate", "workflow", "authored_manifest_sha256"},
        "preverified-checkout contract",
    )
    candidate = exact_keys(contract["candidate"], {"sha", "tree", "clean"}, "preverified candidate")
    workflow = exact_keys(contract["workflow"], {"sha", "tree", "clean"}, "preverified workflow")
    if contract["schema"] != PREVERIFIED_CHECKOUT_SCHEMA:
        raise VerificationError("preverified-checkout schema mismatch")
    if contract["source"] != "host-read-only-git" or contract["repository"] != expected["repository"]:
        raise VerificationError("preverified-checkout source/repository mismatch")
    if candidate != {
        "sha": expected["candidate_sha"],
        "tree": expected["candidate_tree"],
        "clean": True,
    }:
        raise VerificationError("preverified candidate identity/cleanliness mismatch")
    if workflow != {
        "sha": expected["workflow_sha"],
        "tree": expected["workflow_tree"],
        "clean": True,
    }:
        raise VerificationError("preverified workflow identity/cleanliness mismatch")
    if contract["authored_manifest_sha256"] != compiled_authored_sha256:
        raise VerificationError("preverified authored-manifest digest mismatch")


def verify_action_pins(trusted_root: Path, runtime_lock: dict[str, Any]) -> None:
    workflow_path = trusted_root / WORKFLOW_PATH
    try:
        workflow = workflow_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise VerificationError(f"cannot read protected workflow: {exc}") from exc
    actions = {
        "attest_build_provenance": "actions/attest-build-provenance",
        "checkout": "actions/checkout",
        "upload_artifact": "actions/upload-artifact",
    }
    for lock_key, action_name in actions.items():
        pin = runtime_lock.get("actions", {}).get(lock_key)
        require_hex(pin, f"runtime lock action pin {lock_key}", git=True)
        found = re.findall(rf"uses:\s*{re.escape(action_name)}@([^\s#]+)", workflow)
        if not found or set(found) != {pin}:
            raise VerificationError(f"workflow action pin drift for {action_name}: {found}")
    verify_budget_gate_contract(workflow)


def verify_budget_gate_contract(workflow: str) -> None:
    schemas = {
        "living-town.cafe-qualification-budget-receipt.v1",
        "living-town.cafe-protected-budget-receipt.v1",
    }
    steps = re.split(r"(?m)^      - name: ", workflow)
    for schema in schemas:
        matches = [step for step in steps if schema in step]
        if len(matches) != 1:
            raise VerificationError(f"workflow budget gate missing or duplicated: {schema}")
        step = matches[0]
        required = (
            "podman run --pull=never --rm --interactive",
            "python -B -",
            "stdin-loss-negative-control",
            'test -s "$receipt"',
        )
        if any(fragment not in step for fragment in required):
            raise VerificationError(f"workflow budget stdin/receipt gate drift: {schema}")


def verify_oci_toolchain_contract(trusted_root: Path, runtime_lock: dict[str, Any]) -> None:
    toolchain = exact_keys(
        runtime_lock.get("oci_toolchain"),
        {"archive_contract", "platform", "podman_image", "skopeo_image", "versions"},
        "OCI toolchain",
    )
    archive = exact_keys(
        toolchain["archive_contract"],
        {"format", "group", "mtime", "numeric_owner", "owner", "sort", "strip_pax_times"},
        "OCI archive contract",
    )
    versions = exact_keys(
        toolchain["versions"],
        {"podman", "python", "sha256sum", "skopeo", "tar"},
        "OCI toolchain versions",
    )
    if toolchain["platform"] != "linux/amd64" or toolchain["podman_image"] != OCI_TOOLCHAIN_IMAGE:
        raise VerificationError("OCI Podman toolchain image/platform drift or unpinned reference")
    if toolchain["skopeo_image"] != SKOPEO_TOOLCHAIN_IMAGE:
        raise VerificationError("OCI Skopeo toolchain image drift or unpinned reference")
    if archive != {
        "format": "posix",
        "group": 0,
        "mtime": 0,
        "numeric_owner": True,
        "owner": 0,
        "sort": "name",
        "strip_pax_times": True,
    }:
        raise VerificationError("canonical OCI tar contract drift")
    if versions != {
        "podman": "5.8.4",
        "python": "3.14.7",
        "sha256sum": "sha256sum (GNU coreutils) 9.10",
        "skopeo": "1.22.2",
        "tar": "tar (GNU tar) 1.35",
    }:
        raise VerificationError("OCI toolchain binary identity drift")
    bootstrap = exact_keys(
        runtime_lock.get("attestation_bootstrap_image"),
        {"platform", "reference"},
        "attestation bootstrap image",
    )
    if bootstrap != {"platform": "linux/amd64", "reference": ATTESTATION_BOOTSTRAP_IMAGE}:
        raise VerificationError("attestation bootstrap image drift or unpinned reference")
    script = (trusted_root / "tools/trusted_cafe_capture.sh").read_text(encoding="utf-8")
    required = (
        OCI_TOOLCHAIN_IMAGE,
        "docker run --pull=always --rm --privileged --platform linux/amd64",
        "CAFE_OCI_TOOLCHAIN_ACTIVE=1",
        'p["oci_toolchain"]["skopeo_image"]',
        '--entrypoint sh "$skopeo_image"',
        'skopeo inspect --raw "$1"',
        "--sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner",
        "--format=posix --pax-option=delete=atime,delete=ctime",
    )
    if any(fragment not in script for fragment in required):
        raise VerificationError("containerized OCI build/archive contract drift")


def verify_protected_bootstrap_contract(workflow: str) -> None:
    marker = "  protected_capture_and_attestation:"
    if marker not in workflow:
        raise VerificationError("protected workflow job missing")
    protected = workflow[workflow.index(marker) :]
    bootstrap_name = "      - name: Verify archive attestations before subject load in pinned bootstrap"
    load_name = "      - name: Load the attested exact-digest subjects"
    if protected.count(bootstrap_name) != 1 or protected.count(load_name) != 1:
        raise VerificationError("protected bootstrap/load steps missing or duplicated")
    bootstrap_at, load_at = protected.index(bootstrap_name), protected.index(load_name)
    if bootstrap_at >= load_at:
        raise VerificationError("archive attestation verification occurs after subject load")
    bootstrap_step = protected[bootstrap_at:load_at]
    required = (
        ATTESTATION_BOOTSTRAP_IMAGE,
        "--env GH_TOKEN",
        "--archive-bootstrap",
        "archive-bootstrap-receipt.json",
        "subject_load_count_before_verification",
    )
    if any(fragment not in bootstrap_step for fragment in required):
        raise VerificationError("archive attestation bootstrap contract drift")
    load_end = protected.find("      - name: ", load_at + len(load_name))
    load_step = protected[load_at:] if load_end < 0 else protected[load_at:load_end]
    receipt_gate = 'test -s "$RUNNER_TEMP/cafe-runtime-verification/archive-bootstrap-receipt.json"'
    if receipt_gate not in load_step or "podman load" not in load_step:
        raise VerificationError("subject load is not gated by the bootstrap receipt")
    if load_step.index(receipt_gate) > load_step.index("podman load"):
        raise VerificationError("subject load precedes bootstrap receipt gate")
    steps = re.split(r"(?m)^      - name: ", protected)
    token_steps = [step for step in steps if "GH_TOKEN" in step]
    if not token_steps:
        raise VerificationError("attestation bootstrap token step missing")
    for step in token_steps:
        if ATTESTATION_BOOTSTRAP_IMAGE not in step or "$RUNTIME_REF" in step or "$VALIDATION_REF" in step:
            raise VerificationError("GH_TOKEN is exposed outside the digest-pinned bootstrap")


def inspect_png(data: bytes, where: str) -> tuple[int, int]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise VerificationError(f"{where} is not a PNG")
    offset = 8
    chunks: list[tuple[bytes, bytes]] = []
    saw_iend = False
    saw_ihdr = False
    saw_idat = False
    ended_idat = False
    saw_plte = False
    known_critical = {b"IHDR", b"PLTE", b"IDAT", b"IEND"}
    while offset < len(data):
        if len(data) - offset < 12:
            raise VerificationError(f"{where} has a truncated PNG chunk")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise VerificationError(f"{where} has a truncated PNG payload")
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : end])[0]
        actual_crc = binascii.crc32(chunk_type + payload) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise VerificationError(f"{where} has a bad PNG CRC")
        if len(chunk_type) != 4 or any(not (65 <= byte <= 90 or 97 <= byte <= 122) for byte in chunk_type):
            raise VerificationError(f"{where} has an invalid PNG chunk type")
        if not (chunk_type[0] & 0x20) and chunk_type not in known_critical:
            raise VerificationError(f"{where} has unknown critical PNG chunk {chunk_type!r}")
        if chunk_type == b"IHDR":
            if saw_ihdr or chunks:
                raise VerificationError(f"{where} has duplicate or non-first IHDR")
            saw_ihdr = True
        elif not saw_ihdr:
            raise VerificationError(f"{where} does not begin with IHDR")
        if chunk_type == b"PLTE":
            if saw_plte or saw_idat or not payload or len(payload) % 3 or len(payload) > 768:
                raise VerificationError(f"{where} has invalid or misplaced PLTE")
            saw_plte = True
        elif chunk_type == b"IDAT":
            if ended_idat:
                raise VerificationError(f"{where} has noncontiguous IDAT chunks")
            saw_idat = True
        elif saw_idat and chunk_type != b"IEND":
            ended_idat = True
        if chunk_type == b"IEND" and payload:
            raise VerificationError(f"{where} has nonempty IEND")
        chunks.append((chunk_type, payload))
        offset = end
        if chunk_type == b"IEND":
            saw_iend = True
            break
    if not saw_iend or offset != len(data):
        raise VerificationError(f"{where} has no terminal IEND or has trailing bytes")
    if not saw_ihdr or not chunks or chunks[0][0] != b"IHDR" or len(chunks[0][1]) != 13:
        raise VerificationError(f"{where} has an invalid IHDR")
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", chunks[0][1]
    )
    if (
        width < 1
        or height < 1
        or bit_depth != 8
        or color_type != 6
        or compression != 0
        or filtering != 0
        or interlace != 0
    ):
        raise VerificationError(f"{where} has unsupported PNG geometry/encoding")
    row_bytes = width * 4
    decoded_size = height * (row_bytes + 1)
    if decoded_size > MAX_PNG_DECOMPRESSED_BYTES:
        raise VerificationError(
            f"{where} exceeds the {MAX_PNG_DECOMPRESSED_BYTES}-byte PNG expansion limit"
        )
    idat = b"".join(payload for kind, payload in chunks if kind == b"IDAT")
    if not saw_idat or not idat:
        raise VerificationError(f"{where} has no IDAT")
    try:
        decompressor = zlib.decompressobj()
        decoded = decompressor.decompress(idat, decoded_size + 1)
        if len(decoded) > decoded_size or decompressor.unconsumed_tail:
            raise VerificationError(
                f"{where} has excess decoded PNG scanline bytes"
            )
        decoded += decompressor.flush(decoded_size + 1 - len(decoded))
        if len(decoded) != decoded_size:
            raise VerificationError(f"{where} has truncated or excess decoded PNG scanlines")
        if not decompressor.eof or decompressor.unused_data:
            raise VerificationError(f"{where} has incomplete or trailing PNG image data")
    except zlib.error as exc:
        raise VerificationError(f"{where} has corrupt PNG image data: {exc}") from exc
    for row in range(height):
        filter_type = decoded[row * (row_bytes + 1)]
        if filter_type > 4:
            raise VerificationError(f"{where} has invalid PNG scanline filter {filter_type}")
    return width, height


def _canonical_archive_name(name: str) -> str:
    try:
        encoded = name.encode("ascii")
    except UnicodeEncodeError as exc:
        raise VerificationError(f"non-ASCII bundle path: {name!r}") from exc
    if not encoded or any(byte < 0x20 or byte == 0x7F for byte in encoded):
        raise VerificationError(f"control character in bundle path: {name!r}")
    if unicodedata.normalize("NFC", name) != name:
        raise VerificationError(f"non-canonical Unicode bundle path: {name!r}")
    pure = PurePosixPath(name)
    if (
        pure.is_absolute()
        or not pure.parts
        or ".." in pure.parts
        or "\\" in name
        or ":" in name
        or name != pure.as_posix()
        or name.startswith("./")
    ):
        raise VerificationError(f"unsafe bundle path: {name!r}")
    return name


def safe_extract(bundle: Path, destination: Path) -> list[str]:
    names: list[str] = []
    total = 0
    try:
        with tarfile.open(bundle, "r:gz") as archive:
            members = archive.getmembers()
            if len(members) != len(EXPECTED_BUNDLE_MEMBERS):
                raise VerificationError(
                    f"bundle member count mismatch: {len(members)} != {len(EXPECTED_BUNDLE_MEMBERS)}"
                )
            for member in members:
                _canonical_archive_name(member.name)
                if member.name in names:
                    raise VerificationError(f"duplicate bundle member: {member.name}")
                if not member.isfile():
                    raise VerificationError(f"bundle member is not a regular file: {member.name}")
                if member.size < 0 or member.size > 100 * 1024 * 1024:
                    raise VerificationError(f"bundle member size is invalid: {member.name}")
                total += member.size
                if total > 250 * 1024 * 1024:
                    raise VerificationError("bundle exceeds the 250 MiB limit")
                names.append(member.name)
            if tuple(sorted(names)) != EXPECTED_BUNDLE_MEMBERS:
                actual = set(names)
                expected = set(EXPECTED_BUNDLE_MEMBERS)
                raise VerificationError(
                    "bundle member allowlist mismatch: "
                    f"missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
                )
            for member in members:
                target = destination.joinpath(*PurePosixPath(member.name).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise VerificationError(f"cannot extract {member.name}")
                with target.open("xb") as output:
                    shutil.copyfileobj(source, output)
    except (OSError, tarfile.TarError) as exc:
        raise VerificationError(f"malformed evidence archive: {exc}") from exc
    return sorted(names)


def expected_argv(viewport: str, floor: str, mode: str, filename: str) -> list[str]:
    args = [
        "godot",
        "--path",
        "<candidate-game-copy>",
        "--display-driver",
        "x11",
        "--rendering-driver",
        "opengl3",
        "--audio-driver",
        "Dummy",
        "--resolution",
        viewport,
        "--single-window",
        "--",
        "--backend",
        "logic",
        "--seed",
        "3",
        "--warmup-tick",
        "600",
        "--probe-space",
        "cafe",
        "--probe-floor",
        floor,
        "--shot-fit",
    ]
    if mode == "bare":
        args += ["--draw-skip", "interior_furniture"]
    return args + ["--shot", f"<output>/{viewport}/{filename}"]


def _expected_session(context: dict[str, str], viewport: str) -> str:
    material = "\0".join(
        [
            context["repository"],
            context["candidate_sha"],
            context["candidate_tree"],
            context["workflow_sha"],
            context["workflow_tree"],
            context["run_id"],
            context["run_attempt"],
            viewport,
        ]
    ).encode("ascii")
    return hashlib.sha256(material).hexdigest()


def _expected_pair(session: str, floor: str, authored_binding: str) -> str:
    return hashlib.sha256(f"{session}\0{floor}\0{authored_binding}".encode("ascii")).hexdigest()


def validate_attestation_output(data: bytes, bundle_sha256: str, bundle_name: str) -> dict[str, Any]:
    result = load_json_bytes(data, "gh attestation verification output")
    if not isinstance(result, list) or not result:
        raise VerificationError("gh returned no verified build-provenance attestation")
    matches: list[dict[str, Any]] = []
    for index, item in enumerate(result):
        if not isinstance(item, dict) or not isinstance(item.get("verificationResult"), dict):
            raise VerificationError(f"gh result[{index}] is malformed")
        statement = item["verificationResult"].get("statement")
        if not isinstance(statement, dict) or statement.get("predicateType") != SLSA_PREDICATE:
            continue
        subjects = statement.get("subject")
        if not isinstance(subjects, list):
            raise VerificationError(f"gh result[{index}] has malformed subjects")
        for subject in subjects:
            if not isinstance(subject, dict) or not isinstance(subject.get("digest"), dict):
                continue
            if subject["digest"].get("sha256") == bundle_sha256 and subject.get("name") in (
                bundle_name,
                f"./{bundle_name}",
            ):
                matches.append(item)
    if len(matches) != 1:
        raise VerificationError(f"expected exactly one verified attestation subject, found {len(matches)}")
    return matches[0]


def verify_archive_bootstrap(
    *,
    runtime_archive: Path,
    runtime_attestation: bytes,
    validation_archive: Path,
    validation_attestation: bytes,
    repository: str,
    workflow_sha: str,
    receipt_output: Path | None = None,
) -> dict[str, Any]:
    if repository.count("/") != 1:
        raise VerificationError("archive bootstrap repository is invalid")
    require_hex(workflow_sha, "archive bootstrap workflow SHA", git=True)
    archives = []
    for role, path, attestation_raw in (
        ("runtime", runtime_archive.resolve(strict=True), runtime_attestation),
        ("validation", validation_archive.resolve(strict=True), validation_attestation),
    ):
        value = sha256_file(path)
        attestation = validate_attestation_output(attestation_raw, value, path.name)
        archives.append(
            {
                "bytes": path.stat().st_size,
                "name": path.name,
                "role": role,
                "sha256": value,
                "predicate_type": attestation["verificationResult"]["statement"]["predicateType"],
            }
        )
    if archives[0]["sha256"] == archives[1]["sha256"]:
        raise VerificationError("runtime and validation archive subjects must be distinct")
    receipt = {
        "archives": archives,
        "repository": repository,
        "schema": "living-town.cafe-archive-bootstrap-receipt.v1",
        "subject_load_count_before_verification": 0,
        "subject_token_exposed": False,
        "verified": True,
        "workflow_sha": workflow_sha,
    }
    if receipt_output is not None:
        receipt_output.parent.mkdir(parents=True, exist_ok=True)
        temporary = receipt_output.with_name(f".{receipt_output.name}.{os.getpid()}.tmp")
        try:
            temporary.write_bytes(canonical_bytes(receipt))
            os.replace(temporary, receipt_output)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
    return receipt


def run_github_attestation(
    bundle: Path,
    repository: str,
    workflow_sha: str,
    gh_bin: str,
) -> bytes:
    signer_workflow = f"{repository}/{WORKFLOW_PATH}"
    command = [
        gh_bin,
        "attestation",
        "verify",
        str(bundle),
        "--repo",
        repository,
        "--signer-workflow",
        signer_workflow,
        "--signer-digest",
        workflow_sha,
        "--source-digest",
        workflow_sha,
        "--source-ref",
        "refs/heads/master",
        "--cert-oidc-issuer",
        "https://token.actions.githubusercontent.com",
        "--deny-self-hosted-runners",
        "--predicate-type",
        SLSA_PREDICATE,
        "--format",
        "json",
    ]
    try:
        completed = subprocess.run(command, check=False, capture_output=True)
    except OSError as exc:
        raise VerificationError(f"cannot execute gh attestation verifier: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", "replace").strip()
        raise VerificationError(f"GitHub attestation verification failed: {detail}")
    return completed.stdout


AttestationRunner = Callable[[Path, str, str], bytes]


def verify_bundle(
    *,
    bundle: Path,
    candidate_root: Path,
    trusted_root: Path,
    expected: dict[str, str],
    runtime_archive_sha256: str,
    attestation_runner: AttestationRunner,
    preverified_checkouts: Path | None,
    compiled_authored_manifest: Path | None,
    receipt_output: Path | None = None,
) -> dict[str, Any]:
    bundle = bundle.resolve(strict=True)
    candidate_root = candidate_root.resolve(strict=True)
    trusted_root = trusted_root.resolve(strict=True)
    bundle_sha256 = sha256_file(bundle)
    require_hex(runtime_archive_sha256, "runtime archive SHA-256")
    for field in ("candidate_sha", "candidate_tree", "workflow_sha", "workflow_tree"):
        require_hex(expected.get(field), field, git=True)
    if not isinstance(expected.get("repository"), str) or expected["repository"].count("/") != 1:
        raise VerificationError("repository must be owner/name")
    if not RUN_ID_RE.fullmatch(expected.get("run_id", "")) or not RUN_ID_RE.fullmatch(
        expected.get("run_attempt", "")
    ):
        raise VerificationError("run identity is invalid")

    runtime_lock_path = trusted_root / "evidence/cafe/runtime-lock.v1.json"
    runtime_lock = load_json_file(runtime_lock_path)
    if not isinstance(runtime_lock, dict) or runtime_lock.get("schema") != RUNTIME_LOCK_SCHEMA:
        raise VerificationError("runtime lock schema mismatch")
    container_contract = exact_keys(
        runtime_lock.get("container_contract"),
        {
            "cap_drop",
            "candidate_mount",
            "network_default",
            "no_new_privileges",
            "platform",
            "read_only_root",
            "scratch_mount",
            "trusted_mount",
        },
        "runtime lock container contract",
    )
    if container_contract != {
        "cap_drop": "ALL",
        "candidate_mount": "read-only",
        "network_default": "none",
        "no_new_privileges": True,
        "platform": "linux/amd64",
        "read_only_root": True,
        "scratch_mount": "task-owned-read-write",
        "trusted_mount": "read-only",
    }:
        raise VerificationError("runtime lock weakens the isolated container contract")
    if runtime_lock.get("limits", {}).get("max_png_decompressed_bytes") != MAX_PNG_DECOMPRESSED_BYTES:
        raise VerificationError("runtime lock PNG decompression limit drift")
    verify_action_pins(trusted_root, runtime_lock)
    verify_oci_toolchain_contract(trusted_root, runtime_lock)
    verify_protected_bootstrap_contract((trusted_root / WORKFLOW_PATH).read_text(encoding="utf-8"))

    trusted_ids = trusted_root / "evidence/cafe/cafe-authored-ids.v1.json"
    trusted_authored_manifest = trusted_root / "evidence/cafe/cafe-authored-manifest.v1.json"
    candidate_ids = candidate_root / "evidence/cafe/cafe-authored-ids.v1.json"
    candidate_authored_manifest = candidate_root / "evidence/cafe/cafe-authored-manifest.v1.json"
    for left, right, label in (
        (trusted_ids, candidate_ids, "stable IDs"),
        (trusted_authored_manifest, candidate_authored_manifest, "authored manifest"),
    ):
        try:
            if left.read_bytes() != right.read_bytes():
                raise VerificationError(f"candidate {label} differs from protected master")
        except OSError as exc:
            raise VerificationError(f"missing protected/candidate {label}: {exc}") from exc

    if compiled_authored_manifest is None:
        raise VerificationError("container-authored manifest input is required")
    try:
        compiled_bytes = compiled_authored_manifest.resolve(strict=True).read_bytes()
    except OSError as exc:
        raise VerificationError(f"cannot read container-authored manifest: {exc}") from exc
    if compiled_bytes != trusted_authored_manifest.read_bytes():
        raise VerificationError("container-authored manifest differs from protected master")
    verify_preverified_checkouts(
        preverified_checkouts,
        expected,
        sha256_bytes(compiled_bytes),
    )
    authored_manifest = load_json_bytes(compiled_bytes, "compiled authored manifest")

    with tempfile.TemporaryDirectory(prefix="cafe-attested-verify-") as temporary:
        extracted = Path(temporary)
        member_names = safe_extract(bundle, extracted)
        manifest_path = extracted / "trusted-cafe-manifest.json"
        if "trusted-cafe-manifest.json" not in member_names:
            raise VerificationError("bundle has no trusted-cafe-manifest.json")
        manifest_raw = manifest_path.read_bytes()
        manifest = load_json_bytes(manifest_raw, "trusted-cafe-manifest.json")
        if canonical_bytes(manifest) != manifest_raw:
            raise VerificationError("trusted-cafe-manifest.json is not canonical")
        exact_keys(
            manifest,
            {
                "schema",
                "repository",
                "candidate",
                "workflow",
                "run",
                "runtime",
                "authored",
                "capture_contract",
                "tools",
                "payloads",
                "evidence_only",
                "does_not_authorize",
            },
            "bundle manifest",
        )
        if manifest["schema"] != BUNDLE_SCHEMA or manifest["repository"] != expected["repository"]:
            raise VerificationError("bundle schema/repository mismatch")
        if manifest["evidence_only"] is not True or manifest["does_not_authorize"] != DOES_NOT_AUTHORIZE:
            raise VerificationError("bundle attempts to broaden visual evidence authority")

        candidate = exact_keys(manifest["candidate"], {"sha", "tree"}, "manifest candidate")
        workflow = exact_keys(
            manifest["workflow"], {"sha", "tree", "path", "ref"}, "manifest workflow"
        )
        run = exact_keys(manifest["run"], {"id", "attempt"}, "manifest run")
        if candidate != {"sha": expected["candidate_sha"], "tree": expected["candidate_tree"]}:
            raise VerificationError("manifest candidate identity mismatch")
        if workflow != {
            "sha": expected["workflow_sha"],
            "tree": expected["workflow_tree"],
            "path": WORKFLOW_PATH,
            "ref": f"{expected['repository']}{WORKFLOW_REF_SUFFIX}",
        }:
            raise VerificationError("manifest workflow identity mismatch")
        if run != {"id": expected["run_id"], "attempt": expected["run_attempt"]}:
            raise VerificationError("manifest run identity mismatch (receipt replay)")

        payloads = manifest["payloads"]
        if not isinstance(payloads, list) or len(payloads) != len(EXPECTED_PAYLOAD_PATHS):
            raise VerificationError("manifest payload count does not match the protected allowlist")
        expected_members = {"trusted-cafe-manifest.json"}
        seen_payloads: set[str] = set()
        for index, payload in enumerate(payloads):
            exact_keys(payload, {"path", "sha256", "bytes"}, f"payloads[{index}]")
            path = payload["path"]
            if not isinstance(path, str):
                raise VerificationError(f"payload path is not a string: {path!r}")
            if path != EXPECTED_PAYLOAD_PATHS[index]:
                raise VerificationError(
                    f"payloads[{index}] is outside or out of order in the protected allowlist: {path!r}"
                )
            _canonical_archive_name(path)
            pure = PurePosixPath(path)
            if path in seen_payloads:
                raise VerificationError(f"invalid/duplicate payload path: {path}")
            seen_payloads.add(path)
            expected_members.add(path)
            full = extracted.joinpath(*pure.parts)
            if not full.is_file():
                raise VerificationError(f"manifest payload is absent: {path}")
            raw = full.read_bytes()
            if payload["bytes"] != len(raw) or payload["sha256"] != sha256_bytes(raw):
                raise VerificationError(f"payload hash/size mismatch: {path}")
        if expected_members != set(member_names):
            raise VerificationError(
                f"manifest/member set mismatch: missing={sorted(set(member_names)-expected_members)}, "
                f"extra={sorted(expected_members-set(member_names))}"
            )

        bundled_ids = extracted / "authored/cafe-authored-ids.v1.json"
        bundled_authored = extracted / "authored/cafe-authored-manifest.v1.json"
        if bundled_ids.read_bytes() != trusted_ids.read_bytes() or bundled_authored.read_bytes() != compiled_bytes:
            raise VerificationError("bundled authored inputs differ from protected, recompiled source")
        authored_binding = exact_keys(
            manifest["authored"],
            {"ids_sha256", "manifest_sha256", "render_closure_sha256", "game_tree_git_oid"},
            "manifest authored",
        )
        if authored_binding != {
            "ids_sha256": sha256_file(trusted_ids),
            "manifest_sha256": sha256_bytes(compiled_bytes),
            "render_closure_sha256": authored_manifest["render_closure_sha256"],
            "game_tree_git_oid": authored_manifest["game_tree_git_oid"],
        }:
            raise VerificationError("manifest authored-source binding mismatch")

        bundled_runtime_lock = extracted / "runtime/runtime-lock.v1.json"
        if bundled_runtime_lock.read_bytes() != runtime_lock_path.read_bytes():
            raise VerificationError("bundled runtime lock differs from protected master")
        runtime = exact_keys(
            manifest["runtime"],
            {
                "lock_sha256",
                "archive_sha256",
                "oci_manifest_digest",
                "python",
                "pillow",
                "godot",
            },
            "manifest runtime",
        )
        if runtime["lock_sha256"] != sha256_file(runtime_lock_path):
            raise VerificationError("runtime lock digest mismatch")
        if runtime["archive_sha256"] != runtime_archive_sha256:
            raise VerificationError("runtime archive digest mismatch")
        require_hex(runtime["oci_manifest_digest"], "OCI manifest digest")
        versions = runtime_lock["versions"]
        if runtime["python"] != versions["python"] or runtime["pillow"] != versions["pillow"]:
            raise VerificationError("Python/Pillow runtime drift")
        if runtime["godot"] != versions["godot"]:
            raise VerificationError("Godot runtime drift")

        runtime_receipt_path = extracted / "runtime/runtime-build-receipt.json"
        runtime_receipt_raw = runtime_receipt_path.read_bytes()
        runtime_receipt = load_json_bytes(runtime_receipt_raw, "runtime build receipt")
        if canonical_bytes(runtime_receipt) != runtime_receipt_raw:
            raise VerificationError("runtime build receipt is not canonical")
        exact_keys(
            runtime_receipt,
            {
                "schema",
                "lock_sha256",
                "runtime_archive_sha256",
                "oci_manifest_digest",
                "base_manifest_digest",
                "python",
                "pillow",
                "godot",
                "podman",
                "skopeo",
                "gh",
                "oci_toolchain_image",
                "skopeo_image",
                "toolchain_tar",
                "toolchain_python",
                "toolchain_sha256sum",
                "validation_image",
                "validation_oci_manifest_digest",
                "container_platform",
                "container_network",
                "container_read_only",
                "container_cap_drop",
                "container_no_new_privileges",
                "first_archive_sha256",
                "second_archive_sha256",
                "reproducible",
            },
            "runtime build receipt",
        )
        if runtime_receipt["schema"] != RUNTIME_RECEIPT_SCHEMA or runtime_receipt["reproducible"] is not True:
            raise VerificationError("runtime reproducibility receipt mismatch")
        if not (
            runtime_receipt["runtime_archive_sha256"]
            == runtime_receipt["first_archive_sha256"]
            == runtime_receipt["second_archive_sha256"]
            == runtime_archive_sha256
        ):
            raise VerificationError("runtime double-build/archive binding mismatch")
        runtime_expected = {
            "lock_sha256": sha256_file(runtime_lock_path),
            "oci_manifest_digest": runtime["oci_manifest_digest"],
            "base_manifest_digest": runtime_lock["python_image"]["amd64_manifest_digest"],
            "python": versions["python"],
            "pillow": versions["pillow"],
            "godot": versions["godot"],
            "podman": runtime_lock["oci_toolchain"]["versions"]["podman"],
            "skopeo": runtime_lock["oci_toolchain"]["versions"]["skopeo"],
            "gh": runtime_lock["host_tools"]["gh"],
            "oci_toolchain_image": runtime_lock["oci_toolchain"]["podman_image"],
            "skopeo_image": runtime_lock["oci_toolchain"]["skopeo_image"],
            "toolchain_tar": runtime_lock["oci_toolchain"]["versions"]["tar"],
            "toolchain_python": runtime_lock["oci_toolchain"]["versions"]["python"],
            "toolchain_sha256sum": runtime_lock["oci_toolchain"]["versions"]["sha256sum"],
            "validation_image": runtime_lock["validation_image"]["reference"],
            "validation_oci_manifest_digest": runtime_receipt["validation_oci_manifest_digest"],
            "container_platform": runtime_lock["validation_image"]["platform"],
            "container_network": "none",
            "container_read_only": True,
            "container_cap_drop": "ALL",
            "container_no_new_privileges": True,
        }
        require_hex(runtime_receipt["validation_oci_manifest_digest"], "validation OCI manifest digest")
        for key, value in runtime_expected.items():
            if runtime_receipt[key] != value:
                raise VerificationError(f"runtime receipt drift: {key}")

        tool_records = manifest["tools"]
        if not isinstance(tool_records, list) or len(tool_records) != len(TRUSTED_TOOL_PATHS):
            raise VerificationError("trusted tool set mismatch")
        expected_tool_records = []
        for path in TRUSTED_TOOL_PATHS:
            protected = trusted_root.joinpath(*PurePosixPath(path).parts)
            snapshot = extracted / "trust-root" / path
            if not protected.is_file() or not snapshot.is_file():
                raise VerificationError(f"trusted tool snapshot is missing: {path}")
            if protected.read_bytes() != snapshot.read_bytes():
                raise VerificationError(f"trusted tool drift/snapshot mismatch: {path}")
            expected_tool_records.append(
                {"authority": "protected-master", "path": path, "sha256": sha256_file(protected)}
            )
        if tool_records != expected_tool_records:
            raise VerificationError("manifest trusted tool hashes/order mismatch")

        capture_contract = exact_keys(
            manifest["capture_contract"],
            {"space", "viewports", "seed", "tick", "renderer", "display", "audio", "slots", "frames"},
            "capture contract",
        )
        if capture_contract != {
            "space": "cafe",
            "viewports": ["1280x768", "320x192"],
            "seed": 3,
            "tick": 600,
            "renderer": "opengl3",
            "display": "x11/Xvfb",
            "audio": "Dummy",
            "slots": list(SLOTS),
            "frames": 8,
        }:
            raise VerificationError("capture contract drift or frame budget violation")

        floor_bindings = {item["floor"]: item["authored_binding_sha256"] for item in authored_manifest["floors"]}
        transcript_receipts: list[dict[str, str]] = []
        context = dict(expected)
        frame_hashes: dict[tuple[str, str], str] = {}
        for viewport, dimensions in VIEWPORTS.items():
            receipt_path = extracted / viewport / "cafe-capture-receipt.json"
            receipt_raw = receipt_path.read_bytes()
            receipt = load_json_bytes(receipt_raw, f"{viewport} receipt")
            if canonical_bytes(receipt) != receipt_raw:
                raise VerificationError(f"{viewport} receipt is not canonical")
            exact_keys(
                receipt,
                {
                    "schema",
                    "repository",
                    "candidate_sha",
                    "candidate_tree",
                    "workflow_sha",
                    "workflow_tree",
                    "run_id",
                    "run_attempt",
                    "viewport",
                    "session",
                    "captures",
                },
                f"{viewport} receipt",
            )
            if receipt["schema"] != RECEIPT_SCHEMA or any(
                receipt[key] != context[key]
                for key in (
                    "repository",
                    "candidate_sha",
                    "candidate_tree",
                    "workflow_sha",
                    "workflow_tree",
                    "run_id",
                    "run_attempt",
                )
            ):
                raise VerificationError(f"{viewport} receipt identity/replay mismatch")
            session = _expected_session(context, viewport)
            if receipt["viewport"] != viewport or receipt["session"] != session:
                raise VerificationError(f"{viewport} receipt session mismatch")
            captures = receipt["captures"]
            if not isinstance(captures, list) or len(captures) != 4:
                raise VerificationError(f"{viewport} receipt must contain four captures")
            by_slot: dict[str, dict[str, Any]] = {}
            for index, capture in enumerate(captures):
                exact_keys(
                    capture,
                    {
                        "slot",
                        "file",
                        "floor",
                        "mode",
                        "draw_skip",
                        "width",
                        "height",
                        "seed",
                        "tick",
                        "pair_id",
                        "authored_binding_sha256",
                        "argv",
                        "argv_sha256",
                        "sha256",
                        "bytes",
                    },
                    f"{viewport}.captures[{index}]",
                )
                slot = capture["slot"]
                if slot not in SLOTS or slot in by_slot:
                    raise VerificationError(f"{viewport} has an invalid/duplicate capture slot")
                floor, mode, draw_skip, filename = SLOTS[slot]
                if (
                    capture["file"] != filename
                    or capture["floor"] != floor
                    or capture["mode"] != mode
                    or capture["draw_skip"] != draw_skip
                    or (capture["width"], capture["height"]) != dimensions
                    or capture["seed"] != 3
                    or capture["tick"] != 600
                    or capture["authored_binding_sha256"] != floor_bindings[floor]
                ):
                    raise VerificationError(f"{viewport}/{slot} semantic binding mismatch")
                expected_pair = _expected_pair(session, floor, floor_bindings[floor])
                if capture["pair_id"] != expected_pair:
                    raise VerificationError(f"{viewport}/{slot} normal/bare pair mismatch")
                argv = expected_argv(viewport, floor, mode, filename)
                if capture["argv"] != argv or capture["argv_sha256"] != sha256_bytes(
                    json.dumps(argv, separators=(",", ":"), ensure_ascii=True).encode("ascii")
                ):
                    raise VerificationError(f"{viewport}/{slot} capture command mismatch")
                frame_path = extracted / viewport / filename
                frame_raw = frame_path.read_bytes()
                if capture["bytes"] != len(frame_raw) or capture["sha256"] != sha256_bytes(frame_raw):
                    raise VerificationError(f"{viewport}/{slot} frame byte tamper")
                if inspect_png(frame_raw, f"{viewport}/{filename}") != dimensions:
                    raise VerificationError(f"{viewport}/{slot} crop/resize detected")
                by_slot[slot] = capture
                frame_hashes[(viewport, slot)] = capture["sha256"]
            if set(by_slot) != set(SLOTS):
                raise VerificationError(f"{viewport} capture slot set mismatch")
            for floor in ("1f", "2f"):
                normal = by_slot[f"cafe_{floor}_normal"]
                bare = by_slot[f"cafe_{floor}_bare"]
                if normal["pair_id"] != bare["pair_id"] or normal["sha256"] == bare["sha256"]:
                    raise VerificationError(f"{viewport}/{floor} normal/bare pairing is invalid")
            if by_slot["cafe_1f_normal"]["sha256"] == by_slot["cafe_2f_normal"]["sha256"]:
                raise VerificationError(f"{viewport} floor-normal substitution detected")
            transcript_receipts.append(
                {
                    "path": f"{viewport}/cafe-capture-receipt.json",
                    "sha256": sha256_bytes(receipt_raw),
                    "viewport": viewport,
                }
            )

        transcript_path = extracted / "capture-transcript.json"
        transcript_raw = transcript_path.read_bytes()
        transcript = load_json_bytes(transcript_raw, "capture transcript")
        if canonical_bytes(transcript) != transcript_raw:
            raise VerificationError("capture transcript is not canonical")
        exact_keys(
            transcript,
            {
                "schema",
                "repository",
                "candidate_sha",
                "candidate_tree",
                "workflow_sha",
                "workflow_tree",
                "run_id",
                "run_attempt",
                "frame_count",
                "receipts",
            },
            "capture transcript",
        )
        if transcript != {
            "schema": TRANSCRIPT_SCHEMA,
            **context,
            "frame_count": 8,
            "receipts": transcript_receipts,
        }:
            raise VerificationError("capture transcript identity/hash mismatch")

    attestation_raw = attestation_runner(bundle, expected["repository"], expected["workflow_sha"])
    attestation = validate_attestation_output(attestation_raw, bundle_sha256, bundle.name)
    receipt = {
        "schema": "living-town.cafe-attested-verification-receipt.v1",
        "repository": expected["repository"],
        "candidate_sha": expected["candidate_sha"],
        "candidate_tree": expected["candidate_tree"],
        "workflow_sha": expected["workflow_sha"],
        "workflow_tree": expected["workflow_tree"],
        "run_id": expected["run_id"],
        "run_attempt": expected["run_attempt"],
        "runtime_archive_sha256": runtime_archive_sha256,
        "preverified_checkouts_sha256": sha256_file(preverified_checkouts.resolve(strict=True)),
        "compiled_authored_manifest_sha256": sha256_bytes(compiled_bytes),
        "bundle_sha256": bundle_sha256,
        "attestation_predicate_type": attestation["verificationResult"]["statement"]["predicateType"],
        "verified": True,
        "evidence_only": True,
        "does_not_authorize": DOES_NOT_AUTHORIZE,
    }
    if receipt_output is not None:
        receipt_output.parent.mkdir(parents=True, exist_ok=True)
        temporary = receipt_output.with_name(f".{receipt_output.name}.{os.getpid()}.tmp")
        try:
            temporary.write_bytes(canonical_bytes(receipt))
            os.replace(temporary, receipt_output)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
    return receipt


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--archive-bootstrap" in argv:
        parser = argparse.ArgumentParser(description="Validate pre-load runtime and validation attestations")
        parser.add_argument("--archive-bootstrap", action="store_true", required=True)
        parser.add_argument("--runtime-archive", type=Path, required=True)
        parser.add_argument("--runtime-attestation", type=Path, required=True)
        parser.add_argument("--validation-archive", type=Path, required=True)
        parser.add_argument("--validation-attestation", type=Path, required=True)
        parser.add_argument("--repository", required=True)
        parser.add_argument("--workflow-sha", required=True)
        parser.add_argument("--receipt-output", type=Path, required=True)
        args = parser.parse_args(argv)
        try:
            receipt = verify_archive_bootstrap(
                runtime_archive=args.runtime_archive,
                runtime_attestation=args.runtime_attestation.read_bytes(),
                validation_archive=args.validation_archive,
                validation_attestation=args.validation_attestation.read_bytes(),
                repository=args.repository,
                workflow_sha=args.workflow_sha,
                receipt_output=args.receipt_output,
            )
        except (VerificationError, OSError) as exc:
            print(f"VERIFY_CAFE_ARCHIVE_BOOTSTRAP FAIL: {exc}", file=sys.stderr)
            return 1
        print(
            "VERIFY_CAFE_ARCHIVE_BOOTSTRAP PASS "
            f"runtime={receipt['archives'][0]['sha256']} validation={receipt['archives'][1]['sha256']}",
            file=sys.stderr,
        )
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--trusted-root", type=Path, required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--candidate-tree", required=True)
    parser.add_argument("--workflow-sha", required=True)
    parser.add_argument("--workflow-tree", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    parser.add_argument("--runtime-archive-sha256", required=True)
    parser.add_argument("--preverified-checkouts", type=Path)
    parser.add_argument("--compiled-authored-manifest", type=Path)
    parser.add_argument("--gh-bin", default="gh")
    parser.add_argument("--attestation-json", type=Path)
    parser.add_argument("--receipt-output", type=Path, required=True)
    args = parser.parse_args(argv)
    expected = {
        "repository": args.repository,
        "candidate_sha": args.candidate_sha,
        "candidate_tree": args.candidate_tree,
        "workflow_sha": args.workflow_sha,
        "workflow_tree": args.workflow_tree,
        "run_id": args.run_id,
        "run_attempt": args.run_attempt,
    }
    try:
        receipt = verify_bundle(
            bundle=args.bundle,
            candidate_root=args.candidate_root,
            trusted_root=args.trusted_root,
            expected=expected,
            runtime_archive_sha256=args.runtime_archive_sha256,
            preverified_checkouts=args.preverified_checkouts,
            compiled_authored_manifest=args.compiled_authored_manifest,
            attestation_runner=(
                (lambda *_: args.attestation_json.read_bytes())
                if args.attestation_json is not None
                else lambda bundle, repository, workflow_sha: run_github_attestation(
                    bundle, repository, workflow_sha, args.gh_bin
                )
            ),
            receipt_output=args.receipt_output,
        )
    except (VerificationError, OSError) as exc:
        print(f"VERIFY_CAFE_ATTESTED_EVIDENCE FAIL: {exc}", file=sys.stderr)
        return 1
    print(
        "VERIFY_CAFE_ATTESTED_EVIDENCE PASS "
        f"bundle_sha256={receipt['bundle_sha256']} candidate={receipt['candidate_sha']}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
