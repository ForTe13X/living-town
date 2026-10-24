"""Scoped Spec003 ground adapter. No engine effects on import.

The former rejection stays historical. This module requires the newer, narrow
root acceptance and the actual fresh one-scalar pair; it creates no art approval.
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
from types import FunctionType

TECHNICAL_SHA='c86a60cb58f700066d8f022f8fbcf7e447d38b1bb2462d7d9cd81f9378119a2f'
ROOT_REVIEW_SHA='b75c6798cde6fc753c34c6125a45c36c3cfea27969cebb59d16ae1e8cbe1995b'
SPEC_SHA='47f0e0504dffe33d7fbd2c7044d15ae2dc2da37a46e8586c78bc77034e238b7c'
VISUAL_SHA='a0a6953755f7a46ace34ed096dac1dd7251867b2a104cdf87705996c16fdd238'
PILOT_SHA='78989d7044372543ac309898adaab98333be72b022e28fdc17b8e762554633f7'
FEATHER_SHA='083b79522df90c261f89efabee9d3fa756f25ea8050a7a563c1752766674e934'
ORIGINAL_SHA='baeead4459219ebd9f1030ae38150ff3ed43176c274af756599173c824ffa04d'
ALIAS_SHA='190764fd19755296284b48d85933a0087c151b4bcc79f41659094298511ea091'
TABLE_SHA='2691ac9303fc377e273f76ef7a50bd91aff2e315c64cac6bf85f2bb86879314a'
C_SHA='302f0c27b96f131c92b6a05cadef146bde2302e9f112958d6fdcb9c9a277d338'
D_SHA='83ee88465901e1a68226e67ff3b72856d09cd221a8e71fec0429cba3e2a2e3e4'
ENTRY_SHA='b550a160dede21d339ccb195339d13c631202e600b352d2f04d6be9f526b752c'
MATERIAL='ContinuousSummer_Grass_Pilot'
OLD_MATERIAL='Refined_Terrain_PortableAtlas'
SOCKET='Specular IOR Level'
VALUE=0.2800000011920929
SCOPE='SCOPED_GROUND_MATERIAL_COURT_GRAIN_OVERLAY_REMOVAL_COMPOSITION_ONLY_EXISTING_BANK_P2'
DELTA_STATUS='EXACT_ONE_SCALAR_AND_35_MEASURED_SERIALIZED_PATHS_ONLY'


def need(value,message):
    if not value:raise ValueError(message)


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def binding(path):
    p=Path(path).resolve(strict=True);return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}


def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def alias_model():
    p=Path(__file__).with_name('alias_projection_001.py')
    need(sha(p)==ALIAS_SHA and sha(p.with_name('alias_paths_001.json'))==TABLE_SHA,'Sealed35-path scalar source differs')
    spec=importlib.util.spec_from_file_location('refined_ground_exact_scalar_alias',p)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


def evidence_contract(root,spec,visual,feather,original):
    need(root['schema']=='living_town.root_ground_finish_scoped_acceptance.v1' and root['status']=='ACCEPTED_FOR_NEW_COMPOSITION_CANDIDATE_ONLY','New explicit scoped ground acceptance required')
    need(root['technical_receipt_sha256']==SPEC_SHA and root['pilot_source_sha256']==PILOT_SHA and root['independent_visual_review_sha256']==VISUAL_SHA
         and root['fresh_C_image_sha256']==C_SHA and root['fresh_D_image_sha256']==D_SHA,'Root scoped acceptance actual source/pair differs')
    need(all(root[key] is False for key in ('seam_fixed_claim','whole_town_concept_accepted','native_save_or_export_accepted','runtime_accepted')),'Ground acceptance was broadened beyond composition material finish')
    need(spec['status']=='FRESH_SAME_PROCESS_C_D_ONE_SCALAR_SOURCE_PRESERVATION_PASS_ART_PENDING' and spec['native']['sha256']==ENTRY_SHA
         and spec['sources']['pilot']['sha256']==PILOT_SHA and spec['source_native_unchanged'] is True and spec['saved'] is False and spec['exported'] is False,'Actual completed fresh Spec003 pair required')
    need(spec['preservation_after_render']['status']=='EXACT_SCOPED_PRESERVATION_PASS' and spec['preservation_after_render']['original_materials_unchanged']==133
         and spec['original_furniture_after_render']['count']==6739 and spec['original_furniture_after_render']['all_original_6739_match'] is True,'Spec003 full preservation/furniture proof incomplete')
    need(spec['scalar_delta']['status']==DELTA_STATUS and spec['scalar_delta']['authored_field_count']==1
         and spec['scalar_delta']['serialized_changed_path_count']==35 and spec['scalar_delta']['ignored_or_normalized_state']==[]
         and spec['scalar_delta']['old']==0.5 and spec['scalar_delta']['new']==VALUE,'Actual finite35-path scalar proof differs')
    need(spec['original_scalar_rna']['material']==OLD_MATERIAL and spec['original_scalar_rna']['socket']==SOCKET
         and spec['original_scalar_rna']['default_value']==VALUE and spec['original_scalar_rna']['is_linked'] is False,'Measured original grass scalar differs')
    pair=spec['images'];need(len(pair)==2 and [x['image']['sha256'] for x in pair]==[C_SHA,D_SHA],'Fresh actual C/D images missing/substituted')
    keys=('actual_matrix_world','lens_mm','camera_type','ortho_scale','seed','resolution')
    need(all(pair[0][key]==pair[1][key] for key in keys),'Fresh pair camera/seed/resolution differs')
    need(spec['paired_control_scope']['fresh_same_process_C_and_D'] is True and spec['paired_control_scope']['authored_socket_writes_after_reconstruction']==1
         and spec['paired_control_scope']['authored_derived_cache_writes']==0 and spec['paired_control_scope']['full_current_corner_normals_exact'] is True,'Fresh one-scalar pair control incomplete')
    need(all(not row['before_differences'] and not row['after_differences'] for row in spec['paired_camera_checks']),'Fresh pair camera drift')
    need(visual['status']=='SCOPED_MATERIAL_FINISH_SUPPORTED_EXISTING_GRADED_BANK_REMAINS' and visual['source_reports']['fresh_paired_C_D']['sha256']==SPEC_SHA
         and visual['whole_town_concept_acceptance'] is False and visual['blocking_new_finish_regression_in_D_found'] is False,'Independent actual pair review missing/wrong scope')
    need(spec['sources']['actual_feather_receipt']['sha256']==FEATHER_SHA and feather['status']=='RENDERED_BOUNDARY_FEATHER_SOURCE_PRESERVATION_PASS_ART_PENDING'
         and feather['source_native_unchanged'] is True and feather['native']['sha256']==ENTRY_SHA,'Exact reconstructed four-metre feather proof differs')
    need(feather['sources']['baseline002']['sha256']==ORIGINAL_SHA and original['status']=='RENDERED_EXACT_SCOPED_PRESERVATION_PASS_ART_PENDING'
         and original['native']['sha256']==ENTRY_SHA and len(original['images'])==6,'Original ground comparison evidence differs')
    need(spec['sources']['terrain_change']==feather['terrain_change'] and spec['sources']['feather_change']==feather['feather_change'],'Spec003 reconstructed mask/feather lineage differs')
    return {'scope':SCOPE,'seam_fixed_claim':False,'whole_town_concept_acceptance':False,'native_or_runtime_approval':False,
            'original_specular_ior':VALUE,'remaining_art_issues':root['remaining_art_issues']}


def check_payload(root_path,spec_path,visual_path,technical_path):
    for p,expected in ((root_path,ROOT_REVIEW_SHA),(spec_path,SPEC_SHA),(visual_path,VISUAL_SHA),(technical_path,TECHNICAL_SHA)):
        need(sha(p)==expected,'Exact actual root/Spec003/visual ground evidence required: '+str(p))
    root,spec,visual=map(read,(root_path,spec_path,visual_path))
    technical=read(technical_path)
    need(technical['status']=='TECHNICAL_CAUSAL_PAIR_EVIDENCE_REVIEW_PASS_VISUAL_DECISION_SEPARATE'
         and technical['actual_root_report']==binding(spec_path),'Independent completed Spec003 technical review differs')
    feather_row=spec['sources']['actual_feather_receipt'];need(binding(feather_row['path'])==feather_row,'Actual feather receipt changed')
    feather=read(feather_row['path']);original_row=feather['sources']['baseline002'];need(binding(original_row['path'])==original_row,'Original ground evidence changed')
    original=read(original_row['path']);scope=evidence_contract(root,spec,visual,feather,original)
    artifacts=[binding(spec_path),binding(visual_path),binding(technical_path),original_row,*spec['sources'].values(),feather['terrain_change'],feather['feather_change']]
    for row in (feather['terrain_change'],feather['feather_change']):artifacts.append(read(row['path'])['actual_scope_arrays'])
    A=alias_model();artifacts.extend(A.evidence_bindings().values())
    rows={}
    for row in artifacts:
        need(binding(row['path'])==row,'Bound ground evidence changed: '+row['path'])
        if row['path'] in rows:need(rows[row['path']]==row,'Conflicting ground evidence identity')
        rows[row['path']]=row
    images=[x['image'] for x in original['images']]+[x['image'] for x in feather['images']]+[x['image'] for x in spec['images']]
    for row in images:need(binding(row['path'])==row,'Actual ground comparison image changed')
    return {'review':binding(root_path),'pilot':feather_row,'images':images,'artifacts':list(rows.values()),'reviewer':'root',
            'decision':'APPROVED_FOR_COMPOSITION','finish_inputs':{'root':binding(root_path),'specular':binding(spec_path),'visual':binding(visual_path),'technical':binding(technical_path)},'accepted_scope':scope}


def validate_archived(proof,read_bound):
    """Read copied members only. read_bound verifies their hash/length first."""
    need(set(proof['finish_inputs'])=={'root','specular','visual','technical'},'Complete scoped ground input set required')
    rows=proof['finish_inputs']
    need(rows['root']==proof['review'] and rows['root']['sha256']==ROOT_REVIEW_SHA and rows['specular']['sha256']==SPEC_SHA
         and rows['visual']['sha256']==VISUAL_SHA and rows['technical']['sha256']==TECHNICAL_SHA and proof['pilot']['sha256']==FEATHER_SHA,'Copied scoped ground proof identity differs')
    root,spec,visual=(read_bound(rows[k]) for k in ('root','specular','visual'))
    technical=read_bound(rows['technical'])
    need(technical['status']=='TECHNICAL_CAUSAL_PAIR_EVIDENCE_REVIEW_PASS_VISUAL_DECISION_SEPARATE'
         and technical['actual_root_report']==rows['specular'],'Copied actual technical review differs')
    feather=read_bound(proof['pilot']);original=read_bound(feather['sources']['baseline002'])
    scope=evidence_contract(root,spec,visual,feather,original)
    need(proof['accepted_scope']==scope and proof['decision']=='APPROVED_FOR_COMPOSITION' and proof['reviewer']=='root','Archived narrow ground scope differs')
    required=[*spec['sources'].values(),feather['terrain_change'],feather['feather_change']]
    for row in required:read_bound(row,parse=False)
    for key in ('terrain_change','feather_change'):read_bound(read_bound(feather[key])['actual_scope_arrays'],parse=False)
    expected_images=[x['image'] for x in original['images']]+[x['image'] for x in feather['images']]+[x['image'] for x in spec['images']]
    need(proof['images']==expected_images,'Archived ground actual view list differs')
    return scope


def structured_materials(bpy,E):
    private=FunctionType(E._materials.__code__,{**E.__dict__,'_digest':lambda value:value})
    return private(bpy)


def apply_specular(bpy,E):
    """Exactly one authored socket; preserve the full live134-material graph."""
    source=bpy.data.materials.get(OLD_MATERIAL);material=bpy.data.materials.get(MATERIAL)
    need(source is not None and material is not None,'Actual original/new grass materials required')
    nodes=[n for n in source.node_tree.nodes if n.bl_idname=='ShaderNodeBsdfPrincipled']
    need(len(nodes)==1,'Actual original grass Principled node missing/ambiguous')
    source_socket=nodes[0].inputs.get(SOCKET)
    need(source_socket is not None and not source_socket.is_linked and float(source_socket.default_value)==VALUE,'Actual original source Specular IOR not measured0.28')
    node=material.node_tree.nodes.get('Principled BSDF');socket=node.inputs.get(SOCKET) if node else None
    need(socket is not None and not socket.is_linked and float(socket.default_value)==.5,'New grass default control differs')
    before=structured_materials(bpy,E);need(len(before)==134,'Full original133 plus one new grass required')
    A=alias_model();wanted=A.expected(before,'grass_specular')
    socket.default_value=float(source_socket.default_value)
    after=structured_materials(bpy,E);need(digest(after)==digest(wanted),'Full grass graph differs from finite35 projected state')
    proof=A.specular_delta(before,after,material.name,node.name,.5,float(socket.default_value))
    return {'status':DELTA_STATUS,'all134_before_scalar':before,'all134_after_scalar':after,'material_changes':proof,
            'source_material':source.name,'source_node':nodes[0].name,'source_socket':SOCKET,'source_value':float(source_socket.default_value),
            'geometry_or_binding_changed':False,'whole_town_concept_acceptance':False}


def validate_composed(change,before_tree,original133):
    need(change['status']==DELTA_STATUS and change['geometry_or_binding_changed'] is False and change['whole_town_concept_acceptance'] is False
         and change['source_material']==OLD_MATERIAL and change['source_socket']==SOCKET and change['source_value']==VALUE,'Composed scalar scope differs')
    before,after=change['all134_before_scalar'],change['all134_after_scalar']
    need(len(before)==len(after)==134 and set(before)==set(original133)|{MATERIAL},'Complete ground134 graph inventory differs')
    need(digest({k:before[k] for k in original133})==digest(original133),'Ground before scalar changed an original133 material')
    need(digest(before_tree)==digest(after),'After-ground scalar graph differs from actual before-tree graph')
    proof=alias_model().specular_delta(before,after,MATERIAL,'Principled BSDF',.5,VALUE)
    need(digest(proof)==digest(change['material_changes']),'Composed full35-path scalar proof differs')
    return proof
