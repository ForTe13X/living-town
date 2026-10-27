"""Windows job ownership before suspended child can create any descendants."""
import ctypes as C,ctypes.wintypes as W,subprocess,os,time,msvcrt
K=C.WinDLL('kernel32',use_last_error=True);P=C.WinDLL('psapi',use_last_error=True)
SIZE=C.c_size_t;ULONG=C.c_ulonglong
class SI(C.Structure):
 _fields_=[('cb',W.DWORD),('lpReserved',W.LPWSTR),('lpDesktop',W.LPWSTR),('lpTitle',W.LPWSTR),('dwX',W.DWORD),('dwY',W.DWORD),('dwXSize',W.DWORD),('dwYSize',W.DWORD),('dwXCountChars',W.DWORD),('dwYCountChars',W.DWORD),('dwFillAttribute',W.DWORD),('dwFlags',W.DWORD),('wShowWindow',W.WORD),('cbReserved2',W.WORD),('lpReserved2',C.c_void_p),('hStdInput',W.HANDLE),('hStdOutput',W.HANDLE),('hStdError',W.HANDLE)]
class PI(C.Structure):_fields_=[('process',W.HANDLE),('thread',W.HANDLE),('pid',W.DWORD),('tid',W.DWORD)]
class BASIC(C.Structure):_fields_=[('PerProcessUserTimeLimit',C.c_longlong),('PerJobUserTimeLimit',C.c_longlong),('LimitFlags',W.DWORD),('MinimumWorkingSetSize',SIZE),('MaximumWorkingSetSize',SIZE),('ActiveProcessLimit',W.DWORD),('Affinity',SIZE),('PriorityClass',W.DWORD),('SchedulingClass',W.DWORD)]
class IO(C.Structure):_fields_=[(n,ULONG)for n in ['ReadOperationCount','WriteOperationCount','OtherOperationCount','ReadTransferCount','WriteTransferCount','OtherTransferCount']]
class LIMITS(C.Structure):_fields_=[('BasicLimitInformation',BASIC),('IoInfo',IO),('ProcessMemoryLimit',SIZE),('JobMemoryLimit',SIZE),('PeakProcessMemoryUsed',SIZE),('PeakJobMemoryUsed',SIZE)]
class MEMORY(C.Structure):_fields_=[('cb',W.DWORD),('PageFaultCount',W.DWORD)]+[(n,SIZE)for n in ['PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage','PrivateUsage']]
K.CreateJobObjectW.argtypes=[C.c_void_p,W.LPCWSTR];K.CreateJobObjectW.restype=W.HANDLE
K.SetInformationJobObject.argtypes=[W.HANDLE,C.c_int,C.c_void_p,W.DWORD];K.SetInformationJobObject.restype=W.BOOL
K.QueryInformationJobObject.argtypes=[W.HANDLE,C.c_int,C.c_void_p,W.DWORD,C.c_void_p];K.QueryInformationJobObject.restype=W.BOOL
K.AssignProcessToJobObject.argtypes=[W.HANDLE,W.HANDLE];K.AssignProcessToJobObject.restype=W.BOOL
K.CreateProcessW.argtypes=[W.LPCWSTR,W.LPWSTR,C.c_void_p,C.c_void_p,W.BOOL,W.DWORD,C.c_void_p,W.LPCWSTR,C.POINTER(SI),C.POINTER(PI)];K.CreateProcessW.restype=W.BOOL
K.ResumeThread.argtypes=[W.HANDLE];K.ResumeThread.restype=W.DWORD
K.TerminateJobObject.argtypes=[W.HANDLE,W.UINT];K.TerminateJobObject.restype=W.BOOL
K.WaitForSingleObject.argtypes=[W.HANDLE,W.DWORD];K.WaitForSingleObject.restype=W.DWORD
K.GetExitCodeProcess.argtypes=[W.HANDLE,C.POINTER(W.DWORD)];K.GetExitCodeProcess.restype=W.BOOL
K.CloseHandle.argtypes=[W.HANDLE];K.CloseHandle.restype=W.BOOL
K.OpenProcess.argtypes=[W.DWORD,W.BOOL,W.DWORD];K.OpenProcess.restype=W.HANDLE
P.GetProcessMemoryInfo.argtypes=[W.HANDLE,C.POINTER(MEMORY),W.DWORD];P.GetProcessMemoryInfo.restype=W.BOOL
def check(ok):
 if not ok:raise C.WinError(C.get_last_error())
class OwnedJob:
 def __init__(self,command,cwd,env,stdout,stderr,private_limit):
  self.job=K.CreateJobObjectW(None,None);check(self.job);self.process=None;self.pid=None
  limit=LIMITS();limit.BasicLimitInformation.LimitFlags=0x2000|0x200 # KILL_ON_JOB_CLOSE and JOB_MEMORY
  limit.JobMemoryLimit=private_limit;check(K.SetInformationJobObject(self.job,9,C.byref(limit),C.sizeof(limit)))
  pi=PI();si=SI();si.cb=C.sizeof(si);si.dwFlags=0x100
  with open(os.devnull,'rb')as stdin:
   handles=[msvcrt.get_osfhandle(f.fileno())for f in [stdin,stdout,stderr]]
   for h in handles:os.set_handle_inheritable(h,True)
   si.hStdInput,si.hStdOutput,si.hStdError=handles
   block=C.create_unicode_buffer('\0'.join(k+'='+v for k,v in sorted(env.items(),key=lambda r:r[0].upper()))+'\0\0')
   try:check(K.CreateProcessW(command[0],C.create_unicode_buffer(subprocess.list2cmdline(command)),None,None,True,0x4|0x400|0x08000000,block,str(cwd),C.byref(si),C.byref(pi)))
   finally:
    for h in handles:os.set_handle_inheritable(h,False)
  self.process=pi.process;self.pid=pi.pid
  try:check(K.AssignProcessToJobObject(self.job,pi.process));check(K.ResumeThread(pi.thread)!=0xffffffff)
  except BaseException:
   K.TerminateJobObject(self.job,91)
   # If assignment itself refused, terminate only our still-suspended child.
   K.TerminateProcess.argtypes=[W.HANDLE,W.UINT];K.TerminateProcess(pi.process,91);K.WaitForSingleObject(pi.process,30000);raise
  finally:K.CloseHandle(pi.thread)
 def ids(self):
  capacity=4096;buffer=C.create_string_buffer(8+capacity*C.sizeof(SIZE));check(K.QueryInformationJobObject(self.job,3,buffer,len(buffer),None));assigned,n=C.cast(buffer,C.POINTER(W.DWORD*2)).contents
  if n>capacity:raise ValueError('Owned process inventory exceeded finite4096')
  return list((SIZE*n).from_buffer(buffer,8))
 def counters(self):
  rows=[]
  for pid in self.ids():
   h=K.OpenProcess(0x1000|0x10,False,pid)
   if not h:continue # Process may exit after the actual job inventory.
   try:
    m=MEMORY();m.cb=C.sizeof(m)
    if P.GetProcessMemoryInfo(h,C.byref(m),C.sizeof(m)):rows.append({'pid':pid,'rss_bytes':m.WorkingSetSize,'private_bytes':m.PrivateUsage,'peak_pagefile_bytes':m.PeakPagefileUsage})
   finally:K.CloseHandle(h)
  return {'owned_pids':self.ids(),'processes':rows,'rss_bytes':sum(r['rss_bytes']for r in rows),'private_bytes':sum(r['private_bytes']for r in rows)}
 def running(self):return K.WaitForSingleObject(self.process,0)==258
 def stop_and_reap(self):
  check(K.TerminateJobObject(self.job,92));deadline=time.monotonic()+30
  check(K.WaitForSingleObject(self.process,30000)==0)
  while self.ids()and time.monotonic()<deadline:time.sleep(.05)
  remaining=self.ids();code=W.DWORD();check(K.GetExitCodeProcess(self.process,C.byref(code)));K.CloseHandle(self.process);K.CloseHandle(self.job);self.process=None;self.job=None
  if remaining:raise ValueError('Owned descendants not reaped: '+str(remaining))
  return {'root_exit_code':code.value,'owned_root_waited':True,'remaining_owned_pids':remaining,'controlled_job_termination':True,'includes_ShaderCompileWorker_descendants':True}
