#!/usr/bin/env python
# Endorse blind judge: endorse (huddle with a faction-mate to badmouth/isolate an out-group person Y)
# vs abstain (=best non-aggression action). Milder than rally_oust but still a coordinated reputation
# attack; logic picks it ~29%. Is it in-character? Judge the structural choice blind, mirror-flipped,
# with A=A controls. Usage: python build_endorse_judge.py <pk.jsonl> <out.json> [N=72] [exclude_mapping]
import json, sys, os
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import render_case, K_CAND, K_MEAN, K_OBJ

DATA=sys.argv[1]; OUTP=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 72
AGGRESSION={"confront","apologize","mediate","rally_oust","gossip_rep","endorse","leak","gossip"}

def key(r): return "%d:%d:%s"%(r["seed"],r["tick"],r["agent"])
def mean_of(case,cid):
    for c in case[K_CAND]:
        if c["id"]==cid:
            o=c.get(K_OBJ,""); return c.get(K_MEAN,"")+((" →"+o) if o else "")
    return None
def context_text(case):
    return render_case(case, list(range(len(case[K_CAND]))), salient=True).split("【候选】")[0].strip()
def endorse_id(r):
    for c in r["case"][K_CAND]:
        if c["action"]=="endorse": return c["id"]
    return None
def abstain_id(r):
    best=None; bs=-1e9
    for c in r["case"][K_CAND]:
        if c["action"] in AGGRESSION: continue
        oi=r["id_map"].get(c["id"]); sc=r["cands"][oi].get("score",0.0) if oi is not None else 0.0
        if sc>bs: bs=sc; best=c["id"]
    return best

exclude=set()
if len(sys.argv)>4 and os.path.exists(sys.argv[4]):
    exclude={v["key"] for v in json.load(open(sys.argv[4],encoding="utf-8")).values()}

rows=[]
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if key(d) in exclude: continue
    if any(c["action"]=="endorse" for c in d["case"][K_CAND]): rows.append(d)
buck=defaultdict(list)
for r in sorted(rows,key=key): buck[r["persona"]].append(r)
per=max(1,N//max(1,len(buck))); sample=[]
for k in sorted(buck):
    a=buck[k]; sample+=a[::max(1,len(a)//per)][:per]
sample=sorted(sample,key=key)[:N]

tasks=[]; controls=0
for idx,r in enumerate(sample):
    ei=endorse_id(r); ai=abstain_id(r)
    if not ei or not ai: continue
    en=mean_of(r["case"],ei); ab=mean_of(r["case"],ai); ctx=context_text(r["case"])
    for orient in (0,1):
        if orient==0: A,B,As,Bs=en,ab,"endorse","abstain"
        else:         A,B,As,Bs=ab,en,"abstain","endorse"
        tasks.append({"tid":"%s#%d"%(key(r),orient),"key":key(r),"seed":r["seed"],"orient":orient,
            "A_text":A,"B_text":B,"A_src":As,"B_src":Bs,"persona":r["persona"],"status":"faction","severity":0,"packet":ctx})
    if idx%9==4:
        controls+=1
        tasks.append({"tid":"%s#ctl"%key(r),"key":key(r),"seed":r["seed"],"orient":9,
            "A_text":ab,"B_text":ab,"A_src":"abstain","B_src":"abstain","persona":r["persona"],"status":"faction","severity":0,"packet":ctx})
json.dump({"tasks":tasks,"n_cases":len(sample),"n_tasks":len(tasks),"n_controls":controls,"kind":"endorse_vs_abstain"},
    open(OUTP,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
print("endorse cases=%d sampled=%d tasks=%d (+%d controls); personas=%s"%(
    len(rows),len(sample),len(tasks),controls,dict((k,len(v)) for k,v in sorted(buck.items()))))
