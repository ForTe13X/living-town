import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import worldpackage_boundary as boundary


class CafeBoundaryTests(unittest.TestCase):
    def setUp(self):
        folder = ROOT / "game/addons/worldgen/consumers/ai_town_adapter/fixtures"
        self.inventory = boundary.load_json(folder / "native_inventory.json")
        self.ledger = boundary.load_json(folder / "identity_ledger.json")
        self.coastal_plan = boundary.load_json(ROOT / "game/data/coastal_plan.json")
        before = copy.deepcopy(self.inventory)
        self.reference, self.bindings = boundary.export_reference(self.inventory, self.ledger, self.coastal_plan)
        self.assertEqual(before, self.inventory)
        self.assertEqual(self.reference, boundary.load_json(folder / "lt22_cafe_street.world.json"))
        self.assertEqual(self.bindings, boundary.load_json(folder / "host_action_bindings.json"))

    def check_without_mutation(self, package, occupied=(), occupied_affordances=()):
        before = copy.deepcopy((package, self.reference, occupied, occupied_affordances))
        result = boundary.check_compatible(package, self.reference, occupied, occupied_affordances)
        self.assertEqual(before, (package, self.reference, occupied, occupied_affordances))
        return result

    def test_roundtrip_identity_cells_and_host_bindings(self):
        self.assertTrue(boundary.canonical_value(self.reference))
        self.assertTrue(self.check_without_mutation(self.reference)["ok"])
        topology = self.reference["payload"]["topology"]
        self.assertEqual({o["id"] for o in self.inventory["objects"]},
                         {s["source_id"] for s in topology["slots"]})
        self.assertEqual(len({s["id"] for s in topology["slots"]}), 6)
        for actual, exported in zip(self.inventory["navigation"], topology["planes"]):
            self.assertEqual(actual["blocked_cells"],
                             [[v // 48 for v in p] for p in exported["blocked_cells_q"]])
        self.assertEqual(len(self.bindings), sum(len(o["advertises"]) for o in self.inventory["objects"]))

    def test_presentation_preserves_topology_and_state_compatibility(self):
        changed = copy.deepcopy(self.reference)
        presentation = {"profile": "alternate", "pixels_per_cell": 96}
        changed["payload"]["presentation"] = {**presentation, "digest_sha256": boundary.digest(presentation)}
        checked = self.check_without_mutation(changed)
        self.assertTrue(checked["ok"])
        self.assertEqual(changed["payload"]["compatibility"], self.reference["payload"]["compatibility"])
        self.assertNotEqual(checked["presentation_sha256"], self.reference["payload"]["presentation"]["digest_sha256"])

    def test_empty_presentation_profile_rejected(self):
        changed = copy.deepcopy(self.reference)
        presentation = {"profile": "", "pixels_per_cell": 48}
        changed["payload"]["presentation"] = {**presentation, "digest_sha256": boundary.digest(presentation)}
        self.assertIn("E_PRESENTATION", self.check_without_mutation(changed)["errors"])

    def test_cafe_frontage_street_identity_and_units(self):
        street, = self.reference["payload"]["topology"]["streets"]
        source, = [s for s in self.coastal_plan["streets"] if s["id"] == street["source_id"]]
        segment = street["segment_index"]
        self.assertEqual(street["path_q"], [[n * 48 for n in p] for p in source["points"][segment:segment+2]])
        link, = [x for x in self.coastal_plan["links"] if x["entrance"] == [41, 19]]
        self.assertEqual(street["entrance_link_q"], [[n * 48 for n in p] for p in link["cells"]])
        self.assertEqual(street["portal_id"], "p_cafe_door")
        self.assertEqual(street["width_cells_ratio"], [8, 5])

    def test_portal_policy_and_object_ownership_preserved(self):
        topology = self.reference["payload"]["topology"]
        for source, mapped in zip(self.inventory["portals"], topology["portals"]):
            for key, default in [("kind", ""), ("access", ""), ("owner_space", ""), ("staff_titles", [])]:
                self.assertEqual(source.get(key, default), mapped[key])
        for source, mapped in zip(self.inventory["objects"], topology["slots"]):
            self.assertEqual(source.get("home_space", source["space"]), mapped["home_space"])

    def test_occupied_portal_rename_rejected_even_with_rehashed_topology(self):
        changed = copy.deepcopy(self.reference)
        topology = changed["payload"]["topology"]
        topology["portals"][0]["id"] = "renamed"
        changed["payload"]["compatibility"]["topology_sha256"] = boundary.digest(topology)
        result = self.check_without_mutation(changed, (self.reference["payload"]["topology"]["portals"][0]["id"],))
        self.assertIn("E_OCCUPIED_PORTAL_REMOVED", result["errors"])
        self.assertIn("E_TOPOLOGY_CHANGED", result["errors"])

    def test_removed_affordance_rejected_even_with_rehashed_topology(self):
        changed = copy.deepcopy(self.reference)
        occupied = changed["payload"]["topology"]["affordances"].pop()["id"]
        changed["payload"]["compatibility"]["topology_sha256"] = boundary.digest(changed["payload"]["topology"])
        result = self.check_without_mutation(changed, occupied_affordances=(occupied,))
        self.assertIn("E_OCCUPIED_AFFORDANCE_REMOVED", result["errors"])
        self.assertIn("E_TOPOLOGY_CHANGED", result["errors"])

    def test_unhashable_portal_and_affordance_ids_reject_without_exception(self):
        for group, occupied, expected in (
            ("portals", ("p_cafe_door",), "E_PORTAL_ID"),
            ("affordances", (self.reference["payload"]["topology"]["affordances"][0]["id"],),
             "E_AFFORDANCE_ID"),
        ):
            for malformed in ([], {}):
                with self.subTest(group=group, malformed=malformed):
                    changed = copy.deepcopy(self.reference)
                    changed["payload"]["topology"][group][0]["id"] = malformed
                    changed["payload"]["compatibility"]["topology_sha256"] = boundary.digest(
                        changed["payload"]["topology"])
                    result = self.check_without_mutation(
                        changed,
                        occupied=occupied if group == "portals" else (),
                        occupied_affordances=occupied if group == "affordances" else (),
                    )
                    self.assertFalse(result["ok"])
                    self.assertIn(expected, result["errors"])
                    self.assertIn("E_TOPOLOGY_CHANGED", result["errors"])

    def test_mismatched_units_rejected(self):
        changed = copy.deepcopy(self.reference)
        changed["coordinate_frame"]["q_per_cell"] = 32
        self.assertIn("E_UNITS", self.check_without_mutation(changed)["errors"])

    def test_numeric_and_envelope_spoofs_rejected(self):
        for mutate in (
            lambda p: p["coordinate_frame"].update(q_per_cell=48.0),
            lambda p: p["capabilities"].update(read_only=1),
            lambda p: p.update(schema_version=True),
            lambda p: p.update(unrecognized=True),
            lambda p: p["payload"].update(topology=[]),
            lambda p: p["payload"]["presentation"].update(pixels_per_cell=2**32),
        ):
            changed = copy.deepcopy(self.reference)
            mutate(changed)
            self.assertFalse(self.check_without_mutation(changed)["ok"])

    def test_source_drift_requires_explicit_ledger_revision(self):
        changed = copy.deepcopy(self.inventory)
        changed["objects"][0]["pos"][0] += 1
        with self.assertRaises(ValueError):
            boundary.export_reference(changed, self.ledger, self.coastal_plan)

    def test_street_geometry_drift_requires_explicit_ledger_revision(self):
        changed = copy.deepcopy(self.coastal_plan)
        street = next(s for s in changed["streets"] if s["id"] == "market_walk")
        street["points"][4][0] += 1
        with self.assertRaises(ValueError):
            boundary.export_reference(self.inventory, self.ledger, changed)

    def test_native_navigation_and_portal_drift_rejected_before_export(self):
        changed = copy.deepcopy(self.inventory)
        changed["navigation"][0]["blocked_cells"].pop()
        with self.assertRaisesRegex(ValueError, "native navigation changed"):
            boundary.export_reference(changed, self.ledger, self.coastal_plan)
        changed = copy.deepcopy(self.inventory)
        changed["portals"][0]["traversal_cost"] += 1
        with self.assertRaisesRegex(ValueError, "native portals changed"):
            boundary.export_reference(changed, self.ledger, self.coastal_plan)

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "hostile.json"
            p.write_text('{"schema_version":1,"schema_version":2}', encoding="utf-8")
            with self.assertRaises(ValueError):
                boundary.load_json(p)


if __name__ == "__main__":
    unittest.main()
