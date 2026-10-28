"""Portable CPU intake regressions; temporary embedded GLBs, no external fixtures."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

for candidate_root in (Path(__file__).resolve().parents[2], Path.cwd()):
    if (candidate_root / "tools/asset_refinement/inspect_character_candidate.py").is_file():
        sys.path.insert(0, str(candidate_root))
        break
from tools.asset_refinement import inspect_character_candidate as intake


def rgba_png():
    """Two explicit pixels: opaque red and half-alpha green, encoded as PNG."""
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))
    header = struct.pack(">IIBBBBB", 2, 1, 8, 6, 0, 0, 0)
    pixels = b"\x00\xff\x00\x00\xff\x00\xff\x00\x80"
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def make_source(path, *, skinned=False, animation=False, bad_index=False):
    """Author one triangle; expected coordinates are independent literal values."""
    doc = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": 0}],
           "bufferViews": [], "accessors": [], "scene": 0,
           "scenes": [{"nodes": [0]}],
           "nodes": [{"mesh": 0, "translation": [2, 3, 4], "scale": [2, 2, 2]}]}
    binary = bytearray()

    def add_view(data):
        binary.extend(b"\0" * (-len(binary) % 4))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary.extend(data)
        return view

    def accessor(values, code, kind, component, count):
        data = struct.pack("<" + code * len(values), *values)
        number = len(doc["accessors"])
        doc["accessors"].append({"bufferView": add_view(data), "componentType": component,
                                 "count": count, "type": kind})
        return number

    position = accessor([0, 0, 0, 1, 0, 0, 0, 1, 0], "f", "VEC3", 5126, 3)
    uv = accessor([0, 0, 1, 0, 0, 1], "f", "VEC2", 5126, 3)
    indices = accessor([0, 1, 3 if bad_index else 2], "H", "SCALAR", 5123, 3)
    attributes = {"POSITION": position, "TEXCOORD_0": uv}
    doc["meshes"] = [{"primitives": [{"attributes": attributes, "indices": indices, "material": 0}]}]
    doc["images"] = [{"bufferView": add_view(rgba_png()), "mimeType": "image/png"}]
    doc["textures"] = [{"source": 0}]
    doc["materials"] = [{"alphaMode": "BLEND", "pbrMetallicRoughness": {
        "baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": .8}}]
    if skinned:
        attributes["JOINTS_0"] = accessor([0] * 12, "B", "VEC4", 5121, 3)
        attributes["WEIGHTS_0"] = accessor([1, 0, 0, 0] * 3, "f", "VEC4", 5126, 3)
        inverse = accessor([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -1, 1],
                           "f", "MAT4", 5126, 1)
        doc["skins"] = [{"joints": [1], "inverseBindMatrices": inverse}]
        doc["nodes"] = [{"mesh": 0, "skin": 0, "translation": [100, 0, 0]},
                        {"name": "RootJoint", "translation": [2, 3, 4]}]
        doc["scenes"][0]["nodes"] = [0, 1]
    if animation:
        active_time = accessor([0, 1], "f", "SCALAR", 5126, 2)
        active_value = accessor([2, 3, 4, 3, 3, 4], "f", "VEC3", 5126, 2)
        unused_time = accessor([0, 100], "f", "SCALAR", 5126, 2)
        unused_value = accessor([0] * 6, "f", "VEC3", 5126, 2)
        doc["animations"] = [{"name": "OneSecondMove", "samplers": [
            {"input": active_time, "output": active_value},
            {"input": unused_time, "output": unused_value}],
            "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}]}]
    doc["buffers"][0]["byteLength"] = len(binary)
    encoded = json.dumps(doc, separators=(",", ":"), allow_nan=False).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary))
                     + struct.pack("<I4s", len(encoded), b"JSON") + encoded
                     + struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    return path


def snapshot(path):
    return path.stat().st_mtime_ns, path.read_bytes()


class CharacterCandidatePortableTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="living-town-intake-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def inspect(self, source, **kwargs):
        before = snapshot(source)
        facts = intake.inspect_candidate(source, "test_character", **kwargs)
        self.assertEqual(snapshot(source), before)
        self.assertEqual(facts["source"]["sha256"], hashlib.sha256(before[1]).hexdigest())
        self.assertIs(facts["source"]["bytes_size_mtime_hash_unchanged"], True)
        self.assertTrue(all(value is False for value in facts["qualification"].values()))
        return facts

    def cli(self, source, report):
        command = [sys.executable, "-B", "-m", "tools.asset_refinement.inspect_character_candidate",
                   str(source), "--appearance-family", "test_character",
                   "--source-origin", "provider_original", "--report", str(report)]
        return subprocess.run(command, cwd=Path(intake.__file__).resolve().parents[2],
                              capture_output=True, text=True, timeout=20)

    def test_static_geometry_and_transformed_bounds_are_measured(self):
        facts = self.inspect(make_source(self.folder / "static.glb"), source_origin="provider_original")
        self.assertEqual(facts["status"], "FACTS_ONLY", facts["refusals"])
        geometry = facts["geometry"]
        self.assertEqual((geometry["vertex_count"], geometry["triangle_count"]), (3, 1))
        self.assertEqual(geometry["degenerate_triangle_count"], 0)
        self.assertEqual(geometry["active_triangle_count"], 1)
        bounds = facts["active_scene_rest_bounds"]
        self.assertEqual(bounds["minimum"], [2, 3, 4])
        self.assertEqual(bounds["maximum"], [4, 5, 4])
        self.assertIs(bounds["posed_or_animation_bounds_qualified"], False)

    def test_embedded_image_and_material_link_are_measured(self):
        facts = self.inspect(make_source(self.folder / "texture.glb"))
        self.assertEqual(facts["status"], "FACTS_ONLY", facts["refusals"])
        image = facts["images"][0]
        self.assertEqual(image["sha256"], hashlib.sha256(rgba_png()).hexdigest())
        self.assertEqual(image["dimensions"], [2, 1])
        self.assertEqual(image["pixel_facts_status"], "DECODED_RGBA8_STRIPS")
        self.assertEqual((image["alpha"]["full"], image["alpha"]["partial"]), (1, 1))
        material = facts["materials"][0]
        self.assertEqual(material["alpha_mode"], "BLEND")
        self.assertEqual(material["texture_links"][0]["image"], 0)
        self.assertEqual(material["texture_links"][0]["role"], "base_color")

    def test_skin_rest_bounds_use_joint_world_and_inverse_bind(self):
        facts = self.inspect(make_source(self.folder / "skin.glb", skinned=True))
        self.assertEqual(facts["status"], "FACTS_ONLY", facts["refusals"])
        bounds = facts["active_scene_rest_bounds"]
        self.assertEqual(bounds["minimum"], [2, 3, 3])
        self.assertEqual(bounds["maximum"], [3, 4, 3])
        self.assertIs(bounds["instances"][0]["skin_rest_evaluated"], True)
        self.assertEqual(facts["skeletons"][0]["maximum_influences"], 1)

    def test_unused_sampler_does_not_extend_clip_duration(self):
        facts = self.inspect(make_source(self.folder / "animation.glb", animation=True))
        self.assertEqual(facts["status"], "FACTS_ONLY", facts["refusals"])
        animation = facts["animations"][0]
        self.assertEqual(animation["channels"][0]["sample_count"], 2)
        self.assertEqual((animation["start_seconds"], animation["end_seconds"],
                          animation["duration_seconds"]), (0, 1, 1))
        self.assertIs(animation["motion_action_contact_qualified"], False)

    def test_invalid_index_refuses_without_changing_source(self):
        facts = self.inspect(make_source(self.folder / "invalid.glb", bad_index=True))
        self.assertEqual(facts["status"], "REFUSED")
        self.assertTrue(any("index" in value.lower() for value in facts["refusals"]))

    def test_origin_and_provider_remain_unauthenticated_declarations(self):
        facts = self.inspect(make_source(self.folder / "derivative.glb"),
                             source_origin="other_derivative", provider="Local Blender", task_id="tiny-01")
        self.assertEqual(facts["status"], "FACTS_ONLY", facts["refusals"])
        source = facts["source"]
        self.assertEqual((source["source_origin"], source["provider"], source["task_id"]),
                         ("other_derivative", "Local Blender", "tiny-01"))
        self.assertIs(source["origin_is_caller_declaration_not_authenticated"], True)
        refused = intake.inspect_candidate(self.folder / "derivative.glb", "../unsafe")
        self.assertEqual(refused["status"], "REFUSED")

    def test_cli_creates_one_exclusive_report(self):
        source = make_source(self.folder / "original.glb")
        before = snapshot(source)
        report = self.folder / "nested" / "facts.json"
        result = self.cli(source, report)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(report.read_text(encoding="utf-8"))["status"], "FACTS_ONLY")
        report_before = snapshot(report)
        repeated = self.cli(source, report)
        self.assertEqual(repeated.returncode, 2)
        self.assertEqual(snapshot(report), report_before)
        self.assertEqual(snapshot(source), before)

    def test_cli_refuses_report_at_input_path(self):
        source = make_source(self.folder / "protected.glb")
        before = snapshot(source)
        result = self.cli(source, source)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(snapshot(source), before)


if __name__ == "__main__":
    unittest.main()
