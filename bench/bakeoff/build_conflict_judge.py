#!/usr/bin/env python
# Clean blind judge — set the knob direction on OPEN-GRIEVANCE (aggrieved) cases.
# Phase D 语义契约版：judge 评的是同一心结下的【结构化选择】——confront(X) vs a FIRST-CLASS defer
# ("consciously let the grudge with X lie"). defer 不再是"最高分非冲突动作(睡觉/吃饭/寒暄)"——那测的是
# 日常动作 base rate、不是"对质 vs 明确延期"。两项以对称的结构化意图描述呈现(无差异化台词)→ 评的是选择、
# 非文采。Mirror-flip 抵消位置偏置；A=A control 校准 tie 率。Output feeds the judge Workflow。
# Usage: python build_conflict_judge.py <packet_v1.jsonl> <out.json> [N=72]
import json, sys, os
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import render_case, canon, K_CAND, K_MEAN, K_OBJ

DATA=sys.argv[1]; OUTP=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 72
CONFLICT={"confront","apologize","mediate"}
# defer must be a genuine let-it-lie: exclude indirect aggression too (rally_oust/gossip_rep/endorse/leak/gossip)
AGGRESSION={"confront","apologize","mediate","rally_oust","gossip_rep","endorse","leak","gossip"}

def key(r): return "%d:%d:%s"%(r["seed"],r["tick"],r["agent"])
def mean_of(case,cid):
    for c in case[K_CAND]:
        if c["id"]==cid:
            o=c.get(K_OBJ,""); return c.get(K_MEAN,"")+((" →"+o) if o else "")
    return None
def context_text(case):
    return render_case(case, list(range(len(case[K_CAND]))), salient=True).split("【候选】")[0].strip()

def target_griev(r):
    gs=r.get("grievances",[])
    if not gs: return None
    oi=r["id_map"].get(r["logic_pick_id"]); pid=r["cands"][oi].get("partner") if oi is not None else None
    return next((g for g in gs if g.get("other_id")==pid), None) or max(gs,key=lambda g:g["severity"])

def confront_id(r,tg):
    for c in r["case"][K_CAND]:
        if c["action"]=="confront":
            oi=r["id_map"].get(c["id"])
            if oi is not None and r["cands"][oi].get("partner")==tg["other_id"]: return c["id"]
    return None
def response_options(tg):
    # Phase D 语义契约：defer 是【针对同一心结的一等 ResponseIntent】——"consciously let the grudge lie"，
    # 不再冒充成"最高分日常动作(睡觉/吃饭/寒暄)"。两项都以【结构化意图描述】呈现(不给差异化台词)，
    # 让 judge 评的是"这个人设面对这桩心结会不会当面挑破"这个【选择】，而非台词文采——消除旧 confront-vs-maintenance 混淆。
    other=tg["other"]
    confront=("径直去找%s，把心里这桩怨气【当面说开、把话挑明】——宁可把关系闹僵，也要把这口气讲清楚。"%other)
    defer=("把和%s的这点过节【先按下不表】——不当面挑破、维持面上的平和，自己把怨气消化掉（真到日后过不去，再找机会说）。"%other)
    return confront,defer

# optional 4th arg = a previous mapping.json whose case keys to EXCLUDE (for a disjoint held-out sample)
exclude_keys=set()
if len(sys.argv)>4 and os.path.exists(sys.argv[4]):
    m=json.load(open(sys.argv[4],encoding="utf-8"))
    exclude_keys={v["key"] for v in m.values()}
    print("excluding %d prior-sample case keys (held-out mode)"%len(exclude_keys))

# select OPEN-GRIEVANCE (aggrieved) cases, stratified by (status × persona)
rows=[]
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if not (d.get("strata",{}).get("has_grievance") and d.get("strata",{}).get("has_conflict_cand")): continue
    if key(d) in exclude_keys: continue
    tg=target_griev(d)
    if tg and tg["role"]=="aggrieved": rows.append(d)
# Phase D 事件窗口去重：同一心结(seed,agent,对象)在同一 status 阶段会横跨很多 tick → 近似重复。每个
# (episode × 阶段) 只留最早一例 → 案例相互独立（后续按 seed cluster-bootstrap 才不虚增有效样本）。
seen_ep={}; dedup=[]
for r in sorted(rows, key=lambda r:(r["seed"], r["agent"], r["tick"])):
    tg=target_griev(r); ek=(r["seed"], r["agent"], tg["other_id"], tg["status"])
    if ek in seen_ep: continue
    seen_ep[ek]=1; dedup.append(r)
rows=dedup
buck=defaultdict(list)
for r in sorted(rows,key=key):
    tg=target_griev(r); buck[(tg["status"],r["persona"])].append(r)
per=max(1,N//max(1,len(buck))); sample=[]
for k in sorted(buck):
    a=buck[k]; sample+=a[::max(1,len(a)//per)][:per]
sample=sorted(sample,key=key)[:N]

tasks=[]; controls=0
for idx,r in enumerate(sample):
    tg=target_griev(r); cfi=confront_id(r,tg)
    if not cfi: continue                       # 只在"当面对质"确为合法候选的局里比（否则 confront/defer 对照无意义）
    confront,defer=response_options(tg)
    ctx=context_text(r["case"])
    for orient in (0,1):
        if orient==0: A,B,As,Bs=confront,defer,"confront","defer"
        else:         A,B,As,Bs=defer,confront,"defer","confront"
        tasks.append({"tid":"%s#%d"%(key(r),orient),"key":key(r),"seed":r["seed"],"orient":orient,
            "A_text":A,"B_text":B,"A_src":As,"B_src":Bs,
            "status":tg["status"],"severity":tg["severity"],"persona":r["persona"],"packet":ctx})
    # A=A control on ~1/9 of cases (both = defer) → judge should say 平（校准 tie 率）
    if idx%9==4:
        controls+=1
        tasks.append({"tid":"%s#ctl"%key(r),"key":key(r),"seed":r["seed"],"orient":9,
            "A_text":defer,"B_text":defer,"A_src":"defer","B_src":"defer",
            "status":tg["status"],"severity":tg["severity"],"persona":r["persona"],"packet":ctx})

json.dump({"tasks":tasks,"n_cases":len(sample),"n_tasks":len(tasks),"n_controls":controls,
    "kind":"confront_vs_defer"}, open(OUTP,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
print("aggrieved cases=%d  sampled=%d  judge tasks=%d (mirror x2 + %d A=A controls)"%(
    len(rows),len(sample),len(tasks),controls))
from collections import Counter
print("status spread in sample:",dict(Counter(target_griev(r)["status"] for r in sample)))
