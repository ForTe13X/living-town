"""Real tiny subprocesses exercise orchestration; no Blender/Godot/network jobs."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

from tools.asset_toolbox.cli import Recipe, ToolboxError, main, read, run, write, load_state
from tools.asset_toolbox.export_copy import prepare_copy


FAKE = '''import base64, json, pathlib, sys, time
mode, destination, payload = sys.argv[1:4]
target = pathlib.Path(destination)
target.parent.mkdir(parents=True, exist_ok=True)
print("tiny stdout", flush=True)
print("tiny stderr", file=sys.stderr, flush=True)
if mode == "sleep": time.sleep(5)
if mode == "mutate": pathlib.Path(sys.argv[4]).write_text("CHANGED", encoding="utf-8")
target.write_text(json.dumps({"status":"PASS","payload":payload}), encoding="utf-8")
if mode == "fail": sys.exit(7)
target.with_suffix(".png").write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jx1kAAAAASUVORK5CYII="))
'''


class ToolboxTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="asset toolbox ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.script = self.root / "fake stage.py"
        self.script.write_text(FAKE, encoding="utf-8")
        self.source = self.root / "concept.png"
        self.source.write_bytes(b"bound concept fixture")
        self.recipe_file = self.root / "recipe.json"
        self.config_file = self.root / "config.json"
        self.iteration = self.root / "iterations" / "one"
        self.config = {"repo": str(self.root), "runtimes": {"python": sys.executable},
                       "inputs": {"concept": str(self.source)}}
        self.payload = "spaces ; & $(do-not-run) `literal` $HOME"
        self.stage = {"id": "build", "kind": "command", "phase": "native",
                      "argv": ["${runtime.python}", str(self.script), "write", "${iteration}/result.json", self.payload],
                      "outputs": ["${iteration}/result.json", "${iteration}/result.png"],
                      "checks": [{"file": "${iteration}/result.json", "pointer": "/status", "equals": "PASS"}]}
        self.review = {"id": "art", "kind": "review", "phase": "visual_review", "depends_on": ["build"],
                       "artifacts": ["${iteration}/result.png", "${input.concept}"],
                       "criteria": ["Inspect silhouette and material detail"],
                       "scope": "Fixture test only; not a town art review"}
        self.data = {"schema": "living_town.asset_toolbox.recipe.v1", "name": "tiny",
                     "required_runtimes": ["python"], "required_inputs": ["concept"],
                     "source_paths": [str(self.script)], "stages": [self.stage, self.review]}
        self.save()

    def save(self):
        write(self.config_file, self.config)
        write(self.recipe_file, self.data)

    def recipe(self):
        return Recipe(self.recipe_file, self.config_file, self.iteration)

    def assert_error(self, callback, code):
        with self.assertRaises(ToolboxError) as raised:
            callback()
        self.assertEqual(raised.exception.code, code)
        return str(raised.exception)

    def accept(self, decision="ACCEPT"):
        path = self.iteration / "reviews/art.json"
        value = read(path)
        value.update(decision=decision, reviewer="Fixture reviewer", reviewed_files=value["artifact_files"])
        value["criterion_results"] = [{"criterion": c, "decision": "ACCEPT", "observations": "Observed fixture only; no production art claim."}
                                      for c in value["criteria"]]
        write(path, value)

    def test_plan_and_dry_run_execute_nothing_and_create_no_output(self):
        recipe = self.recipe()
        self.assertEqual(recipe.plan()["status"], "PLAN_ONLY")
        self.assertEqual(recipe.plan()["stages"][0]["argv"][-1], self.payload)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["run", "--dry-run", "--recipe", str(self.recipe_file), "--config", str(self.config_file),
                                   "--iteration", str(self.iteration)]), 0)
        self.assertFalse(self.iteration.exists())

    def test_actual_argv_process_review_stop_and_unchanged_resume(self):
        recipe = self.recipe()
        first = run(recipe, stop_after="build")
        self.assertEqual(first["status"], "INCOMPLETE")
        self.assertEqual(read(self.iteration / "result.json")["payload"], self.payload)
        old_pid = first["stages"]["build"]["pid"]
        self.assert_error(lambda: run(recipe, resume=True), 4)
        self.assertEqual(read(self.iteration / "state.json")["status"], "NEEDS_REVIEW")
        self.accept()
        final = run(recipe, resume=True)
        self.assertEqual(final["status"], "RECIPE_COMPLETE")
        self.assertEqual(final["stages"]["build"]["pid"], old_pid)
        self.assertEqual(final["production_readiness"], "NOT_EVALUATED")
        self.assertEqual(load_state(recipe)["status"], "RECIPE_COMPLETE")
        self.assertIn("tiny stderr", (self.iteration / "logs/build.stderr.log").read_text())

    def test_partial_art_review_is_explicit_and_does_not_pass(self):
        self.assert_error(lambda: run(self.recipe()), 4)
        self.accept("PARTIAL")
        self.assert_error(lambda: run(self.recipe(), resume=True), 4)
        self.assertEqual(read(self.iteration / "state.json")["status"], "PARTIAL_REVIEW")
        self.accept("CHANGES_REQUIRED")
        self.assert_error(lambda: run(self.recipe(), resume=True), 4)
        self.assertEqual(read(self.iteration / "state.json")["status"], "CHANGES_REQUIRED")
        self.accept()
        self.assertEqual(run(self.recipe(), resume=True)["status"], "RECIPE_COMPLETE")

    def test_technical_checks_cannot_fill_art_review_or_claim_concept_parity(self):
        self.assert_error(lambda: run(self.recipe()), 4)
        self.accept()
        path = self.iteration / "reviews/art.json"
        value = read(path)
        value["criterion_results"][0]["observations"] = ""
        write(path, value)
        self.assert_error(lambda: run(self.recipe(), resume=True), 4)
        value["criterion_results"][0]["observations"] = "Fixture inspected"
        value["reviewed_files"] = {}
        write(path, value)
        self.assert_error(lambda: run(self.recipe(), resume=True), 4)

    def test_changed_input_source_config_and_optional_runtime_reject_resume(self):
        run(self.recipe(), stop_after="build")
        for path in (self.source, self.script, self.config_file):
            original = path.read_bytes()
            with self.subTest(path=path):
                path.write_bytes(original + b" ")
                self.assert_error(lambda: run(self.recipe(), resume=True), 2)
                path.write_bytes(original)
        # Even an optional configured runtime must be content-bound.
        optional = self.root / "optional executable"
        optional.write_bytes(b"runtime v1")
        self.config["runtimes"]["optional"] = str(optional)
        self.save()
        self.iteration = self.root / "iterations/two"
        run(self.recipe(), stop_after="build")
        optional.write_bytes(b"runtime v2")
        self.assert_error(lambda: run(self.recipe(), resume=True), 2)

    def test_output_and_completed_review_tampering_are_rejected(self):
        self.assert_error(lambda: run(self.recipe()), 4)
        self.accept()
        run(self.recipe(), resume=True)
        path = self.iteration / "reviews/art.json"
        value = read(path)
        value["criterion_results"][0]["observations"] += " tampered"
        write(path, value)
        self.assert_error(lambda: load_state(self.recipe()), 2)
        self.iteration = self.root / "iterations/two"
        run(self.recipe(), stop_after="build")
        (self.iteration / "result.png").write_bytes(b"different")
        self.assert_error(lambda: run(self.recipe(), resume=True), 2)

    def test_nonzero_process_preserves_logs_partial_files_and_cannot_retry(self):
        self.stage["argv"][2] = "fail"
        self.data["stages"] = [self.stage]
        self.save()
        self.assert_error(lambda: run(self.recipe()), 3)
        state = read(self.iteration / "state.json")
        self.assertEqual(state["status"], "FAILED")
        self.assertEqual(state["stages"]["build"]["exit_code"], 7)
        self.assertTrue((self.iteration / "result.json").exists())
        self.assert_error(lambda: run(self.recipe(), resume=True), 3)
        self.assert_error(lambda: run(self.recipe()), 2)

    def test_external_effects_are_blocked_without_launch_and_require_explicit_option(self):
        self.stage["effects"] = ["credits", "network", "weights"]
        self.data["stages"] = [self.stage]
        self.save()
        self.assert_error(lambda: run(self.recipe()), 2)
        self.assertFalse((self.iteration / "result.json").exists())
        self.assertEqual(run(self.recipe(), resume=True, allow_effects=["credits", "network", "weights"])["status"], "RECIPE_COMPLETE")

    def test_later_stage_cannot_modify_completed_artifacts(self):
        second = {"id": "bad", "kind": "command", "depends_on": ["build"],
                  "argv": ["${runtime.python}", str(self.script), "mutate", "${iteration}/second.json", "new", "${iteration}/result.json"],
                  "outputs": ["${iteration}/second.json"]}
        self.data["stages"] = [self.stage, second]
        self.save()
        self.assert_error(lambda: run(self.recipe()), 2)
        self.assertEqual(read(self.iteration / "state.json")["stages"]["bad"]["status"], "FAILED")

    def test_timeout_is_evidence_failure_not_success(self):
        self.stage["argv"][2] = "sleep"
        self.stage["timeout_seconds"] = 0.1
        self.data["stages"] = [self.stage]
        self.save()
        self.assert_error(lambda: run(self.recipe()), 3)
        state = read(self.iteration / "state.json")
        self.assertIn("timed out", state["stages"]["build"]["error"])
        self.assertTrue((self.iteration / "logs/build.stderr.log").exists())

    def test_structural_errors_and_output_escape_are_rejected_before_launch(self):
        variants = [lambda: self.stage.update(argv="python script.py"),
                    lambda: self.stage["argv"].__setitem__(0, "python"),
                    lambda: self.stage.update(outputs=["${repo}/escaped.json"]),
                    lambda: self.stage.update(outputs=["relative.json"]),
                    lambda: self.stage.update(depends_on=["unknown"]),
                    lambda: self.stage.update(effects=["surprise"])]
        original = json.dumps(self.data)
        for change in variants:
            with self.subTest(change=change):
                self.data = json.loads(original)
                self.stage = self.data["stages"][0]
                change()
                self.save()
                self.assert_error(self.recipe, 2)
                self.assertFalse(self.iteration.exists())

    def test_missing_stage_input_is_recorded_and_boolean_is_not_integer_pass(self):
        self.stage["inputs"] = ["${iteration}/missing.json"]
        self.data["stages"] = [self.stage]
        self.save()
        self.assert_error(lambda: run(self.recipe()), 2)
        self.assertEqual(read(self.iteration / "state.json")["status"], "FAILED")
        self.iteration = self.root / "iterations/two"
        self.stage["inputs"] = []
        self.stage["checks"] = [{"file": "${iteration}/result.json", "pointer": "/status", "equals": True}]
        self.save()
        self.assert_error(lambda: run(self.recipe()), 3)

    def test_terminal_label_cannot_hide_missing_or_failed_art_and_dependency_records(self):
        self.assert_error(lambda: run(self.recipe()), 4)
        self.accept()
        run(self.recipe(), resume=True)
        path = self.iteration / "state.json"
        original = path.read_bytes()
        variants = []
        for missing in ("art", "build"):
            value = json.loads(original)
            del value["stages"][missing]
            variants.append(value)
        value = json.loads(original)
        value["stages"]["art"]["status"] = "FAILED"
        variants.append(value)
        value = json.loads(original)
        value["stages"] = {}
        variants.append(value)
        value = json.loads(original)
        value["stages"]["unknown"] = {"status": "COMPLETE"}
        variants.append(value)
        for value in variants:
            with self.subTest(stages=value["stages"].keys()):
                write(path, value)
                self.assert_error(lambda: load_state(self.recipe()), 2)
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(main(["verify", "--recipe", str(self.recipe_file), "--config", str(self.config_file),
                                           "--iteration", str(self.iteration)]), 2)
        path.write_bytes(original)
        self.assertEqual(load_state(self.recipe())["status"], "RECIPE_COMPLETE")

    def test_external_literal_future_inputs_and_artifacts_are_frozen_before_first_use(self):
        external = self.root / "not in config.png"
        external.write_bytes(b"first version")
        for key in ("inputs", "artifacts"):
            with self.subTest(key=key):
                self.iteration = self.root / ("iterations/literal_" + key)
                self.review[key] = list(self.review.get(key, [])) + [str(external)]
                self.save()
                recipe = self.recipe()
                # Generated result.png does not exist yet and must not be
                # mistaken for an immutable external prerequisite.
                self.assertFalse((self.iteration / "result.png").exists())
                self.assertIn(str(external), recipe.snapshot()["immutable_bindings"])
                run(recipe, stop_after="build")
                external.write_bytes(b"new version before review stage ever ran")
                self.assert_error(lambda: run(self.recipe(), resume=True), 2)
                external.write_bytes(b"first version")

    def native_copy_fixture(self):
        source = self.root / "native candidate"
        source.mkdir()
        write(source / "upgrade_manifest.json", {"native": {"path": "town.blend"}, "assets": [],
                                                   "buildings": [{"id": "one", "group": "urban"}]})
        (source / "town.blend").write_bytes(b"packed native fixture")
        write(source / "whole_town_buildings.json", {"buildings": [{"id": "one"}]})
        write(source / "whole_town_native_geometry.json", {"status": "PASS"})
        (source / "materials").mkdir()
        (source / "materials/map.png").write_bytes(b"source map fixture")
        return source

    def test_complete_native_coordination_manifest_is_frozen_before_portable_stage(self):
        source = self.native_copy_fixture()
        # Exercise the recipe-level native-directory contract with a real tiny
        # producer; never invoke the real Blender exporter.
        self.stage["outputs"] = ["${iteration}/native"]
        self.stage["argv"] = ["${runtime.python}", "-c",
                              "import shutil,sys;shutil.copytree(sys.argv[1],sys.argv[2])",
                              str(source), "${iteration}/native"]
        self.stage["inputs"] = [str(source)]
        self.stage["checks"] = []
        self.review["inputs"] = ["${iteration}/native"]
        self.review["artifacts"] = ["${input.concept}"]
        self.save()
        run(self.recipe(), stop_after="build")
        path = self.iteration / "native/upgrade_manifest.json"
        value = read(path)
        value["buildings"][0]["group"] = "unreviewed replacement"
        write(path, value)
        self.assert_error(lambda: run(self.recipe(), resume=True), 2)

    def test_export_copy_preserves_all_native_bytes_and_changes_only_working_manifest(self):
        source = self.native_copy_fixture()
        original = (source / "upgrade_manifest.json").read_bytes()
        destination = self.root / "portable copy"
        _, _, receipt = prepare_copy(source, destination)
        self.assertEqual(receipt["source"]["files"], receipt["copy_before_export"]["files"])
        self.assertEqual(len(receipt["source"]["files"]), 5)
        value = read(destination / "upgrade_manifest.json")
        value["assets"] = [{"id": "new portable chunk"}]
        write(destination / "upgrade_manifest.json", value)
        self.assertEqual((source / "upgrade_manifest.json").read_bytes(), original)
        self.assert_error(lambda: prepare_copy(source, destination), 2)

    def test_export_copy_rejects_source_changes_during_copy(self):
        source = self.native_copy_fixture()
        import shutil
        original_copy = shutil.copyfile
        def changed_copy(src, dst):
            result = original_copy(src, dst)
            if Path(src).name == "town.blend":
                Path(src).write_bytes(b"changed during copy")
            return result
        with mock.patch("tools.asset_toolbox.export_copy.shutil.copyfile", side_effect=changed_copy):
            self.assert_error(lambda: prepare_copy(source, self.root / "partial portable"), 3)

    def test_export_copy_rejects_relative_native_path_escape(self):
        source = self.native_copy_fixture()
        write(source / "upgrade_manifest.json", {"native": {"path": "../outside.blend"}, "assets": []})
        self.assert_error(lambda: prepare_copy(source, self.root / "portable"), 2)

    def test_shipped_recipes_resolve_without_starting_tools(self):
        root = Path(__file__).resolve().parents[2]
        config = read(root / "tools/asset_toolbox/config.example.json")
        config["repo"] = str(root)
        config_path = self.root / "examples.json"
        write(config_path, config)
        for path in sorted((root / "tools/asset_toolbox/recipes").glob("*.json")):
            with self.subTest(recipe=path):
                recipe = Recipe(path, config_path, self.iteration)
                self.assertEqual(recipe.plan()["status"], "PLAN_ONLY")
                self.assertFalse(self.iteration.exists())


if __name__ == "__main__":
    unittest.main()
