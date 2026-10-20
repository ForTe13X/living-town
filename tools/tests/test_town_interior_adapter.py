"""Room readiness tests use the canonical independent physical audits."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest


REPO = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


adapter = load("tested_interior_adapter", REPO / "tools/town_generation/interior_adapter.py")


class CompactInteriorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.authority = adapter.load_authority(REPO / "art/living_town")
        cls.ident = "Expansion_D10_Forest_Edge_Link_L02"
        cls.fixture = {"buildings": [{"id": cls.ident, "kind": "cafe", "width": 7.2,
                                      "depth": 7.6, "floors": 2}],
                       "detailed_focus_ids": [cls.ident]}
        cls.plans, cls.report = adapter.prepare_plans(cls.fixture, REPO / "art/living_town")

    def audit(self, plan):
        return adapter.audit_prepared_plans([plan], authority=self.authority)

    def public(self, plan):
        return next(r for r in plan["levels"][0]["rooms"] if r["purpose"] == "cafe dining")

    def test_compact_cafe_keeps_real_program_and_hero_reservations(self):
        self.assertEqual(self.report["status"], "PASS")
        plan = self.plans[self.ident]
        public = self.public(plan)
        self.assertEqual(sum(a["kind"] == "cafe_table_set" for a in public["assets"]), 4)
        required = {a["detail_source"]: a for a in public["assets"] if a.get("detail_source")}
        self.assertEqual(set(required), {"hero_counter", "hero_bistro"})
        self.assertGreaterEqual(required["hero_counter"]["dimensions_m"][1], .739)
        self.assertGreaterEqual(required["hero_bistro"]["dimensions_m"][1], 1.77777)
        kitchen = next(r for r in plan["levels"][1]["rooms"] if r["purpose"] == "private owner kitchenette")
        self.assertTrue(any(a["kind"] == "dining_table" and a["integrated_seating"] == 2 for a in kitchen["assets"]))
        self.assertTrue(all(c["pass"] for c in self.report["audit"]["nonrectangular_room_checks"]))

    def test_missing_public_table_fails_unchanged_essential_gate(self):
        plan = deepcopy(self.plans[self.ident])
        room = self.public(plan)
        room["assets"].remove(next(a for a in room["assets"] if a["kind"] == "cafe_table_set"))
        audit = self.audit(plan)
        self.assertEqual(audit["status"], "FAIL")
        self.assertTrue(any(f["reason"] == "missing essential seated public tables" for f in audit["failures"]))

    def test_backwards_banquette_fails_facing_gate_even_with_pass_label(self):
        plan = deepcopy(self.plans[self.ident])
        asset = next(a for a in self.public(plan)["assets"] if a["kind"] == "banquette")
        asset["rotation_degrees"] = (asset["rotation_degrees"] + 180) % 360
        asset["footprint_m"] = self.authority.asset_footprint(asset)
        audit = self.audit(plan)
        self.assertEqual(audit["status"], "FAIL")
        self.assertTrue(any(f["reason"] == "physical back is not supported by the facing wall" for f in audit["failures"]))

    def test_fixture_on_entrance_axis_fails_actual_pedestrian_gate(self):
        plan = deepcopy(self.plans[self.ident])
        asset = next(a for a in self.public(plan)["assets"] if a["kind"] == "cafe_table_set" and not a.get("detail_source"))
        asset["center_m"] = [0, plan["clear_bounds_m"][1] + .55]
        asset["rotation_degrees"] = 0
        asset["footprint_m"] = self.authority.asset_footprint(asset)
        audit = self.audit(plan)
        self.assertEqual(audit["status"], "FAIL")
        self.assertTrue(any(f["reason"] == "actual entrance axis or exact interior seed is blocked" for f in audit["failures"]))

    def test_removed_bathroom_partition_fails_privacy_gate(self):
        plan = deepcopy(self.plans[self.ident])
        floor = plan["levels"][1]
        bathroom = next(r for r in floor["rooms"] if r["purpose"] == "private owner bathroom")
        boundary = bathroom["bounds_m"][1]
        floor["partitions"] = [p for p in floor["partitions"] if not (p["axis"] == "y" and abs(p["coordinate_m"]-boundary) < 1e-6)]
        audit = self.audit(plan)
        self.assertEqual(audit["status"], "FAIL")
        self.assertTrue(any(f["reason"] == "sleeping or sanitary room has an unenclosed interior edge" for f in audit["failures"]))

    def test_fixture_inside_stair_notch_fails_actual_room_check(self):
        plan = deepcopy(self.plans[self.ident])
        asset = next(a for a in self.public(plan)["assets"] if a["kind"] == "cafe_table_set")
        a, b, c, e = plan["core"]["bounds"]
        asset["center_m"] = [(a+c)/2, (b+e)/2]
        asset["footprint_m"] = self.authority.asset_footprint(asset)
        audit = self.audit(plan)
        self.assertEqual(audit["status"], "FAIL")
        self.assertTrue(any(f["reason"] == "nonrectangular room density or protected-core clearance failed" for f in audit["failures"]))

    def test_built_record_floor_contract_is_normalized_without_mutation(self):
        plan = deepcopy(self.plans[self.ident])
        plan["floor_count"] = plan["floors"]
        plan["floors"] = plan["levels"]
        self.assertEqual(self.audit(plan)["status"], "PASS")
        self.assertIsInstance(plan["floors"], list)
        plan["levels"][1]["finished_floor_local_z_m"] += .1
        self.assertTrue(any(f["reason"] == "finished floor differs from geometry authority" for f in self.audit(plan)["failures"]))

    def test_actual_default_territory_passes_all_room_gates(self):
        territory = load("tested_territory", REPO / "tools/town_generation/territory.py")
        plan = territory.generate(REPO / "art/living_town", 20261020)
        self.assertEqual(plan["validation"]["status"], "PASS")
        prepared, report = adapter.prepare_plans(plan, REPO / "art/living_town")
        self.assertEqual(set(prepared), {b["id"] for b in plan["buildings"]})
        self.assertEqual(report["status"], "PASS", report["audit"]["failures"])
        self.assertEqual(report["audit"]["furniture_composition"]["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
