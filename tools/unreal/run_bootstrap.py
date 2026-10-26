"""Reproducible, finite native MCP discovery. Preflight starts no engine."""
from common import *
from owned_job import OwnedJob
from mcp_client import Client,free_port
from process_inventory import external_state,editor_queue
from build_native_module import validate_native_build_receipt,stage_native_binaries
import argparse,os,time,traceback,shutil,threading,urllib.error,re

TRANSIENT={'Saved','Intermediate','DerivedDataCache','Binaries','.vs','__pycache__'}
RSS_LIMIT=14*1024**3;PRIVATE_LIMIT=20*1024**3;STARTUP_SECONDS=600;TOTAL_SECONDS=720

def preserve_guard(extra_paths=()):
 """Same qualified byte guard, with environment-derived roots and explicit extras."""
 roots=[Path(os.environ['APPDATA'])/'Blender Foundation',Path(os.environ['LOCALAPPDATA'])/'Blender Foundation',Path(os.environ['APPDATA'])/'Godot/app_userdata',*map(Path,extra_paths)];records=[]
 for number,directory in enumerate(roots):
  need(not directory.is_symlink(),'Private userdata root symlink requires explicit review')
  if directory.is_file():records.append([number,'',directory.stat().st_size,sha(directory)])
  elif directory.exists():
   for path in sorted(directory.rglob('*')):
    need(not path.is_symlink(),'Private userdata symlink requires explicit review')
    if path.is_file():records.append([number,path.relative_to(directory).as_posix(),path.stat().st_size,sha(path)])
 return {'files':len(records),'aggregate_sha256':hashlib.sha256(json.dumps(records,ensure_ascii=True,separators=(',',':')).encode()).hexdigest()}

def require_hardware_rhi(log,expected_gpu_name=None):
 text=Path(log).read_text(encoding='utf-8-sig',errors='replace');required=['Using Default RHI: D3D12','Using Highest Feature Level of D3D12: SM6','Creating D3D12 RHI with Max Feature Level SM6']
 need(all(token in text for token in required),'Actual D3D12/SM6 initialization not demonstrated')
 chosen=re.search(r'Chosen D3D12 Adapter Id = (\d+)',text);need(chosen,'Actual chosen D3D12 adapter absent')
 adapter=re.search(r'Found D3D12 adapter '+chosen.group(1)+r': (.*?) \(VendorId: ([0-9A-Fa-f]+),',text);need(adapter,'Actual chosen adapter identity absent');name,vendor=adapter.groups();need(vendor.lower()!='1414'and'Microsoft Basic Render Driver'not in name,'Software/WARP adapter is not hardware qualification')
 if expected_gpu_name is not None:need(name==expected_gpu_name,'Actual hardware adapter differs from explicit expected GPU')
 need(not any(token in text for token in ['GPU crash detected','DXGI_ERROR_DEVICE_REMOVED','GPU Crashed or D3D Device Removed.']),'Actual GPU/device failure remains')
 return {'actual_log':binding(log),'chosen_adapter_index':int(chosen.group(1)),'chosen_adapter_name':name,'chosen_adapter_vendor_hex':vendor,'hardware_D3D12_SM6_initialization_demonstrated':True,'offscreen_launch_requested':True,'NullRHI_used':False,'import_render_quality_or_Lumen_Nanite_qualification':False}

def source_bindings(source_root,engine_root,fingerprint_path=None,native_build=None):
 paths=[]
 for root in [source_root/'unreal',source_root/'tools/unreal']:
  for path in root.rglob('*'):
   if path.is_file()and not any(part in TRANSIENT for part in path.relative_to(root).parts):need(not path.is_symlink(),'Source symlink requires review');paths.append(path)
 paths.extend([engine_root/'Engine/Build/Build.version',engine_root/'Engine/Binaries/Win64/UnrealEditor.exe',engine_root/'Engine/Binaries/Win64/ShaderCompileWorker.exe'])
 for plugin in ['Experimental/ModelContextProtocol','Experimental/ToolsetRegistry','Experimental/Toolsets/EditorToolset','Experimental/PythonScriptPlugin','Interchange/Editor']:
  directory=engine_root/'Engine/Plugins'/plugin;descriptors=list(directory.glob('*.uplugin'));dlls=list((directory/'Binaries/Win64').glob('*.dll'));need(len(descriptors)==1 and dlls,'Required installed editor plugin/compiled DLL absent: '+plugin);paths.extend(descriptors);paths.extend(dlls);paths.extend((directory/'Content/Python').rglob('*.py'))
 if fingerprint_path is not None:paths.append(fingerprint_path)
 if native_build is not None:paths.extend(Path(row['path'])for row in native_build['bound_files'])
 return [binding(path)for path in sorted(set(paths))]

def copy_project_for_bootstrap(source,engine,project,native_build=None):
 """Stage source and only an explicitly verified native runtime closure."""
 need(not Path(project).exists(),'Bootstrap project copy must be fresh')
 names=read(Path(source)/'unreal/LivingTown.uproject').get('Modules',[])
 need(not names or native_build is not None,'Native project requires a verified build before staging')
 need(names or native_build is None,'Content-only project cannot receive unrelated native binaries')
 if native_build is not None:need(native_build['source_root']==str(Path(source).resolve())and native_build['engine_root']==str(Path(engine).resolve()),'Verified build belongs to another source/engine root')
 shutil.copytree(Path(source)/'unreal',project,ignore=shutil.ignore_patterns(*TRANSIENT))
 return stage_native_binaries(project,native_build)

def owned_layout(args):
 source=args.source_root.resolve();engine=args.engine_root.resolve();out=args.artifact_root.resolve();cache=(args.cache_root or out/'cache').resolve()
 need((source/'unreal/LivingTown.uproject').is_file(),'source-root must contain unreal/LivingTown.uproject')
 for path in [out,cache]:
  need(not path.exists(),'Preserve existing artifact/cache output: '+str(path))
  need(not path.is_relative_to(source)and not path.is_relative_to(engine),'Outputs must be outside repository/engine installation')
  need(not source.is_relative_to(path)and not engine.is_relative_to(path),'Output cannot contain source or installation')
 need(out!=cache,'Cache root must be a separate owned directory')
 need(not out.is_relative_to(cache),'Cache root cannot contain the artifact root')
 protected=[Path(os.environ['APPDATA'])/'Blender Foundation',Path(os.environ['LOCALAPPDATA'])/'Blender Foundation',Path(os.environ['APPDATA'])/'Godot/app_userdata',Path(os.environ['LOCALAPPDATA'])/'UnrealEngine',Path(os.environ['LOCALAPPDATA'])/'UnrealEditor',*args.preserve_path]
 for path in [out,cache]:need(not any(path.is_relative_to(root.resolve())for root in protected),'Owned output cannot be inside an original user archive/profile')
 need(1<=args.port<=65535,'Valid TCP port required')
 version=read(engine/'Engine/Build/Build.version');need((version['MajorVersion'],version['MinorVersion'],version['PatchVersion'],version['Changelist'])==(5,8,4,58902052),'This source is qualified against UE5.8.4/58902052; requalify a different installation')
 return source,engine,out,cache,version

def command_and_environment(engine,project,out,cache,port):
 private=cache/'private';env={k:v for k,v in os.environ.items()if not(k.upper().startswith('PYTHON')or k.upper()=='UE_PYTHONPATH')}
 for name in ['TEMP','TMP','APPDATA','LOCALAPPDATA']:env[name]=str(private/name)
 env.update(PYTHONDONTWRITEBYTECODE='1',PYTHONNOUSERSITE='1',PYTHONPYCACHEPREFIX=str(private/'PythonCache'),LIVING_TOWN_BOOTSTRAP_OUTPUT=str(out));env['UE-LocalDataCachePath']=str(cache/'DerivedDataCache');env['UE-SharedDataCachePath']='None';env['UE-ZenSharedDataCacheHost']='None'
 command=[str(engine/'Engine/Binaries/Win64/UnrealEditor.exe'),str(project/'LivingTown.uproject'),'/Engine/Maps/Entry','-ModelContextProtocolStartServer',f'-ModelContextProtocolPort={port}','-unattended','-nosplash','-nop4','-NoSound',f'-UserDir={private/"User"}',f'-ShaderWorkingDir={private/"ShaderWorking"}',f'-ShaderCompileWorkerCrashLogsDir={private/"ShaderCrashes"}',f'-abslog={out/"UnrealEditor.log"}','-DDC=LivingTownPilot',f'-LocalDataCachePath={cache/"DerivedDataCache"}','-NoLiveCoding','-RenderOffScreen']
 for category in ['Engine','Editor','EditorSettings','EditorPerProjectUserSettings','Game','GameUserSettings','Input','Scalability']:command.append(f'-{category}INI={private/"Config"/(category+".ini")}')
 return command,env,private

def main(argv=None):
 parser=argparse.ArgumentParser();parser.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[2]);parser.add_argument('--engine-root',type=Path,required=True);parser.add_argument('--artifact-root',type=Path,required=True);parser.add_argument('--cache-root',type=Path);parser.add_argument('--port',type=int,default=19841);parser.add_argument('--external-editor-fingerprint',type=Path);parser.add_argument('--native-build-receipt',type=Path);parser.add_argument('--preserve-path',type=Path,action='append',default=[]);parser.add_argument('--expected-gpu-name');parser.add_argument('--execute',action='store_true');args=parser.parse_args(argv)
 source,engine,out,cache,version=owned_layout(args);native=validate_native_build_receipt(source,engine,args.native_build_receipt);records=source_bindings(source,engine,args.external_editor_fingerprint,native);port=free_port(args.port);external=external_state(args.external_editor_fingerprint,args.port);project=out/'Project';command,env,private=command_and_environment(engine,project,out,cache,args.port)
 if not args.execute:print(json.dumps({'status':'PREFLIGHT_NO_ENGINE','source_root':str(source),'engine_root':str(engine),'artifact_root':str(out),'cache_root':str(cache),'source_bindings':len(records),'native_build':native,'actual_free_loopback_bind':port,'external_editor':external,'command':command,'total_deadline_seconds':TOTAL_SECONDS,'import_executed':False,'compilation_in_editor_phase':False}));return
 out.mkdir(parents=True);cache.mkdir(parents=True);staged_native=copy_project_for_bootstrap(source,engine,project,native);verify(records);write(out/'NATIVE_BINARY_STAGING.json',{'native_build':native,'staged_files':staged_native,'compilation_in_editor_phase':False})
 for name in ['User','ShaderWorking','Config','ShaderCrashes','PythonCache','TEMP','TMP','APPDATA','LOCALAPPDATA']:(private/name).mkdir(parents=True)
 original_private=preserve_guard(args.preserve_path);system_drive=Path(os.environ.get('SystemDrive','C:')+'/');disk_before=shutil.disk_usage(system_drive).free;source_meta={str(p):tree_stats(p)for p in [source/'game/scripts',source/'game/data',source/'tools']};user=Path(os.environ['LOCALAPPDATA']);ue_roots=[user/'UnrealEngine',user/'UnrealEditor',user/'EpicGamesLauncher/Saved/Config'];before_ue={str(p):tree_stats(p)for p in ue_roots};preexisting_ue_config=[binding(p)for root in ue_roots if root.exists()for p in root.rglob('*.ini')];installed=[engine/'Engine'/name for name in ['Saved','Intermediate','DerivedDataCache','Config']];installed_before={str(p):tree_stats(p)for p in installed}
 write(out/'SOURCE_BINDINGS.json',records);write(out/'UE_PROFILE_BEFORE.json',before_ue);write(out/'INSTALLED_WRITABLE_PATHS_BEFORE.json',installed_before)
 start=time.monotonic();state={'status':'RUNNING','command':command,'engine_version':version,'source_root':str(source),'artifact_root':str(out),'cache_root':str(cache),'native_build':native,'staged_native_files':staged_native,'compilation_in_editor_phase':False,'actual_free_port_before_spawn':port,'memory_is_aggregate_owned_process_tree':True,'asset_import_executed':False,'feature_enablement_executed':False,'external_editor_before':external,'external_processes_never_assigned_to_owned_job':True};samples=[];job=None;stop=threading.Event();errors=[];peakrss=0;peakprivate=0
 def supervise():
  need(time.monotonic()-start<TOTAL_SECONDS,'Finite bootstrap deadline exceeded');need(not errors,'Owned memory/monitor refused: '+str(errors));need(job is None or job.running(),'Editor exited before discovery completed')
 def monitor():
  nonlocal peakrss,peakprivate
  while not stop.wait(.5):
   try:
    sample=job.counters();sample['elapsed_seconds']=time.monotonic()-start;samples.append(sample);peakrss=max(peakrss,sample['rss_bytes']);peakprivate=max(peakprivate,sample['private_bytes']);need(peakrss<=RSS_LIMIT and peakprivate<=PRIVATE_LIMIT,'Aggregate owned14GiB RSS/20GiB private cap exceeded');need(time.monotonic()-start<TOTAL_SECONDS,'Owned bootstrap deadline exceeded')
   except BaseException as error:errors.append(str(error));stop.set()
 try:
  write(out/'REPORT.json',state)
  with(out/'stdout.log').open('xb')as stdout,(out/'stderr.log').open('xb')as stderr:
   job=OwnedJob(command,project,env,stdout,stderr,PRIVATE_LIMIT);state['owned_root_pid']=job.pid;write(out/'REPORT.json',state);watcher=threading.Thread(target=monitor,daemon=True);watcher.start();client=Client(out,supervise,f'http://127.0.0.1:{args.port}/mcp');attempts=[]
   while True:
    supervise()
    try:client.discover();break
    except (ConnectionError,TimeoutError,urllib.error.URLError)as error:
     need(client.session is None,'Transport interrupted an initialized session; preserve partials');attempts.append({'elapsed_seconds':time.monotonic()-start,'error':str(error)});write(out/'CONNECTION_ATTEMPTS.json',attempts);need(time.monotonic()-start<STARTUP_SECONDS,'Native MCP startup deadline exceeded');time.sleep(1)
   state['hardware_RHI_readback']=require_hardware_rhi(out/'UnrealEditor.log',args.expected_gpu_name);state.update(status='PASS_ACTUAL_NATIVE_MCP_DISCOVERY_IMPORT_PENDING',actual_tool_count=len(client.tools),actual_toolsets=list(client.toolsets),discovery_seconds=time.monotonic()-start,protocol=client.protocol)
 except BaseException:state.update(status='FAIL_PRESERVED_BOOTSTRAP',error=traceback.format_exc())
 finally:
  stop.set()
  if job:
   try:state['owned_reap']=job.stop_and_reap()
   except BaseException:state.update(status='FAIL_PRESERVED_BOOTSTRAP',reap_error=traceback.format_exc())
  if 'watcher'in locals():watcher.join(timeout=3)
  if state['status']=='PASS_ACTUAL_NATIVE_MCP_DISCOVERY_IMPORT_PENDING':
   try:state['hardware_RHI_readback_after_owned_stop']=require_hardware_rhi(out/'UnrealEditor.log',args.expected_gpu_name);need(state.get('owned_reap',{}).get('root_exit_code')==92,'Editor exited/crashed before controlled owned stop')
   except BaseException:state.update(status='FAIL_PRESERVED_BOOTSTRAP',post_stop_hardware_error=traceback.format_exc())
  write(out/'OWNED_MEMORY.json',samples);state.update(wall_seconds=time.monotonic()-start,peak_owned_rss_bytes=peakrss,peak_owned_private_bytes=peakprivate,memory_monitor_errors=errors)
  if errors:state['status']='FAIL_PRESERVED_BOOTSTRAP'
  try:verify(records);state['sources_unchanged']=True
  except BaseException:state.update(status='FAIL_PRESERVED_BOOTSTRAP',sources_unchanged=False,source_error=traceback.format_exc())
  try:verify(staged_native);state['staged_native_binaries_unchanged']=True
  except BaseException:state.update(status='FAIL_PRESERVED_BOOTSTRAP',staged_native_binaries_unchanged=False,native_binary_error=traceback.format_exc())
  changed=[]
  for row in preexisting_ue_config:
   p=Path(row['path'])
   if not p.exists()or binding(p)!=row:changed.append({'before':row,'after':binding(p)if p.exists()else None})
  state['preexisting_UE_config_changes_recorded_never_restored']=changed;state['preexisting_UE_config_bytes_preserved']=not changed;state['original_private_archives_unchanged']=preserve_guard(args.preserve_path)==original_private;state['installed_writable_paths_unchanged']={str(p):tree_stats(p)for p in installed}==installed_before;state['source_metadata_unchanged']={str(p):tree_stats(p)for p in [source/'game/scripts',source/'game/data',source/'tools']}==source_meta;state['system_drive_free_bytes_before']=disk_before;state['system_drive_free_bytes_after']=shutil.disk_usage(system_drive).free;state['system_drive_consumed_bytes']=disk_before-state['system_drive_free_bytes_after'];after_ue={str(p):tree_stats(p)for p in ue_roots};write(out/'UE_PROFILE_AFTER.json',after_ue);changes=[]
  for root,files in after_ue.items():
   old=before_ue[root];changes.extend({'path':p,'before':old.get(p),'after':v}for p,v in files.items()if old.get(p)!=v);changes.extend({'path':p,'before':v,'after':None}for p,v in old.items()if p not in files)
  write(out/'UE_PROFILE_DELTA.json',changes);state['UE_profile_deltas_recorded']=len(changes);state['queue_after']=editor_queue()
  try:state['external_editor_after']=external_state(args.external_editor_fingerprint,args.port);state['external_editor_preserved_exact']=state['external_editor_after']==external if external is None else {k:v for k,v in state['external_editor_after'].items()if k!='listening_ports'}=={k:v for k,v in external.items()if k!='listening_ports'}
  except BaseException:state.update(status='FAIL_PRESERVED_BOOTSTRAP',external_editor_preserved_exact=False,external_editor_error=traceback.format_exc())
  if not all(state[key]for key in ['preexisting_UE_config_bytes_preserved','original_private_archives_unchanged','installed_writable_paths_unchanged','source_metadata_unchanged','external_editor_preserved_exact','staged_native_binaries_unchanged']):state['status']='FAIL_PRESERVED_BOOTSTRAP'
  write(out/'REPORT.json',state);print(json.dumps(state))
 need(state['status']=='PASS_ACTUAL_NATIVE_MCP_DISCOVERY_IMPORT_PENDING','Bootstrap failed; all partials preserved')
if __name__=='__main__':main()
