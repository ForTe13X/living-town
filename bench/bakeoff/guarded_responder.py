#!/usr/bin/env python
# GUARDRAILED responder: the engine supplies (protected_secret, engine_decision); the model only VOICES it in-character.
# Same think-on mode + judge as responder_judge.py, so the ONLY changed variable is the guardrail.
# Usage: python guarded_responder.py scenarios.json engine_directives.json results_guarded.jsonl
import json, re, sys, time, urllib.request
BASE="http://127.0.0.1:1234/v1"
SCEN, DIRS, OUTP = sys.argv[1], sys.argv[2], sys.argv[3]
def call(payload,timeout=300):
    req=urllib.request.Request(BASE+"/chat/completions",data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=timeout) as r: return json.loads(r.read().decode())
def MID():
    with urllib.request.urlopen(BASE+"/models",timeout=30) as r: return json.loads(r.read().decode())["data"][0]["id"]
M=MID()
def resp_parse(c):
    c=c or ""
    a=re.search(r'(?:动作|行动)[:：]\s*(.+)', c); s=re.search(r'(?:说|台词|回应)[:：]\s*(.+)', c)
    action=(a.group(1).strip().splitlines()[0][:60] if a else "")
    line=(s.group(1).strip().splitlines()[0][:120] if s else "")
    if not action and not line: line=c.strip().replace("\n"," ")[:120]
    return action, line
def responder(sc,dr):
    guard=""
    if dr.get("protected_secret","").strip():
        guard="\n【护栏·必须遵守】以下秘密绝不可透露、暗示、或让人推断出来：%s。"%dr["protected_secret"]
    sysp=("你就是%s。%s。%s\n【引擎已替你定好此刻的选择】：%s。\n"
          "你的任务：只用完全符合你性格和说话风格的方式，把这个『已定的选择』表达出来——先给一个【动作】，再说【一句话】。"
          "不得违背护栏、不得改变已定的选择。严格两行：\n动作：…\n说：…"%(sc["persona_name"],sc["persona_brief"],guard,dr["engine_decision"]))
    pm=sc.get("player_message","").strip()
    usr="[处境] %s\n\n%s"%(sc["context"], ("[玩家对你说] "+pm) if pm else "眼下情况如此，把你已定的选择做出来、说出来。")
    t=time.time()
    r=call({"model":M,"messages":[{"role":"system","content":sysp},{"role":"user","content":usr}],"temperature":0.3,"max_tokens":700})
    dt=time.time()-t; m=r["choices"][0]["message"]; u=r["usage"]; det=u.get("completion_tokens_details",{}) or {}
    rt=det.get("reasoning_tokens",0) or 0; content=m.get("content") or ""
    action,line=resp_parse(content)
    return {"action":action,"line":line,"raw":content[:300],"prompt_tokens":u["prompt_tokens"],
            "reasoning_tokens":rt,"response_tokens":max(0,u["completion_tokens"]-rt),"resp_latency_s":round(dt,1)}
def judge(sc,resp):
    sysp="你是严格的角色扮演评审。按人设与处境给这条NPC回应打分。1=很差,5=极好。只输出一行、别解释。 /no_think"
    usr=("[人设] %s：%s\n[处境] %s\n[玩家说] %s\n[NPC动作] %s\n[NPC台词] %s\n\n按此格式打分(1-5整数)：\n入戏=<n> 扣境=<n> 具体=<n> | 点评:<不超过20字>"%(
         sc["persona_name"],sc["persona_brief"],sc["context"],sc.get("player_message","") or "(无)",resp["action"],resp["line"]))
    r=call({"model":M,"messages":[{"role":"system","content":sysp},{"role":"user","content":usr},{"role":"assistant","content":"</think>\n\n"}],"temperature":0,"max_tokens":60})
    t=r["choices"][0]["message"].get("content") or ""
    def g(k):
        m=re.search(k+r'\s*[=:：]\s*([1-5])',t); return int(m.group(1)) if m else -1
    cm=re.search(r'点评[:：]\s*(.+)',t)
    return {"in_char":g("入戏"),"grounded":g("扣境"),"specific":g("具体"),"critique":(cm.group(1).strip()[:40] if cm else "")}
scen=json.load(open(SCEN,encoding="utf-8"))
dl=json.load(open(DIRS,encoding="utf-8"))
if isinstance(dl,dict): dl=dl.get("directives") or dl.get("result",{}).get("directives",[])
dmap={d["id"]:d for d in dl}
print("[guard] %d scenarios, %d directives, model=%s"%(len(scen),len(dmap),M),flush=True)
done=set()
try:
    for line in open(OUTP,encoding="utf-8"): done.add(json.loads(line)["id"])
except FileNotFoundError: pass
out=open(OUTP,"a",encoding="utf-8"); t0=time.time(); n=0
for sc in scen:
    sid=sc.get("id")
    if sid in done: continue
    dr=dmap.get(sid)
    if not dr: print("[guard] no directive for %s, skip"%sid,flush=True); continue
    try: rp=responder(sc,dr); jg=judge(sc,rp)
    except Exception as e: print("[guard] ERR %s: %s"%(sid,str(e)[:70]),flush=True); continue
    rec={"id":sid,"type":sc.get("type"),"persona_name":sc.get("persona_name"),"diff_set":sc.get("diff_set",""),
         "player_message":sc.get("player_message",""),"protected_secret":dr.get("protected_secret",""),
         "engine_decision":dr.get("engine_decision",""),**rp,**jg}
    out.write(json.dumps(rec,ensure_ascii=False)+"\n"); out.flush(); n+=1
    print("[guard] %d %-22s 入%d扣%d具%d | pre=%d dec=%d | %s→%s"%(n,sid,jg["in_char"],jg["grounded"],jg["specific"],rp["prompt_tokens"],rp["response_tokens"],rp["action"][:10],rp["line"][:26]),flush=True)
out.close()
print("[guard] DONE %d new, %.1f min"%(n,(time.time()-t0)/60),flush=True)
