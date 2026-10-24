"""Compose ENTRY + reviewed ground/facade + proved tree004 UV + leaf mask.

Root runs Blender. Importing this module has no engine or filesystem effects.
All paths resolve from an explicit --repo; staging placement is never a repo.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time

SCHEMA='living_town.refined_native_composition.v3'
REVIEW_SCHEMA='living_town.refined_stage_art_review.v1'
ENTRY_SHA='b550a160dede21d339ccb195339d13c631202e600b352d2f04d6be9f526b752c'
BUILDINGS_SHA='2ffec0c996de735cd31035b2d5ad322a8ddba9e55d73fa5e81ce949aa0cbd125'
FURNITURE_SHA='eb650a64b89c848a9697aee978baa9d414cabe3fd2d6e348f3c5306b7192a97e'
BASELINE_SHA='05ad3ae485c655ad6e150f2a9f7e535f2ebb4d266fdbe0a1adc50db8fc9dc0ad'
UNUSED_SHA='36fa60c89ea3157a7f168c92c5056c0d5c1e1a58b0e357e87c4881b7b3a92789'
PRODUCTS=('compose_refined_candidate.py','ground_details.py','facade_aperture_details.py','tree_uv_details.py','derive_refined_candidate.py',
          'leaf_cutoff_details.py','alias_projection_001.py','alias_paths_001.json','ground_finish_details.py','packed_image_guard.py')
FACADE_TARGETS=('lot_12_halftimber_Front_Trunk','lot_14_halftimber_Front_Trunk','lot_22_halftimber_Front_Trunk',
                'lot_29_halftimber_Front_Trunk','lot_38_halftimber_Front_Trunk','lot_38_halftimber_Upgrade_OpenEntrance_Trunk')
SUCCESS='NATIVE_SAVED_REOPENED_REQUIRES_PORTABLE_AND_RUNTIME_REVIEW'
LEAF_REVIEW_SHA='6acf99de661eda8408b00c9197188bdb796ba03bb1de76e77292664fd4ffe453'
IMAGE_GUARD_SHA='fe07fc295e92a391c6760fb5dd5650551a7faf703115ccc4d34161842763fbf0'
LEAF_ART_SCOPE='SCOPED_MATERIAL_PREVIEW_IMPROVEMENT_SUPPORTED_FINAL_NATIVE_RUNTIME_PENDING'

def need(condition,message):
    if not condition:raise ValueError(message)

def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
def bound(path):
    p=Path(path).resolve(strict=True);return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}
def verify(row):need(bound(row['path'])==row,'Bound input changed: '+row['path'])
def write(path,value):
    path=Path(path);tmp=path.with_suffix(path.suffix+'.tmp');tmp.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n',encoding='utf-8');tmp.replace(path)
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module);return module

def check_review(path,stage,source_sha):
    review=read(path)
    need(review['schema']==REVIEW_SCHEMA and review['stage']==stage and review['decision']=='APPROVED_FOR_COMPOSITION', 'An explicit stage art acceptance receipt is required')
    need(review['actual_pixels_viewed'] is True and isinstance(review['reviewer'],str) and review['reviewer'].strip() and review['whole_town_concept_acceptance'] is False,'Review scope/reviewer/pixel evidence differs')
    verify(review['pilot_receipt']);pilot=read(review['pilot_receipt']['path']);artifact_rows=[]
    if stage=='ground':
        need(pilot['status']=='RENDERED_BOUNDARY_FEATHER_SOURCE_PRESERVATION_PASS_ART_PENDING' and pilot['source_native_unchanged'],'Actual feather ground pilot is not complete')
        need(pilot['native']['sha256']==ENTRY_SHA and pilot['sources']['pilot']['sha256']==source_sha,'Feather art pilot source differs')
        need(pilot['sources']['baseline002']['sha256']=='baeead4459219ebd9f1030ae38150ff3ed43176c274af756599173c824ffa04d' and pilot['sources']['math']['sha256']=='afb608a472b55ac6609b94068b16e1563dc1785fe811bd4f550b8e29a0b9b04b' and pilot['sources']['source_pixel_receipt']['sha256']=='dcfff8c98eec0837c1261c81483d70aae460a04e95815dc3f7e9463c67662fe2','Feather original source/sampler/baseline differs')
        need(pilot['preservation_before_render']['status']=='EXACT_SCOPED_PRESERVATION_PASS','Feather actual preservation failed')
        verify(pilot['sources']['baseline002']);original=read(pilot['sources']['baseline002']['path'])
        need(original['status']=='RENDERED_EXACT_SCOPED_PRESERVATION_PASS_ART_PENDING' and original['native']['sha256']==ENTRY_SHA and len(original['images'])==6,'Original six ground comparison frames missing')
        need(pilot['images'] and all(row['exact_pass'] for row in pilot['camera_rehearsal']) and all(not row['before_render_differences'] and not row['after_render_differences'] for row in pilot['render_camera_checks']),'Actual exact feather cameras incomplete')
        for key in ('terrain_change','feather_change'):verify(pilot[key])
        artifact_rows=[pilot['sources']['baseline002'],pilot['terrain_change'],pilot['feather_change']]
        for key in ('terrain_change','feather_change'):
            row=read(pilot[key]['path'])['actual_scope_arrays'];verify(row);artifact_rows.append(row)
        images=[row['image'] for row in original['images']]+[row['image'] for row in pilot['images']]
        need(7<=len(images)<=9,'Require original six frames plus every actually rendered feather candidate frame')
    else:
        need(pilot['status']=='RENDERED_REQUIRES_VISUAL_REVIEW' and pilot['inputs_stable'] and pilot['inputs']['native']['sha256']==ENTRY_SHA and pilot['inputs']['tool']['sha256']==source_sha,'Actual facade pilot/source differs')
        need(pilot['repair']['status']=='PASS' and pilot['repair']['whole_source_members_removed']==11 and pilot['repair']['structural_apertures_after']['status']=='PASS','Actual facade structural scope differs')
        images=[bound(row['path']) for row in pilot['views']]
        need(len(images)==4 and all(row['sha256']==actual['sha256'] for row,actual in zip(pilot['views'],images)),'Require exact four facade comparison frames')
    for image in images:verify(image)
    need(review['reviewed_images']==images,'Review omits/substitutes actual comparison frames')
    return {'review':bound(path),'pilot':review['pilot_receipt'],'images':images,'artifacts':artifact_rows,'reviewer':review['reviewer'],'decision':review['decision']}

def check_prepared(folder,G):
    receipt=Path(folder)/'prepared_maps.json';need(sha(receipt)==G.PREPARED_SHA256,'Require exact prepared003 bytes')
    r=read(receipt)
    need(r['schema']=='living_town.continuous_ground_finish_prepared.v1' and r['status']=='HOST_PREPARED_NATIVE_ART_AND_PORTABLE_PENDING' and r['inputs']['native']['sha256']==ENTRY_SHA and r['inputs']['preparer']['sha256']==G.SOURCE_PREPARER_SHA256,'Prepared source/recipe differs')
    rows=[]
    for group in ('inputs','source_maps','material_images','outputs','provenance_files'):
        for row in r[group].values():
            core={k:row[k] for k in ('path','bytes','sha256')};verify(core);rows.append(core)
    row={k:r['original_atlas_diff'][k] for k in ('path','bytes','sha256')};verify(row);rows.append(row)
    return r,rows

def canonical_other_data(bpy,E):
    result={};excluded={}
    for ob in bpy.data.objects:
        if ob.data is None or ob.type=='MESH':continue
        key=ob.type+':'+ob.data.name_full
        if key in result:continue
        state=copy.deepcopy(E._curve_state(ob.data) if ob.type in ('FONT','CURVE') else E._rna_values(ob.data))
        if 'session_uid' in state:
            uid=state.pop('session_uid');need(type(uid) is int and uid>0,'Invalid root native ID session UID')
            excluded[key]={'field':'/session_uid','raw_value':uid}
        result[key]=E._digest(state)
    return {'canonical':result,'excluded_root_session_only':excluded}

def image_rows(snapshot):
    # Exact proved helper packed_row translated to existing material-proof keys.
    # alpha_mode is the sole explicit row-schema extension.
    return {name:{'size':row['size'],'colorspace':row['colorspace'],'source':'FILE',
            'packed_bytes':row['bytes'],'packed_sha256':row['sha256'],'filepath':row['filepath'],
            'alpha_mode':row['alpha_mode']} for name,row in snapshot['assets'].items()}


def images(bpy):
    helper=Path(__file__).with_name('packed_image_guard.py')
    need(sha(helper)==IMAGE_GUARD_SHA,'Proved packed shader-image helper differs')
    return image_rows(load('refined_packed_image_capture',helper).capture(bpy))


def verify_shader_bindings(before,after,allow_added=False):
    a,b=before['shader_image_bindings'],after['shader_image_bindings']
    need(set(a).issubset(b) if allow_added else set(a)==set(b),'Shader-bound image inventory changed')
    need(all(a[name]==b[name] for name in a),'Original Material/World recursive image bindings changed')


def verify_images(before,after,allow_filepath_remap=False):
    need(set(before)==set(after),'Used packed native image identity changed')
    remaps={}
    for name,state in before.items():
        wanted,actual=dict(state),dict(after[name]);old_path=wanted.pop('filepath');new_path=actual.pop('filepath')
        need(wanted==actual,'Packed native image/content/colorspace changed: '+name)
        if old_path!=new_path:
            need(allow_filepath_remap,'Packed image path changed within process: '+name);remaps[name]={'before':old_path,'after':new_path}
    return remaps

def check_audit(audit,baseline,furniture):
    need(audit['schema']=='living_town.whole_town_native_geometry.v1' and audit['status']==audit['source_furniture_geometry_status']=='PASS' and not audit['failures'],'Actual full native audit failed')
    need(audit['counts']==baseline['counts'] and audit['all_visual_acceptance'] is False and audit['scene_mutations']==[],'Architectural inventory/audit scope changed')
    checks=audit['source_furniture_geometry_checks']
    need(len(checks)==6739 and len({row['object'] for row in checks})==6739 and {row['object'] for row in checks}==set(furniture),'Full original furniture audit scope differs')
    for row in checks:need(row['pass'] is True and row['actual_geometry_sha256']==row['expected_geometry_sha256']==furniture[row['object']]['geometry_sha256'],'Original furniture fingerprint changed: '+row['object'])

def verify_facade_delta(before,after,objects_before,objects_after,facade):
    changes=facade['changed_objects'];need([row['object'] for row in changes]==list(FACADE_TARGETS) and facade['whole_source_members_removed']==11,'Unexpected facade change budget')
    need(facade['status']=='PASS' and facade['structural_apertures_after']['all_authored_window_apertures_tested']==49 and not facade['structural_apertures_after']['failing_windows'],'Facade full evaluated aperture checks failed')
    expected_objects=dict(before['objects']);old_meshes=set();new_meshes=set()
    for row in changes:
        name=row['object'];a,b=copy.deepcopy(objects_before[name]),copy.deepcopy(objects_after[name])
        need(a.pop('data')==row['source_mesh'] and b.pop('data')==row['result_mesh'] and a==b,'Facade changed object identity/transform/flags beyond data replacement')
        expected_objects[name]=after['objects'][name];old_meshes.add(row['source_mesh']);new_meshes.add(row['result_mesh'])
        empty=name.endswith('_Upgrade_OpenEntrance_Trunk')
        need((row['source_vertices'],row['result_vertices'],row['source_polygons'],row['result_polygons'])==((8,0,12,0) if empty else (48,32,36,24)),'Facade primitive budget changed')
        need(row['protected_geometry_uv_material_smooth_faces_preserved'] and row['replacement_geometry_or_clipped_fragments_created']==0,'Protected facade faces changed')
    need(after['objects']==expected_objects and after['other_data']==before['other_data'] and after['materials']==before['materials'],'Non-target facade stage object/data/material changed')
    need(set(after['meshes'])==(set(before['meshes'])-old_meshes)|new_meshes,'Facade mesh ownership set changed')
    for name,state in before['meshes'].items():
        if name not in old_meshes:need(after['meshes'].get(name)==state,'Non-target local mesh changed during facade stage: '+name)
    return {'status':'EXACT_COMPOSED_DELTA_PASS','changed_facade_objects':list(FACADE_TARGETS),'whole_members_removed':11,'other_objects_meshes_materials_exact':True}

def stage_views(before,final,terrain_mesh,soil_mesh,facade,tree_targets,wood_materials):
    """Derived views of TWO actual full guards, not extra measured snapshots.

    Each masked target has its own exact apply proof. A single final guard
    compares all remaining actual scene bytes against the initial guard.
    """
    def shallow(state):return {key:dict(rows) for key,rows in state.items()}
    old_facade={row['source_mesh'] for row in facade['changed_objects']}
    new_facade={row['result_mesh'] for row in facade['changed_objects']}
    need(len(old_facade)==len(new_facade)==6 and len(tree_targets)==10 and not old_facade&tree_targets and not new_facade&tree_targets and not {terrain_mesh,soil_mesh}&(old_facade|new_facade|tree_targets),'Composition stage mesh scopes overlap')
    post_facade=shallow(final)
    for name in tree_targets:post_facade['meshes'][name]=before['meshes'][name]
    for name in wood_materials:post_facade['materials'][name]=before['materials'][name]
    ground_only=shallow(post_facade)
    for row in facade['changed_objects']:
        ground_only['objects'][row['object']]=before['objects'][row['object']]
        ground_only['meshes'].pop(row['result_mesh']);ground_only['meshes'][row['source_mesh']]=before['meshes'][row['source_mesh']]
    expected_ground=shallow(before)
    expected_ground['objects'].pop('Reference_Pocket_Gardens_Dirt');expected_ground['meshes'].pop(soil_mesh)
    expected_ground['meshes'][terrain_mesh]=final['meshes'][terrain_mesh]
    expected_ground['materials']['ContinuousSummer_Grass_Pilot']=final['materials']['ContinuousSummer_Grass_Pilot']
    return ground_only,expected_ground,post_facade

def verify_npz_equal(actual,expected):
    import numpy as np
    with np.load(actual,allow_pickle=False) as a,np.load(expected,allow_pickle=False) as b:
        need(set(a.files)==set(b.files),'Reviewed/native scope array keys differ')
        for key in a.files:
            left,right=a[key],b[key]
            need(left.dtype==right.dtype and left.shape==right.shape and left.tobytes()==right.tobytes(),'Reviewed/native array bytes differ: '+key)
    return True


def check_leaf_review(path,L,payload):
    need(sha(path)==LEAF_REVIEW_SHA,'Exact independent four-image leaf review required')
    review=read(path)
    need(review['status']=='SCOPED_MATERIAL_PREVIEW_IMPROVEMENT_SUPPORTED_INTEGRATION_PENDING'
         and review['report']['sha256']==L.GUI_SHA and review['whole_town_concept_acceptance'] is False,
         'Leaf review scope differs; it is not whole-town/runtime approval')
    need(review['viewed_images']==payload['gui']['screenshots'],'Leaf review omits/substitutes actual paired views')
    return bound(path)


def stage_views_v2(before,final,terrain_mesh,soil_mesh,facade,tree_targets,wood_materials,leaf_materials):
    """Only proven target deltas are removed from the actual final full guard."""
    need(set(leaf_materials)=={'Botanical_Broadleaf','Botanical_Pine_Needles'}
         and not set(leaf_materials)&set(wood_materials),'Exact disjoint two-leaf material scope required')
    post_tree={key:dict(rows) for key,rows in final.items()}
    for name in leaf_materials:post_tree['materials'][name]=before['materials'][name]
    return stage_views(before,post_tree,terrain_mesh,soil_mesh,facade,tree_targets,wood_materials)

def run(args):
    import bpy
    import numpy as np
    repo=args.repo.resolve(strict=True);entry=args.entry.resolve(strict=True);prepared=args.prepared.resolve(strict=True);output=args.output.resolve()
    original_pixels=args.original_pixels.resolve(strict=True);tree_pilot=args.tree_pilot.resolve(strict=True)
    leaf_alias=args.leaf_alias.resolve(strict=True);leaf_portable=args.leaf_portable.resolve(strict=True)
    leaf_gui=args.leaf_gui_report.resolve(strict=True);leaf_rna=args.leaf_rna.resolve(strict=True)
    need(not output.exists() and all(not output.is_relative_to(p) and not p.is_relative_to(output) for p in
         (entry,prepared,original_pixels,tree_pilot,leaf_alias,leaf_portable,leaf_gui.parent,args.ground_specular_pilot.resolve().parent)),
         'Fresh output outside immutable input folders required')
    need(bpy.app.background,'Isolated root-owned background Blender required')
    if str(repo) not in sys.path:sys.path.insert(0,str(repo))
    G=load('refined_ground_details',Path(__file__).with_name('ground_details.py'))
    Q=load('refined_ground_finish_details',Path(__file__).with_name('ground_finish_details.py'))
    image_helper=Path(__file__).with_name('packed_image_guard.py')
    need(sha(image_helper)==IMAGE_GUARD_SHA,'Proved packed shader-image helper differs')
    I=load('refined_packed_shader_images',image_helper)
    F=load('refined_facade_details',Path(__file__).with_name('facade_aperture_details.py'));F.configure(repo)
    T=load('refined_tree_uv_details',Path(__file__).with_name('tree_uv_details.py'))
    L=load('refined_leaf_cutoff_details',Path(__file__).with_name('leaf_cutoff_details.py'))
    E=load('refined_frozen_entry',repo/'tools/town_upgrade/entry_details.py')
    D=load('refined_entry_preflight',repo/'tools/town_upgrade/derive_entry_candidate.py')
    A=load('refined_native_audit',repo/'tools/town_upgrade/building_native_audit.py')
    S=load('refined_material_inventory',repo/'tools/town_upgrade/garden_soil_details.py')
    H=load('refined_soil_components',repo/'tools/town_upgrade/scale_figures.py')
    # Review and immutable-byte checks all precede engine mutation or output.
    ground_review=Q.check_payload(args.ground_review,args.ground_specular_pilot,args.ground_visual_review,args.ground_technical_review)
    facade_review=check_review(args.facade_review,'facade',F.SOURCE_FACADE_SHA256)
    entry_preflight=D.preflight(entry,repo);manifest=read(entry/'upgrade_manifest.json')
    need(entry_preflight['native_sha256']==ENTRY_SHA,'Require accepted saved ENTRY')
    record,prepared_rows=check_prepared(prepared,G)
    original_pixels=G.check_original_pixels(args.original_pixels,record)
    tree_payload=T.check_payload_v4(args.tree_pilot,args.tree_pilot_sha256,args.tree_wrapper_sha256,repo)
    leaf_payload=L.check_payload(leaf_rna,leaf_gui,leaf_alias,leaf_portable)
    leaf_review=check_leaf_review(args.leaf_review,L,leaf_payload)
    native=entry/manifest['native']['path'];need(sha(native)==ENTRY_SHA,'Actual ENTRY differs')
    need(sha(entry/'whole_town_buildings.json')==BUILDINGS_SHA and sha(entry/'source_furniture_geometry.json')==FURNITURE_SHA,'Original architectural/furniture records changed')
    buildings=read(entry/'whole_town_buildings.json');furniture=read(entry/'source_furniture_geometry.json')['objects'];need(len(furniture)==6739,'Require original6739 records')
    baseline_audit=read(entry/'whole_town_native_geometry.json')
    need(sha(args.material_baseline)==BASELINE_SHA and sha(args.unused_material_proof)==UNUSED_SHA,'Measured material lifecycle proof changed')
    material_baseline=S.verify_material_baseline(args.material_baseline);S.verify_unused_proof(args.unused_material_proof,material_baseline)
    expected_materials={k:v for k,v in material_baseline['canonical_material_state_sha256'].items() if k not in S.SAVE_ORPHAN_MATERIALS}
    source_paths={f'tools/town_upgrade/{name}':Path(__file__).with_name(name) for name in PRODUCTS}
    source_paths.update({f'tools/town_upgrade/{name}':repo/'tools/town_upgrade'/name for name in ('entry_details.py','building_native_audit.py','garden_soil_details.py','scale_figures.py')})
    sources={name:bound(path) for name,path in source_paths.items()}
    bound_inputs={name:bound(path) for name,path in {'entry_manifest':entry/'upgrade_manifest.json','entry_audit':entry/'whole_town_native_geometry.json','buildings':entry/'whole_town_buildings.json','furniture':entry/'source_furniture_geometry.json','prepared':prepared/'prepared_maps.json','material_baseline':args.material_baseline,'unused_material_proof':args.unused_material_proof,'original_pixels_receipt':args.original_pixels/'original_atlas_rgb8_receipt.json','tree_pilot_receipt':args.tree_pilot/'tree_uv_repair_pilot.json'}.items()}
    bound_inputs.update({name:bound(path) for name,path in {
        'tree_wrapper_receipt':tree_pilot/'revision004_wrapper.json',
        'ground_specular_pilot':args.ground_specular_pilot,'ground_visual_review':args.ground_visual_review,'ground_technical_review':args.ground_technical_review,'ground_scoped_review':args.ground_review,'leaf_rna':leaf_rna,'leaf_gui_report':leaf_gui,
        'leaf_alias_receipt':leaf_alias/'leaf_mask_alias_report.json','leaf_portable_check':leaf_portable/'core_mask_check.json',
        'leaf_portable_export':leaf_portable/'portable_cutoff_export.json','leaf_review':args.leaf_review}.items()})
    output.mkdir(parents=True,exist_ok=False);receipt=output/'refined_native_derivation.json'
    report={'schema':SCHEMA,'status':'RUNNING','input_native':bound(native),'inputs':bound_inputs,'sources':sources,'art_reviews':{'ground':ground_review,'facade':facade_review},'tree_uv_input':tree_payload['receipt'],'tree_art_review':'PENDING_ROOT_FINAL_CLOSEUPS_AND_CATALOG','blender_version':bpy.app.version_string,'whole_town_concept_acceptance':False,'portable_review':'PENDING','runtime_review':'PENDING','saved':False,'reopened':False}
    report.update(tree_uv_wrapper_input=tree_payload['wrapper_receipt'],leaf_art_review=LEAF_ART_SCOPE,
        leaf_input={'rna':leaf_payload['rna_binding'],'gui':leaf_payload['gui_binding'],
            'aliases':leaf_payload['aliases']['receipt'],'portable_check':bound_inputs['leaf_portable_check'],
            'portable_export':bound_inputs['leaf_portable_export'],'review':leaf_review})
    write(receipt,report)
    wall_start,cpu_start=time.monotonic(),time.process_time()
    def checkpoint(name,event):
        row={'stage':name,'event':event,'wall_elapsed_seconds':time.monotonic()-wall_start,'cpu_elapsed_seconds':time.process_time()-cpu_start}
        report.setdefault('stage_checkpoints',[]).append(row);report['current_stage']=row
        write(receipt,report);print('REFINED_STAGE '+json.dumps(row),flush=True)
    try:
        checkpoint('open_ENTRY','before')
        bpy.ops.wm.open_mainfile(filepath=str(native),load_ui=False,use_scripts=False);bpy.context.view_layer.update()
        checkpoint('open_ENTRY','after');checkpoint('early_packed_shader_image_preflight','before')
        initial_image_snapshot=I.capture(bpy);before_images=image_rows(initial_image_snapshot)
        image_observations={'helper':sources['tools/town_upgrade/packed_image_guard.py'],'initial':initial_image_snapshot}
        write(output/'packed_image_observations.json',image_observations)
        report['image_preflight']={'status':'ALL_USED_AND_RECURSIVE_SHADER_BOUND_IMAGES_PACKED_FILE',
            'assets':len(before_images),'excluded_unbound_builtins':initial_image_snapshot['excluded_unbound_builtins'],
            'excluded_unused_images':initial_image_snapshot['excluded_unused_images']}
        checkpoint('early_packed_shader_image_preflight','after');checkpoint('initial_full_guard','before')
        before=G.scene_guard(bpy,E);before_other=canonical_other_data(bpy,E);before_materials=S.material_inventory(bpy)
        initial_material_states=T.structured_materials(bpy,E)
        need({name:T.raw_state_sha256(state) for name,state in initial_material_states.items()}==before_materials['raw'],'Complete initial structured material capture differs')
        need(before_materials['canonical']==expected_materials and len(expected_materials)==133,'Actual ENTRY canonical133 materials differ')
        original_furniture=G.furniture_guard(bpy,furniture,A)
        checkpoint('initial_full_guard','after')
        write(output/'source_before_inventory.json',before);write(output/'source_furniture_before.json',original_furniture)
        terrain=bpy.data.objects.get(G.GROUND);soil=bpy.data.objects.get(G.SOIL)
        need(terrain is not None and terrain.type=='MESH' and terrain.data.users==1 and not terrain.modifiers and not terrain.data.shape_keys,'Exact owned unmodified terrain required')
        need(terrain.data.uv_layers and terrain.data.uv_layers.active_index==0 and terrain.data.uv_layers[0].active_render,'Expected source UV0')
        need(soil is not None and soil.type=='MESH' and soil.data.users==1 and len(soil.data.vertices)==781 and len(soil.data.polygons)==710 and E._digest(E._mesh_state(soil))==G.SOIL_SHA and len(H._components(soil))==71,'Exact old71 soil overlay differs')
        soil_mesh=soil.data.name;terrain_mesh=terrain.data.name
        slots=[m.name if m else None for m in terrain.data.materials];need(slots.count(G.OLD_MATERIAL)==1,'Original atlas material missing')
        checkpoint('ground_selection_apply','before')
        data=G.native_arrays(terrain);woodland=np.load(record['outputs']['original_woodland.npy']['path'],mmap_mode='r',allow_pickle=False);rock=np.load(record['outputs']['original_rockblend.npy']['path'],mmap_mode='r',allow_pickle=False)
        selected,centers=G.select_faces(data,slots.index(G.OLD_MATERIAL),woodland,rock,record['bounds_xy_m'],G)
        reviewed_ground=read(read(ground_review['pilot']['path'])['terrain_change']['path'])
        actual_mask=hashlib.sha256(np.flatnonzero(selected).astype('int32').tobytes()).hexdigest()
        need(actual_mask==reviewed_ground['selected_face_indices_sha256'],'Composed ground mask differs from actual reviewed feather pilot')
        adapter,calls,feather=G.feather_adapter(terrain,data,selected,centers,record,original_pixels,output)
        change=G.apply_terrain(bpy,terrain,data,selected,centers,record,adapter,output);bpy.data.objects.remove(soil,do_unlink=True)
        need(len(calls)==1,'Feather sampler must serve exactly one registered macro request')
        reviewed_feather=read(read(ground_review['pilot']['path'])['feather_change']['path'])
        verify_npz_equal(feather['actual_scope_arrays']['path'],reviewed_feather['actual_scope_arrays']['path'])
        for key in ('all_uv_write_sha256','all_polygon_material_write_sha256','selected_face_indices_sha256','selected_loop_indices_sha256','new_colour_attribute'):
            need(change[key]==reviewed_ground[key],'Actual final ground write differs from reviewed feather payload: '+key)
        ground_scalar=Q.apply_specular(bpy,E)
        write(output/'ground_specular_changes.json',ground_scalar)
        report['ground_specular_preservation']=ground_scalar['status']
        report['ground_art_scope']=Q.SCOPE
        report['reviewed_feather_payload_exact']=True
        checkpoint('ground_selection_apply','after')
        write(output/'ground_changes.json',change);write(output/'ground_feather_changes.json',feather)
        target_states={name:E._object_state(bpy.data.objects[name]) for name in FACADE_TARGETS}
        need(all(bpy.data.objects[name].data.users==1 for name in FACADE_TARGETS),'Facade target mesh has an unexpected additional owner')
        checkpoint('facade_apply','before');facade=F.apply(bpy,buildings['buildings']);write(output/'facade_changes.json',facade);checkpoint('facade_apply','after')
        checkpoint('tree_uv_original_native_and_payload_preflight','before')
        tree_context=T.preflight_native_v4(bpy,E,tree_payload)
        Q.validate_composed(ground_scalar,tree_context['materials'],initial_material_states)
        need({name:tree_context['materials'][name] for name in initial_material_states}==initial_material_states,'Ground/facade changed an original shader field before tree UV stage')
        checkpoint('tree_uv_original_native_and_payload_preflight','after');checkpoint('tree_uv_apply','before')
        tree=T.apply_v4(bpy,E,tree_payload,tree_context);write(output/'tree_uv_changes.json',tree)
        tree_material_after=T.structured_materials(bpy,E)
        T.validate_composed_material_states_v4(initial_material_states,tree_context['materials'],tree_material_after,tree['material_changes']['fields'])
        write(output/'tree_material_state_changes.json',{'original133_before':initial_material_states,'all134_before_tree':tree_context['materials'],'all134_after_tree':tree_material_after,'fields':tree['material_changes']['fields']})
        after_tree_materials=S.material_inventory(bpy)
        checkpoint('tree_uv_apply','after');checkpoint('leaf_cutoff_preflight','before')
        leaf_context=L.preflight_native(bpy,E,leaf_payload)
        need(L.digest(leaf_context['materials'])==L.digest(tree_material_after),'Before-leaf graph differs from exact after-tree graph')
        checkpoint('leaf_cutoff_preflight','after');checkpoint('leaf_cutoff_apply','before')
        leaf=L.apply(bpy,E,leaf_payload,leaf_context);write(output/'leaf_cutoff_changes.json',leaf)
        leaf_material_after=T.structured_materials(bpy,E)
        leaf_material_proof=L.permitted_material_delta(leaf_context['materials'],leaf_material_after,leaf['fields'],leaf_payload['aliases']['rows'])
        write(output/'leaf_material_state_changes.json',{'all134_before_leaf':leaf_context['materials'],
            'all134_after_leaf':leaf_material_after,'fields':leaf['fields'],'measured_aliases':leaf_payload['aliases']['rows'],
            'material_changes':leaf_material_proof})
        checkpoint('leaf_cutoff_apply','after');checkpoint('single_final_composed_full_guard','before')
        final=G.scene_guard(bpy,E)
        tree_targets=set(tree['target_meshes'])
        ground_view,expected_post_ground,post_facade_view=stage_views_v2(before,final,terrain_mesh,soil_mesh,facade,tree_targets,T.WOOD_MATERIALS,set(L.LEAVES))
        report['ground_preservation']=G.verify_preservation(before,ground_view,terrain_mesh,soil_mesh,G.SOIL,change)
        report['facade_preservation']=verify_facade_delta(expected_post_ground,post_facade_view,target_states,{name:E._object_state(bpy.data.objects[name]) for name in FACADE_TARGETS},facade)
        report['tree_mesh_preservation']=T.prove_mesh_guards(post_facade_view['meshes'],final['meshes'],tree_targets)
        final_materials=S.material_inventory(bpy);original_names=set(expected_materials);unchanged_names=original_names-T.WOOD_MATERIALS-set(L.LEAVES)
        need(len(unchanged_names)==125 and set(final_materials['raw'])==original_names|{G.MATERIAL},'Expected125 unchanged +six field-corrected wood +two cutoff leaf +one new grass materials')
        need(all({k:final_materials[mode][k] for k in unchanged_names}=={k:before_materials[mode][k] for k in unchanged_names} for mode in ('raw','canonical','session_uid')),'Non-target original125 material state changed')
        need({k for k in original_names if after_tree_materials['raw'][k]!=before_materials['raw'][k]}==T.WOOD_MATERIALS,'Before-leaf changes exceed exact six wood shaders')
        need({k for k in final_materials['raw'] if final_materials['raw'][k]!=after_tree_materials['raw'][k]}==set(L.LEAVES),'Leaf stage changed another material')
        need({k for k in original_names if final_materials['raw'][k]!=before_materials['raw'][k]}==T.WOOD_MATERIALS|set(L.LEAVES),'Original material changes exceed exact eight wood/leaf shaders')
        report['stage_scope_allowlists']={'ground_object':G.GROUND,'ground_mesh':terrain_mesh,'removed_soil_object':G.SOIL,'removed_soil_mesh':soil_mesh,
            'ground_finish_scope':Q.SCOPE,'ground_specular_ior':Q.VALUE,'ground_specular_authored_fields':1,'ground_specular_serialized_aliases':35,
            'facade_objects':list(FACADE_TARGETS),'facade_source_meshes':[r['source_mesh'] for r in facade['changed_objects']],'facade_result_meshes':[r['result_mesh'] for r in facade['changed_objects']],
            'tree_meshes':sorted(tree_targets),'tree_materials':sorted(T.WOOD_MATERIALS),'tree_fields':tree['material_changes']['fields'],
            'leaf_materials':sorted(L.LEAVES),'leaf_fields':leaf['fields'],'leaf_serialized_aliases':leaf_payload['aliases']['rows'],
            'leaf_geometry_or_bindings_changed':False,'pairwise_mesh_scopes_disjoint':True}
        report['guard_measurements']={'actual_full_initial_guard':True,'actual_full_final_guard':True,'intermediate_scope_views':'DERIVED_DELTA_VIEWS_OF_ACTUAL_INITIAL_FINAL_GUARDS; not claimed as additional engine snapshots','exact_target_and_material_apply_checks_each_stage':True}
        write(output/'derived_post_ground_view.json',expected_post_ground);write(output/'derived_post_facade_view.json',post_facade_view)
        final_other=canonical_other_data(bpy,E);need(final_other==before_other,'Non-target other native data changed within composition')
        final_image_snapshot=I.capture(bpy);final_images=image_rows(final_image_snapshot)
        verify_shader_bindings(initial_image_snapshot,final_image_snapshot,allow_added=True)
        image_observations['final_before_save']=final_image_snapshot
        write(output/'packed_image_observations.json',image_observations)
        need(set(before_images).issubset(final_images),'Original packed image disappeared')
        verify_images(before_images,{k:final_images[k] for k in before_images})
        need(len(set(final_images)-set(before_images))==3,'Expected exactly three added packed grass images')
        final_furniture=G.furniture_guard(bpy,furniture,A);need(final_furniture==original_furniture,'Original furniture changed during composition')
        write(output/'composed_final_inventory.json',final)
        checkpoint('single_final_composed_full_guard','after');checkpoint('full_native_audit_before_save','before')
        pre_audit=A.audit({'bpy':bpy},buildings['buildings'],output/'native_geometry_before_save.json',furniture);check_audit(pre_audit,baseline_audit,furniture)
        checkpoint('full_native_audit_before_save','after');checkpoint('save_new_native','before')
        candidate=output/'refined_whole_town.blend';print('REFINED_COMPOSITION_SAVE',flush=True)
        saved=bpy.ops.wm.save_as_mainfile(filepath=str(candidate),copy=True);need('FINISHED' in saved and candidate.is_file(),'Fresh native save failed')
        report.update(saved=True,candidate=bound(candidate));write(receipt,report)
        checkpoint('save_new_native','after');checkpoint('reopen_saved_native','before')
        bpy.ops.wm.open_mainfile(filepath=str(candidate),load_ui=False,use_scripts=False);bpy.context.view_layer.update()
        checkpoint('reopen_saved_native','after');checkpoint('reopened_full_guard','before')
        reopened=G.scene_guard(bpy,E);reopened_other=canonical_other_data(bpy,E);reopened_materials=S.material_inventory(bpy)
        need(reopened['objects']==final['objects'] and reopened['meshes']==final['meshes'],'Saved/reopened local mesh or scene-linked object state changed')
        need(reopened_other['canonical']==final_other['canonical'] and set(reopened_other['excluded_root_session_only'])==set(final_other['excluded_root_session_only']),'Saved/reopened other native state changed beyond explicit root session UID')
        need(reopened_materials['canonical']==final_materials['canonical'] and len(reopened_materials['canonical'])==134,'Saved/reopened complete134 material state changed')
        reopened_image_snapshot=I.capture(bpy);reopened_images=image_rows(reopened_image_snapshot)
        verify_shader_bindings(final_image_snapshot,reopened_image_snapshot)
        path_remaps=verify_images(final_images,reopened_images,allow_filepath_remap=True)
        image_observations['reopened']=reopened_image_snapshot
        image_observations['original_bindings_preserved']=True
        image_observations['all_final_bindings_reopened_exact']=True
        write(output/'packed_image_observations.json',image_observations)
        reopened_furniture=G.furniture_guard(bpy,furniture,A);need(reopened_furniture==original_furniture,'Saved/reopened original furniture changed')
        checkpoint('reopened_full_guard','after');checkpoint('reopened_full_native_audit','before')
        reopened_audit=A.audit({'bpy':bpy},buildings['buildings'],output/'refined_native_geometry_reopened.json',furniture);check_audit(reopened_audit,baseline_audit,furniture)
        aperture=F.aperture_audit(bpy,buildings['buildings']);need(aperture['status']=='PASS' and aperture['all_authored_window_apertures_tested']==49,'Saved/reopened facade aperture checks failed')
        write(output/'reopened_inventory.json',reopened);write(output/'source_furniture_reopened.json',reopened_furniture);write(output/'reopened_facade_apertures.json',aperture)
        material_proof={'raw_before':before_materials,'raw_after_tree':after_tree_materials,'raw_after_composition':final_materials,'raw_reopened':reopened_materials,
            'same_process_non_target125_exact':True,'six_wood_materials_exact15_uv_names_and66_serialized_paths_only':True,
            'two_leaf_materials_exact4_authored_values_and18_serialized_paths_only':True,
            'tree_material_fields':tree['material_changes']['fields'],'leaf_material_fields':leaf['fields'],
            'leaf_serialized_aliases':leaf_payload['aliases']['rows'],'ground_specular_exact1_authored_value_and35_serialized_paths_only':True,
            'all134_canonical_reopened_exact':True,
            'excluded_material_fields':['/settings/session_uid'],'other_data_before':final_other,'other_data_reopened':reopened_other,
            'packed_image_filepath_remaps':path_remaps,'packed_images_reopened':reopened_images,
            'packed_image_observations':bound(output/'packed_image_observations.json'),
            'packed_image_row_schema':'LEGACY_KEYS_PLUS_ALPHA_MODE_V1'}
        write(output/'material_and_image_roundtrip.json',material_proof)
        checkpoint('reopened_full_native_audit','after');checkpoint('immutable_source_final_check','before')
        for row in [*bound_inputs.values(),*sources.values(),*prepared_rows,original_pixels['tool'],original_pixels['feather_math'],original_pixels['array'],*tree_payload['report']['source_bindings'].values(),*tree_payload['artifacts']]:verify(row)
        for row in [tree_payload['wrapper_receipt'],*tree_payload['wrapper_report']['sources'].values(),
                    *tree_payload['wrapper_report']['source_checker_records'],*leaf_payload['artifacts'],
                    leaf_payload['aliases']['receipt'],*leaf_payload['aliases']['sources'],*leaf_payload['aliases']['artifacts']]:verify(row)
        for proof in (ground_review,facade_review):
            verify(proof['review']);verify(proof['pilot'])
            for row in [*proof['images'],*proof['artifacts']]:verify(row)
        need(sha(native)==ENTRY_SHA and bound(candidate)==report['candidate'],'Immutable input or saved candidate changed')
        checkpoint('immutable_source_final_check','after')
        report.update(status=SUCCESS,reopened=True,original_furniture_count=6739,original_furniture_inventory_sha256=original_furniture['inventory_sha256'],native_geometry_audit='PASS',facade_apertures='PASS',complete_source_stability=True,
            actual_reopened_native_sha256=report['candidate']['sha256'],new_material=G.MATERIAL,changed_terrain_object=G.GROUND,removed_soil_object=G.SOIL,material_original_count=133,material_final_count=134,
            tree_uv_preservation=tree['status'],tree_art_review='PENDING_ROOT_FINAL_CLOSEUPS_AND_CATALOG',
            leaf_cutoff_preservation=leaf['status'],leaf_art_review=LEAF_ART_SCOPE,
            cross_save_policy='Local mesh bytes plus each scene-linked object separately; no representative substitution. Only explicit root Material/other-ID session_uid canonical exclusion; all raw within-process guards exact.',
            limits='Narrow newer ground material acceptance with actual sourceIOR0.28/35paths checked; pre-existing graded bank remainsP2. Facade art acceptance inputs checked; exact tree004 proof and scoped leaf Material Preview/tiny core MASK evidence checked. Tree/leaf final native closeups and whole-town portable/Godot remain pending. No whole-town concept, frame-rate or gameplay approval. One fresh native saved once and actually reopened; source ENTRY unchanged.')
        report['artifacts']={p.name:bound(p) for p in sorted(output.iterdir()) if p.is_file() and p.name not in ('refined_native_derivation.json','refined_whole_town.blend')}
        write(receipt,report);print('refined_composition_test: PASS report='+str(receipt),flush=True)
    except BaseException as exc:
        report.update(status='FAIL',error=str(exc));write(receipt,report);print('refined_composition_test: FAIL '+str(exc),flush=True);raise

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('repo','entry','prepared','original-pixels','tree-pilot','ground-review','facade-review','material-baseline','unused-material-proof','output',
                'leaf-rna','leaf-gui-report','leaf-alias','leaf-portable','leaf-review','ground-specular-pilot','ground-visual-review','ground-technical-review'):p.add_argument('--'+key,type=Path,required=True)
    p.add_argument('--tree-pilot-sha256',required=True)
    p.add_argument('--tree-wrapper-sha256',required=True)
    args=p.parse_args(argv if argv is not None else sys.argv[sys.argv.index('--')+1:]);run(args)
if __name__=='__main__':main()
