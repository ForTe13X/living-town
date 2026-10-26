"""No-engine source tests; optionally replay a real native discovery transcript."""
from common import *
from run_bootstrap import main as bootstrap_main,owned_layout,command_and_environment,require_hardware_rhi,preserve_guard,source_bindings,copy_project_for_bootstrap,RSS_LIMIT,PRIVATE_LIMIT,STARTUP_SECONDS,TOTAL_SECONDS
from build_native_module import validate_native_build_receipt,native_inputs,engine_identity,file_record,digest,SCHEMA as NATIVE_SCHEMA,PASS as NATIVE_PASS
from process_inventory import validate_external,require_idle_shape
from mcp_client import Client,parse_catalog,free_port
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import patch
import argparse,os,socket,shutil,struct,io,contextlib

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--scratch-root',type=Path,required=True);parser.add_argument('--actual-run-root',type=Path);parser.add_argument('--native-build-receipt',type=Path);parser.add_argument('--actual-engine-root',type=Path);args=parser.parse_args();scratch=args.scratch_root.resolve();need(not scratch.exists(),'Preserve prior test output');scratch.mkdir(parents=True);checks=[]
 def check(name,ok):need(ok,name);checks.append(name)
 def refuse(name,call):
  failed=False
  try:call()
  except (ValueError,OSError):failed=True
  check(name,failed)
 source=scratch/'fake_repository';engine=scratch/'fake_engine';(source/'unreal').mkdir(parents=True);write(source/'unreal/LivingTown.uproject',{'FileVersion':3});(engine/'Engine/Build').mkdir(parents=True);write(engine/'Engine/Build/Build.version',{'MajorVersion':5,'MinorVersion':8,'PatchVersion':4,'Changelist':58902052})
 options=SimpleNamespace(source_root=source,engine_root=engine,artifact_root=scratch/'artifacts',cache_root=scratch/'separate_cache',port=24681,preserve_path=[]);resolved=owned_layout(options);check('explicit_source_engine_artifact_cache_and_port_resolve_without_creation',resolved[:4]==tuple(p.resolve()for p in [source,engine,options.artifact_root,options.cache_root])and not options.artifact_root.exists()and not options.cache_root.exists())
 for name,field,value in [('source_output_refused','artifact_root',source/'owned'),('engine_output_refused','artifact_root',engine/'owned'),('invalid_port_refused','port',0)]:
  wrong=deepcopy(options);setattr(wrong,field,value);refuse(name,lambda wrong=wrong:owned_layout(wrong))
 wrong=deepcopy(options);wrong.cache_root=scratch/'fresh_cache_parent';wrong.artifact_root=wrong.cache_root/'output';refuse('fresh_cache_ancestor_of_artifact_refused',lambda:owned_layout(wrong))
 binary=engine/'Engine/Binaries/Win64';binary.mkdir(parents=True)
 for name in ['UnrealEditor.exe','ShaderCompileWorker.exe']:(binary/name).write_bytes(b'not-an-executable source binding fixture only')
 refuse('missing_installed_required_plugin_refused',lambda:source_bindings(source,engine))
 for plugin in ['Experimental/ModelContextProtocol','Experimental/ToolsetRegistry','Experimental/Toolsets/EditorToolset','Experimental/PythonScriptPlugin','Interchange/Editor']:
  root=engine/'Engine/Plugins'/plugin;(root/'Binaries/Win64').mkdir(parents=True);write(root/'Fixture.uplugin',{'FileVersion':3});(root/'Binaries/Win64/Fixture.dll').write_bytes(b'not-a-library source binding fixture only')
 plugin_python=engine/'Engine/Plugins/Experimental/Toolsets/EditorToolset/Content/Python';plugin_python.mkdir(parents=True);script=plugin_python/'fixture.py';script.write_text('value = 1\n',encoding='utf-8');bound=source_bindings(source,engine);check('installed_plugin_python_sources_are_bound',binding(script)in bound);script.write_text('value = 2\n',encoding='utf-8');refuse('bound_plugin_Python_source_mutation_refused',lambda:verify(bound));script.write_text('value = 1\n',encoding='utf-8')
 command,env,private=command_and_environment(engine,options.artifact_root/'Project',options.artifact_root,options.cache_root,24681);check('requested_engine_project_and_port_used',command[0]==str(engine/'Engine/Binaries/Win64/UnrealEditor.exe')and command[1]==str(options.artifact_root/'Project/LivingTown.uproject')and'-ModelContextProtocolPort=24681'in command);check('offscreen_keeps_hardware_path_without_null_or_quality_switch',command.count('-RenderOffScreen')==1 and not any(x.lower()in ['-nullrhi','-d3d11','-sm5']for x in command));check('all_private_shader_temp_Python_DDC_paths_in_explicit_cache',all(Path(env[key]).is_relative_to(options.cache_root)for key in ['TEMP','TMP','APPDATA','LOCALAPPDATA','PYTHONPYCACHEPREFIX','UE-LocalDataCachePath']));check('controlled_Python_env_removes_ambient_paths',not any(key in env for key in ['PYTHONHOME','PYTHONPATH','UE_PYTHONPATH'])and env['PYTHONDONTWRITEBYTECODE']=='1'and env['PYTHONNOUSERSITE']=='1');check('same_finite_owned_tree_caps',RSS_LIMIT==14*1024**3 and PRIVATE_LIMIT==20*1024**3 and STARTUP_SECONDS==600 and TOTAL_SECONDS==720)
 expected={'pid':4321,'name':'UnrealEditor.exe','creation_utc':'2026-01-01T00:00:00.0000000Z','exe':str(engine/'Engine/Binaries/Win64/UnrealEditor.exe'),'project_args':[],'has_mcp_flag':False,'main_window_title':'Unreal Engine 5.8','main_window_handle':987,'listening_ports':[1985]};queue=[{'ProcessId':4321,'Name':'UnrealEditor.exe'}];validate_external(expected,expected,queue,24681);checks.append('explicit_runtime_idle_editor_fingerprint_accepts_exact_identity')
 for key,value in [('pid',4322),('creation_utc','changed'),('exe',str(engine/'other/UnrealEditor.exe')),('project_args',['SomeProject.uproject']),('has_mcp_flag',True),('main_window_title','Opened project'),('listening_ports',[24681])]:
  bad=deepcopy(expected);bad[key]=value;refuse('changed_external_'+key+'_refused',lambda bad=bad:validate_external(bad,expected,queue,24681))
 refuse('additional_unowned_worker_refused',lambda:validate_external(expected,expected,queue+[{'ProcessId':9999,'Name':'ShaderCompileWorker.exe'}],24681));refuse('incomplete_fingerprint_refused',lambda:require_idle_shape({'pid':4321}))
 entries=parse_catalog('- First: description\ncontinued line\n- Second: another\n');check('multiline_catalog_retains_only_actual_headers',[r['name']for r in entries]==['First','Second']and entries[0]['description']=='description\ncontinued line');refuse('orphan_catalog_continuation_refused',lambda:parse_catalog('orphan\n- A: d'));refuse('duplicate_catalog_names_refused',lambda:parse_catalog('- A: d\n- A: e'))
 for url in ['http://example.com:24681/mcp','http://127.0.0.1:24681/mcp?x=1','http://name:secret@127.0.0.1:24681/mcp','file:///mcp']:refuse('non_loopback_or_noncanonical_URL_refused_'+str(len(checks)),lambda url=url:Client(scratch,lambda:None,url))
 with socket.socket()as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 check('configured_free_port_actually_binds',free_port(port)['port']==port)
 fixture=scratch/'preserved.dat';fixture.write_bytes(b'original');before=preserve_guard([fixture]);fixture.write_bytes(b'changed!');check('actual_private_byte_change_detected',preserve_guard([fixture])!=before);fixture.write_bytes(b'original');check('actual_private_byte_restore_matches',preserve_guard([fixture])==before)
 # Staging-contract fixtures are deliberately not an engine/DLL execution proof.
 def preflight_case(name,receipt=None):
  output=scratch/name;captured=io.StringIO();argv=['--source-root',str(source),'--engine-root',str(engine),'--artifact-root',str(output)]
  if receipt is not None:argv.extend(['--native-build-receipt',str(receipt)])
  with patch('run_bootstrap.external_state',return_value=None),patch('run_bootstrap.free_port',return_value={'port':19841}),patch('run_bootstrap.OwnedJob')as spawn,contextlib.redirect_stdout(captured):bootstrap_main(argv)
  result=json.loads(captured.getvalue());check(name+'_passes_cli_preflight_without_editor',result['status']=='PREFLIGHT_NO_ENGINE'and not spawn.called and not output.exists());check(name+'_native_receipt_state_matches_project',(result['native_build']is not None)==(receipt is not None))
 check('content_only_needs_no_build_receipt',validate_native_build_receipt(source,engine)is None)
 preflight_case('content_only_cli')
 stale=source/'unreal/Binaries/Win64';stale.mkdir(parents=True);(stale/'stale.dll').write_bytes(b'untrusted preexisting binary')
 content_copy=scratch/'content_only_copy';check('content_only_copy_excludes_all_ambient_binaries',copy_project_for_bootstrap(source,engine,content_copy)==[]and not(content_copy/'Binaries').exists())
 canonical=Path(__file__).resolve().parents[2];shutil.copytree(canonical/'unreal/Source',source/'unreal/Source')
 write(source/'unreal/LivingTown.uproject',{'FileVersion':3,'Modules':[{'Name':'LivingTownNative','Type':'Runtime','LoadingPhase':'Default'}]})
 refuse('native_project_without_receipt_refused',lambda:validate_native_build_receipt(source,engine))
 with patch('run_bootstrap.OwnedJob')as spawn:
  refuse('native_cli_refuses_missing_build_before_editor_phase',lambda:bootstrap_main(['--source-root',str(source),'--engine-root',str(engine),'--artifact-root',str(scratch/'must_not_launch'),'--execute']))
  check('missing_native_receipt_never_spawned_editor',not spawn.called)
 refuse('native_copy_without_receipt_refused_before_copy',lambda:copy_project_for_bootstrap(source,engine,scratch/'must_not_copy'))
 check('refused_native_copy_created_no_project',(scratch/'must_not_copy').exists()is False)
 for rel in ['Engine/Binaries/Win64/UnrealEditor-Core.dll','Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll']:
  p=engine/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'not an engine binary; staging fixture only')
 write(engine/'Engine/Binaries/Win64/UnrealEditor.modules',{'BuildId':'fixture-installed-editor','Modules':{}})
 artifact=scratch/'native_build_fixture';runtime=artifact/'project/Binaries/Win64';runtime.mkdir(parents=True);(artifact/'Build').mkdir()
 pe=bytearray(512);pe[:2]=b'MZ';struct.pack_into('<I',pe,60,128);pe[128:132]=b'PE\0\0';struct.pack_into('<H',pe,132,0x8664);struct.pack_into('<H',pe,150,0x2000)
 dll=runtime/'UnrealEditor-LivingTownNative.dll';dll.write_bytes(pe);module=runtime/'UnrealEditor.modules';write(module,{'BuildId':'fixture-installed-editor','Modules':{'LivingTownNative':dll.name}})
 log=artifact/'Build/UBT.log';log.write_text('Fixture only, not actual UBT execution.\nLivingTownEditor\nLink [x64] UnrealEditor-LivingTownNative.dll\nResult: Succeeded\n')
 inputs=native_inputs(source);packet={'schema':NATIVE_SCHEMA,'status':NATIVE_PASS,'workcopy_sources_exact':True,'project':{'file':'LivingTown.uproject','editor_target':'LivingTownEditor','modules':['LivingTownNative']},'source':{'inputs':inputs,'sha256':digest(inputs)},'engine':engine_identity(engine),'build':{'root_exit_code':0,'owned_descendants_reaped':True,'log':file_record(log,'Build/UBT.log')},'runtime_files':[file_record(module,'project/Binaries/Win64/UnrealEditor.modules'),file_record(dll,'project/Binaries/Win64/'+dll.name)]}
 receipt=artifact/'BUILD_RECEIPT.json';write(receipt,packet);qualified=validate_native_build_receipt(source,engine,receipt)
 preflight_case('native_cli',receipt)
 (runtime/'arbitrary_stale.dll').write_bytes(b'never stage this')
 staged=scratch/'native_verified_copy';staged_rows=copy_project_for_bootstrap(source,engine,staged,qualified)
 check('only_exact_receipted_runtime_closure_staged',{p.name for p in(staged/'Binaries/Win64').iterdir()}=={dll.name,module.name}and len(staged_rows)==2)
 check('staged_dll_and_module_metadata_match_build_bytes',sha(staged/'Binaries/Win64'/dll.name)==sha(dll)and sha(staged/'Binaries/Win64'/module.name)==sha(module))
 refuse('existing_native_stage_never_overwritten',lambda:copy_project_for_bootstrap(source,engine,staged,qualified))
 for name,change in [('failed_build_receipt',lambda p:p.update(status='FAIL_PRESERVED_NATIVE_BUILD')),('mutated_compiled_workcopy',lambda p:p.update(workcopy_sources_exact=False)),('unreaped_build',lambda p:p['build'].update(owned_descendants_reaped=False)),('wrong_editor_target',lambda p:p['project'].update(editor_target='UnrealGame')),('runtime_path_escape',lambda p:p['runtime_files'][1].update(file='../outside.dll')),('stale_engine_identity',lambda p:p['engine'].update(build_id='different'))]:
  bad=deepcopy(packet);change(bad);write(receipt,bad);refuse(name+'_refused',lambda:validate_native_build_receipt(source,engine,receipt))
 write(receipt,packet);changed=source/'unreal/Source/LivingTownNative/Private/LivingTownNative.cpp';original=changed.read_bytes();changed.write_bytes(original+b'\n');refuse('changed_native_source_refuses_old_dll',lambda:validate_native_build_receipt(source,engine,receipt));changed.write_bytes(original)
 original=dll.read_bytes();dll.write_bytes(original+b'changed');refuse('changed_dll_bytes_refused',lambda:validate_native_build_receipt(source,engine,receipt));dll.write_bytes(original)
 write(module,{'BuildId':'wrong-build','Modules':{'LivingTownNative':dll.name}});bad=deepcopy(packet);bad['runtime_files'][0]=file_record(module,'project/Binaries/Win64/UnrealEditor.modules');write(receipt,bad);refuse('matching_hash_but_wrong_module_buildid_refused',lambda:validate_native_build_receipt(source,engine,receipt))
 write(module,{'BuildId':'fixture-installed-editor','Modules':{'LivingTownNative':'unlisted.dll'}});bad['runtime_files'][0]=file_record(module,'project/Binaries/Win64/UnrealEditor.modules');write(receipt,bad);refuse('module_metadata_cannot_redirect_dll',lambda:validate_native_build_receipt(source,engine,receipt))
 write(module,{'BuildId':'fixture-installed-editor','Modules':{'LivingTownNative':dll.name}});wrong_machine=bytearray(pe);struct.pack_into('<H',wrong_machine,132,0x14c);dll.write_bytes(wrong_machine);bad=deepcopy(packet);bad['runtime_files'][1]=file_record(dll,'project/Binaries/Win64/'+dll.name);write(receipt,bad);refuse('x86_binary_with_matching_hash_refused',lambda:validate_native_build_receipt(source,engine,receipt));dll.write_bytes(pe);write(receipt,packet)
 log.write_text('LivingTownEditor never finished');bad=deepcopy(packet);bad['build']['log']=file_record(log,'Build/UBT.log');write(receipt,bad);refuse('bound_but_unsuccessful_ubt_log_refused',lambda:validate_native_build_receipt(source,engine,receipt))
 if args.native_build_receipt:
  need(args.actual_engine_root is not None,'Actual native replay needs --actual-engine-root');actual_native=validate_native_build_receipt(canonical,args.actual_engine_root,args.native_build_receipt);actual_copy=scratch/'actual_native_consumer_copy';rows=copy_project_for_bootstrap(canonical,args.actual_engine_root,actual_copy,actual_native)
  check('actual_canonical_build_receipt_stages_matching_binaries_without_editor',len(rows)==len(actual_native['runtime_files']) and all(Path(r['path']).is_file()for r in rows));write(scratch/'ACTUAL_NATIVE_STAGING.json',{'verified_build':actual_native,'staged_files':rows,'no_engine_launched':True})
 if args.actual_run_root:
  actual=args.actual_run_root.resolve();report=read(actual/'REPORT.json');schema=read(actual/'ACTUAL_DISCOVERED_MAP.json');transcript=read(actual/'HTTP_TRANSCRIPT.json');catalog=read(actual/'ACTUAL_TOOLSET_CATALOG.json')['text'];check('actual_qualified_report_and_schema_scope',report['status']=='PASS_ACTUAL_NATIVE_MCP_DISCOVERY_IMPORT_PENDING'and report['owned_reap']['root_exit_code']==92 and bool(schema['actual_toolsets']) and set(schema['actual_toolsets'])==set(report['actual_toolsets']));rhi=require_hardware_rhi(actual/'UnrealEditor.log','AMD Radeon(TM) 8060S Graphics');check('actual_hardware_RHI_reader_parity',rhi['hardware_D3D12_SM6_initialization_demonstrated']);refuse('explicit_wrong_actual_GPU_refused',lambda:require_hardware_rhi(actual/'UnrealEditor.log','Wrong GPU'))
  actual_log=(actual/'UnrealEditor.log').read_text(encoding='utf-8-sig');software=scratch/'software_adapter_refusal.log';software.write_text(actual_log.replace('Chosen D3D12 Adapter Id = 0','Chosen D3D12 Adapter Id = 1'),encoding='utf-8');refuse('actual_recorded_WARP_adapter_selection_refused',lambda:require_hardware_rhi(software));failure=scratch/'device_failure_refusal.log';failure.write_text(actual_log+'\nDXGI_ERROR_DEVICE_REMOVED\n',encoding='utf-8');refuse('recorded_device_failure_refused',lambda:require_hardware_rhi(failure));sm5=scratch/'SM5_refusal.log';sm5.write_text(actual_log.replace('Using Highest Feature Level of D3D12: SM6','Using Highest Feature Level of D3D12: SM5'),encoding='utf-8');refuse('SM5_initialization_refused',lambda:require_hardware_rhi(sm5))
  replay=scratch/'replay';replay.mkdir();sent=[];endpoint='http://127.0.0.1:24681/mcp';tool_list=next(row['response']['result']for row in transcript if row['request']['method']=='tools/list');init=next(row['response']['result']for row in transcript if row['request']['method']=='initialize')
  class Response:
   def __init__(self,value,status=200,initialize=False):self.body=json.dumps(value).encode()if value is not None else b'';self.status=status;self.headers={'Content-Type':'application/json',**({'Mcp-Session-Id':'offline-recorded-response-replay'}if initialize else{})}
   def __enter__(self):return self
   def __exit__(self,*args):pass
   def read(self,count):return self.body[:count]
  def urlopen(request,timeout):
   check('replay_request_uses_explicit_endpoint_'+str(len(sent)),request.full_url==endpoint);value=json.loads(request.data);sent.append(value);method=value['method']
   if method=='notifications/initialized':return Response(None,202)
   if method=='initialize':return Response({'jsonrpc':'2.0','id':value['id'],'result':init},initialize=True)
   if method=='tools/list':result=tool_list
   elif value['params']['name']=='list_toolsets':result={'content':[{'type':'text','text':catalog}]}
   else:need(value['params']['name']=='describe_toolset','Unexpected dispatch in replay');result=schema['actual_toolsets'][value['params']['arguments']['toolset_name']]['raw_result']
   return Response({'jsonrpc':'2.0','id':value['id'],'result':result})
  with patch('urllib.request.urlopen',urlopen):client=Client(replay,lambda:None,endpoint);result=client.discover()
  check('all_actual_schemas_replay_on_parameterized_endpoint',set(client.toolsets)==set(schema['actual_toolsets'])and result['actual_schema_count']==len(schema['actual_toolsets']));check('replay_no_import_or_general_tool_dispatch',all(row['params']['name']in ['list_toolsets','describe_toolset']for row in sent if row['method']=='tools/call'))
 write(scratch/'REPORT.json',{'status':'PASS_SOURCE_PARAMETERIZATION_AND_OPTIONAL_ACTUAL_REPLAY_NO_ENGINE','checks':len(checks),'names':checks,'actual_replay_supplied':args.actual_run_root is not None,'actual_native_build_replayed':args.native_build_receipt is not None,'no_engine_launched':True});print(json.dumps({'status':'PASS','checks':len(checks)}))
if __name__=='__main__':main()
