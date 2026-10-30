"""Verify the additive bounded HISM observer and recorded evidence; stdlib only.

No engine/compiler/asset mutation. Optional local roots verify retained originals.
The bound Editor scene consumer is distinct from Game, visible-count, art or FPS acceptance.
"""
from pathlib import Path
import argparse,copy,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
CPP='unreal/Source/LivingTownNative/Private/LivingTownHismInspection.cpp'
HEADER='unreal/Source/LivingTownNative/Public/LivingTownHismInspection.h'
EVIDENCE='docs/evidence/native_hism_inspection_v001.json'
NATIVE='05db4b4dff0668a81e241a5f8c543fcc6cc6a908449c217b2a4fc158cb6c821f'
BASELINE='ae761f4c9df57fb9a07ae849096ce1b18dc92a80206fcd6dbc5101d5cdab67d4'
TEST='LivingTown.HismInspection.BoundedReadOnly'
SOURCES={CPP:(18622,'1ce39a751ff6658e296e069111314f18d24ebcf39e4b3347a9170fb5aedad94c'),HEADER:(559,'2433245f5e6894fd1c9ef0ba21c688ee433b18238608a5a12aeef39be17b08ed')}
ARTIFACTS={'build': {'file': 'native_hism_inspection_build_actual_v1_002/BUILD_RECEIPT.json',
           'bytes': 24253,
           'sha256': '2966db79900a87f6d08da30752d0eac0896c784cd55bc3bdc6665c81049e8a79'},
 'build_audit': {'file': 'native_hism_inspection_build_audit_v1_002/AUDIT.json',
                 'bytes': 2581,
                 'sha256': 'fb91b3bdc15817e9362c8cae059abcfba44266a18ae1a39826bcb8bf2e1015a2'},
 'native_structured_result': {'file': 'native_hism_inspection_boundary_actual_v1_001/Automation/index.json',
                              'bytes': 1137,
                              'sha256': 'e7ac4340ea94b4d109c85c3e09318fb7a91f3ca9d41228f877a04ec6aa21e467'},
 'native_raw_observation': {'file': 'native_hism_inspection_boundary_actual_v1_001/ACTUAL_AUTOMATION_RAW.json',
                            'bytes': 1233,
                            'sha256': 'a04fd148aaa97fc27942214580beed307ff6ace063a21c22dc0e836277ef62e7'},
 'boundary_audit': {'file': 'native_hism_inspection_boundary_audit_v1_001/AUDIT.json',
                    'bytes': 3886,
                    'sha256': '4826c72f55b3a7c792a2a4db371029782b47fd6161cc2f6113dcb1a5b37d1742'},
 'boundary_process_report': {'file': 'native_hism_inspection_boundary_actual_v1_001/REPORT.json',
                             'bytes': 12449,
                             'sha256': '2b6be8cf6f4e55a2c1296e3a21383edd38cad2bc7959c538ff276914e7b01f31'},
 'boundary_raw_log': {'file': 'native_hism_inspection_boundary_actual_v1_001/UnrealEditor.log',
                      'bytes': 254367,
                      'sha256': '024c523623f8b56345e31f73ce2ee8a30b58607cf4665d8047c48d57948b653f'},
 'original_failed_host_console': {'file': 'root_serial_console_v1_001/HismBoundary001_ACTUAL.log',
                                  'bytes': 12182,
                                  'sha256': 'd0f46babeb2ceb5a9633db39038acc46bd812fa3190323a2e8a1c9dc05b5e66a'}}
SCENE_ARTIFACTS={'scene_saved151': {'file': 'native_reserve_canopy3900_population_actual_v1_005/SAVED_PACKAGES.json', 'bytes': 74264, 'sha256': 'e33a373c2b9fc5ea4f7239271f473475128fef53ecb726a8087b84bae30b1404'}, 'scene_Author_audit': {'file': 'native_reserve_canopy3900_population_audit_v1_005/Author/AUDIT.json', 'bytes': 20596, 'sha256': '066479a499f0db805c1498a2044aa3f7509758643702de869cc4da6e1832eb60'}, 'scene_Cold_proof': {'file': 'native_reserve_canopy3900_population_actual_v1_005/COLD_PROOF.json', 'bytes': 1245, 'sha256': '99052b32b1ef05a79f0f25b7f5672e96c5baee85fe5d74f0a17e14adb941433e'}, 'scene_Cold_audit': {'file': 'native_reserve_canopy3900_population_audit_v1_005/Review/AUDIT.json', 'bytes': 18510, 'sha256': 'a8d6238fc1406680102f255ef1796b7856481dcc7534bcef219f27d21942e26e'}, 'scene_Author_DDC': {'file': 'native_reserve_canopy3900_population_actual_v1_005/AUTHOR_DDC_SOURCE.json', 'bytes': 512889, 'sha256': '984c9759658de026f51c7abd959764d26aa7da302088233895f92dc79d8609ea'}, 'scene_preparation': {'file': 'native_reserve_canopy3900_population_prepare_v1_005/FROZEN_HANDOFF.json', 'bytes': 14009, 'sha256': '41cd34e217b06539f6ad5e348a12300dec4d6bc82f063c18d14aa241e134c4c3'}, 'scene_Author_population_proof': {'file': 'native_reserve_canopy3900_population_actual_v1_005/Author/HOST_FINAL_POPULATION_PROOF.json', 'bytes': 767, 'sha256': '8be9f860d2387527711389a8266d1acf4ca1dbb654cf4045f4ede550f00fa472'}, 'scene_Review_population_proof': {'file': 'native_reserve_canopy3900_population_actual_v1_005/Review/HOST_FINAL_POPULATION_PROOF.json', 'bytes': 767, 'sha256': '8be9f860d2387527711389a8266d1acf4ca1dbb654cf4045f4ede550f00fa472'}}
ARTIFACTS.update(SCENE_ARTIFACTS)
SCENE_EXPECTED={'status': 'PASS_RECORDED_EDITOR_AUTHOR_AND_COLD_BOUNDED_HISM_OBSERVER', 'case': 'Canopy3900Current151_v005', 'preparation': {'file': 'native_reserve_canopy3900_population_prepare_v1_005/FROZEN_HANDOFF.json', 'bytes': 14009, 'sha256': '41cd34e217b06539f6ad5e348a12300dec4d6bc82f063c18d14aa241e134c4c3'}, 'saved151': {'file': 'native_reserve_canopy3900_population_actual_v1_005/SAVED_PACKAGES.json', 'bytes': 74264, 'sha256': 'e33a373c2b9fc5ea4f7239271f473475128fef53ecb726a8087b84bae30b1404'}, 'Author': {'audit': {'file': 'native_reserve_canopy3900_population_audit_v1_005/Author/AUDIT.json', 'bytes': 20596, 'sha256': '066479a499f0db805c1498a2044aa3f7509758643702de869cc4da6e1832eb60'}, 'population_proof': {'file': 'native_reserve_canopy3900_population_actual_v1_005/Author/HOST_FINAL_POPULATION_PROOF.json', 'bytes': 767, 'sha256': '8be9f860d2387527711389a8266d1acf4ca1dbb654cf4045f4ede550f00fa472'}, 'world_scope': 'Editor', 'groups': 141, 'instances': 3900, 'wall_seconds': 166.73399999999674, 'owned_reap': {'root_exit_code': 92, 'owned_root_waited': True, 'remaining_owned_pids': [], 'controlled_job_termination': True, 'includes_ShaderCompileWorker_descendants': True}}, 'Cold': {'proof': {'file': 'native_reserve_canopy3900_population_actual_v1_005/COLD_PROOF.json', 'bytes': 1245, 'sha256': '99052b32b1ef05a79f0f25b7f5672e96c5baee85fe5d74f0a17e14adb941433e'}, 'audit': {'file': 'native_reserve_canopy3900_population_audit_v1_005/Review/AUDIT.json', 'bytes': 18510, 'sha256': 'a8d6238fc1406680102f255ef1796b7856481dcc7534bcef219f27d21942e26e'}, 'population_proof': {'file': 'native_reserve_canopy3900_population_actual_v1_005/Review/HOST_FINAL_POPULATION_PROOF.json', 'bytes': 767, 'sha256': '8be9f860d2387527711389a8266d1acf4ca1dbb654cf4045f4ede550f00fa472'}, 'world_scope': 'NewProcess_Editor', 'groups': 141, 'instances': 3900, 'wall_seconds': 112.39100000000326, 'owned_reap': {'root_exit_code': 92, 'owned_root_waited': True, 'remaining_owned_pids': [], 'controlled_job_termination': True, 'includes_ShaderCompileWorker_descendants': True}}, 'Author_DDC': {'file': 'native_reserve_canopy3900_population_actual_v1_005/AUTHOR_DDC_SOURCE.json', 'bytes': 512889, 'sha256': '984c9759658de026f51c7abd959764d26aa7da302088233895f92dc79d8609ea'}, 'serialized_scene_observer_qualified': True, 'full_declared_group_identity_materials_culls_readiness_and_all_transforms_checked': True, 'pool_counts_are_not_visible_or_drawn': True, 'Game_art_or_FPS_qualified': False}
FIXED_CONTRACT={'schema': 'LivingTown.BoundedHismInspection.v1',
 'success_status': 'READ_ONLY_BOUNDED_NATIVE_HISM_SNAPSHOT',
 'error_status': 'ERROR',
 'fixed_caps': {'instances_and_sorted_entries': 20000,
                'actor_instance_members': 256,
                'effective_materials': 64},
 'native_subclasses_require_exact_parent_fields': True,
 'world_types': ['Editor', 'Game', 'PIE'],
 'pending_state_observed_without_repair': True,
 'finite_LOD_distance_scale_required': True,
 'read_preserves_package_and_map_dirty_flags': True,
 'host_binds_full_source_map_group_identity_and_transforms': True,
 'counts_are_pool_state_not_visible_or_drawn': True}
QUALIFICATIONS={'recorded_native_build': True,
 'recorded_structured_native_boundary': True,
 'original_dual_log_host_gate_passed': False,
 'portable_verifier_executes_Unreal': False,
 'authoring_or_HISM_repair_authority': False,
 'scene_or_Game_acceptance': False,
 'LOD_or_canopy_art_acceptance': False,
 'visible_instance_count': False,
 'GPU_or_FPS_improvement': False}
FORBIDDEN=('GEditor','FCommandLine::','BuildTreeIfOutdated(','FinishCompilation(','FlushRenderingCommands(','RegisterComponent(','SavePackage(','SetMaterial(','SetCullDistances(','Modify(','SpawnActor<','NewObject<','CreateWorld(')

def need(value,message):
    if not value:raise ValueError(message)

def sha(data):return hashlib.sha256(data).hexdigest()

def digest(rows):return sha(json.dumps(rows,sort_keys=True,separators=(',',':')).encode())

def read_json(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def relative(root,name):
    path=Path(name);need(not path.is_absolute()and '..'not in path.parts and ':'not in name and '\\'not in name,'Fixed portable relative path')
    candidate=Path(root)/path;need(candidate.resolve().is_relative_to(Path(root).resolve())and not candidate.is_symlink(),'Contained non-symlink input');return candidate

def checked(data,expected,label):need((len(data),sha(data))==expected,'Exact source bytes: '+label)

def validate_implementation(cpp,header):
    body=cpp.split('#if WITH_DEV_AUTOMATION_TESTS',1)[0]
    need(all(token not in body for token in FORBIDDEN),'Runtime reader has no author/build/register/flush/wait/save or editor-global authority')
    invariants=('IsInGameThread()','Component->IsA<UHierarchicalInstancedStaticMeshComponent>()','Component->IsTemplate()','CLASS_Native','HismInspectionOwner->GetWorld()!=HismInspectionWorld','HismInspectionComponent->GetOuter()!=HismInspectionOwner','EWorldType::Editor','EWorldType::Game','EWorldType::PIE','exact_parent_property_types_required','subclass_must_retain_exact_parent_fields','HismInspectionMaximumInstances=20000','HismInspectionMaximumMembers=256','HismInspectionMaximumMaterials=64','fixed_finite_count_cap_exceeded','read_changed_dirty_state','GetNumRenderInstances()','GetInstanceCount()','IsTreeFullyBuilt()','IsAsyncBuilding()')
    need(all(token in body for token in invariants),'Bounded native identity/thread/owner/world/field/readiness invariants')
    need(body.index('if(!FMath::IsFinite(HismInspectionDistanceScale))')<body.index('SetNumberField(TEXT("instance_LOD_distance_scale"),HismInspectionDistanceScale)'),'Finite scalar gate precedes JSON number')
    for name in ('NumBuiltInstances','InstanceCountToRender','SortedInstances','bEnableDensityScaling','bUseTranslatedInstanceSpace'):
        need('TEXT("'+name+'")'in body,'Exact native parent property binding: '+name)
    need('TEXT("operation_writes_or_repairs"),false'in body and 'TEXT("visible_instances_LOD_GPU_or_FPS_qualified"),false'in body,'Read-only pool evidence scope')
    need('owner_label_available' in body and '#if WITH_EDITOR'in body and 'GetActorLabel(false)'in body,'Editor label availability stays explicit')
    need(header.count('UFUNCTION(')==1 and 'static FString ReadHismComponent(UHierarchicalInstancedStaticMeshComponent* Component);'in header,'One typed read-only public API')
    need(cpp.count('#if WITH_DEV_AUTOMATION_TESTS')==1 and TEST in cpp,'Guarded native boundary test remains present')
    need(sum(cpp.count(x)for x in ('TestTrue(','TestFalse(','TestEqual(','TestNotNull('))==19,'Exactly19 source assertions, not19 fabricated raw events')
    need('quiet_NaN()'in cpp and 'infinity()'in cpp and 'Live owned unregistered native pending state'in cpp,'Meaningful nonfinite and live pending controls')

def validate_evidence(e):
    need(set(e)=={'schema','scope','qualified_native89_sha256','unchanged_baseline_native87_sha256','qualified_native_inputs','added_files','recorded_artifacts','actual_build','actual_boundary','original_host_failure','fixed_contract','scene_consumer','qualifications'},'Closed observer evidence fields')
    need(e['schema']=='LivingTown.BoundedHismObserverEvidence.v1'and e['scope']=='READ_ONLY_NATIVE_INSPECTION_UTILITY_NOT_AUTHORING_OR_PERFORMANCE','Observer utility evidence scope')
    need(e['qualified_native89_sha256']==NATIVE and e['unchanged_baseline_native87_sha256']==BASELINE,'Qualified historical source family')
    rows=e['qualified_native_inputs'];need(len(rows)==89 and len({x['file']for x in rows})==89 and digest(rows)==NATIVE,'Exact recorded89-input source manifest')
    need(all(set(x)=={'file','bytes','sha256'}for x in rows),'Closed recorded source rows');need({x['file']:(x['bytes'],x['sha256'])for x in e['added_files']}==SOURCES,'Only two additive native source files')
    before=[x for x in rows if x['file']not in SOURCES];need(len(before)==87 and digest(before)==BASELINE,'All87 old native inputs unchanged, including Build.cs and old observers')
    need(e['recorded_artifacts']==ARTIFACTS,'Exact retained build/boundary evidence identities')
    need(e['fixed_contract']==FIXED_CONTRACT and e['qualifications']==QUALIFICATIONS and all(type(x)is bool for x in e['qualifications'].values()),'No repair, scene, visible-count, art or FPS promotion')
    build=e['actual_build'];need(build['status']=='PASS_NATIVE_EDITOR_BUILD'and build['source87_exact']is True and build['seconds']==238.234,'Actual build/source summary')
    need(build['owned_reap']['root_exit_code']==0 and build['owned_reap']['owned_root_waited']is True and build['owned_reap']['remaining_owned_pids']==[],'Actual build ownership and reap')
    for name in ('peak_RSS_bytes','peak_private_bytes'):need(0<build[name]<16*2**30,'Actual bounded build memory')
    native=e['actual_boundary'];need(native['qualification']=='INDEPENDENT_STRUCTURED_NATIVE_BOUNDARY_EVIDENCE_ONLY'and native['test_name']==TEST and native['source_assertions']==19 and native['native_state']=='Success','One actual structured native boundary result')
    need(native['warnings']==native['errors']==native['raw_entry_count']==0 and native['duration_seconds']==0.0225025974214077,'Zero raw events/errors/warnings; no invented per-assertion transcript')
    need(native['actual_owned_PID']==29740 and native['device_instance_name']=='DESKTOP-CDF6A3A-29740'and native['device_instance']=='022663F741CFD2C55D0A72BE64084416'and native['RHI']=='D3D12 (SM6)','Actual current-owned PID/device/RHI binding')
    need(native['runtime_DLL_source89_and_original87_exact']is True and native['source_config_canonical32_owned_guards_exact']is True,'Actual source/DLL/config custody')
    need(native['owned_reap']['root_exit_code']==92 and native['owned_reap']['owned_root_waited']is True and native['owned_reap']['remaining_owned_pids']==[]and native['owned_reap']['controlled_job_termination']is True,'Actual controlled92 stop/wait, no stranded descendants')
    for name in ('peak_RSS_bytes','peak_private_bytes'):need(0<native[name]<16*2**30,'Actual bounded native-test memory')
    failure=e['original_host_failure'];need(failure['status']=='FAIL_RETAINED_UNCHANGED'and failure['raw_start_completion_counts']==[0,0]and failure['all_original_host_gates_passed']is False,'Original dual-log host gate remains failed')
    for name in ('parser_format_only_adapter_recovery','engine_rerun_for_audit','missing_events_replayed_or_fabricated'):need(failure[name]is False,'No requalification by fabricated/absent log events')
    scene=e['scene_consumer'];need(scene==SCENE_EXPECTED,'Exact recorded Editor Author/Cold observer consumer, without Game/art/FPS promotion')

def verify_recorded(root,e):
    for name,row in e['recorded_artifacts'].items():checked(relative(root,row['file']).read_bytes(),(row['bytes'],row['sha256']),name)
    raw=read_json(relative(root,ARTIFACTS['native_structured_result']['file']));need(raw['succeeded']==1 and all(raw[k]==0 for k in ('succeededWithWarnings','failed','notRun','inProcess')),'Retained native Automation terminal counts')
    need(len(raw['tests'])==1,'Exactly one actual native boundary case');test=raw['tests'][0];need(test['fullTestPath']==TEST and test['state']=='Success'and test['entries']==[]and test['warnings']==test['errors']==0,'Retained native success and raw event absence')
    need(raw['devices'][0]['instanceName']=='DESKTOP-CDF6A3A-29740','Retained current-owned PID device')
    log=relative(root,ARTIFACTS['boundary_raw_log']['file']).read_text(encoding='utf-8-sig',errors='replace')
    counts=[sum(token in line and'Path={'+TEST+'}'in line for line in log.splitlines())for token in ('Test Started.','Test Completed. Result={Success}')];need(counts==[0,0],'Preserve actual missing dual-log events, not a parser adapter')
    report=read_json(relative(root,ARTIFACTS['boundary_process_report']['file']));need(report['owned_reap']==e['actual_boundary']['owned_reap']and report['owned_root_pid']==29740,'Retained report ownership/PID')
    saved=read_json(relative(root,SCENE_ARTIFACTS['scene_saved151']['file']));need(len(saved['files'])==151,'Retained exact151 saved scene source closure')
    for phase in ('Author','Cold'):
        audit=read_json(relative(root,SCENE_ARTIFACTS['scene_'+phase+'_audit']['file']));p=audit['native_population_replay'];need(p['groups']==141 and p['instances']==3900 and audit['all150_nonMap_dependencies_including372_and7LODs_exact']is True and all(audit['guards'].values()),'Recorded serialized native groups/source/custody')
        need(audit['owned_reap']==e['scene_consumer'][phase]['owned_reap'],'Recorded Editor phase ownership/reap')
    for phase in ('Author','Review'):
        proof=read_json(relative(root,SCENE_ARTIFACTS['scene_'+phase+'_population_proof']['file']));need(proof['groups']==141 and proof['instances']==3900 and proof['visible_leaf_drawn_LOD_Game_GPU_art_qualified']is False,'Actual pool source evidence is not visible/Game/art/GPU proof')
    for row in e['actual_build']['runtime_binary_closure']:checked(relative(root,row['file']).read_bytes(),(row['bytes'],row['sha256']),'Retained native binary closure')

def self_test(cpp,header,e):
    passed=[]
    def rejects(name,fn):
        try:fn()
        except(ValueError,KeyError,TypeError):passed.append(name);return
        raise ValueError('Negative accepted: '+name)
    for name,change in [('source_manifest_tamper',lambda x:x['qualified_native_inputs'][0].__setitem__('sha256','0'*64)),('wrong_source_family',lambda x:x.__setitem__('qualified_native89_sha256',BASELINE)),('false_host_pass',lambda x:x['original_host_failure'].__setitem__('all_original_host_gates_passed',True)),('invented_log_events',lambda x:x['original_host_failure'].__setitem__('raw_start_completion_counts',[1,1])),('parser_recovery_claim',lambda x:x['original_host_failure'].__setitem__('parser_format_only_adapter_recovery',True)),('boundary_wrong_PID',lambda x:x['actual_boundary'].__setitem__('actual_owned_PID',1)),('boundary_false_events',lambda x:x['actual_boundary'].__setitem__('raw_entry_count',19)),('stranded_owned_process',lambda x:x['actual_boundary']['owned_reap'].__setitem__('remaining_owned_pids',[1])),('wrong_cap',lambda x:x['fixed_contract']['fixed_caps'].__setitem__('instances_and_sorted_entries',20001)),('false_FPS',lambda x:x['qualifications'].__setitem__('GPU_or_FPS_improvement',True)),('false_art',lambda x:x['qualifications'].__setitem__('LOD_or_canopy_art_acceptance',True)),('wrong_consumer_Cold_hash',lambda x:x['scene_consumer']['Cold']['proof'].__setitem__('sha256','0'*64)),('false_consumer_Game',lambda x:x['scene_consumer'].__setitem__('Game_art_or_FPS_qualified',True)),('wrong_consumer_count',lambda x:x['scene_consumer']['Author'].__setitem__('instances',3901))]:
        bad=copy.deepcopy(e);change(bad);rejects(name,lambda bad=bad:validate_evidence(bad))
    rejects('source_byte_tamper',lambda:checked((cpp+'\n').encode(),SOURCES[CPP],CPP))
    rejects('runtime_mutation',lambda:validate_implementation(cpp.replace('using namespace LivingTownHismInspectionInternal;','using namespace LivingTownHismInspectionInternal;\n RegisterComponent();',1),header))
    rejects('finite_scalar_gate_removed',lambda:validate_implementation(cpp.replace('if(!FMath::IsFinite(HismInspectionDistanceScale))','if(false)'),header))
    return passed

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--repository-root',type=Path,default=ROOT);ap.add_argument('--qualified-source-root',type=Path);ap.add_argument('--recorded-evidence-root',type=Path);ap.add_argument('--self-test',action='store_true');a=ap.parse_args();root=a.repository_root.resolve();e=read_json(relative(root,EVIDENCE));validate_evidence(e)
    data={name:relative(root,name).read_bytes()for name in SOURCES}
    for name,value in data.items():checked(value,SOURCES[name],name)
    cpp=data[CPP].decode();header=data[HEADER].decode();validate_implementation(cpp,header)
    if a.qualified_source_root:
        for row in e['qualified_native_inputs']:checked(relative(a.qualified_source_root,row['file']).read_bytes(),(row['bytes'],row['sha256']),row['file'])
    if a.recorded_evidence_root:verify_recorded(a.recorded_evidence_root,e)
    negatives=self_test(cpp,header,e)if a.self_test else[]
    print(json.dumps({'status':'PASS_SOURCE_RECORDED_BOUNDARY_AND_EXACT_EDITOR_SCENE_OBSERVER','native_added_files':2,'source_assertions':19,'negative_controls':negatives,'retained_original_artifacts_checked':a.recorded_evidence_root is not None,'qualified89_source_checked':a.qualified_source_root is not None,'original_dual_log_host_gate':'FAIL_RETAINED','native_scene_consumer':'RECORDED_EDITOR_AUTHOR_AND_COLD_ONLY','engine_compiler_or_asset_mutation_executed':False,'GPU_art_or_FPS_accepted':False}))
if __name__=='__main__':main()
