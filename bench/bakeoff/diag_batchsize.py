#!/usr/bin/env python
# Phase C diagnostic: WHY did single-vs-batch agreement collapse to 29.5%?
# Two hypotheses:
#   (A) the teacher is intrinsically stochastic even at temp=0 (MoE routing non-determinism)
#       -> then NO batch size is stable; single-vs-single would also be low.
#   (B) batch=30 on the rich packet specifically poisons it (through-batch attention decay)
#       -> then single-vs-single is high, and agreement degrades as batch size grows.
# Measures agreement-with-single-A (the reference) for:  single-B, batch2, batch5, batch10, batch30.
# Usage: python diag_batchsize.py <packet_ds.jsonl> <outdir> [M=40]
import json, sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import (K_CAND, MID, key, sig_of, canon, load_sample, label_condition)

DATA=sys.argv[1]; OUTD=sys.argv[2]
M_N=int(sys.argv[3]) if len(sys.argv)>3 else 40
os.makedirs(OUTD, exist_ok=True)

sample,ns,nn = load_sample(DATA, M_N)
MID_=MID()
print("[diag] model=%s sample=%d (social=%d/non=%d)"%(MID_,len(sample),ns,nn), flush=True)
CASE={key(r):r["case"] for r in sample}

def ag(ref, other):
    both=n=0
    for k in ref:
        a=ref[k]["pick"]; b=other.get(k,{}).get("pick")
        if a is not None and b is not None:
            both+=1
            if sig_of(CASE[k],a)==sig_of(CASE[k],b): n+=1
    return (100.0*n/both if both else 0.0), both

# reference: single pass A
print("[diag] reference single-A ...", flush=True)
A,_ = label_condition("singleA", sample, canon, 1, MID_)
# reproducibility floor: single pass B (identical conditions, temp=0)
print("[diag] repro single-B ...", flush=True)
Bx,_ = label_condition("singleB", sample, canon, 1, MID_)

conds={}
for bs in (2,5,10,30):
    print("[diag] batch=%d ..."%bs, flush=True)
    r,_ = label_condition("batch%d"%bs, sample, canon, bs, MID_)
    conds[bs]=r

print("\n"+"="*50)
print("PHASE C DIAGNOSTIC — agreement vs single-A (n=%d)"%len(sample))
print("="*50)
rb,nb=ag(A,Bx)
print("  single-B (repro floor)   %5.1f%%  (n=%d)"%(rb,nb))
for bs in (2,5,10,30):
    a,n=ag(A,conds[bs])
    print("  batch=%-3d                 %5.1f%%  (n=%d)"%(bs,a,n))
print("="*50)
print("  READ: if single-B ~high and batchN falls with N -> shrink batch (hyp B).")
print("        if single-B already low -> teacher is stochastic (hyp A); need vote/soft-labels.")
print("="*50, flush=True)

out={"n":len(sample),"model":MID_,"single_B_repro":rb,
     "batch":{bs:ag(A,conds[bs])[0] for bs in (2,5,10,30)}}
json.dump(out, open(os.path.join(OUTD,"diag_batchsize.json"),"w"), indent=2)
# per-case dump for inspection
det=open(os.path.join(OUTD,"diag_detail.jsonl"),"w",encoding="utf-8")
for r in sample:
    k=key(r)
    det.write(json.dumps({"key":k,"A":A[k]["pick"],"B":Bx[k]["pick"],
        **{("b%d"%bs):conds[bs][k]["pick"] for bs in (2,5,10,30)}},ensure_ascii=False)+"\n")
det.close()
print("[diag] wrote diag_batchsize.json + diag_detail.jsonl", flush=True)
