#!/usr/bin/env python
# Clean blind judge — set the knob direction on OPEN-GRIEVANCE cases.
# The engine engages (logic always confronts, 100%); the LLM defers (only 37% confront). Which is more
# in-character? We judge the STRUCTURAL choice — confront(X) vs defer(=best non-conflict action) — over
# the same salient context, blind. No dependence on the noisy LLM pick. Mirror-flip cancels position bias;
# a few A=A controls calibrate the judge's tie rate. Output feeds the judge Workflow.
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
def defer_id(r):
    # best NON-aggression candidate by logic score (maintenance or a benign/conciliatory social)
    best=None; bs=-1e9
    for c in r["case"][K_CAND]:
        if c["action"] in AGGRESSION: continue
        oi=r["id_map"].get(c["id"]); sc=r["cands"][oi].get("score",0.0) if oi is not None else 0.0
        if sc>bs: bs=sc; best=c["id"]
    return best

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
buck=defaultdict(list)
for r in sorted(rows,key=key):
    tg=target_griev(r); buck[(tg["status"],r["persona"])].append(r)
per=max(1,N//max(1,len(buck))); sample=[]
for k in sorted(buck):
    a=buck[k]; sample+=a[::max(1,len(a)//per)][:per]
sample=sorted(sample,key=key)[:N]

tasks=[]; controls=0
for idx,r in enumerate(sample):
    tg=target_griev(r); cfi=confront_id(r,tg); dfi=defer_id(r)
    if not cfi or not dfi: continue
    conf=mean_of(r["case"],cfi); defr=mean_of(r["case"],dfi)
    ctx=context_text(r["case"])
    for orient in (0,1):
        if orient==0: A,B,As,Bs=conf,defr,"confront","defer"
        else:         A,B,As,Bs=defr,conf,"defer","confront"
        tasks.append({"tid":"%s#%d"%(key(r),orient),"key":key(r),"seed":r["seed"],"orient":orient,
            "A_text":A,"B_text":B,"A_src":As,"B_src":Bs,
            "status":tg["status"],"severity":tg["severity"],"persona":r["persona"],"packet":ctx})
    # A=A control on ~1/9 of cases (both = defer) → judge should say 平
    if idx%9==4:
        controls+=1
        tasks.append({"tid":"%s#ctl"%key(r),"key":key(r),"seed":r["seed"],"orient":9,
            "A_text":defr,"B_text":defr,"A_src":"defer","B_src":"defer",
            "status":tg["status"],"severity":tg["severity"],"persona":r["persona"],"packet":ctx})

json.dump({"tasks":tasks,"n_cases":len(sample),"n_tasks":len(tasks),"n_controls":controls,
    "kind":"confront_vs_defer"}, open(OUTP,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
print("aggrieved cases=%d  sampled=%d  judge tasks=%d (mirror x2 + %d A=A controls)"%(
    len(rows),len(sample),len(tasks),controls))
from collections import Counter
print("status spread in sample:",dict(Counter(target_griev(r)["status"] for r in sample)))
