"""Tiny file-contract fixtures only: no Blender/Godot or full asset assembly."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.town_upgrade import derive_entry_candidate as d


class EntryDerivationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="entry derivation ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.base = self.root / "native14"
        self.pilot = self.root / "actual pilot fixture"
        self.output = self.root / "derivative15"
        self.base.mkdir(); self.pilot.mkdir()
        def save(path, value):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        self.save = save
        (self.base / "refined_whole_town.blend").write_bytes(b"tiny native14 fixture")
        self.base_sha = d.sha(self.base / "refined_whole_town.blend")
        self.rows = {"buildings": [{"id": "one", "group": "urban"}]}
        self.save(self.base / "whole_town_buildings.json", self.rows)
        self.save(self.base / "whole_town_interiors.json", {"schema": "source-metadata-retained", "buildings": [{"id": "one", "levels": []}]})
        self.save(self.base / "source_furniture_geometry.json", {"objects": {str(i): {"fingerprint": "original"} for i in range(6739)}})
        self.save(self.base / "botanical_report.json", {"placements": [], "status": "BUILT_REQUIRES_REVIEW"})
        (self.base / "terrain_materials").mkdir()
        (self.base / "terrain_materials/map.png").write_bytes(b"unaltered source PBR fixture")
        (self.base / "chunks").mkdir()
        (self.base / "chunks/old.glb").write_bytes(b"historical export, not derivative geometry")
        self.save(self.base / "portable_export_receipt.json", {"status": "OLD_EXPORT_SCOPE_ONLY"})
        self.recipes = {}
        for i in range(14):
            relative = "tools/town_upgrade/building_native_audit.py" if i == 0 else f"tools/town_upgrade/base_{i:02d}.py"
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"# Original frozen source {i}\n", encoding="utf-8")
            self.recipes[relative] = {"sha256": d.sha(path)}
        self.sources = {"tools/town_upgrade/building_native_audit.py": self.recipes["tools/town_upgrade/building_native_audit.py"]["sha256"]}
        self.records = {name: d.sha(self.base / name) for name in ("whole_town_buildings.json", "source_furniture_geometry.json")}
        factory = self.repo / d.ENTRY
        factory.write_text(f"NATIVE_SHA256 = {self.base_sha!r}\nRECORD_HASHES = {self.records!r}\nSOURCE_HASHES = {self.sources!r}\n", encoding="utf-8")
        (self.repo / d.ASSEMBLER).write_bytes(Path(d.__file__).read_bytes())
        self.audit = {"schema": "living_town.whole_town_native_geometry.v1", "status": "PASS", "source_furniture_geometry_status": "PASS",
                      "tool_sha256": self.sources["tools/town_upgrade/building_native_audit.py"], "loaded_native_path": str(self.base / "refined_whole_town.blend"),
                      "counts": {"buildings": 151, "floors": 263}, "failures": [], "all_visual_acceptance": False}
        original_audit = {**self.audit, "saved_native_sha256": self.base_sha, "building_records_sha256": self.records["whole_town_buildings.json"]}
        self.save(self.base / "whole_town_native_geometry.json", original_audit)
        self.manifest = {"schema": "living_town.whole_town_upgrade.v1", "status": "BUILT_REQUIRES_VISUAL_AND_GAMEPLAY_REVIEW",
                         "native": {"path": "refined_whole_town.blend", "sha256": self.base_sha, "bytes": 21}, "source_blend_sha256": self.base_sha,
                         "native_geometry_status": "PASS", "native_geometry_receipt_sha256": d.sha(self.base / "whole_town_native_geometry.json"),
                         "input": {"path": "historical-v6.blend", "sha256": "historical"}, "buildings": self.rows["buildings"],
                         "interiors": {"buildings": [{"id": "one", "levels": []}]}, "recipe_bindings": copy.deepcopy(self.recipes),
                         "assets": [{"id": "old", "path": "chunks/old.glb", "sha256": d.sha(self.base / "chunks/old.glb")}],
                         "export_recipe": {"historical": True}, "counts": {"building_count": 151}, "botanical_report": "botanical_report.json"}
        self.save(self.base / "upgrade_manifest.json", self.manifest)
        self.base_manifest_sha = d.sha(self.base / "upgrade_manifest.json")
        (self.pilot / "refined_whole_town.blend").write_bytes(b"tiny actual native15 fixture")
        preserve = {"original_target_fingerprints_unchanged": False, "protected_interior_furniture_count": 6739,
                    "verified_source_component_count": 195, "changed_component_count": 195}
        for key in ("untargeted_mixed_geometry_uv", "all_non_target_meshes", "all_materials", "all_non_target_object_transforms_and_ids", "original_protected_interior_baseline"):
            preserve[key] = "PASS"
        def h(value): return hashlib.sha256(value.encode()).hexdigest()
        self.changes = {"schema": "living_town.source_bound_entry_details.v1", "status": "APPLIED_SCOPED_GEOMETRY_VERIFIED_REQUIRES_ART_AND_RUNTIME_REVIEW",
                        "source_native": {"path": str(self.base / "refined_whole_town.blend"), "sha256": self.base_sha}, "record_bindings": self.records,
                        "tool_sha256": d.sha(factory), "source_bindings": {key: {"sha256": value} for key, value in self.sources.items()},
                        "preservation_contract": preserve, "whole_town_concept_acceptance": False, "text": {"object": "Reserve_Bathhouse_SignText"},
                        "components": [{"source_object": "Civic_Square_and_Summer_Life_Oak", "original_geometry_uv_sha256": h(f"old{i}"),
                                        "new_geometry_uv_sha256": h(f"new{i}"), "new_expected_world_points_sha256": h(f"points{i}")} for i in range(195)]}
        self.save(self.pilot / "entry_detail_changes.json", self.changes)
        self.save(self.pilot / "whole_town_native_geometry_audit.json", self.audit)
        self.derivation = {"schema": "living_town.entry_native_derivation.v1", "status": "NATIVE_CANDIDATE_SAVED_REQUIRES_ART_AND_RUNTIME_REVIEW",
                           "source": copy.deepcopy(self.changes["source_native"]),
                           "candidate": {"path": str(self.pilot / "refined_whole_town.blend"), "sha256": d.sha(self.pilot / "refined_whole_town.blend")},
                           "entry_receipt_sha256": d.sha(self.pilot / "entry_detail_changes.json"), "native_audit_sha256": d.sha(self.pilot / "whole_town_native_geometry_audit.json"),
                           "native_geometry_audit": "PASS", "protected_interior_furniture": "PASS", "rendered_review": False, "runtime_review": False, "portable_export": False}
        self.save(self.pilot / "entry_native_derivation.json", self.derivation)

    def derive(self):
        return d.derive(self.base / "upgrade_manifest.json", self.pilot, self.output, self.repo,
                        expected_base_manifest_sha256=self.base_manifest_sha)

    def refresh_pilot(self):
        self.save(self.pilot / "entry_detail_changes.json", self.changes)
        self.save(self.pilot / "whole_town_native_geometry_audit.json", self.audit)
        self.derivation["entry_receipt_sha256"] = d.sha(self.pilot / "entry_detail_changes.json")
        self.derivation["native_audit_sha256"] = d.sha(self.pilot / "whole_town_native_geometry_audit.json")
        self.save(self.pilot / "entry_native_derivation.json", self.derivation)

    def test_fixture_assembly_preserves_inputs_and_original_recipes_and_clears_only_new_copy_exports(self):
        before_base, before_pilot = d.snapshot(self.base), d.snapshot(self.pilot)
        result = self.derive()
        self.assertEqual(result["status"], "PREFLIGHT_PASS_REQUIRES_PORTABLE_ART_AND_RUNTIME_REVIEW")
        self.assertEqual(d.snapshot(self.base), before_base)
        self.assertEqual(d.snapshot(self.pilot), before_pilot)
        final = d.read(self.output / "upgrade_manifest.json")
        self.assertEqual({k: final["recipe_bindings"][k] for k in self.recipes}, self.recipes)
        self.assertFalse(final["assets"])
        self.assertNotIn("export_recipe", final)
        self.assertFalse((self.output / "chunks").exists())
        self.assertFalse((self.output / "portable_export_receipt.json").exists())
        self.assertEqual(d.sha(self.base / "botanical_report.json"), d.sha(self.output / "botanical_report.json"))
        self.assertEqual(d.sha(self.base / "terrain_materials/map.png"), d.sha(self.output / "terrain_materials/map.png"))
        audit = d.read(self.output / "whole_town_native_geometry.json")
        self.assertEqual(audit["saved_native_sha256"], final["source_blend_sha256"])
        self.assertEqual(audit["loaded_native_path"], str(self.base / "refined_whole_town.blend"))
        self.assertFalse(audit["all_visual_acceptance"])
        self.assertEqual(final["native_derivation"]["changed_exterior_components"], 195)
        self.assertEqual(final["native_derivation"]["protected_original_interior_objects"], 6739)
        self.assertFalse(final["native_derivation"]["original_target_fingerprints_unchanged"])
        self.assertEqual(final["native_derivation"]["runtime_review"], "PENDING")
        self.assertFalse(final["native_derivation"]["whole_town_concept_acceptance"])

    def test_manifest_pin_and_original_recipe_drift_reject_before_output(self):
        with self.assertRaisesRegex(ValueError, "manifest changed"):
            d.derive(self.base / "upgrade_manifest.json", self.pilot, self.output, self.repo)
        first = self.repo / next(iter(self.recipes))
        first.write_text("changed historical recipe", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Source recipe changed"):
            self.derive()
        self.assertFalse(self.output.exists())

    def test_pilot_hash_and_partial_audit_failures_are_rejected(self):
        (self.pilot / "refined_whole_town.blend").write_bytes(b"changed native")
        with self.assertRaisesRegex(ValueError, "candidate changed"):
            self.derive()
        self.assertFalse(self.output.exists())

    def test_previous_183_change_pilot_does_not_approve_all_195_grounded_components(self):
        self.changes["preservation_contract"]["changed_component_count"] = 183
        self.changes["components"] = self.changes["components"][:183]
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "exterior component budget"):
            self.derive()
        self.assertFalse(self.output.exists())
        self.changes["preservation_contract"]["changed_component_count"] = 195
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "exterior component budget"):
            self.derive()
        self.assertFalse(self.output.exists())

    def test_false_unchanged_target_claim_and_missing_component_fingerprint_reject(self):
        self.changes["preservation_contract"]["original_target_fingerprints_unchanged"] = True
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "misrepresented"):
            self.derive()
        self.changes["preservation_contract"]["original_target_fingerprints_unchanged"] = False
        self.changes["components"][0]["new_geometry_uv_sha256"] = "invalid"
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "fingerprint"):
            self.derive()

    def test_protected_interior_baseline_cannot_be_rewritten_or_reduced(self):
        self.changes["preservation_contract"]["original_protected_interior_baseline"] = "RELAXED"
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "preservation failed"):
            self.derive()
        self.assertFalse(self.output.exists())

    def test_audit_tool_source_and_inventory_must_match_actual_derivative(self):
        self.audit["tool_sha256"] = "0" * 64
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "audit source changed"):
            self.derive()
        self.audit["tool_sha256"] = self.sources["tools/town_upgrade/building_native_audit.py"]
        self.audit["counts"]["buildings"] = 150
        self.refresh_pilot()
        with self.assertRaisesRegex(ValueError, "architectural inventory"):
            self.derive()

    def test_native_path_escape_and_existing_output_are_rejected_without_mutation(self):
        self.derivation["candidate"]["path"] = str(self.base / "refined_whole_town.blend")
        self.save(self.pilot / "entry_native_derivation.json", self.derivation)
        with self.assertRaisesRegex(ValueError, "outside the actual pilot"):
            self.derive()
        self.output.mkdir()
        (self.output / "keep.txt").write_text("do not overwrite")
        with self.assertRaisesRegex(ValueError, "new derivative output"):
            self.derive()
        self.assertEqual((self.output / "keep.txt").read_text(), "do not overwrite")

    def test_source_change_during_copy_leaves_rejected_label_and_preflight_refuses(self):
        original = d.checked_copy
        def drifting_copy(source, destination, expected):
            result = original(source, destination, expected)
            if source.name == "botanical_report.json":
                (self.base / "new-unbound-at-start.txt").write_text("drift")
            return result
        with mock.patch.object(d, "checked_copy", side_effect=drifting_copy):
            with self.assertRaisesRegex(ValueError, "input folder changed"):
                self.derive()
        self.assertEqual(d.read(self.output / "entry_candidate_REJECTED.json")["status"], "REJECTED_NOT_FOR_EXPORT")
        self.assertEqual(d.read(self.output / "upgrade_manifest.json")["native_geometry_status"], "REJECTED_ASSEMBLY")
        with self.assertRaisesRegex(ValueError, "Rejected derivative"):
            d.preflight(self.output, self.repo)

    def test_source_change_during_validation_cannot_reset_the_initial_snapshot(self):
        original = d.factory_contract
        def drifting_contract(repo):
            result = original(repo)
            (self.base / "chunks/old.glb").write_bytes(b"changed after initial complete snapshot")
            return result
        with mock.patch.object(d, "factory_contract", side_effect=drifting_contract):
            with self.assertRaisesRegex(ValueError, "input folder changed"):
                self.derive()
        self.assertEqual(d.read(self.output / "entry_candidate_REJECTED.json")["status"], "REJECTED_NOT_FOR_EXPORT")

    def test_preflight_rechecks_actual_native_metadata_and_archived_source_bytes(self):
        self.derive()
        path = self.output / "provenance/base_generation/sources" / next(iter(self.recipes))
        path.write_text("not the archived source")
        with self.assertRaisesRegex(ValueError, "snapshot changed"):
            d.preflight(self.output, self.repo)

    def test_preflight_rehashes_retained_material_maps_and_botanical_metadata(self):
        self.derive()
        for relative in ("terrain_materials/map.png", "botanical_report.json", "whole_town_interiors.json"):
            with self.subTest(member=relative):
                path = self.output / relative
                original = path.read_bytes()
                path.write_bytes(original + b" ")
                with self.assertRaisesRegex(ValueError, "Retained original source member changed"):
                    d.preflight(self.output, self.repo)
                path.write_bytes(original)
        self.assertEqual(d.preflight(self.output, self.repo)["status"], "PREFLIGHT_PASS_REQUIRES_PORTABLE_ART_AND_RUNTIME_REVIEW")


if __name__ == "__main__":
    unittest.main()
