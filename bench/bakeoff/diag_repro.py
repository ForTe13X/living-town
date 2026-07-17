#!/usr/bin/env python
# Phase C decisive test: teacher SELF-CONSISTENCY on cases that MATTER.
# The full-sample calibration was dominated by indifferent moments (needs~72, no urgency) where
# low agreement is expected. This isolates DECISIVE cases (conflict present OR min_need<60) and asks:
#   - reproducibility floor: 3 single passes A/B/C at temp=0 — does the teacher agree with ITSELF?
#   - batch=5 vs single: does light batching preserve the single pick?
# If the teacher is unstable even single-vs-single on decisive cases, hard labels don't exist here.
# Uses the hardened retry call(). Usage: python diag_repro.py <packet_ds.jsonl> <outdir> [N=30]
import json, sys, os, time, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import (K_CAND, MID, key, sig_of, canon, label_condition)

DATA=sys.argv[1]; OUTD=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 30
os.makedirs(OUTD, exist_ok=True)

# ── select DECISIVE cases: conflict candidate present, OR a genuinely low need (<60) ──
rows=[]
for l in open(DATA, encoding="utf-8"):
    d=json.loads(l)
    if "case" not in d: continue
    if d["strata"].get("has_conflict_cand") or d["min_need"]<60.0:
        rows.append(d)
rows.sort(key=key)
def stride(a,k): return a[::max(1,len(a)//k)][:k] if k>0 else []
sample=stride(rows,N)
MID_=MID()
CASE={key(r):r["case"] for r in sample}
conf=sum(1 for r in sample if r["strata"].get("has_conflict_cand"))
print("[repro] model=%s decisive-sample=%d (conflict=%d, low-need=%d)"%(
      MID_,len(sample),conf,len(sample)-conf), flush=True)

def ag(A,Bd):
    both=n=0
    for k in A:
        a=A[k]["pick"]; b=Bd.get(k,{}).get("pick")
        if a is not None and b is not None:
            both+=1
            if sig_of(CASE[k],a)==sig_of(CASE[k],b): n+=1
    return (100.0*n/both if both else 0.0), both

passes={}
for nm in ("A","B","C"):
    print("[repro] single pass %s ..."%nm, flush=True)
    passes[nm],_=label_condition("single%s"%nm, sample, canon, 1, MID_)
print("[repro] batch=5 pass ...", flush=True)
b5,_=label_condition("batch5", sample, canon, 5, MID_)

A,B,C=passes["A"],passes["B"],passes["C"]
ab,nab=ag(A,B); ac,_=ag(A,C); bc,_=ag(B,C)
b5a,_=ag(A,b5)
# majority-vote stability: for each case, does a 2/3 majority exist among A/B/C?
maj=0; mn=0
for k in A:
    sigs=[sig_of(CASE[k],p[k]["pick"]) for p in (A,B,C) if p[k]["pick"]]
    if len(sigs)==3:
        mn+=1
        c=collections.Counter(sigs).most_common(1)[0][1]
        if c>=2: maj+=1
# distinct-pick spread across A/B/C
spread=collections.Counter()
for k in A:
    sigs={sig_of(CASE[k],p[k]["pick"]) for p in (A,B,C) if p[k]["pick"]}
    if sigs: spread[len(sigs)]+=1

print("\n"+"="*54)
print("PHASE C DECISIVE SELF-CONSISTENCY (n=%d decisive cases)"%len(sample))
print("="*54)
print("  single A-vs-B            %5.1f%%  (n=%d)"%(ab,nab))
print("  single A-vs-C            %5.1f%%"%ac)
print("  single B-vs-C            %5.1f%%"%bc)
print("  --- mean pairwise repro  %5.1f%% ---"%((ab+ac+bc)/3))
print("  batch=5 vs single-A      %5.1f%%"%b5a)
print("  2/3 majority exists      %5.1f%%  (%d/%d)"%(100.0*maj/mn if mn else 0,maj,mn))
print("  distinct picks / 3 runs: "+", ".join("%d→%d"%(k,spread[k]) for k in sorted(spread)))
print("="*54, flush=True)

json.dump({"n":len(sample),"conflict":conf,"model":MID_,
    "repro_AB":ab,"repro_AC":ac,"repro_BC":bc,"repro_mean":(ab+ac+bc)/3,
    "batch5_vs_single":b5a,"majority_2of3":100.0*maj/mn if mn else 0,
    "spread":dict(spread)}, open(os.path.join(OUTD,"diag_repro.json"),"w"), indent=2)
det=open(os.path.join(OUTD,"diag_repro_detail.jsonl"),"w",encoding="utf-8")
for r in sample:
    k=key(r)
    det.write(json.dumps({"key":k,"conflict":r["strata"].get("has_conflict_cand"),
        "min_need":round(r["min_need"],1),
        "A":sig_of(CASE[k],A[k]["pick"]),"B":sig_of(CASE[k],B[k]["pick"]),
        "C":sig_of(CASE[k],C[k]["pick"]),"logic":sig_of(CASE[k],r["logic_pick_id"])},
        ensure_ascii=False)+"\n")
det.close()
print("[repro] wrote diag_repro.json + diag_repro_detail.jsonl", flush=True)
