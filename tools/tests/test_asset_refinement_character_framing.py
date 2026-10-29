"""CI-discovered, path-independent controls for complete-vertex camera framing."""
import copy
import json
import math
import unittest

from tools.unreal import character_framing as framing


def box_pose():
    return {
        "status": "READ_ACTUAL_CPU_SKINNED_POSE_EXPLICIT_EVALUATION",
        "component_space_positions_cm": [
            [x, y, z] for x in (-10.0, 10.0)
            for y in (-25.0, 25.0) for z in (0.0, 180.0)
        ],
        "component_to_world": {
            "translation": [0.0, 0.0, 0.0],
            "scale": [1.0, 1.0, 1.0],
            "rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
        },
    }


def viewport_for(fit):
    forward = [-x for x in fit["direction_from_target"]]
    return {
        "perspective": True,
        "lit": True,
        "location_cm": fit["camera_cm"],
        "rotation_pitch_yaw_roll": [
            math.degrees(math.asin(forward[2])),
            math.degrees(math.atan2(forward[1], forward[0])), 0.0,
        ],
        "fov": fit["horizontal_FOV_degrees"],
        "viewport_width": 1014,
        "viewport_height": 550,
    }


class CharacterFramingTests(unittest.TestCase):
    def test_known_body_box_fits_all_orientations_in_centimeters(self):
        pose = box_pose()
        for direction in ([1, 0, 0], [1, -1, .15], [-1, 0, .05]):
            with self.subTest(direction=direction):
                fit = framing.fit(pose, direction, 45, [1014, 550], expected_vertex_count=8)
                proof = framing.verify_actual_view(pose, viewport_for(fit), expected_vertex_count=8)
                self.assertEqual(proof["status"], "ALL_NATIVE_VERTICES_INSIDE_SAFE_FRAME")
                self.assertEqual(proof["vertices"], 8)
                self.assertLessEqual(proof["maximum_abs_normalized_device_coordinate"], .88)
                self.assertGreaterEqual(proof["minimum_camera_depth_cm"], 100.0)
                self.assertEqual(fit["actual_world_AABB_minimum_maximum_cm"],
                                 [[-10.0, -25.0, 0.0], [10.0, 25.0, 180.0]])
                self.assertEqual(fit["target_cm"], [0.0, 0.0, 90.0])
                self.assertEqual(fit, framing.fit(pose, direction, 45, [1014, 550], expected_vertex_count=8))

    def test_transform_order_is_scale_then_quaternion_then_translation(self):
        pose = box_pose()
        pose["component_space_positions_cm"] = [[1, 0, 0], [0, 1, 1]]
        q = math.sqrt(.5)
        pose["component_to_world"] = {
            "scale": [2, 3, 4], "rotation_xyzw": [0, 0, q, q], "translation": [10, 20, 30],
        }
        before = copy.deepcopy(pose)
        actual = framing.world_vertices(pose, expected_vertex_count=2)
        for point, expected in zip(actual, ([10, 22, 30], [7, 20, 34])):
            for value, target in zip(point, expected):
                self.assertAlmostEqual(value, target, places=12)
        self.assertEqual(pose, before)

    def test_expected_count_is_explicit_and_no_outlier_is_dropped(self):
        pose = box_pose()
        with self.assertRaisesRegex(ValueError, "Every native render vertex"):
            framing.fit(pose, [1, 0, 0], 45, [1014, 550])
        pose["component_space_positions_cm"].append([0, 200, 90])
        fit = framing.fit(pose, [1, 0, 0], 45, [1014, 550], expected_vertex_count=9)
        self.assertEqual(fit["derived_projection"]["vertices"], 9)
        self.assertEqual(fit["actual_world_AABB_minimum_maximum_cm"][1][1], 200)
        pose["component_space_positions_cm"].pop()
        with self.assertRaisesRegex(ValueError, "Every native render vertex"):
            framing.fit(pose, [1, 0, 0], 45, [1014, 550], expected_vertex_count=9)
        for count in (0, -1, True, 8.0):
            with self.subTest(count=count), self.assertRaises(ValueError):
                framing.world_vertices(pose, expected_vertex_count=count)

    def test_default_count_stays_10707_without_fixture_files(self):
        pose = box_pose()
        pose["component_space_positions_cm"] = [[0, 0, 0]] * 10707
        self.assertEqual(len(framing.world_vertices(pose)), 10707)
        fit = framing.fit(pose, [1, 0, 0], 45, [1014, 550])
        self.assertEqual(fit["derived_projection"]["vertices"], 10707)

    def test_old_cropped_camera_fails_despite_positive_depth(self):
        pose = box_pose()
        fit = framing.fit(pose, [1, 0, 0], 45, [1014, 550], expected_vertex_count=8)
        view = viewport_for(fit)
        view["location_cm"] = [200, 0, 90]
        proof = framing.verify_actual_view(pose, view, expected_vertex_count=8)
        self.assertEqual(proof["status"], "REFUSED_NATIVE_VERTEX_FRAMING")
        self.assertTrue(proof["strictly_positive_camera_depth_for_every_vertex"])
        self.assertTrue(proof["conservative_depth_margin_satisfied"])
        self.assertGreater(proof["maximum_abs_normalized_device_coordinate"], 1.0)

    def test_aspect_change_and_opposite_facing_are_refused(self):
        pose = box_pose()
        fit = framing.fit(pose, [1, 0, 0], 45, [1014, 550], expected_vertex_count=8)
        view = viewport_for(fit)
        view["viewport_height"] = 275
        self.assertEqual(framing.verify_actual_view(pose, view, expected_vertex_count=8)["status"],
                         "REFUSED_NATIVE_VERTEX_FRAMING")
        view = viewport_for(fit)
        view["rotation_pitch_yaw_roll"] = [0, 0, 0]
        proof = framing.verify_actual_view(pose, view, expected_vertex_count=8)
        self.assertFalse(proof["strictly_positive_camera_depth_for_every_vertex"])
        self.assertIsNone(proof["maximum_abs_normalized_device_coordinate"])
        json.dumps(proof, allow_nan=False)

    def test_horizontal_fov_projection_uses_actual_aspect(self):
        points = [[0, 0, 0], [0, 0, 100]]
        proof = framing.evaluate(points, [300, 0, 50], [-1, 0, 0], 45, [1000, 500], .88)
        expected = 50 / (300 * math.tan(math.radians(45) * .5) / 2)
        self.assertAlmostEqual(proof["maximum_abs_normalized_device_coordinate"], expected, places=14)
        self.assertEqual(proof["status"], "ALL_NATIVE_VERTICES_INSIDE_SAFE_FRAME")
        self.assertEqual(framing.evaluate(points, [300, 0, 50], [-1, 0, 0], 45, [1000, 250], .88)["status"],
                         "REFUSED_NATIVE_VERTEX_FRAMING")

    def test_executed_native_float_accumulation_order_is_retained(self):
        # Python 3.12 float sum differs; UE's retained 3.11 receipts use this order.
        self.assertEqual(framing.dot([1e16, 1.0, -1e16], [1.0, 1.0, 1.0]), 0.0)

    def test_depth_margin_is_model_policy_not_native_clip_readback(self):
        proof = framing.evaluate([[0, 0, 0]], [50, 0, 0], [-1, 0, 0], 45, [1000, 500], .88)
        self.assertTrue(proof["strictly_positive_camera_depth_for_every_vertex"])
        self.assertFalse(proof["conservative_depth_margin_satisfied"])
        self.assertEqual(proof["required_conservative_depth_margin_cm"], 100.0)
        self.assertFalse(proof["actual_native_near_plane_direct_readback"])
        self.assertEqual(proof["status"], "REFUSED_NATIVE_VERTEX_FRAMING")

    def test_nonfinite_or_boolean_vertices_are_refused(self):
        for value in (float("nan"), float("inf"), -float("inf"), True):
            pose = box_pose()
            pose["component_space_positions_cm"][0][0] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                framing.fit(pose, [1, 0, 0], 45, [1014, 550], expected_vertex_count=8)
            with self.subTest(evaluate=value), self.assertRaises(ValueError):
                framing.evaluate([[value, 0, 0]], [300, 0, 0], [-1, 0, 0], 45, [1000, 500], .88)

    def test_bad_schema_transform_and_empty_points_are_refused(self):
        for pose in ({}, dict(box_pose(), status="untrusted_other_schema"),
                     dict(box_pose(), component_to_world=None),
                     dict(box_pose(), component_to_world={})):
            with self.subTest(pose=pose), self.assertRaises(ValueError):
                framing.world_vertices(pose, expected_vertex_count=8)
        for scale, quaternion in (([0, 1, 1], [0, 0, 0, 1]), ([-1, 1, 1], [0, 0, 0, 1]),
                                  ([1, 1, 1], [0, 0, 0, 2]), ([1, 1, 1], [0, 0, 0, float("nan")])):
            pose = box_pose()
            pose["component_to_world"].update(scale=scale, rotation_xyzw=quaternion)
            with self.subTest(scale=scale, quaternion=quaternion), self.assertRaises(ValueError):
                framing.world_vertices(pose, expected_vertex_count=8)
        with self.assertRaises(ValueError):
            framing.evaluate([], [300, 0, 0], [-1, 0, 0], 45, [1000, 500], .88)

    def test_invalid_basis_fov_aspect_and_usable_fraction_refuse(self):
        for direction in ([0, 0, 0], [0, 0, 1], [float("nan"), 0, 0]):
            with self.subTest(direction=direction), self.assertRaises(ValueError):
                framing.fit(box_pose(), direction, 45, [1014, 550], expected_vertex_count=8)
        for fov, size, usable in ((0, [1000, 500], .88), (120, [1000, 500], .88),
                                  (float("nan"), [1000, 500], .88), (45, [1000, 0], .88),
                                  (45, [1000.5, 500], .88), (45, [True, 500], .88),
                                  (45, [1000, 500], 0), (45, [1000, 500], 1),
                                  (45, [1000, 500], float("nan"))):
            with self.subTest(fov=fov, size=size, usable=usable), self.assertRaises(ValueError):
                framing.fit(box_pose(), [1, 0, 0], fov, size, usable, expected_vertex_count=8)

    def test_view_requires_lit_perspective_zero_roll_and_integral_dimensions(self):
        pose = box_pose()
        fit = framing.fit(pose, [1, 0, 0], 45, [1014, 550], expected_vertex_count=8)
        for key, value in (("lit", False), ("perspective", False), ("lit", "true"),
                           ("rotation_pitch_yaw_roll", [0, 180, .01]), ("viewport_width", 1014.5)):
            view = viewport_for(fit)
            view[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                framing.verify_actual_view(pose, view, expected_vertex_count=8)


if __name__ == "__main__":
    unittest.main()
