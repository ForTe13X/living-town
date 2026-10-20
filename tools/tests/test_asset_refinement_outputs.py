"""Actual GLB binary fixtures exercise portable cafe artifact failure modes."""

import copy
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import zlib

from tools.asset_refinement import verify_outputs as verifier
from tools.asset_refinement import workflows


def png_bytes(width, height):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload)))
    row = b"\0" + b"\x80\x70\x60\xff" + b"\0" * (width * 4 - 4)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))


def fixture_glb(path, *, whole=False, mutate=None, translate=(0, 0, 0)):
    binary, views, accessors = bytearray(), [], []
    def array(values, kind, component, fmt):
        start = len(binary)
        for value in values:
            binary.extend(struct.pack("<" + fmt, *value))
        length = len(binary) - start
        binary.extend(b"\0" * (-len(binary) % 4))
        views.append({"buffer": 0, "byteOffset": start, "byteLength": length})
        accessors.append({"bufferView": len(views) - 1, "componentType": component,
                          "count": len(values), "type": kind})
        return len(accessors) - 1
    position = array([(0, 0, 0), (1, 0, 0), (0, 1, 0)], "VEC3", 5126, "fff")
    normal = array([(0, 0, 1)] * 3, "VEC3", 5126, "fff")
    uv = array([(0, 0), (1, 0), (0, 1)], "VEC2", 5126, "ff")
    tangent = array([(1, 0, 0, 1)] * 3, "VEC4", 5126, "ffff")
    indices = array([(0,), (1,), (2,)], "SCALAR", 5123, "H")
    image = png_bytes(2, 2)
    views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(image)})
    binary.extend(image)
    binary.extend(b"\0" * (-len(binary) % 4))
    primitive = {"attributes": {"POSITION": position, "NORMAL": normal,
                                "TEXCOORD_0": uv, "TANGENT": tangent},
                 "indices": indices, "material": 0}
    meshes = [{"name": "CounterMesh", "primitives": [primitive]}]
    nodes = [{"name": "CounterRoot", "extras": {"original_geometry": True},
              "children": [1], "translation": list(translate)},
             {"name": "CounterPart", "mesh": 0,
              "extras": {"original_geometry": True, "furniture_part": "slab"}}]
    roots = [0]
    if whole:
        meshes.append({"name": "ArchitectureMesh", "primitives": [copy.deepcopy(primitive)]})
        nodes.append({"name": "Architecture", "mesh": 1, "translation": [5, 0, 0]})
        roots.append(2)
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": roots}],
           "nodes": nodes, "meshes": meshes,
           "materials": [{"name": "Stone", "normalTexture": {"index": 0},
                          "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
           "textures": [{"source": 0}], "images": [{"bufferView": len(views)-1, "mimeType": "image/png"}],
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(binary)}]}
    if mutate:
        mutate(doc, binary)
    encoded = json.dumps(doc).encode()
    encoded += b" " * (-len(encoded) % 4)
    result = (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary))
              + struct.pack("<I4s", len(encoded), b"JSON") + encoded
              + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    path.write_bytes(result)
    return doc


class OutputVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="town_glb_contract_")
        self.base = Path(self.temp.name)
        self.glb = self.base / "fixture.glb"
        fixture_glb(self.glb)

    def tearDown(self):
        self.temp.cleanup()

    def test_valid_dense_binary_and_actual_root_transform_are_checked(self):
        fixture_glb(self.glb, translate=(2, 3, -4))
        result = verifier.inspect_glb(
            self.glb, expected_nodes=["CounterPart"], expected_root="CounterRoot",
            expected_bounds_blender={"min": [2, 4, 3], "max": [3, 4, 4]})
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["triangles_unique"], 1)
        self.assertEqual(result["normal_mapped_primitives"], 1)
        self.assertTrue(result["standalone_root_retained"])
        self.assertEqual(result["semantic_bounds_gltf_m"], [[2., 3., -4.], [3., 4., -4.]])

    def test_external_image_and_buffer_uri_are_rejected(self):
        for member, change in (("images", "missing.png"), ("buffers", "external.bin")):
            fixture_glb(self.glb, mutate=lambda doc, data: doc[member][0].update(uri=change))
            with self.assertRaisesRegex(ValueError, "URI forbidden"):
                verifier.inspect_glb(self.glb)

    def test_normal_map_missing_uv_or_tangent_is_rejected(self):
        for attribute in ("TEXCOORD_0", "TANGENT"):
            fixture_glb(self.glb, mutate=lambda doc, data: doc["meshes"][0]["primitives"][0]["attributes"].pop(attribute))
            with self.assertRaisesRegex(ValueError, "TEXCOORD|TANGENT"):
                verifier.inspect_glb(self.glb)

    def test_material_requesting_missing_uv1_is_rejected(self):
        fixture_glb(self.glb, mutate=lambda doc, data: doc["materials"][0]["normalTexture"].update(texCoord=1))
        with self.assertRaisesRegex(ValueError, "missing TEXCOORD"):
            verifier.inspect_glb(self.glb)

    def test_only_supported_required_uv_transform_is_accepted(self):
        def supported(doc, binary):
            doc["extensionsRequired"] = ["KHR_texture_transform"]
            doc["materials"][0]["normalTexture"]["extensions"] = {
                "KHR_texture_transform": {"scale": [2, 2], "offset": [0, -1]}}
        fixture_glb(self.glb, mutate=supported)
        self.assertEqual(verifier.inspect_glb(self.glb)["status"], "PASS")
        fixture_glb(self.glb, mutate=lambda doc, binary: doc.update(
            extensionsRequired=["KHR_draco_mesh_compression"]))
        with self.assertRaisesRegex(ValueError, "only supports required"):
            verifier.inspect_glb(self.glb)

    def test_supported_uv_transform_still_rejects_malformed_or_missing_coordinates(self):
        for transform in ({"scale": [2]}, {"scale": [0, 1]}, {"rotation": float("nan")}, {"texCoord": 2}):
            def corrupt(doc, binary):
                doc["extensionsRequired"] = ["KHR_texture_transform"]
                doc["materials"][0]["normalTexture"]["extensions"] = {"KHR_texture_transform": transform}
            fixture_glb(self.glb, mutate=corrupt)
            with self.assertRaisesRegex(ValueError, "texture_transform|missing TEXCOORD"):
                verifier.inspect_glb(self.glb)

    def test_nontriangle_index_count_and_out_of_bounds_index_are_rejected(self):
        fixture_glb(self.glb, mutate=lambda doc, data: doc["accessors"][4].update(count=2))
        with self.assertRaisesRegex(ValueError, "index count"):
            verifier.inspect_glb(self.glb)
        def corrupt(doc, binary):
            start = doc["bufferViews"][4]["byteOffset"]
            struct.pack_into("<H", binary, start, 99)
        fixture_glb(self.glb, mutate=corrupt)
        with self.assertRaisesRegex(ValueError, "outside POSITION"):
            verifier.inspect_glb(self.glb)

    def test_bad_accessor_span_and_nonfinite_position_are_rejected(self):
        fixture_glb(self.glb, mutate=lambda doc, data: doc["accessors"][0].update(count=1000))
        with self.assertRaisesRegex(ValueError, "exceeds"):
            verifier.inspect_glb(self.glb)
        def corrupt(doc, binary):
            struct.pack_into("<f", binary, 0, float("nan"))
        fixture_glb(self.glb, mutate=corrupt)
        with self.assertRaisesRegex(ValueError, "Non-finite"):
            verifier.inspect_glb(self.glb)

    def test_semantic_child_extras_and_hierarchy_are_checked(self):
        fixture_glb(self.glb, mutate=lambda doc, data: doc["nodes"][1].pop("extras"))
        with self.assertRaisesRegex(ValueError, "extras missing"):
            verifier.inspect_glb(self.glb, expected_nodes=["CounterPart"])
        def detach(doc, binary):
            doc["nodes"][0]["children"] = []
            doc["scenes"][0]["nodes"].append(1)
        fixture_glb(self.glb, mutate=detach)
        with self.assertRaisesRegex(ValueError, "escaped"):
            verifier.inspect_glb(self.glb, expected_nodes=["CounterPart"], expected_root="CounterRoot")

    def test_wrong_actual_transform_cannot_pass_by_declared_bounds(self):
        fixture_glb(self.glb, translate=(0, 4, 0))
        with self.assertRaisesRegex(ValueError, "bounds do not match"):
            verifier.inspect_glb(self.glb, expected_nodes=["CounterPart"],
                                 expected_bounds_blender={"min": [0, 0, 0], "max": [1, 0, 1]})

    def test_zstandard_container_is_recognized_without_claiming_native_reopen(self):
        path = self.base / "compressed.blend"
        path.write_bytes(b"\x28\xb5\x2f\xfd" + b"compressed fixture envelope")
        result = verifier.native_info(path)
        self.assertTrue(result["compression_magic_verified"])
        self.assertFalse(result["native_header_verified"])
        self.assertFalse(result["native_reopened"])
        path.write_bytes(b"not a Blender container")
        with self.assertRaisesRegex(ValueError, "neither Blender"):
            verifier.native_info(path)

    def make_hero(self):
        hero, repo = self.base / "hero", self.base / "repo"
        (hero / "input").mkdir(parents=True)
        (hero / "renders").mkdir()
        modules = {}
        for name in verifier.SOURCE_MODULES:
            path = repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# fixture module\n")
            modules[name] = verifier.sha(path)
        concept = repo / "art/living_town/concept/01_idealized_presentation.png"
        concept.parent.mkdir(parents=True)
        concept.write_bytes(png_bytes(2, 2))
        fixture_glb(hero / "cafe_hero.glb", whole=True)
        fixture_glb(hero / "input/counter.glb")
        (hero / "cafe_hero.blend").write_bytes(b"BLENDER-v502 header-only fixture")
        for name in verifier.VIEW_ORDER:
            (hero / "input" / (name + ".png")).write_bytes(png_bytes(1024, 1024))
        for name in ("01_cafe_street.png", "02_cafe_interior.png"):
            (hero / "renders" / name).write_bytes(png_bytes(2, 2))
        record = {
            "schema": "living_town.reconstructed_cafe_hero.v1", "ai_inference_executed": False,
            "source_modules": modules, "concept_sha256": verifier.sha(concept),
            "counter": {"root": "CounterRoot", "objects": ["CounterPart"], "triangles": 1,
                        "bounds": {"min": [0, 0, 0], "max": [1, 0, 1]}},
            "bistro_sets": [{"triangles": 1}, {"triangles": 1}],
            "conditioning_views": [
                {"name": name, "image": "input/" + name + ".png", "ortho_scale_m": 3.8,
                 "sha256": verifier.sha(hero / "input" / (name + ".png")),
                 "camera_position_blender_m": position}
                for name, position in zip(verifier.VIEW_ORDER, [(0, -5, .6), (-5, 0, .6), (0, 5, .6), (5, 0, .6)])],
            "files": {path.relative_to(hero).as_posix(): {"sha256": verifier.sha(path), "bytes": path.stat().st_size}
                      for path in hero.rglob("*") if path.is_file()}}
        (hero / "hero_manifest.json").write_text(json.dumps(record), encoding="utf-8")
        return hero, repo, record

    def test_bound_hero_passes_and_wrong_view_order_or_changed_source_fails(self):
        hero, repo, record = self.make_hero()
        result = verifier.verify(hero, repo=repo)
        self.assertEqual(result["status"], "PASS")
        self.assertFalse(result["visual_review_performed"])
        record["conditioning_views"][1:3] = reversed(record["conditioning_views"][1:3])
        (hero / "hero_manifest.json").write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, "view order"):
            verifier.verify(hero, repo=repo)
        record["conditioning_views"][1:3] = reversed(record["conditioning_views"][1:3])
        (hero / "hero_manifest.json").write_text(json.dumps(record))
        (repo / "tools/asset_refinement/hero_scene.py").write_text("# changed\n")
        with self.assertRaisesRegex(ValueError, "Current source module differs"):
            verifier.verify(hero, repo=repo)

    def test_prepared_bindings_sheet_pixels_and_offline_license_gates(self):
        hero, repo, record = self.make_hero()
        prepared, workflow_dir = self.base / "prepared", self.base / "workflows"
        prepared.mkdir()
        preparation = {"schema": "living_town.owned_view_preparation.v1",
                       "source_hero_manifest_sha256": verifier.sha(hero / "hero_manifest.json"),
                       "view_order": list(verifier.VIEW_ORDER), "ai_inference_executed": False,
                       "views": []}
        for name in verifier.VIEW_ORDER:
            source, output = hero / "input" / (name + ".png"), prepared / (name + ".png")
            shutil.copyfile(source, output)
            preparation["views"].append({"name": name, "source_path": str(source),
                                         "source_sha256": verifier.sha(source), "path": output.name,
                                         "sha256": verifier.sha(output), "dimensions": [1024, 1024], "mode": "RGBA"})
        shutil.copyfile(hero / "input/counter.glb", prepared / "counter.glb")
        preparation["mesh"] = {"source_path": str(hero / "input/counter.glb"), "path": "counter.glb",
                               "sha256": verifier.sha(prepared / "counter.glb")}
        try:
            from PIL import Image
        except ImportError:
            (prepared / "turnaround_sheet.png").write_bytes(png_bytes(4096, 1024))
        else:
            sheet = Image.new("RGBA", (4096, 1024))
            for index, name in enumerate(verifier.VIEW_ORDER):
                with Image.open(prepared / (name + ".png")) as view:
                    sheet.paste(view, (index * 1024, 0))
            sheet.save(prepared / "turnaround_sheet.png")
        preparation["sheet"] = {"path": "turnaround_sheet.png", "dimensions": [4096, 1024],
                                "sha256": verifier.sha(prepared / "turnaround_sheet.png")}
        (prepared / "preparation_manifest.json").write_text(json.dumps(preparation))
        workflows.build_variants(workflow_dir, prepared / "counter.glb", prepared / "front.png",
                                 prepared / "turnaround_sheet.png")
        result = verifier.verify(hero, prepared, repo=repo, workflows=workflow_dir)
        self.assertEqual(result["prepared"]["status"], "PASS")
        manifest_path = workflow_dir / "workflow_manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["uv"]["atlas_validated_by_caller"] = True
        manifest["uv"]["ultratex_mode"] = "keep_existing"
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "Metric hero UVs"):
            verifier.verify(hero, prepared, repo=repo, workflows=workflow_dir)


if __name__ == "__main__":
    unittest.main()
