"""Compose local asset stages without treating technical success as art approval.

Standard library only. Commands execute argv arrays with shell=False. Recipes
are executable project configuration, not a sandbox for untrusted workflows.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

SCHEMA = "living_town.asset_toolbox.v1"
RECIPE_SCHEMA = "living_town.asset_toolbox.recipe.v1"
EFFECTS = {"network", "credits", "weights", "workspace_write"}
IGNORE = {"__pycache__", ".git", ".godot"}
TOKEN = re.compile(r"\$\{([^}]+)\}")
SAFE_ID = re.compile(r"^[a-z][a-z0-9_-]*$")


class ToolboxError(ValueError):
    def __init__(self, message, code=2):
        super().__init__(message)
        self.code = code


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=False, allow_nan=False)
        stream.write("\n")
    temporary.replace(path)


def link(path):
    return path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction())


def files(path):
    """Deterministic regular-file inventory; never follow links/junctions."""
    path = Path(path)
    if link(path):
        raise ToolboxError("Linked input/output is not a stable content tree: " + str(path))
    if path.is_file():
        return [path]
    if not path.is_dir():
        raise ToolboxError("Missing input/output: " + str(path))
    result = []
    for parent, folders, names in os.walk(path, followlinks=False):
        folders[:] = sorted(name for name in folders if name not in IGNORE)
        for name in folders + sorted(names):
            child = Path(parent) / name
            if link(child):
                raise ToolboxError("Linked member is not supported: " + str(child))
        result.extend(Path(parent) / name for name in sorted(names)
                      if not name.endswith((".pyc", ".pyo")))
    return result


def binding(path):
    path = Path(path)
    directory = path.is_dir()
    members = files(path)
    rows = []
    for member in members:
        with member.open("rb") as stream:
            sha = hashlib.file_digest(stream, "sha256").hexdigest()
        rows.append({"path": member.relative_to(path).as_posix() if directory else member.name,
                     "bytes": member.stat().st_size, "sha256": sha})
    return {"path": str(path), "kind": "directory" if directory else "file",
            "sha256": digest(rows) if directory else rows[0]["sha256"], "files": rows}


def bindings(paths):
    return {str(path): binding(path) for path in sorted(set(paths), key=str)}


class Recipe:
    def __init__(self, recipe_path, config_path, iteration):
        self.recipe_path = Path(recipe_path).absolute()
        self.config_path = Path(config_path).absolute()
        self.recipe, self.config = read(self.recipe_path), read(self.config_path)
        if not isinstance(self.recipe, dict) or not isinstance(self.config, dict):
            raise ToolboxError("Recipe and configuration must be JSON objects")
        self.iteration = Path(iteration).absolute()
        self.repo = Path(self.config["repo"]).absolute()
        if not Path(self.config["repo"]).is_absolute():
            raise ToolboxError("config.repo must be an absolute path")
        self.values = {"repo": str(self.repo), "iteration": str(self.iteration)}
        for group in ("runtime", "input"):
            data = self.config.get("runtimes" if group == "runtime" else "inputs", {})
            if not isinstance(data, dict):
                raise ToolboxError("Configuration runtimes/inputs must be objects")
            for key, value in data.items():
                if not SAFE_ID.fullmatch(key) or not isinstance(value, str):
                    raise ToolboxError("Invalid configuration key/value: " + key)
                value = self.expand(value)
                if not Path(value).is_absolute():
                    raise ToolboxError("Explicit absolute path required: " + group + "." + key)
                self.values[group + "." + key] = str(Path(value).absolute())
        self.stages = self.recipe.get("stages", [])
        self.validate()

    def expand(self, value):
        if not isinstance(value, str):
            raise ToolboxError("Arguments and paths must be strings")
        def replacement(match):
            key = match.group(1)
            if key not in self.values:
                raise ToolboxError("Unresolved token: " + key)
            return self.values[key]
        expanded = TOKEN.sub(replacement, value)
        if "${" in expanded or "\x00" in expanded:
            raise ToolboxError("Malformed token or NUL in recipe")
        return expanded

    def paths(self, stage, key):
        result = [Path(self.expand(p)) for p in stage.get(key, [])]
        if any(not p.is_absolute() for p in result):
            raise ToolboxError("Recipe paths must be absolute or use an absolute path token")
        return result

    def owned(self, path):
        path = Path(path)
        # Resolve existing parents too, to reject an output through a junction.
        if not path.resolve().is_relative_to(self.iteration.resolve()) or path == self.iteration:
            raise ToolboxError("Output must be inside this iteration: " + str(path))
        return path

    def validate(self):
        if self.recipe.get("schema") != RECIPE_SCHEMA or not isinstance(self.stages, list) or not self.stages:
            raise ToolboxError("Expected recipe v1 with nonempty stages")
        seen, outputs = set(), []
        required = ["runtime." + k for k in self.recipe.get("required_runtimes", [])]
        required += ["input." + k for k in self.recipe.get("required_inputs", [])]
        for key in required:
            if key not in self.values:
                raise ToolboxError("Required configuration missing: " + key)
        for stage in self.stages:
            if not isinstance(stage, dict):
                raise ToolboxError("Every stage must be a JSON object")
            ident = stage.get("id", "")
            if not isinstance(ident, str):
                raise ToolboxError("Stage ID must be a string")
            if not SAFE_ID.fullmatch(ident) or ident in seen:
                raise ToolboxError("Invalid or duplicate stage ID: " + ident)
            for key in ("depends_on", "effects", "inputs", "outputs", "artifacts", "criteria"):
                value = stage.get(key, [])
                if not isinstance(value, list) or any(not isinstance(v, str) or not v for v in value):
                    raise ToolboxError("Stage " + key + " must be a string array: " + ident)
            if not set(stage.get("depends_on", [])).issubset(seen):
                raise ToolboxError("Stages must follow their dependencies: " + ident)
            if not set(stage.get("effects", [])).issubset(EFFECTS):
                raise ToolboxError("Unknown effects: " + ident)
            if stage.get("kind") not in {"command", "review"}:
                raise ToolboxError("Unknown stage kind: " + ident)
            if stage["kind"] == "command":
                argv = stage.get("argv")
                if not isinstance(argv, list) or not argv:
                    raise ToolboxError("Use an argv array, never a shell command: " + ident)
                expanded = [self.expand(arg) for arg in argv]
                runtimes = {value for key, value in self.values.items() if key.startswith("runtime.")}
                if expanded[0] not in runtimes:
                    raise ToolboxError("argv[0] must be an explicitly configured runtime: " + ident)
                timeout = stage.get("timeout_seconds", 3600)
                if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not 0 < timeout <= 86400:
                    raise ToolboxError("Invalid timeout: " + ident)
                if not stage.get("outputs"):
                    raise ToolboxError("Command stages require declared outputs: " + ident)
            elif not stage.get("artifacts") or not stage.get("criteria"):
                raise ToolboxError("Review requires real artifacts and explicit criteria: " + ident)
            checks = stage.get("checks", [])
            if not isinstance(checks, list) or any(not isinstance(c, dict) or not {"file", "pointer", "equals"} <= c.keys() for c in checks):
                raise ToolboxError("Technical checks require file, pointer and equals: " + ident)
            for check in checks:
                self.owned(Path(self.expand(check["file"])))
                if not isinstance(check["pointer"], str) or (check["pointer"] and not check["pointer"].startswith("/")):
                    raise ToolboxError("Technical checks require JSON pointers: " + ident)
            for key in ("inputs", "artifacts"):
                for path in self.paths(stage, key):
                    if not path.is_absolute():
                        raise ToolboxError("Path must be absolute: " + str(path))
            for path in self.paths(stage, "outputs"):
                self.owned(path)
                if any(path == p or path.is_relative_to(p) or p.is_relative_to(path) for p in outputs):
                    raise ToolboxError("Stage outputs must have separate ownership: " + str(path))
                outputs.append(path)
            seen.add(ident)

    def external_paths(self):
        # Bind even optional configured executables/inputs. A token used deep in
        # an argv must not evade the immutable-input ledger.
        keys = [key for key in self.values if key.startswith(("runtime.", "input."))]
        result = [Path(self.values[k]) for k in keys]
        result += [Path(self.expand(p)) for p in self.recipe.get("source_paths", [])]
        result += list(Path(__file__).parent.glob("*.py")) + [self.config_path, self.recipe_path]
        # Literal paths in a later stage are just as immutable as configured
        # tokens. Future artifacts *inside* this iteration are produced by its
        # stages and are bound when consumed; they need not exist at the start.
        for stage in self.stages:
            for key in ("inputs", "artifacts"):
                result.extend(path for path in self.paths(stage, key)
                              if not path.resolve().is_relative_to(self.iteration.resolve()))
        for path in result:
            if path.resolve().is_relative_to(self.iteration.resolve()) or self.iteration.resolve().is_relative_to(path.resolve()):
                raise ToolboxError("Immutable input/source cannot contain iteration output: " + str(path))
        return result

    def snapshot(self):
        return {"schema": SCHEMA, "recipe": self.recipe, "config": self.config,
                "iteration": str(self.iteration), "immutable_bindings": bindings(self.external_paths())}

    def plan(self):
        return {"schema": SCHEMA, "status": "PLAN_ONLY", "name": self.recipe.get("name"),
                "iteration": str(self.iteration), "network_or_engines_started": False,
                "stages": [{"id": s["id"], "kind": s["kind"], "phase": s.get("phase"),
                            "depends_on": s.get("depends_on", []), "effects": s.get("effects", []),
                            "argv": [self.expand(a) for a in s.get("argv", [])],
                            "inputs": [str(p) for p in self.paths(s, "inputs")],
                            "outputs": [str(p) for p in self.paths(s, "outputs")],
                            "criteria": s.get("criteria", [])} for s in self.stages]}


def stage_inputs(recipe, stage):
    return bindings(recipe.paths(stage, "inputs") + recipe.paths(stage, "artifacts"))


def assertions(recipe, stage):
    for check in stage.get("checks", []):
        value = read(recipe.owned(Path(recipe.expand(check["file"]))))
        pointer = check["pointer"]
        if pointer and not pointer.startswith("/"):
            raise ToolboxError("Use a JSON pointer in checks")
        for key in pointer.split("/")[1:] if pointer else []:
            key = key.replace("~1", "/").replace("~0", "~")
            value = value[int(key)] if isinstance(value, list) else value[key]
        if type(value) is not type(check["equals"]) or value != check["equals"]:
            raise ToolboxError("Technical check failed: " + stage["id"] + " " + pointer, 3)


def review_request(recipe, stage, input_bindings, freeze):
    extensions = set(stage.get("extensions", [".png", ".jpg", ".jpeg", ".mp4"]))
    artifact_files = {}
    for path in recipe.paths(stage, "artifacts"):
        for member in files(path):
            if member.suffix.lower() in extensions:
                artifact_files[str(member)] = binding(member)["files"][0]["sha256"]
    if not artifact_files:
        raise ToolboxError("No actual reviewable artifacts: " + stage["id"], 3)
    return {"schema": "living_town.asset_toolbox.art_review.v1", "stage": stage["id"],
            "freeze_sha256": freeze, "input_bindings_sha256": digest(input_bindings),
            "scope": stage.get("scope", "Only the declared artifacts and criteria; no broader asset, concept or gameplay approval."),
            "artifact_files": artifact_files, "criteria": stage["criteria"]}


def validate_review(request, review):
    if not isinstance(review, dict):
        raise ToolboxError("Art review must be a JSON object", 4)
    for key, value in request.items():
        if review.get(key) != value:
            raise ToolboxError("Review binding changed: " + key, 4)
    if (review.get("decision") != "ACCEPT" or not isinstance(review.get("reviewer"), str)
        or not review["reviewer"].strip()):
        raise ToolboxError("Actual visual review and explicit ACCEPT required", 4)
    if review.get("reviewed_files") != request["artifact_files"]:
        raise ToolboxError("Review must attest to every declared artifact's actual bytes", 4)
    results = review.get("criterion_results", [])
    if (not isinstance(results, list) or any(not isinstance(row, dict) for row in results) or
        [row.get("criterion") for row in results] != request["criteria"] or
        any(row.get("decision") != "ACCEPT" or not isinstance(row.get("observations"), str)
            or not row["observations"].strip() for row in results)):
        raise ToolboxError("Each art criterion requires an observed result", 4)


def validate_state(recipe, state):
    """A terminal label cannot substitute for complete, ordered stage records."""
    if not isinstance(state, dict) or state.get("schema") != SCHEMA or not isinstance(state.get("stages"), dict):
        raise ToolboxError("Invalid iteration state structure")
    records = state["stages"]
    ids = {stage["id"] for stage in recipe.stages}
    if set(records) - ids:
        raise ToolboxError("State contains unknown stages")
    allowed = {"COMPLETE", "RUNNING", "FAILED", "INTERRUPTED", "NEEDS_REVIEW", "PARTIAL_REVIEW",
               "CHANGES_REQUIRED", "EFFECT_NOT_ALLOWED"}
    complete, gap, unfinished = set(), False, None
    for stage in recipe.stages:
        ident = stage["id"]
        if ident not in records:
            gap = True
            continue
        row = records[ident]
        if gap or unfinished is not None:
            raise ToolboxError("State has a stage after an unexecuted or incomplete predecessor: " + ident)
        if not isinstance(row, dict) or row.get("status") not in allowed:
            raise ToolboxError("Invalid stage state: " + ident)
        if not set(stage.get("depends_on", [])).issubset(complete):
            raise ToolboxError("State stage dependencies are incomplete: " + ident)
        if row["status"] == "COMPLETE":
            complete.add(ident)
        else:
            unfinished = row["status"]
        if row["status"] in {"NEEDS_REVIEW", "PARTIAL_REVIEW", "CHANGES_REQUIRED"} and stage["kind"] != "review":
            raise ToolboxError("Art-review state on a command stage: " + ident)
    status = state.get("status")
    if status == "RECIPE_COMPLETE":
        if complete != ids:
            raise ToolboxError("RECIPE_COMPLETE requires every declared stage, including art reviews, to be COMPLETE")
    elif status == "INCOMPLETE":
        if unfinished is not None:
            raise ToolboxError("INCOMPLETE state hides an unfinished stage verdict")
    elif status not in allowed - {"COMPLETE"} or unfinished != status:
        raise ToolboxError("Top-level verdict disagrees with actual stage state")


def verify_completed(recipe, state):
    validate_state(recipe, state)
    for stage in recipe.stages:
        record = state["stages"].get(stage["id"])
        if not record or record["status"] != "COMPLETE":
            continue
        if stage_inputs(recipe, stage) != record["inputs"]:
            raise ToolboxError("Completed stage inputs changed: " + stage["id"])
        if bindings(recipe.paths(stage, "outputs")) != record["outputs"]:
            raise ToolboxError("Completed stage outputs changed: " + stage["id"])
        assertions(recipe, stage)
        if stage["kind"] == "review":
            request = review_request(recipe, stage, record["inputs"], state["freeze_sha256"])
            review_path = recipe.iteration / "reviews" / (stage["id"] + ".json")
            current = read(review_path)
            validate_review(request, current)
            if digest(current) != record["review_sha256"]:
                raise ToolboxError("Completed review changed: " + stage["id"])


def load_state(recipe):
    state = read(recipe.iteration / "state.json")
    freeze = read(recipe.iteration / "freeze.json")
    if state["freeze_sha256"] != digest(freeze) or recipe.snapshot() != freeze:
        raise ToolboxError("Recipe, runtime, input, source or iteration binding changed; use a fresh iteration")
    verify_completed(recipe, state)
    return state


def run(recipe, resume=False, stop_after=None, allow_effects=()):
    if stop_after and stop_after not in {s["id"] for s in recipe.stages}:
        raise ToolboxError("Unknown --stop-after stage")
    if recipe.iteration.exists():
        if not resume:
            raise ToolboxError("Iteration already exists; use --resume for unchanged completed work or a fresh path")
        state = load_state(recipe)
    else:
        if resume:
            raise ToolboxError("Cannot resume an iteration that does not exist")
        freeze = recipe.snapshot()
        recipe.iteration.mkdir(parents=True, exist_ok=False)
        write(recipe.iteration / "freeze.json", freeze)
        write(recipe.iteration / "plan.json", recipe.plan())
        state = {"schema": SCHEMA, "status": "INCOMPLETE", "created_utc": utc(),
                 "concept_fidelity": "NOT_INFERRED_FROM_RECIPE_COMPLETION",
                 "production_readiness": "NOT_EVALUATED",
                 "freeze_sha256": digest(freeze), "stages": {}}
        write(recipe.iteration / "state.json", state)
    for stage in recipe.stages:
        ident = stage["id"]
        prior = state["stages"].get(ident)
        if prior and prior["status"] == "COMPLETE":
            if stop_after == ident:
                return state
            continue
        if prior and prior["status"] not in {"NEEDS_REVIEW", "PARTIAL_REVIEW", "CHANGES_REQUIRED", "EFFECT_NOT_ALLOWED"}:
            raise ToolboxError("Partial/failed/running stage preserved; inspect its PID/logs and use a fresh iteration: " + ident, 3)
        missing_effects = set(stage.get("effects", [])) - set(allow_effects)
        if missing_effects:
            state["stages"][ident] = {"status": "EFFECT_NOT_ALLOWED", "effects": sorted(missing_effects)}
            state["status"] = "EFFECT_NOT_ALLOWED"
            write(recipe.iteration / "state.json", state)
            raise ToolboxError("Explicit --allow-effect required for: " + ", ".join(sorted(missing_effects)))
        record = {"status": "RUNNING", "started_utc": utc(), "inputs": {}}
        state["stages"][ident] = record
        state["status"] = "RUNNING"
        write(recipe.iteration / "state.json", state)
        started = time.monotonic()
        try:
            record["inputs"] = stage_inputs(recipe, stage)
            if stage["kind"] == "review":
                request = review_request(recipe, stage, record["inputs"], state["freeze_sha256"])
                path = recipe.iteration / "reviews" / (ident + ".json")
                if not path.exists():
                    write(path, {**request, "decision": "PENDING", "reviewer": "", "reviewed_files": {},
                                 "criterion_results": [{"criterion": c, "decision": "PENDING", "observations": ""}
                                                       for c in request["criteria"]]})
                review = {}
                try:
                    review = read(path)
                    validate_review(request, review)
                except ToolboxError as exc:
                    decision = review.get("decision") if isinstance(review, dict) else None
                    record["status"] = {"PARTIAL": "PARTIAL_REVIEW", "CHANGES_REQUIRED": "CHANGES_REQUIRED"}.get(decision, "NEEDS_REVIEW")
                    state["status"] = record["status"]
                    write(recipe.iteration / "state.json", state)
                    raise ToolboxError(str(exc) + "; inspect artifacts, then edit " + str(path), 4)
                record["review_sha256"] = digest(review)
            else:
                argv = [recipe.expand(arg) for arg in stage["argv"]]
                log_dir = recipe.iteration / "logs"
                log_dir.mkdir(exist_ok=True)
                record["argv"] = argv
                with (log_dir / (ident + ".stdout.log")).open("wb") as out, (log_dir / (ident + ".stderr.log")).open("wb") as err:
                    process = subprocess.Popen(argv, cwd=recipe.repo, stdout=out, stderr=err, shell=False)
                    record["pid"] = process.pid
                    write(recipe.iteration / "state.json", state)
                    try:
                        record["exit_code"] = process.wait(timeout=stage.get("timeout_seconds", 3600))
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                        raise ToolboxError("Stage timed out; parent process stopped, inspect descendants before another engine job", 3)
                if record["exit_code"] != 0:
                    raise ToolboxError("Command failed: " + ident + " exit " + str(record["exit_code"]), 3)
                assertions(recipe, stage)
            record["outputs"] = bindings(recipe.paths(stage, "outputs"))
            if recipe.snapshot() != read(recipe.iteration / "freeze.json") or stage_inputs(recipe, stage) != record["inputs"]:
                raise ToolboxError("Readonly source/input/runtime changed during stage: " + ident, 3)
            # Also protect every previously completed artifact from a later tool.
            verify_completed(recipe, state)
            record["status"] = "COMPLETE"
            record["finished_utc"] = utc()
            record["elapsed_seconds"] = round(time.monotonic() - started, 3)
            state["status"] = "INCOMPLETE"
            write(recipe.iteration / "state.json", state)
        except BaseException as exc:
            if record["status"] not in {"NEEDS_REVIEW", "PARTIAL_REVIEW", "CHANGES_REQUIRED"}:
                record["status"] = "FAILED" if not isinstance(exc, KeyboardInterrupt) else "INTERRUPTED"
                record["error"] = str(exc)
                record["finished_utc"] = utc()
                state["status"] = record["status"]
                write(recipe.iteration / "state.json", state)
            raise
        if stop_after == ident:
            if ident == recipe.stages[-1]["id"]:
                break
            return state
    state["status"] = "RECIPE_COMPLETE"
    state["completed_utc"] = utc()
    write(recipe.iteration / "state.json", state)
    return state


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("doctor", "inventory", "plan", "run", "status", "verify"))
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--iteration", type=Path, required=True)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Equivalent to plan; executes nothing and writes nothing")
    parser.add_argument("--stop-after")
    parser.add_argument("--allow-effect", choices=sorted(EFFECTS), action="append", default=[])
    args = parser.parse_args(argv)
    try:
        recipe = Recipe(args.recipe, args.config, args.iteration)
        command = "plan" if args.dry_run else args.command
        if command == "plan":
            result = recipe.plan()
        elif command == "doctor":
            paths = recipe.external_paths()
            missing = [str(p) for p in paths if not p.exists()]
            missing += [value + " (runtime must be a regular file)" for key, value in recipe.values.items()
                        if key.startswith("runtime.") and Path(value).exists() and not Path(value).is_file()]
            result = {"status": "MISSING_PREREQUISITES" if missing else "PATHS_READY",
                      "missing": missing, "engine_versions_probed": False,
                      "scope": "Paths/configuration only; no runtime, dependency import, inference or download executed."}
            if missing:
                print(json.dumps(result, indent=2))
                return 2
        elif command == "inventory":
            result = recipe.snapshot()
        elif command == "run":
            result = run(recipe, args.resume, args.stop_after, args.allow_effect)
        else:
            result = load_state(recipe)
            if command == "verify" and result["status"] != "RECIPE_COMPLETE":
                print(json.dumps(result, indent=2))
                return 5
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0
    except (ToolboxError, OSError, KeyError, IndexError, TypeError, ValueError) as exc:
        print(json.dumps({"status": "ERROR", "error": str(exc), "art_approval_inferred": False}), file=sys.stderr)
        return exc.code if isinstance(exc, ToolboxError) else 2


if __name__ == "__main__":
    raise SystemExit(main())
