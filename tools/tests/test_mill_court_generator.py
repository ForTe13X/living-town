"""Significant generator invariants without Blender or third-party dependencies."""

from pathlib import Path
import copy, collections, math, sys, unittest, json, os, tempfile, hashlib, shlex

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.mill_court.inputs import (
    load_inputs,
    compile_geometry,
    terrain_mesh,
    saved_blend_path,
    expected_asset_counts,
    BLEND_FILENAME,
)
from tools.mill_court.generate import main as generate, arguments
from tools.mill_court.design import Design

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mill_court_graph_fixture import main as graph_control


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def minus(a, b):
    return [x - y for x, y in zip(a, b)]


def hits(rows, origin, direction):
    distances = []
    for row in rows:
        vertices = row["vertices"]
        for face in row["faces"]:
            for i in range(1, len(face) - 1):
                a, b, c = [vertices[k] for k in (face[0], face[i], face[i + 1])]
                e1 = minus(b, a)
                e2 = minus(c, a)
                h = cross(direction, e2)
                det = dot(e1, h)
                if abs(det) < 1e-10:
                    continue
                f = 1 / det
                s = minus(origin, a)
                u = f * dot(s, h)
                if u < 0 or u > 1:
                    continue
                q = cross(s, e1)
                v = f * dot(direction, q)
                if v < 0 or u + v > 1:
                    continue
                distance = f * dot(e2, q)
                if distance > 1e-9 and all(abs(distance - d) > 1e-8 for d in distances):
                    distances.append(distance)
    return sorted(distances)


class GeneratorTests(unittest.TestCase):
    def test_apertures_are_empty_mesh_volume_and_walls_are_closed(self):
        d = Design({}, {})
        d.owner = "Test"
        d.plan = dict(
            id="Fixture", level_index=0, world_inner_southwest_xy_m=[0, 0], FF_world_m=0
        )
        d.wall(
            "DoorWindow",
            "horizontal",
            0,
            0,
            4,
            0.3,
            [(0.95, 0, 1.85, 2.2), (2.5, 1, 3.5, 2.2)],
            "plaster_A",
        )
        self.assertEqual(hits(d.objects, [1.4, -1, 1], (0, 1, 0)), [])
        self.assertEqual(hits(d.objects, [3, -1, 1.5], (0, 1, 0)), [])
        self.assertEqual(len(hits(d.objects, [1.4, -1, 2.35], (0, 1, 0))), 2)
        self.assertEqual(len(hits(d.objects, [3, -1, 0.5], (0, 1, 0))), 2)
        for row in d.objects:
            edges = collections.Counter(
                tuple(sorted((a, b)))
                for face in row["faces"]
                for a, b in zip(face, face[1:] + face[:1])
            )
            self.assertEqual(set(edges.values()), {2})

    def test_current_room_owners_furniture_and_stair_voids_bind(self):
        plan, site, _, _ = load_inputs()
        spec = compile_geometry(plan, site)
        self.assertEqual(spec, compile_geometry(plan, site))
        self.assertEqual(
            {
                (r["owner"], r["plan"], r["id"], tuple(r["source_facing"]))
                for r in spec["furniture"]
            },
            {
                (p["owner_id"], p["id"], f["id"], tuple(f["facing"]))
                for p in plan["plans"]
                for f in p["furniture"]
            },
        )
        for p in (p for p in plan["plans"] if p["level_index"]):
            x, y = p["world_inner_southwest_xy_m"]
            a, b, c, d = p["stair_void_bounds_m"]
            origin = [x + (a + c) / 2, y + (b + d) / 2, p["FF_world_m"] - 1]
            slabs = [
                r
                for r in spec["objects"]
                if r["plan"] == p["id"] and r["category"] == "slab"
            ]
            # Independent geometry ray through each actual slab hole.
            converted = []
            for r in slabs:
                lo, hi = r["low"], r["high"]
                v = [
                    (xx, yy, zz)
                    for xx, yy, zz in (
                        (lo[0], lo[1], lo[2]),
                        (hi[0], lo[1], lo[2]),
                        (hi[0], hi[1], lo[2]),
                        (lo[0], hi[1], lo[2]),
                        (lo[0], lo[1], hi[2]),
                        (hi[0], lo[1], hi[2]),
                        (hi[0], hi[1], hi[2]),
                        (lo[0], hi[1], hi[2]),
                    )
                ]
                converted.append(
                    dict(
                        vertices=v,
                        faces=[
                            [0, 3, 2, 1],
                            [4, 5, 6, 7],
                            [0, 1, 5, 4],
                            [1, 2, 6, 5],
                            [2, 3, 7, 6],
                            [3, 0, 4, 7],
                        ],
                    )
                )
            self.assertEqual(hits(converted, origin, (0, 0, 1)), [])

    def test_closed_slab_and_pocket_intrusion_are_rejected(self):
        plan, site, _, _ = load_inputs()
        bad = copy.deepcopy(plan)
        next(p for p in bad["plans"] if p["id"] == "A_Upper")["floor_slab"][
            "opening_bounds_m"
        ] = None
        with self.assertRaisesRegex(ValueError, "void declarations"):
            compile_geometry(bad, site)
        bad = copy.deepcopy(plan)
        next(
            w
            for p in bad["plans"]
            if p["id"] == "B_Upper"
            for w in p["walls"]
            if w["id"] == "child_n"
        )["end_m"] = 4.6
        with self.assertRaisesRegex(ValueError, "pocket-door travel"):
            compile_geometry(bad, site)

    def test_production_material_graph_keeps_finegrain_and_plankseams(self):
        proof = graph_control()
        self.assertTrue(proof["old_defect_negative_control_rejected"])

    def test_compact_terrain_grid_has_exact_deterministic_extent(self):
        _, _, grid, _ = load_inputs()
        mesh = terrain_mesh(grid)
        self.assertEqual(len(mesh["vertices"]), grid["width"] * grid["height"])
        self.assertEqual(
            mesh["vertices"][0], [*grid["origin_xy_m"], grid["height_values_z_m"][0]]
        )
        self.assertEqual(mesh, terrain_mesh(grid))

    def test_relocated_output_reopens_local_blend_not_old_author_path(self):
        with tempfile.TemporaryDirectory(
            dir=os.environ.get("MILL_COURT_TEST_TMPDIR")
        ) as folder:
            root = Path(folder)
            old = root / "old"
            moved = root / "moved"
            old.mkdir()
            moved.mkdir()
            payload = b"owned test blend bytes"
            old_blend = old / BLEND_FILENAME
            local = moved / BLEND_FILENAME
            old_blend.write_bytes(payload)
            local.write_bytes(payload)
            saved = dict(
                path=str(old_blend.resolve()),
                file=BLEND_FILENAME,
                bytes=len(payload),
                sha256=hashlib.sha256(payload).hexdigest(),
            )
            before = copy.deepcopy(saved)
            resolved = saved_blend_path(moved, saved)
            self.assertEqual(resolved, local.resolve())
            self.assertNotEqual(resolved, old_blend.resolve())
            self.assertEqual(
                hashlib.sha256(resolved.read_bytes()).hexdigest(), saved["sha256"]
            )
            old_blend.unlink()
            self.assertEqual(saved_blend_path(moved, saved), local.resolve())
            self.assertEqual(saved, before)
            legacy = {k: v for k, v in saved.items() if k != "file"}
            self.assertEqual(saved_blend_path(moved, legacy), local.resolve())
            with self.assertRaisesRegex(ValueError, "filename"):
                saved_blend_path(moved, {**saved, "file": "../" + BLEND_FILENAME})

    def test_reopen_counts_follow_valid_bound_custom_furniture(self):
        plan, site, _, _ = load_inputs()
        plan = copy.deepcopy(plan)
        plan["plans"][0]["furniture"].pop()
        spec = compile_geometry(plan, site)
        self.assertEqual(
            expected_asset_counts(plan["plans"], spec),
            dict(furniture_assets=46, stairs=2, risers=28, treads=26),
        )
        bad = copy.deepcopy(spec)
        bad["furniture"].pop()
        with self.assertRaisesRegex(ValueError, "bound floorplans"):
            expected_asset_counts(plan["plans"], bad)

    def test_invalid_view_ids_fail_before_any_output_creation(self):
        with tempfile.TemporaryDirectory(
            dir=os.environ.get("MILL_COURT_TEST_TMPDIR")
        ) as folder:
            root = Path(folder)
            sentinel = root / "outside.png"
            sentinel.write_bytes(b"preserve outside image")
            cases = [
                [],
                [{"id": "Same"}, {"id": "Same"}],
                [{"id": "Same"}, {"id": "same"}],
                [{"id": "../outside"}],
                [{"id": "..\\outside"}],
                [{"id": str(root / "absolute")}],
                [{"id": "CON"}],
                [{"id": ""}],
            ]
            for i, views in enumerate(cases):
                source = root / f"views{i}.json"
                source.write_text(json.dumps(views), encoding="utf8")
                output = root / f"output{i}"
                with self.subTest(views=views), self.assertRaises(ValueError):
                    generate(
                        [
                            "--geometry-only",
                            "--views-json",
                            str(source),
                            "--output",
                            str(output),
                        ]
                    )
                self.assertFalse(output.exists())
                self.assertEqual(sentinel.read_bytes(), b"preserve outside image")

    def test_render_export_are_opt_in_and_documented_blender_failures_are_nonzero(self):
        a = arguments(["--output", "unused"])
        self.assertFalse(a.render)
        self.assertFalse(a.export_geometry_glb)
        commands = [
            shlex.split(line)
            for line in (
                Path(__file__).resolve().parents[2] / "tools/mill_court/README.md"
            )
            .read_text(encoding="utf8")
            .splitlines()
            if line.startswith("blender --background")
        ]
        self.assertEqual(len(commands), 2)
        for cmd in commands:
            self.assertEqual(cmd[cmd.index("--python-exit-code") + 1], "1")
            self.assertLess(cmd.index("--python-exit-code"), cmd.index("--python"))


if __name__ == "__main__":
    unittest.main()
