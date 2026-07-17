#!/usr/bin/env python
# Scoped decisive re-test — STEP B2: aggregate blind-judge verdicts.
# Combines mirror-flipped orientations (cancels position bias), computes p_eff(teacher) =
# (teacher_win + 0.5*tie)/evaluable, cluster-bootstraps a CI by SEED (trajectories are correlated),
# and breaks down by divergence type (engage/defer), stance, status, severity.
# Pre-registered gate (per Codex review): teacher p_eff >= 0.60 with CI-lower > 0.55.
# Usage: python aggregate_judge.py <verdicts.json>
import json, sys, random
from collections import defaultdict, Counter

V=json.load(open(sys.argv[1],encoding="utf-8"))
verdicts=V["verdicts"] if isinstance(V,dict) and "verdicts" in V else V
SCORE={"teacher":1.0,"tie":0.5,"logic":0.0}

# group by case key -> {orient: winner}
bycase=defaultdict(dict)
meta={}
for v in verdicts:
    bycase[v["key"]][v["orient"]]=v["winner"]
    meta[v["key"]]=v   # keep last for stance/status/severity/te/le

cases=[]
consistent=0
for k,orients in bycase.items():
    ws=list(orients.values())
    s=sum(SCORE[w] for w in ws)/len(ws)     # avg over available orientations
    # consistency: both orientations name the same winner side (or both tie)
    cons = len(set(ws))==1
    if cons: consistent+=1
    m=meta[k]
    cases.append({"key":k,"seed":m["seed"],"p":s,"cons":cons,
        "dtype":("defer" if not m["te"] else "engage")+"→"+("logic:"+("engage" if m["le"] else "defer")),
        "te":m["te"],"le":m["le"],"stance":m["stance"],"status":m["status"],"severity":m["severity"]})

n=len(cases)
if n==0:
    print("no divergent cases judged."); sys.exit(0)
peff=sum(c["p"] for c in cases)/n

# cluster-bootstrap by seed
seeds=sorted(set(c["seed"] for c in cases))
by_seed=defaultdict(list)
for c in cases: by_seed[c["seed"]].append(c["p"])
rng=random.Random(12345)
boots=[]
for _ in range(2000):
    pool=[]
    for _s in seeds:
        s=rng.choice(seeds)
        pool+=by_seed[s]
    boots.append(sum(pool)/len(pool))
boots.sort()
lo=boots[int(0.025*len(boots))]; hi=boots[int(0.975*len(boots))]

print("="*58)
print("BLIND JUDGE — teacher(salient) vs logic  (divergent cases only)")
print("="*58)
print("  cases judged            %d   (seeds=%s)"%(n,seeds))
print("  mirror consistency      %.0f%%  (both orientations agree)"%(100*consistent/n))
raw=Counter(v["winner"] for v in verdicts)
print("  raw verdict tally       teacher=%d logic=%d tie=%d (of %d orientations)"%(
    raw["teacher"],raw["logic"],raw["tie"],len(verdicts)))
print("  ---")
print("  p_eff(teacher)          %.3f   95%% CI [%.3f, %.3f]  (cluster-boot by seed)"%(peff,lo,hi))
gate = peff>=0.60 and lo>0.55
print("  GATE teacher>=0.60 & CI-lo>0.55:  %s"%("PASS ✅" if gate else "FAIL ❌"))
print("  ---  breakdowns  ---")
def bd(keyfn,label):
    g=defaultdict(list)
    for c in cases: g[keyfn(c)].append(c["p"])
    for k in sorted(g):
        a=g[k]; print("  %-22s p_eff=%.3f  (n=%d)"%(label+":"+str(k),sum(a)/len(a),len(a)))
bd(lambda c:c["dtype"],"divergence")
bd(lambda c:c["stance"],"stance")
bd(lambda c:("sev<5" if c["severity"]<5 else "sev5-9"),"severity")
print("="*58)

# a few illustrative reasons where teacher won / logic won
tw=[v for v in verdicts if v["winner"]=="teacher"][:4]
lw=[v for v in verdicts if v["winner"]=="logic"][:4]
print("\nsample reasons — TEACHER preferred:")
for v in tw: print("  [%s] %s"%(v["key"],v.get("reason","")))
print("sample reasons — LOGIC preferred:")
for v in lw: print("  [%s] %s"%(v["key"],v.get("reason","")))

json.dump({"n":n,"peff":peff,"ci":[lo,hi],"gate":gate,
    "consistency":consistent/n,"raw":dict(raw),
    "by_dtype":{k:sum(g)/len(g) for k,g in {kk:[c["p"] for c in cases if c["dtype"]==kk] for kk in set(c["dtype"] for c in cases)}.items()}},
    open(sys.argv[1].replace(".json","_summary.json"),"w"), indent=2)
