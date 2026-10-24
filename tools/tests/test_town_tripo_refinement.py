"""Offline retexture acceptance tests exercise actual GLB buffer mutations."""
import contextlib
import copy
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest

from tools.town_upgrade.tripo_refinement import GLB, compare_glbs, inspect_glb, main


def fixture():
    doc = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": 0}],
           "bufferViews": [], "accessors": [], "materials": [{"name": "linen", "pbrMetallicRoughness": {"roughnessFactor": .8}}],
           "nodes": [{"name": "Character", "mesh": 0, "skin": 0, "children": [1]}, {"name": "Pelvis"}],
           "skins": [{"joints": [1], "skeleton": 1}], "scenes": [{"nodes": [0]}], "scene": 0}
    binary = bytearray()

    def add(values, kind, code="f", normalized=False):
        binary.extend(b"\0" * (-len(binary) % 4))
        offset = len(binary)
        flat = [v for row in values for v in row]
        binary.extend(struct.pack("<" + code * len(flat), *flat))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
        component = {"f": 5126, "H": 5123, "B": 5121}[code]
        doc["accessors"].append({"bufferView": len(doc["bufferViews"]) - 1, "componentType": component,
                                 "count": len(values), "type": kind, "normalized": normalized})
        return len(doc["accessors"]) - 1

    position = add([(0., 0., 0.), (1., 0., 0.), (0., 1., 0.)], "VEC3")
    uv = add([(0., 0.), (1., 0.), (0., 1.)], "VEC2")
    normal = add([(0., 0., 1.)] * 3, "VEC3")
    tangent = add([(1., 0., 0., 1.)] * 3, "VEC4")
    joints = add([(0, 0, 0, 0)] * 3, "VEC4", "B")
    weights = add([(255, 0, 0, 0)] * 3, "VEC4", "B", True)
    indices = add([(0,), (1,), (2,)], "SCALAR", "H")
    morph = add([(0., 0., 0.), (0., .02, 0.), (0., 0., 0.)], "VEC3")
    inverse = add([tuple(float(i % 5 == 0) for i in range(16))], "MAT4")
    time = add([(0.,), (1.,)], "SCALAR")
    rotation = add([(0., 0., 0., 1.)] * 2, "VEC4")
    doc["skins"][0]["inverseBindMatrices"] = inverse
    doc["meshes"] = [{"name": "body", "weights": [0.], "extras": {"targetNames": ["SeatContact"]},
                      "primitives": [{"attributes": {"POSITION": position, "TEXCOORD_0": uv, "NORMAL": normal,
                                                     "TANGENT": tangent, "JOINTS_0": joints, "WEIGHTS_0": weights},
                                      "indices": indices, "targets": [{"POSITION": morph}], "material": 0}]}]
    doc["animations"] = [{"name": "Idle", "samplers": [{"input": time, "output": rotation, "interpolation": "LINEAR"}],
                           "channels": [{"sampler": 0, "target": {"node": 1, "path": "rotation"}}]}]
    # A valid one-pixel PNG is embedded to verify image bytes independently.
    import base64
    payload = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4K0AAAAASUVORK5CYII=")
    binary.extend(b"\0" * (-len(binary) % 4))
    offset = len(binary)
    binary.extend(payload)
    doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(payload)})
    doc["images"] = [{"bufferView": len(doc["bufferViews"]) - 1, "mimeType": "image/png"}]
    doc["textures"] = [{"source": 0}]
    doc["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
    return doc, binary


def write(path, doc, binary):
    doc = copy.deepcopy(doc)
    doc["buffers"][0]["byteLength"] = len(binary)
    encoded = json.dumps(doc, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    data = bytes(binary) + b"\0" * (-len(binary) % 4)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(data))
                     + struct.pack("<I4s", len(encoded), b"JSON") + encoded
                     + struct.pack("<I4s", len(data), b"BIN\0") + data)


def mutate_accessor(doc, binary, index, value, component=0):
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    code = {5126: "f", 5121: "B", 5123: "H"}[accessor["componentType"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0) + component * struct.calcsize(code)
    struct.pack_into("<" + code, binary, offset, value)


class TripoRefinementTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.source = Path(self.folder.name) / "source.glb"
        self.candidate = Path(self.folder.name) / "candidate.glb"
        self.doc, self.binary = fixture()
        write(self.source, self.doc, self.binary)

    def compare(self, doc=None, binary=None):
        write(self.candidate, self.doc if doc is None else doc, self.binary if binary is None else binary)
        return compare_glbs(self.source, self.candidate)

    def test_identical_actual_bytes_preserve_contract_with_real_bounds(self):
        result = self.compare()
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["source"]["sha256"], result["candidate"]["sha256"])
        self.assertEqual(result["source"]["primitives"][0]["maximum"], [1., 1., 0.])
        self.assertEqual(result["aesthetic_acceptance"], "NOT_EVALUATED")
        self.assertFalse(result["network_executed"])
        self.assertEqual(result["source"]["accessors"][5]["maximum"], [1., 0., 0., 0.])

    def test_each_geometry_uv_skin_and_morph_mutation_fails(self):
        for accessor, value in [(0, .1), (1, .2), (4, 1), (5, 254), (6, 2), (7, .03)]:
            with self.subTest(accessor=accessor):
                binary = bytearray(self.binary)
                mutate_accessor(self.doc, binary, accessor, value)
                result = self.compare(binary=binary)
                self.assertFalse(result["preservation_pass"])
                self.assertIn("geometry", result["changed_contracts"])

    def test_bind_and_animation_buffer_mutations_fail(self):
        for accessor, contract in [(8, "skins_inverse_bind"), (9, "morph_clips"), (10, "morph_clips")]:
            with self.subTest(accessor=accessor):
                binary = bytearray(self.binary)
                mutate_accessor(self.doc, binary, accessor, .5)
                self.assertIn(contract, self.compare(binary=binary)["changed_contracts"])

    def test_rest_hierarchy_clip_targets_and_morph_defaults_fail(self):
        mutations = [(lambda d: d["nodes"][1].update(translation=[0, .1, 0]), "nodes_rest_hierarchy"),
                     (lambda d: d["animations"][0].update(name="Walk"), "morph_clips"),
                     (lambda d: d["animations"][0]["channels"][0]["target"].update(path="weights"), "morph_clips"),
                     (lambda d: d["meshes"][0].update(weights=[1.]), "geometry"),
                     (lambda d: d["meshes"][0]["extras"].update(targetNames=["Other"]), "geometry")]
        for change, contract in mutations:
            with self.subTest(contract=contract):
                doc = copy.deepcopy(self.doc)
                change(doc)
                self.assertIn(contract, self.compare(doc=doc)["changed_contracts"])

    def test_normal_and_tangent_changes_are_separate_visual_warnings(self):
        for accessor in (2, 3):
            binary = bytearray(self.binary)
            mutate_accessor(self.doc, binary, accessor, .25)
            result = self.compare(binary=binary)
            self.assertTrue(result["preservation_pass"])
            self.assertTrue(result["normal_tangent_changed"])
            self.assertTrue(result["warnings"])

    def test_material_and_image_changes_are_allowed_and_fingerprinted(self):
        doc = copy.deepcopy(self.doc)
        doc["materials"][0]["pbrMetallicRoughness"]["roughnessFactor"] = .6
        result = self.compare(doc=doc)
        self.assertTrue(result["material_changed"])
        self.assertTrue(result["preservation_pass"])
        binary = bytearray(self.binary)
        binary[-1] ^= 1
        result = self.compare(binary=binary)
        self.assertTrue(result["image_changed"])
        self.assertTrue(result["preservation_pass"])
        self.assertNotEqual(result["source"]["images"][0]["sha256"], result["candidate"]["images"][0]["sha256"])

    def test_sparse_morph_and_interleaved_uv_compare_decoded_values(self):
        doc, binary = copy.deepcopy(self.doc), bytearray(self.binary)
        binary.extend(b"\0" * (-len(binary) % 4))
        index_offset = len(binary)
        binary.extend(b"\1\0\0\0")
        doc["bufferViews"].append({"buffer": 0, "byteOffset": index_offset, "byteLength": 1})
        index_view = len(doc["bufferViews"]) - 1
        value_offset = len(binary)
        binary.extend(struct.pack("<3f", 0., .02, 0.))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": value_offset, "byteLength": 12})
        doc["accessors"][7] = {"type": "VEC3", "count": 3, "componentType": 5126,
                              "sparse": {"count": 1, "indices": {"bufferView": index_view, "componentType": 5121},
                                         "values": {"bufferView": index_view + 1}}}
        offset = len(binary)
        binary.extend(struct.pack("<9f", 99., 0., 0., 99., 1., 0., 99., 0., 1.))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": 36, "byteStride": 12})
        doc["accessors"][1]["bufferView"] = len(doc["bufferViews"]) - 1
        doc["accessors"][1]["byteOffset"] = 4
        result = self.compare(doc, binary)
        self.assertTrue(result["preservation_pass"])
        self.assertNotEqual(result["source"]["sha256"], result["candidate"]["sha256"])

    def test_small_integer_matrix_padding_is_not_decoded_as_values(self):
        doc, binary = copy.deepcopy(self.doc), bytearray(self.binary)
        binary.extend(b"\0" * (-len(binary) % 4))
        offset = len(binary)
        binary.extend(bytes([1, 2, 3, 99, 4, 5, 6, 99, 7, 8, 9, 99]))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": 12})
        doc["accessors"].append({"bufferView": len(doc["bufferViews"]) - 1, "type": "MAT3", "componentType": 5121, "count": 1})
        write(self.candidate, doc, binary)
        self.assertEqual(GLB(self.candidate).accessor(len(doc["accessors"]) - 1), [(1, 2, 3, 4, 5, 6, 7, 8, 9)])

    def test_nonfinite_buffer_is_rejected_even_if_not_referenced(self):
        doc = copy.deepcopy(self.doc)
        doc["accessors"].append({"bufferView": 0, "componentType": 5126, "count": 1, "type": "SCALAR"})
        binary = bytearray(self.binary)
        # Keep geometry finite; put infinity in an unused accessor instead.
        offset = len(binary)
        binary.extend(b"\0" * (-offset % 4))
        offset = len(binary)
        binary.extend(struct.pack("<f", float("inf")))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": 4})
        doc["accessors"][-1]["bufferView"] = len(doc["bufferViews"]) - 1
        write(self.candidate, doc, binary)
        with self.assertRaisesRegex(ValueError, "Nonfinite accessor"):
            inspect_glb(self.candidate)

    def test_nonfinite_sparse_base_is_rejected_even_when_patched(self):
        doc, binary = copy.deepcopy(self.doc), bytearray(self.binary)
        mutate_accessor(doc, binary, 0, float("nan"))
        binary.extend(b"\0" * (-len(binary) % 4))
        offset = len(binary)
        binary.extend(b"\0\0\0\0")
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": 1})
        view = len(doc["bufferViews"]) - 1
        doc["accessors"][0]["sparse"] = {"count": 1, "indices": {"bufferView": view, "componentType": 5121}, "values": {"bufferView": 1}}
        write(self.candidate, doc, binary)
        with self.assertRaisesRegex(ValueError, "Nonfinite accessor"):
            inspect_glb(self.candidate)

    def test_compression_external_resources_and_invalid_spans_fail_closed(self):
        variants = []
        doc = copy.deepcopy(self.doc)
        doc["meshes"][0]["primitives"][0]["extensions"] = {"KHR_draco_mesh_compression": {"bufferView": 0}}
        variants.append(doc)
        doc = copy.deepcopy(self.doc)
        doc["bufferViews"][0]["extensions"] = {"EXT_meshopt_compression": {}}
        variants.append(doc)
        doc = copy.deepcopy(self.doc)
        doc["buffers"][0]["uri"] = "https://example.invalid/model.bin"
        variants.append(doc)
        doc = copy.deepcopy(self.doc)
        doc["bufferViews"][0]["byteLength"] = 10**9
        variants.append(doc)
        doc = copy.deepcopy(self.doc)
        doc["extensionsRequired"] = ["UNKNOWN_geometry_extension"]
        variants.append(doc)
        doc = copy.deepcopy(self.doc)
        doc["nodes"][0]["extensions"] = {"EXT_mesh_gpu_instancing": {"attributes": {"TRANSLATION": 0}}}
        variants.append(doc)
        for doc in variants:
            with self.subTest(doc=doc), self.assertRaises(ValueError):
                write(self.candidate, doc, self.binary)
                inspect_glb(self.candidate)

    def test_malformed_sparse_indices_and_spans_fail(self):
        for ids in [(1, 1), (2, 1), (1, 3)]:
            doc, binary = copy.deepcopy(self.doc), bytearray(self.binary)
            binary.extend(b"\0" * (-len(binary) % 4))
            offset = len(binary)
            binary.extend(bytes(ids) + b"\0\0")
            doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": 2})
            view = len(doc["bufferViews"]) - 1
            doc["accessors"][7] = {"type": "VEC3", "count": 3, "componentType": 5126,
                                  "sparse": {"count": 2, "indices": {"bufferView": view, "componentType": 5121},
                                             "values": {"bufferView": 0}}}
            write(self.candidate, doc, binary)
            with self.subTest(ids=ids), self.assertRaisesRegex(ValueError, "sorted, unique and in range"):
                inspect_glb(self.candidate)
        doc = copy.deepcopy(self.doc)
        doc["accessors"][0]["byteOffset"] = 4
        write(self.candidate, doc, self.binary)
        with self.assertRaisesRegex(ValueError, "span exceeds"):
            inspect_glb(self.candidate)

    def test_cli_writes_real_failure_report_and_never_overwrites(self):
        report = Path(self.folder.name) / "report.json"
        binary = bytearray(self.binary)
        mutate_accessor(self.doc, binary, 1, .25)
        write(self.candidate, self.doc, binary)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["compare", str(self.source), str(self.candidate), "--report", str(report)]), 1)
        result = json.loads(report.read_text())
        self.assertFalse(result["preservation_pass"])
        self.assertEqual(result["status"], "FAIL")
        with self.assertRaises(FileExistsError), contextlib.redirect_stdout(io.StringIO()):
            main(["inspect", str(self.source), "--report", str(report)])


if __name__ == "__main__":
    unittest.main()
