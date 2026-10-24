"""Tiny real-file contracts for garden assembly; no engines or real asset build."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
from unittest import mock

from tools.tests import test_town_entry_derivation as entry_fixtures
from tools.town_upgrade import derive_garden_candidate as G


def h(value):
    return hashlib.sha256(value.encode()).hexdigest()


class GardenDerivationTests(unittest.TestCase):
    def setUp(self):
        fixture = entry_fixtures.EntryDerivationTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.f = fixture
        self.repo, self.entry = fixture.repo, fixture.output
        self.pilot = fixture.root / "actual soil pilot"
        self.prepared = fixture.root / "soil prepared source"
        self.output = fixture.root / "garden candidate"
        self.pilot.mkdir(); self.prepared.mkdir()
        self.save = fixture.save
        self.contract = G.soil_contract(G.ROOT)
        self.contract["SOIL_NATIVE_STATE_SHA256"] = h("actual source soil state")
        self.contract["DIRT_MATERIAL_STATE_SHA256"] = h("actual source LT_Dirt state")
        for path, name in ((G.FACTORY, "FACTORY_SHA256"), (G.PLAN, "PLAN_SHA256")):
            p = self.repo / path; p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("original soil authored source " + name)
            self.contract[name] = G.sha(p)
        source = self.prepared / "provenance"
        (source / self.contract["ASSET"]).mkdir(parents=True)
        maps = {}
        self.contract["MAP_FILES"] = {}
        for role in ("diff", "nor_gl", "arm"):
            p = source / self.contract["ASSET"] / (role + ".jpg")
            p.write_bytes(("original licensed " + role).encode())
            self.contract["MAP_FILES"][role] = G.sha(p)
            maps[role] = {"path": str(p), "sha256": G.sha(p), "bytes": p.stat().st_size, "role": role}
        metadata = {}
        for name in ("info", "files"):
            p = source / (self.contract["ASSET"] + "_" + name + ".json")
            self.save(p, {"actual original metadata": name}); metadata[name] = G.sha(p)
        license_receipt = {"schema": "living_town.terrain_sources.v1", "license": "CC0-1.0", "license_url": "https://polyhaven.com/license",
                           "assets": {self.contract["ASSET"]: {"asset_url": "https://polyhaven.com/a/" + self.contract["ASSET"],
                                                               "dimensions_mm": [3000.9725093841553, 3000.9801387786865], "metadata_sha256": metadata}},
                           "files": [{"path": self.contract["ASSET"] + "/" + role + ".jpg", "sha256": row["sha256"], "bytes": row["bytes"]} for role, row in maps.items()]}
        self.save(source / "source_receipts.json", license_receipt)
        self.contract["RECEIPT_SHA256"] = G.sha(source / "source_receipts.json")
        soil = self.repo / G.SOIL
        soil.write_text("\n".join(k + " = " + repr(v) for k, v in self.contract.items()) + "\n")
        (self.repo / G.ASSEMBLER).write_bytes(Path(G.__file__).read_bytes())
        soil_sha = G.sha(soil)
        diffuse = self.prepared / "garden_soil_dark_earth_diff.png"
        diffuse.write_bytes(b"tiny prepared graded diffuse fixture")
        maps["diff"] = {"path": str(diffuse), "sha256": G.sha(diffuse), "bytes": diffuse.stat().st_size, "role": "sRGB diffuse"}
        self.prep = {"schema": "living_town.garden_soil_prepared_maps.v1", "status": "PREPARED_REQUIRES_ACTUAL_AB_REVIEW", "tool_sha256": soil_sha,
                     "source": {"root": str(source), "receipt_sha256": self.contract["RECEIPT_SHA256"], "asset_id": self.contract["ASSET"],
                                "license": "CC0-1.0", "license_url": "https://polyhaven.com/license", "asset_url": "https://polyhaven.com/a/" + self.contract["ASSET"],
                                "repeat_metres": [v/1000 for v in license_receipt["assets"][self.contract["ASSET"]]["dimensions_mm"]]},
                     "maps": maps, "dimensions": [2048, 2048], "source_images_modified": False, "art_pass": False,
                     "selected_source_archive": {"path": str(source), "source_receipt_verbatim": True, "selected_asset_only": self.contract["ASSET"],
                                                 "unrelated_receipt_assets_not_copied_or_claimed": True},
                     "grade": {"linear_rgb_factors": list(self.contract["LINEAR_RGB_FACTORS"]), "saturation": self.contract["SATURATION"], "lut_size": 33}}
        self.prep["source"]["maps"] = {role: {**next(r for r in license_receipt["files"] if r["path"] == self.contract["ASSET"] + "/" + role + ".jpg"),
                                                     "absolute_path": str(source / self.contract["ASSET"] / (role + ".jpg"))}
                                         for role in ("diff", "nor_gl", "arm")}
        self.save(self.prepared / "garden_soil_maps.json", self.prep)
        furniture = {str(i): {"geometry_sha256": h("original furniture " + str(i))} for i in range(6739)}
        self.save(fixture.base / "source_furniture_geometry.json", {"objects": furniture})
        fixture.records["source_furniture_geometry.json"] = G.sha(fixture.base / "source_furniture_geometry.json")
        factory = self.repo / G.D.ENTRY
        factory.write_text(f"NATIVE_SHA256 = {fixture.base_sha!r}\nRECORD_HASHES = {fixture.records!r}\nSOURCE_HASHES = {fixture.sources!r}\n")
        fixture.changes["tool_sha256"] = G.sha(factory)
        target = self.contract["TARGET"]
        mesh_states = {target: self.contract["SOIL_NATIVE_STATE_SHA256"], "unchanged_tree": h("tree")}
        target_states = {"changed_civic_mesh": h("entry geometry")}
        material_states = {"LT_Dirt": self.contract["DIRT_MATERIAL_STATE_SHA256"], "LT_White": h("white"),
                           **{"Original_"+str(i): h("original material "+str(i)) for i in range(131)},
                           **{n:h(n) for n in self.contract['SAVE_ORPHAN_MATERIALS']}}
        fixture.changes.update(scene_after_sha256=h("entry scene"), all_mesh_count=3, all_material_count=137,
                               preserved_inventory={"all_non_target_mesh_state_sha256": mesh_states, "target_mesh_new_state_sha256": target_states,
                                                    "all_material_state_sha256": material_states})
        fixture.audit.update(all_visual_acceptance=False, scene_mutations=[], source_furniture_geometry_checks=[
            {"object": name, "pass": True, "expected_geometry_sha256": row["geometry_sha256"], "actual_geometry_sha256": row["geometry_sha256"]}
            for name, row in furniture.items()])
        old_audit = {**fixture.audit, "saved_native_sha256": fixture.base_sha, "building_records_sha256": fixture.records["whole_town_buildings.json"]}
        self.save(fixture.base / "whole_town_native_geometry.json", old_audit)
        fixture.manifest["native_geometry_receipt_sha256"] = G.sha(fixture.base / "whole_town_native_geometry.json")
        self.save(fixture.base / "upgrade_manifest.json", fixture.manifest)
        fixture.base_manifest_sha = G.sha(fixture.base / "upgrade_manifest.json")
        fixture.refresh_pilot()
        fixture.derive()
        manifest = G.read(self.entry / "upgrade_manifest.json")
        canonical = {name: h("canonical "+name) for name in material_states}
        canonical["LT_Dirt"] = self.contract["DIRT_CANONICAL_SHA256"]
        capture_helper=source/"capture_garden_material_baseline.py";capture_helper.write_bytes(b"source-bound actual capture helper fixture")
        baseline = {"schema": "living_town.garden_original_material_baseline.v1", "status": "ACTUAL_ORIGINAL_V14_CANONICAL_MATERIALS_CAPTURED",
                    "native": {"path": str(fixture.base/"refined_whole_town.blend"), "sha256": fixture.base_sha},
                    "entry_material_recipe_sha256": G.sha(factory), "capture_helper_sha256": G.sha(capture_helper),
                    "excluded_root_material_fields": ["/settings/session_uid"], "material_count": 137,
                    "canonical_material_state_sha256": canonical, "canonical_inventory_sha256": G.material_digest(canonical),
                    "original_session_raw_material_state_sha256": material_states, "original_session_uid": {name: i+1 for i,name in enumerate(material_states)},
                    "source_soil_mesh_sha256": self.contract["SOIL_NATIVE_STATE_SHA256"], "scene_saved": False, "material_modified": False, "art_pass": False}
        baseline_path = source/"garden_original_material_baseline.json"; self.save(baseline_path, baseline)
        self.contract["MATERIAL_BASELINE_SHA256"] = G.sha(baseline_path)
        self.contract["BASELINE_NATIVE_SHA256"] = fixture.base_sha
        self.contract['ENTRY_TOOL_SHA256'] = G.sha(factory)
        self.contract['SAVE_ORPHAN_ENTRY_SHA256'] = manifest['native']['sha256']
        usage_helper=source/'diagnose_garden_orphan_materials.py';usage_helper.write_bytes(b'actual usage proof helper fixture')
        live_canonical = {n:v for n,v in canonical.items() if n not in self.contract['SAVE_ORPHAN_MATERIALS']}
        usage = {'schema':'living_town.garden_unused_material_roundtrip.v1','status':'PASS_EXACT_UNUSED_MATERIAL_SAVE_ROUNDTRIP',
                 'original':{'sha256':fixture.base_sha,'material_count':137,'inventory':{'canonical':canonical},
                             'selected_material_usage':{n:{'present':True,'users':0,'use_fake_user':False,'asset_marked':False,'mesh_owners':[],'curve_owners':[],'object_owners':[],'canonical_sha256':canonical[n]} for n in self.contract['SAVE_ORPHAN_MATERIALS']}},
                 'entry':{'sha256':manifest['native']['sha256'],'material_count':133,'inventory':{'canonical':live_canonical},'selected_material_usage':{n:{'present':False} for n in self.contract['SAVE_ORPHAN_MATERIALS']}},
                 'missing_materials':self.contract['SAVE_ORPHAN_MATERIALS'],'added_materials':[],'changed_common_canonical_materials':[],
                 'original_materials_have_zero_users_and_no_owners':True,'canonical_excluded_fields':['/settings/session_uid'],
                 'helper_sha256':G.sha(usage_helper),'entry_tool_sha256':G.sha(factory),'scene_saved':False,'material_modified':False,'art_pass':False}
        usage_path=source/'garden_unused_material_roundtrip.json';self.save(usage_path,usage)
        self.contract['UNUSED_MATERIAL_PROOF_SHA256']=G.sha(usage_path)
        soil.write_text("\n".join(k+" = "+repr(v) for k,v in self.contract.items())+"\n")
        soil_sha = G.sha(soil); self.prep["tool_sha256"] = soil_sha
        self.prep["material_baseline"] = {"path": str(baseline_path), "sha256": G.sha(baseline_path), "native_sha256": fixture.base_sha,
                                          "canonical_inventory_sha256": baseline["canonical_inventory_sha256"], "canonical_material_state_sha256": canonical,
                                          "excluded_root_material_fields": ["/settings/session_uid"], "entry_material_recipe_sha256": G.sha(factory),
                                          "capture_helper_sha256": baseline["capture_helper_sha256"]}
        self.prep['unused_material_roundtrip']={'path':str(usage_path),'sha256':G.sha(usage_path),'original_native_sha256':fixture.base_sha,
            'entry_native_sha256':manifest['native']['sha256'],'missing_materials':self.contract['SAVE_ORPHAN_MATERIALS'],'helper_sha256':G.sha(usage_helper)}
        self.save(self.prepared/"garden_soil_maps.json",self.prep)
        live_materials = {name: h("new session raw "+name) for name in live_canonical}
        live_uids = {name:i+1000 for i,name in enumerate(live_canonical)}
        repeat = self.prep["source"]["repeat_metres"]
        chain = {"kind": "VERIFIED_ENTRY_DERIVATIVE", "native": str(self.entry / "refined_whole_town.blend"), "sha256": manifest["native"]["sha256"],
                 "entry_derivation_sha256": G.sha(self.entry / "entry_native_derivation.json"), "entry_receipt_sha256": G.sha(self.entry / "entry_detail_changes.json"),
                 "native_audit_sha256": G.sha(self.entry / "whole_town_native_geometry_audit.json"), "original_v14": fixture.changes["source_native"],
                 "entry_art_or_runtime_acceptance_inferred": False}
        self.report = {"schema": self.contract["SCHEMA"], "status": "MATERIAL_ONLY_APPLIED_REQUIRES_ACTUAL_BLENDER_AND_GODOT_AB", "tool_sha256": soil_sha,
                       "input_native": chain, "target_object": target, "source_mesh": target, "original_mesh_state_sha256": self.contract["SOIL_NATIVE_STATE_SHA256"],
                       "original_shared_dirt_material_sha256": self.contract["DIRT_MATERIAL_STATE_SHA256"], "new_mesh_state_sha256": h("slot changed soil"),
                       "new_material_state_sha256": h("new material"), "new_material": self.contract["MATERIAL"], "alpha_mode": "OPAQUE",
                       "preserved_mesh_state_sha256": {"unchanged_tree": h("tree"), **target_states}, "preserved_material_state_sha256": copy.deepcopy(live_materials),
                       "scene_before_sha256": h("new session scene before"), "scene_after_sha256": h("garden scene"),
                       "material_session_preservation": {"excluded_root_material_fields": ["/settings/session_uid"],
                           "material_baseline_sha256": G.sha(baseline_path), "canonicalizer_tool_sha256": soil_sha,
                           "raw_before": copy.deepcopy(live_materials), "raw_after_original": copy.deepcopy(live_materials),
                           'source_baseline_material_count':137,'live_original_material_count':133,
                           'permitted_missing_unused_materials':self.contract['SAVE_ORPHAN_MATERIALS'],'unused_material_proof_sha256':G.sha(usage_path),
                           "canonical_before": copy.deepcopy(live_canonical), "canonical_after_original": copy.deepcopy(live_canonical),
                           "session_uid_before": copy.deepcopy(live_uids), "session_uid_after_original": copy.deepcopy(live_uids),
                           "raw_same_process_preservation": "PASS", "canonical_same_process_preservation": "PASS",
                           "historical_entry_raw_hashes_compared_across_sessions": False, "raw_whole_scene_digest_compared_across_sessions": False,
                           "live_original_LT_Dirt_raw_sha256": live_materials['LT_Dirt'], "LT_Dirt_canonical_sha256": self.contract["DIRT_CANONICAL_SHA256"]},
                       "geometry_uv_topology_world_transform_preservation": "PASS", "all_non_target_meshes_and_objects": "PASS",
                       "all_original_materials_including_shared_LT_Dirt": "PASS", "material_slot_change": {"from": ["LT_Dirt"], "to": [self.contract["MATERIAL"]]},
                       "maps": self.prep, "prepared_receipt": {"path": str(self.prepared / "garden_soil_maps.json"), "sha256": G.sha(self.prepared / "garden_soil_maps.json")},
                       "island_count": 1, "source_islands": [{"vertices": 11, "source_triangles": 10, "maximum_xy_recipe_error_m": .000001}],
                       "uv_transform": {"uv_bytes_changed": False, "all_channels_share_uv0_and_transform": True, "source_repeat_metres": repeat,
                                        "actual_world_to_uv_affine": [[1/3, 0., 0.], [0., 1/3, 0.]],
                                        "maximum_fit_residual_uv": .000001, "measured_uv_repeat_metres": [3., 3.],
                                        "mapping_scale": [3./repeat[0], 3./repeat[1], 1.], "mapping_location": [0., 0., 0.], "mapping_rotation": [0., 0., 0.]},
                       "packed_material_images": [{"name": role, "sha256": row["sha256"], "bytes": row["bytes"], "color_space": "sRGB" if role == "diff" else "Non-Color"} for role, row in maps.items()],
                       "geometry_reconstruction": False, "scene_saved": False, "exported": False, "art_pass": False, "gameplay_ab": "PENDING",
                       "portable_transform_verification": "PENDING_ACTUAL_GLTF_TEXTURE_TRANSFORM_AND_PBR_IMAGES"}
        self.audit = copy.deepcopy(fixture.audit)
        self.audit["loaded_native_path"] = chain["native"]
        native = self.pilot / "refined_whole_town.blend"; native.write_bytes(b"tiny saved actual garden native fixture")
        self.derivation = {"schema": "living_town.garden_soil_native_derivation.v1", "status": "MATERIAL_CANDIDATE_SAVED_REQUIRES_ACTUAL_AB_REVIEW",
                           "tool_sha256": soil_sha, "input_native": chain, "candidate": {"path": str(native), "sha256": G.sha(native)},
                           "native_geometry_audit": "PASS", "protected_interior_furniture": "PASS", "packed_soil_image_count": 3, "blender_version": "4.5-fixture",
                           "rendered_review": False, "godot_review": False, "portable_export": False}
        self.refresh()

    def refresh(self):
        self.save(self.pilot / "garden_soil_details.json", self.report)
        self.save(self.pilot / "whole_town_native_geometry_audit.json", self.audit)
        self.derivation["garden_receipt_sha256"] = G.sha(self.pilot / "garden_soil_details.json")
        self.derivation["native_audit_sha256"] = G.sha(self.pilot / "whole_town_native_geometry_audit.json")
        self.save(self.pilot / "garden_soil_native_derivation.json", self.derivation)

    def derive(self):
        return G.derive(self.entry, self.pilot, self.prepared, self.output, self.repo)

    def test_complete_copy_is_immutable_self_contained_and_export_contract_compatible(self):
        before = [G.snapshot(p) for p in (self.entry, self.pilot, self.prepared)]
        result = self.derive()
        self.assertEqual(result["status"], G.PASS)
        self.assertEqual(before, [G.snapshot(p) for p in (self.entry, self.pilot, self.prepared)])
        final, original = G.read(self.output / "upgrade_manifest.json"), G.read(self.entry / "upgrade_manifest.json")
        self.assertEqual(final["native_derivation"], original["native_derivation"])
        self.assertEqual(final["interiors"], original["interiors"])
        self.assertEqual({k: final["recipe_bindings"][k] for k in original["recipe_bindings"]}, original["recipe_bindings"])
        self.assertEqual(G.sha(self.output / (G.HISTORY + "entry_upgrade_manifest.json")), G.sha(self.entry / "upgrade_manifest.json"))
        self.assertEqual(G.sha(self.output / "entry_native_derivation.json"), G.sha(self.entry / "entry_native_derivation.json"))
        self.assertFalse(result["geometry_recomputed"])
        self.assertFalse(final["assets"])
        self.assertNotIn("export_recipe", final)
        self.assertFalse((self.output / "chunks").exists())
        self.assertEqual(final["material_derivation"]["art_review"], "PENDING")
        audit = G.read(self.output / "whole_town_native_geometry.json")
        self.assertEqual(G.sha(self.output / final["native"]["path"]), final["source_blend_sha256"])
        self.assertEqual(audit["saved_native_sha256"], final["native"]["sha256"])
        self.assertEqual(G.sha(self.output / "whole_town_native_geometry.json"), final["native_geometry_receipt_sha256"])
        # Original inputs can disappear after assembly: copied archives suffice.
        self.entry.rename(self.entry.with_name("offline entry archive"))
        self.pilot.rename(self.pilot.with_name("offline pilot archive"))
        self.prepared.rename(self.prepared.with_name("offline prepared archive"))
        self.assertEqual(G.preflight(self.output, self.repo)["status"], G.PASS)

    def test_wrong_input_native_chain_and_scene_chain_reject(self):
        self.report["input_native"]["sha256"] = h("other native"); self.refresh()
        with self.assertRaisesRegex(ValueError, "exact verified entry"):
            self.derive()
        self.report["input_native"]["sha256"] = G.sha(self.entry / "refined_whole_town.blend")
        self.report["scene_before_sha256"] = "not-a-hash"; self.refresh()
        with self.assertRaisesRegex(ValueError, "scene hash evidence"):
            self.derive()

    def test_full_preservation_inventory_cannot_drop_or_change_any_mesh(self):
        self.report["preserved_mesh_state_sha256"].pop("changed_civic_mesh"); self.refresh()
        with self.assertRaisesRegex(ValueError, "Full non-target"):
            self.derive()
        self.assertFalse(self.output.exists())

    def test_shared_dirt_and_uv_change_reject(self):
        self.report["preserved_material_state_sha256"]["LT_Dirt"] = h("beach globally altered"); self.refresh()
        with self.assertRaisesRegex(ValueError, "same-process raw material"):
            self.derive()
        self.report["preserved_material_state_sha256"]["LT_Dirt"] = self.report["material_session_preservation"]["raw_before"]["LT_Dirt"]
        self.report["uv_transform"]["uv_bytes_changed"] = True; self.refresh()
        with self.assertRaisesRegex(ValueError, "UV0"):
            self.derive()

    def test_three_packed_images_and_physical_registered_repeat_required(self):
        self.report["packed_material_images"][1]["color_space"] = "sRGB"; self.refresh()
        with self.assertRaisesRegex(ValueError, "Three packed"):
            self.derive()
        self.report["packed_material_images"][1]["color_space"] = "Non-Color"
        self.report["uv_transform"]["mapping_scale"][0] = 1.; self.refresh()
        with self.assertRaisesRegex(ValueError, "physical soil repeat"):
            self.derive()

    def test_original_6739_actual_audit_rows_required_with_unmodified_fingerprints(self):
        removed = self.audit["source_furniture_geometry_checks"].pop(); self.refresh()
        with self.assertRaisesRegex(ValueError, "omits/duplicates"):
            self.derive()
        self.audit["source_furniture_geometry_checks"].append(removed)
        removed["actual_geometry_sha256"] = h("replaced furniture baseline"); self.refresh()
        with self.assertRaisesRegex(ValueError, "furniture fingerprint"):
            self.derive()

    def test_candidate_and_licensed_source_file_tamper_reject_before_copy(self):
        p = self.prepared / "provenance" / self.contract["ASSET"] / "arm.jpg"
        original = p.read_bytes(); p.write_bytes(b"substituted ARM")
        with self.assertRaisesRegex(ValueError, "soil map changed"):
            self.derive()
        p.write_bytes(original)
        (self.pilot / "refined_whole_town.blend").write_bytes(b"substituted native")
        with self.assertRaisesRegex(ValueError, "candidate changed"):
            self.derive()
        self.assertFalse(self.output.exists())

    def test_source_asset_and_verbatim_map_metadata_cannot_be_substituted(self):
        prepared = copy.deepcopy(self.prep)
        prepared["source"]["asset_id"] = "unrelated_asset_claim"
        with self.assertRaisesRegex(ValueError, "source metadata differs"):
            G.check_prepared(prepared, self.prepared, self.contract, G.sha(self.repo / G.SOIL))
        prepared = copy.deepcopy(self.prep)
        prepared["source"]["maps"]["diff"]["source_url"] = "https://example.invalid/unverified"
        with self.assertRaisesRegex(ValueError, "source metadata differs"):
            G.check_prepared(prepared, self.prepared, self.contract, G.sha(self.repo / G.SOIL))

    def test_canonical_inventory_and_raw_same_process_cannot_relax_any_other_material(self):
        session = self.report['material_session_preservation']
        session['canonical_after_original']['Original_27'] = h('changed non-dirt shader'); self.refresh()
        with self.assertRaisesRegex(ValueError, 'Canonical137'):
            self.derive()
        session['canonical_after_original'] = copy.deepcopy(session['canonical_before'])
        session['raw_after_original']['LT_White'] = h('same-process setting changed'); self.refresh()
        with self.assertRaisesRegex(ValueError, 'same-process raw material'):
            self.derive()

    def test_only_explicit_root_uid_exclusion_is_allowed(self):
        self.report['material_session_preservation']['excluded_root_material_fields'].append('/node_tree/nodes/settings/session_uid'); self.refresh()
        with self.assertRaisesRegex(ValueError, 'Canonical137'):
            self.derive()

    def test_a_fifth_material_can_never_be_dropped_under_four_orphan_contract(self):
        self.report['preserved_material_state_sha256'].pop('LT_White');self.refresh()
        with self.assertRaisesRegex(ValueError,'Full non-target'):
            self.derive()

    def test_usage_proof_rejects_nonzero_users_even_with_consistent_file_binding(self):
        baseline=G.read(self.prepared/'provenance/garden_original_material_baseline.json')
        proof=G.read(self.prepared/'provenance/garden_unused_material_roundtrip.json')
        proof['original']['selected_material_usage']['LT_Hair']['users']=1
        with self.assertRaisesRegex(ValueError,'Nonzero users/owners'):
            G.check_unused_proof(proof,baseline,self.contract)

    def test_shared_proof_and_exact_helper_archive_are_bound_in_tiny_file_assembly(self):
        proof=Path('F:/Living Town/2026-10-20_Refined_Town/source_assets/flower_shared_mesh_roundtrip_v15_002.json')
        if not proof.exists():self.skipTest('Actual measured sidecar unavailable')
        helper=self.repo/G.SHARED_PROOF_HELPER;helper.parent.mkdir(parents=True,exist_ok=True);helper.write_bytes((G.ROOT/G.SHARED_PROOF_HELPER).read_bytes())
        summary={'status':'TINY_COPY_BRANCH_ONLY_NO_NATIVE_PROOF_CLAIM','mesh_count':20}
        with mock.patch.object(G,'check_material',return_value=summary):
            result=G.derive(self.entry,self.pilot,self.prepared,self.output,self.repo,shared_mesh_proof=proof)
            self.assertEqual(result['status'],G.PASS)
            final=G.read(self.output/'upgrade_manifest.json');rows=final['material_derivation']['receipts']
            self.assertEqual(G.sha(self.output/rows['shared_mesh_proof']['path']),G.SHARED_PROOF_SHA256)
            self.assertEqual(G.sha(self.output/rows['shared_mesh_helper']['path']),G.sha(helper))
            archived=self.output/rows['shared_mesh_proof']['path'];archived.write_bytes(archived.read_bytes()+b' ')
            with self.assertRaisesRegex(ValueError,'receipt changed'):G.preflight(self.output,self.repo)

    def test_source_recipe_drift_and_art_acceptance_claim_reject(self):
        (self.repo / G.SOIL).write_text((self.repo / G.SOIL).read_text() + "# changed after actual material pilot\n")
        with self.assertRaisesRegex(ValueError, "Prepared garden source/tool"):
            self.derive()

    def test_material_receipt_and_saved_derivation_cannot_approve_downstream_reviews(self):
        self.report["art_pass"] = True; self.refresh()
        with self.assertRaisesRegex(ValueError, "downstream acceptance"):
            self.derive()
        self.report["art_pass"] = False
        self.derivation["godot_review"] = True; self.refresh()
        with self.assertRaisesRegex(ValueError, "cannot approve"):
            self.derive()

    def test_uv_offset_must_match_actual_measured_world_affine(self):
        self.report["uv_transform"]["mapping_location"][0] = .23; self.refresh()
        with self.assertRaisesRegex(ValueError, "physical soil repeat"):
            self.derive()

    def test_preflight_rejects_extra_output_or_unrelated_manifest_metadata_change(self):
        self.derive()
        extra = self.output / "unbound-extra.txt"; extra.write_text("not part of the bounded output")
        with self.assertRaisesRegex(ValueError, "Unexpected unbound"):
            G.preflight(self.output, self.repo)
        extra.unlink()
        final = G.read(self.output / "upgrade_manifest.json"); final["counts"]["building_count"] = 1
        self.save(self.output / "upgrade_manifest.json", final)
        with self.assertRaisesRegex(ValueError, "Non-target entry manifest"):
            G.preflight(self.output, self.repo)

    def test_future_export_inputs_and_overlapping_or_existing_outputs_reject(self):
        (self.entry / "chunks").mkdir()
        with self.assertRaisesRegex(ValueError, "portable export state"):
            self.derive()
        (self.entry / "chunks").rmdir()
        with self.assertRaisesRegex(ValueError, "overlaps"):
            G.derive(self.entry, self.pilot, self.prepared, self.entry / "nested", self.repo)
        self.output.mkdir(); (self.output / "keep.txt").write_bytes(b"untouched")
        with self.assertRaisesRegex(ValueError, "fresh garden"):
            self.derive()
        self.assertEqual((self.output / "keep.txt").read_bytes(), b"untouched")

    def test_preflight_rechecks_retained_entry_metadata_and_every_prepared_source(self):
        self.derive()
        for relative in ("terrain_materials/map.png", "botanical_report.json", "whole_town_interiors.json", "entry_detail_changes.json",
                         G.PREPARED + "provenance/source_receipts.json", G.PREPARED + "garden_soil_dark_earth_diff.png",
                         G.SOURCES + G.SOIL, "garden_soil_native_geometry_audit.json"):
            with self.subTest(relative=relative):
                p = self.output / relative; old = p.read_bytes(); p.write_bytes(old + b" ")
                with self.assertRaises(ValueError): G.preflight(self.output, self.repo)
                p.write_bytes(old)
        self.assertEqual(G.preflight(self.output, self.repo)["status"], G.PASS)

    def test_stored_preflight_summary_cannot_add_a_false_art_approval(self):
        self.derive()
        path = self.output / "garden_candidate_preflight.json"
        result = G.read(path); result["art_review"] = "PASS"; self.save(path, result)
        with self.assertRaisesRegex(ValueError, "stale or altered"):
            G.preflight(self.output, self.repo)

    def test_input_drift_during_copy_marks_final_manifest_rejected(self):
        original = G.checked_copy
        def drift(source, destination, expected):
            original(source, destination, expected)
            if source.name == "botanical_report.json": (self.entry / "unbound-new.txt").write_text("changed during assembly")
        with mock.patch.object(G, "checked_copy", side_effect=drift):
            with self.assertRaisesRegex(ValueError, "Immutable input folder changed"):
                self.derive()
        self.assertEqual(G.read(self.output / "upgrade_manifest.json")["native_geometry_status"], "REJECTED_ASSEMBLY")
        self.assertEqual(G.read(self.output / "garden_candidate_REJECTED.json")["status"], "REJECTED_NOT_FOR_EXPORT")
        with self.assertRaisesRegex(ValueError, "Rejected garden"):
            G.preflight(self.output, self.repo)

    def test_input_drift_during_validation_cannot_reset_initial_snapshot(self):
        original = G.soil_contract
        def drift(repo):
            result = original(repo)
            (self.pilot / "late-unbound.txt").write_text("drift during validation")
            return result
        with mock.patch.object(G, "soil_contract", side_effect=drift):
            with self.assertRaisesRegex(ValueError, "Immutable input folder changed"):
                self.derive()
        self.assertEqual(G.read(self.output / "upgrade_manifest.json")["native_geometry_status"], "REJECTED_ASSEMBLY")


class ActualSharedMeshProofTests(unittest.TestCase):
    def setUp(self):
        self.folder=Path('F:/Living Town/2026-10-20_Refined_Town')
        self.path=self.folder/'source_assets/flower_shared_mesh_roundtrip_v15_002.json'
        if not self.path.exists():self.skipTest('Owner actual shared-mesh proof unavailable')
        self.proof=G.load_shared_mesh_proof(self.path,G.ROOT/G.SHARED_PROOF_HELPER)
        self.old={n:r['entry_receipt_raw_sha256'] for n,r in self.proof['comparisons'].items()}
        self.new={n:r['soil_receipt_raw_sha256'] for n,r in self.proof['comparisons'].items()}

    def check(self,proof=None):
        return G.check_shared_mesh_roundtrip(proof or self.proof,self.old,self.new,self.proof['entry_receipt_sha256'],self.proof['soil_receipt_sha256'],self.proof['entry_tool_sha256'])

    def test_actual_exact20_local_and437_scene_instances_proof_passes(self):
        self.assertEqual(self.check()['scene_instances'],437)

    def test_scene_matrix_change_rejects_even_with_recomputed_state_digest(self):
        proof=copy.deepcopy(self.proof);name=G.SHARED_MESH_NAMES[0];rows=proof['saved_soil']['meshes'][name]['instances'];row=next(v for v in rows.values() if v['in_scene'])
        row['state']['object']['matrix_world'][0][3]+=.1;row['state_sha256']=G.material_digest(row['state'])
        with self.assertRaisesRegex(ValueError,'Scene instance'):self.check(proof)

    def test_local_uv_change_rejects_even_with_recomputed_local_digest(self):
        proof=copy.deepcopy(self.proof);row=proof['saved_soil']['meshes'][G.SHARED_MESH_NAMES[0]];row['local_state']['uv_layers']['MetricUV']=h('changedUV');row['local_state_sha256']=G.material_digest(row['local_state'])
        with self.assertRaisesRegex(ValueError,'Local mesh/UV'):self.check(proof)

    def test_receipt_hash_or_twentyfirst_mismatch_can_never_be_substituted(self):
        proof=copy.deepcopy(self.proof);proof['soil_receipt_sha256']=h('otherreceipt')
        with self.assertRaisesRegex(ValueError,'source receipt binding'):self.check(proof)
        self.old['OtherUntargetedMesh']=h('old');self.new['OtherUntargetedMesh']=h('new')
        with self.assertRaisesRegex(ValueError,'exact twenty'):self.check()

    def test_changed_sidecar_bytes_reject_before_structured_comparison(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'proof.json';path.write_bytes(self.path.read_bytes()+b' ')
            with self.assertRaisesRegex(ValueError,'Pinned shared mesh'):G.load_shared_mesh_proof(path,G.ROOT/G.SHARED_PROOF_HELPER)


if __name__ == "__main__":
    unittest.main()
