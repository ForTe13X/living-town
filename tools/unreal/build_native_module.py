"""Build the native editor module in a fresh F-drive copy; never launch an editor.

The receipt is also the only native-binary input accepted by run_bootstrap.py.
It binds compile inputs, installed engine identity, UBT evidence and a closed
runtime file set. It is local provenance, not a signature or anti-cheat format.
"""
from common import *
import argparse, os, re, shutil, struct, time, traceback
from pathlib import PurePosixPath

SCHEMA='living_town.unreal.native_build.v1'
PASS='PASS_NATIVE_EDITOR_BUILD'
TRANSIENT={'Saved','Intermediate','DerivedDataCache','Binaries','.vs','__pycache__'}
FROZEN_INPUTS={
 'unreal/Source/LivingTownNative/ThirdParty/LeaseKernel.hpp':'942eb43c7b822da17c4949b08aa890d65324cd6d0e31bafa5d5104440641a8ac',
 'unreal/Source/LivingTownNative/ThirdParty/PILOT_CASES.json':'b5a0df51f0bb7fd1a04196d8fe1118df75b9de275b881faad71ac014c00ecf4c',
 'unreal/Source/LivingTownNative/ThirdParty/PilotWorldBinding.json':'9b7866e037be2bf9f2757c1201a572b466402eb4c0f3dc5b510c0166301bbcfc'}
ENGINE_FILES=['Engine/Build/Build.version','Engine/Binaries/Win64/UnrealEditor.modules',
 'Engine/Binaries/Win64/UnrealEditor.exe','Engine/Binaries/Win64/UnrealEditor-Core.dll',
 'Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll']
RSS_LIMIT=8*1024**3; PRIVATE_LIMIT=12*1024**3; DEADLINE=600

def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def file_record(path,relative):
 path=Path(path);before=path.stat();h=sha(path);after=path.stat()
 need((before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns),'Input changed while hashing: '+str(path))
 return {'file':relative,'bytes':after.st_size,'sha256':h}
def project_modules(source):
 rows=read(Path(source)/'unreal/LivingTown.uproject').get('Modules',[])
 need(isinstance(rows,list),'Project Modules must be a list')
 names=[]
 for row in rows:
  need(isinstance(row,dict)and isinstance(row.get('Name'),str)and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',row['Name']),'Invalid native module name')
  need(row['Name']not in names,'Duplicate native module');names.append(row['Name'])
 return names
def native_inputs(source):
 source=Path(source).resolve();paths=[source/'unreal/LivingTown.uproject']
 paths.extend(p for p in (source/'unreal/Source').rglob('*')if p.is_file())
 rows=[]
 for p in sorted(paths):
  need(not p.is_symlink()and p.resolve().is_relative_to(source),'Native source escapes source-root')
  rows.append(file_record(p,p.relative_to(source).as_posix()))
 return rows
def require_frozen_contract(source):
 for rel,h in FROZEN_INPUTS.items():need((Path(source)/rel).is_file()and sha(Path(source)/rel)==h,'Frozen portable contract changed: '+rel)
def engine_identity(engine):
 engine=Path(engine).resolve();version=read(engine/'Engine/Build/Build.version')
 need(tuple(version[k]for k in ['MajorVersion','MinorVersion','PatchVersion','Changelist'])==(5,8,4,58902052),'Requalify a different engine installation')
 modules=read(engine/'Engine/Binaries/Win64/UnrealEditor.modules')
 need(isinstance(modules.get('BuildId'),str)and modules['BuildId'],'Installed editor BuildId missing')
 return {'root':str(engine),'version':version,'build_id':modules['BuildId'],'files':[file_record(engine/rel,rel)for rel in ENGINE_FILES]}
def artifact_file(root,relative):
 need(isinstance(relative,str)and '\\'not in relative and ':'not in relative,'Noncanonical build artifact path')
 parts=PurePosixPath(relative);need(not parts.is_absolute()and '..'not in parts.parts and parts.parts,'Build artifact traversal refused')
 path=(Path(root)/Path(*parts.parts)).resolve();need(path.is_relative_to(Path(root).resolve()),'Build artifact resolves outside receipt root')
 need(path.is_file(),'Build artifact absent: '+str(path));return path
def check_record(root,row):
 need(isinstance(row,dict)and set(row)=={'file','bytes','sha256'},'Malformed artifact binding')
 path=artifact_file(root,row['file']);need(file_record(path,row['file'])==row,'Build artifact bytes changed: '+row['file']);return path
def require_editor_dll(path):
 with Path(path).open('rb')as f:
  dos=f.read(64);need(len(dos)==64 and dos[:2]==b'MZ','Native binary has no DOS header')
  offset=struct.unpack_from('<I',dos,60)[0];need(64<=offset<=Path(path).stat().st_size-24,'Invalid PE offset');f.seek(offset);pe=f.read(24)
 need(pe[:4]==b'PE\0\0'and struct.unpack_from('<H',pe,4)[0]==0x8664 and struct.unpack_from('<H',pe,22)[0]&0x2000,'Expected an x64 PE DLL')

def validate_native_build_receipt(source,engine,receipt_path=None):
 """Read-only and fail closed before an editor is launched."""
 source=Path(source).resolve();engine=Path(engine).resolve();names=project_modules(source)
 if not names:
  need(receipt_path is None,'Content-only project must not stage unrelated native binaries');return None
 need(receipt_path is not None,'Native project requires --native-build-receipt; build it before bootstrap')
 require_frozen_contract(source);receipt_path=Path(receipt_path).resolve();packet=read(receipt_path);root=receipt_path.parent
 need(packet.get('schema')==SCHEMA and packet.get('status')==PASS,'Native build receipt is not a successful supported build')
 need(packet.get('workcopy_sources_exact')is True,'Compiled workcopy sources were not preserved exactly')
 need(packet.get('project')=={'file':'LivingTown.uproject','editor_target':'LivingTownEditor','modules':names},'Native project/target/module declaration differs from build')
 inputs=native_inputs(source);need(packet.get('source',{}).get('inputs')==inputs and packet['source'].get('sha256')==digest(inputs),'Native sources differ from compiled receipt')
 need(packet.get('engine')==engine_identity(engine),'Installed engine/version/BuildId bytes differ from native build')
 build=packet.get('build',{});need(build.get('root_exit_code')==0 and build.get('owned_descendants_reaped')is True,'Build process did not complete cleanly')
 log=check_record(root,build.get('log'));text=log.read_text(encoding='utf-8-sig',errors='replace')
 need('Result: Succeeded'in text and'LivingTownEditor'in text,'Successful Editor-target UBT evidence absent')
 files=packet.get('runtime_files');need(isinstance(files,list)and all(isinstance(r,dict)for r in files),'Native runtime file bindings absent')
 expected={'project/Binaries/Win64/UnrealEditor.modules',*[f'project/Binaries/Win64/UnrealEditor-{n}.dll'for n in names]}
 need(len(files)==len(expected)and{r.get('file')for r in files}==expected,'Native runtime file closure differs from declared modules')
 actual={r['file']:check_record(root,r)for r in files};module_path=actual['project/Binaries/Win64/UnrealEditor.modules'];module_data=read(module_path)
 need(module_data.get('BuildId')==packet['engine']['build_id'],'Project module BuildId differs from installed editor')
 need(module_data.get('Modules')=={n:f'UnrealEditor-{n}.dll'for n in names},'Module metadata points at unlisted/renamed binary')
 for n in names:
  dll=actual[f'project/Binaries/Win64/UnrealEditor-{n}.dll'];require_editor_dll(dll)
  need(dll.name in text,'DLL link output absent from UBT evidence')
 engine_rows=[{'path':str((engine/row['file']).resolve()),'bytes':row['bytes'],'sha256':row['sha256']}for row in packet['engine']['files']]
 return {'receipt':binding(receipt_path),'source_root':str(source),'engine_root':str(engine),'source_sha256':digest(inputs),
  'build_id':module_data['BuildId'],'modules':names,'runtime_files':[binding(actual[r['file']])for r in files],
  'bound_files':[binding(receipt_path),binding(log),*[binding(actual[r['file']])for r in files],*engine_rows]}

def stage_native_binaries(project,validated):
 if validated is None:return []
 fresh=validate_native_build_receipt(validated['source_root'],validated['engine_root'],validated['receipt']['path'])
 need(fresh==validated,'Native receipt/artifacts changed after preflight')
 destination=Path(project)/'Binaries/Win64';need(not destination.exists(),'Refuse existing staged native-binary directory')
 destination.mkdir(parents=True);staged=[]
 for row in validated['runtime_files']:
  target=destination/Path(row['path']).name;shutil.copyfile(row['path'],target)
  copied=binding(target);need(copied['bytes']==row['bytes']and copied['sha256']==row['sha256'],'Native binary changed while staging');staged.append(copied)
 return staged

def output_layout(source,engine,out):
 source=Path(source).resolve();engine=Path(engine).resolve();out=Path(out).resolve()
 need(out.drive.lower()=='f:','Native build workcopy/output must use F: on this host')
 need(not out.exists(),'Preserve existing native build output')
 need(not out.is_relative_to(source)and not out.is_relative_to(engine)and not source.is_relative_to(out)and not engine.is_relative_to(out),'Build output overlaps source/engine')
 need(project_modules(source),'Native module declaration required');require_frozen_contract(source)
 for target in ['LivingTown.Target.cs','LivingTownEditor.Target.cs']:need((source/'unreal/Source'/target).is_file(),'Expected project target absent: '+target)
 return source,engine,out
def incidental_metadata(engine=None):
 roots=[Path(os.environ['LOCALAPPDATA'])/'UnrealEngine/Intermediate/Build',Path(os.environ['LOCALAPPDATA'])/'UnrealBuildTool']
 if engine is not None:roots.append(Path(engine)/'Engine/Intermediate/UbtRuns')
 return {str(p):[p.stat().st_size,p.stat().st_mtime_ns]for root in roots if root.exists()for p in root.rglob('*')if p.is_file()}
def config_guard(engine):
 paths=[Path(engine)/'Engine/Saved/UnrealBuildTool/BuildConfiguration.xml',Path(os.environ['APPDATA'])/'Unreal Engine/UnrealBuildTool/BuildConfiguration.xml',Path(os.environ['LOCALAPPDATA'])/'Unreal Engine/UnrealBuildTool/BuildConfiguration.xml',Path(os.environ['USERPROFILE'])/'Documents/Unreal Engine/UnrealBuildTool/BuildConfiguration.xml']
 return {str(p):binding(p)if p.is_file()else None for p in paths}

def main(argv=None):
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[2]);parser.add_argument('--engine-root',type=Path,required=True);parser.add_argument('--artifact-root',type=Path,required=True);parser.add_argument('--execute',action='store_true');args=parser.parse_args(argv)
 source,engine,out=output_layout(args.source_root,args.engine_root,args.artifact_root);identity=engine_identity(engine);inputs=native_inputs(source)
 command=[str(engine/'Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe'),str(engine/'Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll'),'LivingTownEditor','Win64','Development',f'-Project={out/"project/LivingTown.uproject"}','-NoEngineChanges','-NoHotReloadFromIDE','-NoUBA','-NoXGE','-NoFASTBuild','-NoSNDBS','-MaxParallelActions=2','-Compiler=VisualStudio2022','-CompilerVersion=14.44.35229','-WindowsSDKVersion=10.0.22621.0',f'-Log={out/"Build/UBT.log"}',f'-XmlConfigCache={out/"Build/DefaultXmlConfigCache.bin"}']
 plan={'status':'PREFLIGHT_NO_COMPILER_OR_EDITOR','source_sha256':digest(inputs),'engine_build_id':identity['build_id'],'command':command,'limits':{'deadline_seconds':DEADLINE,'rss_bytes':RSS_LIMIT,'private_bytes':PRIVATE_LIMIT}}
 if not args.execute:print(json.dumps(plan));return
 need(shutil.disk_usage('C:\\').free>=1024**3,'System drive headroom below1GiB; no build launched')
 out.mkdir(parents=True);(out/'Build').mkdir();private=out/'private'
 for name in ['TEMP','TMP','DotnetHome','Nuget']:(private/name).mkdir(parents=True)
 project=out/'project';shutil.copytree(source/'unreal',project,ignore=shutil.ignore_patterns(*TRANSIENT));(project/'Content').mkdir(exist_ok=True)
 for row in inputs:
  copied=project/Path(row['file']).relative_to('unreal');need(file_record(copied,row['file'])==row,'Native source copy mismatch')
 (out/'Build/DefaultXmlConfigCache.bin').write_bytes(struct.pack('<iii',2,0,0))
 env=os.environ.copy();env.update(TEMP=str(private/'TEMP'),TMP=str(private/'TMP'),DOTNET_CLI_HOME=str(private/'DotnetHome'),NUGET_PACKAGES=str(private/'Nuget'),DOTNET_NOLOGO='1',DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1',DOTNET_MULTILEVEL_LOOKUP='0',DOTNET_ROLL_FORWARD='LatestMajor')
 before_config=config_guard(engine);before_metadata=incidental_metadata(engine);before_engine=identity;producer=[binding(Path(__file__)),binding(Path(__file__).with_name('common.py')),binding(Path(__file__).with_name('owned_job.py'))];write(out/'PLAN.json',plan);write(out/'SOURCE_INPUTS.json',inputs)
 report={'schema':SCHEMA,'status':'RUNNING','project':{'file':'LivingTown.uproject','editor_target':'LivingTownEditor','modules':project_modules(source)},'source':{'inputs':inputs,'sha256':digest(inputs)},'engine':identity,'limits':plan['limits'],'compiler_pinned':'14.44.35229','windows_sdk_pinned':'10.0.22621.0','no_editor_launched':True};write(out/'BUILD_RECEIPT.json',report)
 from owned_job import OwnedJob
 job=None;samples=[];markers={};reason='completed';start=time.monotonic()
 try:
  with(out/'Build/stdout.log').open('xb')as stdout,(out/'Build/stderr.log').open('xb')as stderr:
   job=OwnedJob(command,project,env,stdout,stderr,PRIVATE_LIMIT);report['owned_pid']=job.pid;write(out/'BUILD_RECEIPT.json',report);print(json.dumps({'started_owned_UBT_pid':job.pid,'project':str(project)}),flush=True)
   while job.running():
    s=job.counters();s['elapsed_seconds']=round(time.monotonic()-start,3);samples.append(s)
    for marker in(engine/'Engine/Intermediate/UbtRuns').glob(str(job.pid)+'_*'):
     if marker.is_file():markers[str(marker)]={'bytes':marker.stat().st_size,'observed_seconds':s['elapsed_seconds']}
    if s['rss_bytes']>RSS_LIMIT or s['private_bytes']>PRIVATE_LIMIT:reason='memory_limit';break
    if s['elapsed_seconds']>DEADLINE:reason='deadline';break
    if shutil.disk_usage('C:\\').free<512*1024**2:reason='system_drive_headroom';break
    time.sleep(.5)
   report['owned_reap']=job.stop_and_reap();job=None
  need(reason=='completed'and report['owned_reap']['root_exit_code']==0,'Native build did not complete successfully: '+reason)
  need(native_inputs(source)==inputs,'Canonical native source changed during build')
  need(all(file_record(project/Path(row['file']).relative_to('unreal'),row['file'])==row for row in inputs),'Compiled source copy changed during build')
  need(config_guard(engine)==before_config and engine_identity(engine)==before_engine,'Existing engine/config inputs changed during build')
  report['build']={'root_exit_code':0,'owned_descendants_reaped':not report['owned_reap']['remaining_owned_pids'],'log':file_record(out/'Build/UBT.log','Build/UBT.log')}
  names=report['project']['modules'];relatives=['project/Binaries/Win64/UnrealEditor.modules',*[f'project/Binaries/Win64/UnrealEditor-{n}.dll'for n in names]]
  report['runtime_files']=[file_record(out/rel,rel)for rel in relatives];report['status']=PASS
 except BaseException:report.update(status='FAIL_PRESERVED_NATIVE_BUILD',error=traceback.format_exc())
 finally:
  if job:report['owned_reap']=job.stop_and_reap()
  after=incidental_metadata(engine);report.update(reason=reason,wall_seconds=round(time.monotonic()-start,3),peak_rss_bytes=max((s['rss_bytes']for s in samples),default=0),peak_private_bytes=max((s['private_bytes']for s in samples),default=0),producer_sources=producer,normal_engine_run_markers_observed=markers,normal_installed_engine_metadata_changed={p:v for p,v in after.items()if before_metadata.get(p)!=v})
  try:
   report['canonical_sources_exact']=native_inputs(source)==inputs;report['workcopy_sources_exact']=all(file_record(project/Path(row['file']).relative_to('unreal'),row['file'])==row for row in inputs);report['preexisting_config_exact']=config_guard(engine)==before_config;report['engine_inputs_exact']=engine_identity(engine)==before_engine;verify(producer);report['producer_sources_exact']=True
   need(all(report[k]for k in ['canonical_sources_exact','workcopy_sources_exact','preexisting_config_exact','engine_inputs_exact']),'Native build input guard changed')
  except BaseException:report.update(status='FAIL_PRESERVED_NATIVE_BUILD',guard_error=traceback.format_exc())
  write(out/'MEMORY_SAMPLES.json',samples);write(out/'BUILD_RECEIPT.json',report)
 if report['status']==PASS:
  try:validate_native_build_receipt(source,engine,out/'BUILD_RECEIPT.json')
  except BaseException:report.update(status='FAIL_PRESERVED_NATIVE_BUILD',validation_error=traceback.format_exc());write(out/'BUILD_RECEIPT.json',report)
 print(json.dumps({k:report.get(k)for k in ['status','reason','wall_seconds','peak_rss_bytes','peak_private_bytes','canonical_sources_exact','workcopy_sources_exact','preexisting_config_exact']}))
 need(report['status']==PASS,'Native build failed; all partial evidence preserved')
if __name__=='__main__':main()
