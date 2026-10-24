"""Negative controls for coverage omissions, stale bindings and false PASS labels."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest


REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("tested_town_inventory", REPO/"tools/town_upgrade/building_inventory.py")
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


def building(ident="House", floors=2):
    return {"id": ident, "kind": "home", "width": 8, "depth": 8, "floors": floors,
            "levels": [{"level": level, "rooms": [
                {"id": f"{ident}_L{level}_Hall", "name": "Hall", "purpose": "entrance circulation", "assets": []},
                {"id": f"{ident}_L{level}_Living", "name": "Living", "purpose": "living and dining",
                 "assets": [{"id": f"{ident}_L{level}_Sofa", "kind": "sofa"}]}], "partitions": []}
                for level in range(floors)]}


def fixture():
    source = building()
    native = deepcopy(source)
    native["floor_count"] = 2
    native["floors"] = native["levels"]
    documents = {"masterplan": {"buildings": [source]}, "interior_plan": {"buildings": [source]},
                 "town_manifest": {"buildings": [source], "interiors": [native]}}
    return documents


class WholeTownInventoryTests(unittest.TestCase):
    def test_missing_generated_floor_is_reported_and_not_hidden_by_declared_count(self):
        documents = fixture()
        documents["town_manifest"]["interiors"][0]["levels"].pop()
        report = inventory.build_inventory(documents, {})
        self.assertEqual(report["inventory_status"], "FAIL")
        self.assertTrue(any(x["kind"] == "floor_coverage_mismatch" for x in report["inventory_issues"]))
        self.assertEqual(len(report["buildings"][0]["floors"]), 2)

    def test_removed_furnishing_cannot_pass_by_preserving_room_count(self):
        documents = fixture()
        documents["town_manifest"]["interiors"][0]["levels"][1]["rooms"][1]["assets"] = []
        report = inventory.build_inventory(documents, {})
        mismatch = [i for i in report["inventory_issues"] if i["kind"] == "id_set_mismatch"]
        self.assertTrue(any("House_L1_Sofa" in i["missing"] for i in mismatch))

    def test_changed_furniture_facing_is_not_hidden_by_matching_ids(self):
        documents = fixture()
        documents["town_manifest"]["interiors"][0]["levels"][0]["rooms"][1]["assets"][0]["rotation_degrees"] = 180
        report = inventory.build_inventory(documents, {})
        self.assertTrue(any(i["kind"] == "fixture_pose_or_program_mismatch" and i["field"] == "rotation_degrees" for i in report["inventory_issues"]))

    def test_removed_partition_is_not_hidden_by_matching_rooms(self):
        documents = fixture()
        documents["interior_plan"]["buildings"][0]["levels"][0]["partitions"] = [{"axis": "x", "coordinate_m": 0}]
        report = inventory.build_inventory(documents, {})
        self.assertTrue(any(i["kind"] == "floor_geometry_record_mismatch" and i["field"] == "partitions" for i in report["inventory_issues"]))

    def test_global_pass_without_bindings_does_not_verify_native_or_visual(self):
        documents = fixture()
        documents["core_native_audit"] = {"status": "PASS"}
        documents["old_visual_review"] = {"status": "PASS"}
        report = inventory.build_inventory(documents, {})
        self.assertFalse(report["evidence_evaluations"]["urban_native"]["accepted"])
        self.assertFalse(report["evidence_evaluations"]["old_visual_review"]["accepted"])
        self.assertTrue(all(f["coverage"]["visual_interior"]["status"] == "missing" for f in report["buildings"][0]["floors"]))
        self.assertEqual(report["status"], "INCOMPLETE")

    def test_duplicate_building_id_is_not_silently_collapsed(self):
        documents = fixture()
        documents["masterplan"]["buildings"].append(deepcopy(documents["masterplan"]["buildings"][0]))
        report = inventory.build_inventory(documents, {})
        self.assertTrue(any(x["kind"] == "duplicate_id" for x in report["inventory_issues"]))

    def test_duplicate_levels_do_not_supply_missing_floor(self):
        documents = fixture()
        documents["interior_plan"]["buildings"][0]["levels"][1]["level"] = 0
        report = inventory.build_inventory(documents, {})
        self.assertTrue(any(x["kind"] == "floor_coverage_mismatch" for x in report["inventory_issues"]))

    def test_circulation_and_rectangle_do_not_become_enclosed_rooms(self):
        report = inventory.build_inventory(fixture(), {})
        floor = report["buildings"][0]["floors"][0]
        self.assertEqual(floor["rooms"][0]["zone_type"], "circulation_zone")
        self.assertTrue(all(r["enclosure"] == "not_asserted_by_inventory" for r in floor["rooms"]))

    def test_duplicate_native_floors_and_levels_are_counted_once(self):
        report = inventory.build_inventory(fixture(), {})
        self.assertEqual(report["summary"], {"buildings": 1, "floors": 2, "room_zones": 4, "furnishings": 2})
        self.assertEqual(report["inventory_status"], "PASS")

    def test_stale_source_hash_invalidates_scoped_native_check(self):
        receipt = {"status": "PASS", "native_sha256": "old", "checks": [{"id": "floor", "status": "PASS"}]}
        result = inventory.bound_receipt(receipt, {"native_sha256": "current"}, checks=["floor"])
        self.assertFalse(result["accepted"])
        self.assertIn("binding mismatch: native_sha256", result["reasons"])

    def test_missing_named_check_does_not_inherit_global_pass(self):
        receipt = {"status": "PASS", "native_sha256": "current", "checks": []}
        self.assertFalse(inventory.bound_receipt(receipt, {"native_sha256": "current"}, checks=["floor"])["accepted"])


if __name__ == "__main__":
    unittest.main()
