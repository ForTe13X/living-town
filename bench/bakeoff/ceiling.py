#!/usr/bin/env python
# Scoped re-test — STEP 3: LLM top-K "ceiling" test on the CLEAN v1 packet (single-case, no batch).
# The target architecture uses the LLM as an ORDERING-ONLY proposal prior feeding a Theory DSL.
# The ceiling of that approach is bounded by whether the LLM's top-K SET reliably contains the good
# action AND is stable under candidate permutation. We measure:
#   - valid@K       : all K proposed ids in-set & distinct (can we even trust the output shape?)
#   - recall@1/3/5  : does top-K contain the logic-floor pick? (engine's reference choice)
#   - engage@K      : for grievance cases, is a conflict response (confront/apologize) in top-K?
#   - set-overlap   : Jaccard(top-K canonical, top-K permuted)  (SET stability, kinder than argmax)
# Usage: python ceiling.py <packet_v1.jsonl> <outdir> [N=80] [K=5]
import json, sys, os, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import (K_CAND, MID, key, canon, permuted, render_case, call, SYS as _S0)

DATA=sys.argv[1]; OUTD=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 80
K=int(sys.argv[4]) if len(sys.argv)>4 else 5
os.makedirs(OUTD, exist_ok=True)
CONF={"confront","apologize","mediate"}

SYS=(
"你是 Living Town 的封闭集角色行为排序器。下面给一位居民此刻的处境和一组带唯一 id 的候选行动。\n"
"请按“这位【具体居民】此刻最可能【主动】去做”的可能性从高到低排序，输出最靠前的 %d 个候选 id，\n"
"每行一个 id，最像的放第一行。判断顺序：性格与身份 > 关系/心结/已知私密 > 当前需求与时段现实性。\n"
"注意：心结里的怨气数值低时未必要当面理论；不要因某项更戏剧化/更礼貌就抬高它。\n"
"只输出 %d 行 id，不要编号、不要解释、不要复述。 /no_think"%(K,K))

def topk(case, order, M):
    usr=render_case(case, order, salient=True)
    msg=[{"role":"system","content":SYS},{"role":"user","content":usr},
         {"role":"assistant","content":"</think>\n\n"}]
    r=call({"model":M,"messages":msg,"temperature":0,"max_tokens":16*K+48})
    txt=r["choices"][0]["message"].get("content") or ""
    idset=set(c["id"] for c in case[K_CAND])
    out=[]
    for m in re.finditer(r'(c[0-9a-fx]{2,8})', txt):
        cid=m.group(1)
        if cid in idset and cid not in out:
            out.append(cid)
        if len(out)>=K: break
    return out

# ── sample decisive cases, stratified by (stance-proxy via role of target grievance) ──
def tgt_role(r):
    gs=r.get("grievances",[])
    if not gs: return "?"
    oi=r["id_map"].get(r["logic_pick_id"]); pid=r["cands"][oi].get("partner") if oi is not None else None
    for g in gs:
        if g.get("other_id")==pid: return g["role"]
    return gs[0]["role"]
rows=[json.loads(l) for l in open(DATA,encoding="utf-8")
      if json.loads(l).get("strata",{}).get("has_grievance") and json.loads(l).get("strata",{}).get("has_conflict_cand")] \
     if False else []
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if d.get("strata",{}).get("has_grievance") and d.get("strata",{}).get("has_conflict_cand"):
        rows.append(d)
rows.sort(key=key)
sample=rows[::max(1,len(rows)//N)][:N]
M=MID()
print("[ceiling] model=%s decisive-sample=%d/%d K=%d"%(M,len(sample),len(rows),K),flush=True)

def jacc(a,b):
    sa,sb=set(a),set(b)
    return len(sa&sb)/len(sa|sb) if (sa|sb) else 1.0

agg={"valid":0,"r1":0,"r3":0,"r5":0,"eng":0,"n":0,"ov":[]}
det=open(os.path.join(OUTD,"ceiling_detail.jsonl"),"w",encoding="utf-8"); t0=time.time()
for i,r in enumerate(sample):
    case=r["case"]; lp=r["logic_pick_id"]
    try:
        tc=topk(case, canon(r), M)
        tp=topk(case, permuted(r), M)
    except Exception as e:
        print("[ceiling] ERR %s: %s"%(key(r),str(e)[:70]),flush=True); continue
    conf_ids=[c["id"] for c in case[K_CAND] if c["action"] in CONF]
    valid = len(tc)==K
    r1 = lp in tc[:1]; r3 = lp in tc[:3]; r5 = lp in tc[:5]
    eng = any(cid in tc for cid in conf_ids)
    ov = jacc(tc,tp)
    agg["n"]+=1; agg["valid"]+=valid; agg["r1"]+=r1; agg["r3"]+=r3; agg["r5"]+=r5; agg["eng"]+=eng; agg["ov"].append(ov)
    det.write(json.dumps({"key":key(r),"seed":r["seed"],"role":tgt_role(r),
        "topk":tc,"topk_perm":tp,"logic":lp,"r1":r1,"r3":r3,"r5":r5,"eng":eng,"overlap":ov},
        ensure_ascii=False)+"\n"); det.flush()
    if (i+1)%10==0 or i==len(sample)-1:
        n=agg["n"]
        print("[ceiling] %d/%d | valid@%d %.0f%% r@1/3/5 %.0f/%.0f/%.0f%% eng@%d %.0f%% setovlp %.2f | %.1fmin"%(
            i+1,len(sample),K,100*agg["valid"]/n,100*agg["r1"]/n,100*agg["r3"]/n,100*agg["r5"]/n,
            K,100*agg["eng"]/n,sum(agg["ov"])/n,(time.time()-t0)/60),flush=True)
det.close()
n=max(1,agg["n"])
print("\n"+"="*54)
print("TOP-K CEILING (n=%d, K=%d, model=%s)"%(agg["n"],K,M))
print("="*54)
print("  valid@%d             %.0f%%"%(K,100*agg["valid"]/n))
print("  recall@1 (logic)     %.0f%%"%(100*agg["r1"]/n))
print("  recall@3 (logic)     %.0f%%"%(100*agg["r3"]/n))
print("  recall@5 (logic)     %.0f%%"%(100*agg["r5"]/n))
print("  engage@%d (conflict)  %.0f%%   (grievance→confront/apologize in top-K)"%(K,100*agg["eng"]/n))
print("  set-overlap (perm)   %.2f   (Jaccard top-K canonical vs permuted)"%(sum(agg["ov"])/n))
print("="*54)
print("  READ: high recall@K + high set-overlap ⇒ LLM is a usable ordering-prior for the DSL.")
print("        low recall or unstable set ⇒ DSL should lean on rules, LLM prior capped low.")
print("="*54,flush=True)
json.dump({"n":agg["n"],"K":K,"valid":agg["valid"]/n,"r1":agg["r1"]/n,"r3":agg["r3"]/n,"r5":agg["r5"]/n,
    "engage":agg["eng"]/n,"set_overlap":sum(agg["ov"])/n},open(os.path.join(OUTD,"ceiling_summary.json"),"w"),indent=2)
