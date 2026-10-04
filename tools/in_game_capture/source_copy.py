"""Prepare and verify an isolated game copy against pinned Git blobs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tarfile
import uuid
from pathlib import Path, PureWindowsPath


WINDOWS_FORBIDDEN = set('<>:"\\|?*')


def safe_relative_target(root: Path, name: str) -> Path:
    """Resolve one canonical POSIX archive/bundle name safely on Windows too."""
    if not isinstance(name, str) or not name or name.startswith("/"):
        raise ValueError(f"Unsafe relative path: {name!r}")
    parts = name.split("/")
    for part in parts:
        if (
            part in {"", ".", ".."}
            or part.endswith((" ", "."))
            or any(char in WINDOWS_FORBIDDEN or ord(char) < 32 for char in part)
            or PureWindowsPath(part).is_reserved()
        ):
            raise ValueError(f"Unsafe Windows path component: {name!r}")
    base = root.resolve(strict=True)
    target = base.joinpath(*parts)
    if not target.resolve(strict=False).is_relative_to(base):
        raise ValueError(f"Relative path escapes its root: {name!r}")
    return target


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repo), *args])


def git_text(repo: Path, *args: str) -> str:
    return git(repo, *args).decode("utf-8").strip()


def blob_id(data: bytes, object_format: str) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.new(object_format, header + data).hexdigest()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def tracked_entries(repo: Path, source_commit: str) -> dict[str, dict[str, str]]:
    entries: dict[str, dict[str, str]] = {}
    for record in git(repo, "ls-tree", "-r", "-z", source_commit, "game").split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split(" ")
        path = raw_path.decode("utf-8")
        if kind != "blob" or mode not in {"100644", "100755"} or not path.startswith("game/"):
            raise ValueError(f"Unsupported game tree entry: {path} ({mode} {kind})")
        name = path.removeprefix("game/")
        # Validate before the archive can create any directories or files.
        safe_relative_target(repo, name)
        entries[name] = {"mode": mode, "blob_oid": oid}
    if not entries or "project.godot" not in entries:
        raise ValueError("Pinned Git game tree is empty or lacks project.godot")
    return entries


def patched_project(source: bytes, user_dir_name: str) -> bytes:
    if b"config/use_custom_user_dir" in source or b"config/custom_user_dir_name" in source:
        raise ValueError("Pinned project already sets a custom user directory")
    newline = b"\r\n" if b"\r\n" in source else b"\n"
    marker = b"[application]" + newline
    if source.count(marker) != 1:
        raise ValueError("Expected exactly one [application] section")
    settings = (
        b"config/use_custom_user_dir=true" + newline
        + b'config/custom_user_dir_name="' + user_dir_name.encode("ascii") + b'"' + newline
    )
    return source.replace(marker, marker + settings, 1)


def restored_project(capture: bytes, user_dir_name: str) -> bytes | None:
    """Remove exactly the two capture settings, leaving the pinned blob bytes."""
    newline = b"\r\n" if b"\r\n" in capture else b"\n"
    settings = (
        b"config/use_custom_user_dir=true" + newline
        + b'config/custom_user_dir_name="' + user_dir_name.encode("ascii") + b'"' + newline
    )
    if capture.count(settings) != 1:
        return None
    return capture.replace(settings, b"", 1)


def assert_outside_repo(repo: Path, capture_root: Path) -> None:
    repo = repo.resolve()
    capture_root = capture_root.resolve()
    if capture_root == repo or repo in capture_root.parents:
        raise ValueError("Capture root must be outside the source worktree")


def prepare(repo: Path, capture_root: Path, requested_commit: str, allow_crlf: bool) -> dict:
    repo = repo.resolve(strict=True)
    capture_root = capture_root.resolve()
    assert_outside_repo(repo, capture_root)
    if capture_root.exists() and any(capture_root.iterdir()):
        raise ValueError(f"Capture root is not empty: {capture_root}")
    if git(repo, "status", "--porcelain=v1", "--untracked-files=all").strip():
        raise ValueError("Source worktree is dirty; commit capture tools before preparing exact evidence")
    source_commit = git_text(repo, "rev-parse", f"{requested_commit}^{{commit}}")
    object_format = git_text(repo, "rev-parse", "--show-object-format")
    if object_format not in {"sha1", "sha256"}:
        raise ValueError(f"Unsupported Git object format: {object_format}")
    entries = tracked_entries(repo, source_commit)
    source_game_tree = git_text(repo, "rev-parse", f"{source_commit}:game")
    instrumentation_commit = git_text(repo, "rev-parse", "HEAD")
    user_dir_name = "LivingTownCapture_" + uuid.uuid4().hex
    capture_root.mkdir(parents=True, exist_ok=True)
    game = capture_root / "game"
    game.mkdir()
    extracted: set[str] = set()
    archive_normalized: list[str] = []
    project_source = b""

    # This Windows Git can convert LF blobs to CRLF even in an archive. Accept
    # that conversion only with an explicit option, then write the blob bytes.
    process = subprocess.Popen(
        ["git", "-C", str(repo), "archive", "--format=tar", f"{source_commit}:game"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                if member.isdir():
                    continue
                if not member.isfile():
                    raise ValueError(f"Unsafe or unsupported archive entry: {member.name}")
                name = member.name
                target = safe_relative_target(game, name)
                if name not in entries:
                    raise ValueError(f"Unexpected archive entry: {name}")
                file = archive.extractfile(member)
                if file is None:
                    raise ValueError(f"Cannot read archive entry: {name}")
                data = file.read()
                if blob_id(data, object_format) != entries[name]["blob_oid"]:
                    normalized = data.replace(b"\r\n", b"\n")
                    if (
                        allow_crlf
                        and normalized != data
                        and blob_id(normalized, object_format) == entries[name]["blob_oid"]
                    ):
                        data = normalized
                        archive_normalized.append(name)
                    else:
                        raise ValueError(f"Git archive blob mismatch: {name}")
                if name == "project.godot":
                    project_source = data
                    data = patched_project(data, user_dir_name)
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.resolve(strict=False).is_relative_to(game.resolve(strict=True)):
                    raise ValueError(f"Archive target escaped game copy: {name}")
                target.write_bytes(data)
                extracted.add(name)
    finally:
        process.stdout.close()
    stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr else ""
    if process.wait() != 0 or extracted != set(entries):
        raise ValueError(f"Incomplete Git archive: {stderr or sorted(set(entries) - extracted)}")

    script_dir = Path(__file__).resolve().parent
    instruments = {}
    for name in ("live_bridge.gd", "send-command.ps1", "start.ps1", "verify_run.py", "source_copy.py"):
        path = script_dir / name
        instruments[name] = sha256(path.read_bytes())
    manifest = {
        "schema": "living-town.capture-source/1",
        "source_commit": source_commit,
        "source_game_tree": source_game_tree,
        "git_object_format": object_format,
        "instrumentation_commit": instrumentation_commit,
        "instrument_sha256": instruments,
        "user_dir_name": user_dir_name,
        "project_source_blob_oid": entries["project.godot"]["blob_oid"],
        "project_capture_sha256": sha256(patched_project(project_source, user_dir_name)),
        "allow_crlf_normalization": allow_crlf,
        "archive_crlf_normalized_files": len(archive_normalized),
        "archive_crlf_normalized_path_list_sha256": sha256("\n".join(archive_normalized).encode("utf-8")),
        "entries": entries,
    }
    write_json(capture_root / "source-manifest.json", manifest)
    return verify(capture_root, "prepare")


def verify(capture_root: Path, phase: str) -> dict:
    capture_root = capture_root.resolve(strict=True)
    manifest = json.loads((capture_root / "source-manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != "living-town.capture-source/1":
        raise ValueError("Unknown source manifest schema")
    game = capture_root / "game"
    entries = manifest["entries"]
    for name in entries:
        safe_relative_target(game, name)
    object_format = manifest["git_object_format"]
    actual = {
        path.relative_to(game).as_posix()
        for path in game.rglob("*")
        if path.is_file() and not path.relative_to(game).parts[0] == ".godot"
    }
    missing = sorted(set(entries) - actual)
    extra = sorted(actual - set(entries))
    mismatches = []
    normalized = []
    for name in sorted(set(entries) & actual):
        data = (game / name).read_bytes()
        if name == "project.godot":
            restored = restored_project(data, manifest["user_dir_name"])
            if (
                sha256(data) != manifest["project_capture_sha256"]
                or restored is None
                or blob_id(restored, object_format) != manifest["project_source_blob_oid"]
            ):
                mismatches.append(name)
            continue
        if blob_id(data, object_format) == entries[name]["blob_oid"]:
            continue
        lf_data = data.replace(b"\r\n", b"\n")
        if (
            manifest["allow_crlf_normalization"]
            and lf_data != data
            and blob_id(lf_data, object_format) == entries[name]["blob_oid"]
        ):
            normalized.append(name)
        else:
            mismatches.append(name)
    proof = {
        "schema": "living-town.capture-copy-proof/1",
        "phase": phase,
        "source_commit": manifest["source_commit"],
        "source_game_tree": manifest["source_game_tree"],
        "git_object_format": object_format,
        "comparison": "Git blob IDs; optional explicit CRLF-to-LF normalization",
        "allow_crlf_normalization": manifest["allow_crlf_normalization"],
        "archive_crlf_normalized_files": manifest["archive_crlf_normalized_files"],
        "tracked_game_files": len(entries),
        "project_only_override": "custom user:// directory",
        "project_capture_sha256": manifest["project_capture_sha256"],
        "user_dir_name": manifest["user_dir_name"],
        "line_ending_normalized_files": len(normalized),
        "line_ending_normalized_path_list_sha256": sha256("\n".join(normalized).encode("utf-8")),
        "missing_files": missing,
        "extra_files": extra,
        "mismatched_files": mismatches,
        "pass": not (missing or extra or mismatches),
    }
    output = capture_root / f"source-copy-{phase}.json"
    write_json(output, proof)
    if not proof["pass"]:
        raise ValueError(f"Capture copy mismatch: {output}")
    return proof


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prepare_parser = sub.add_parser("prepare")
    prepare_parser.add_argument("--repo", type=Path, required=True)
    prepare_parser.add_argument("--capture-root", type=Path, required=True)
    prepare_parser.add_argument("--source-commit", required=True)
    prepare_parser.add_argument("--allow-crlf-normalization", action="store_true")
    verify_parser = sub.add_parser("verify")
    verify_parser.add_argument("--capture-root", type=Path, required=True)
    verify_parser.add_argument("--phase", required=True)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            proof = prepare(args.repo, args.capture_root, args.source_commit, args.allow_crlf_normalization)
        else:
            proof = verify(args.capture_root, args.phase)
        print(json.dumps({key: value for key, value in proof.items() if key not in {"missing_files", "extra_files", "mismatched_files"}}))
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        print(f"CAPTURE_SOURCE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
