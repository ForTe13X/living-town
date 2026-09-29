#!/usr/bin/env python3
"""Authoring-only immutable package store and revision-CAS publication catalog.

The runtime consumes resolved WorldPackage JSON files and never opens this
catalog. Immutable package bytes are persisted before the SQLite transaction;
an interrupted publication can therefore leave an orphan object, but cannot
replace the currently published build with a partial file.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CATALOG_SCHEMA = 1


class CatalogError(Exception):
    """A validation, durability, or catalog conflict error."""


class StaleRevision(CatalogError):
    """The caller's expected revision is no longer the active revision."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CatalogError(f"E_JSON_DUPLICATE_KEY: duplicate key {key!r}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise CatalogError(f"E_JSON_CONSTANT: unsupported numeric constant {value}")


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream, object_pairs_hook=_unique_object, parse_constant=_reject_constant)
    except CatalogError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CatalogError(f"E_JSON_READ: {path}: {exc}") from exc


def _canonical_value(value: Any) -> Any:
    if isinstance(value, bool) or value is None or isinstance(value, (str, int)):
        return value
    if isinstance(value, float):
        nearest = round(value)
        if abs(value - nearest) <= 1e-9:
            return int(nearest)
        return round(value, 6)
    if isinstance(value, list):
        return [_canonical_value(item) for item in value]
    if isinstance(value, dict):
        return {key: _canonical_value(value[key]) for key in sorted(value)}
    raise CatalogError(f"E_JSON_TYPE: unsupported value {type(value).__name__}")


def canonical_bytes(value: Any) -> bytes:
    try:
        return json.dumps(
            _canonical_value(value), ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise CatalogError(f"E_CANONICAL: {exc}") from exc


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _is_hex_digest(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def validate_package(package: Any) -> tuple[str, str, str]:
    if not isinstance(package, dict) or package.get("schema") != "WorldPackage/1":
        raise CatalogError("E_PACKAGE_SCHEMA: expected WorldPackage/1")
    if set(package) != {"schema", "world_id", "coordinate_frame", "capabilities", "semantic", "presentation", "provenance", "digests"}:
        raise CatalogError("E_PACKAGE_FIELDS: unknown or missing package root fields")
    world_id = package.get("world_id")
    if not isinstance(world_id, str) or not world_id.strip():
        raise CatalogError("E_PACKAGE_ID: world_id must be a non-empty string")
    for key in ("semantic", "presentation", "provenance", "digests"):
        if not isinstance(package.get(key), dict):
            raise CatalogError(f"E_PACKAGE_FIELD: {key} must be an object")
    if not isinstance(package.get("coordinate_frame"), dict) or not isinstance(package.get("capabilities"), dict):
        raise CatalogError("E_PACKAGE_FIELD: coordinate_frame and capabilities must be objects")
    digests = package["digests"]
    semantic_hash = sha256_bytes(canonical_bytes(package["semantic"]))
    presentation_hash = sha256_bytes(canonical_bytes(package["presentation"]))
    if digests.get("semantic_sha256") != semantic_hash:
        raise CatalogError("E_PACKAGE_SEMANTIC_HASH: semantic payload does not match package digest")
    if digests.get("presentation_sha256") != presentation_hash:
        raise CatalogError("E_PACKAGE_PRESENTATION_HASH: presentation payload does not match package digest")
    if not _is_hex_digest(semantic_hash) or not _is_hex_digest(presentation_hash):
        raise CatalogError("E_PACKAGE_DIGEST: package section digest is malformed")
    return world_id, semantic_hash, presentation_hash


def package_identity(package: dict[str, Any]) -> tuple[str, str, str, str, bytes]:
    world_id, semantic_hash, presentation_hash = validate_package(package)
    data = canonical_bytes(package)
    return world_id, sha256_bytes(data), semantic_hash, presentation_hash, data


def validate_attestations(
    package: dict[str, Any], build_id: str, expected_revision: int,
    validation: Any, approval: Any,
) -> tuple[bytes, bytes]:
    world_id = package["world_id"]
    if not isinstance(validation, dict) or validation.get("schema") != "worldgen.validation/1":
        raise CatalogError("E_VALIDATION_SCHEMA: expected worldgen.validation/1")
    if set(validation) != {"schema", "status", "world_id", "candidate_sha256", "checker", "evidence"}:
        raise CatalogError("E_VALIDATION_FIELDS: unexpected or missing validation fields")
    if validation.get("status") != "passed" or validation.get("world_id") != world_id or validation.get("candidate_sha256") != build_id:
        raise CatalogError("E_VALIDATION_BINDING: validation must pass and bind to this candidate")
    checker = validation.get("checker")
    if not isinstance(checker, dict) or not all(isinstance(checker.get(k), str) and checker[k].strip() for k in ("id", "version")):
        raise CatalogError("E_VALIDATION_CHECKER: checker id and version are required")
    evidence = validation.get("evidence", [])
    if not isinstance(evidence, list) or not evidence:
        raise CatalogError("E_VALIDATION_EVIDENCE: at least one evidence reference is required")
    for item in evidence:
        if not isinstance(item, dict) or set(item) - {"id", "sha256", "source"} or not isinstance(item.get("id"), str) or not item["id"].strip():
            raise CatalogError("E_VALIDATION_EVIDENCE: each evidence record needs an id")

    if not isinstance(approval, dict) or approval.get("schema") != "worldgen.approval/1":
        raise CatalogError("E_APPROVAL_SCHEMA: expected worldgen.approval/1")
    if set(approval) != {"schema", "decision", "world_id", "candidate_sha256", "expected_revision", "review_id", "reviewer_id"}:
        raise CatalogError("E_APPROVAL_FIELDS: unexpected or missing approval fields")
    required = ("review_id", "reviewer_id")
    if approval.get("decision") != "approved" or approval.get("world_id") != world_id or approval.get("candidate_sha256") != build_id:
        raise CatalogError("E_APPROVAL_BINDING: approval must approve this candidate")
    if type(approval.get("expected_revision")) is not int or approval.get("expected_revision") != expected_revision:
        raise CatalogError("E_APPROVAL_REVISION: approval base revision differs from the publish request")
    if any(not isinstance(approval.get(k), str) or not approval[k].strip() for k in required):
        raise CatalogError("E_APPROVAL_REVIEWER: review_id and reviewer_id are required")
    return canonical_bytes(validation), canonical_bytes(approval)


def _fsync_directory(path: Path) -> None:
    if not hasattr(os, "O_DIRECTORY"):
        return
    try:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    except OSError:
        return
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def persist_immutable_object(root: Path, build_id: str, data: bytes) -> Path:
    if sha256_bytes(data) != build_id:
        raise CatalogError("E_OBJECT_DIGEST: staged package bytes do not match build id")
    root.mkdir(parents=True, exist_ok=True)
    root = root.resolve()
    object_root = root / "objects"
    if object_root.is_symlink():
        raise CatalogError("E_OBJECT_PATH: objects directory cannot be a symlink")
    object_root.mkdir(exist_ok=True)
    prefix_dir = object_root / build_id[:2]
    if prefix_dir.is_symlink():
        raise CatalogError("E_OBJECT_PATH: object prefix cannot be a symlink")
    prefix_dir.mkdir(exist_ok=True)
    if not prefix_dir.resolve().is_relative_to(root):
        raise CatalogError("E_OBJECT_PATH: object directory escaped catalog root")
    destination = prefix_dir / f"{build_id}.json"
    if destination.is_symlink():
        raise CatalogError("E_OBJECT_PATH: immutable object cannot be a symlink")
    if destination.exists():
        current = destination.read_bytes()
        if current != data:
            raise CatalogError(f"E_OBJECT_CORRUPT: immutable object differs at {destination}")
        return destination
    fd, staged_name = tempfile.mkstemp(prefix=".pending-", dir=destination.parent)
    staged = Path(staged_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if staged.read_bytes() != data:
            raise CatalogError("E_OBJECT_VERIFY: staged bytes changed during write")
        try:
            os.link(staged, destination)
        except FileExistsError:
            if destination.read_bytes() != data:
                raise CatalogError(f"E_OBJECT_CORRUPT: immutable object differs at {destination}")
        except OSError:
            # A same-directory replace is atomic. The content-addressed path is
            # derived from the bytes; a concurrent equal digest is equal content.
            if destination.exists():
                if destination.read_bytes() != data:
                    raise CatalogError(f"E_OBJECT_CORRUPT: immutable object differs at {destination}")
            else:
                os.replace(staged, destination)
        _fsync_directory(destination.parent)
        if destination.read_bytes() != data:
            raise CatalogError("E_OBJECT_VERIFY: promoted object failed read-back")
        return destination
    finally:
        try:
            staged.unlink(missing_ok=True)
        except OSError:
            pass


def _connect(root: Path, read_only: bool = False) -> sqlite3.Connection:
    if not read_only:
        root.mkdir(parents=True, exist_ok=True)
    root = root.resolve()
    database = root / "authoring_catalog.sqlite"
    if database.is_symlink():
        raise CatalogError("E_CATALOG_PATH: catalog database cannot be a symlink")
    if read_only and not database.is_file():
        raise CatalogError("E_CATALOG_MISSING: no authoring catalog exists")
    location = database.resolve().as_uri() + "?mode=ro" if read_only else str(database)
    connection = sqlite3.connect(location, uri=read_only, timeout=5.0, isolation_level=None)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA busy_timeout = 5000")
    if not read_only:
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = FULL")
    version = int(connection.execute("PRAGMA user_version").fetchone()[0])
    if version == 0 and not read_only:
        connection.executescript("""
            BEGIN IMMEDIATE;
            CREATE TABLE IF NOT EXISTS builds (
                world_id TEXT NOT NULL,
                revision INTEGER NOT NULL CHECK (revision > 0),
                build_id TEXT NOT NULL,
                semantic_sha256 TEXT NOT NULL,
                presentation_sha256 TEXT NOT NULL,
                artifact_path TEXT NOT NULL,
                validation_json BLOB NOT NULL,
                approval_json BLOB NOT NULL,
                published_utc TEXT NOT NULL,
                PRIMARY KEY (world_id, revision),
                UNIQUE (world_id, revision, build_id)
            );
            CREATE TABLE IF NOT EXISTS heads (
                world_id TEXT PRIMARY KEY,
                revision INTEGER NOT NULL CHECK (revision > 0),
                build_id TEXT NOT NULL,
                FOREIGN KEY (world_id, revision, build_id)
                    REFERENCES builds(world_id, revision, build_id)
            );
            PRAGMA user_version = 1;
            COMMIT;
        """)
    elif version != CATALOG_SCHEMA:
        connection.close()
        raise CatalogError(f"E_CATALOG_VERSION: supported={CATALOG_SCHEMA} found={version}")
    return connection


def publish(
    root: Path, package: dict[str, Any], validation: Any,
    approval: Any, expected_revision: int,
) -> dict[str, Any]:
    world_id, build_id, semantic_hash, presentation_hash, data = package_identity(package)
    if expected_revision < 0:
        raise CatalogError("E_EXPECTED_REVISION: expected revision must be non-negative")
    validation_bytes, approval_bytes = validate_attestations(package, build_id, expected_revision, validation, approval)
    artifact = persist_immutable_object(root, build_id, data)
    artifact_relpath = artifact.relative_to(root.resolve()).as_posix()
    connection = _connect(root)
    try:
        try:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT revision FROM heads WHERE world_id = ?", (world_id,)).fetchone()
            actual_revision = int(row["revision"]) if row else 0
            if actual_revision != expected_revision:
                raise StaleRevision(f"STALE_REVISION: world={world_id} expected={expected_revision} actual={actual_revision}")
            next_revision = actual_revision + 1
            published_utc = datetime.now(timezone.utc).isoformat(timespec="seconds")
            connection.execute(
                "INSERT INTO builds(world_id,revision,build_id,semantic_sha256,presentation_sha256,artifact_path,validation_json,approval_json,published_utc) VALUES(?,?,?,?,?,?,?,?,?)",
                (world_id, next_revision, build_id, semantic_hash, presentation_hash, artifact_relpath, validation_bytes, approval_bytes, published_utc),
            )
            connection.execute(
                "INSERT INTO heads(world_id,revision,build_id) VALUES(?,?,?) ON CONFLICT(world_id) DO UPDATE SET revision=excluded.revision,build_id=excluded.build_id",
                (world_id, next_revision, build_id),
            )
            connection.execute("COMMIT")
            return {"status": "published", "world_id": world_id, "revision": next_revision, "build_id": build_id,
                    "semantic_sha256": semantic_hash, "presentation_sha256": presentation_hash,
                    "artifact": artifact_relpath, "catalog": str((root / "authoring_catalog.sqlite").resolve())}
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise
    except sqlite3.OperationalError as exc:
        raise CatalogError(f"E_CATALOG_BUSY_OR_IO: {exc}") from exc
    finally:
        connection.close()


def resolve(root: Path, world_id: str, revision: int | None = None) -> dict[str, Any]:
    connection = _connect(root, read_only=True)
    try:
        if revision is None:
            row = connection.execute(
                "SELECT b.* FROM heads h JOIN builds b ON b.world_id=h.world_id AND b.revision=h.revision AND b.build_id=h.build_id WHERE h.world_id=?",
                (world_id,),
            ).fetchone()
        else:
            row = connection.execute("SELECT * FROM builds WHERE world_id=? AND revision=?", (world_id, revision)).fetchone()
        if row is None:
            raise CatalogError(f"E_BUILD_MISSING: no published build for {world_id} revision={revision or 'head'}")
        artifact = (root.resolve() / Path(row["artifact_path"])).resolve()
        if root.resolve() not in artifact.parents:
            raise CatalogError("E_ARTIFACT_PATH: catalog artifact escaped its root")
        raw = artifact.read_bytes()
        if sha256_bytes(raw) != row["build_id"]:
            raise CatalogError("E_OBJECT_CORRUPT: published artifact digest mismatch")
        package = load_json(artifact)
        actual = package_identity(package)
        if actual[:4] != (world_id, row["build_id"], row["semantic_sha256"], row["presentation_sha256"]):
            raise CatalogError("E_BUILD_BINDING: artifact identity differs from its catalog row")
        return {"world_id": world_id, "revision": int(row["revision"]), "build_id": row["build_id"],
                "artifact": artifact, "package": package}
    except OSError as exc:
        raise CatalogError(f"E_OBJECT_READ: {exc}") from exc
    finally:
        connection.close()


def history(root: Path, world_id: str) -> list[dict[str, Any]]:
    connection = _connect(root, read_only=True)
    try:
        rows = connection.execute("SELECT revision,build_id,semantic_sha256,presentation_sha256,artifact_path,published_utc FROM builds WHERE world_id=? ORDER BY revision", (world_id,)).fetchall()
        return [dict(row) for row in rows]
    finally:
        connection.close()


def atomic_export(package: dict[str, Any], destination: Path) -> None:
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    data = canonical_bytes(package) + b"\n"
    fd, staged_name = tempfile.mkstemp(prefix=f".{destination.name}.", suffix=".pending", dir=destination.parent)
    staged = Path(staged_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(staged, destination)
        _fsync_directory(destination.parent)
    finally:
        staged.unlink(missing_ok=True)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog-root", type=Path, required=True, help="Authoring-only catalog and immutable object directory")
    commands = parser.add_subparsers(dest="command", required=True)
    pub = commands.add_parser("publish", help="CAS-publish a validated approved WorldPackage/1")
    pub.add_argument("--candidate", type=Path, required=True)
    pub.add_argument("--validation", type=Path, required=True)
    pub.add_argument("--approval", type=Path, required=True)
    pub.add_argument("--expected-revision", type=int, required=True)
    resolve_cmd = commands.add_parser("resolve", help="Resolve an immutable head or historical revision for export")
    resolve_cmd.add_argument("--world-id", required=True)
    resolve_cmd.add_argument("--revision", type=int)
    resolve_cmd.add_argument("--output", type=Path, required=True)
    history_cmd = commands.add_parser("history", help="List published revisions for one world")
    history_cmd.add_argument("--world-id", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "publish":
            package = load_json(args.candidate)
            validation = load_json(args.validation)
            approval = load_json(args.approval)
            result = publish(args.catalog_root, package, validation, approval, args.expected_revision)
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        elif args.command == "resolve":
            record = resolve(args.catalog_root, args.world_id, args.revision)
            atomic_export(record["package"], args.output)
            print(json.dumps({"status": "resolved", "world_id": record["world_id"], "revision": record["revision"],
                              "build_id": record["build_id"], "output": str(args.output.resolve())}, ensure_ascii=False, sort_keys=True))
        else:
            print(json.dumps({"world_id": args.world_id, "revisions": history(args.catalog_root, args.world_id)}, ensure_ascii=False, sort_keys=True))
        return 0
    except StaleRevision as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except (CatalogError, sqlite3.Error, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
