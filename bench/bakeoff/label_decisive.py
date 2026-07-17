#!/usr/bin/env python
# Scoped decisive re-test — STEP A: single-case teacher labeling on SALIENT grievance cases.
# Phase C proved single-case labeling is reliable (97.6% self-consistent) but batching poisons it,
# so we label ONE case per call (batch=1), retry-hardened.
# For each case we label the teacher TWICE: with the 心结 salience block (salient) and without (bare),
# to isolate whether surfacing the grievance makes the teacher ENGAGE the conflict.
# Output feeds STEP B (blind Claude pairwise judge, teacher-salient-pick vs logic-pick).
# Usage: python label_decisive.py <packet_big.jsonl> <out.jsonl> [N=160]
import json, sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import (K_CAND, K_MEAN, K_OBJ, K_GRIEV, MID, key, canon, run_batch)

DATA=sys.argv[1]; OUTP=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 160
CONFLICT_ACTS={"confront","apologize","mediate"}

def action_of(case, cid):
    for c in case[K_CAND]:
        if c["id"]==cid: return c.get("action","")
    return None
def mean_of(case, cid):
    for c in case[K_CAND]:
        if c["id"]==cid:
            o=c.get(K_OBJ,""); return c.get(K_MEAN,"")+((" →"+o) if o else "")
    return None
# P0-4: bind to the grievance the DECISION is about — the one whose other_id matches logic's target —
# not blindly the first grievance (agents can carry several; picking [0] flipped 254/1014 stances).
def logic_partner_id(r):
    oi=r.get("id_map",{}).get(r.get("logic_pick_id",""))
    if oi is None: return None
    try: return r["cands"][oi].get("partner")
    except Exception: return None
def target_griev(r):
    gs=r.get("grievances",[])          # typed (row-level), NOT the display 心结 strings
    if not gs: return None
    pid=logic_partner_id(r)
    if pid:
        for g in gs:
            if g.get("other_id")==pid: return g
    return max(gs, key=lambda g:g.get("severity",0))
def stance_of(r):
    g=target_griev(r); return g["role"] if g else "?"
def status_of(r):
    g=target_griev(r); return g["status"] if g else "?"
def sev_of(r):
    g=target_griev(r); return int(g.get("severity",0)) if g else 0

# ── select decisive cases: real grievance AND actor can act on it (confront/apologize present) ──
rows=[]
for l in open(DATA, encoding="utf-8"):
    d=json.loads(l)
    if d.get("strata",{}).get("has_grievance") and d.get("strata",{}).get("has_conflict_cand"):
        rows.append(d)
# deterministic stratified sample across (stance × status)
from collections import defaultdict
buck=defaultdict(list)
for r in sorted(rows,key=key):
    buck[(stance_of(r),status_of(r))].append(r)
sample=[]
nb=len(buck); per=max(1,N//nb)
for kk in sorted(buck):
    a=buck[kk]; step=max(1,len(a)//per)
    sample+=a[::step][:per]
sample=sorted(sample,key=key)[:N]
M=MID()
print("[label] model=%s decisive-sample=%d from %d cases; buckets=%s"%(
      M,len(sample),len(rows),{str(k):len(v) for k,v in sorted(buck.items())}),flush=True)

done=set()
try:
    for l in open(OUTP,encoding="utf-8"): done.add(json.loads(l)["key"])
except FileNotFoundError: pass
todo=[r for r in sample if key(r) not in done]
print("[label] %d done, %d to label (x2 renders)"%(len(done),len(todo)),flush=True)

def label1(r, salient):
    picks,_=run_batch([r],[canon(r)],M,salient=salient)
    return picks[0]

out=open(OUTP,"a",encoding="utf-8"); t0=time.time()
eng={"logic":0,"sal":0,"bare":0}; nlab=0
for i,r in enumerate(todo):
    case=r["case"]
    try:
        ts=label1(r, True); tb=label1(r, False)
    except Exception as e:
        print("[label] ERR %s: %s"%(key(r),str(e)[:70]),flush=True); continue
    rec={"key":key(r),"seed":r["seed"],"tick":r["tick"],"persona":r["persona"],
         "stance":stance_of(r),"status":status_of(r),"severity":sev_of(r),
         "logic_id":r["logic_pick_id"],"logic_action":action_of(case,r["logic_pick_id"]),
         "logic_mean":mean_of(case,r["logic_pick_id"]),
         "tsal_id":ts,"tsal_action":action_of(case,ts) if ts else None,"tsal_mean":mean_of(case,ts) if ts else None,
         "tbare_id":tb,"tbare_action":action_of(case,tb) if tb else None,"tbare_mean":mean_of(case,tb) if tb else None,
         "case":case}
    out.write(json.dumps(rec,ensure_ascii=False)+"\n"); out.flush()
    nlab+=1
    if action_of(case,r["logic_pick_id"]) in CONFLICT_ACTS: eng["logic"]+=1
    if ts and action_of(case,ts) in CONFLICT_ACTS: eng["sal"]+=1
    if tb and action_of(case,tb) in CONFLICT_ACTS: eng["bare"]+=1
    if (i+1)%10==0 or i==len(todo)-1:
        print("[label] %d/%d | engage rate: logic %.0f%% salient %.0f%% bare %.0f%% | %.1fmin"%(
            i+1,len(todo),100*eng["logic"]/nlab,100*eng["sal"]/nlab,100*eng["bare"]/nlab,(time.time()-t0)/60),flush=True)
out.close()
print("\n[label] DONE labeled=%d"%nlab)
print("  ENGAGE-THE-CONFLICT rate:  logic=%.0f%%  teacher-salient=%.0f%%  teacher-bare=%.0f%%"%(
    100*eng["logic"]/max(1,nlab),100*eng["sal"]/max(1,nlab),100*eng["bare"]/max(1,nlab)))
print("  (salient>bare ⇒ surfacing the grievance made the teacher engage more)",flush=True)
