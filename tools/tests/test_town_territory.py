"""Geometry/authority regression tests for the actual territory planner."""
import hashlib
import json
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
from pathlib import Path

from tools.town_generation import territory


ROOT = Path(__file__).resolve().parents[2] / "art/living_town"


class TerritoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = territory.generate(ROOT, 71126)

    def test_real_layout_is_connected_and_clear(self):
        report = self.plan["validation"]
        self.assertEqual(report["status"], "PASS", report["errors"])
        self.assertGreaterEqual(report["additional_buildings"], 80)
        self.assertEqual(report["disconnected_graph_vertices"], [])
        self.assertEqual(report["street_building_collisions"], [])
        self.assertEqual(report["preserved_route_buffer_collisions"], [])
        self.assertEqual(report["blocked_entrances"], [])
        self.assertEqual(len(self.plan["districts"]), 5)
        self.assertTrue(all(d["building_count"] >= 10 for d in self.plan["districts"][:4]))

    def test_determinism_and_source_binding(self):
        again = territory.generate(ROOT, 71126)
        self.assertEqual(json.dumps(self.plan, sort_keys=True), json.dumps(again, sort_keys=True))
        for name, digest in self.plan["source_bindings"].items():
            self.assertEqual(digest, hashlib.sha256((ROOT/name).read_bytes()).hexdigest())
        ids = [b["id"] for b in self.plan["buildings"]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_final_foundations_and_preserved_routes_are_exact(self):
        report = self.plan["validation"]["surface_contact"]
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["maximum_pad_drift_m"], 0)
        self.assertEqual(report["maximum_preserved_route_drift_m"], 0)
        self.assertLessEqual(report["maximum_profile_contact_drift_m"], .04)
        self.assertLessEqual(self.plan["validation"]["maximum_road_grade"], .080001)

    def test_flat_pad_boundaries_and_road_owner_seams_are_continuous(self):
        boundary=self.plan["validation"]["surface_contact"]["surface_boundary"]
        self.assertEqual(boundary["status"],"PASS")
        self.assertEqual(boundary["pad_count"],len(self.plan["buildings"]))
        self.assertGreater(boundary["pad_edge_sample_pairs"],10000)
        self.assertEqual(boundary["paired_span_m"],[.02,.002])
        self.assertLessEqual(boundary["maximum_pad_edge_2cm_delta_m"],.001)
        self.assertLessEqual(boundary["maximum_pad_edge_2mm_delta_m"],.0001)
        self.assertTrue(all(row["converges"] for row in boundary["road_owner_seams"]))
        masks=boundary["preservation_masks"]
        self.assertEqual(masks["status"],"ENGINEERED_SUPPORT_REQUIRED")
        self.assertFalse(masks["native_support_geometry_verified"])
        self.assertGreater(masks["maximum_introduced_height_change_m"],.15)
        self.assertTrue(masks["retaining_wall_sections"])
        self.assertTrue(masks["crossing_gap_support_reviews"])
        for wall in masks["retaining_wall_sections"]:
            self.assertGreater(wall["width_m"],wall["span_m"])
            self.assertLessEqual(wall["low_level_m"],wall["high_level_m"])
            for inside,outside,top,toe in zip(wall["inside_samples_m"],wall["outside_samples_m"],wall["sampled_tops_m"],wall["sampled_toes_m"]):
                self.assertGreaterEqual(top,max(inside[2],outside[2]))
                self.assertLessEqual(toe,min(inside[2],outside[2]))

    def test_run_seed_preserves_previously_accepted_entrance_routes(self):
        plan = territory.generate(ROOT, 20261020)
        self.assertEqual(plan["validation"]["status"], "PASS", plan["validation"]["errors"])
        self.assertEqual(plan["validation"]["blocked_entrances"], [])
        self.assertGreaterEqual(len(plan["buildings"]), 80)
        contact=plan["validation"]["surface_contact"]
        self.assertLessEqual(contact["maximum_profile_contact_drift_m"],.04)
        boundary=contact["surface_boundary"]
        self.assertEqual(boundary["status"],"PASS")
        self.assertLessEqual(boundary["maximum_pad_edge_2cm_delta_m"],.001)
        self.assertLessEqual(boundary["maximum_pad_edge_2mm_delta_m"],.0001)
        self.assertTrue(all(row["converges"] for row in boundary["road_owner_seams"]))
        self.assertEqual(boundary["preservation_masks"]["status"],"ENGINEERED_SUPPORT_REQUIRED")

    def test_rotated_shell_and_thin_crossing_are_not_missed(self):
        shell = territory._polygon([0,0], 8, 10, 37)
        self.assertEqual(territory._segment_polygon([-20,0],[20,0],shell), 0)
        self.assertEqual(territory._polygon_distance(shell,territory._polygon([1,1],2,2,0)),0)
        self.assertGreater(territory._segment_polygon([20,20],[25,20],shell),10)

    def test_invalid_seed_is_rejected(self):
        for seed in (-1, 2**32, True, "71126"):
            with self.assertRaises(ValueError):territory.generate(ROOT,seed)

    def test_paved_sections_share_topology_and_resolve_actual_triangle_surface(self):
        review=self.plan['terrain']['paved_surface_review']
        self.assertTrue(review['records'])
        for road in self.plan['roads']+self.plan['approaches']:
            rows=road['paved_sections_m'];offsets=rows[0]['offsets_m']
            self.assertTrue(all(row['offsets_m']==offsets for row in rows),road['id'])
            self.assertIn(0.,offsets)
            self.assertIn(road['width_m']/2,offsets)
            self.assertIn(-road['width_m']/2,offsets)
            self.assertAlmostEqual(offsets[-1],road['width_m']/2+road['sidewalk_width_m'])
            self.assertLessEqual(max(b-a for a,b in zip(offsets,offsets[1:])),.200001)
            self.assertTrue(all(len(row['points_m'])==len(offsets) for row in rows))
        for row in review['records']:
            self.assertLessEqual(row['maximum_triangle_positive_ground_residual_m'],.02,row['id'])
            self.assertLessEqual(row['maximum_triangle_absolute_ground_residual_m'],.02,row['id'])
            self.assertIsNotNone(row['worst_transverse'])
            self.assertIsNotNone(row['worst_longitudinal'])
        # Actual measured failure from fixed-tip plan359a0d6a. Keep this tiny
        # evidence fixture portable; do not require a generated build folder.
        failed_triangle={'id':'Trailhead_Village_Loop',
                         'maximum_triangle_absolute_ground_residual_m':.5466242829589909}
        with patch.object(territory,'add_paved_sections',return_value={'records':[failed_triangle]}):
            rejected=territory.generate(ROOT,20261020)
        self.assertEqual(rejected['validation']['status'],'FAIL')
        self.assertIn('Trailhead_Village_Loop',rejected['terrain']['paved_surface_review']['triangle_failure_ids'])
        self.assertEqual(rejected['terrain']['paved_surface_review']['analytic_triangle_tolerance_m'],.02)
        # Prove the production orchestrator rejects this actual failed-plan
        # shape before creating output, drawing a map, or launching any engine.
        from tools.town_generation import generate_town as runner
        preview=SimpleNamespace(render_map=Mock())
        planner=SimpleNamespace(generate=Mock(return_value=rejected))
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'rejected'
            baseline=Path(directory)/'baseline';baseline.mkdir()
            (baseline/'living_town_complete.blend').write_bytes(b'Native must never be opened by an engine in this rejection test.')
            with patch.dict(sys.modules,{'territory':planner,'preview_territory':preview}),patch.object(runner.subprocess,'run') as launch:
                with self.assertRaisesRegex(ValueError,'Territory audit did not pass'):
                    runner.generate(output=output,baseline_root=baseline,blender=Path(__file__),pbr_library=Path(__file__))
                launch.assert_not_called()
                preview.render_map.assert_not_called()
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
