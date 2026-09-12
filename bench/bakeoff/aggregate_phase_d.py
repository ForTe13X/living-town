#!/usr/bin/env python
# Aggregate the Phase-D confirmatory judge across all four opportunities.
# Input: verdicts.json = [{tid,key,kind,seed,orient,persona,status,pass, ic,ap,dr}] where ic/ap/dr are
#        already mapped by the workflow to {AGGRESSIVE_label, PASSIVE_label, "tie"} (mirror-safe).
# Per opportunity, per axis: p_eff(aggressive) = (#aggressive + 0.5*#tie)/N, with a cluster-bootstrap CI
# by SEED (episodes within a seed correlate). Plus per-persona in_character + the A=A control tie-rate
# (orient==9: both sides identical → judge SHOULD say tie; high tie-rate = calibrated judge).
import json, sys, random
from collections import defaultdict
random.seed(0)

V=json.load(open(sys.argv[1],encoding="utf-8"))
if isinstance(V,dict): V=V.get("verdicts",V)
AXES=[("ic","in_character"),("ap","appropriate"),("dr","dramatic")]
AGG={"conflict":"confront","secret":"leak","endorse":"endorse","faction":"rally_oust"}
# "extended blunt" hypothesis from the first pass: 耿直 hai + 莽撞 evy + 爽快 tie
BLUNTISH={"hai","evy","tie"}

def p_eff(rows, axis, agg):
    n=len(rows)
    if n==0: return None
    a=sum(1 for r in rows if r[axis]==agg); t=sum(1 for r in rows if r[axis]=="tie")
    return (a+0.5*t)/n

def boot_ci(rows, axis, agg, B=2000):
    by=defaultdict(list)
    for r in rows: by[r["seed"]].append(r)
    seeds=list(by)
    if len(seeds)<2: return (None,None)
    est=[]
    for _ in range(B):
        pool=[]
        for _ in seeds: pool+=by[random.choice(seeds)]
        v=p_eff(pool,axis,agg)
        if v is not None: est.append(v)
    est.sort(); return (est[int(0.025*len(est))], est[int(0.975*len(est))])

bykind=defaultdict(list); controls=defaultdict(list)
for r in V:
    (controls if r["orient"]==9 else bykind)[r["kind"]].append(r)

print("Phase-D confirmatory judge — all four opportunities (neutral prompt, 3 axes, first-class passive)")
print("total verdicts: %d  | real: %d  | controls: %d\n"%(len(V), sum(len(x) for x in bykind.values()), sum(len(x) for x in controls.values())))

for kind in ["conflict","secret","endorse","faction"]:
    rows=bykind.get(kind,[]); agg=AGG[kind]
    if not rows: continue
    ncases=len({r["key"] for r in rows}); nseeds=len({r["seed"] for r in rows})
    print("############ %s  (aggressive=%s)  cases=%d seeds=%d N=%d ############"%(kind,agg,ncases,nseeds,len(rows)))
    for ak,an in AXES:
        pe=p_eff(rows,ak,agg); lo,hi=boot_ci(rows,ak,agg)
        # mirror consistency: same verdict regardless of A/B position (position-bias robustness).
        byc=defaultdict(dict)
        for r in rows: byc[r["key"]][r["orient"]]=r[ak]
        both=[(d[0],d[1]) for d in byc.values() if 0 in d and 1 in d]
        mc=(sum(1 for a,b in both if a==b)/len(both)) if both else 0.0
        print("  %-13s p_eff(%s)=%.3f  CI95[%.3f,%.3f]  mirror-consistent=%.0f%%"%(an,agg,pe,lo or 0,hi or 0,100*mc))
    # control tie-rate (in_character axis; A=A so aggressive/passive labels collapse → tie is correct)
    ctl=controls.get(kind,[])
    if ctl:
        tr=sum(1 for r in ctl if r["ic"]=="tie")/len(ctl)
        print("  A=A control tie-rate (in_character): %.2f  (N=%d ctrl)  [高=judge 会正确判平]"%(tr,len(ctl)))
    # persona split on in_character
    if kind=="conflict":
        for grp,name in [({p for p in {r["persona"] for r in rows} if p in BLUNTISH},"直/莽/爽(blunt-ish)"),
                         ({p for p in {r["persona"] for r in rows} if p not in BLUNTISH},"其余(default-defer)")]:
            g=[r for r in rows if r["persona"] in grp]
            if g:
                lo,hi=boot_ci(g,"ic",agg)
                print("   %-18s in_character p_eff(confront)=%.3f CI[%.3f,%.3f] N=%d"%(name,p_eff(g,"ic",agg),lo or 0,hi or 0,len(g)))
    perp=defaultdict(list)
    for r in rows: perp[r["persona"]].append(r)
    print("   per-persona in_character p_eff(%s): %s"%(agg, "  ".join("%s=%.2f(N%d)"%(p,p_eff(perp[p],"ic",agg),len(perp[p])) for p in sorted(perp,key=lambda p:-p_eff(perp[p],"ic",agg)))))
    print()
