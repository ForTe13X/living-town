#!/usr/bin/env python
# Faction-moment blind judge: rally_oust (incite a mob against an out-group person) vs abstain
# (=best non-aggression action). Logic picks rally_oust 49% of the time across ALL personas — the
# always-confront analog. Is mobbing in-character? Judge the structural choice blind, mirror-flipped,
# with A=A controls. Output feeds the judge subagents. Usage: python build_faction_judge.py <pk.jsonl> <out.json> [N=72] [exclude_mapping]
import json, sys, os
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import render_case, canon, K_CAND, K_MEAN, K_OBJ

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
def rally_id(r):
    for c in r["case"][K_CAND]:
        if c["action"]=="rally_oust": return c["id"]
    return None
def response_options():
    # Phase D 语义契约：abstain 是【针对同一 rally_oust 机会的一等 ResponseIntent】——consciously stay out，
    # 不再冒充"最高分非攻击动作"。两项对称的结构化意图描述(具体对象由 packet 语境交代)→ 评的是【选择】。
    rally=("【当众发难、联合大家一起施压】——把那个跟你们不对付的人排挤出去。")
    abstain=("【不参与这场围攻】——不煽动也不跟着起哄，置身事外。")
    return rally,abstain

exclude=set()
if len(sys.argv)>4 and os.path.exists(sys.argv[4]):
    exclude={v["key"] for v in json.load(open(sys.argv[4],encoding="utf-8")).values()}

rows=[]
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if key(d) in exclude: continue
    if any(c["action"]=="rally_oust" for c in d["case"][K_CAND]): rows.append(d)
buck=defaultdict(list)
for r in sorted(rows,key=key): buck[r["persona"]].append(r)
per=max(1,N//max(1,len(buck))); sample=[]
for k in sorted(buck):
    a=buck[k]; sample+=a[::max(1,len(a)//per)][:per]
sample=sorted(sample,key=key)[:N]

tasks=[]; controls=0
for idx,r in enumerate(sample):
    ri=rally_id(r)
    if not ri: continue                        # 只在"联合施压"确为合法候选的局里比
    ro,ab=response_options(); ctx=context_text(r["case"])
    for orient in (0,1):
        if orient==0: A,B,As,Bs=ro,ab,"rally_oust","abstain"
        else:         A,B,As,Bs=ab,ro,"abstain","rally_oust"
        tasks.append({"tid":"%s#%d"%(key(r),orient),"key":key(r),"seed":r["seed"],"orient":orient,
            "A_text":A,"B_text":B,"A_src":As,"B_src":Bs,"persona":r["persona"],"status":"faction","severity":0,"packet":ctx})
    if idx%9==4:
        controls+=1
        tasks.append({"tid":"%s#ctl"%key(r),"key":key(r),"seed":r["seed"],"orient":9,
            "A_text":ab,"B_text":ab,"A_src":"abstain","B_src":"abstain","persona":r["persona"],"status":"faction","severity":0,"packet":ctx})
json.dump({"tasks":tasks,"n_cases":len(sample),"n_tasks":len(tasks),"n_controls":controls,"kind":"rally_vs_abstain"},
    open(OUTP,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
print("rally_oust cases=%d sampled=%d tasks=%d (+%d controls); personas=%s"%(
    len(rows),len(sample),len(tasks),controls,dict((k,len(v)) for k,v in sorted(buck.items()))))
