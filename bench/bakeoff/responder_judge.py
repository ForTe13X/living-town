#!/usr/bin/env python
# Player-interaction eval: for each grounded model-hard scenario, the model produces (action + in-character line),
# then judges it on 3 dims. Records latency profile (prefill / deployable-decode / ceiling-reasoning tokens).
# Sequential, RAM-lean, resumable. Usage: python responder_judge.py scenarios.json results.jsonl
import json, re, sys, time, urllib.request
BASE="http://127.0.0.1:1234/v1"
SCEN, OUTP = sys.argv[1], sys.argv[2]

def call(payload,timeout=300):
    req=urllib.request.Request(BASE+"/chat/completions",data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=timeout) as r: return json.loads(r.read().decode())
def MID():
    with urllib.request.urlopen(BASE+"/models",timeout=30) as r: return json.loads(r.read().decode())["data"][0]["id"]
M=MID()

def resp_parse(c):
    c=c or ""
    a=re.search(r'(?:动作|行动|action)[:：]\s*(.+)', c)
    s=re.search(r'(?:说|台词|回应|line)[:：]\s*(.+)', c)
    action=(a.group(1).strip() if a else "").splitlines()[0][:60] if a else ""
    line=(s.group(1).strip() if s else "").splitlines()[0][:120] if s else ""
    if not action and not line: line=c.strip().replace("\n"," ")[:120]
    return action, line

def responder(sc):
    # think-ON ceiling: let the 120B reason, then answer. Record tokens (deployable decode = content, not reasoning).
    sysp=("你就是%s。%s。这是像素小镇里的一个真实处境，请用完全符合你性格和说话风格的方式回应。"
          "先给一个【动作】（一个简短动词短语），再说【一句话】（符合你口吻、对眼前的人说的话）。严格用两行：\n动作：…\n说：…"%(sc["persona_name"],sc["persona_brief"]))
    pm=sc.get("player_message","").strip()
    usr="[处境] %s\n\n%s"%(sc["context"], ("[玩家对你说] "+pm) if pm else "眼下的情况就是如此，你会怎么做、说什么？")
    t=time.time()
    r=call({"model":M,"messages":[{"role":"system","content":sysp},{"role":"user","content":usr}],"temperature":0.3,"max_tokens":700})
    dt=time.time()-t
    m=r["choices"][0]["message"]; u=r["usage"]; det=u.get("completion_tokens_details",{}) or {}
    reason_tok=det.get("reasoning_tokens",0) or 0
    content=m.get("content") or ""
    action,line=resp_parse(content)
    content_tok=max(0,u["completion_tokens"]-reason_tok)
    return {"action":action,"line":line,"raw":content[:300],
            "prompt_tokens":u["prompt_tokens"],"reasoning_tokens":reason_tok,"response_tokens":content_tok,"resp_latency_s":round(dt,1)}

def judge(sc,resp):
    sysp="你是严格的角色扮演评审。按人设与处境给这条NPC回应打分。1=很差,5=极好。只输出一行、别解释。 /no_think"
    usr=("[人设] %s：%s\n[处境] %s\n[玩家说] %s\n[NPC动作] %s\n[NPC台词] %s\n\n"
         "按此格式打分(1-5整数)：\n入戏=<n> 扣境=<n> 具体=<n> | 点评:<不超过20字>"%(
         sc["persona_name"],sc["persona_brief"],sc["context"],sc.get("player_message","") or "(无，自主处境)",resp["action"],resp["line"]))
    r=call({"model":M,"messages":[{"role":"system","content":sysp},{"role":"user","content":usr},{"role":"assistant","content":"</think>\n\n"}],"temperature":0,"max_tokens":60})
    t=r["choices"][0]["message"].get("content") or ""
    def g(k):
        m=re.search(k+r'\s*[=:：]\s*([1-5])',t); return int(m.group(1)) if m else -1
    cm=re.search(r'点评[:：]\s*(.+)',t)
    return {"in_char":g("入戏"),"grounded":g("扣境"),"specific":g("具体"),"critique":(cm.group(1).strip()[:40] if cm else ""),"judge_raw":t[:80]}

scen=json.load(open(SCEN,encoding="utf-8"))
if isinstance(scen,dict): scen=scen.get("curated") or scen.get("scenarios") or []
print("[eval] %d scenarios  model=%s  out=%s"%(len(scen),M,OUTP),flush=True)
done=set()
try:
    for line in open(OUTP,encoding="utf-8"): done.add(json.loads(line)["id"])
except FileNotFoundError: pass
out=open(OUTP,"a",encoding="utf-8"); t0=time.time(); n=0
for sc in scen:
    sid=sc.get("id") or ("%s-%s"%(sc.get("type"),sc.get("persona_key")))
    if sid in done: continue
    try:
        rp=responder(sc); jg=judge(sc,rp)
    except Exception as e:
        print("[eval] ERR %s: %s"%(sid,str(e)[:80]),flush=True); continue
    rec={"id":sid,"type":sc.get("type"),"persona_key":sc.get("persona_key"),"persona_name":sc.get("persona_name"),
         "diff_set":sc.get("diff_set",""),"player_message":sc.get("player_message",""),**rp,**jg}
    out.write(json.dumps(rec,ensure_ascii=False)+"\n"); out.flush(); n+=1
    print("[eval] %d/%d %-22s 入戏%d 扣境%d 具体%d | pre=%d dec=%d(reason%d) | %s→%s"%(
        n,len(scen)-len(done),sid,jg["in_char"],jg["grounded"],jg["specific"],
        rp["prompt_tokens"],rp["response_tokens"],rp["reasoning_tokens"],rp["action"][:12],rp["line"][:24]),flush=True)
out.close()
print("[eval] DONE %d new, %.1f min"%(n,(time.time()-t0)/60),flush=True)
