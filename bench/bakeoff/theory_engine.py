#!/usr/bin/env python
# Theory Engine v1 (offline prototype) — docs/24.
# Consumes the TheorySnapshot (typed rows from log_decisions --packet) and adjudicates the CONFLICT
# opportunity with the highest-value rules, via a deterministic weighted-MAP. No sim, no LLM, no RNG.
#   HARD      protected_secret : drop leak/confide of a non-authorized secret (engine owns secrets)
#   CRISIS    survival         : need < NEED_CRISIS → force maintenance (defer)
#   DRAMA     progress_conflict: engage (confront/apologize) an open opportunity        (+w_drama)
#   CHARACTER petty_grievance  : a small grievance → prefer defer                        (+w_petty if sev<TH)
#   CHARACTER trait_lean       : impulsive→engage / easygoing→defer (illustrative)       (±w_trait)
#   STRATEGIC bad_standing     : already-bad reputation → more willing to confront       (+w_stand)
# `defer` is first-class: it resolves to the best NON-conflict candidate (what the agent does otherwise).
# Reports DSL-vs-logic and, if ceiling_detail.jsonl is present, DSL-vs-LLM engage agreement, and sweeps
# the petty threshold — the single knob the ceiling identified as the only real headroom.
# Usage: python theory_engine.py <packet_v1.jsonl> [ceiling_detail.jsonl]
import json, sys, os
from collections import Counter, defaultdict

DATA=sys.argv[1]
CEIL=sys.argv[2] if len(sys.argv)>2 else None
NEED_CRISIS=15.0
CONFLICT_ACTS={"confront","apologize","mediate"}       # engage detection
# a real "defer" = let the grudge lie: neither the direct conflict response NOR indirect aggression
# (rally_oust/gossip_rep/endorse = reputation attacks; leak = betrayal; gossip = spreading others' business).
AGGRESSION={"confront","apologize","mediate","rally_oust","gossip_rep","endorse","leak","gossip"}
# rule weights — CHARACTER layer now CALIBRATED to the clean blind judge (in-character ground truth):
#   open-grievance default = DEFER (judge agrees 91% vs logic's always-confront 9%);
#   confront only for BLUNT personas (老海: 耿直/好酒 → 5/5 confront). DRAMA is a SEPARATE override axis.
W_DEFER_DEFAULT=1.0; W_BLUNT=1.6; W_APOLOGY=1.0
BLUNT={"耿直","好酒","认死理"}                         # judge-derived confront-associated traits
W_DRAMA_OVERRIDE=0.0   # drama director can raise this to force a confrontation SCENE for arc progression;
                       # 0 = pure in-character mode. "dramatic/interesting" is a separate eval, never weight-mixed here.

def key(r): return "%d:%d:%s"%(r["seed"],r["tick"],r["agent"])

def cand_by_id(case,cid):
    for c in case["候选"]:
        if c["id"]==cid: return c
    return None
def action_of(case,cid):
    c=cand_by_id(case,cid); return c["action"] if c else None

def snapshot(r):
    """assemble the decision-relevant TheorySnapshot slice for the acting agent."""
    case=r["case"]; cands=r["cands"]
    # target grievance = the one logic's pick (or a conflict candidate) is about
    oi=r["id_map"].get(r["logic_pick_id"]); lp_partner=cands[oi].get("partner") if oi is not None else None
    gs=r.get("grievances",[])
    tg=None
    if gs:
        tg=next((g for g in gs if g.get("other_id")==lp_partner), None) or max(gs,key=lambda g:g["severity"])
    traits=set(case.get("居民",{}).get("性格",[]) or [])
    return {"case":case,"cands":cands,"grievance":tg,"traits":traits,
            "min_need":r.get("min_need",100.0),"secrets":r.get("secrets",[]),
            "logic_id":r["logic_pick_id"]}

def intents(snap):
    """enumerate legal response intents for the conflict opportunity → concrete candidate id each."""
    case=snap["case"]; tg=snap["grievance"]; out={}
    if tg:
        want = "confront" if tg["role"]=="aggrieved" else "apologize"
        for c in case["候选"]:
            if c["action"]==want and _cand_partner(snap,c["id"])==tg["other_id"]:
                out["engage"]=c["id"]; break
    # defer = best NON-aggression candidate by logic score (maintenance or a benign/conciliatory social)
    nonconf=[c for c in snap["cands"] if c["action"] not in AGGRESSION]
    if nonconf:
        best=max(nonconf,key=lambda c:c.get("score",0.0))
        # map orig-index candidate back to opaque id
        oid=_id_for_index(snap, best["i"])
        if oid: out["defer"]=oid
    return out

def _cand_partner(snap,cid):
    # opaque id -> orig index -> cands[i].partner
    # (case candidate has 对象 name; use row cands via id_map inverse)
    return snap["_id2partner"].get(cid)
def _id_for_index(snap,i):
    return snap["_idx2id"].get(i)

def hard_secret_ok(snap,cid):
    """HARD: forbid leak/confide of a secret the agent isn't authorized to disclose."""
    c=cand_by_id(snap["case"],cid)
    if not c or c["action"] not in ("leak","confide"): return True
    # any non-authorized secret in play → forbid (v1: only own secret authorized)
    return not any(not s.get("authorized",False) for s in snap["secrets"])

def decide(snap, petty_th):
    """deterministic weighted-MAP over intents → concrete candidate id + engaged?"""
    ins=intents(snap)
    if "engage" not in ins:            # no actionable conflict → not our opportunity; defer to logic
        return snap["logic_id"], None, "no_opportunity"
    score={"engage":0.0,"defer":0.0}
    tg=snap["grievance"]; traits=snap["traits"]
    # CRISIS
    if snap["min_need"] < NEED_CRISIS: score["defer"]+=10.0
    if tg and tg["role"]=="offender":
        # apology-due: near-consensus engage (apologize) — logic/LLM/judge all agree
        score["engage"]+=W_APOLOGY
    else:
        # open-grievance CHARACTER layer (judge-calibrated): default to letting the grudge lie,
        # unless this is a blunt/直性子 persona who'd rather have it out. severity is ~constant so unused.
        score["defer"]+=W_DEFER_DEFAULT
        if traits & BLUNT: score["engage"]+=W_BLUNT
        # DRAMA override (separate axis; 0 in in-character mode): director may force a scene for arc.
        score["engage"]+=W_DRAMA_OVERRIDE
    _ = petty_th   # legacy sweep arg, no longer used by the calibrated policy
    # HARD guard on the chosen concrete candidate (defer target could be leak/confide)
    order=sorted(score, key=lambda k:(-score[k], k))   # deterministic tie-break
    for intent in order:
        cid=ins.get(intent)
        if cid and hard_secret_ok(snap,cid):
            return cid, (intent=="engage"), intent
    return snap["logic_id"], None, "fallback"

# ── load ──
rows=[]
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if d.get("strata",{}).get("has_grievance") and d.get("strata",{}).get("has_conflict_cand"):
        rows.append(d)
# precompute id<->index maps per row
for r in rows:
    inv={v:k for k,v in r["id_map"].items()}
    id2partner={}
    for cid,i in r["id_map"].items():
        id2partner[cid]=r["cands"][i].get("partner")
    r["_snap_idx2id"]=inv; r["_snap_id2partner"]=id2partner

llm_engage={}
if CEIL and os.path.exists(CEIL):
    for l in open(CEIL,encoding="utf-8"):
        d=json.loads(l); tk=d.get("topk",[])
        llm_engage[d["key"]] = (tk[0] if tk else None)   # LLM argmax id

def run(petty_th):
    m=defaultdict(lambda: {"n":0,"dsl_eng":0,"match":0,"llm_agree":0,"llm_n":0,"llm_eng":0})
    for r in rows:
        snap=snapshot(r); snap["_idx2id"]=r["_snap_idx2id"]; snap["_id2partner"]=r["_snap_id2partner"]
        cid,eng,intent=decide(snap,petty_th)
        if eng is None: continue
        role=snap["grievance"]["role"]
        for bucket in (role,"all"):
            d=m[bucket]; d["n"]+=1; d["dsl_eng"]+=eng
            if cid==r["logic_pick_id"]: d["match"]+=1
            lid=llm_engage.get(key(r))
            if lid:
                le=action_of(r["case"],lid) in CONFLICT_ACTS
                d["llm_n"]+=1; d["llm_eng"]+=le; d["llm_agree"]+=(le==bool(eng))
    return m

print("="*74)
print("THEORY ENGINE v1 — conflict opportunity, role-aware DSL vs logic vs LLM")
print("="*74)
print("  logic engages ~100% by construction. LLM (ceiling top-1) engage-rate by role is the target.")
print("  petty_grievance (severity<TH → defer) applies to OPEN-GRIEVANCE only.\n")
for role in ("offender","aggrieved","all"):
    print("  ── %s ──"%role)
    print("    %-4s %5s %11s %8s %13s %13s"%("TH","n","DSL-engage","=logic","LLM-engage","DSL≈LLM(eng)"))
    for th in (0,5,7,9,12):
        d=run(th)[role]; n=max(1,d["n"]); ln=max(1,d["llm_n"])
        print("    %-4d %5d %10.0f%% %7.0f%% %12.0f%% %12.0f%%"%(
            th,d["n"],100*d["dsl_eng"]/n,100*d["match"]/n,100*d["llm_eng"]/ln,100*d["llm_agree"]/ln))
        if role=="offender": break   # petty doesn't apply; one row suffices
print("="*74)
print("  READ: offender→always engage (apologize) matches logic&LLM. open-grievance is the contested")
print("        arm; but severity is ~constant so no TH reproduces the LLM → the engage/defer signal")
print("        lives in OTHER features (persona/relationship/context). That's the step-5 GBDT question.")
