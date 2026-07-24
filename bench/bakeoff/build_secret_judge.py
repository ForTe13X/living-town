#!/usr/bin/env python
# Secret-stake blind judge — set the direction on the BETRAYAL decision.
# Logic never leaks (0/1054). Is universal GUARD in-character, or should some personas (gossipy /
# resentful-toward-the-confider) BETRAY? We judge the structural choice — leak(betray) vs guard(keep
# faith = best non-aggression action) — over the same salient context, blind. Mirror-flip + A=A controls.
# Usage: python build_secret_judge.py <packet.jsonl> <out.json> [N=66]
import json, sys, os
from collections import defaultdict, Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import render_case, K_CAND, K_MEAN, K_OBJ

DATA=sys.argv[1]; OUTP=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 66
AGGRESSION={"confront","apologize","mediate","rally_oust","gossip_rep","endorse","leak","gossip"}

def key(r): return "%d:%d:%s"%(r["seed"],r["tick"],r["agent"])
def mean_of(case,cid):
    for c in case[K_CAND]:
        if c["id"]==cid:
            o=c.get(K_OBJ,""); return c.get(K_MEAN,"")+((" →"+o) if o else "")
    return None
def context_text(case):
    return render_case(case, list(range(len(case[K_CAND]))), salient=True).split("【候选】")[0].strip()

def leak_id(r):
    # the most tempting leak = highest logic score among leak candidates
    best=None; bs=-1e9
    for c in r["case"][K_CAND]:
        if c["action"]!="leak": continue
        oi=r["id_map"].get(c["id"]); sc=r["cands"][oi].get("score",0.0) if oi is not None else 0.0
        if sc>bs: bs=sc; best=c["id"]
    return best
def response_options():
    # Phase D 语义契约：guard 是【针对同一桩秘密的一等 ResponseIntent】——consciously keep faith，
    # 不再冒充"最高分非攻击动作"。两项对称的结构化意图描述(具体秘密/对象由 packet 语境交代)→ 评的是【选择】。
    leak=("【把你知道的这桩私密说出去】——抖落给对方听，背弃当初信任你的人。")
    guard=("【守口如瓶】——把这桩私密咽在肚子里，守住当初的信任，绝不外传。")
    return leak,guard
def max_resent(r):
    return max([s.get("resent_teller",0) for s in r.get("secret_stakes",[])] or [0])

# select secret-stake cases (a leak candidate present + typed stake), stratify by (persona, resent>0)
rows=[]
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if d.get("secret_stakes") and any(c["action"]=="leak" for c in d["case"][K_CAND]):
        rows.append(d)
_seen={}; _dd=[]                                # Phase D 事件窗口去重：每(seed,agent)一例→案例独立
for r in sorted(rows,key=lambda r:(r["seed"],r["tick"])):
    ek=(r["seed"],r["agent"])
    if ek in _seen: continue
    _seen[ek]=1; _dd.append(r)
rows=_dd
buck=defaultdict(list)
for r in sorted(rows,key=key):
    buck[(r["persona"], max_resent(r)>0)].append(r)
per=max(1,N//max(1,len(buck))); sample=[]
for k in sorted(buck, key=lambda x:(x[0],x[1])):
    a=buck[k]; sample+=a[::max(1,len(a)//per)][:per]
_s=sorted(sample,key=lambda r:(r["seed"],r["tick"])); sample=_s[::max(1,len(_s)//N)][:N]  # Phase D：铺满 seed（见 conflict builder 注释）

tasks=[]; controls=0
for idx,r in enumerate(sample):
    li=leak_id(r)
    if not li: continue                        # 只在"泄密"确为合法候选的局里比
    leak,guard=response_options(); ctx=context_text(r["case"])
    for orient in (0,1):
        if orient==0: A,B,As,Bs=leak,guard,"leak","guard"
        else:         A,B,As,Bs=guard,leak,"guard","leak"
        tasks.append({"tid":"%s#%d"%(key(r),orient),"key":key(r),"seed":r["seed"],"orient":orient,
            "A_text":A,"B_text":B,"A_src":As,"B_src":Bs,
            "persona":r["persona"],"resent":max_resent(r),"gossipy":("爱八卦" in r["case"].get("居民",{}).get("性格",[])),
            "packet":ctx})
    if idx%9==4:
        controls+=1
        tasks.append({"tid":"%s#ctl"%key(r),"key":key(r),"seed":r["seed"],"orient":9,
            "A_text":guard,"B_text":guard,"A_src":"guard","B_src":"guard",
            "persona":r["persona"],"resent":max_resent(r),"gossipy":False,"packet":ctx})

json.dump({"tasks":tasks,"n_cases":len(sample),"n_tasks":len(tasks),"n_controls":controls,
    "kind":"leak_vs_guard"}, open(OUTP,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
print("secret-stake cases=%d  sampled=%d  judge tasks=%d (mirror x2 + %d controls)"%(
    len(rows),len(sample),len(tasks),controls))
print("sample persona spread:",dict(Counter(r["persona"] for r in sample)))
print("sample with resent-toward-teller:",sum(1 for r in sample if max_resent(r)>0),
      "| gossipy(aria):",sum(1 for r in sample if r["persona"]=="aria"))
