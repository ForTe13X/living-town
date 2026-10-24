"""Pure source-topology and unchanged planting-safety gate regression fixtures."""
import importlib.util
import math
from pathlib import Path
from types import SimpleNamespace
import unittest

SOURCE = Path(__file__).resolve().parents[1]/"town_upgrade/natural_surface_details.py"
SPEC = importlib.util.spec_from_file_location("natural_surface_details", SOURCE)
DETAIL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DETAIL)


def ellipsoid():
    points = []
    for j in range(5):
        lat = -math.pi/2+math.pi*j/4
        for i in range(7):
            a = 2*math.pi*i/7
            points.append([48+1.2*math.cos(lat)*math.cos(a),
                           -54+.8*math.cos(lat)*math.sin(a), -.25+1.1*math.sin(lat)])
    faces = [(j*7+i, j*7+(i+1) % 7, (j+1)*7+(i+1) % 7, (j+1)*7+i)
             for j in range(4) for i in range(7)]
    return points, faces


class NaturalSurfaceDetailsTests(unittest.TestCase):
    def test_accepts_exact_original_headland_geometry(self):
        p, f = ellipsoid()
        result = DETAIL._ellipsoid_binding(p, f)
        self.assertAlmostEqual(result["radii_m"][0], 1.2)
        self.assertLess(result["maximum_recipe_error_m"], 1e-10)
        self.assertEqual(len(DETAIL._components(len(p), f)), 1)

    def test_accepts_legal_source_quad_triangulation(self):
        p, f = ellipsoid()
        tris = [tri for a, b, c, d in f for tri in ((a, b, c), (a, c, d))]
        self.assertEqual(DETAIL._ellipsoid_binding(p, tris)["source_grid_quads"], 28)

    def test_coastal_outcrops_bind_both_signed_coasts_and_their_own_recipe(self):
        p, f = ellipsoid()
        for sign in (-1, 1):
            coastal = [[x, sign*54+(y+54), z-.05] for x, y, z in p]
            bound = DETAIL._ellipsoid_binding(coastal, f, source_name="Coastal_Granite_Outcrops_Granite")
            self.assertAlmostEqual(bound["center_world_m"][1], sign*54)
            self.assertAlmostEqual(bound["center_world_m"][2], -.30)
            with self.assertRaises(ValueError):
                DETAIL._ellipsoid_binding(coastal, f)

    def test_built_masonry_and_similar_names_never_enter_rock_whitelist(self):
        p, f = ellipsoid()
        for name in ("Reserve_Stone_Stair_Granite", "Atlantic_Quay_Granite", "Granite_Headland_Granite.001"):
            with self.assertRaises(ValueError):
                DETAIL._ellipsoid_binding(p, f, source_name=name)

    def test_empty_and_absent_exact_batches_are_explicit_noops(self):
        class Objects:
            def get(self, name):
                return SimpleNamespace(type="MESH", data=SimpleNamespace(vertices=[], polygons=[])) if name == DETAIL.ROCK_NAME else None
        bpy = SimpleNamespace(data=SimpleNamespace(objects=Objects()))
        result = DETAIL._repair_rocks({"bpy": bpy})
        self.assertEqual(result["changed_object_count"], 0)
        self.assertEqual(result["rejected_object_count"], 0)
        self.assertEqual([r["status"] for r in result["source_batches"]],
                         ["EMPTY_SOURCE_BATCH_NO_MUTATIONS", "NOT_PRESENT_NO_MUTATIONS"])

    def test_rejects_moved_deformed_or_wrong_count_geometry(self):
        p, f = ellipsoid()
        changed = [list(point) for point in p]
        changed[18][0] += .01
        with self.assertRaises(ValueError):
            DETAIL._ellipsoid_binding(changed, f)
        moved = [[x, y+20, z] for x, y, z in p]
        with self.assertRaises(ValueError):
            DETAIL._ellipsoid_binding(moved, f)
        with self.assertRaises(ValueError):
            DETAIL._ellipsoid_binding(p[:-1], f)

    def test_rejects_wrong_topology_with_same_vertex_and_face_counts(self):
        p, f = ellipsoid()
        f[3] = (0, 1, 15, 14)
        with self.assertRaises(ValueError):
            DETAIL._ellipsoid_binding(p, f)

    def test_bounded_pond_and_bath_targets_do_not_require_layout_mutation(self):
        pond = {"center": [26, -42], "water_radii_m": [5, 3]}
        bath = {"id": "Reserve_Bathhouse", "center_m": [10, 20, 1],
                "footprint_m": [14, 7], "yaw_degrees": 90}
        result = DETAIL.drift_targets(pond, [bath])
        self.assertEqual(len(result), 5)
        self.assertEqual(len({r["id"] for r in result}), 5)
        self.assertEqual(pond["center"], [26, -42])

    def test_routes_buildings_and_pond_veto_before_native_queries(self):
        class Mask:
            def reason(self, *args):
                return "pond_water_and_shore_clearance"
        def forbidden(*args):
            self.fail("Rejected source mask must not be bypassed")
        value, reason = DETAIL.candidate_ground(Mask(), forbidden, forbidden, 0, 0, .4, "domestic_garden_border", "fern_02")
        self.assertIsNone(value)
        self.assertEqual(reason, "pond_water_and_shore_clearance")

    def test_native_paving_missing_ground_and_steep_land_are_rejected(self):
        class Mask:
            def reason(self, *args):
                return None
        args = (0, 0, .4, "domestic_garden_border", "grass_medium_01")
        self.assertEqual(DETAIL.candidate_ground(Mask(), lambda *a: "paving", lambda *a: 0, *args)[1], "actual_native_hardscape")
        self.assertEqual(DETAIL.candidate_ground(Mask(), lambda *a: None, lambda *a: float("nan"), *args)[1], "no_actual_ground_surface")
        self.assertEqual(DETAIL.candidate_ground(Mask(), lambda *a: None, lambda x, y, f: x*2, *args)[1], "steep_or_broken_terrain")
        good, error = DETAIL.candidate_ground(Mask(), lambda *a: None, lambda x, y, f: .1*x+3, *args)
        self.assertIsNone(error)
        self.assertAlmostEqual(good[0], 3)
        self.assertAlmostEqual(good[1], .1)


if __name__ == "__main__":
    unittest.main()
