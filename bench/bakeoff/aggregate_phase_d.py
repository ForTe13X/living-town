#!/usr/bin/env python
# Aggregate the Phase-D confirmatory conflict judge.
# Input: verdicts.json = [{tid,key,seed,orient,persona,status,pass, ic,ap,dr}] where ic/ap/dr in
#        {"confront","defer","tie"} (already mapped by the workflow via A_src/B_src, so mirror-safe).
# Reports p_eff(confront) = (#confront + 0.5*#tie)/N per axis (in_character/appropriate/dramatic),
# overall + per-persona (blunt 老海=hai should tilt confront; others should tilt defer), with a
# cluster-bootstrap CI by SEED (episodes within a seed are correlated → resample seeds, not judgments).
import json, sys, random
random.seed(0)  # deterministic bootstrap (no wall-clock)

V=json.load(open(sys.argv[1],encoding="utf-8"))
if isinstance(V,dict): V=V.get("verdicts",V)
AXES=[("ic","in_character"),("ap","appropriate"),("dr","dramatic")]

def p_eff(rows, axis):
    n=len(rows)
    if n==0: return None
    c=sum(1 for r in rows if r[axis]=="confront"); t=sum(1 for r in rows if r[axis]=="tie")
    return (c+0.5*t)/n

def boot_ci(rows, axis, B=2000):
    # cluster-bootstrap by seed: resample seeds w/ replacement, pool their judgments, recompute p_eff
    by_seed={}
    for r in rows: by_seed.setdefault(r["seed"],[]).append(r)
    seeds=list(by_seed)
    if len(seeds)<2: return (None,None)
    est=[]
    for _ in range(B):
        pool=[]
        for _ in seeds: pool+=by_seed[random.choice(seeds)]
        v=p_eff(pool,axis)
        if v is not None: est.append(v)
    est.sort()
    return (est[int(0.025*len(est))], est[int(0.975*len(est))])

print("Phase-D confirmatory conflict judge — confront vs FIRST-CLASS defer (neutral prompt, 3 axes)")
print("verdicts: %d  | cases: %d  | seeds: %d  | personas: %d"%(
    len(V), len({r["key"] for r in V}), len({r["seed"] for r in V}), len({r["persona"] for r in V})))
print("p_eff = P(judge deems CONFRONT the pick) = (#confront + 0.5*#tie)/N.  <0.5 → defer favored.\n")

for ak,an in AXES:
    lo,hi=boot_ci(V,ak); pe=p_eff(V,ak)
    print("== %s ==  overall p_eff(confront)=%.3f  CI95[%.3f, %.3f]  (N=%d)"%(an,pe,lo or 0,hi or 0,len(V)))
    # blunt(老海) vs the rest
    hai=[r for r in V if r["persona"]=="hai"]; rest=[r for r in V if r["persona"]!="hai"]
    if hai: hl,hh=boot_ci(hai,ak); print("   耿直老海 (blunt, expect CONFRONT): p_eff=%.3f CI[%.3f,%.3f] N=%d"%(p_eff(hai,ak),hl or 0,hh or 0,len(hai)))
    if rest: rl,rh=boot_ci(rest,ak); print("   其余人设 (expect DEFER):        p_eff=%.3f CI[%.3f,%.3f] N=%d"%(p_eff(rest,ak),rl or 0,rh or 0,len(rest)))
    print()

# per-persona table (in_character axis — the character-fidelity one)
from collections import defaultdict
perp=defaultdict(list)
for r in V: perp[r["persona"]].append(r)
print("per-persona in_character p_eff(confront):")
for p in sorted(perp, key=lambda p:-p_eff(perp[p],"ic")):
    print("   %-6s p_eff=%.3f  N=%d"%(p, p_eff(perp[p],"ic"), len(perp[p])))
