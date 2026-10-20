"""The offline adapter must preserve graph wiring and never queue generation."""

import copy
import hashlib
import json
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib

from tools.asset_refinement import workflows as adapter


def png(path, width, height, color_type=6):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload)))
    channels = 4 if color_type == 6 else 3
    image = b"\x89PNG\r\n\x1a\n"
    image += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    image += chunk(b"IDAT", zlib.compress((b"\0" * (1 + width * channels)) * height))
    image += chunk(b"IEND", b"")
    path.write_bytes(image)


class AssetWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="town_offline_workflows_")
        self.base = Path(self.temp.name)
        self.inputs = self.base / "owned inputs"
        self.inputs.mkdir()
        self.mesh = self.inputs / "counter_atlas.glb"
        self.mesh.write_bytes(b"owned test mesh; adapter does not validate geometry")
        for name in adapter.VIEW_ORDER:
            png(self.inputs / f"{name}.png", 1024, 1024)
        self.reference = self.inputs / "front.png"
        self.sheet = self.inputs / "turnaround_sheet.png"
        png(self.sheet, 4096, 1024)
        self.output = self.base / "review"

    def tearDown(self):
        self.temp.cleanup()

    def build(self, **kwargs):
        return adapter.build_variants(self.output, self.mesh, self.reference, self.sheet, **kwargs)

    def load(self, name):
        return json.loads((self.output / name).read_text(encoding="utf-8"))

    def test_pinned_mit_sources_and_licenses_are_exact(self):
        sources = adapter._verify_sources()
        self.assertEqual(len(sources), 4)
        for item in sources:
            pin, digest = adapter.PINNED_FILES[item["path"]]
            self.assertEqual(item["commit"], pin)
            self.assertEqual(item["sha256"], digest)
            self.assertEqual(item["license"], "MIT")
            self.assertIn(pin, item["source_url"])
            if item["path"].endswith("LICENSE"):
                text = (adapter.VENDOR / item["path"]).read_text(encoding="utf-8")
                self.assertIn("MIT License", text)
                self.assertIn("Copyright (c) 2026 PixelArtistry", text)

    def test_owned_input_routes_four_real_views_in_correct_order(self):
        record = self.build()
        graph = self.load("multiview_owned_views.json")
        nodes = adapter._nodes(graph)
        conditioning = nodes[324]
        links = {link[0]: link for link in graph["links"]}
        self.assertEqual([port["name"] for port in conditioning["inputs"]][1:],
                         list(adapter.VIEW_ORDER))
        for index, name in enumerate(adapter.VIEW_ORDER):
            port = conditioning["inputs"][index + 1]
            link = links[port["link"]]
            self.assertEqual(link[1:3], [703 + index, 0])
            self.assertEqual(link[3:5], [324, index + 1])
            self.assertEqual(nodes[703 + index]["type"], "LoadImage")
            self.assertEqual(nodes[703 + index]["widgets_values"][0],
                             f"living_town_refinement/{name}.png")
            self.assertEqual(nodes[703 + index]["mode"], 0)
            self.assertEqual(record["inputs"][f"view_{name}"]["sha256"],
                             adapter.sha256(self.inputs / f"{name}.png"))
        for node_id in (192, 193, 348, 351, 353, 402, 411, 312, 349, 350, 352):
            self.assertEqual(nodes[node_id]["mode"], 2)
        self.assertEqual(record["default_workflow"], "multiview_owned_views.json")
        self.assertFalse(record["execution"]["performed"])

    def test_research_reference_link_and_nested_object_prompts_are_real(self):
        self.build()
        graph = self.load("multiview_qwen_research_BLOCKED.json")
        nodes = adapter._nodes(graph)
        link = next(link for link in graph["links"] if link[0] == 1504)
        self.assertEqual(link, [1504, 703, 0, 411, 9, "IMAGE"])
        self.assertEqual(nodes[411]["inputs"][9]["name"], "images.image_1")
        self.assertEqual(nodes[402]["widgets_values_named"]["prompt"], adapter.FRONT_PROMPT)
        self.assertFalse(nodes[402]["widgets_values_named"]["switch"])
        self.assertFalse(nodes[411]["widgets_values_named"]["switch_1"])
        self.assertEqual(nodes[411]["widgets_values_named"]["prompt"], adapter.SHEET_PROMPT)
        for scope in graph["definitions"]["subgraphs"]:
            for node in scope["nodes"]:
                if node["type"] in ("TextEncodeQwenImage21", "TextGenerate"):
                    expected = adapter.FRONT_PROMPT if node["id"] in (452, 471) else adapter.SHEET_PROMPT
                    self.assertEqual(node["widgets_values"][0], expected)
                    self.assertEqual(node["widgets_values_named"]["prompt"], expected)
                if node["id"] in (474, 584):
                    self.assertFalse(node["widgets_values_named"]["switch"])
                if node["type"] == "TextGenerate" or node["id"] in (473, 577):
                    self.assertEqual(node["mode"], 2)
                if node["type"] == "PrimitiveStringMultiline":
                    self.assertEqual(node["widgets_values"][0], node["widgets_values_named"]["value"])
        text = json.dumps(graph)
        for stale in ("T-pose", "space mechanic", "snout", "your_reference.png", "C:\\\\path"):
            self.assertNotIn(stale, text)

    def test_crop_rectangles_are_equal_bounded_and_both_widget_encodings_agree(self):
        self.build()
        for name in ("multiview_owned_views.json", "multiview_qwen_research_BLOCKED.json"):
            graph = self.load(name)
            nodes = adapter._nodes(graph)
            for index, node_id in enumerate(adapter.CROP_NODES):
                node = nodes[node_id]
                region = {"x": index * 1024, "y": 0, "width": 1024, "height": 1024}
                self.assertEqual(node["widgets_values"][0], region)
                self.assertEqual(node["widgets_values"][1:], [index * 1024, 0, 1024, 1024])
                self.assertEqual(node["widgets_values_named"]["crop_region"], region)
                self.assertLessEqual(region["x"] + region["width"], 4096)
                self.assertLessEqual(region["y"] + region["height"], 1024)
            self.assertEqual(nodes[411]["widgets_values"][7:9], [4096, 1024])

    def test_default_uv_mode_cannot_claim_a_validated_existing_atlas(self):
        record = self.build()
        graph = self.load("ultratex_standard_9b_BLOCKED.json")
        nodes = adapter._nodes(graph)
        self.assertEqual(nodes[14]["widgets_values"][3], "comfy_gpu")
        self.assertFalse(record["uv"]["atlas_validated_by_caller"])
        self.assertFalse(record["uv"]["audit_performed_by_adapter"])
        self.assertEqual(nodes[12]["widgets_values"], [""])
        self.assertEqual(nodes[14]["widgets_values"][5], "background (LoadImage)")
        self.assertEqual(next(link for link in graph["links"] if link[0] == 8),
                         [8, 1, 1, 14, 1, "MASK"])
        self.assertEqual(nodes[3]["mode"], 2)
        self.assertEqual(nodes[4]["mode"], 2)

    def test_caller_acceptance_enables_only_existing_atlas_mode(self):
        record = self.build(atlas_validated=True)
        nodes = adapter._nodes(self.load("ultratex_standard_9b_BLOCKED.json"))
        self.assertEqual(nodes[14]["widgets_values"][3], "keep_existing")
        self.assertTrue(record["uv"]["atlas_validated_by_caller"])
        self.assertFalse(record["execution"]["permitted"])
        self.assertEqual(record["gates"]["ultratex_9b"]["status"], "BLOCKED_NONCOMMERCIAL")

    def test_no_execution_network_or_installer_side_effects(self):
        with patch.object(socket, "create_connection", side_effect=AssertionError("network")), \
                patch.object(subprocess, "Popen", side_effect=AssertionError("execution")):
            record = self.build()
        self.assertEqual({path.name for path in self.output.iterdir()}, {
            "multiview_owned_views.json", "multiview_qwen_research_BLOCKED.json",
            "ultratex_standard_9b_BLOCKED.json", "workflow_manifest.json"
        })
        for flag in ("permitted", "performed", "installs", "downloads_models", "queues_comfyui", "runtime_tested"):
            self.assertFalse(record["execution"][flag])
        self.assertEqual(record["gates"]["qwen_research"]["status"], "BLOCKED_RESEARCH_LICENSE")
        self.assertEqual(record["gates"]["owned_multiview"]["status"], "MANUAL_REVIEW_REQUIRED")

    def test_every_graph_and_source_is_bound_and_integrity_passes(self):
        before = {path: adapter.sha256(adapter.VENDOR / path) for path in adapter.PINNED_FILES}
        record = self.build()
        for name, row in record["workflows"].items():
            self.assertEqual(row["sha256"], adapter.sha256(self.output / name))
            self.assertEqual(row["integrity"]["status"], "PASS")
            self.assertFalse(row["integrity"]["runtime_execution_tested"])
            graph = self.load(name)
            adapter.validate_graph(graph)
            notice = graph["extra"]["living_town_refinement"]["workflow_source_license_notice"]
            self.assertIn("MIT License", notice)
            self.assertIn("Copyright (c) 2026 PixelArtistry", notice)
            self.assertIn("The above copyright notice and this permission notice", notice)
        self.assertEqual(before, {path: adapter.sha256(adapter.VENDOR / path) for path in before})

    def test_integrity_rejects_broken_nested_real_links_and_top_level_stale_links(self):
        self.build()
        graph = self.load("multiview_owned_views.json")
        broken = copy.deepcopy(graph)
        broken["definitions"]["subgraphs"][0]["links"][0]["origin_id"] = 999999
        with self.assertRaisesRegex(ValueError, "Missing origin"):
            adapter.validate_graph(broken)
        broken = copy.deepcopy(graph)
        adapter._nodes(broken)[324]["inputs"][1]["link"] = -1
        with self.assertRaisesRegex(ValueError, "Invalid target"):
            adapter.validate_graph(broken)

    def test_no_overwrite_even_when_output_is_an_empty_folder(self):
        self.output.mkdir()
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual(list(self.output.iterdir()), [])
        self.output.rmdir()
        self.build()
        before = {path.name: adapter.sha256(path) for path in self.output.iterdir()}
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual(before, {path.name: adapter.sha256(path) for path in self.output.iterdir()})

    def test_missing_view_and_bad_sheet_fail_before_output_creation(self):
        (self.inputs / "left.png").unlink()
        with self.assertRaises(FileNotFoundError):
            self.build()
        self.assertFalse(self.output.exists())
        png(self.inputs / "left.png", 1024, 1024)
        png(self.sheet, 4096, 1088)
        with self.assertRaisesRegex(ValueError, "Expected"):
            self.build()
        self.assertFalse(self.output.exists())

    def test_owned_view_without_alpha_and_non_boolean_atlas_fail(self):
        png(self.inputs / "right.png", 1024, 1024, color_type=2)
        with self.assertRaisesRegex(ValueError, "RGBA"):
            self.build()
        with self.assertRaisesRegex(ValueError, "boolean"):
            self.build(atlas_validated="yes")

    def test_tampered_source_and_provenance_are_rejected(self):
        fake = self.base / "fake_vendor"
        fake.mkdir()
        provenance = json.loads((adapter.VENDOR / "provenance.json").read_text(encoding="utf-8"))
        for item in provenance["files"]:
            path = fake / item["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((adapter.VENDOR / item["path"]).read_bytes())
        (fake / "provenance.json").write_text(json.dumps(provenance), encoding="utf-8")
        (fake / adapter.ULTRA_SOURCE).write_text("{}", encoding="utf-8")
        with patch.object(adapter, "VENDOR", fake), self.assertRaisesRegex(ValueError, "Pinned source changed"):
            self.build()
        self.assertFalse(self.output.exists())

    def test_cli_uses_the_same_nonexecuting_builder(self):
        with patch("builtins.print") as printed:
            result = adapter.main([
                "--output", str(self.output), "--mesh", str(self.mesh),
                "--reference", str(self.reference), "--sheet", str(self.sheet)
            ])
        self.assertEqual(result, 0)
        self.assertIn('"execution_performed": false', printed.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
