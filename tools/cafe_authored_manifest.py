#!/usr/bin/env python3
"""Compile the reviewed cafe authored-source contract into canonical JSON.

The stable-ID input and generated manifest are deliberately maintained by a
separate Stack B.  This protected compiler only defines and enforces their
format.  It never treats rendered pixels as simulation or canon authority.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any


IDS_SCHEMA = "living-town.cafe-authored-ids.v1"
MANIFEST_SCHEMA = "living-town.cafe-authored-manifest.v1"
COMPILER_SCHEMA = "living-town.cafe-authored-compiler.v1"
EXPECTED_FLOORS = ("1f", "2f")
EXPECTED_SLOTS = {
    "1f": ("cafe_1f_normal", "cafe_1f_bare"),
    "2f": ("cafe_2f_normal", "cafe_2f_bare"),
}
SOURCE_ROLES = {"semantic", "renderer"}
SOURCE_KINDS = {"file", "json-pointer"}
SOURCE_EXTENSIONS = {
    ".gd",
    ".gdextension",
    ".godot",
    ".json",
    ".tres",
    ".tscn",
}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._/-]{2,95}$")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")


class ContractError(ValueError):
    """A fail-closed authored-source contract violation."""


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json_strict(path: Path) -> Any:
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ContractError(f"cannot read UTF-8 JSON {path}: {exc}") from exc
    try:
        return json.loads(
            raw,
            object_pairs_hook=_reject_duplicates,
            parse_constant=lambda value: (_ for _ in ()).throw(
                ContractError(f"non-finite JSON number: {value}")
            ),
        )
    except (json.JSONDecodeError, UnicodeError) as exc:
        raise ContractError(f"malformed JSON {path}: {exc}") from exc


def canonical_bytes(value: Any, *, newline: bool = True) -> bytes:
    try:
        text = json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        raise ContractError(f"value is not canonical JSON: {exc}") from exc
    return (text + ("\n" if newline else "")).encode("ascii")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise ContractError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _exact_keys(value: dict[str, Any], expected: set[str], where: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise ContractError(f"{where} keys mismatch; missing={missing}, extra={extra}")


def _git(repo: Path, *args: str, text: bool = True) -> str | bytes:
    command = ["git", "-C", str(repo), *args]
    try:
        return subprocess.check_output(command, text=text, stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = getattr(exc, "output", "")
        if isinstance(detail, bytes):
            detail = detail.decode("utf-8", "replace")
        raise ContractError(f"git command failed: {' '.join(command)}: {detail.strip()}") from exc


def _safe_source_path(repo: Path, value: Any, where: str) -> tuple[str, Path]:
    if not isinstance(value, str) or not value:
        raise ContractError(f"{where} must be a non-empty repository-relative path")
    if "\\" in value:
        raise ContractError(f"{where} must use POSIX separators")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or pure.parts[0] != "game":
        raise ContractError(f"{where} must stay under game/: {value}")
    normalized = pure.as_posix()
    if normalized != value or value.endswith("/"):
        raise ContractError(f"{where} is not canonical: {value}")

    repo_resolved = repo.resolve(strict=True)
    candidate = repo.joinpath(*pure.parts)
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(repo_resolved)
    except (OSError, ValueError) as exc:
        raise ContractError(f"{where} escapes or is missing: {value}") from exc
    cursor = repo
    for part in pure.parts:
        cursor /= part
        if cursor.is_symlink():
            raise ContractError(f"{where} traverses a symlink: {value}")
    if not resolved.is_file():
        raise ContractError(f"{where} is not a regular file: {value}")
    _git(repo, "ls-files", "--error-unmatch", "--", normalized)
    return normalized, resolved


def _json_pointer(document: Any, pointer: str, where: str) -> Any:
    if not isinstance(pointer, str) or (pointer and not pointer.startswith("/")):
        raise ContractError(f"{where} is not an RFC 6901 JSON pointer")
    current = document
    if pointer == "":
        return current
    for raw_token in pointer[1:].split("/"):
        token = raw_token.replace("~1", "/").replace("~0", "~")
        if "~" in token:
            # Any remaining tilde came from an invalid escape in the raw token.
            escaped = raw_token.replace("~0", "").replace("~1", "")
            if "~" in escaped:
                raise ContractError(f"{where} contains an invalid '~' escape")
        if isinstance(current, dict):
            if token not in current:
                raise ContractError(f"{where} does not resolve at object token {token!r}")
            current = current[token]
        elif isinstance(current, list):
            if token == "-" or not token.isdigit() or (len(token) > 1 and token[0] == "0"):
                raise ContractError(f"{where} has a non-canonical array token {token!r}")
            index = int(token)
            if index >= len(current):
                raise ContractError(f"{where} array index is out of range: {index}")
            current = current[index]
        else:
            raise ContractError(f"{where} descends through a scalar at token {token!r}")
    return current


def _source_inventory(repo: Path) -> tuple[str, int]:
    raw = _git(repo, "ls-tree", "-r", "-z", "--full-tree", "HEAD", "--", "game", text=False)
    assert isinstance(raw, bytes)
    records: list[dict[str, str]] = []
    for item in raw.split(b"\0"):
        if not item:
            continue
        try:
            metadata, raw_path = item.split(b"\t", 1)
            mode, object_type, object_id = metadata.decode("ascii").split(" ")
            path = raw_path.decode("utf-8")
        except (ValueError, UnicodeError) as exc:
            raise ContractError("git emitted a malformed game tree record") from exc
        if object_type != "blob":
            raise ContractError(f"game tree contains a non-blob entry: {path}")
        if mode == "120000":
            raise ContractError(f"game tree contains a symlink: {path}")
        if PurePosixPath(path).suffix.lower() not in SOURCE_EXTENSIONS:
            continue
        records.append({"git_oid": object_id, "mode": mode, "path": path})
    if not records:
        raise ContractError("tracked game source inventory is empty")
    records.sort(key=lambda item: item["path"])
    return sha256_bytes(canonical_bytes(records, newline=False)), len(records)


def compile_manifest(repo: Path, ids_path: Path, compiler_path: Path | None = None) -> dict[str, Any]:
    repo = repo.resolve(strict=True)
    if not (repo / ".git").exists():
        # Worktree .git is a file, ordinary repository .git is a directory.
        raise ContractError(f"not a Git checkout: {repo}")
    dirty_game = str(_git(repo, "status", "--porcelain=v1", "--untracked-files=all", "--", "game")).strip()
    if dirty_game:
        raise ContractError(f"game source must be clean before compilation: {dirty_game}")

    game_tree = str(_git(repo, "rev-parse", "HEAD:game")).strip()
    if not HEX40_RE.fullmatch(game_tree):
        raise ContractError(f"unexpected game tree object ID: {game_tree}")
    source_inventory_sha256, source_inventory_count = _source_inventory(repo)

    ids_path = ids_path.resolve(strict=True)
    ids = load_json_strict(ids_path)
    if not isinstance(ids, dict):
        raise ContractError("stable-ID document must be a JSON object")
    _exact_keys(ids, {"schema", "space", "floors", "sources"}, "stable-ID document")
    if ids["schema"] != IDS_SCHEMA or ids["space"] != "cafe":
        raise ContractError("stable-ID schema/space mismatch")
    if not isinstance(ids["floors"], list) or not isinstance(ids["sources"], list):
        raise ContractError("floors and sources must be arrays")
    if ids_path.read_bytes() != canonical_bytes(ids):
        raise ContractError("stable-ID document must use canonical JSON bytes")

    source_records: list[dict[str, Any]] = []
    sources_by_id: dict[str, dict[str, Any]] = {}
    for index, source in enumerate(ids["sources"]):
        where = f"sources[{index}]"
        if not isinstance(source, dict):
            raise ContractError(f"{where} must be an object")
        common = {"id", "path", "kind", "role", "floors"}
        kind = source.get("kind")
        expected = common | ({"json_pointer"} if kind == "json-pointer" else set())
        _exact_keys(source, expected, where)
        source_id = source["id"]
        if not isinstance(source_id, str) or not ID_RE.fullmatch(source_id):
            raise ContractError(f"{where}.id is not stable/canonical")
        if source_id in sources_by_id:
            raise ContractError(f"duplicate source id: {source_id}")
        if kind not in SOURCE_KINDS or source["role"] not in SOURCE_ROLES:
            raise ContractError(f"{where} has an unsupported kind or role")
        floors = source["floors"]
        if (
            not isinstance(floors, list)
            or not floors
            or any(floor not in EXPECTED_FLOORS for floor in floors)
            or floors != sorted(set(floors))
        ):
            raise ContractError(f"{where}.floors must be a sorted non-empty subset of {EXPECTED_FLOORS}")
        rel_path, full_path = _safe_source_path(repo, source["path"], f"{where}.path")
        raw = full_path.read_bytes()
        selected = raw
        record: dict[str, Any] = {
            "file_bytes": len(raw),
            "file_sha256": sha256_bytes(raw),
            "floors": floors,
            "id": source_id,
            "kind": kind,
            "path": rel_path,
            "role": source["role"],
        }
        if kind == "json-pointer":
            document = load_json_strict(full_path)
            pointer = source["json_pointer"]
            selected_value = _json_pointer(document, pointer, f"{where}.json_pointer")
            selected = canonical_bytes(selected_value, newline=False)
            record["json_pointer"] = pointer
        record["selected_bytes"] = len(selected)
        record["selected_sha256"] = sha256_bytes(selected)
        sources_by_id[source_id] = record
        source_records.append(record)

    if not source_records:
        raise ContractError("at least one authored source is required")
    source_records.sort(key=lambda item: item["id"])

    floor_records: list[dict[str, Any]] = []
    seen_floors: set[str] = set()
    used_sources: set[str] = set()
    for index, floor in enumerate(ids["floors"]):
        where = f"floors[{index}]"
        if not isinstance(floor, dict):
            raise ContractError(f"{where} must be an object")
        _exact_keys(floor, {"floor", "normal_slot", "bare_slot", "source_ids"}, where)
        floor_id = floor["floor"]
        if floor_id not in EXPECTED_FLOORS or floor_id in seen_floors:
            raise ContractError(f"{where}.floor is missing, duplicate, or unsupported")
        seen_floors.add(floor_id)
        expected_normal, expected_bare = EXPECTED_SLOTS[floor_id]
        if (floor["normal_slot"], floor["bare_slot"]) != (expected_normal, expected_bare):
            raise ContractError(f"{where} slot identity mismatch")
        source_ids = floor["source_ids"]
        if (
            not isinstance(source_ids, list)
            or not source_ids
            or source_ids != sorted(set(source_ids))
            or any(source_id not in sources_by_id for source_id in source_ids)
        ):
            raise ContractError(f"{where}.source_ids must be sorted, unique, and declared")
        selected_sources = [sources_by_id[source_id] for source_id in source_ids]
        if any(floor_id not in source["floors"] for source in selected_sources):
            raise ContractError(f"{where} references a source not declared for floor {floor_id}")
        roles = {source["role"] for source in selected_sources}
        if roles != SOURCE_ROLES:
            raise ContractError(f"{where} must bind both semantic and renderer sources")
        used_sources.update(source_ids)
        binding_payload = [
            {
                "id": source["id"],
                "role": source["role"],
                "selected_sha256": source["selected_sha256"],
            }
            for source in selected_sources
        ]
        floor_records.append(
            {
                "authored_binding_sha256": sha256_bytes(canonical_bytes(binding_payload, newline=False)),
                "bare_slot": expected_bare,
                "floor": floor_id,
                "normal_slot": expected_normal,
                "source_ids": source_ids,
            }
        )
    if seen_floors != set(EXPECTED_FLOORS):
        raise ContractError(f"floors must be exactly {EXPECTED_FLOORS}")
    if used_sources != set(sources_by_id):
        raise ContractError(f"unbound authored sources: {sorted(set(sources_by_id) - used_sources)}")
    floor_records.sort(key=lambda item: item["floor"])

    compiler_path = (compiler_path or Path(__file__)).resolve(strict=True)
    ids_bytes = canonical_bytes(ids)
    closure_payload = {
        "floors": floor_records,
        "game_tree_git_oid": game_tree,
        "source_inventory_sha256": source_inventory_sha256,
        "sources": source_records,
    }
    return {
        "schema": MANIFEST_SCHEMA,
        "compiler": {
            "schema": COMPILER_SCHEMA,
            "sha256": sha256_file(compiler_path),
        },
        "space": "cafe",
        "ids_sha256": sha256_bytes(ids_bytes),
        "game_tree_git_oid": game_tree,
        "source_inventory": {
            "count": source_inventory_count,
            "sha256": source_inventory_sha256,
        },
        "sources": source_records,
        "floors": floor_records,
        "render_closure_sha256": sha256_bytes(canonical_bytes(closure_payload, newline=False)),
        "evidence_only": True,
        "does_not_authorize": [
            "canon",
            "collision",
            "navigation",
            "pixels",
            "portals",
            "replay",
            "save",
            "simulation",
            "view",
        ],
    }


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("xb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True, help="exact candidate Git checkout")
    parser.add_argument(
        "--ids",
        type=Path,
        default=Path("evidence/cafe/cafe-authored-ids.v1.json"),
        help="stable-ID JSON (relative paths resolve under --repo)",
    )
    parser.add_argument("--output", type=Path, help="write canonical generated manifest")
    parser.add_argument("--check", type=Path, help="require byte equality with a checked manifest")
    args = parser.parse_args(argv)

    repo = args.repo.resolve(strict=True)
    ids_path = args.ids if args.ids.is_absolute() else repo / args.ids
    try:
        manifest = compile_manifest(repo, ids_path)
        encoded = canonical_bytes(manifest)
        if args.check:
            check_path = args.check if args.check.is_absolute() else repo / args.check
            try:
                checked = check_path.read_bytes()
            except OSError as exc:
                raise ContractError(f"cannot read checked manifest {check_path}: {exc}") from exc
            if checked != encoded:
                raise ContractError(
                    "checked authored manifest is stale or non-canonical; regenerate it with the protected compiler"
                )
        if args.output:
            write_atomic(args.output, encoded)
        elif not args.check:
            sys.stdout.buffer.write(encoded)
    except (ContractError, OSError) as exc:
        print(f"CAFE_AUTHORED_MANIFEST FAIL: {exc}", file=sys.stderr)
        return 1
    print(
        f"CAFE_AUTHORED_MANIFEST PASS sha256={sha256_bytes(encoded)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
