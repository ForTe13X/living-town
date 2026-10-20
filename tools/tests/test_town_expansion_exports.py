"""Tiny real GLB payloads exercise the portable town export verifier."""
import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest

from tools.town_generation.verify_expansion import inspect_glb


def triangle():
    """A self-contained indexed triangle with real position/normal/UV bytes."""
    position = struct.pack("<9f", 0,0,0, 1,0,0, 0,1,0)
    normal = struct.pack("<9f", 0,0,1, 0,0,1, 0,0,1)
    uv = struct.pack("<6f", 0,0, 1,0, 0,1)
    indices = struct.pack("<3H", 0,1,2)
    binary = bytearray(position+normal+uv+indices)
    binary.extend(b"\0"*((-len(binary)) % 4))
    document = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "MeasuredTriangle", "mesh": 0}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36, "target": 34962},
            {"buffer": 0, "byteOffset": 36, "byteLength": 36, "target": 34962},
            {"buffer": 0, "byteOffset": 72, "byteLength": 24, "target": 34962},
            {"buffer": 0, "byteOffset": 96, "byteLength": 6, "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3,
             "type": "VEC3", "min": [0,0,0], "max": [1,1,0]},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": 3, "type": "SCALAR"},
        ],
        "meshes": [{"primitives": [{"attributes": {
            "POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "mode": 4}]}],
    }
    return document, binary


def write_glb(path, document, binary):
    encoded = json.dumps(document, allow_nan=False, separators=(",", ":")).encode("utf-8")
    encoded += b" "*((-len(encoded)) % 4)
    total = 12+8+len(encoded)+8+len(binary)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, total)
                     +struct.pack("<II", len(encoded), 0x4E4F534A)+encoded
                     +struct.pack("<II", len(binary), 0x004E4942)+binary)
    return path


class ExpansionExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.document, self.binary = triangle()

    def inspect(self, name="triangle.glb", expected_buildings=None):
        return inspect_glb(write_glb(self.root/name, self.document, self.binary),expected_buildings=expected_buildings)

    def metadata(self):
        owner="Expansion_D06_Harbor_Back_Loop_L04"
        self.document["nodes"][0]["extras"]={"building_id":owner,"interior_building_id":owner,
            "interior_room_id":owner+"_L01_Bedroom","presentation_layer":"upper"}
        return owner

    def test_valid_embedded_triangle_requires_no_normal_map(self):
        report = self.inspect()
        self.assertEqual(report["mesh_nodes"], 1)
        self.assertEqual(report["unique_meshes"], 1)
        self.assertEqual(report["unique_geometry_triangles"], 1)
        self.assertEqual(report["images"], 0)
        self.assertEqual(report["normal_mapped_materials"], 0)
        self.assertEqual(len(report["sha256"]), 64)

    def test_invalid_accessor_buffer_view_reference_is_rejected(self):
        self.document["accessors"][0]["bufferView"] = 999
        with self.assertRaisesRegex(ValueError, "Invalid accessor bufferView reference"):
            self.inspect()

    def test_actual_index_payload_cannot_reference_a_missing_vertex(self):
        # Keep all counts and metadata valid; corrupt only the binary index.
        struct.pack_into("<H", self.binary, 100, 3)
        with self.assertRaisesRegex(ValueError, "Index payload references a missing vertex"):
            self.inspect()

    def test_actual_nan_position_is_rejected_despite_finite_declared_bounds(self):
        struct.pack_into("<f", self.binary, 0, float("nan"))
        with self.assertRaisesRegex(ValueError, "Non-finite actual POSITION payload"):
            self.inspect()

    def test_accessor_cannot_read_beyond_truncated_view(self):
        # The BIN remains intact, but the declared POSITION view is too short.
        self.document["bufferViews"][0]["byteLength"] = 32
        with self.assertRaisesRegex(ValueError, "Accessor exceeds buffer view"):
            self.inspect()

    def test_external_texture_image_is_rejected(self):
        self.document["images"] = [{"uri": "wall_albedo.png", "mimeType": "image/png"}]
        with self.assertRaisesRegex(ValueError, "External texture image"):
            self.inspect()

    def test_normals_and_uvs_are_required_even_without_normal_mapping(self):
        original = copy.deepcopy(self.document)
        for attribute in ("NORMAL", "TEXCOORD_0"):
            with self.subTest(missing=attribute):
                self.document = copy.deepcopy(original)
                del self.document["meshes"][0]["primitives"][0]["attributes"][attribute]
                with self.assertRaisesRegex(ValueError, "Mesh lacks position, normal or UV"):
                    self.inspect(attribute+"_missing.glb")

    def test_complete_loop_and_lot_owner_is_preserved(self):
        owner=self.metadata()
        report=self.inspect(expected_buildings={owner})
        self.assertEqual(report["building_owner_count"],1)
        self.assertEqual(report["building_ids"],[owner])
        self.assertEqual(report["presentation_layer_counts"],{"upper":1})

    def test_truncated_building_interior_or_room_owner_is_rejected(self):
        for field,value,message in (
            ("building_id","Expansion_D06_Harbor_Back","Mesh building owner"),
            ("interior_building_id","Expansion_D06_Harbor_Back","Interior building owner"),
            ("interior_room_id","Expansion_D06_Harbor_Back_L01_Bedroom","Interior room owner")):
            with self.subTest(field=field):
                owner=self.metadata();self.document["nodes"][0]["extras"][field]=value
                with self.assertRaisesRegex(ValueError,message):
                    self.inspect(field+"_truncated.glb",expected_buildings={owner})

    def test_missing_or_invalid_presentation_layer_is_rejected(self):
        for layer in (None,"undocumented"):
            with self.subTest(layer=layer):
                owner=self.metadata()
                if layer is None:del self.document["nodes"][0]["extras"]["presentation_layer"]
                else:self.document["nodes"][0]["extras"]["presentation_layer"]=layer
                with self.assertRaisesRegex(ValueError,"Mesh lacks valid presentation layer"):
                    self.inspect(expected_buildings={owner})

    def test_expected_district_owner_coverage_is_complete(self):
        owner=self.metadata()
        with self.assertRaisesRegex(ValueError,"District building owner coverage differs"):
            self.inspect(expected_buildings={owner,"Expansion_D06_Other_Loop_L04"})


if __name__ == "__main__":
    unittest.main()
