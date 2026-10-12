#!/usr/bin/env python3
"""Path-free JSON protocol adapter for WorldGen authoring commands.

The request is data on stdin. Project paths, script selection, and temporary
file names are adapter-owned; request values can never select code or files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
GODOT_SCRIPT = "res://addons/worldgen/core/worldgen_authoring_command_cli.gd"
MAX_REQUEST_BYTES = 1_048_576
MAX_REPAIR_BUDGET = 250_000
IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
DIGEST = re.compile(r"^[a-f0-9]{64}$")
EDIT_PATH = re.compile(r"^stages/[A-Za-z0-9][A-Za-z0-9_.-]{0,63}/parameters/[A-Za-z0-9_]{1,64}$")
FORBIDDEN_KEYS = {"path", "script", "code", "shell", "command_line", "system_prompt", "asset_metadata", "prompt"}
COMMAND_FIELDS = {
    "inspect": {"schema", "request_id", "command", "world_id"},
    "validate": {"schema", "request_id", "command", "candidate_sha256"},
    "propose": {"schema", "request_id", "command", "world_id", "base_recipe_sha256", "base_package_sha256", "base_revision", "patch_id", "declared_class", "changes"},
    "repair": {"schema", "request_id", "command", "repair_request"},
    "publish-request": {"schema", "request_id", "command", "world_id", "candidate_sha256", "expected_revision"},
}


class ProtocolError(ValueError):
    pass


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError(f"E_JSON_DUPLICATE_KEY: {key}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ProtocolError(f"E_JSON_CONSTANT: {value}")


def _walk_forbidden(value: Any, location: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            is_patch_path = key == "path" and re.fullmatch(r"\$\.changes\[\d+\]", location) is not None
            if key.lower() in FORBIDDEN_KEYS and not is_patch_path:
                raise ProtocolError(f"E_REQUEST_FORBIDDEN_FIELD: {location}.{key}")
            _walk_forbidden(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _walk_forbidden(child, f"{location}[{index}]")


def validate_request(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProtocolError("E_REQUEST_TYPE: request must be a JSON object")
    command = value.get("command")
    if command not in COMMAND_FIELDS:
        raise ProtocolError("E_COMMAND_UNKNOWN")
    expected = COMMAND_FIELDS[command]
    if set(value) != expected:
        unsupported = sorted(set(value) - expected)
        missing = sorted(expected - set(value))
        raise ProtocolError(f"E_REQUEST_FIELDS: unsupported={unsupported} missing={missing}")
    if value.get("schema") != "worldgen.authoring_command/1":
        raise ProtocolError("E_REQUEST_SCHEMA")
    if not isinstance(value.get("request_id"), str) or not IDENTIFIER.fullmatch(value["request_id"]):
        raise ProtocolError("E_REQUEST_ID")
    _walk_forbidden(value)

    if "world_id" in value and (not isinstance(value["world_id"], str) or not IDENTIFIER.fullmatch(value["world_id"])):
        raise ProtocolError("E_WORLD_ID")
    if "candidate_sha256" in value and (not isinstance(value["candidate_sha256"], str) or not DIGEST.fullmatch(value["candidate_sha256"])):
        raise ProtocolError("E_CANDIDATE_DIGEST")
    if "base_recipe_sha256" in value and (not isinstance(value["base_recipe_sha256"], str) or not DIGEST.fullmatch(value["base_recipe_sha256"])):
        raise ProtocolError("E_RECIPE_DIGEST")
    if "base_package_sha256" in value and (not isinstance(value["base_package_sha256"], str) or not DIGEST.fullmatch(value["base_package_sha256"])):
        raise ProtocolError("E_PACKAGE_DIGEST")
    if "base_revision" in value and (type(value["base_revision"]) is not int or value["base_revision"] < 0):
        raise ProtocolError("E_BASE_REVISION")
    if "expected_revision" in value and (type(value["expected_revision"]) is not int or value["expected_revision"] < 0):
        raise ProtocolError("E_EXPECTED_REVISION")

    if command == "propose":
        if not isinstance(value["patch_id"], str) or not IDENTIFIER.fullmatch(value["patch_id"]):
            raise ProtocolError("E_PATCH_ID")
        if value["declared_class"] not in ("visual", "semantic"):
            raise ProtocolError("E_DECLARED_CLASS")
        changes = value["changes"]
        if not isinstance(changes, list) or not 1 <= len(changes) <= 64:
            raise ProtocolError("E_CHANGES_BOUNDS")
        for change in changes:
            if not isinstance(change, dict) or set(change) != {"path", "value"}:
                raise ProtocolError("E_CHANGE_FIELDS")
            if not isinstance(change["path"], str) or not EDIT_PATH.fullmatch(change["path"]):
                raise ProtocolError("E_EDIT_PATH")
            _walk_forbidden(change["value"], "$.changes.value")
    elif command == "repair":
        _validate_repair_request(value["repair_request"])
    return value


def _validate_repair_request(request: Any) -> None:
    fields = {"schema", "scope_id", "base_revision", "extent", "boundary", "boundary_interfaces", "placements", "dirty_ids", "hard_pins", "protected_ids", "candidate_assignments", "operation_budget"}
    required = {"schema", "scope_id", "base_revision", "extent", "boundary", "placements", "dirty_ids", "candidate_assignments", "operation_budget"}
    if not isinstance(request, dict) or set(request) - fields or required - set(request):
        raise ProtocolError("E_REPAIR_FIELDS")
    if request.get("schema") != "worldgen.local_repair_request/1":
        raise ProtocolError("E_REPAIR_SCHEMA")
    if not isinstance(request.get("scope_id"), str) or not IDENTIFIER.fullmatch(request["scope_id"]):
        raise ProtocolError("E_REPAIR_SCOPE")
    if type(request.get("base_revision")) is not int or request["base_revision"] < 0:
        raise ProtocolError("E_REPAIR_REVISION")
    budget = request.get("operation_budget")
    if type(budget) is not int or not 1 <= budget <= MAX_REPAIR_BUDGET:
        raise ProtocolError("E_REPAIR_BUDGET")
    if not isinstance(request.get("placements"), list) or len(request["placements"]) > 4096:
        raise ProtocolError("E_REPAIR_PLACEMENTS")
    if not isinstance(request.get("dirty_ids"), list) or not 1 <= len(request["dirty_ids"]) <= 256:
        raise ProtocolError("E_REPAIR_DIRTY_IDS")
    _walk_forbidden(request, "$.repair_request")


def _error(request_id: str, command: str, code: str) -> dict[str, Any]:
    return {"schema": "worldgen.authoring_result/1", "request_id": request_id, "command": command, "ok": False, "status": "INVALID_REQUEST", "detail": {"errors": [code]}}


def _read_request() -> dict[str, Any]:
    raw = sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
    if len(raw) > MAX_REQUEST_BYTES:
        raise ProtocolError("E_REQUEST_SIZE")
    try:
        parsed = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs, parse_constant=_reject_constant)
    except UnicodeDecodeError as exc:
        raise ProtocolError("E_REQUEST_UTF8") from exc
    except json.JSONDecodeError as exc:
        raise ProtocolError(f"E_REQUEST_JSON: {exc.msg}") from exc
    return validate_request(parsed)


def _find_godot(configured: str | None) -> Path | None:
    candidate = configured or os.environ.get("WORLDGEN_GODOT_BIN") or shutil.which("godot") or shutil.which("godot_console")
    if not candidate:
        return None
    path = Path(candidate).expanduser().resolve()
    return path if path.is_file() else None


def run_request(request: dict[str, Any], godot: Path) -> dict[str, Any]:
    version = subprocess.run([str(godot), "--version"], capture_output=True, text=True, timeout=15, check=False, shell=False)
    version_text = (version.stdout + version.stderr).strip()
    if version.returncode != 0 or not version_text.startswith("4.6.2"):
        raise ProtocolError("E_GODOT_VERSION: expected Godot 4.6.2, got " + (version_text[:80] or "no version response"))
    with tempfile.TemporaryDirectory(prefix="worldgen-authoring-") as temp_name:
        temp = Path(temp_name)
        request_file = temp / "request.json"
        response_file = temp / "response.json"
        request_file.write_text(json.dumps(request, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        process = subprocess.run(
            [str(godot), "--headless", "--path", str(GAME), "--script", GODOT_SCRIPT, "--", str(request_file), str(response_file)],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
            shell=False,
            cwd=ROOT,
        )
        if not response_file.is_file():
            diagnostic = (process.stderr or process.stdout).strip().replace("\r", "")[-1200:]
            raise ProtocolError(f"E_GODOT_COMMAND: exit={process.returncode} {diagnostic}")
        response = json.loads(response_file.read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicate_pairs, parse_constant=_reject_constant)
        response["native_version"] = version_text
        return response


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run a bounded WorldGen authoring command from one JSON request on stdin.")
    parser.add_argument("--godot-bin", help="Trusted Godot 4.6.2 executable path; may also be set with WORLDGEN_GODOT_BIN")
    args = parser.parse_args(argv)
    request_id = ""
    command = ""
    try:
        request = _read_request()
        request_id = request["request_id"]
        command = request["command"]
        godot = _find_godot(args.godot_bin)
        if godot is None:
            raise ProtocolError("E_GODOT_BINARY: configure the trusted Godot 4.6.2 executable")
        response = run_request(request, godot)
    except (ProtocolError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        response = _error(request_id, command, str(exc))
    sys.stdout.write(json.dumps(response, ensure_ascii=False, sort_keys=True) + "\n")
    return 0 if bool(response.get("ok", False)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
