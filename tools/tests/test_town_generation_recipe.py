"""Semantic recipe contracts, independent of Blender and external generators."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.town_generation import compile_recipe as compiler


def fixtures():
    hashes = {name: str(index) * 64 for index, name in enumerate(
        ("masterplan", "interiors", "landscape", "terrain", "reserve"), 1)}
    profile = {
        "schema": "living_town.generation_profile.v1", "seed": 71126,
        "style": "Breton summer", "focus_buildings": ["Cafe"],
        "runtime": {"engine_jobs_at_once": 1}, "upstream_references": {},
        "proposed_quality": {"focus_facade_bake_pixels": 4096,
                             "other_facade_bake_pixels": 2048,
                             "fine_plaster_repeat_metres": 1},
    }
    building = {"id": "Cafe", "kind": "cafe", "center": [10., 20.],
                "width": 8., "depth": 6., "floors": 2, "yaw_degrees": 90.}
    interior = {"id": "Cafe", "floors": 2, "footprint_m": [8., 6.],
                "floor_height_m": 2.85, "levels": []}
    for number in range(2):
        room_id = f"Cafe_L{number}_Room"
        interior["levels"].append({
            "level": number, "finished_floor_local_z_m": .38 + number * 2.85,
            "rooms": [{"id": room_id, "purpose": "cafe dining",
                       "bounds_m": [-3.7, -2.7, 3.7, 2.7],
                       "door_gaps": [], "circulation_keepouts": [],
                       "assets": [{"id": room_id + "_Table", "kind": "cafe_table_set",
                                   "center_m": [1., 2.], "dimensions_m": [1.4, 1., .95],
                                   "rotation_degrees": 30.}]}]})
    pad = {"id": "Cafe", "pad_base_z_m": 2., "finished_floor_z_m": 2.38,
           "threshold_xy": [13., 20.]}
    reserve = {"id": "Reserve_Reception", "kind": "visitor_reception",
               "center": [-130., -50.], "yaw_degrees": 0., "pad_level_m": 7.,
               "finished_floor_offset_m": .18, "entry_threshold_m": [-130., -53.5, 7.18],
               "program": ["visitor reception", "first aid"]}
    inputs = {
        "masterplan": {"buildings": [building]},
        "interiors": {"masterplan_sha256": hashes["masterplan"], "buildings": [interior]},
        "terrain": {"masterplan_sha256": hashes["masterplan"],
                    "landscape_plan_sha256": hashes["landscape"], "building_pads": [pad]},
        "landscape": {"source_bindings": {"baseline_terrain_profile_sha256": "historical"}},
        "reserve": {"buildings": [reserve], "source_bindings": {}},
    }
    return profile, inputs, hashes


def add_building(inputs, identity, center):
    building = copy.deepcopy(inputs["masterplan"]["buildings"][0])
    building.update(id=identity, center=center)
    interior = copy.deepcopy(inputs["interiors"]["buildings"][0])
    previous_identity = interior["id"]
    interior["id"] = identity
    for level in interior["levels"]:
        for room in level["rooms"]:
            room["id"] = room["id"].replace(previous_identity, identity)
            for asset in room["assets"]:
                asset["id"] = asset["id"].replace(previous_identity, identity)
    pad = copy.deepcopy(inputs["terrain"]["building_pads"][0])
    pad.update(id=identity, threshold_xy=[center[0] + 3, center[1]])
    inputs["masterplan"]["buildings"].append(building)
    inputs["interiors"]["buildings"].append(interior)
    inputs["terrain"]["building_pads"].append(pad)


class RecipeSemanticTests(unittest.TestCase):
    def setUp(self):
        self.profile, self.inputs, self.hashes = fixtures()

    def build(self):
        return compiler.build_recipe(self.profile, self.inputs, self.hashes)

    def test_stable_ids_ignore_order_and_unrelated_insertions(self):
        add_building(self.inputs, "Shop", [10., 28.])
        first = self.build()
        for role, key in (("masterplan", "buildings"), ("interiors", "buildings"),
                          ("terrain", "building_pads")):
            self.inputs[role][key].reverse()
        for interior in self.inputs["interiors"]["buildings"]:
            interior["levels"].reverse()
        self.assertEqual(first, self.build())
        add_building(self.inputs, "Workshop", [30., 50.])
        later = {row["id"]: row for row in self.build()["town"]}
        for row in first["town"]:
            self.assertEqual(row, later[row["id"]])
        self.assertEqual(first["reserve"], self.build()["reserve"])

    def test_rotated_local_positions_facing_and_yaw_are_world_space(self):
        cafe = self.build()["town"][0]
        asset = cafe["levels"][0]["rooms"][0]["assets"][0]
        self.assertAlmostEqual(asset["target_world_xy_m"][0], 8.)
        self.assertAlmostEqual(asset["target_world_xy_m"][1], 21.)
        self.assertEqual(asset["world_yaw_degrees"], 120.)
        self.assertAlmostEqual(cafe["front_outward_xy"][0], 1.)
        self.assertAlmostEqual(cafe["front_outward_xy"][1], 0.)

    def test_urban_and_reserve_use_their_own_floor_datums(self):
        recipe = self.build()
        levels = recipe["town"][0]["levels"]
        self.assertAlmostEqual(levels[0]["finished_floor_world_z_m"], 2.38)
        self.assertAlmostEqual(levels[1]["finished_floor_world_z_m"], 5.23)
        self.assertAlmostEqual(recipe["reserve"][0]["finished_floor_world_z_m"], 7.18)
        self.assertNotAlmostEqual(recipe["reserve"][0]["finished_floor_world_z_m"], 7.38)

    def test_stale_interior_and_terrain_bindings_are_rejected(self):
        for role, field in (("interiors", "masterplan_sha256"),
                            ("terrain", "masterplan_sha256"),
                            ("terrain", "landscape_plan_sha256")):
            with self.subTest(role=role, field=field):
                saved = self.inputs[role][field]
                self.inputs[role][field] = "stale"
                with self.assertRaises(ValueError):
                    self.build()
                self.inputs[role][field] = saved

    def test_duplicate_building_ids_and_unknown_focus_are_rejected(self):
        self.inputs["masterplan"]["buildings"].append(copy.deepcopy(self.inputs["masterplan"]["buildings"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.build()
        self.inputs["masterplan"]["buildings"].pop()
        self.profile["focus_buildings"] = ["Missing"]
        with self.assertRaisesRegex(ValueError, "Focus"):
            self.build()

    def test_duplicate_asset_ids_are_rejected(self):
        assets = self.inputs["interiors"]["buildings"][0]["levels"][0]["rooms"][0]["assets"]
        assets.append(copy.deepcopy(assets[0]))
        with self.assertRaises(ValueError):
            self.build()

    def test_duplicate_room_ids_are_rejected(self):
        levels = self.inputs["interiors"]["buildings"][0]["levels"]
        levels[1]["rooms"][0]["id"] = levels[0]["rooms"][0]["id"]
        with self.assertRaises(ValueError):
            self.build()

    def test_duplicate_level_indices_are_rejected(self):
        levels = self.inputs["interiors"]["buildings"][0]["levels"]
        levels[1]["level"] = 0
        with self.assertRaises(ValueError):
            self.build()

    def test_ground_floor_pad_disagreement_is_rejected(self):
        self.inputs["terrain"]["building_pads"][0]["finished_floor_z_m"] = 5.
        with self.assertRaisesRegex(ValueError, "Ground floor"):
            self.build()

    def test_interior_footprint_must_match_target_shell(self):
        self.inputs["interiors"]["buildings"][0]["footprint_m"] = [8.6, 6.4]
        with self.assertRaises(ValueError):
            self.build()

    def test_reserve_threshold_uses_its_recorded_floor_offset(self):
        self.inputs["reserve"]["buildings"][0]["entry_threshold_m"][2] = 7.38
        with self.assertRaises(ValueError):
            self.build()

    def test_profile_seed_rejects_booleans_and_out_of_range_values(self):
        for seed in (True, -1, 2**32):
            with self.subTest(seed=seed):
                self.profile["seed"] = seed
                with self.assertRaises(ValueError):
                    self.build()


class RecipeCompilationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="town_recipe_contract_")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "repo"
        self.town = self.root / "art/living_town"
        self.town.mkdir(parents=True)
        self.profile, self.inputs, _ = fixtures()
        module = self.town / "tools/terrain_profile.py"
        module.parent.mkdir()
        module.write_text("# Bound authoring source; never imported.\n", encoding="utf-8")
        filenames = {"masterplan": "masterplan.json", "landscape": "landscape_plan.json",
                     "interiors": "interior_plan.json", "terrain": "terrain_plan.json",
                     "reserve": "reserve_plan.json"}
        paths = {role: self.town / name for role, name in filenames.items()}
        def write(role):
            paths[role].write_text(json.dumps(self.inputs[role]), encoding="utf-8")
        write("masterplan")
        write("landscape")
        self.inputs["interiors"]["masterplan_sha256"] = compiler.sha(paths["masterplan"])
        write("interiors")
        self.inputs["terrain"]["masterplan_sha256"] = compiler.sha(paths["masterplan"])
        self.inputs["terrain"]["landscape_plan_sha256"] = compiler.sha(paths["landscape"])
        write("terrain")
        self.inputs["reserve"]["source_bindings"] = {
            filenames[role]: compiler.sha(paths[role]) for role in ("masterplan", "landscape", "terrain")}
        self.inputs["reserve"]["source_bindings"]["tools/terrain_profile.py"] = compiler.sha(module)
        write("reserve")
        self.profile["inputs"] = {role: path.relative_to(self.root).as_posix() for role, path in paths.items()}
        self.profile["source_modules"] = [module.relative_to(self.root).as_posix()]
        self.profile_path = self.root / "profile.json"
        self.profile_path.write_text(json.dumps(self.profile), encoding="utf-8")
        self.output = self.base / "new_recipe"

    def compile(self):
        return compiler.compile_recipe(self.root, self.profile_path, self.output)

    def test_exclusive_output_and_no_engine_or_shell_execution(self):
        before = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        with mock.patch("subprocess.run", side_effect=AssertionError("No process allowed")), \
             mock.patch("subprocess.Popen", side_effect=AssertionError("No process allowed")), \
             mock.patch("os.system", side_effect=AssertionError("No shell allowed")):
            recipe = self.compile()
        self.assertEqual(recipe["status"], "COMPILED_NOT_GENERATED")
        self.assertFalse(recipe["blender_executed"])
        self.assertFalse(recipe["infinigen_executed"])
        self.assertFalse(recipe["inference_executed"])
        destination = self.output / "generation_recipe.json"
        encoded = destination.read_bytes()
        with self.assertRaises(FileExistsError):
            self.compile()
        self.assertEqual(destination.read_bytes(), encoded)
        self.assertEqual({p: p.read_bytes() for p in before}, before)

    def test_changed_bound_source_is_rejected_before_output_creation(self):
        (self.town / "tools/terrain_profile.py").write_text("# Changed source\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Reserve source binding differs"):
            self.compile()
        self.assertFalse(self.output.exists())

    def test_input_path_escape_is_rejected_before_output_creation(self):
        outside = self.base / "outside.json"
        outside.write_text("{}", encoding="utf-8")
        self.profile["inputs"]["masterplan"] = "../outside.json"
        self.profile_path.write_text(json.dumps(self.profile), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "escapes repository"):
            self.compile()
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
