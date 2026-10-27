"""Discovery only; toolset dispatch/import calls deliberately absent."""
from common import *
import urllib.request,urllib.error,re,time,socket
def free_port(port):
 need(isinstance(port,int)and not isinstance(port,bool)and 1<=port<=65535,'Valid explicit loopback port required')
 with socket.socket()as s:s.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1);s.bind(('127.0.0.1',port))
 return {'address':'127.0.0.1','port':port,'actual_bind_succeeded':True,'reservation_released_for_owned_editor':True}
def decode_body(body,kind):
 text=body.decode('utf-8')
 if 'text/event-stream'in kind:
  messages=[json.loads('\n'.join(line[5:].lstrip()for line in chunk.splitlines()if line.startswith('data:')))for chunk in text.replace('\r\n','\n').split('\n\n')if any(line.startswith('data:')for line in chunk.splitlines())]
  answers=[m for m in messages if'result'in m or'error'in m];need(len(answers)==1,'Expected one finite SSE JSONRPC answer');return answers[0]
 return json.loads(text)if text.strip()else None
def result_text(result):
 need(not result.get('isError',False),'MCP tool returned isError');need(isinstance(result.get('content'),list),'Actual text content missing');parts=[v['text']for v in result['content']if v.get('type')=='text'];need(parts,'Actual discovery text missing');return '\n'.join(parts)
def parse_catalog(text):
 need(isinstance(text,str)and text.strip()and len(text.encode('utf-8'))<=1024*1024,'Empty or oversized actual toolset catalog')
 lines=text.splitlines();need(len(lines)<=4096,'Unbounded actual catalog lines');entries=[];seen=set()
 for line in lines:
  if not line.strip():continue
  if line.startswith('-'):
   match=re.fullmatch(r'- ([A-Za-z_][A-Za-z0-9_.-]*):[ \t]*(.*)',line)
   need(match is not None,'Invalid actual toolset bullet/name/colon');name,description=match.groups();need(name not in seen,'Duplicate actual catalog name');seen.add(name);need(len(seen)<=128,'Unbounded actual toolset count');entries.append({'name':name,'description':description})
  else:
   need(entries,'Orphan actual catalog description continuation');entries[-1]['description']+='\n'+line
 for entry in entries:need(entry['description'].strip(),'Empty actual toolset description')
 need(entries,'Empty actual toolset catalog');return entries
class Client:
 def __init__(self,output,supervise,url):
  from urllib.parse import urlsplit
  endpoint=urlsplit(url);need(endpoint.scheme=='http'and endpoint.hostname=='127.0.0.1'and endpoint.port is not None and endpoint.path=='/mcp'and not endpoint.query and not endpoint.fragment and endpoint.username is None and endpoint.password is None,'Explicit loopback /mcp endpoint required')
  self.output=output;self.supervise=supervise;self.url=url;self.session=None;self.seq=0;self.protocol='2025-11-25';self.tools={};self.toolsets={};self.history=[]
 def request(self,method,params=None,notification=False):
  self.supervise();self.seq+=1;value={'jsonrpc':'2.0','method':method}
  if not notification:value['id']=self.seq
  if params is not None:value['params']=params
  headers={'Content-Type':'application/json','Accept':'application/json, text/event-stream','MCP-Protocol-Version':self.protocol}
  if self.session:headers['Mcp-Session-Id']=self.session
  start=time.monotonic()
  try:
   with urllib.request.urlopen(urllib.request.Request(self.url,data=json.dumps(value).encode(),headers=headers),timeout=15)as response:
    data=response.read(32*1024*1024+1);need(len(data)<=32*1024*1024,'Finite MCP response exceeded32MiB');answer=decode_body(data,response.headers.get('Content-Type',''));new_session=response.headers.get('Mcp-Session-Id');status=response.status
   self.history.append({'request':value,'response':answer,'http_status':status,'seconds':time.monotonic()-start,'session_header_present':bool(new_session or self.session)});write(self.output/'HTTP_TRANSCRIPT.json',self.history)
   if new_session:self.session=new_session
   if notification:need(status in[200,202,204],'Notification refused');return answer
   need(isinstance(answer,dict)and answer.get('id')==value['id']and'error'not in answer and'result'in answer,'MCP JSONRPC request refused/mismatched');return answer['result']
  finally:self.supervise()
 def discover(self):
  initialization=self.request('initialize',{'protocolVersion':self.protocol,'capabilities':{},'clientInfo':{'name':'LivingTownOwnedBootstrap','version':'1.0'}});need(self.session,'Native MCP did not return session ID');self.protocol=initialization['protocolVersion'];self.request('notifications/initialized',notification=True)
  cursor=None;seen=set()
  while True:
   page=self.request('tools/list',{}if cursor is None else{'cursor':cursor})
   for item in page['tools']:need(item['name']not in self.tools,'Duplicate actual tool');self.tools[item['name']]=item
   cursor=page.get('nextCursor')
   if not cursor:break
   need(cursor not in seen and len(seen)<50,'Invalid/unbounded discovery pagination');seen.add(cursor)
  need({'list_toolsets','describe_toolset','call_tool'}<=set(self.tools),'Native meta-tool discovery contract absent')
  catalog=result_text(self.request('tools/call',{'name':'list_toolsets','arguments':{}}));write(self.output/'ACTUAL_TOOLSET_CATALOG.json',{'text':catalog})
  entries=parse_catalog(catalog);names=[entry['name']for entry in entries];write(self.output/'ACTUAL_PARSED_CATALOG.json',{'entries':entries,'all_names_from_actual_column0_headers':True,'continuations_are_description_only':True})
  schema=self.tools['describe_toolset']['inputSchema'];need(schema.get('properties',{}).get('toolset_name',{}).get('type')=='string'and'toolset_name'in schema.get('required',[]),'Actual describe schema differs; do not guess')
  for name in names:
   described=self.request('tools/call',{'name':'describe_toolset','arguments':{'toolset_name':name}});self.toolsets[name]={'raw_result':described,'schema':json.loads(result_text(described))};write(self.output/'ACTUAL_DISCOVERED_MAP.json',{'actual_tools':self.tools,'actual_toolsets':self.toolsets,'source':'actual_http_initialize_tools_list_list_toolsets_describe_toolset','import_or_other_tool_executed':False})
  return {'initialization':initialization,'actual_tool_count':len(self.tools),'actual_toolsets':names,'actual_schema_count':len(self.toolsets),'import_executed':False}
