#!/usr/bin/env python
# Aggregate the faction-moment blind judge (rally_oust vs abstain). Maps each blind A/B back via the
# held-out mapping, combines mirror pairs, cluster-bootstraps p_eff(rally_oust) by seed, and breaks it
# down BY PERSONA (to find any aggressive-persona exception, like 老海 for confront / 阿丽 for leak).
# Usage: python aggregate_faction_judge.py <judge_dir>
import json, sys, os, glob, random
from collections import defaultdict, Counter

JD=sys.argv[1]
mapping=json.load(open(os.path.join(JD,"mapping.json"),encoding="utf-8"))
verdicts=[]
for f in glob.glob(os.path.join(JD,"verdicts","verdict_*.json")):
    try: verdicts+=json.load(open(f,encoding="utf-8"))
    except Exception as e: print("WARN bad verdict %s: %s"%(f,e))
print("loaded %d verdicts, %d tasks"%(len(verdicts),len(mapping)))

def winner(v):
    m=mapping.get(v["tid"])
    if not m: return None
    if v["choice"]=="平": return "tie"
    return m["A_src"] if v["choice"]=="A" else m["B_src"]

ctl=[v for v in verdicts if v["tid"].endswith("#ctl")]
ctl_tie=sum(1 for v in ctl if v["choice"]=="平")
SCORE={"rally_oust":1.0,"tie":0.5,"abstain":0.0}
bycase=defaultdict(dict); meta={}
for v in verdicts:
    if v["tid"].endswith("#ctl"): continue
    m=mapping.get(v["tid"]);
    if not m: continue
    w=winner(v)
    if w is None: continue
    bycase[m["key"]][m["orient"]]=w; meta[m["key"]]=m
cases=[]; consistent=0
for k,orients in bycase.items():
    ws=list(orients.values()); s=sum(SCORE[w] for w in ws)/len(ws)
    consistent += (len(set(ws))==1)
    cases.append({"key":k,"seed":meta[k]["seed"],"p":s,"persona":meta[k]["persona"]})
n=len(cases)
if n==0: print("no cases"); sys.exit(0)
peff=sum(c["p"] for c in cases)/n
seeds=sorted(set(c["seed"] for c in cases)); by_seed=defaultdict(list)
for c in cases: by_seed[c["seed"]].append(c["p"])
rng=random.Random(909); boots=[]
for _ in range(3000):
    pool=[]
    for _s in seeds: pool+=by_seed[rng.choice(seeds)]
    boots.append(sum(pool)/len(pool))
boots.sort(); lo=boots[int(0.025*len(boots))]; hi=boots[int(0.975*len(boots))]
raw=Counter(winner(v) for v in verdicts if not v["tid"].endswith("#ctl"))

print("="*64)
print("FACTION-MOMENT BLIND JUDGE — rally_oust (mob) vs abstain")
print("="*64)
print("  cases=%d seeds=%s mirror-consistency=%.0f%%"%(n,seeds,100*consistent/n))
print("  raw: rally_oust=%d abstain=%d tie=%d"%(raw["rally_oust"],raw["abstain"],raw["tie"]))
print("  A=A controls: %d/%d judged 平"%(ctl_tie,len(ctl)))
print("  p_eff(RALLY_OUST) = %.3f  95%% CI [%.3f, %.3f]"%(peff,lo,hi))
verdict=("favors RALLY_OUST (logic right)" if lo>0.5 else
         "favors ABSTAIN (logic mobs out-of-character; DSL should default to abstain)" if hi<0.5 else
         "WASH")
print("  DIRECTION: %s"%verdict)
print("  ── per-persona p_eff(rally_oust) (who, if anyone, is in-character mobbing) ──")
g=defaultdict(list)
for c in cases: g[c["persona"]].append(c["p"])
for p in sorted(g,key=lambda p:-sum(g[p])/len(g[p])):
    a=g[p]; print("    %-6s %.2f (n=%d)"%(p,sum(a)/len(a),len(a)))
print("="*64)
cw=[v for v in verdicts if winner(v)=="rally_oust" and not v["tid"].endswith("#ctl")][:5]
print("sample reasons — judge chose RALLY_OUST:")
for v in cw: print("   [%s] %s"%(mapping.get(v["tid"],{}).get("persona","?"),v.get("reason","")))
json.dump({"n":n,"peff_rally":peff,"ci":[lo,hi],"direction":verdict,"consistency":consistent/n,
    "raw":dict(raw),"by_persona":{p:sum(g[p])/len(g[p]) for p in g}},
    open(os.path.join(JD,"faction_judge_summary.json"),"w"),indent=2)
