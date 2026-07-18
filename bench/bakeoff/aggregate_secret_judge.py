#!/usr/bin/env python
# Aggregate the secret-stake blind judge (leak/betray vs guard/keep-faith).
# Maps blind A/B → leak/guard via the held-out mapping, mirror-combines, cluster-bootstraps p_eff(leak).
# DIRECTION: p_eff(leak) high → judge favors betrayal (logic's never-leak is wrong);
#            low → judge favors GUARD (logic's never-leak is validated); straddle 0.5 → wash.
# Plus a feature probe: does resentment-toward-the-confider or a gossipy(爱八卦) persona flip to leak?
# Usage: python aggregate_secret_judge.py <judge_dir>
import json, sys, os, glob, random
from collections import defaultdict, Counter

JD=sys.argv[1]
mapping=json.load(open(os.path.join(JD,"mapping.json"),encoding="utf-8"))
verdicts=[]
for f in glob.glob(os.path.join(JD,"verdicts","verdict_*.json")):
    try: verdicts+=json.load(open(f,encoding="utf-8"))
    except Exception as e: print("WARN",f,e)
print("loaded %d verdicts, %d mapping"%(len(verdicts),len(mapping)))

def winner(v):
    m=mapping.get(v["tid"])
    if not m: return None
    if v["choice"]=="平": return "tie"
    return m["A_src"] if v["choice"]=="A" else m["B_src"]

ctl=[v for v in verdicts if v["tid"].endswith("#ctl")]
ctl_tie=sum(1 for v in ctl if v["choice"]=="平")
SCORE={"leak":1.0,"tie":0.5,"guard":0.0}
bycase=defaultdict(dict); meta={}
for v in verdicts:
    if v["tid"].endswith("#ctl"): continue
    m=mapping.get(v["tid"]);
    if not m: continue
    w=winner(v)
    if w is None: continue
    bycase[m["key"]][m["orient"]]=w; meta[m["key"]]=m
cases=[]; consistent=0
for k,ors in bycase.items():
    ws=list(ors.values()); s=sum(SCORE[w] for w in ws)/len(ws)
    consistent += (len(set(ws))==1)
    cases.append({"key":k,"seed":meta[k]["seed"],"p":s,"persona":meta[k]["persona"],
        "resent":meta[k]["resent"],"gossipy":meta[k]["gossipy"]})
n=len(cases)
if n==0: print("no cases"); sys.exit(0)
peff=sum(c["p"] for c in cases)/n
seeds=sorted(set(c["seed"] for c in cases)); by_seed=defaultdict(list)
for c in cases: by_seed[c["seed"]].append(c["p"])
rng=random.Random(999); boots=[]
for _ in range(3000):
    pool=[]
    for _s in seeds: pool+=by_seed[rng.choice(seeds)]
    boots.append(sum(pool)/len(pool))
boots.sort(); lo=boots[int(0.025*len(boots))]; hi=boots[int(0.975*len(boots))]
raw=Counter(winner(v) for v in verdicts if not v["tid"].endswith("#ctl"))

print("="*60)
print("SECRET-STAKE BLIND JUDGE — leak(betray) vs guard(keep faith)")
print("="*60)
print("  cases=%d seeds=%s mirror-consistency=%.0f%%"%(n,seeds,100*consistent/n))
print("  raw orientations: leak=%d guard=%d tie=%d"%(raw["leak"],raw["guard"],raw["tie"]))
print("  A=A controls: %d/%d judged 平 (%.0f%%)"%(ctl_tie,len(ctl),100*ctl_tie/max(1,len(ctl))))
print("  p_eff(LEAK) = %.3f  95%% CI [%.3f,%.3f]"%(peff,lo,hi))
verdict=("favors LEAK (logic's never-leak is wrong)" if lo>0.5 else
         "favors GUARD (logic's never-leak VALIDATED — keep faith is in-character)" if hi<0.5 else
         "WASH / mixed")
print("  DIRECTION: %s"%verdict)
print("  --- feature probe: leak-rate (p_eff) by segment ---")
def seg(fn,label):
    g=defaultdict(list)
    for c in cases: g[fn(c)].append(c["p"])
    for k in sorted(g,key=str): a=g[k]; print("    %-22s p_eff(leak)=%.3f (n=%d)"%(label+":"+str(k),sum(a)/len(a),len(a)))
seg(lambda c:c["resent"]>0,"resent-toward-confider")
seg(lambda c:c["gossipy"],"gossipy(爱八卦)")
# personas with any leak lean
plean=defaultdict(list)
for c in cases: plean[c["persona"]].append(c["p"])
print("    persona leak-lean (p_eff>0.3):", {k:round(sum(v)/len(v),2) for k,v in sorted(plean.items()) if sum(v)/len(v)>0.3} or "none")
print("="*60)
lw=[v for v in verdicts if winner(v)=="leak" and not v["tid"].endswith("#ctl")][:4]
gw=[v for v in verdicts if winner(v)=="guard" and not v["tid"].endswith("#ctl")][:3]
print("sample reasons — judge chose LEAK:")
for v in lw: print("   ",v.get("reason",""))
print("sample reasons — judge chose GUARD:")
for v in gw: print("   ",v.get("reason",""))
json.dump({"n":n,"peff_leak":peff,"ci":[lo,hi],"direction":verdict,"consistency":consistent/n,
    "raw":dict(raw),"ctl_tie":ctl_tie/max(1,len(ctl))},open(os.path.join(JD,"secret_judge_summary.json"),"w"),indent=2)
