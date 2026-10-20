"""Negative geometry fixtures for the contextual wall export inspector."""
import unittest

from tools.asset_refinement.verify_wall_exports import check_geometry_arrays


def fixture():
    xs = [-.08, -.04, 0., .04, .08]
    zs = [0., .04, .08, .12, .16]
    positions = [(x, z, .081) for z in zs for x in xs]
    normals = [(0., 0., 1.)] * len(positions)
    uvs = [((x + .08) / 2, 1-z/2) for x, z, _ in positions]
    indices = []
    for j in range(4):
        for i in range(4):
            if i in (1, 2) and j in (1, 2):
                continue
            a = j * 5 + i
            indices.extend((a, a+1, a+6, a, a+6, a+5))
    geometry = {"width_m": .16, "height_m": .16, "height_range_m": [.0007, .004],
                "base_front_y_m": -.08, "actual_displacement_range_m": [.001, .001],
                "maximum_grid_spacing_m": .04, "mesh_quad_count": len(indices)//6,
                "apertures_x_z_width_height_m": [(0., .08, .08, .08)]}
    return positions, normals, uvs, indices, geometry


class WallGeometryTests(unittest.TestCase):
    def test_true_opening_and_metric_uv_pass(self):
        result = check_geometry_arrays(*fixture(), 0.)
        self.assertEqual(result["triangles"], 24)
        self.assertEqual(result["aperture_crossing_triangles"], 0)

    def test_reversed_height_displacement_is_rejected(self):
        positions, normals, uvs, indices, geometry = fixture()
        positions[0] = (*positions[0][:2], .079)
        with self.assertRaisesRegex(ValueError, "height decode"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)

    def test_unused_authoring_vertices_allow_wider_source_range(self):
        positions, normals, uvs, indices, geometry = fixture()
        geometry["actual_displacement_range_m"] = [.0008, .0039]
        result = check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)
        self.assertAlmostEqual(result["actual_displacement_range_m"][0], .001)

    def test_used_displacement_cannot_escape_authoring_range(self):
        positions, normals, uvs, indices, geometry = fixture()
        geometry["actual_displacement_range_m"] = [.0012, .0039]
        with self.assertRaisesRegex(ValueError, "authoring grid range"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)

    def test_unflipped_v_is_rejected(self):
        positions, normals, uvs, indices, geometry = fixture()
        uvs = [(u, 1-v) for u,v in uvs]
        with self.assertRaisesRegex(ValueError, "UV orientation"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)

    def test_triangle_crossing_aperture_is_rejected(self):
        positions, normals, uvs, indices, geometry = fixture()
        # Add one regular grid cell inside the omitted true opening.
        indices += [6, 7, 12, 6, 12, 11]
        geometry["mesh_quad_count"] += 1
        with self.assertRaisesRegex(ValueError, "aperture interior"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)

    def test_inward_normals_are_rejected(self):
        positions, normals, uvs, indices, geometry = fixture()
        normals[0] = (0., 0., -1.)
        with self.assertRaisesRegex(ValueError, "outward"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)

    def test_reversed_winding_is_rejected(self):
        positions, normals, uvs, indices, geometry = fixture()
        indices[0], indices[1] = indices[1], indices[0]
        with self.assertRaisesRegex(ValueError, "winding"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)

    def test_out_of_bounds_index_is_rejected(self):
        positions, normals, uvs, indices, geometry = fixture()
        indices[0] = len(positions)
        with self.assertRaisesRegex(ValueError, "indices"):
            check_geometry_arrays(positions, normals, uvs, indices, geometry, 0.)


if __name__ == "__main__":
    unittest.main()
