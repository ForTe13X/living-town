"""Regression cases for usable furniture and circulation in the Mill Court plans."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "mill_court_plan", ROOT / "tools/mill_court_plan.py"
)
PLAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PLAN)


class MillCourtPlanTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(PLAN.DEFAULT_PLAN.read_text(encoding="utf-8"))

    def test_four_plans_have_reachable_interactions_and_do_not_mutate_input(self):
        original = copy.deepcopy(self.data)
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(len(report["plans"]), 4)
        self.assertTrue(
            all(
                target["reachable"]
                for plan in report["plans"]
                for target in plan["access"]
            )
        )
        self.assertEqual(self.data, original)

    def test_entry_door_cannot_swing_through_added_furniture(self):
        ground = next(p for p in self.data["plans"] if p["id"] == "A_Ground")
        ground["furniture"].append(
            {
                "id": "blocking_cabinet",
                "kind": "cabinet",
                "bounds_m": [2.5, 0.3, 3.1, 0.9],
            }
        )
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(
            any(
                f[1] == "door_swing_furniture" and f[-1] == "blocking_cabinet"
                for f in report["failures"]
            )
        )

    def test_chair_pullback_is_not_treated_as_free_storage(self):
        ground = next(p for p in self.data["plans"] if p["id"] == "A_Ground")
        ground["furniture"].append(
            {
                "id": "pullback_obstacle",
                "kind": "cabinet",
                "bounds_m": [3.15, 2.15, 3.5, 2.5],
            }
        )
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(
            any(
                f[1] == "chair_pullback_solid" and f[-1] == "pullback_obstacle"
                for f in report["failures"]
            )
        )

    def test_wider_bed_cannot_consume_both_side_clearances(self):
        upper = next(p for p in self.data["plans"] if p["id"] == "A_Upper")
        bed = next(f for f in upper["furniture"] if f["id"] == "double_bed")
        bed["bounds_m"] = [3.1, 0.25, 5.1, 2.25]
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        consumed = {
            f[2]
            for f in report["failures"]
            if f[1] == "clearance_solid" and f[-1] == "double_bed"
        }
        self.assertTrue({"bed_w_side", "bed_e_side"}.issubset(consumed))

    def test_stale_wall_segments_cannot_pass_by_silent_regeneration(self):
        self.data["plans"][0]["wall_segments"][0]["bounds_m"][0] += 0.2
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(
            any(f[1] == "stale_serialized_wall_segments" for f in report["failures"])
        )

    def test_floor_record_and_shared_stair_must_agree(self):
        self.data["stairs"][0]["clear_width_m"] = 0.7
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(
            any(f[1] == "shared_stair_mismatch" for f in report["failures"])
        )

    def test_closed_upper_slab_cannot_claim_stair_headroom(self):
        upper = next(p for p in self.data["plans"] if p["id"] == "A_Upper")
        upper["floor_slab"]["opening_bounds_m"] = None
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(
            any(f[1] == "slab_stair_opening_mismatch" for f in report["failures"])
        )
        measured = next(p for p in report["plans"] if p["plan"] == "A_Upper")
        self.assertLess(measured["minimum_computed_stair_headroom_m"], 0.5)

    def test_primary_pocket_retraction_cannot_cross_child_room_wall(self):
        upper = next(p for p in self.data["plans"] if p["id"] == "B_Upper")
        wall = next(w for w in upper["walls"] if w["id"] == "child_n")
        wall["end_m"] = 4.6
        upper["wall_segments"] = PLAN.walls_for(upper)
        report = PLAN.validate(self.data)
        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(
            any(
                f[1:] == ["pocket_sweep_wall", "primary_door", "child_n"]
                for f in report["failures"]
            )
        )


if __name__ == "__main__":
    unittest.main()
