"""File-only complete assembly of an actually saved/reopened refined native.

No Blender import, subprocess or art approval. The engine receipt must preexist.
The old ENTRY and all input folders stay immutable; partial output fails closed.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

SCHEMA='living_town.refined_candidate_assembly.v3'
PREFIX='provenance/refined_composition/'
REPLACED={'upgrade_manifest.json','whole_town_native_geometry.json','refined_whole_town.blend'}
CONTROL={'upgrade_manifest.json','refined_candidate_assembly.json','refined_candidate_preflight.json'}
SELF='tools/town_upgrade/derive_refined_candidate.py'
HISTORY={'entry_manifest':PREFIX+'entry_upgrade_manifest.json','entry_audit':PREFIX+'entry_whole_town_native_geometry.json',
         'entry_snapshot':PREFIX+'entry_complete_snapshot.json','composition':PREFIX+'pilot/refined_native_derivation.json',
         'assembly':'refined_candidate_assembly.json'}

def need(condition,message):
    if not condition:raise ValueError(message)
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def write(path,data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_suffix(path.suffix+'.tmp');tmp.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n',encoding='utf-8');tmp.replace(path)
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module);return module
def member(folder,relative):
    relative=Path(relative);need(not relative.is_absolute() and '..' not in relative.parts,'Unsafe relative package path')
    result=Path(folder)/relative;need(result.resolve().is_relative_to(Path(folder).resolve()),'Package path escapes folder');return result
def bound(path,root=None):
    path=Path(path);return {'path':path.relative_to(root).as_posix() if root else str(path.resolve()),'sha256':sha(path),'bytes':path.stat().st_size}
def verify_member(folder,row):
    path=member(folder,row['path']);need(path.is_file() and path.stat().st_size==row['bytes'] and sha(path)==row['sha256'],'Copied member changed: '+row['path'])

def canonical_receipts(folder):
    return {name:bound(member(folder,path),folder) for name,path in HISTORY.items()}

def archived_art_inputs(folder,report):
    """Bind the actual archived stage proofs to their engine-receipt inputs.

    The assembler does not create human approval. It preserves the exact review,
    actual pilot, images and scope arrays already used by the native composer.
    """
    result={'scope':'GROUND_FACADE_SCOPED_APPROVALS_TREE_TECHNICAL_ONLY'}
    for stage in ('ground','facade'):
        proof=report['art_reviews'][stage];copied={}
        def archived(relative,original):
            row=bound(member(folder,relative),folder)
            need(row['sha256']==original['sha256'] and row['bytes']==original['bytes'],'Archived stage art input hash/length differs: '+relative)
            return row
        for key in ('review','pilot'):
            copied[key]=archived(PREFIX+'art/'+stage+'/'+key+'.json',proof[key])
        copied['images']=[archived(PREFIX+'art/'+stage+'/image_'+str(i)+'.png',row) for i,row in enumerate(proof['images'])]
        copied['artifacts']=[archived(PREFIX+'art/'+stage+'/artifact_'+str(i)+Path(row['path']).suffix,row) for i,row in enumerate(proof['artifacts'])]
        result[stage]=copied
    return result

def validate_archived_ground(folder,report,Q):
    proof=report['art_reviews']['ground'];rows={}
    for key in ('review','pilot'):rows[proof[key]['path']]=(proof[key],PREFIX+'art/ground/'+key+'.json')
    for i,row in enumerate(proof['images']):rows[row['path']]=(row,PREFIX+'art/ground/image_'+str(i)+'.png')
    for i,row in enumerate(proof['artifacts']):rows[row['path']]=(row,PREFIX+'art/ground/artifact_'+str(i)+Path(row['path']).suffix)
    def copied(row,parse=True):
        need(row['path'] in rows and rows[row['path']][0]==row,'Ground source missing or identity substituted in copied archive')
        path=member(folder,rows[row['path']][1]);actual=bound(path)
        need(actual['bytes']==row['bytes'] and actual['sha256']==row['sha256'],'Copied ground evidence hash/length differs')
        return read(path) if parse else actual
    return Q.validate_archived(proof,copied)


def canonical_lineage(folder,report,C):
    scope=report['stage_scope_allowlists']
    return {'schema':'living_town.source_bound_refined_derivation.v3','input_entry_native_sha256':C.ENTRY_SHA,
        'receipts':canonical_receipts(folder),'protected_original_interior_objects':6739,
        'changed_objects':{'ground':'Atlantic_Terrain_Grass','removed_old_soil':'Reference_Pocket_Gardens_Dirt',
            'facades':list(C.FACADE_TARGETS),'tree_meshes':scope['tree_meshes'],'tree_materials':scope['tree_materials'],'tree_fields':scope['tree_fields'],
            'leaf_materials':scope['leaf_materials'],'leaf_fields':scope['leaf_fields']},
        'stage_scope_allowlists':copy.deepcopy(scope),'stage_art_review_inputs':archived_art_inputs(folder,report),
        'tree_art_review':'PENDING_ROOT_FINAL_CLOSEUPS_AND_CATALOG','leaf_art_review':C.LEAF_ART_SCOPE,
        'leaf_evidence_archive':bound(member(folder,PREFIX+'leaf_source_archive.json'),folder),
        'ground_material_art_scope':copy.deepcopy(report['art_reviews']['ground']['accepted_scope']),
        'tree004_wrapper_input':copy.deepcopy(report['tree_uv_wrapper_input']),
        'portable_review':'PENDING','runtime_review':'PENDING',
        'whole_town_concept_acceptance':False,'engine_executed_by_assembler':False,'geometry_recomputed_by_assembler':False}

def validate_archived_tree(folder,report,T):
    """File receipt/payload check only; never pretends to re-run Blender."""
    import numpy as np
    root=member(folder,PREFIX+'tree_pilot');receipt=root/'tree_uv_repair_pilot.json'
    need(sha(receipt)==report['tree_uv_input']['sha256'],'Copied actual tree pilot receipt differs')
    pilot=read(receipt);T.payload_contract_v4(pilot)
    wrapper_path=root/'revision004_wrapper.json';wrapper=read(wrapper_path)
    need(sha(wrapper_path)==report['tree_uv_wrapper_input']['sha256']==T.ACTUAL_WRAPPER004_SHA,
         'Copied complete actual tree004 wrapper differs')
    T.wrapper_contract_v4(wrapper,report['tree_uv_input'])
    historical_root=Path(report['tree_uv_input']['path']).parent.resolve()
    for row in wrapper['source_checker_records']:
        original=Path(row['path']).resolve()
        need(original.is_relative_to(historical_root),'Tree checker proof leaves historical actual pilot folder')
        relative=(Path(PREFIX)/'tree_pilot'/original.relative_to(historical_root)).as_posix()
        verify_member(folder,{'path':relative,'bytes':row['bytes'],'sha256':row['sha256']})
    source_pins={Path(row['path']).name:row['sha256'] for row in pilot['source_bindings'].values() if Path(row['path']).name in ('pilot.py','contract.py') and row['sha256'] in (T.SOURCE_PILOT_SHA,T.SOURCE_CONTRACT_SHA)}
    need(source_pins.get('pilot.py')==T.SOURCE_PILOT_SHA and source_pins.get('contract.py')==T.SOURCE_CONTRACT_SHA,'Copied actual UV pilot source identities differ')
    index=read(member(folder,PREFIX+'tree_source_archive.json'))
    libraries=[row for original,row in index['copied'].items() if Path(original).name=='botanical_prototypes.json' and row['sha256']==T.LIBRARY_SHA]
    need(len(libraries)==1,'Copied actual botanical library metadata missing');verify_member(folder,libraries[0])
    entries={row['mesh']:row for row in read(member(folder,libraries[0]['path']))['entries'] if row['asset'] in T.ASSETS}
    arrays={}
    for stage,relative in [('baseline_replay','baseline'),('uv_aware_replay','uv_aware')]:
        arrays[stage]={}
        for name,row in pilot[stage]['prototypes'].items():
            p=root/relative/(name+'.npz')
            need(Path(row['arrays']['path']).name==p.name and sha(p)==row['arrays']['sha256'] and p.stat().st_size==row['arrays']['bytes'],'Copied original/alternate tree NPZ differs')
            with np.load(p,allow_pickle=False) as z:values={k:z[k] for k in z.files}
            T.validate_array_layout(values,entries[name])
            need({k:T.array_state(v) for k,v in values.items()}==row['buffers'],'Copied tree NPZ buffer receipts differ')
            arrays[stage][name]=values
    for name,a in arrays['baseline_replay'].items():
        names=pilot['baseline_replay']['prototypes'][name]['materials'];wood=np.repeat(np.array([names[i] in T.WOOD_MATERIALS for i in a['material_index']]),3)
        T.compare_arrays(a,arrays['uv_aware_replay'][name],wood,True)
    return pilot


def leaf_evidence_rows(payload,review):
    rows=[payload['rna_binding'],payload['gui_binding'],*payload['artifacts'],payload['aliases']['receipt'],
          *payload['aliases']['artifacts'],*payload['aliases']['sources'],review]
    result={}
    for row in rows:
        if row['path'] in result:need(result[row['path']]==row,'Duplicate leaf evidence path has conflicting identity')
        result[row['path']]=row
    return result


def validate_archived_leaf(folder,report,L):
    """Relocated actual proof files, never obsolete absolute-path dereferences."""
    index=read(member(folder,PREFIX+'leaf_source_archive.json'))
    need(index['leaf_input']==report['leaf_input'] and set(index['copied'])==set(index['historical_bindings']),
         'Leaf archived input/source inventory differs')
    historical=index['historical_bindings']
    for original,row in index['copied'].items():
        old=historical[original]
        need(old['path']==original and row['sha256']==old['sha256'] and row['bytes']==old['bytes'],
             'Leaf archived source differs from historical binding')
        verify_member(folder,row)
    def archived(row):
        need(row['path'] in historical and historical[row['path']]==row,'Leaf required source absent from archive')
        return member(folder,index['copied'][row['path']]['path'])
    leaf=report['leaf_input'];need(set(leaf)=={'rna','gui','aliases','portable_check','portable_export','review'},'Exact leaf input binding inventory differs')
    for key,expected in [('rna',L.RNA_SHA),('gui',L.GUI_SHA),('aliases',L.ALIAS_REPORT_SHA),
                         ('portable_check',L.PORTABLE_CHECK_SHA),('portable_export',L.PORTABLE_EXPORT_SHA)]:
        need(sha(archived(leaf[key]))==expected,'Actual archived leaf proof hash differs: '+key)
    gui=read(archived(leaf['gui']));need(gui['status']==L.GUI_STATUS and not gui['failures']
        and gui['all_original_slots_restored'] is True,'Archived actual GUI preservation incomplete')
    for row in [gui['all_leaf_users'],*[entry['file'] for entry in gui['screenshots']]]:archived(row)
    alias=read(archived(leaf['aliases']))
    need(alias['status']=='ACTUAL_TWO_LEAF_ALIAS_MEASUREMENT_AND_RESTORATION_PASS'
         and alias['original_graph_images_bindings_restored'] is True and alias['immutable_bytes_preserved'] is True
         and alias['script']['sha256']==L.ALIAS_SOURCE_SHA,'Archived actual measured aliases incomplete')
    for row in [alias['script'],*alias['sources']]:archived(row)
    documents={name:read(archived(row)) for name,row in alias['artifacts'].items()}
    L.alias_contract(documents['before.json'],documents['after.json'],documents['recursive_diff.json'],alias['authored_owners'])
    portable=read(archived(leaf['portable_check']))
    need(portable['status']=='CORE_GLTF_MASK025_ORIGINAL_RGBA_PASS' and portable['export_report_sha256']==L.PORTABLE_EXPORT_SHA,
         'Archived actual tiny core MASK check incomplete')
    archived(portable['glb'])
    review=read(archived(leaf['review']))
    need(review['report']['sha256']==L.GUI_SHA and review['whole_town_concept_acceptance'] is False,
         'Archived leaf visual scope differs')
    required={row['path'] for row in [*leaf.values(),gui['all_leaf_users'],*[entry['file'] for entry in gui['screenshots']],
        alias['script'],*alias['sources'],*alias['artifacts'].values(),portable['glb']]}
    need(set(historical)==required,'Leaf archive omits/adds an evidence source')
    return {'alias_rows':documents['recursive_diff.json'],'source_index':bound(member(folder,PREFIX+'leaf_source_archive.json'),folder)}

def verify_source_archive(folder,pilot):
    index=read(member(folder,PREFIX+'tree_source_archive.json'))
    need(index['historical_bindings']==pilot['source_bindings'],'Copied tree source lineage metadata differs')
    required={row['path'] for row in pilot['source_bindings'].values() if (Path(row['path']).suffix.lower() in ('.py','.gltf','.json') and Path(row['path']).name!='scene_before_inventory.json')}
    need(set(index['copied'])==required,'Tree provenance omits/substitutes a source/tool/license metadata member')
    for original,row in index['copied'].items():
        old=next(v for v in pilot['source_bindings'].values() if v['path']==original)
        need(row['sha256']==old['sha256'] and row['bytes']==old['bytes'],'Tree archived source differs from historical binding');verify_member(folder,row)
    need(index['raw_geometry_texture_files_duplicated'] is False,'Unexpected source archive scope claim')

def validate_image_observations(report,composition,materials,C):
    artifact=bound(composition/'packed_image_observations.json');expected=report['artifacts']['packed_image_observations.json']
    need(artifact['sha256']==expected['sha256'] and artifact['bytes']==expected['bytes'],'Packed image observation artifact changed')
    image_observations=read(composition/'packed_image_observations.json')
    need(image_observations['helper']==report['sources']['tools/town_upgrade/packed_image_guard.py']
         and image_observations['helper']['sha256']==C.IMAGE_GUARD_SHA
         and image_observations['original_bindings_preserved'] is True
         and image_observations['all_final_bindings_reopened_exact'] is True,'Exact proved recursive image helper/bindings not retained')
    need(materials['packed_image_observations']==report['artifacts']['packed_image_observations.json']
         and materials['packed_image_row_schema']=='LEGACY_KEYS_PLUS_ALPHA_MODE_V1','Packed image observation or explicit row schema differs')
    initial_images=image_observations['initial'];final_images=image_observations['final_before_save'];reopened_images=image_observations['reopened']
    C.verify_shader_bindings(initial_images,final_images,allow_added=True);C.verify_shader_bindings(final_images,reopened_images)
    initial_rows=C.image_rows(initial_images);final_rows=C.image_rows(final_images);reopened_rows=C.image_rows(reopened_images)
    C.verify_images(initial_rows,{k:final_rows[k] for k in initial_rows})
    need(len(set(final_rows)-set(initial_rows))==3 and materials['packed_images_reopened']==reopened_rows,'Packed asset scope/readback differs')
    need(C.verify_images(final_rows,reopened_rows,allow_filepath_remap=True)==materials['packed_image_filepath_remaps'],'Packed image save/reopen remaps differ')
    for snapshot in (initial_images,final_images,reopened_images):
        for row in snapshot['excluded_unbound_builtins']:
            need(row['type'] in ('RENDER_RESULT','COMPOSITING') and not row['shader_bindings']
                 and row['name'] not in snapshot['shader_image_bindings']
                 and row['reason']=='RNA_BUILTIN_TYPE_AND_ACTUAL_ALL_MATERIAL_WORLD_SHADER_UNBOUND','A shader-bound/nonbuiltin image was excluded')
    return {'status':'EXACT_PACKED_ASSETS_SHADER_BINDINGS_AND_TYPED_BUILTIN_EXCLUSIONS_PASS'}


def validate_actual(report,composition,native,entry,entry_audit,furniture,repo,C):
    need(report['schema']==C.SCHEMA and report['status']==C.SUCCESS and report['saved'] is True and report['reopened'] is True and report['complete_source_stability'] is True,'Actual saved/reopened native evidence incomplete')
    need(report['input_native']['sha256']==entry['native']['sha256']==C.ENTRY_SHA and report['candidate']['sha256']==sha(native)==report['actual_reopened_native_sha256'] and native.stat().st_size==report['candidate']['bytes'],'Composed native/input identity differs')
    need(report['candidate']['sha256']!=C.ENTRY_SHA and report['original_furniture_count']==6739 and report['material_original_count']==133 and report['material_final_count']==134,'Native composition inventory differs')
    need(report['whole_town_concept_acceptance'] is False and report['portable_review']==report['runtime_review']=='PENDING' and report['tree_art_review']=='PENDING_ROOT_FINAL_CLOSEUPS_AND_CATALOG','Composition cannot grant downstream/tree art acceptance')
    need(report['ground_preservation']['status']=='EXACT_SCOPED_PRESERVATION_PASS' and report['facade_preservation']=={'status':'EXACT_COMPOSED_DELTA_PASS','changed_facade_objects':list(C.FACADE_TARGETS),'whole_members_removed':11,'other_objects_meshes_materials_exact':True},'Actual scoped preservation failed')
    need(report['changed_terrain_object']=='Atlantic_Terrain_Grass' and report['removed_soil_object']=='Reference_Pocket_Gardens_Dirt' and report['new_material']=='ContinuousSummer_Grass_Pilot','Unauthorized target scope')
    for name,row in report['artifacts'].items():
        need(Path(name).name==name and name not in ('refined_native_derivation.json','refined_whole_town.blend'),'Unsafe/cyclic composition artifact')
        actual=member(composition,name);need(actual.is_file() and sha(actual)==row['sha256'] and actual.stat().st_size==row['bytes'],'Actual composition artifact changed: '+name)
    required={'packed_image_observations.json','ground_specular_changes.json','ground_feather_changes.json','actual_feather_scope.npz','tree_uv_changes.json','tree_material_state_changes.json','ground_changes.json','facade_changes.json','actual_terrain_scope.npz','source_before_inventory.json','derived_post_ground_view.json','derived_post_facade_view.json','composed_final_inventory.json','reopened_inventory.json','source_furniture_before.json','source_furniture_reopened.json','leaf_cutoff_changes.json','leaf_material_state_changes.json','native_geometry_before_save.json','refined_native_geometry_reopened.json','reopened_facade_apertures.json','material_and_image_roundtrip.json'}
    need(set(report['artifacts'])==required,'Missing/extra composition evidence members')
    reopened=read(composition/'refined_native_geometry_reopened.json');before=read(composition/'native_geometry_before_save.json')
    C.check_audit(before,entry_audit,furniture);C.check_audit(reopened,entry_audit,furniture)
    need(Path(reopened['loaded_native_path']).resolve()==Path(report['candidate']['path']).resolve(),'Actual audit did not load saved candidate')
    need(before['tool_sha256']==reopened['tool_sha256']==report['sources']['tools/town_upgrade/building_native_audit.py']['sha256'],'Actual audit recipe identity differs')
    original=read(composition/'source_furniture_before.json');after=read(composition/'source_furniture_reopened.json')
    expected={name:row['geometry_sha256'] for name,row in furniture.items()}
    need(len(expected)==6739 and original==after and original['count']==6739 and original['all_original_6739_match'] is True and original['actual_geometry_sha256']==expected and C.digest(expected)==report['original_furniture_inventory_sha256']==original['inventory_sha256'],'Original furniture baseline evidence differs')
    final=read(composition/'composed_final_inventory.json');saved=read(composition/'reopened_inventory.json')
    need(final['objects']==saved['objects'] and final['meshes']==saved['meshes'],'Saved/reopened object/local mesh equality differs')
    materials=read(composition/'material_and_image_roundtrip.json')
    a,t,b,c=(materials[name] for name in ('raw_before','raw_after_tree','raw_after_composition','raw_reopened'));old=set(a['raw'])
    need(len(old)==133 and set(t['raw'])==set(b['raw'])==set(c['raw'])==old|{report['new_material']}
         and materials['excluded_material_fields']==['/settings/session_uid'],'Complete material inventory/canonical policy differs')
    T=C.load('refined_assembled_tree_contract',Path(C.__file__).with_name('tree_uv_details.py'))
    L=C.load('refined_assembled_leaf_contract',Path(C.__file__).with_name('leaf_cutoff_details.py'))
    leaves=set(L.LEAVES);unchanged=old-T.WOOD_MATERIALS-leaves
    need(len(unchanged)==125 and materials['same_process_non_target125_exact'] is True
         and materials['six_wood_materials_exact15_uv_names_and66_serialized_paths_only'] is True
         and materials['two_leaf_materials_exact4_authored_values_and18_serialized_paths_only'] is True,'Original125/wood/leaf scope proof missing')
    for mode in ('raw','canonical','session_uid'):
        need({k:b[mode][k] for k in unchanged}=={k:a[mode][k] for k in unchanged},'Non-target125 material state changed within process')
    need({k for k in old if a['raw'][k]!=t['raw'][k]}==T.WOOD_MATERIALS,'Before-leaf material changes exceed six wood shaders')
    need({k for k in b['raw'] if t['raw'][k]!=b['raw'][k]}==leaves,'Leaf stage changed another material')
    need({k for k in old if a['raw'][k]!=b['raw'][k]}==T.WOOD_MATERIALS|leaves,'Final original material changes exceed exact eight shaders')
    need(t['session_uid']==b['session_uid'],'Leaf stage replaced a material resource')
    need(b['canonical']==c['canonical'] and materials['all134_canonical_reopened_exact'] is True,'Reopened material appearance differs')
    tree=read(composition/'tree_uv_changes.json')
    need(tree['status']==report['tree_uv_preservation']=='EXACT_REPLAY_UV_ONLY_AND_15_FIELDS_PASS_ART_PENDING'
         and tree['art_review']==report['tree_art_review'] and tree['source_pilot']==report['tree_uv_input']
         and tree['source_wrapper']==report['tree_uv_wrapper_input'],'Tree stage/receipt/art pending scope differs')
    need(tree['material_changes']['status']==T.MATERIAL_V4_STATUS,'Tree exact66-path material proof missing')
    need(set(tree['target_meshes'])=={'BotanicalSource_'+name for name in T.EXPECTED_OWNERS}
         and len(tree['target_meshes'])==10 and len(tree['material_changes']['fields'])==15
         and tree['geometry_leaf_uv_preserved'] is True,'Tree exact mesh/field scope differs')
    need(materials['tree_material_fields']==tree['material_changes']['fields'] and tree['placements']['count']==30176
         and tree['placements']['tree_owners']==6701 and len(tree['packed_images'])==30,'Tree owner/material/image proof incomplete')
    graphs=read(composition/'tree_material_state_changes.json')
    need(graphs['fields']==tree['material_changes']['fields'] and set(graphs['original133_before'])==old
         and set(graphs['all134_before_tree'])==set(graphs['all134_after_tree'])==old|{report['new_material']},'Complete structured tree graph evidence differs')
    T.validate_composed_material_states_v4(graphs['original133_before'],graphs['all134_before_tree'],graphs['all134_after_tree'],graphs['fields'])
    Q=C.load('refined_assembled_ground_finish_contract',Path(C.__file__).with_name('ground_finish_details.py'))
    scalar=read(composition/'ground_specular_changes.json')
    Q.validate_composed(scalar,graphs['all134_before_tree'],graphs['original133_before'])
    need(report['ground_specular_preservation']==Q.DELTA_STATUS and report['ground_art_scope']==Q.SCOPE
         and materials['ground_specular_exact1_authored_value_and35_serialized_paths_only'] is True,'Exact source grassIOR/35path proof missing')
    need({name:T.raw_state_sha256(state) for name,state in graphs['original133_before'].items()}==a['raw']
         and {name:T.raw_state_sha256(state) for name,state in graphs['all134_after_tree'].items()}==t['raw'],
         'Tree structured graphs do not bind actual initial/after-tree raw material hashes')
    leaf=read(composition/'leaf_cutoff_changes.json');leaf_graphs=read(composition/'leaf_material_state_changes.json')
    need(leaf['status']==report['leaf_cutoff_preservation']=='EXACT_TWO_LEAF_MASK_FOUR_VALUE_DELTA_PASS_INTEGRATION_PENDING'
         and report['leaf_art_review']==C.LEAF_ART_SCOPE and leaf['geometry_or_UV_edit_by_stage'] is False
         and leaf['material_identities_and_bindings_unchanged'] is True and leaf['whole_town_concept_acceptance'] is False,
         'Leaf exact authored delta/binding/pending scope differs')
    need(leaf['source_RNA']==report['leaf_input']['rna'] and leaf['source_GUI']==report['leaf_input']['gui']
         and leaf['source_exact_aliases']==report['leaf_input']['aliases'],'Leaf actual evidence binding differs')
    need(digest(leaf_graphs['all134_before_leaf'])==digest(graphs['all134_after_tree'])
         and materials['leaf_material_fields']==leaf['fields']==leaf_graphs['fields']
         and materials['leaf_serialized_aliases']==leaf_graphs['measured_aliases'],
         'Exact after-tree/before-leaf graph or authored/alias scope differs')
    leaf_proof=L.permitted_material_delta(leaf_graphs['all134_before_leaf'],leaf_graphs['all134_after_leaf'],
                                       leaf_graphs['fields'],leaf_graphs['measured_aliases'])
    need(leaf_proof==leaf['material_changes']==leaf_graphs['material_changes'], 'Leaf full graph proof differs')
    need({name:T.raw_state_sha256(state) for name,state in leaf_graphs['all134_after_leaf'].items()}==b['raw'],
         'Leaf structured graphs do not bind actual final material raw hashes')
    scope=report['stage_scope_allowlists']
    need(scope['ground_finish_scope']==Q.SCOPE and scope['ground_specular_ior']==Q.VALUE
         and scope['ground_specular_authored_fields']==1 and scope['ground_specular_serialized_aliases']==35,'New ground scalar scope differs')
    need(report['tree_mesh_preservation']['status']=='EXACT_UV_ONLY_LOCAL_MESH_PRESERVATION_PASS'
         and scope['pairwise_mesh_scopes_disjoint'] is True and scope['leaf_materials']==sorted(leaves)
         and scope['leaf_fields']==leaf['fields'] and scope['leaf_serialized_aliases']==leaf_graphs['measured_aliases']
         and scope['leaf_geometry_or_bindings_changed'] is False,'Disjoint tree/ground/facade/leaf scope differs')
    need(materials['other_data_before']['canonical']==materials['other_data_reopened']['canonical'],'Reopened other native data differs')
    facade=read(composition/'facade_changes.json');apertures=read(composition/'reopened_facade_apertures.json')
    need(facade['tool_sha256']==report['sources']['tools/town_upgrade/facade_aperture_details.py']['sha256'] and facade['whole_source_members_removed']==11 and [r['object'] for r in facade['changed_objects']]==list(C.FACADE_TARGETS) and apertures['status']=='PASS' and apertures['all_authored_window_apertures_tested']==49 and not apertures['failing_windows'],'Exact facade save/aperture scope differs')
    validate_image_observations(report,composition,materials,C)
    ground=read(composition/'ground_changes.json');need(ground['new_material']==report['new_material'] and ground['native_normals_preserved'] is True and ground['selected_colour_clipping'] is False and ground['original_protected_uv_sha256']==ground['actual_protected_uv_sha256'] and ground['original_protected_face_material_sha256']==ground['actual_protected_face_material_sha256'],'Ground protected state differs')
    need(sha(composition/'actual_terrain_scope.npz')==ground['actual_scope_arrays']['sha256'],'Actual ground selection array changed')
    packed=ground['node_bindings']['packed_images'];need(set(packed)=={'diff','nor_gl','arm'} and len({v['name'] for v in packed.values()})==3,'Missing/duplicate registered grass images')
    for row in packed.values():
        actual=materials['packed_images_reopened'][row['name']]
        need(actual['packed_sha256']==row['sha256'] and actual['packed_bytes']==row['bytes'] and actual['colorspace']==row['colorspace'] and actual['size']==[2048,2048],'Actual saved packed PBR image differs')
    expected_sources={f'tools/town_upgrade/{name}' for name in C.PRODUCTS}|{f'tools/town_upgrade/{name}' for name in ('entry_details.py','building_native_audit.py','garden_soil_details.py','scale_figures.py')}
    need(set(report['sources'])==expected_sources,'Missing/extra final composition source bindings')
    for relative,row in report['sources'].items():need(sha(member(repo,relative))==row['sha256'],'Composition recipe changed: '+relative)
    return reopened

def preflight(folder,repo):
    folder,repo=Path(folder).resolve(),Path(repo).resolve();need(not (folder/'refined_candidate_REJECTED.json').exists(),'Rejected final assembly is not exportable')
    final=read(folder/'upgrade_manifest.json');lineage=final['finish_derivation']
    need(lineage['schema']=='living_town.source_bound_refined_derivation.v3','Missing final composition lineage')
    need(lineage['receipts']==canonical_receipts(folder),'Final canonical receipt scope/identity differs')
    for row in lineage['receipts'].values():verify_member(folder,row)
    old=read(member(folder,lineage['receipts']['entry_manifest']['path']));snapshot=read(member(folder,lineage['receipts']['entry_snapshot']['path']));assembly=read(folder/'refined_candidate_assembly.json')
    need(snapshot['sha256']==digest(snapshot['files'])==assembly['entry_snapshot_sha256'] and snapshot['files']['upgrade_manifest.json']['sha256']==lineage['receipts']['entry_manifest']['sha256'],'Entry historical snapshot differs')
    retained=set()
    for name,row in snapshot['files'].items():
        if name in REPLACED:continue
        verify_member(folder,{'path':name,**row});retained.add(name)
    for name,row in assembly['new_members'].items():verify_member(folder,{'path':name,**row})
    D=load('refined_package_file_helpers',repo/'tools/town_upgrade/derive_entry_candidate.py')
    controls=CONTROL if (folder/'refined_candidate_preflight.json').exists() else CONTROL-{'refined_candidate_preflight.json'}
    need(set(D.snapshot(folder)['files'])==retained|set(assembly['new_members'])|controls,'Unbound/missing final folder members')
    need(not final['assets'] and not (folder/'chunks').exists() and 'export_recipe' not in final,'Final inherited previous/partial portable state')
    for name,row in old['recipe_bindings'].items():need(final['recipe_bindings'].get(name)==row,'Original recipe binding was substituted')
    source_root=PREFIX+'sources/'
    report=read(member(folder,lineage['receipts']['composition']['path']))
    need(report['inputs']['entry_manifest']['sha256']==lineage['receipts']['entry_manifest']['sha256'] and report['inputs']['entry_audit']['sha256']==lineage['receipts']['entry_audit']['sha256'],'Historical entry inputs differ from actual engine inputs')
    need(set(final['recipe_bindings'])==set(old['recipe_bindings'])|set(report['sources']),'Final recipe binding set differs')
    for name,row in final['recipe_bindings'].items():need(sha(member(repo,name))==row['sha256'],'Current recipe differs: '+name)
    for name,row in report['sources'].items():need(sha(member(folder,source_root+name))==row['sha256'],'Copied composition recipe changed: '+name)
    C=load('refined_package_composition_contract',repo/'tools/town_upgrade/compose_refined_candidate.py')
    entry_audit=read(member(folder,lineage['receipts']['entry_audit']['path']));furniture=read(folder/'source_furniture_geometry.json')['objects']
    raw=validate_actual(report,member(folder,PREFIX+'pilot'),folder/'refined_whole_town.blend',old,entry_audit,furniture,repo,C)
    T=load('refined_archived_tree_contract',repo/'tools/town_upgrade/tree_uv_details.py');tree_original=validate_archived_tree(folder,report,T);verify_source_archive(folder,tree_original)
    L=load('refined_archived_leaf_contract',repo/'tools/town_upgrade/leaf_cutoff_details.py')
    leaf_archive=validate_archived_leaf(folder,report,L)
    Q=load('refined_archived_ground_finish_contract',repo/'tools/town_upgrade/ground_finish_details.py')
    validate_archived_ground(folder,report,Q)
    leaf_graphs=read(member(folder,PREFIX+'pilot/leaf_material_state_changes.json'))
    need(leaf_graphs['measured_aliases']==leaf_archive['alias_rows'],'Actual measured leaf alias table differs from composed graph scope')
    pixel_receipt=read(member(folder,PREFIX+'original_pixels/original_atlas_rgb8_receipt.json'))
    need(sha(member(folder,PREFIX+'original_pixels/original_atlas_rgb8_receipt.json'))==report['inputs']['original_pixels_receipt']['sha256'] and sha(member(folder,PREFIX+'original_pixels/original_atlas_rgb8.npy'))==pixel_receipt['array']['sha256'],'Copied exact original8K RGB8 source archive differs')
    baseline=read(member(folder,PREFIX+'material_proofs/material_baseline.json'))
    proof=read(member(folder,PREFIX+'material_proofs/unused_material_proof.json'))
    need(sha(member(folder,PREFIX+'material_proofs/material_baseline.json'))==C.BASELINE_SHA and sha(member(folder,PREFIX+'material_proofs/unused_material_proof.json'))==C.UNUSED_SHA,'Copied source material lifecycle proof differs')
    expected_materials={k:v for k,v in baseline['canonical_material_state_sha256'].items() if k not in ('LT_Hair','LT_Shirt','LT_Skin','LT_Trousers')}
    actual_materials=read(member(folder,PREFIX+'pilot/material_and_image_roundtrip.json'))
    need(len(expected_materials)==133 and actual_materials['raw_before']['canonical']==expected_materials and proof['entry']['sha256']==C.ENTRY_SHA,'Original complete133 material baseline differs')
    audit=read(folder/'whole_town_native_geometry.json');expected=copy.deepcopy(raw)
    expected.update(saved_native_sha256=sha(folder/'refined_whole_town.blend'),saved_native_path=str(folder/'refined_whole_town.blend'),building_records_sha256=sha(folder/'whole_town_buildings.json'),raw_reopened_audit_sha256=sha(member(folder,PREFIX+'pilot/refined_native_geometry_reopened.json')),refined_native_derivation_sha256=lineage['receipts']['composition']['sha256'])
    need(audit==expected and audit['status']==final['native_geometry_status']=='PASS' and sha(folder/'whole_town_native_geometry.json')==final['native_geometry_receipt_sha256'],'Final audit enrichment/native status differs')
    need(final['native']['path']=='refined_whole_town.blend' and final['native']['sha256']==final['source_blend_sha256']==audit['saved_native_sha256']==report['candidate']['sha256'] and final['native']['bytes']==(folder/'refined_whole_town.blend').stat().st_size,'Final saved native identity differs')
    allowed={'status','source_blend_sha256','native','native_geometry_receipt_sha256','recipe_bindings'}
    need(set(final)==set(old)|{'finish_derivation'} and all(final[k]==v for k,v in old.items() if k not in allowed),'Original entry metadata/history changed')
    need(final['buildings']==read(folder/'whole_town_buildings.json')['buildings'] and final['interiors']['buildings']==read(folder/'whole_town_interiors.json')['buildings'],'Building/interior inline records differ')
    need(digest(lineage)==digest(canonical_lineage(folder,report,C)),'Final complete scope/provenance claims differ')
    result={'status':'PREFLIGHT_PASS_REQUIRES_PORTABLE_AND_RUNTIME_REVIEW','manifest_sha256':sha(folder/'upgrade_manifest.json'),'native_sha256':sha(folder/'refined_whole_town.blend'),'actual_saved_reopened_engine_receipts_checked':True,'engine_executed':False,'geometry_recomputed':False}
    if (folder/'refined_candidate_preflight.json').exists():need(read(folder/'refined_candidate_preflight.json')==result,'Stored final preflight differs')
    return result

def derive(entry,composition,prepared,original_pixels,tree_pilot,output,repo,*,leaf_rna,leaf_gui_report,leaf_alias,leaf_portable,leaf_review):
    entry,composition,prepared,original_pixels,tree_pilot,output,repo=(Path(p).resolve() for p in (entry,composition,prepared,original_pixels,tree_pilot,output,repo))
    leaf_rna,leaf_gui_report,leaf_alias,leaf_portable,leaf_review=(Path(p).resolve(strict=True) for p in
        (leaf_rna,leaf_gui_report,leaf_alias,leaf_portable,leaf_review))
    folders={'entry':entry,'composition':composition,'prepared':prepared,'original_pixels':original_pixels,'tree_pilot':tree_pilot,
             'leaf_gui':leaf_gui_report.parent,'leaf_alias':leaf_alias,'leaf_portable':leaf_portable}
    need(not output.exists() and all(not output.is_relative_to(p) and not p.is_relative_to(output) for p in folders.values()),'Fresh non-overlapping assembly output required')
    D=load('refined_immutable_file_helpers',repo/'tools/town_upgrade/derive_entry_candidate.py');C=load('refined_actual_composition_contract',repo/'tools/town_upgrade/compose_refined_candidate.py')
    snapshots={name:D.snapshot(path) for name,path in folders.items()}
    leaf_file_bindings=[bound(path) for path in (leaf_rna,leaf_gui_report,leaf_review)]
    D.preflight(entry,repo);old=read(entry/'upgrade_manifest.json');report=read(composition/'refined_native_derivation.json')
    need(old['native']['sha256']==C.ENTRY_SHA and not any(name.startswith(PREFIX) for name in snapshots['entry']['files']),'Wrong entry or reserved final provenance exists')
    need(sha(entry/'whole_town_buildings.json')==C.BUILDINGS_SHA and sha(entry/'source_furniture_geometry.json')==C.FURNITURE_SHA,'Original records changed')
    need(report['inputs']['entry_manifest']['sha256']==sha(entry/'upgrade_manifest.json') and report['inputs']['entry_audit']['sha256']==sha(entry/'whole_town_native_geometry.json') and report['inputs']['prepared']['sha256']==sha(prepared/'prepared_maps.json'),'Engine input receipts differ from exact complete folders')
    furniture=read(entry/'source_furniture_geometry.json')['objects'];raw=validate_actual(report,composition,composition/'refined_whole_town.blend',old,read(entry/'whole_town_native_geometry.json'),furniture,repo,C)
    G=load('refined_package_ground_contract',repo/'tools/town_upgrade/ground_details.py');prepared_record,_=C.check_prepared(prepared,G);G.check_original_pixels(original_pixels,prepared_record)
    T=load('refined_package_tree_contract',repo/'tools/town_upgrade/tree_uv_details.py')
    tree_payload=T.check_payload_v4(tree_pilot,report['tree_uv_input']['sha256'],report['tree_uv_wrapper_input']['sha256'],repo)
    need(tree_payload['wrapper_receipt']==report['tree_uv_wrapper_input'],'Actual tree004 wrapper input differs')
    L=load('refined_package_leaf_contract',repo/'tools/town_upgrade/leaf_cutoff_details.py')
    leaf_payload=L.check_payload(leaf_rna,leaf_gui_report,leaf_alias,leaf_portable)
    actual_leaf_inputs={'rna':leaf_payload['rna_binding'],'gui':leaf_payload['gui_binding'],'aliases':leaf_payload['aliases']['receipt'],
                       'portable_check':bound(leaf_portable/'core_mask_check.json'),
                       'portable_export':bound(leaf_portable/'portable_cutoff_export.json'),'review':bound(leaf_review)}
    need(report['leaf_input']==actual_leaf_inputs and sha(leaf_review)==C.LEAF_REVIEW_SHA,
         'Actual leaf source/GUI/alias/portable/review inputs differ from engine composition')
    leaf_rows=leaf_evidence_rows(leaf_payload,bound(leaf_review))
    Q=load('refined_package_ground_finish_contract',repo/'tools/town_upgrade/ground_finish_details.py')
    ground=report['art_reviews']['ground'];ground_inputs=ground['finish_inputs']
    actual_ground=Q.check_payload(*(ground_inputs[k]['path'] for k in ('root','specular','visual','technical')))
    need(digest(actual_ground)==digest(ground),'Actual new scoped ground evidence differs from composer')
    need(sha(original_pixels/'original_atlas_rgb8_receipt.json')==report['inputs']['original_pixels_receipt']['sha256'] and sha(tree_pilot/'tree_uv_repair_pilot.json')==report['inputs']['tree_pilot_receipt']['sha256']==report['tree_uv_input']['sha256'],'Actual tree/originalpixel input differs from composition')
    for stage in ('ground','facade'):
        proof=report['art_reviews'][stage];C.verify(proof['review']);C.verify(proof['pilot'])
        for row in [*proof['images'],*proof['artifacts']]:C.verify(row)
    created=False
    try:
        output.mkdir(parents=True,exist_ok=False);created=True
        def copy_file(source,relative,expected):D.checked_copy(source,member(output,relative),expected)
        for name,row in snapshots['entry']['files'].items():
            if name not in REPLACED:copy_file(member(entry,name),name,row['sha256'])
        history={'entry_manifest':PREFIX+'entry_upgrade_manifest.json','entry_audit':PREFIX+'entry_whole_town_native_geometry.json','entry_snapshot':PREFIX+'entry_complete_snapshot.json','composition':PREFIX+'pilot/refined_native_derivation.json'}
        copy_file(entry/'upgrade_manifest.json',history['entry_manifest'],sha(entry/'upgrade_manifest.json'));copy_file(entry/'whole_town_native_geometry.json',history['entry_audit'],sha(entry/'whole_town_native_geometry.json'));write(member(output,history['entry_snapshot']),snapshots['entry'])
        for name,row in snapshots['composition']['files'].items():
            if name!='refined_whole_town.blend':copy_file(member(composition,name),PREFIX+'pilot/'+name,row['sha256'])
        copy_file(composition/'refined_whole_town.blend','refined_whole_town.blend',report['candidate']['sha256'])
        for name,row in snapshots['prepared']['files'].items():copy_file(member(prepared,name),PREFIX+'prepared/'+name,row['sha256'])
        for category,source_folder in [('original_pixels',original_pixels),('tree_pilot',tree_pilot)]:
            for name,row in snapshots[category]['files'].items():copy_file(member(source_folder,name),PREFIX+category+'/'+name,row['sha256'])
        tree_original=read(tree_pilot/'tree_uv_repair_pilot.json');tree_sources={}
        for i,row in enumerate(tree_original['source_bindings'].values()):
            source=Path(row['path'])
            if source.suffix.lower() not in ('.py','.gltf','.json') or source.name=='scene_before_inventory.json':continue
            relative=PREFIX+'tree_sources/'+str(i).zfill(3)+'_'+source.name
            copy_file(source,relative,row['sha256']);tree_sources[row['path']]=bound(member(output,relative),output)
        write(member(output,PREFIX+'tree_source_archive.json'),{'historical_bindings':tree_original['source_bindings'],'copied':tree_sources,'raw_geometry_texture_files_duplicated':False,
            'scope':'Original tool, glTF and receipt metadata plus both complete actual replay NPZ payload sets retained. Native contains used packed pixels/actual geometry; source license/URLs/hashes retained for raw-source regeneration. No claim of another full raw-download backup.'})
        leaf_copied={}
        for i,(original,row) in enumerate(leaf_rows.items()):
            relative=PREFIX+'leaf_pilot/'+str(i).zfill(3)+'_'+Path(original).name
            copy_file(Path(original),relative,row['sha256']);leaf_copied[original]=bound(member(output,relative),output)
        write(member(output,PREFIX+'leaf_source_archive.json'),{'historical_bindings':leaf_rows,'copied':leaf_copied,
            'leaf_input':actual_leaf_inputs,'full_source_native_duplicated':False,
            'scope':'Actual four GUI PNGs/users/receipt, source RNA, measured18-path complete graphs/diff/script/sources, tinycoreMASK GLB/check/export and scoped independent review. Historical absolute paths are metadata only; relocated preflight reads the bound copied members.'})
        pixels=read(original_pixels/'original_atlas_rgb8_receipt.json')
        for key in ('tool','feather_math'):
            row=pixels[key];copy_file(Path(row['path']),PREFIX+'original_pixel_tools/'+key+'.py',row['sha256'])
        for relative,row in report['sources'].items():copy_file(member(repo,relative),PREFIX+'sources/'+relative,row['sha256'])
        for name in ('material_baseline','unused_material_proof'):
            row=report['inputs'][name];C.verify(row);copy_file(Path(row['path']),PREFIX+'material_proofs/'+name+'.json',row['sha256'])
        for stage in ('ground','facade'):
            proof=report['art_reviews'][stage]
            for key in ('review','pilot'):
                row=proof[key];copy_file(Path(row['path']),PREFIX+'art/'+stage+'/'+key+'.json',row['sha256'])
            for i,row in enumerate(proof['images']):copy_file(Path(row['path']),PREFIX+'art/'+stage+'/image_'+str(i)+'.png',row['sha256'])
            for i,row in enumerate(proof['artifacts']):copy_file(Path(row['path']),PREFIX+'art/'+stage+'/artifact_'+str(i)+Path(row['path']).suffix,row['sha256'])
        enriched=copy.deepcopy(raw);enriched.update(saved_native_sha256=sha(output/'refined_whole_town.blend'),saved_native_path=str(output/'refined_whole_town.blend'),building_records_sha256=sha(output/'whole_town_buildings.json'),raw_reopened_audit_sha256=sha(composition/'refined_native_geometry_reopened.json'),refined_native_derivation_sha256=sha(composition/'refined_native_derivation.json'));write(output/'whole_town_native_geometry.json',enriched)
        new_members={name:row for name,row in D.snapshot(output)['files'].items() if name not in snapshots['entry']['files'] or name in REPLACED}
        assembly={'schema':SCHEMA,'status':'ASSEMBLED_REQUIRES_PREFLIGHT_PORTABLE_AND_RUNTIME','entry_snapshot_sha256':snapshots['entry']['sha256'],'immutable_input_snapshots':snapshots,'new_members':new_members,'engine_executed':False,'geometry_recomputed':False,'source_furniture_baseline_rewritten':False};write(output/'refined_candidate_assembly.json',assembly)
        final=copy.deepcopy(old);final.update(status='REFINED_SAVED_REOPENED_REQUIRES_PORTABLE_AND_RUNTIME_REVIEW',source_blend_sha256=sha(output/'refined_whole_town.blend'),native=bound(output/'refined_whole_town.blend',output),native_geometry_receipt_sha256=sha(output/'whole_town_native_geometry.json'))
        for relative,row in report['sources'].items():
            if relative in final['recipe_bindings']:need(final['recipe_bindings'][relative]['sha256']==row['sha256'],'Old recipe conflicts with composition')
            else:final['recipe_bindings'][relative]={'sha256':row['sha256']}
        history['assembly']='refined_candidate_assembly.json'
        final['finish_derivation']=canonical_lineage(output,report,C)
        write(output/'upgrade_manifest.json',final)
        result=preflight(output,repo)
        for name,path in folders.items():need(D.snapshot(path)==snapshots[name],'Immutable input folder changed during assembly')
        for row in leaf_file_bindings:need(bound(row['path'])==row,'Immutable leaf input file changed during assembly')
        write(output/'refined_candidate_preflight.json',result);return result
    except BaseException as exc:
        if created:
            path=output/'upgrade_manifest.json'
            if path.exists():
                rejected=read(path);rejected.update(status='REJECTED_ASSEMBLY_DO_NOT_EXPORT',native_geometry_status='REJECTED_ASSEMBLY',assembly_rejection=str(exc));write(path,rejected)
            write(output/'refined_candidate_REJECTED.json',{'status':'REJECTED_NOT_FOR_EXPORT','error':str(exc),'engine_executed':False})
        raise

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('entry','composition','prepared','original-pixels','tree-pilot','output','repo',
                'leaf-rna','leaf-gui-report','leaf-alias','leaf-portable','leaf-review'):p.add_argument('--'+key,type=Path,required=True)
    args=p.parse_args(argv)
    try:print(json.dumps(derive(args.entry,args.composition,args.prepared,args.original_pixels,args.tree_pilot,args.output,args.repo,
        leaf_rna=args.leaf_rna,leaf_gui_report=args.leaf_gui_report,leaf_alias=args.leaf_alias,
        leaf_portable=args.leaf_portable,leaf_review=args.leaf_review)));return 0
    except (ValueError,OSError,KeyError,TypeError) as error:print(json.dumps({'status':'REJECTED_NOT_FOR_EXPORT','error':str(error),'engine_executed':False}),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
