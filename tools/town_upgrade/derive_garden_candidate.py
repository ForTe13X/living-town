"""Assemble one verified entry native plus an actual garden material pilot.

Only file contracts are checked here. Blender geometry, packed-image bytes and
preservation were measured by the bound pilot; this tool never reruns an engine
or grants art, portable-material or gameplay acceptance.
"""
from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.town_upgrade import derive_entry_candidate as D

ASSEMBLER = "tools/town_upgrade/derive_garden_candidate.py"
SOIL = "tools/town_upgrade/garden_soil_details.py"
FACTORY = "art/living_town/tools/landscape_details.py"
PLAN = "art/living_town/landscape_plan.json"
HISTORY = "provenance/garden_derivation/"
PREPARED = "provenance/garden_prepared/"
SOURCES = "provenance/garden_sources/"
REPLACED = {"upgrade_manifest.json", "whole_town_native_geometry.json", "refined_whole_town.blend"}
PILOT_FILES = {"garden_soil_details.json": "garden_soil_details.json",
               "garden_soil_native_derivation.json": "garden_soil_native_derivation.json",
               "whole_town_native_geometry_audit.json": "garden_soil_native_geometry_audit.json"}
SHARED_MESH_NAMES = ['Granular_Flower_0_BloomCream', 'Granular_Flower_0_Leaf', 'Granular_Flower_13_BloomCream', 'Granular_Flower_13_Leaf',
         'Granular_Flower_1_BloomCream', 'Granular_Flower_1_Leaf', 'Granular_Flower_2_BloomCream', 'Granular_Flower_2_BloomPink',
         'Granular_Flower_2_Leaf', 'Granular_Flower_3_BloomCream', 'Granular_Flower_3_BloomPink', 'Granular_Flower_3_Leaf',
         'Granular_Flower_4_BloomCream', 'Granular_Flower_4_Leaf', 'Granular_Flower_5_BloomCream', 'Granular_Flower_5_BloomPink',
         'Granular_Flower_5_Leaf', 'Granular_Flower_7_BloomCream', 'Granular_Flower_7_BloomPink', 'Granular_Flower_7_Leaf']
SHARED_SOIL_SHA = '7f93baf8f8d9f0284c647c5f192d57b2c331c53c1beaf6dcd46eb078185833e9'
SHARED_ENTRY_SHA = 'b550a160dede21d339ccb195339d13c631202e600b352d2f04d6be9f526b752c'
SHARED_ORIGINAL_SHA = '59680e9c67b184eb607430ad84b26eef780109c6420073156c0740d1193b10eb'

SHARED_PROOF_SHA256 = '82ad6afec5436bf600fdd1c902f3827d65e3d633e208a2a392d2fcf6cc76bdec'
SHARED_PROOF_FOLDER = 'provenance/garden_shared_mesh_roundtrip/'
SHARED_PROOF_HELPER = 'build/town_upgrade/diagnose_flower_mesh_roundtrip.py'

SCHEMA = "living_town.garden_candidate_assembly.v1"
PASS = "PREFLIGHT_PASS_REQUIRES_PORTABLE_MATERIAL_ART_AND_RUNTIME_REVIEW"
need, read, sha, write, member, snapshot, checked_copy = (D.need, D.read, D.sha, D.write, D.member, D.snapshot, D.checked_copy)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def material_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def valid_hash(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def soil_contract(repo):
    names = {"TARGET", "MATERIAL", "SCHEMA", "ASSET", "RECEIPT_SHA256", "SOIL_NATIVE_STATE_SHA256",
             "DIRT_MATERIAL_STATE_SHA256", "FACTORY_SHA256", "PLAN_SHA256", "MAP_FILES",
             "LINEAR_RGB_FACTORS", "SATURATION", "DIRT_CANONICAL_SHA256", "MATERIAL_BASELINE_SHA256", "MATERIAL_EXCLUDED_FIELDS",
             "UNUSED_MATERIAL_PROOF_SHA256", "SAVE_ORPHAN_ENTRY_SHA256", "SAVE_ORPHAN_MATERIALS"}
    result = {}
    for node in ast.parse((repo / SOIL).read_text(encoding="utf-8-sig")).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in names:
                    result[target.id] = ast.literal_eval(node.value)
    need(set(result) == names, "Missing literal garden source contract")
    result["BASELINE_NATIVE_SHA256"] = D.factory_contract(repo)["NATIVE_SHA256"]
    result["ENTRY_TOOL_SHA256"] = sha(repo / D.ENTRY)
    return result


def check_audit(audit, entry_audit, furniture, source_hash):
    need(audit["schema"] == "living_town.whole_town_native_geometry.v1" and
         audit["status"] == audit["source_furniture_geometry_status"] == "PASS" and not audit["failures"],
         "Actual garden native audit did not pass")
    need(audit["tool_sha256"] == source_hash, "Garden audit recipe changed")
    need(audit["counts"] == entry_audit["counts"], "Garden changed architectural audit counts")
    need(audit["all_visual_acceptance"] is False and not audit["scene_mutations"], "Audit claims visual approval or scene mutation")
    need(len(furniture) == 6739, "Original protected furniture baseline count differs")
    rows = audit["source_furniture_geometry_checks"]
    need(len(rows) == len(furniture) and len({r["object"] for r in rows}) == len(furniture),
         "Garden audit omits/duplicates protected interior objects")
    need({r["object"] for r in rows} == set(furniture), "Garden audit furniture object identities differ")
    for row in rows:
        expected = furniture[row["object"]]["geometry_sha256"]
        need(row["pass"] is True and row["expected_geometry_sha256"] == row["actual_geometry_sha256"] == expected,
             "Garden audit changed original furniture fingerprint: " + row["object"])


def check_unused_proof(proof, baseline, contract):
    names = contract['SAVE_ORPHAN_MATERIALS']; full = baseline['canonical_material_state_sha256']
    expected = {n:v for n,v in full.items() if n not in names}; original, entry = proof['original'], proof['entry']
    need(names == ['LT_Hair','LT_Shirt','LT_Skin','LT_Trousers'] and proof['schema'] == 'living_town.garden_unused_material_roundtrip.v1' and
         proof['status'] == 'PASS_EXACT_UNUSED_MATERIAL_SAVE_ROUNDTRIP' and original['sha256'] == contract['BASELINE_NATIVE_SHA256'] and
         entry['sha256'] == contract['SAVE_ORPHAN_ENTRY_SHA256'] and proof['entry_tool_sha256'] == contract['ENTRY_TOOL_SHA256'], 'Unused material proof source identity differs')
    need(proof['missing_materials'] == names and not proof['added_materials'] and not proof['changed_common_canonical_materials'] and
         proof['original_materials_have_zero_users_and_no_owners'] is True and proof['canonical_excluded_fields'] == ['/settings/session_uid'] and
         original['material_count'] == 137 and entry['material_count'] == 133 and original['inventory']['canonical'] == full and entry['inventory']['canonical'] == expected,
         'Unused material proof exact inventory/scope differs')
    need(set(original['selected_material_usage']) == set(entry['selected_material_usage']) == set(names), 'Incomplete orphan usage records')
    for name in names:
        need(original['selected_material_usage'][name] == {'present':True,'users':0,'use_fake_user':False,'asset_marked':False,'mesh_owners':[],'curve_owners':[],'object_owners':[],'canonical_sha256':full[name]} and
             entry['selected_material_usage'][name] == {'present':False}, 'Nonzero users/owners or changed orphan exception: '+name)
    need(not proof['scene_saved'] and not proof['material_modified'] and not proof['art_pass'], 'Usage proof mutation/review claims differ')
    return expected


def check_shared_mesh_roundtrip(proof, expected, actual, entry_receipt_sha, soil_receipt_sha, entry_tool_sha):
    digest = material_digest
    mismatch = sorted(n for n in set(expected)|set(actual) if expected.get(n) != actual.get(n))
    need(set(expected) == set(actual) and mismatch == SHARED_MESH_NAMES, 'Not the exact twenty representative-only differences')
    need(proof['schema'] == 'living_town.flower_shared_mesh_roundtrip.v1' and proof['status'] == 'PASS' and proof['mesh_count'] == 20 and
         proof['original']['sha256'] == SHARED_ORIGINAL_SHA and proof['saved_entry']['sha256'] == SHARED_ENTRY_SHA and proof['saved_soil']['sha256'] == SHARED_SOIL_SHA,
         'Shared mesh proof native/scope identity differs')
    need(proof['entry_receipt_sha256'] == entry_receipt_sha and proof['soil_receipt_sha256'] == soil_receipt_sha and proof['entry_tool_sha256'] == entry_tool_sha,
         'Shared mesh proof source receipt binding differs')
    need(not proof['scene_saved'] and not proof['geometry_modified'] and not proof['art_pass'], 'Shared mesh proof mutation/review claim')
    need(set(proof['comparisons']) == set(SHARED_MESH_NAMES) and all(set(proof[k]['meshes']) == set(SHARED_MESH_NAMES) for k in ('original','saved_entry','saved_soil')),
         'Shared mesh proof exact name set differs')
    total_instances = 0
    for name in SHARED_MESH_NAMES:
        a,b,c = [proof[k]['meshes'][name] for k in ('original','saved_entry','saved_soil')]
        need(a['local_state'] == b['local_state'] == c['local_state'] and
             a['local_state_sha256'] == b['local_state_sha256'] == c['local_state_sha256'] == digest(a['local_state']),
             'Local mesh/UV/topology/material state changed: '+name)
        need(a['local_state']['mesh'] == name and valid_hash(a['local_state']['local_geometry_sha256']) and
             'matrix_world' not in a['local_state'] and 'geometry_sha256' not in a['local_state'], 'Malformed factored local geometry proof')
        scenes = []
        for row in (a,b,c):
            need(row['first_representative'] in row['instances'] and
                 row['first_raw_sha256'] == row['all_raw_representatives'][row['first_representative']] and
                 set(row['instances']) == set(row['all_raw_representatives']), 'Representative proof incomplete')
            scene = {}
            for obj, record in row['instances'].items():
                state = record['state']
                need(digest(state) == record['state_sha256'] and state['object']['name'] == obj and state['object']['data'] == name and
                     state['object']['type'] == 'MESH' and valid_hash(row['all_raw_representatives'][obj]), 'Actual instance state binding differs')
                need([r['name'] for r in record['collections']] == state['object']['collections'], 'Collection instance metadata differs')
                if record['in_scene']:
                    need(any(r['in_current_scene'] is True for r in record['collections']), 'Scene instance lacks proven owning collection')
                    scene[obj] = state
            scenes.append(scene)
        need(bool(scenes[0]) and scenes[0] == scenes[1] == scenes[2], 'Scene instance identity/matrices/state changed: '+name)
        need(set(a['instances'])-set(b['instances']) == {name} and not (set(b['instances'])-set(a['instances'])) and
             set(b['instances']) == set(c['instances']), 'More than the exact unused prototype disappeared')
        prototype = a['instances'][name]
        need(prototype['in_scene'] is False and prototype['users'] == 0 and prototype['collections'] == [] and prototype['state']['object']['collections'] == [] and
             a['first_representative'] == name, 'Removed representative was not a zero-user unlinked prototype')
        need(all(b['instances'][n]['state'] == c['instances'][n]['state'] and b['instances'][n]['in_scene'] == c['instances'][n]['in_scene'] for n in b['instances']),
             'Saved entry-to-soil instance changed')
        need(a['first_raw_sha256'] == expected[name] and b['first_raw_sha256'] == c['first_raw_sha256'] == actual[name], 'Receipt representative hash transition differs')
        comp = proof['comparisons'][name]
        need(comp['pass'] is True and comp['local_meshes_identical'] is True and comp['scene_instances_identical'] is True and comp['all_missing_outside_scene'] is True and
             comp['missing_objects'] == [name] and comp['added_objects'] == [] and comp['scene_instance_count'] == len(scenes[0]) and
             comp['entry_receipt_raw_sha256'] == expected[name] and comp['soil_receipt_raw_sha256'] == actual[name] and
             comp['original_receipt_representatives'] == sorted(n for n,h in a['all_raw_representatives'].items() if h == expected[name]) and
             comp['soil_receipt_representatives'] == sorted(n for n,h in b['all_raw_representatives'].items() if h == actual[name]),
             'Derived shared mesh comparison record differs')
        total_instances += len(scenes[0])
    return {'status':'EXACT_TWENTY_REPRESENTATIVE_ROUNDTRIP_PROOF_CHECKED','mesh_count':20,'scene_instances':total_instances,
            'geometry_recomputed':False,'engine_executed':False,'art_pass':False}


def load_shared_mesh_proof(path, helper):
    need(sha(path) == SHARED_PROOF_SHA256, 'Pinned shared mesh roundtrip proof changed')
    proof = read(path)
    need(sha(helper) == proof['helper_sha256'] and valid_hash(proof['helper_sha256']), 'Shared mesh diagnostic helper source changed')
    return proof


def check_prepared(prepared, folder, contract, soil_hash):
    """Check archived source/map bytes, without regrading or decoding images."""
    need(prepared["schema"] == "living_town.garden_soil_prepared_maps.v1" and
         prepared["status"] == "PREPARED_REQUIRES_ACTUAL_AB_REVIEW" and prepared["tool_sha256"] == soil_hash,
         "Prepared garden source/tool identity differs")
    need(prepared["dimensions"] == [2048, 2048] and prepared["source_images_modified"] is False and prepared["art_pass"] is False,
         "Prepared garden scope differs")
    need(prepared["grade"]["linear_rgb_factors"] == list(contract["LINEAR_RGB_FACTORS"]) and
         prepared["grade"]["saturation"] == contract["SATURATION"] and prepared["grade"]["lut_size"] == 33,
         "Prepared garden grading recipe differs")
    archive = prepared["selected_source_archive"]
    need(archive["source_receipt_verbatim"] is True and archive["selected_asset_only"] == contract["ASSET"] and
         archive["unrelated_receipt_assets_not_copied_or_claimed"] is True, "Selected CC0 archive scope differs")
    # Original absolute paths remain historical text; copied member locations are
    # registered independently, so the final candidate is self-contained.
    origin = Path(prepared["source"]["root"]).resolve()
    receipt_relative = "provenance/source_receipts.json"
    need(sha(member(folder, receipt_relative)) == contract["RECEIPT_SHA256"] == prepared["source"]["receipt_sha256"],
         "Verbatim CC0 source receipt changed")
    receipt = read(member(folder, receipt_relative))
    need(receipt["schema"] == "living_town.terrain_sources.v1" and receipt["license"] == prepared["source"]["license"] == "CC0-1.0" and
         receipt["license_url"] == prepared["source"]["license_url"] == "https://polyhaven.com/license", "CC0 source license differs")
    asset = contract["ASSET"]
    need(receipt["assets"][asset]["asset_url"] == prepared["source"]["asset_url"] == "https://polyhaven.com/a/" + asset,
         "CC0 garden asset identity differs")
    repeat = [v / 1000 for v in receipt["assets"][asset]["dimensions_mm"]]
    need(repeat == prepared["source"]["repeat_metres"] and len(repeat) == 2 and
         all(math.isfinite(v) and 3. <= v <= 3.002 for v in repeat), "Physical soil repeat differs")
    for name, expected in receipt["assets"][asset]["metadata_sha256"].items():
        need(name in {"info", "files"} and sha(member(folder, "provenance/" + asset + "_" + name + ".json")) == expected,
             "Selected CC0 metadata changed")
    need(set(prepared["maps"]) == set(contract["MAP_FILES"]) == {"diff", "nor_gl", "arm"}, "Garden PBR channels incomplete")
    locations, source_maps = {}, {}
    for role, expected in contract["MAP_FILES"].items():
        original_relative = "provenance/" + asset + "/" + role + ".jpg"
        rows = [r for r in receipt["files"] if r["path"] == asset + "/" + role + ".jpg"]
        need(len(rows) == 1 and rows[0]["sha256"] == expected and sha(member(folder, original_relative)) == expected and
             member(folder, original_relative).stat().st_size == rows[0]["bytes"], "Selected original soil map changed: " + role)
        source_maps[role] = {**rows[0], "absolute_path": str(origin / rows[0]["path"])}
        row = prepared["maps"][role]
        historical = Path(row["path"]).resolve()
        need(historical.is_relative_to(origin.parent), "Prepared map escapes selected archive folder")
        relative = historical.relative_to(origin.parent).as_posix()
        path = member(folder, relative)
        need(path.is_file() and sha(path) == row["sha256"] and path.stat().st_size == row["bytes"], "Prepared map changed: " + role)
        if role != "diff":
            need(row["sha256"] == expected, "Original normal/ARM substituted")
        locations[role] = relative
    expected_source = {"root": str(origin), "receipt_sha256": contract["RECEIPT_SHA256"], "asset_id": asset, "repeat_metres": repeat,
                       "license": "CC0-1.0", "license_url": receipt["license_url"], "asset_url": receipt["assets"][asset]["asset_url"], "maps": source_maps}
    need(prepared["source"] == expected_source and archive["path"] == str(origin), "Prepared source metadata differs from verbatim CC0 receipt")
    baseline_path = member(folder, "provenance/garden_original_material_baseline.json")
    need(sha(baseline_path) == contract["MATERIAL_BASELINE_SHA256"] == prepared["material_baseline"]["sha256"], "Original canonical material baseline bytes differ")
    baseline = read(baseline_path); values = baseline["canonical_material_state_sha256"]
    need(baseline["schema"] == "living_town.garden_original_material_baseline.v1" and baseline["status"] == "ACTUAL_ORIGINAL_V14_CANONICAL_MATERIALS_CAPTURED" and
         baseline["native"]["sha256"] == contract["BASELINE_NATIVE_SHA256"] == prepared["material_baseline"]["native_sha256"] and
         baseline["material_count"] == len(values) == 137 and values["LT_Dirt"] == contract["DIRT_CANONICAL_SHA256"] and
         baseline["excluded_root_material_fields"] == prepared["material_baseline"]["excluded_root_material_fields"] == contract["MATERIAL_EXCLUDED_FIELDS"] == ["/settings/session_uid"] and
         values == prepared["material_baseline"]["canonical_material_state_sha256"] and material_digest(values) == baseline["canonical_inventory_sha256"] == prepared["material_baseline"]["canonical_inventory_sha256"],
         "Original137 canonical material baseline identity differs")
    need(not baseline["scene_saved"] and not baseline["material_modified"] and not baseline["art_pass"] and
         baseline["entry_material_recipe_sha256"] == prepared["material_baseline"]["entry_material_recipe_sha256"] == contract['ENTRY_TOOL_SHA256'] and
         baseline["capture_helper_sha256"] == prepared["material_baseline"]["capture_helper_sha256"] == sha(member(folder,"provenance/capture_garden_material_baseline.py")), "Canonical baseline recipe/mutation claims differ")
    usage_row = prepared['unused_material_roundtrip']; usage_path = member(folder,'provenance/garden_unused_material_roundtrip.json')
    need(sha(usage_path) == usage_row['sha256'] == contract['UNUSED_MATERIAL_PROOF_SHA256'], 'Unused material proof bytes differ')
    usage = read(usage_path); check_unused_proof(usage,baseline,contract)
    need(usage_row['original_native_sha256'] == contract['BASELINE_NATIVE_SHA256'] and usage_row['entry_native_sha256'] == contract['SAVE_ORPHAN_ENTRY_SHA256'] and
         usage_row['missing_materials'] == contract['SAVE_ORPHAN_MATERIALS'] and usage_row['helper_sha256'] == usage['helper_sha256'] == sha(member(folder,'provenance/diagnose_garden_orphan_materials.py')), 'Prepared usage proof metadata/helper differs')
    return locations


def check_material(report, derivation, raw_audit, entry, entry_audit, entry_changes, furniture,
                   prepared, prepared_hash, soil_hash, contract, audit_hash, shared_mesh_proof=None):
    need(report["schema"] == contract["SCHEMA"] and
         report["status"] == "MATERIAL_ONLY_APPLIED_REQUIRES_ACTUAL_BLENDER_AND_GODOT_AB" and report["tool_sha256"] == soil_hash,
         "Garden material pilot was not applied with current source")
    chain = report["input_native"]
    need(chain == derivation["input_native"] and chain["kind"] == "VERIFIED_ENTRY_DERIVATIVE" and
         chain["sha256"] == entry["native"]["sha256"], "Garden input is not the exact verified entry native")
    need(chain["entry_derivation_sha256"] == entry["native_derivation"]["entry_native_derivation"]["sha256"] and
         chain["entry_receipt_sha256"] == entry["native_derivation"]["entry_detail_changes"]["sha256"] and
         chain["native_audit_sha256"] == entry["native_derivation"]["raw_pilot_audit"]["sha256"] and
         chain["original_v14"] == entry_changes["source_native"] and chain["entry_art_or_runtime_acceptance_inferred"] is False,
         "Garden entry derivation chain differs")
    need(Path(raw_audit["loaded_native_path"]).resolve() == Path(chain["native"]).resolve(), "Garden raw audit loaded a different native")
    check_audit(raw_audit, entry_audit, furniture, audit_hash)
    need(report["target_object"] == contract["TARGET"] and report["source_mesh"] == contract["TARGET"] and
         report["original_mesh_state_sha256"] == contract["SOIL_NATIVE_STATE_SHA256"] and
         report["original_shared_dirt_material_sha256"] == contract["DIRT_MATERIAL_STATE_SHA256"], "Original soil/material fingerprint differs")
    inventory = entry_changes["preserved_inventory"]
    meshes = {**inventory["all_non_target_mesh_state_sha256"], **inventory["target_mesh_new_state_sha256"]}
    need(len(meshes) == entry_changes["all_mesh_count"] and meshes.pop(contract["TARGET"]) == contract["SOIL_NATIVE_STATE_SHA256"],
         "Entry full mesh preservation inventory incomplete")
    full_materials = prepared['material_baseline']['canonical_material_state_sha256']
    expected_materials = {n:v for n,v in full_materials.items() if n not in contract['SAVE_ORPHAN_MATERIALS']}
    need(chain['sha256'] == contract['SAVE_ORPHAN_ENTRY_SHA256'] and set(inventory['all_material_state_sha256']) == set(full_materials) and
         entry_changes['all_material_count'] == 137, 'No exact saved-entry material lifecycle contract')
    actual_meshes = report['preserved_mesh_state_sha256']; shared_review = None
    if actual_meshes != meshes or shared_mesh_proof is not None:
        need(shared_mesh_proof is not None and derivation['candidate']['sha256'] == SHARED_SOIL_SHA, 'Full non-target mesh preservation differs; exact shared mesh save-roundtrip proof required')
        shared_review = check_shared_mesh_roundtrip(shared_mesh_proof, meshes, actual_meshes,
            entry['native_derivation']['entry_detail_changes']['sha256'], derivation['garden_receipt_sha256'], contract['ENTRY_TOOL_SHA256'])
    need(set(actual_meshes) == set(meshes) and set(report["preserved_material_state_sha256"]) == set(expected_materials) and
         len(report["preserved_material_state_sha256"]) == 133, "Full non-target mesh/material preservation differs")
    session = report["material_session_preservation"]
    need(session["excluded_root_material_fields"] == contract["MATERIAL_EXCLUDED_FIELDS"] == ["/settings/session_uid"] and
         session["material_baseline_sha256"] == contract["MATERIAL_BASELINE_SHA256"] and session["canonicalizer_tool_sha256"] == soil_hash and
         session['source_baseline_material_count'] == 137 and session['live_original_material_count'] == 133 and
         session['permitted_missing_unused_materials'] == contract['SAVE_ORPHAN_MATERIALS'] and session['unused_material_proof_sha256'] == contract['UNUSED_MATERIAL_PROOF_SHA256'] and
         session["canonical_before"] == session["canonical_after_original"] == expected_materials and
         session["raw_before"] == session["raw_after_original"] == report["preserved_material_state_sha256"] and
         session["session_uid_before"] == session["session_uid_after_original"] and set(session["session_uid_before"]) == set(session["raw_before"]) == set(session["canonical_before"]) and
         all(valid_hash(v) for mode in ("raw_before", "canonical_before") for v in session[mode].values()) and
         all(type(v) is int and v > 0 for v in session["session_uid_before"].values()) and
         session["raw_same_process_preservation"] == session["canonical_same_process_preservation"] == "PASS" and
         session["historical_entry_raw_hashes_compared_across_sessions"] is False and session["raw_whole_scene_digest_compared_across_sessions"] is False and
         session["live_original_LT_Dirt_raw_sha256"] == session["raw_before"]["LT_Dirt"] and session["LT_Dirt_canonical_sha256"] == contract["DIRT_CANONICAL_SHA256"],
         "Canonical137 or strict same-process raw material preservation differs")
    need(valid_hash(report["scene_before_sha256"]) and valid_hash(report["scene_after_sha256"]) and
         report["scene_after_sha256"] != report["scene_before_sha256"], "Garden same-process scene hash evidence differs")
    for key in ("geometry_uv_topology_world_transform_preservation", "all_non_target_meshes_and_objects", "all_original_materials_including_shared_LT_Dirt"):
        need(report[key] == "PASS", "Garden preservation failed: " + key)
    need(report["material_slot_change"] == {"from": ["LT_Dirt"], "to": [contract["MATERIAL"]]} and
         report["new_material"] == contract["MATERIAL"] and report["alpha_mode"] == "OPAQUE" and
         valid_hash(report["new_mesh_state_sha256"]) and valid_hash(report["new_material_state_sha256"]) and
         report["new_mesh_state_sha256"] != report["original_mesh_state_sha256"], "Garden slot-only material change differs")
    need(report["maps"] == prepared and report["prepared_receipt"]["sha256"] == prepared_hash, "Actual pilot used different prepared maps")
    islands = report["source_islands"]
    need(report["island_count"] == len(islands) > 0 and all(r["vertices"] == 11 and r["source_triangles"] == 10 and
         0 <= r["maximum_xy_recipe_error_m"] <= .00003 for r in islands), "Garden original island topology evidence differs")
    uv = report["uv_transform"]
    need(uv["uv_bytes_changed"] is False and uv["all_channels_share_uv0_and_transform"] is True and
         uv["source_repeat_metres"] == prepared["source"]["repeat_metres"] and
         0 <= uv["maximum_fit_residual_uv"] <= .00002, "Garden registered UV0 evidence differs")
    for key in ("mapping_scale", "mapping_location", "mapping_rotation"):
        need(len(uv[key]) == 3 and all(math.isfinite(n) for n in uv[key]), "Invalid registered UV transform")
    need(uv["mapping_rotation"] == [0., 0., 0.] and uv["mapping_scale"][2] == 1. and uv["mapping_location"][2] == 0., "UV transform axes differ")
    affine = uv["actual_world_to_uv_affine"]
    need(len(affine) == 2 and all(len(row) == 3 and all(math.isfinite(n) for n in row) for row in affine) and
         abs(affine[0][1]) <= 1e-6 and abs(affine[1][0]) <= 1e-6, "Measured UV affine mapping differs")
    for k in range(2):
        need(abs(uv["measured_uv_repeat_metres"][k] - 3.) <= .00003 and
             abs(affine[k][k] * uv["measured_uv_repeat_metres"][k] - 1.) <= 1e-8 and
             abs(uv["mapping_location"][k] + affine[k][2] * uv["mapping_scale"][k]) <= 1e-8 and
             abs(uv["mapping_scale"][k] * uv["source_repeat_metres"][k] - uv["measured_uv_repeat_metres"][k]) <= 1e-8,
             "UV transform does not preserve physical soil repeat")
    packed = report["packed_material_images"]
    expected = sorted((r["sha256"], r["bytes"], "sRGB" if role == "diff" else "Non-Color") for role, r in prepared["maps"].items())
    need(len(packed) == 3 and len({r["name"] for r in packed}) == 3 and
         sorted((r["sha256"], r["bytes"], r["color_space"]) for r in packed) == expected, "Three packed PBR images do not match actual prepared bytes")
    need(all(report[k] is False for k in ("geometry_reconstruction", "scene_saved", "exported", "art_pass")) and
         report["gameplay_ab"] == "PENDING" and report["portable_transform_verification"] == "PENDING_ACTUAL_GLTF_TEXTURE_TRANSFORM_AND_PBR_IMAGES",
         "Material pilot cannot grant downstream acceptance")
    need(derivation["schema"] == "living_town.garden_soil_native_derivation.v1" and
         derivation["status"] == "MATERIAL_CANDIDATE_SAVED_REQUIRES_ACTUAL_AB_REVIEW" and derivation["tool_sha256"] == soil_hash and
         derivation["native_geometry_audit"] == derivation["protected_interior_furniture"] == "PASS" and
         derivation["packed_soil_image_count"] == 3 and bool(derivation["blender_version"]), "Garden saved-native derivation differs")
    need(not derivation["rendered_review"] and not derivation["godot_review"] and not derivation["portable_export"], "Garden derivation cannot approve art/runtime/export")
    return shared_review


def preflight(folder, repo=ROOT):
    """Verify complete copied file evidence; never reopen/recompute native state."""
    folder, repo = Path(folder).resolve(), Path(repo).resolve()
    need(not (folder / "garden_candidate_REJECTED.json").exists(), "Rejected garden derivative is not exportable")
    final = read(folder / "upgrade_manifest.json")
    lineage = final["material_derivation"]
    need(lineage["schema"] == "living_town.source_bound_material_derivation.v1", "Missing garden material derivation")
    for name, row in lineage["receipts"].items():
        need(sha(member(folder, row["path"])) == row["sha256"], "Garden derivation receipt changed: " + name)
    entry = read(member(folder, lineage["receipts"]["entry_manifest"]["path"]))
    entry_audit = read(member(folder, lineage["receipts"]["entry_audit"]["path"]))
    inventory = read(member(folder, lineage["receipts"]["entry_snapshot"]["path"]))
    assembly = read(member(folder, lineage["receipts"]["assembly"]["path"]))
    need(assembly["schema"] == SCHEMA and inventory["sha256"] == digest(inventory["files"]) == assembly["entry_snapshot_sha256"], "Entry inventory binding differs")
    need(inventory["files"]["upgrade_manifest.json"]["sha256"] == sha(member(folder, HISTORY + "entry_upgrade_manifest.json")) and
         inventory["files"]["whole_town_native_geometry.json"]["sha256"] == sha(member(folder, HISTORY + "entry_whole_town_native_geometry.json")), "Historical entry files differ from input snapshot")
    need(inventory["files"]["refined_whole_town.blend"]["sha256"] == entry["native"]["sha256"], "Historical entry native snapshot differs")
    expected_members = set()
    for relative, row in inventory["files"].items():
        if relative in REPLACED:
            continue
        path = member(folder, relative)
        need(path.is_file() and path.stat().st_size == row["bytes"] and sha(path) == row["sha256"], "Retained entry member changed: " + relative)
        expected_members.add(relative)
    for relative, row in assembly["new_members"].items():
        path = member(folder, relative)
        need(path.is_file() and path.stat().st_size == row["bytes"] and sha(path) == row["sha256"], "Garden assembled member changed: " + relative)
        expected_members.add(relative)
    expected_members |= {"upgrade_manifest.json", "garden_candidate_assembly.json", "garden_candidate_preflight.json"}
    actual_members = set(snapshot(folder)["files"])
    need(not (actual_members - expected_members), "Unexpected unbound garden output members: " + str(sorted(actual_members - expected_members)))
    need(not final["assets"] and not (folder / "chunks").exists() and "export_recipe" not in final, "Garden inherited portable export state")
    need(set(final["recipe_bindings"]) == set(entry["recipe_bindings"]) | {ASSEMBLER, SOIL, FACTORY, PLAN}, "Garden recipe binding set differs")
    for relative, binding in final["recipe_bindings"].items():
        need(sha(member(repo, relative)) == binding["sha256"], "Active garden recipe changed: " + relative)
        need(sha(member(folder, SOURCES + relative)) == binding["sha256"], "Copied garden recipe snapshot changed: " + relative)
    for relative, binding in entry["recipe_bindings"].items():
        need(final["recipe_bindings"].get(relative) == binding, "Entry recipe binding was substituted: " + relative)
    contract = soil_contract(repo)
    need(final["recipe_bindings"][FACTORY]["sha256"] == contract["FACTORY_SHA256"] and
         final["recipe_bindings"][PLAN]["sha256"] == contract["PLAN_SHA256"], "Authored soil source binding differs")
    prepared = read(member(folder, PREPARED + "garden_soil_maps.json"))
    locations = check_prepared(prepared, member(folder, PREPARED), contract, sha(repo / SOIL))
    need(locations == lineage["self_contained_pbr_members"], "Relocated PBR provenance differs")
    changes = read(folder / "garden_soil_details.json")
    derivation = read(folder / "garden_soil_native_derivation.json")
    raw = read(folder / "garden_soil_native_geometry_audit.json")
    receipts = lineage['receipts']; proof = None
    need(('shared_mesh_proof' in receipts) == ('shared_mesh_helper' in receipts), 'Partial shared mesh proof archive')
    if 'shared_mesh_proof' in receipts:
        proof = load_shared_mesh_proof(member(folder, receipts['shared_mesh_proof']['path']), member(folder, receipts['shared_mesh_helper']['path']))
    shared_review = check_material(changes, derivation, raw, entry, entry_audit, read(folder / "entry_detail_changes.json"),
                   read(folder / "source_furniture_geometry.json")["objects"], prepared, sha(member(folder, PREPARED + "garden_soil_maps.json")),
                   sha(repo / SOIL), contract, final["recipe_bindings"]["tools/town_upgrade/building_native_audit.py"]["sha256"], shared_mesh_proof=proof)
    need(lineage.get('shared_mesh_roundtrip') == shared_review, 'Shared mesh proof summary differs')
    need(derivation["garden_receipt_sha256"] == sha(folder / "garden_soil_details.json") and
         derivation["native_audit_sha256"] == sha(folder / "garden_soil_native_geometry_audit.json"), "Garden actual pilot receipt hashes differ")
    native = member(folder, final["native"]["path"])
    audit = read(folder / "whole_town_native_geometry.json")
    need(final["native_geometry_status"] == audit["status"] == "PASS" and final["native"]["path"] == "refined_whole_town.blend" and
         sha(native) == final["native"]["sha256"] == final["source_blend_sha256"] == audit["saved_native_sha256"] == derivation["candidate"]["sha256"] and
         sha(native) != entry["native"]["sha256"] and native.stat().st_size == final["native"]["bytes"], "Garden saved-native identity differs")
    need(sha(folder / "whole_town_native_geometry.json") == final["native_geometry_receipt_sha256"] and
         sha(folder / "whole_town_buildings.json") == audit["building_records_sha256"], "Garden enriched audit binding differs")
    expected_audit = copy.deepcopy(raw)
    expected_audit.update(saved_native_sha256=sha(native), saved_native_path=str(native), building_records_sha256=sha(folder / "whole_town_buildings.json"),
                          raw_pilot_audit_sha256=sha(folder / "garden_soil_native_geometry_audit.json"),
                          garden_soil_native_derivation_sha256=sha(folder / "garden_soil_native_derivation.json"))
    need(audit == expected_audit, "Garden audit was altered beyond actual-save enrichment")
    need(final["buildings"] == entry["buildings"] == read(folder / "whole_town_buildings.json")["buildings"] and
         final["interiors"] == entry["interiors"] and final["native_derivation"] == entry["native_derivation"], "Entry metadata/history was substituted")
    changed_metadata = {"status", "source_blend_sha256", "native", "native_geometry_receipt_sha256", "recipe_bindings"}
    need(set(final) == set(entry) | {"material_derivation"} and
         all(final.get(k) == v for k, v in entry.items() if k not in changed_metadata) and
         final["status"] == "MATERIAL_DERIVED_REQUIRES_VISUAL_AND_GAMEPLAY_REVIEW", "Non-target entry manifest metadata changed")
    need(lineage["input_entry_native_sha256"] == entry["native"]["sha256"] and lineage["target_object"] == contract["TARGET"] and
         lineage["changed_material_slots"] == 1 and lineage["source_preparation_recipe"] == {"path": SOIL, "sha256": sha(repo / SOIL)} and
         lineage['source_baseline_material_count'] == 137 and lineage['loaded_original_material_count'] == 133 and
         lineage['save_orphan_material_exceptions'] == contract['SAVE_ORPHAN_MATERIALS'] and lineage['unused_material_proof_sha256'] == contract['UNUSED_MATERIAL_PROOF_SHA256'] and
         lineage["derivative_blender_version"] == derivation["blender_version"], "Garden root material lineage differs")
    need(lineage["art_review"] == lineage["runtime_review"] == lineage["portable_material_review"] == "PENDING" and
         lineage["whole_town_concept_acceptance"] is False and lineage["geometry_recomputed"] is False and
         lineage["engine_executed"] is False and lineage["protected_original_interior_objects"] == 6739,
         "Garden assembly cannot grant downstream acceptance or claim engine work")
    result = {"status": PASS, "manifest_sha256": sha(folder / "upgrade_manifest.json"), "native_sha256": sha(native),
              "geometry_recomputed": False, "engine_executed": False, "actual_pilot_receipts_checked": True,
              "art_review": "PENDING", "runtime_review": "PENDING", "portable_material_review": "PENDING"}
    if (folder / "garden_candidate_preflight.json").exists():
        need(read(folder / "garden_candidate_preflight.json") == result, "Stored garden preflight result is stale or altered")
    return result


def derive(entry, pilot, prepared, output, repo=ROOT, shared_mesh_proof=None):
    entry, pilot, prepared, output, repo = (Path(p).resolve() for p in (entry, pilot, prepared, output, repo))
    need(not output.exists(), "Use a fresh garden output directory")
    need(all(not output.is_relative_to(p) and not p.is_relative_to(output) for p in (entry, pilot, prepared)), "Garden output overlaps immutable inputs")
    # Capture complete inputs before validation so concurrent drift cannot reset
    # the accepted baseline. No incomplete or exported entry input is accepted.
    snapshots = {"entry": snapshot(entry), "pilot": snapshot(pilot), "prepared": snapshot(prepared)}
    proof_data, proof_inputs = None, {}
    if shared_mesh_proof is not None:
        proof_path = Path(shared_mesh_proof).resolve(strict=True); helper_path = member(repo, SHARED_PROOF_HELPER)
        proof_inputs = {proof_path: sha(proof_path), helper_path: sha(helper_path)}
        proof_data = load_shared_mesh_proof(proof_path, helper_path)
    manifest = read(entry / "upgrade_manifest.json")
    source_paths = set(manifest["recipe_bindings"]) | {ASSEMBLER, SOIL, FACTORY, PLAN}
    source_hashes = {r: sha(member(repo, r)) for r in source_paths}
    D.preflight(entry, repo)
    need(manifest["native"]["path"] == "refined_whole_town.blend" and not any(k.startswith((HISTORY, PREPARED, SOURCES)) for k in snapshots["entry"]["files"]), "Entry layout/reserved garden provenance differs")
    need(not any(k in snapshots["entry"]["files"] for k in (*PILOT_FILES.values(), "garden_candidate_assembly.json", "garden_candidate_REJECTED.json", "garden_candidate_preflight.json")), "Entry contains reserved garden evidence")
    contract = soil_contract(repo)
    need(source_hashes[FACTORY] == contract["FACTORY_SHA256"] and source_hashes[PLAN] == contract["PLAN_SHA256"], "Authored soil source changed")
    for relative, binding in manifest["recipe_bindings"].items():
        need(source_hashes[relative] == binding["sha256"], "Entry recipe changed: " + relative)
    prepared_data = read(prepared / "garden_soil_maps.json")
    locations = check_prepared(prepared_data, prepared, contract, source_hashes[SOIL])
    changes, derivation, raw = (read(pilot / r) for r in PILOT_FILES)
    shared_review = check_material(changes, derivation, raw, manifest, read(entry / "whole_town_native_geometry.json"), read(entry / "entry_detail_changes.json"),
                   read(entry / "source_furniture_geometry.json")["objects"], prepared_data, sha(prepared / "garden_soil_maps.json"), source_hashes[SOIL],
                   contract, source_hashes["tools/town_upgrade/building_native_audit.py"], shared_mesh_proof=proof_data)
    need(derivation["garden_receipt_sha256"] == sha(pilot / "garden_soil_details.json") and
         derivation["native_audit_sha256"] == sha(pilot / "whole_town_native_geometry_audit.json"), "Actual garden pilot receipt hashes differ")
    candidate = Path(derivation["candidate"]["path"]).resolve()
    need(candidate.is_relative_to(pilot) and candidate.is_file() and sha(candidate) == derivation["candidate"]["sha256"] and
         sha(candidate) != manifest["native"]["sha256"], "Actual garden candidate changed or escapes pilot")
    source_native = Path(changes["input_native"]["native"]).resolve()
    need(source_native.is_file() and sha(source_native) == manifest["native"]["sha256"], "Actual garden input native changed")
    source_native_hash = sha(source_native)
    created = False
    try:
        output.mkdir(parents=True, exist_ok=False); created = True
        for relative, row in snapshots["entry"]["files"].items():
            if relative not in REPLACED:
                checked_copy(member(entry, relative), member(output, relative), row["sha256"])
        checked_copy(entry / "upgrade_manifest.json", member(output, HISTORY + "entry_upgrade_manifest.json"), sha(entry / "upgrade_manifest.json"))
        checked_copy(entry / "whole_town_native_geometry.json", member(output, HISTORY + "entry_whole_town_native_geometry.json"), sha(entry / "whole_town_native_geometry.json"))
        write(member(output, HISTORY + "complete_entry_folder_snapshot.json"), snapshots["entry"])
        write(member(output, HISTORY + "complete_pilot_folder_snapshot.json"), snapshots["pilot"])
        write(member(output, HISTORY + "complete_prepared_folder_snapshot.json"), snapshots["prepared"])
        for relative, row in snapshots["prepared"]["files"].items():
            checked_copy(member(prepared, relative), member(output, PREPARED + relative), row["sha256"])
        for relative, expected in source_hashes.items():
            checked_copy(member(repo, relative), member(output, SOURCES + relative), expected)
        for source, target in PILOT_FILES.items():
            checked_copy(pilot / source, output / target, snapshots["pilot"]["files"][source]["sha256"])
        if proof_data is not None:
            checked_copy(proof_path, member(output, SHARED_PROOF_FOLDER+'proof.json'), proof_inputs[proof_path])
            checked_copy(helper_path, member(output, SHARED_PROOF_FOLDER+'diagnose_flower_mesh_roundtrip.py'), proof_inputs[helper_path])
        checked_copy(candidate, output / "refined_whole_town.blend", derivation["candidate"]["sha256"])
        audit = copy.deepcopy(raw)
        audit.update(saved_native_sha256=sha(output / "refined_whole_town.blend"), saved_native_path=str(output / "refined_whole_town.blend"),
                     building_records_sha256=sha(output / "whole_town_buildings.json"), raw_pilot_audit_sha256=sha(output / "garden_soil_native_geometry_audit.json"),
                     garden_soil_native_derivation_sha256=sha(output / "garden_soil_native_derivation.json"))
        write(output / "whole_town_native_geometry.json", audit)
        current = snapshot(output)
        assembly = {"schema": SCHEMA, "status": "ASSEMBLED_REQUIRES_PREFLIGHT_AND_ACTUAL_AB_REVIEW", "entry_snapshot_sha256": snapshots["entry"]["sha256"],
                    "new_members": {k: v for k, v in current["files"].items() if k not in snapshots["entry"]["files"] or k in REPLACED},
                    "replaced_entry_members": sorted(REPLACED), "geometry_recomputed": False, "engine_executed": False,
                    "source_furniture_baseline_rewritten": False, "packed_native_images_measured_by_bound_pilot_only": True}
        write(output / "garden_candidate_assembly.json", assembly)
        def bound(relative): return {"path": relative, "sha256": sha(member(output, relative))}
        final = copy.deepcopy(manifest)
        final.update(status="MATERIAL_DERIVED_REQUIRES_VISUAL_AND_GAMEPLAY_REVIEW", source_blend_sha256=sha(output / "refined_whole_town.blend"),
                     native={"path": "refined_whole_town.blend", "sha256": sha(output / "refined_whole_town.blend"), "bytes": (output / "refined_whole_town.blend").stat().st_size},
                     native_geometry_status="PASS", native_geometry_receipt_sha256=sha(output / "whole_town_native_geometry.json"))
        for relative, expected in source_hashes.items():
            final["recipe_bindings"].setdefault(relative, {"sha256": expected})
        final["material_derivation"] = {"schema": "living_town.source_bound_material_derivation.v1", "input_entry_native_sha256": manifest["native"]["sha256"],
            "receipts": {"entry_manifest": bound(HISTORY + "entry_upgrade_manifest.json"), "entry_audit": bound(HISTORY + "entry_whole_town_native_geometry.json"),
                         "entry_snapshot": bound(HISTORY + "complete_entry_folder_snapshot.json"), "assembly": bound("garden_candidate_assembly.json"),
                         "garden_pilot": bound("garden_soil_details.json"), "garden_native_derivation": bound("garden_soil_native_derivation.json"),
                         "garden_raw_audit": bound("garden_soil_native_geometry_audit.json"), "prepared_maps": bound(PREPARED + "garden_soil_maps.json")},
            "target_object": contract["TARGET"], "changed_material_slots": 1, "geometry_recomputed": False, "engine_executed": False,
            'source_baseline_material_count': 137, 'loaded_original_material_count': 133,
            'save_orphan_material_exceptions': contract['SAVE_ORPHAN_MATERIALS'], 'unused_material_proof_sha256': contract['UNUSED_MATERIAL_PROOF_SHA256'],
            "protected_original_interior_objects": 6739, "self_contained_pbr_members": locations,
            "source_preparation_recipe": {"path": SOIL, "sha256": source_hashes[SOIL]}, "derivative_blender_version": derivation["blender_version"],
            "art_review": "PENDING", "runtime_review": "PENDING", "portable_material_review": "PENDING", "whole_town_concept_acceptance": False}
        if proof_data is not None:
            final['material_derivation']['receipts'].update(shared_mesh_proof=bound(SHARED_PROOF_FOLDER+'proof.json'),
                shared_mesh_helper=bound(SHARED_PROOF_FOLDER+'diagnose_flower_mesh_roundtrip.py'))
            final['material_derivation']['shared_mesh_roundtrip'] = shared_review
        write(output / "upgrade_manifest.json", final)
        result = preflight(output, repo)
        for label, path in (("entry", entry), ("pilot", pilot), ("prepared", prepared)):
            need(snapshot(path) == snapshots[label], "Immutable input folder changed during garden assembly: " + label)
        need(sha(source_native) == source_native_hash, "Actual source native changed during garden assembly")
        for relative, expected in source_hashes.items():
            need(sha(member(repo, relative)) == expected, "Source recipe changed during garden assembly: " + relative)
        for source, expected in proof_inputs.items():
            need(sha(source) == expected, 'Shared mesh proof/helper input changed during assembly')
        write(output / "garden_candidate_preflight.json", result)
        return result
    except BaseException as exc:
        if created:
            if (output / "upgrade_manifest.json").is_file():
                rejected = read(output / "upgrade_manifest.json")
                rejected.update(status="REJECTED_ASSEMBLY_DO_NOT_EXPORT", native_geometry_status="REJECTED_ASSEMBLY", assembly_rejection=str(exc))
                write(output / "upgrade_manifest_REJECTED.json", rejected)
                (output / "upgrade_manifest_REJECTED.json").replace(output / "upgrade_manifest.json")
            write(output / "garden_candidate_REJECTED.json", {"status": "REJECTED_NOT_FOR_EXPORT", "error": str(exc), "engine_executed": False})
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("entry", "pilot", "prepared", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument('--shared-mesh-proof', type=Path, help='Exact measured20-mesh save-roundtrip proof; never an arbitrary hash bypass')
    args = parser.parse_args(argv)
    try:
        print(json.dumps(derive(args.entry, args.pilot, args.prepared, args.output, args.repo, shared_mesh_proof=args.shared_mesh_proof)))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(json.dumps({"status": "REJECTED_NOT_FOR_EXPORT", "error": str(exc), "engine_executed": False}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
