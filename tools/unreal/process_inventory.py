"""Sanitized read-only process facts; no external process control API."""
from common import *
import subprocess
def powershell_json(script):
 text=subprocess.check_output(['powershell','-NoProfile','-NonInteractive','-Command',script],creationflags=subprocess.CREATE_NO_WINDOW,text=True).strip()
 return json.loads(text)if text else[]
def editor_queue():
 value=powershell_json("Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(UnrealEditor|UnrealEditor-Cmd|ShaderCompileWorker|blender|Godot.*)\\.exe$' } | Select-Object ProcessId,ParentProcessId,Name | ConvertTo-Json -Compress")
 return value if isinstance(value,list)else[value]
def idle_editor_fingerprint(pid):
 need(isinstance(pid,int)and not isinstance(pid,bool)and pid>0,'Explicit positive observed PID required')
 # The raw command line is transient inside this process probe and never returned.
 script=r"""$p=Get-CimInstance Win32_Process -Filter 'ProcessId=__PID__'; if(!$p){throw 'Requested editor disappeared'}; $w=Get-Process -Id __PID__ -ErrorAction Stop; [pscustomobject]@{pid=$p.ProcessId;name=$p.Name;creation_utc=$p.CreationDate.ToUniversalTime().ToString('o');exe=$p.ExecutablePath;project_args=@([regex]::Matches([string]$p.CommandLine,'(?i)(?:\x22([^\x22]+\.uproject)\x22|([^\s\x22]+\.uproject))')|ForEach-Object{if($_.Groups[1].Success){$_.Groups[1].Value}else{$_.Groups[2].Value}});has_mcp_flag=([string]$p.CommandLine -match '(?i)-ModelContextProtocolStartServer');main_window_title=$w.MainWindowTitle;main_window_handle=$w.MainWindowHandle.ToInt64();listening_ports=@(Get-NetTCPConnection -State Listen -OwningProcess __PID__ -ErrorAction SilentlyContinue|Select-Object -ExpandProperty LocalPort)}|ConvertTo-Json -Depth 3 -Compress""".replace('__PID__',str(pid))
 return powershell_json(script)
def require_idle_shape(fingerprint):
 fields={'pid','name','creation_utc','exe','project_args','has_mcp_flag','main_window_title','main_window_handle','listening_ports'}
 need(set(fingerprint)==fields,'External editor fingerprint has missing/unrecognized fields')
 need(isinstance(fingerprint['pid'],int)and not isinstance(fingerprint['pid'],bool)and fingerprint['pid']>0 and isinstance(fingerprint['creation_utc'],str)and fingerprint['creation_utc']and Path(fingerprint['exe']).name=='UnrealEditor.exe','Complete observed PID/creation/executable identity required')
 need(fingerprint['name']=='UnrealEditor.exe'and not fingerprint['project_args']and fingerprint['has_mcp_flag']is False and fingerprint['main_window_handle']>0,'Only an idle project-browser editor may be declared')
 need(fingerprint['main_window_title'].startswith('Unreal Engine '),'A project-browser title is required')
def validate_external(actual,expected,queue,port):
 require_idle_shape(expected);require_idle_shape(actual)
 identity=lambda row:{key:value for key,value in row.items()if key!='listening_ports'}
 need(identity(actual)==identity(expected),'Declared idle editor identity changed; do not touch it')
 need(port not in actual['listening_ports'],'External editor owns the requested bootstrap port')
 need(len(queue)==1 and queue[0]['ProcessId']==expected['pid']and queue[0]['Name']=='UnrealEditor.exe','Another outside-owned engine/worker exists')
def external_state(fingerprint_path,port):
 queue=editor_queue()
 if fingerprint_path is None:need(queue==[],'Engine queue occupied; no external-editor exemption was supplied');return None
 declaration=read(fingerprint_path);need(declaration.get('scope')=='EXPLICIT_IDLE_EDITOR_IDENTITY_ONLY','Reviewed runtime idle-editor declaration required');expected=declaration['exact_fingerprint'];actual=idle_editor_fingerprint(expected['pid']);validate_external(actual,expected,queue,port);return actual
