"""Host-only preservation and refusal controls; no external assets or engines."""
from __future__ import annotations

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

MODULE = Path(__file__).resolve().parents[1] / "asset_refinement" / "append_normal_image.py"
SPEC = importlib.util.spec_from_file_location("append_normal_image", MODULE)
writer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(writer)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png(width=2, height=2, *, stream=None, depth=8, color=6):
    pixel = bytes([128, 128, 255] if color == 2 else [128, 128, 255, 255])
    scan = b"".join(b"\0" + pixel * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, color, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scan) if stream is None else stream) + chunk(b"IEND", b""))


def glb(doc, binary, *, json_bytes=None):
    payload = (json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
               if json_bytes is None else json_bytes)
    payload += b" " * (-len(payload) % 4)
    binary += b"\0" * (-len(binary) % 4)
    return (struct.pack("<III", 0x46546C67, 2, 28 + len(payload) + len(binary))
            + struct.pack("<II", len(payload), 0x4E4F534A) + payload
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def fixture():
    binary, views = bytearray(), []
    def add(data):
        binary.extend(b"\0" * (-len(binary) % 4))
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary.extend(data)
        return len(views) - 1
    records = [
        (add(struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0)), 5126, 3, "VEC3"),
        (add(struct.pack("<9f", *([0, 0, 1] * 3))), 5126, 3, "VEC3"),
        (add(struct.pack("<6f", 0, 0, 1, 0, 0, 1)), 5126, 3, "VEC2"),
        (add(struct.pack("<3H", 0, 1, 2)), 5123, 3, "SCALAR"),
        (add(bytes(12)), 5121, 3, "VEC4"),
        (add(struct.pack("<12f", *([1, 0, 0, 0] * 3))), 5126, 3, "VEC4"),
        (add(struct.pack("<16f", *[1 if i % 5 == 0 else 0 for i in range(16)])), 5126, 1, "MAT4"),
        (add(struct.pack("<2f", 0, 1)), 5126, 2, "SCALAR"),
        (add(struct.pack("<6f", 0, 0, 0, 0, 0, .1)), 5126, 2, "VEC3"),
        (add(struct.pack("<6f", 0, 0, 0, .2, 0, 0)), 5126, 2, "VEC3"),
    ]
    image_views = [add(png()) for _ in range(3)]
    doc = {"asset": {"version": "2.0", "generator": "host fixture"},
           "buffers": [{"byteLength": len(binary), "extras": {"retain": True}}], "bufferViews": views,
           "accessors": [{"bufferView": v, "componentType": c, "count": n, "type": t} for v, c, n, t in records],
           "images": [{"bufferView": v, "mimeType": "image/png"} for v in image_views],
           "textures": [{"source": i, "sampler": 0} for i in range(3)],
           "samplers": [{"magFilter": 9729, "minFilter": 9987}],
           "materials": [{"name": "body", "normalTexture": {"index": 0},
                          "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}, "metallicRoughnessTexture": {"index": 2}}},
                         {"name": "untextured", "pbrMetallicRoughness": {"roughnessFactor": .8}}],
           "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2,
                                                      "JOINTS_0": 4, "WEIGHTS_0": 5}, "indices": 3, "material": 0}]}],
           "nodes": [{"mesh": 0, "skin": 0, "children": [1]}, {"name": "root"}],
           "skins": [{"joints": [1], "inverseBindMatrices": 6}],
           "animations": [{"name": name, "samplers": [{"input": 7, "output": output}],
                           "channels": [{"sampler": 0, "target": {"node": 1, "path": "translation"}}]}
                          for name, output in (("idle", 8), ("walk", 9))],
           "scenes": [{"nodes": [0]}], "scene": 0,
           "extras": {"unicode": "crème", "retain": [1, 2, 3]}}
    return doc, bytes(binary)


class AppendNormalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source, self.normal, self.output = [self.root / n for n in ("source.glb", "normal.png", "output.glb")]
        self.doc, self.binary = fixture()
        self.source.write_bytes(glb(self.doc, self.binary))
        self.normal.write_bytes(png())
        self.before = [(p.stat().st_size, p.stat().st_mtime_ns, p.read_bytes()) for p in (self.source, self.normal)]
        self.kw = {"expected_source_sha256": sha(self.source.read_bytes()),
                   "expected_png_sha256": sha(self.normal.read_bytes()), "sampler": {"minFilter": 9987, "magFilter": 9729},
                   "expected_dimensions": [2, 2], "image_name": "Reviewed normal"}

    def append(self, **kwargs):
        return writer.append_normal_png(self.source, self.normal, self.output, **(self.kw | kwargs))

    def verify(self):
        return writer.verify_normal_append(self.source, self.normal, self.output, **self.kw)

    def replace_source(self, doc=None, binary=None, raw=None):
        self.source.write_bytes(raw if raw is not None else glb(doc or self.doc, self.binary if binary is None else binary))
        self.kw["expected_source_sha256"] = sha(self.source.read_bytes())

    def replace_png(self, raw):
        self.normal.write_bytes(raw)
        self.kw["expected_png_sha256"] = sha(raw)

    def refuse_without_output(self, **kwargs):
        with self.assertRaises((ValueError, zlib.error)):
            self.append(**kwargs)
        self.assertFalse(self.output.exists())

    def test_exact_prefix_entire_json_and_input_preservation(self):
        report = self.append()
        self.assertTrue(report["sampler_reused"])
        old, oldbin = writer._parse_glb(self.source.read_bytes())
        fresh, newbin = writer._parse_glb(self.output.read_bytes())
        self.assertEqual(newbin[:len(oldbin)], oldbin)
        self.assertEqual(newbin[len(oldbin):len(oldbin) + self.normal.stat().st_size], self.normal.read_bytes())
        self.assertEqual(fresh["bufferViews"][-1]["byteOffset"], len(oldbin))
        self.assertEqual(fresh["skins"], old["skins"])
        self.assertEqual(fresh["animations"], old["animations"])
        self.assertEqual(fresh["materials"][0]["pbrMetallicRoughness"], old["materials"][0]["pbrMetallicRoughness"])
        restored = copy.deepcopy(fresh)
        for k in ("bufferViews", "images", "textures"):
            restored[k].pop()
        restored["buffers"][0]["byteLength"] = old["buffers"][0]["byteLength"]
        restored["materials"][0]["normalTexture"] = old["materials"][0]["normalTexture"]
        self.assertEqual(restored, old)
        for p, before in zip((self.source, self.normal), self.before):
            self.assertEqual((p.stat().st_size, p.stat().st_mtime_ns, p.read_bytes()), before)
        self.assertEqual(self.verify()["sha256"], report["sha256"])

    def test_new_sampler_and_absent_sampler_array(self):
        report = self.append(sampler={"minFilter": 9728, "wrapS": 33071, "wrapT": 33648})
        self.assertFalse(report["sampler_reused"])
        self.assertEqual(report["appended_sampler_count"], 1)
        self.output.unlink()
        doc = copy.deepcopy(self.doc)
        del doc["samplers"]
        for texture in doc["textures"]:
            del texture["sampler"]
        self.replace_source(doc)
        self.assertEqual(self.append()["appended_sampler_count"], 1)

    def test_rgb_png_optional_name_and_identity_binding(self):
        self.replace_png(png(color=2))
        doc = copy.deepcopy(self.doc)
        doc["materials"][0]["normalTexture"]["extensions"] = {
            "KHR_texture_transform": {"offset": [0, 0], "scale": [1, 1], "texCoord": 0, "rotation": 0}}
        self.replace_source(doc)
        self.append(image_name=None)
        fresh, _ = writer._parse_glb(self.output.read_bytes())
        self.assertEqual(fresh["images"][-1], {"bufferView": len(doc["bufferViews"]), "mimeType": "image/png"})

    def test_source_overwrite_and_existing_output_refused(self):
        for output in (self.source, self.normal):
            with self.subTest(output=output.name), self.assertRaises(ValueError):
                writer.append_normal_png(self.source, self.normal, output, **self.kw)
        self.output.write_bytes(b"owned elsewhere")
        with self.assertRaises(ValueError):
            self.append()
        self.assertEqual(self.output.read_bytes(), b"owned elsewhere")
        self.assertEqual(self.source.read_bytes(), self.before[0][2])

    def test_hashes_and_dimensions_must_match(self):
        for override in ({"expected_source_sha256": "0" * 64}, {"expected_png_sha256": "f" * 64},
                         {"expected_png_sha256": "xyz"}, {"expected_dimensions": [4, 2]},
                         {"expected_dimensions": [True, 2]}):
            with self.subTest(override=override):
                self.refuse_without_output(**override)

    def test_exclusive_creation_race(self):
        original_open = Path.open
        def raced(path, mode="r", *args, **kwargs):
            if path == self.output and mode == "xb":
                with original_open(path, "wb") as stream:
                    stream.write(b"other owner won")
            return original_open(path, mode, *args, **kwargs)
        with patch.object(Path, "open", raced), self.assertRaises(FileExistsError):
            self.append()
        self.assertEqual(self.output.read_bytes(), b"other owner won")

    def test_input_change_before_create(self):
        original = writer._assert_unchanged
        def changed(path, state, digest):
            if path == self.normal:
                path.write_bytes(b"changed by another owner")
            original(path, state, digest)
        with patch.object(writer, "_assert_unchanged", changed), self.assertRaises(ValueError):
            self.append()
        self.assertFalse(self.output.exists())

    def test_png_crc_stream_filter_and_truncation_refused(self):
        bad_crc = bytearray(png()); bad_crc[-1] ^= 1
        for raw in (b"not PNG", bytes(bad_crc), png(stream=b"not zlib"), png(stream=zlib.compress(b"\0")),
                    png(stream=zlib.compress((b"\5" + bytes(8)) * 2)),
                    png(stream=zlib.compress((b"\0" + bytes(8)) * 2) + b"trailing"),
                    png(depth=16), png()[:-8], png() + b"tail"):
            with self.subTest(raw=sha(raw)):
                self.replace_png(raw)
                self.refuse_without_output()

    def test_glb_header_extent_external_buffer_and_nonfinite_refused(self):
        doc = copy.deepcopy(self.doc); doc["buffers"][0]["uri"] = "external.bin"
        external = glb(doc, self.binary)
        doc = copy.deepcopy(self.doc); doc["bufferViews"][0]["byteOffset"] = len(self.binary)
        extent = glb(doc, self.binary)
        dup = b'{"asset":{"version":"2.0"},"asset":{"version":"2.0"}}'
        special = copy.deepcopy(self.doc); special["extras"]["number"] = float("nan")
        nan = json.dumps(special).encode()
        special["extras"]["number"] = "OVERFLOW"
        inf = json.dumps(special).encode().replace(b'"OVERFLOW"', b'1e999')
        for raw in (b"glTF", self.source.read_bytes()[:-1], external, extent,
                    glb(self.doc, self.binary, json_bytes=dup), glb(self.doc, self.binary, json_bytes=nan),
                    glb(self.doc, self.binary, json_bytes=inf)):
            with self.subTest(raw=sha(raw)):
                self.replace_source(raw=raw)
                self.refuse_without_output()

    def test_normal_binding_uv_strength_transform_and_alias_refused(self):
        for info in ({}, {"index": 55}, {"index": 0, "texCoord": 1}, {"index": 0, "scale": .5},
                     {"index": 0, "scale": True}, {"index": 0, "extensions": {"KHR_texture_transform": {"offset": [.1, 0]}}},
                     {"index": 0, "extensions": {"VENDOR_normal": {}}}):
            doc = copy.deepcopy(self.doc); doc["materials"][0]["normalTexture"] = info
            self.replace_source(doc)
            with self.subTest(info=info):
                self.refuse_without_output()
        doc = copy.deepcopy(self.doc); doc["materials"][1]["normalTexture"] = {"index": 0}
        self.replace_source(doc)
        self.refuse_without_output()

    def test_invalid_sampler_policy_refused(self):
        for sampler in (None, {"minFilter": 0}, {"wrapS": 1}, {"magFilter": True}, {"extensions": {}}):
            with self.subTest(sampler=sampler):
                self.refuse_without_output(sampler=sampler)

    def test_fresh_verifier_detects_geometry_skin_clip_and_material_changes(self):
        self.append()
        clean = self.output.read_bytes()
        def mutations(doc):
            return [lambda: doc["nodes"][1].update(translation=[0, 0, .1]),
                    lambda: doc["skins"][0]["joints"].append(0),
                    lambda: doc["animations"][0]["channels"][0]["target"].update(path="scale"),
                    lambda: doc["meshes"][0]["primitives"][0]["attributes"].update(TEXCOORD_0=1),
                    lambda: doc["materials"][0]["pbrMetallicRoughness"].update(metallicFactor=1)]
        for index in range(5):
            doc, binary = writer._parse_glb(clean)
            mutations(doc)[index]()
            self.output.write_bytes(glb(doc, binary))
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, "Unexpected old JSON change"):
                self.verify()

    def test_fresh_verifier_detects_binary_offset_source_and_binding_changes(self):
        self.append()
        clean = self.output.read_bytes()
        for kind in ("position byte", "PNG byte", "offset", "image source", "binding", "extra extension"):
            doc, binary = writer._parse_glb(clean)
            binary = bytearray(binary)
            if kind == "position byte": binary[0] ^= 1
            elif kind == "PNG byte": binary[len(writer._parse_glb(self.source.read_bytes())[1]) + 20] ^= 1
            elif kind == "offset": doc["bufferViews"][-1]["byteOffset"] -= 4
            elif kind == "image source": doc["textures"][-1]["source"] = 0
            elif kind == "binding": doc["materials"][0]["normalTexture"]["texCoord"] = 1
            else: doc["extensionsUsed"] = ["PRIVATE_unapproved"]
            self.output.write_bytes(glb(doc, bytes(binary)))
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.verify()


if __name__ == "__main__":
    unittest.main()
