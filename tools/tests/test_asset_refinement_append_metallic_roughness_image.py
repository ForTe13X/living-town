"""Preservation/refusal controls; no Blender, network or appearance acceptance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

MODULE = Path(__file__).resolve().parents[1] / "asset_refinement/append_metallic_roughness_image.py"
spec = importlib.util.spec_from_file_location("append_mr_under_test", MODULE)
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def png(rgb=(20, 122, 0), depth=8):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, depth, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes((0, *rgb)))) + chunk(b"IEND", b""))


def container(doc, binary, json_bytes=None):
    encoded = json.dumps(doc, indent=2).encode() if json_bytes is None else json_bytes
    encoded += b" " * (-len(encoded) % 4)
    binary += b"\0" * (-len(binary) % 4)
    return (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary))
            + struct.pack("<I4s", len(encoded), b"JSON") + encoded
            + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def fixture():
    # Distinct actual geometry buffers, plus a sentinel that must survive untouched.
    pieces = [struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0),
              struct.pack("<9f", 0, 0, 1, 0, 0, 1, 0, 0, 1),
              struct.pack("<6f", 0, 0, 1, 0, 0, 1), struct.pack("<3H", 0, 1, 2)]
    binary = b""; views = []
    for data in pieces:
        binary += b"\0" * (-len(binary) % 4)
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary += data
    binary += b"\0" * (-len(binary) % 4)
    image = png((20, 100, 0)); views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(image)})
    binary += image + b"SOURCE_SENTINEL"
    doc = {"asset": {"version": "2.0", "generator": "independent fixture"},
           "buffers": [{"byteLength": len(binary)}], "bufferViews": views,
           "accessors": [{"bufferView": i, "componentType": kind, "count": 3, "type": form}
                         for i, kind, form in [(0, 5126, "VEC3"), (1, 5126, "VEC3"), (2, 5126, "VEC2"), (3, 5123, "SCALAR")]],
           "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
           "nodes": [{"mesh": 0, "translation": [3, 2, 1]}], "scenes": [{"nodes": [0]}], "scene": 0,
           "samplers": [{"wrapS": 10497, "wrapT": 10497}],
           "images": [{"bufferView": 4, "mimeType": "image/png", "name": "MR"},
                      {"bufferView": 4, "mimeType": "image/png", "name": "untouched separate image"}],
           "textures": [{"source": 0, "sampler": 0}, {"source": 1, "sampler": 0}],
           "materials": [{"pbrMetallicRoughness": {"metallicRoughnessTexture": {"index": 0},
               "baseColorTexture": {"index": 1}, "metallicFactor": 1, "roughnessFactor": 0.7},
               "extras": {"preserve": "coastal café"}}]}
    return doc, binary


def split(raw):
    # Independent fixed two-chunk reader used only for assertions.
    json_length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + json_length])
    binary_length = struct.unpack_from("<I", raw, 20 + json_length)[0]
    return doc, raw[28 + json_length:28 + json_length + binary_length]


class AppendMRTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.image, self.output = [self.root / n for n in ("source.glb", "orm.png", "out.glb")]
        self.doc, self.binary = fixture()
        self.source.write_bytes(container(self.doc, self.binary)); self.image.write_bytes(png())

    def apply(self, **overrides):
        args = {"expected_source_sha256": digest(self.source.read_bytes()),
                "expected_png_sha256": digest(self.image.read_bytes())}
        args.update(overrides)
        return writer.append_metallic_roughness_png(self.source, self.image, self.output, **args)

    def test_preserves_every_original_binary_byte_and_unrelated_JSON(self):
        before = {p: (p.stat().st_size, p.stat().st_mtime_ns, digest(p.read_bytes())) for p in (self.source, self.image)}
        result = self.apply(); original, old_bin = split(self.source.read_bytes()); modified, new_bin = split(self.output.read_bytes())
        self.assertEqual(new_bin[:len(old_bin)], old_bin)
        view = modified["bufferViews"][-1]
        self.assertEqual(new_bin[view["byteOffset"]:view["byteOffset"] + view["byteLength"]], self.image.read_bytes())
        for key in ("accessors", "meshes", "nodes", "scenes", "materials", "textures", "samplers"):
            self.assertEqual(original[key], modified[key])
        self.assertEqual(original["images"][1], modified["images"][1])
        modified["bufferViews"].pop(); modified["images"][0] = original["images"][0]; modified["buffers"] = original["buffers"]
        self.assertEqual(original, modified)
        self.assertEqual(before, {p: (p.stat().st_size, p.stat().st_mtime_ns, digest(p.read_bytes())) for p in before})
        self.assertFalse(result["image_semantics_UV_registration_art_rig_engine_or_performance_qualified"])

    def test_existing_output_and_input_alias_are_never_overwritten(self):
        self.output.write_bytes(b"retained")
        with self.assertRaises(ValueError): self.apply()
        self.assertEqual(self.output.read_bytes(), b"retained")
        self.output = self.source; original = self.source.read_bytes()
        with self.assertRaises(ValueError): self.apply()
        self.assertEqual(self.source.read_bytes(), original)

    def test_exclusive_creation_refuses_racing_output(self):
        original_bound = writer._bound_input
        def racing_read(path, *args):
            value = original_bound(path, *args)
            if path == self.image: self.output.write_bytes(b"racing owner")
            return value
        with patch.object(writer, "_bound_input", side_effect=racing_read):
            with self.assertRaises(FileExistsError): self.apply()
        self.assertEqual(self.output.read_bytes(), b"racing owner")

    def test_hash_mismatch_refuses_before_creation(self):
        with self.assertRaises(ValueError): self.apply(expected_png_sha256="0" * 64)
        self.assertFalse(self.output.exists())

    def test_invalid_GLB_containers_never_create_output(self):
        valid = self.source.read_bytes()
        cases = {"bad magic": b"FAIL" + valid[4:], "truncated": valid[:-1],
                 "length": valid[:8] + struct.pack("<I", len(valid) - 4) + valid[12:],
                 "wrong chunk": valid[:16] + b"BIN\0" + valid[20:]}
        for name, raw in cases.items():
            with self.subTest(name=name):
                self.source.write_bytes(raw)
                with self.assertRaises(ValueError): self.apply()
                self.assertFalse(self.output.exists())

    def test_external_aliased_and_out_of_bounds_sources_refused(self):
        def alias(d): d["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"] = 0
        def external(d): d["buffers"][0]["uri"] = "unrequested.bin"
        def badview(d): d["bufferViews"][0]["byteLength"] = 999999
        def missing(d): del d["materials"][0]["pbrMetallicRoughness"]["metallicRoughnessTexture"]
        for mutate in (alias, external, badview, missing):
            with self.subTest(case=mutate.__name__):
                doc = copy.deepcopy(self.doc); mutate(doc); self.source.write_bytes(container(doc, self.binary))
                with self.assertRaises(ValueError): self.apply()
                self.assertFalse(self.output.exists())

    def test_duplicate_nonfinite_JSON_and_extra_chunks_refused(self):
        valid = self.source.read_bytes()
        duplicate = container({}, self.binary, b'{"asset":{},"asset":{}}')
        nonfinite_doc = copy.deepcopy(self.doc); nonfinite_doc["extras"] = {"bad": float("nan")}
        extra = valid + struct.pack("<I4s", 0, b"JUNK")
        extra = extra[:8] + struct.pack("<I", len(extra)) + extra[12:]
        for raw in (duplicate, container(nonfinite_doc, self.binary), extra):
            with self.subTest(size=len(raw)):
                self.source.write_bytes(raw)
                with self.assertRaises(ValueError): self.apply()
                self.assertFalse(self.output.exists())

    def test_bad_PNG_signature_CRC_and_bit_depth_refused(self):
        good = png()
        for raw in (b"not PNG", good[:-1] + bytes([good[-1] ^ 1]), png(depth=16)):
            with self.subTest(size=len(raw)):
                self.image.write_bytes(raw)
                with self.assertRaises(ValueError): self.apply()
                self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
