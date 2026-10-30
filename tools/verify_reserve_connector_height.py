"""Verify the fixed ConnectorA source foundation using Python's standard library.

This checks fixture/source bytes and recorded evidence, never launches Unreal.
--base-root is a read-only overlay fallback for reviewing an unapplied draft.
"""
from pathlib import Path
import argparse,copy,hashlib,json,math,struct
ROOT=Path(__file__).resolve().parents[1]
SIDE=505;COUNT=SIDE*SIDE
OLD='2b5839619c03277cc4e73bb97e0d250661e9aec1efe5efe61850e5c16170b5cb'
NEW='9184ca30385056c1c7b551a5e05a7c1c75daa82a10e19662ce3787a0b51ea145'
CONFIG='d5848a113e7917516562079eb8f1ca81c6ad22de0dcfb4e2073fd5b8ac125d39'
NATIVE='ae761f4c9df57fb9a07ae849096ce1b18dc92a80206fcd6dbc5101d5cdab67d4'
BASELINE='0f34c44c8565e917de7eec1a17aebcf88a6b088657aed1c367574cf5a67e30a7'
CPP='unreal/Source/LivingTownMaterialInspection/LivingTownReserveLandscape.cpp'
HEADER=CPP[:-3]+'h'
OLD_RAW='unreal/Content/ReserveLandscapeSource_v001/Height505.r16'
NEW_RAW='unreal/Content/ReserveConnectorA_v001/Height505_connectorA_v001.r16'
ANCHORS='unreal/Content/ReserveLandscapeSource_v001/bridge_bank_anchors.json'
EVIDENCE='docs/evidence/reserve_connector_a_height_context_v001.json'
FIXTURES={
 'unreal/Config/ReserveLandscape_v001.json':(804,'7dfec8155ef185f04acda5bc5e0f433bb163bcac5bcdfc0f3b477381c463e312'),
 OLD_RAW:(510050,OLD),ANCHORS:(2830,'b126b6d702fc216986d39f4c2cc61598ec0af0e0c04e23f0d0c4121e4f8b24e7'),
 'unreal/Config/ReserveLandscapeConnectorA_v001.json':(789,CONFIG),NEW_RAW:(510050,NEW)}
SOURCES={CPP:(41542,'a6f8e466c65bcd46865c25e7051fe9c458aed3f022eabe0df6fd71d834587560'),HEADER:(1204,'85b06a9518ebdf23ea533c349fc281193199b35b9d36a94edc728b578ca19a9d'),
 'unreal/Source/LivingTownMaterialInspection/LivingTownReserveLandcover.cpp':(69518,'3c157d07871e2921ba0e0f82b7f8abfcec01e7f47f2f0dfe58a70f3db3138a53'),
 'unreal/Source/LivingTownMaterialInspection/LivingTownReserveLandcover.h':(1014,'998973480f4921c37f4ae7cb9327f47719c8c5b0e4c2b2a80ce2433a0e8f5aaa')}
ARTIFACT_HASHES={
 "build": "f9ea59a0091c3d12a7b5460122e8804f8cdd4261c4b46404b0c0741938a60b15",
 "build_audit": "1660df3de01a8f05ad784c5c98961423b0aab20c33f96aee3eed43176637c9be",
 "native_three_tests": "39e2247113995f7f98779334690982efc61d9b060b9daa7f882e47c8ee6f3558",
 "native_three_tests_raw": "2e0ebe66ce85b0a9c544273a17974b63327e4359a042c2845afa89753a2f57de",
 "native_three_tests_audit": "59d9b2549994f80ae341a62526eabb48734d1e9cf413604c270da8d7f6680913",
 "legacy_world": "7142fa69d4cf22a989c180b06f6f032ce6350e112c944aac5133cffe4b83b658",
 "legacy_world_audit": "a2d7cf03dd83d8164d0c9921f1ffb6c6c4c08ce46aebf11bd6f5d1a8610d3bb1",
 "legacy_native": "cad0b426b8d6a999cbd00dbb0d7563e2f91e08175f36a2ca777b3dbe28493dcc",
 "saved137": "21de9105c44a0973bd13e4581ea6c3d4af1df2662572c731406fc4ae070ec986",
 "source_Author_audit": "cd52cb822a4ba7e0f6b3674d2175282a8247d5d7d329be2aed41411cc92e3bf7",
 "source_Cold_proof": "a25ef68ffc7fb9f82e002ee40f923ebbb96cb0f8b1a1b1c33ecf31aab8c7fea0",
 "source_Cold_audit": "a91f385fc5e1cc3ebf2d88ef9068092ed3e317d91d3d7593c6a6609018a9a5f2",
 "source_Author_native": "58ab3930097a025c0b81a6b0e5dd02a793025776b372c4e895104bc684d98880",
 "source_Cold_native": "a37794f02da599c0c2dd8d4c3d02f8336b74b3988aa91f433afc6494a4f39de1",
 "height_derivative_recipe": "3009cf325b14de1f684b47518e4f62c66d9ee2a0d0711473b463d0bd641504d0",
 "source_Author_merged_raw": "9184ca30385056c1c7b551a5e05a7c1c75daa82a10e19662ce3787a0b51ea145",
 "source_Cold_merged_raw": "9184ca30385056c1c7b551a5e05a7c1c75daa82a10e19662ce3787a0b51ea145"
}
TESTS=['LivingTown.ReserveLandcover.ClosedSourceFixture','LivingTown.ReserveLandcover.ProfileBoundary','LivingTown.ReserveLandscape.SourceContextBoundary']
QUALIFICATIONS={'recorded_legacy2b_actual_create_read':True,'recorded_new9184_Author_readonly_Cold':True,'portable_verifier_is_new_engine_execution':False,'profile_paint':False,'complete_grade':False,'rail_collision':False,'full_world_walk':False,'native_Game':False,'art':False,'FPS':False}
CONFIG_KEYS={'schema','map_path','material_path','height_relative_path','height_sha256','height_bytes','width','height','height_encoding','row0','origin_cm','scale_xyz','subsection_size_quads','num_subsections','component_count_xy'}
def need(ok,message):
    if not ok:raise ValueError(message)
def sha(data):return hashlib.sha256(data).hexdigest()
def object_from(data):return json.loads(data.decode('utf-8-sig'))
def digest(rows):return sha(json.dumps(rows,sort_keys=True,separators=(',',':')).encode())
def checked_bytes(data,expected,name):need(len(data)==expected[0]and sha(data)==expected[1],'Exact source bytes: '+name)
def read_relative(root,relative,base=None):
    path=Path(relative);need(not path.is_absolute()and '..'not in path.parts,'Relative fixed source path')
    candidate=root/path
    if not candidate.is_file()and base is not None:candidate=base/path
    return candidate.read_bytes()
def validate_config(data,connector):
    c=object_from(data);need(set(c)==CONFIG_KEYS,'Closed15-key source config')
    namespace='ReserveConnectorA_v001'if connector else'ReserveLandscape_v001'
    expected={'schema':'LivingTown.ReserveLandscapeSource.v1','map_path':f'/Game/LivingTown_UEPilot/TownSlice_v003/{namespace}/L_{namespace}',
      'material_path':'/Game/LivingTown_UEPilot/TownSlice_v003/ReserveLandscape_v001/M_ReserveLandscape_v001.M_ReserveLandscape_v001',
      'height_relative_path':NEW_RAW.removeprefix('unreal/')if connector else OLD_RAW.removeprefix('unreal/'),
      'height_sha256':NEW if connector else OLD,'height_bytes':510050,'width':505,'height':505,'height_encoding':'uint16_le','row0':'minimum_UE_Y',
      'origin_cm':[-60000,-22400,4000],'scale_xyz':[100,100,25],'subsection_size_quads':63,'num_subsections':2,'component_count_xy':[4,4]}
    need(c==expected,'Fixed source context, transform, material and identity')
    config_name='ReserveLandscapeConnectorA_v001'if connector else'ReserveLandscape_v001'
    checked_bytes(data,FIXTURES['unreal/Config/'+config_name+'.json'],config_name)
    return c
def validate_derivative(old,new,record):
    checked_bytes(old,(510050,OLD),'legacy2b height');checked_bytes(new,(510050,NEW),'ConnectorA9184 height')
    before=struct.unpack('<255025H',old);after=struct.unpack('<255025H',new)
    delta=[{'row':i//SIDE,'column':i%SIDE,'legacy_uint16':a,'connector_uint16':b}for i,(a,b)in enumerate(zip(before,after))if a!=b]
    need(len(delta)==record['changed_samples']==59 and record['unchanged_samples']==254966,'Only59 source samples changed')
    need(delta==record['delta_uint16'],'Exact declared59-sample derivative')
    need(record['maximum_cut_m']==max((a-b)/512 for a,b in zip(before,after))==.85546875,'Actual maximum source cut')
    need(record['maximum_fill_m']==max((b-a)/512 for a,b in zip(before,after))==.068359375,'Actual maximum source fill')
    return before,after,delta
def anchor_stencils(before,after,anchors):
    need(anchors['schema']=='LivingTown.ReserveLandscapeBankAnchors.v1'and anchors['height_sha256']==OLD and len(anchors['anchors'])==6,'Original six source bridge anchors')
    result=[]
    for anchor in anchors['anchors']:
        x,y,_=anchor['canonical_xyz_m'];u=x+600;v=224-y;c=math.floor(u);r=math.floor(v);fx=u-c;fy=v-r
        need(0<=c<504 and 0<=r<504,'Anchor source coordinates')
        ids=[r*SIDE+c,r*SIDE+c+1,(r+1)*SIDE+c,(r+1)*SIDE+c+1]
        need(all(before[i]==after[i]for i in ids),'Original bridge anchor four-sample stencil unchanged')
        values=[40+(before[i]-32768)/512 for i in ids];a,b,d,e=values
        bilinear=(1-fx)*(1-fy)*a+fx*(1-fy)*b+(1-fx)*fy*d+fx*fy*e
        fixed=(1-fx)*a+(fx-fy)*b+fy*e if fx>=fy else(1-fy)*a+(fy-fx)*d+fx*e
        need(abs(bilinear-anchor['field_bilinear_height_m'])<1e-10,'Legacy anchor bilinear source value retained')
        result.append({'bank':anchor['bank'],'canonical_xy_m':[x,y],'unchanged_grid_indices':ids,'unchanged_bilinear_height_m':bilinear,'unchanged_fixed_native_triangle_height_m':fixed})
    return result
def validate_evidence(e):
    need(set(e)=={'schema','scope','fixtures','checked_repository_sources','qualified_native87_sha256','qualified_native_inputs','baseline_native87_sha256','baseline_changed_two','recorded_artifacts','derivative','actual','qualifications'},'Closed source-foundation evidence fields')
    need(e['schema']=='LivingTown.ConnectorA.SourceFoundationEvidence.v1'and e['scope']=='RECORDED_NATIVE_HEIGHT_SOURCE_FOUNDATION_NOT_PAINT_OR_GAME','Source-foundation evidence scope')
    need(e['qualifications']==QUALIFICATIONS and all(type(v)is bool for v in e['qualifications'].values()),'No paint/grade/rail/walk/Game/art/FPS acceptance')
    need(e['qualified_native87_sha256']==NATIVE and e['baseline_native87_sha256']==BASELINE,'Qualified native source family')
    rows=e['qualified_native_inputs'];need(len(rows)==87 and len({r['file']for r in rows})==87 and digest(rows)==NATIVE,'Recorded qualified87 source digest')
    changed={r['file']:r for r in e['baseline_changed_two']};need(set(changed)=={CPP,HEADER},'Only two native source replacements')
    need(digest([changed.get(r['file'],r)for r in rows])==BASELINE,'Other85 exact against baseline0f34')
    need({r['file']:(r['bytes'],r['sha256'])for r in e['checked_repository_sources']}==SOURCES,'Current fixed implementation and unchanged landcover-v2 source hashes')
    need({r['file']:(r['bytes'],r['sha256'])for r in e['fixtures']}==FIXTURES,'Closed exact legacy/new fixture roster')
    need(set(e['recorded_artifacts'])=={'build','build_audit','native_three_tests','native_three_tests_raw','native_three_tests_audit','legacy_world','legacy_world_audit','legacy_native','saved137','source_Author_audit','source_Cold_proof','source_Cold_audit','source_Author_native','source_Cold_native','height_derivative_recipe','source_Author_merged_raw','source_Cold_merged_raw'},'Closed retained actual proof roster')
    for role,expected in ARTIFACT_HASHES.items():need(e['recorded_artifacts'][role]['sha256']==expected,'Qualified actual artifact: '+role)
    actual=e['actual'];tests=actual['native_tests'];need(tests['test_names']==TESTS and tests['new_context_assertions']==34 and tests['raw_event_counts']==dict.fromkeys(TESTS,0),'Three actual native test cases and zero error events')
    need(actual['build']['status']=='PASS_NATIVE_EDITOR_BUILD'and actual['legacy_world']['status']=='PASS_ACTUAL_LEGACY2B_CREATE_READ_WORLD_PRIVATE_MAP_ONLY_NEW_REAL_GUID_135_SOURCE_PACKAGES_EXACT'and actual['legacy_world']['all255025_2b_samples_exact']is True and actual['legacy_world']['old_API_names_and_old_map_config_RAW_used']is True,'Actual build and legacy API world replay')
    native=actual['new_source'];need(native['saved_package_count']==137 and native['component_count']==native['native_collision_component_count']==16,'Actual saved137/native16 source foundation')
    need(native['Author_status']=='PASS_INDEPENDENT_ACTUAL_CONNECTOR9184_AUTHOR_SOURCE137_AUDIT'and native['Cold_status']=='PASS_ACTUAL_CONNECTOR9184_SOURCE_AUTHOR_AND_READ_ONLY_COLD137','Recorded actual successful source cases')
    for key in ['all136_original_packages_and229_intrinsic_values_preserved','all137_saved_bytes_preserved_cold','all255025_source_merged_uint16_exact']:need(native[key]is True,'Actual preservation proof: '+key)
    need(native['merged_sha256']==NEW and native['original_pond_contacts']==171 and native['shader_source_count']==6 and native['texture_roles_read_back']==74,'Actual source/readiness/pond/shader readback boundary')
    need(native['landscape_GUID']=='94AEDDFD4682AE90E0E41694BE1F8337'and native['edit_layer_GUID']=='009F77EC4965957FD84C47ACA39944E6','Recorded actual stock-generated GUIDs; not runtime overrides')
def validate_implementation(cpp,header):
    text=cpp.decode();h=header.decode()
    need('CreateReserveLandscapePreview(){return ReserveLandscapeRunContext(ReserveLandscapeLegacyContext(),true);}'in text and 'ReadReserveLandscapePreview(){return ReserveLandscapeRunContext(ReserveLandscapeLegacyContext(),false);}'in text,'Old API wrappers use unchanged legacy context')
    for name in ['CreateReserveConnectorLandscapePreview','ReadReserveConnectorLandscapePreview']:need(name in text and name in h,'New explicit source API')
    need(text.count('FJsonSerializer::Deserialize(')==text.count('SpawnActor<ALandscape>')==text.count('L->Import(FGuid::NewGuid()')==text.count('GetHeightDataFast(')==1,'Single shared parser/stock importer/full height reader')
    need('FCommandLine::Set'not in text and 'FCommandLine::Append'not in text and 'SetLandscapeGuid'not in text,'No command-line rewrite or supplied Landscape GUID')
def verify_external(e,root):
    for role,row in e['recorded_artifacts'].items():checked_bytes(read_relative(root,row['relative_to_evidence_root']),(row['bytes'],row['sha256']),'Retained actual '+role)
    # Hashes bind full actual files; these semantic checks prevent confusing one case with another.
    read=lambda role:object_from(read_relative(root,e['recorded_artifacts'][role]['relative_to_evidence_root']))
    author=read('source_Author_native');cold=read('source_Cold_native');legacy=read('legacy_native')
    for native in [author,cold]:
        need(native['status']=='READY_NATIVE_LANDSCAPE_SOURCE_HEIGHT_COMPONENTS_AND_COLLISION'and native['source_height_sha256']==native['merged_height_sha256']==NEW and native['source_config_sha256']==CONFIG and native['height_mismatch_count']==0 and native['all_source_uint16_samples_exact']is True,'Full retained actual9184 native source/merged proof')
        need(native['component_count']==native['collision_component_count']==16 and len(native['collisions'])==16,'Full retained native component/collision roster')
    need(author['guid']==cold['guid']and author['edit_layers'][0]['guid']==cold['edit_layers'][0]['guid']and len(read('saved137')['files'])==137,'Actual137 cold GUID/package identity')
    need(legacy['source_height_sha256']==legacy['merged_height_sha256']==OLD and legacy['all_source_uint16_samples_exact']is True,'Full legacy2b native source/merged proof')
    return len(e['recorded_artifacts'])
def self_test(old,new,config,evidence,anchors):
    rejected=[]
    def refuses(name,action):
        try:action()
        except (ValueError,KeyError):rejected.append(name);return
        raise AssertionError('Negative control accepted: '+name)
    refuses('truncated_RAW',lambda:validate_derivative(old,new[:-1],evidence['derivative']))
    tampered=bytearray(new);tampered[0]^=1;refuses('one_bit_RAW',lambda:validate_derivative(old,tampered,evidence['derivative']))
    refuses('legacy_RAW_in_connector_context',lambda:validate_derivative(old,old,evidence['derivative']))
    for key,value in [('map_path','/Game/Foreign/L_Map'),('material_path','/Game/Foreign/M.M'),('origin_cm',[-59999,-22400,4000]),('height_relative_path',OLD_RAW.removeprefix('unreal/')),('extra_key',0)]:
        c=object_from(config);c[key]=value;refuses('config_'+key,lambda c=c:validate_config(json.dumps(c).encode(),True))
    altered=copy.deepcopy(evidence);altered['qualifications']['full_world_walk']=True;refuses('false_worldwalk_scope',lambda:validate_evidence(altered))
    altered=copy.deepcopy(evidence);altered['art_accepted']=True;refuses('foreign_acceptance_field',lambda:validate_evidence(altered))
    altered=copy.deepcopy(evidence);altered['derivative']['delta_uint16'][0]['connector_uint16']+=1;refuses('false59_delta',lambda:validate_derivative(old,new,altered['derivative']))
    before=struct.unpack('<255025H',old);after=list(struct.unpack('<255025H',new));x,y,_=anchors['anchors'][0]['canonical_xyz_m'];i=math.floor(224-y)*SIDE+math.floor(x+600);after[i]^=1;refuses('bridge_anchor_stencil_change_independent_of_SHA',lambda:anchor_stencils(before,after,anchors))
    altered=copy.deepcopy(evidence);altered['qualified_native_inputs'][0]['bytes']+=1;refuses('foreign_qualified_native_source',lambda:validate_evidence(altered))
    return rejected
def main():
    p=argparse.ArgumentParser();p.add_argument('--repo-root',type=Path,default=ROOT);p.add_argument('--base-root',type=Path,help='Read-only fallback for unapplied draft review');p.add_argument('--self-test',action='store_true');p.add_argument('--recorded-evidence-root',type=Path,help='Optional retained actual artifact root, not an engine launcher');p.add_argument('--qualified-source-root',type=Path,help='Optional root of the recorded87-input qualified source copy');a=p.parse_args();read=lambda rel:read_relative(a.repo_root,rel,a.base_root)
    evidence=object_from(read(EVIDENCE));validate_evidence(evidence)
    for rel,expected in FIXTURES.items():checked_bytes(read(rel),expected,rel)
    for rel,expected in SOURCES.items():checked_bytes(read(rel),expected,rel)
    validate_config(read('unreal/Config/ReserveLandscape_v001.json'),False);validate_config(read('unreal/Config/ReserveLandscapeConnectorA_v001.json'),True);validate_implementation(read(CPP),read(HEADER))
    old=read(OLD_RAW);new=read(NEW_RAW);before,after,delta=validate_derivative(old,new,evidence['derivative']);anchors=object_from(read(ANCHORS));anchor_rows=anchor_stencils(before,after,anchors)
    result={'status':'PASS_PORTABLE_CONNECTOR_A_SOURCE_FOUNDATION_RECORDED_EVIDENCE_ONLY','legacy_height_sha256':OLD,'connector_height_sha256':NEW,'changed_samples':len(delta),'unchanged_samples':COUNT-len(delta),'all_six_source_bridge_anchor_stencils_unchanged':True,'anchors':anchor_rows,'fixed_repository_native_files_checked':len(SOURCES),'recorded_native87_source_digest_verified':NATIVE,'engine_started_or_new_runtime_qualification':False,'qualifications':QUALIFICATIONS}
    if a.qualified_source_root:
        actual_paths={p.relative_to(a.qualified_source_root).as_posix()for p in (a.qualified_source_root/'unreal/Source').rglob('*')if p.is_file()}|{'unreal/LivingTown.uproject'}
        need(actual_paths=={r['file']for r in evidence['qualified_native_inputs']},'Exact87 qualified native input pathset')
        for row in evidence['qualified_native_inputs']:checked_bytes(read_relative(a.qualified_source_root,row['file']),(row['bytes'],row['sha256']),row['file'])
        result['retained_qualified_source_files_verified']=87
    if a.recorded_evidence_root:result['retained_actual_artifacts_verified']=verify_external(evidence,a.recorded_evidence_root)
    if a.self_test:result['negative_controls_rejected']=self_test(old,new,read('unreal/Config/ReserveLandscapeConnectorA_v001.json'),evidence,anchors)
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
