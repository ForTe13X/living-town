"""Verify a relocatable rendered capture bundle and its fresh-process resume leg."""

from __future__ import annotations

import argparse
import hashlib
import json
import ntpath
import re
import struct
import sys
from pathlib import Path, PureWindowsPath

import source_copy


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"Expected JSON object: {path}")
    return payload


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def original_windows_path(value: str, leaf: str) -> PureWindowsPath:
    require(isinstance(value, str), f"Missing original {leaf} path")
    path = PureWindowsPath(value)
    require(path.is_absolute() and path.name.casefold() == leaf.casefold(),
            f"Unexpected original {leaf} path: {value}")
    return path


def unique_argument(arguments: list, flag: str) -> str:
    require(isinstance(arguments, list) and arguments.count(flag) == 1,
            f"Expected one {flag} Godot argument")
    position = arguments.index(flag)
    require(position + 1 < len(arguments) and isinstance(arguments[position + 1], str),
            f"Missing {flag} argument value")
    return arguments[position + 1]


def verify_supervisor_origin(receipt: dict, leg: Path, manifest: dict) -> None:
    """Tie original run paths together while allowing the bundle to move later."""
    project = original_windows_path(receipt.get("project_path"), "game")
    arguments = receipt.get("arguments")
    bridge = original_windows_path(unique_argument(arguments, "--bridge-dir"), leg.name)
    script = original_windows_path(unique_argument(arguments, "--script"), "live_bridge.gd")
    repo = PureWindowsPath(receipt.get("repo", ""))
    require(ntpath.normcase(ntpath.normpath(str(project.parent))) ==
            ntpath.normcase(ntpath.normpath(str(bridge.parent))),
            "Supervisor project and bridge directory have different capture roots")
    require(repo.is_absolute() and ntpath.normcase(ntpath.normpath(str(script))) ==
            ntpath.normcase(ntpath.normpath(str(repo / "tools" / "in_game_capture" / "live_bridge.gd")))
            and unique_argument(arguments, "--expected-user-dir-name") == manifest["user_dir_name"],
            "Supervisor did not run the capture bridge and isolated user profile")
    require(receipt.get("game_tree") == manifest["source_game_tree"]
            and receipt.get("game_tree_after") == manifest["source_game_tree"]
            and receipt.get("source_head_after") == manifest["instrumentation_commit"],
            "Supervisor source tree or tool commit changed")


def verify_supervisor_logs(receipt_path: Path, receipt: dict) -> None:
    files = receipt.get("files")
    require(isinstance(files, dict) and set(files) == {"godot", "stdout", "stderr"},
            "Supervisor log inventory is incomplete")
    for kind in ("godot", "stdout", "stderr"):
        name = f"{kind}.log"
        info = files[kind]
        require(isinstance(info, dict), f"Missing supervisor {kind} log metadata")
        original = original_windows_path(info.get("path"), name)
        require(original.parent.name == receipt.get("run_id"),
                f"Supervisor {kind} log belongs to another run")
        local = receipt_path.parent / name
        require(local.is_file() and local.stat().st_size == info.get("bytes")
                and digest(local) == info.get("sha256"),
                f"Supervisor {kind} log bytes differ from receipt")
    require(receipt.get("injected_log") == files["godot"]["path"],
            "Supervisor injected log differs from retained Godot log")


def supervisor_receipt(leg: Path, manifest: dict) -> dict:
    receipts = list((leg / "supervisor").glob("*/receipt.json"))
    require(len(receipts) == 1, f"Expected one supervisor receipt for {leg.name}")
    receipt = read_json(receipts[0])
    require(receipt.get("contract") == "living-town-supervised-godot-v3", "Wrong supervisor contract")
    require(receipt.get("outcome") == "pass" and receipt.get("exit_code") == 0, "Godot did not pass")
    require(receipt.get("source_stable") is True and receipt.get("cleanup_verified") is True,
            "Source drift or process survivor")
    require(receipt.get("source_identity") == "external_project_copy"
            and receipt.get("external_project_copy") is True, "External copy was not disclosed")
    require(receipt.get("source_head") == manifest["instrumentation_commit"],
            "Capture tool commit differs from manifest")
    verify_supervisor_origin(receipt, leg, manifest)
    verify_supervisor_logs(receipts[0], receipt)
    return receipt


def relative_png(leg: Path, value: str) -> Path:
    target = source_copy.safe_relative_target(leg, value)
    require(value.startswith("observations/") and len(value.split("/")) == 2
            and target.suffix == ".png", "Unexpected PNG location")
    return target


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    require(header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR",
            f"Invalid PNG header: {path}")
    return struct.unpack(">II", header[16:24])


def save_proof(leg: Path, name: str) -> dict | None:
    proof_path = leg / f"save-{name}.json"
    if not proof_path.exists():
        return None
    proof = read_json(proof_path)
    require(proof.get("schema") == "living-town.capture-save-proof/1", "Wrong save proof schema")
    if proof.get("exists"):
        copy_name = proof.get("copy")
        require(copy_name == f"quicksave-{name}.dat", "Unexpected save copy name")
        copy = source_copy.safe_relative_target(leg, copy_name)
        require(copy.is_file() and copy.stat().st_size == proof.get("bytes"), "Missing save copy")
        require(digest(copy) == proof.get("sha256"), "Save copy hash mismatch")
    else:
        require(proof.get("sha256") == "" and proof.get("copy") == "", "Invalid absent save proof")
    return proof


def expected_result(command: dict) -> dict:
    action = command.get("action")
    if action == "key":
        return {"code": command.get("code"), "route": "Input.parse_input_event"}
    if action == "click":
        return {"point": [command.get("x"), command.get("y")], "route": "Viewport.push_input"}
    if action == "wait":
        return {"duration_ms": command.get("duration_ms")}
    if action == "quit":
        return {"reason": "requested_quit"}
    raise ValueError(f"Unknown processed command action: {action}")


def verify_action_receipt(command_path: Path, command: dict, receipt: dict, seq: int) -> None:
    require(command.get("schema") == "living-town.agent-command/1" and command.get("seq") == seq,
            f"Invalid command {seq}")
    require(receipt.get("schema") == "living-town.agent-receipt/1"
            and receipt.get("seq") == seq and receipt.get("accepted") is True
            and receipt.get("rendered_capture_ok") is True
            and receipt.get("action") == command.get("action")
            and receipt.get("before_observation") == seq - 1
            and receipt.get("after_observation") == seq
            and receipt.get("result") == expected_result(command)
            and receipt.get("command_sha256") == digest(command_path),
            f"Invalid action receipt {seq}")


def verify_leg(root: Path, name: str, manifest: dict) -> dict:
    leg = root / name
    require(leg.is_dir(), f"Missing {name} leg")
    receipt = supervisor_receipt(leg, manifest)
    terminal = read_json(leg / "terminal.json")
    require(terminal.get("status") == "quit", f"{name} did not end through quit")
    observations = sorted((leg / "observations").glob("*.json"))
    require(len(observations) >= 2, f"No rendered observations in {name}")
    require([path.name for path in observations] ==
            [f"{seq:06d}.json" for seq in range(len(observations))], "Observation sequence has a gap")
    observed = []
    for seq, path in enumerate(observations):
        item = read_json(path)
        require(item.get("schema") == "living-town.agent-observation/1" and item.get("seq") == seq,
                f"Wrong observation at {name}/{seq}")
        png = relative_png(leg, item.get("png", ""))
        require(png.is_file() and digest(png) == item.get("png_sha256"), f"PNG hash mismatch at {name}/{seq}")
        require(png_dimensions(png) == (1280, 768) and item.get("viewport") == [1280, 768],
                f"Wrong rendered viewport at {name}/{seq}")
        user_dir_name = item.get("user_data_dir", "").replace("\\", "/").rstrip("/").split("/")[-1]
        require(user_dir_name == manifest["user_dir_name"], f"Wrong user:// profile at {name}/{seq}")
        save = item.get("save", {})
        if save.get("exists"):
            require(bool(re.fullmatch(r"[0-9a-f]{64}", save.get("sha256", ""))), "Invalid save hash")
        observed.append(item)
    commands = sorted((leg / "processed").glob("*.json"))
    receipts = sorted((leg / "receipts").glob("*.json"))
    count = len(observed) - 1
    require(len(commands) == count and len(receipts) == count
            and terminal.get("seq") == count, f"Action sequence has a gap in {name}")
    actions = []
    for seq in range(1, count + 1):
        command_path = leg / "processed" / f"{seq:06d}.json"
        receipt_path = leg / "receipts" / f"{seq:06d}.json"
        require(command_path.is_file() and receipt_path.is_file(), f"Missing action {name}/{seq}")
        command, action_receipt = read_json(command_path), read_json(receipt_path)
        verify_action_receipt(command_path, command, action_receipt, seq)
        actions.append(command)
    require(actions[-1].get("action") == "quit", f"{name} did not request quit")
    after_save = save_proof(leg, "after")
    require(after_save is not None, f"Missing after-save proof in {name}")
    if after_save["exists"]:
        require(observed[-1]["save"] == {"exists": True, "sha256": after_save["sha256"]},
                f"Save changed after final {name} observation")
    return {
        "name": name,
        "receipt": receipt,
        "observations": observed,
        "actions": actions,
        "after_save": after_save,
        "before_save": save_proof(leg, "before"),
    }


def verify_resume(session: dict, resume: dict) -> dict:
    session_save = session["after_save"]
    before_resume = resume["before_save"]
    require(session_save["exists"] and before_resume is not None and before_resume["exists"],
            "Fresh-process resume has no saved input")
    require(session_save["sha256"] == before_resume["sha256"]
            == resume["observations"][0]["save"]["sha256"],
            "Fresh process did not start from the session quicksave bytes")
    f5 = [index for index, action in enumerate(session["actions"], start=1)
          if action.get("action") == "key" and action.get("code") == "F5"]
    f8 = [index for index, action in enumerate(resume["actions"], start=1)
          if action.get("action") == "key" and action.get("code") == "F8"]
    require(f5 and f8, "Session F5 or fresh-process F8 is missing")
    saved = session["observations"][f5[-1]]
    loaded = resume["observations"][f8[-1]]
    require(saved["save"] == {"exists": True, "sha256": session_save["sha256"]},
            "F5 observation does not match the retained quicksave")
    require(saved["running"] is False and loaded["running"] is False,
            "Pause before F5 so save/load tick identity is measurable")
    require(loaded["life"]["active"] and loaded["life"]["resident"] == saved["life"]["resident"],
            "F8 did not restore the selected resident")
    require((loaded["life"]["space"], loaded["life"]["floor"]) ==
            (saved["life"]["space"], saved["life"]["floor"]),
            "F8 restored a different space or floor")
    require((loaded["day"], loaded["tick"], loaded["life"]["position"]) ==
            (saved["day"], saved["tick"], saved["life"]["position"]),
            "F8 did not restore the paused day, tick, and position")
    require(session["receipt"]["run_id"] != resume["receipt"]["run_id"]
            and session["receipt"]["finished_utc"] <= resume["receipt"]["started_utc"],
            "Resume was not a later Godot process")
    return {"quicksave_sha256": session_save["sha256"],
            "resident": loaded["life"]["resident"],
            "space": loaded["life"]["space"], "floor": loaded["life"]["floor"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_root", type=Path)
    parser.add_argument("--require-resume", action="store_true")
    args = parser.parse_args()
    root = args.capture_root.resolve(strict=True)
    try:
        manifest = read_json(root / "source-manifest.json")
        copy_proof = source_copy.verify(root, "portable-recheck")
        for phase in ("prepare", "session-before", "session-after"):
            proof = read_json(root / f"source-copy-{phase}.json")
            require(proof.get("pass") is True and proof.get("source_commit") == manifest["source_commit"]
                    and proof.get("source_game_tree") == manifest["source_game_tree"],
                    f"Missing or invalid copy proof: {phase}")
        session = verify_leg(root, "session", manifest)
        resume = None
        resume_summary = None
        if args.require_resume or (root / "resume").is_dir():
            for phase in ("resume-before", "resume-after"):
                proof = read_json(root / f"source-copy-{phase}.json")
                require(proof.get("pass") is True, f"Missing or invalid copy proof: {phase}")
            resume = verify_leg(root, "resume", manifest)
            resume_summary = verify_resume(session, resume)
        summary = {
            "schema": "living-town.capture-verification/1",
            "result": "pass",
            "source_commit": manifest["source_commit"],
            "source_game_tree": manifest["source_game_tree"],
            "copy_proof": copy_proof["pass"],
            "user_dir_name": manifest["user_dir_name"],
            "input_kind": "Godot-injected viewport events",
            "session": {"rendered_pngs": len(session["observations"]),
                        "accepted_actions": len(session["actions"]),
                        "supervisor_run_id": session["receipt"]["run_id"]},
            "resume": None if resume is None else {
                "rendered_pngs": len(resume["observations"]),
                "accepted_actions": len(resume["actions"]),
                "supervisor_run_id": resume["receipt"]["run_id"],
                **resume_summary,
            },
        }
        source_copy.write_json(root / "verify-summary.json", summary)
        print(json.dumps(summary))
        return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"CAPTURE_VERIFY_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
