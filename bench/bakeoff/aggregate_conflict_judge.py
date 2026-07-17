#!/usr/bin/env python
# Aggregate the clean blind judge (confront vs defer on open-grievance cases).
# Maps each blind A/B choice back to confront/defer via the held-out mapping, combines mirror-flip pairs
# (cancels position bias), computes p_eff(confront) with a seed cluster-bootstrap, and reports the KNOB
# DIRECTION: >0.5 favors logic's confront; <0.5 favors the LLM's defer; straddling 0.5 = genuine wash.
# Usage: python aggregate_conflict_judge.py <judge_dir>
import json, sys, os, glob, random
from collections import defaultdict, Counter

JD=sys.argv[1]
mapping=json.load(open(os.path.join(JD,"mapping.json"),encoding="utf-8"))
verdicts=[]
for f in glob.glob(os.path.join(JD,"verdicts","verdict_*.json")):
    try: verdicts+=json.load(open(f,encoding="utf-8"))
    except Exception as e: print("WARN bad verdict file %s: %s"%(f,e))
print("loaded %d verdicts, %d tasks in mapping"%(len(verdicts),len(mapping)))

def winner(v):
    m=mapping.get(v["tid"])
    if not m: return None
    if v["choice"]=="平": return "tie"
    return m["A_src"] if v["choice"]=="A" else m["B_src"]

# controls (A=A, both defer) → judge should say 平
ctl=[v for v in verdicts if v["tid"].endswith("#ctl")]
ctl_tie=sum(1 for v in ctl if v["choice"]=="平")
# real tasks by case key
SCORE={"confront":1.0,"tie":0.5,"defer":0.0}
bycase=defaultdict(dict); meta={}
for v in verdicts:
    if v["tid"].endswith("#ctl"): continue
    m=mapping.get(v["tid"]);
    if not m: continue
    w=winner(v)
    if w is None: continue
    bycase[m["key"]][m["orient"]]=w
    meta[m["key"]]=m

cases=[]; consistent=0
for k,orients in bycase.items():
    ws=list(orients.values())
    s=sum(SCORE[w] for w in ws)/len(ws)
    cons=len({w for w in ws})==1
    consistent+=cons
    cases.append({"key":k,"seed":meta[k]["seed"],"p":s,"cons":cons,
        "status":meta[k]["status"],"severity":meta[k]["severity"],"persona":meta[k]["persona"]})
n=len(cases)
if n==0: print("no cases judged"); sys.exit(0)
peff=sum(c["p"] for c in cases)/n

seeds=sorted(set(c["seed"] for c in cases)); by_seed=defaultdict(list)
for c in cases: by_seed[c["seed"]].append(c["p"])
rng=random.Random(777); boots=[]
for _ in range(3000):
    pool=[]
    for _s in seeds: pool+=by_seed[rng.choice(seeds)]
    boots.append(sum(pool)/len(pool))
boots.sort(); lo=boots[int(0.025*len(boots))]; hi=boots[int(0.975*len(boots))]

raw=Counter(winner(v) for v in verdicts if not v["tid"].endswith("#ctl"))
print("="*62)
print("CLEAN BLIND JUDGE — confront (logic) vs defer (LLM-aligned)")
print("="*62)
print("  cases=%d  seeds=%s  mirror-consistency=%.0f%%"%(n,seeds,100*consistent/n))
print("  raw orientations: confront=%d  defer=%d  tie=%d"%(raw["confront"],raw["defer"],raw["tie"]))
print("  A=A controls: %d/%d judged 平 (%.0f%%; low ⇒ forced-choice noise)"%(ctl_tie,len(ctl),100*ctl_tie/max(1,len(ctl))))
print("  ─────")
print("  p_eff(CONFRONT) = %.3f   95%% CI [%.3f, %.3f]  (cluster-boot by seed)"%(peff,lo,hi))
verdict = ("favors CONFRONT (logic right — keep engaging)" if lo>0.5 else
           "favors DEFER (LLM right — DSL should default to letting petty grudges lie)" if hi<0.5 else
           "WASH — both in-character; the knob is a drama/game-design call, not a correctness one")
print("  DIRECTION: %s"%verdict)
print("  ─── breakdowns (p_eff confront) ───")
def bd(fn,label):
    g=defaultdict(list)
    for c in cases: g[fn(c)].append(c["p"])
    for k in sorted(g): a=g[k]; print("    %-16s %.3f (n=%d)"%(label+":"+str(k),sum(a)/len(a),len(a)))
bd(lambda c:c["status"],"status")
bd(lambda c:("sev<7" if c["severity"]<7 else "sev7+"),"severity")
print("="*62)
# a few reasons on each side
cw=[v for v in verdicts if winner(v)=="confront" and not v["tid"].endswith("#ctl")][:4]
dw=[v for v in verdicts if winner(v)=="defer" and not v["tid"].endswith("#ctl")][:4]
print("sample reasons — judge chose CONFRONT:")
for v in cw: print("   ",v.get("reason",""))
print("sample reasons — judge chose DEFER:")
for v in dw: print("   ",v.get("reason",""))
json.dump({"n":n,"peff_confront":peff,"ci":[lo,hi],"direction":verdict,
    "consistency":consistent/n,"raw":dict(raw),"ctl_tie_rate":ctl_tie/max(1,len(ctl))},
    open(os.path.join(JD,"conflict_judge_summary.json"),"w"),indent=2)
