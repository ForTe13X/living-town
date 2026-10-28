import copy
import unittest

from tools.unreal.native_town_coverage import compare


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.assembly = {"placements": [
            {"id": "forest:1", "source_stage": "forest", "semantic_group": "nature",
             "extras": {"vegetation_role": "tree", "lod": "far"},
             "world_bounds": [[-66, 0, -2], [-64, 8, 2]]},
            {"id": "town:1", "source_stage": "town", "extras": None},
        ]}
        self.plan = {"source_assembly_sha256": "frozen", "units": [{"entries": [
            {"source_placement_ids": ["town:1"]},
            {"source_placement_ids": ["town:1"]},
        ]}]}

    def test_split_references_do_not_inflate_coverage_or_vegetation(self):
        report = compare(self.assembly, self.plan, "frozen")
        self.assertEqual(report["totals"], {"source_placements": 2,
                         "plan_referenced_placements": 1, "unreferenced_placements": 1})
        self.assertEqual(report["source_references_in_multiple_entries"], 1)
        self.assertEqual(report["by_category"]["vegetation_role"]["tree"]
                         ["plan_referenced_placements"], 0)
        self.assertEqual(report["vegetation_cells_64m"][0]["x"], -2)

    def test_unknown_id_and_wrong_source_refused(self):
        with self.assertRaisesRegex(ValueError, "different source"):
            compare(self.assembly, self.plan, "other")
        self.plan["units"][0]["entries"][0]["source_placement_ids"] = ["absent"]
        with self.assertRaisesRegex(ValueError, "Unknown"):
            compare(self.assembly, self.plan, "frozen")

    def test_duplicate_source_id_refused(self):
        self.assembly["placements"].append(copy.deepcopy(self.assembly["placements"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            compare(self.assembly, self.plan, "frozen")


if __name__ == "__main__":
    unittest.main()
