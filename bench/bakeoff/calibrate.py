#!/usr/bin/env python
# Phase C — teacher calibration on the rich --packet case.
# Before spending Claude-judge budget we must prove the teacher is STABLE on the new packet.
# Labels the SAME stratified sample under 4 conditions and checks 4 acceptance gates:
#   1. parse success              >= 99.5%   (valid in-set id emitted)
#   2. single-vs-batch agreement  >= 90%     (batching must not change the answer)
#   3. candidate-permutation stab >= 85%     (candidate order must not change the answer)
#   4. batch-position drift       <  3pp     (position within a batch must not degrade quality)
# Candidates carry OPAQUE ids (c165a, not "3"/"A") so the teacher answers by id, not by slot.
# Usage: python calibrate.py <packet_ds.jsonl> <outdir> [N=150] [B=30]
import json, re, sys, os, time, random, urllib.request, urllib.error

BASE="http://127.0.0.1:1234/v1"

# ── packet case keys (unicode-escaped so the source is encoding-proof) ──
K_CAND="候选"; K_REL="关系"; K_RES="居民"
K_SEC="我知道的私密"; K_NOW="此刻"; K_RECENT="近事"
K_MEAN="含义"; K_OBJ="对象"
K_AFF="交情"; K_FAM="熟悉度"
K_PERS="性格"; K_JOB="职业"; K_BIO="身份"
K_LOC="位置"; K_TOD="时段"; K_DAY="第几天"
K_URGENT="迫切需求"; K_NEED="需求"; K_SCALE="需求量表"
K_GRIEV="心结"; K_STANCE="立场"; K_RESENT="怨气"; K_STATE="状态"; K_BACKLOG="积压"; K_ESC="已激化"
K_STANDING="风评"
K_DUE="待办约定"; K_CONTENT="内容"; K_LEFT="还剩"
K_STAKE="秘密处境"

def call(payload, timeout=600, retries=5):
    """POST with retry+backoff. The 120B MoE server intermittently 500s under sustained load
    (observed after ~20min of rapid single calls); dropping those calls silently corrupts
    stability metrics, so retry transient 5xx / timeouts with exponential backoff."""
    last=None
    for att in range(retries):
        try:
            req=urllib.request.Request(BASE+"/chat/completions",
                data=json.dumps(payload).encode(),
                headers={"Content-Type":"application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            last=e
            if e.code in (500,502,503,504,429,400) and att<retries-1:
                time.sleep(min(20, 1.5*(2**att)))   # 1.5, 3, 6, 12, 20s
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last=e
            if att<retries-1:
                time.sleep(min(20, 1.5*(2**att))); continue
            raise
    raise last
def MID():
    with urllib.request.urlopen(BASE+"/models", timeout=30) as r:
        return json.loads(r.read().decode())["data"][0]["id"]
def key(r): return "%d:%d:%s"%(r["seed"], r["tick"], r["agent"])
def sig_of(case, cid):
    """Choice-signature: two candidate ids with identical (meaning,object) are interchangeable
    (the sim advertises e.g. two beds → two 'go sleep' ids). Stability is measured on the CHOICE,
    not the arbitrary id, so picking either duplicate is NOT a disagreement."""
    if cid is None: return None
    for c in case[K_CAND]:
        if c["id"]==cid: return "%s|%s"%(c.get(K_MEAN,""), c.get(K_OBJ,""))
    return "?"+str(cid)

SYS=(
"你是 Living Town 的封闭集角色行为选择器。\n"
"下面是若干道彼此独立的选择题。每题给出一位像素小镇居民的人设、此刻状态，"
"以及一组带唯一编号(id)的【候选】行动。\n"
"请为每一题挑选这位具体居民此刻最可能【主动】采取的一项行动。\n"
"判断顺序：\n"
"1. 先看这位居民明确写出的性格、身份与稳定倾向；\n"
"2. 再看与相关人物的具体关系、已知的私密、近期事件；\n"
"3. 然后才是当前需求、时段、地点与现实可行性。\n"
"硬性规则：\n"
"- 需求数值越低表示越缺，但“最低需求”不自动获胜；只有【迫切需求】明确列出时才应强烈左右选择。\n"
"- 不因为某个行动更戏剧化/更善良/更新奇就加分。\n"
"- 不得脑补输入中没有的动机、关系或事实。\n"
"- 候选的排列顺序不代表优先级。\n"
"- 每题只输出一行 `题号:候选id`（如 `3:c165a`），不要任何解释、不要复述。 /no_think"
)

def render_case(case, order, salient=True):
    """Render one packet case to text. `order` is a list of candidate indices into case[K_CAND].
    salient=False drops the 心结/待办约定 blocks (to isolate the salience-enrichment effect)."""
    res=case.get(K_RES,{}); now=case.get(K_NOW,{})
    pers=res.get(K_PERS,[]); pers=("·".join(pers) if isinstance(pers,list) else str(pers))
    job=res.get(K_JOB,"")
    L=[]
    L.append("【居民】%s%s性格：%s。身份：%s"%(
        res.get("name",""), ("（%s）"%job if job else "  "), pers, res.get(K_BIO,"")))
    needs=now.get(K_NEED,{})
    nd=" ".join("%s%s"%(k,v) for k,v in needs.items())
    L.append("【此刻】第%s天·%s·在%s。需求(%s)：%s。迫切需求：%s"%(
        now.get(K_DAY,""), now.get(K_TOD,""), now.get(K_LOC,""),
        now.get(K_SCALE,""), nd, now.get(K_URGENT,"无")))
    # salience blocks (present only on decisive cases) — placed high so the teacher weights them.
    # 心结 is now a list of pre-rendered strings (typed data lives at row-level "grievances").
    if salient:
        for line in case.get(K_GRIEV,[]):
            L.append("【心结】"+(line if isinstance(line,str) else str(line)))
        for line in case.get(K_STAKE,[]):
            L.append("【秘密处境】"+(line if isinstance(line,str) else str(line)))
        for d in case.get(K_DUE,[]):
            if isinstance(d,str): L.append("【待办约定】"+d)
            else: L.append("【待办约定】%s%s，还剩%s"%(d.get("对象",""), d.get(K_CONTENT,""), d.get(K_LEFT,"")))
    rels=case.get(K_REL,[])
    if rels:
        def _rel1(x):
            base="%s：%s·%s"%(x.get("who",""),x.get(K_AFF,""),x.get(K_FAM,""))
            return base+("·"+x[K_STANDING] if x.get(K_STANDING) else "")
        L.append("【关系】"+"；".join(_rel1(x) for x in rels))
    sec=case.get(K_SEC,[])
    L.append("【我知道的私密】"+("；".join(sec) if sec else "（无）"))
    rec=case.get(K_RECENT,[])
    L.append("【近事】"+("；".join(str(x) for x in rec) if rec else "（无）"))
    L.append("【候选】（顺序随机，无优先级）")
    cands=case[K_CAND]
    for i in order:
        c=cands[i]
        obj=c.get(K_OBJ,"")
        tail=("（对象：%s）"%obj) if obj else ""
        L.append("  %s = %s%s"%(c["id"], c.get(K_MEAN,""), tail))
    return "\n".join(L)

def parse_picks(text):
    """Return {qnum:int -> id:str}. id token = 3-6 alnum after the qnum separator."""
    picks={}
    for m in re.finditer(r'(?m)^\s*(\d+)\s*[:：\.\)]\s*([0-9A-Za-z]{2,8})', text):
        picks[int(m.group(1))]=m.group(2)
    return picks

def run_batch(items, orders, M, temperature=0, salient=True):
    """items: list of packet rows. orders: parallel list of candidate-index orderings.
    Returns list of (picked_id or None) parallel to items."""
    parts=[]
    for i,(r,od) in enumerate(zip(items,orders)):
        parts.append("【第%d题】\n%s"%(i+1, render_case(r["case"], od, salient)))
    usr="\n\n".join(parts)
    msg=[{"role":"system","content":SYS},
         {"role":"user","content":usr},
         {"role":"assistant","content":"</think>\n\n"}]
    resp=call({"model":M,"messages":msg,"temperature":temperature,"max_tokens":24*len(items)+64})
    txt=resp["choices"][0]["message"].get("content") or ""
    picks=parse_picks(txt)
    out=[]
    for i,r in enumerate(items):
        pid=picks.get(i+1)
        idset=set(c["id"] for c in r["case"][K_CAND])
        out.append(pid if (pid in idset) else None)
    return out, resp.get("usage",{})

def label_condition(name, sample, order_fn, batch, M, temperature=0):
    """order_fn(row)->list-of-cand-indices. Returns dict key-> {'pick':id,'pos':int}."""
    res={}; parsed=0; t0=time.time()
    for bi in range(0, len(sample), batch):
        chunk=sample[bi:bi+batch]
        orders=[order_fn(r) for r in chunk]
        try:
            picks,_=run_batch(chunk, orders, M, temperature)
        except Exception as e:
            print("  [%s] ERR @%d: %s"%(name,bi,str(e)[:80]), flush=True)
            picks=[None]*len(chunk)
        for pos,(r,pid) in enumerate(zip(chunk,picks)):
            res[key(r)]={"pick":pid,"pos":pos}
            if pid is not None: parsed+=1
        print("  [%s] %d/%d parsed=%d %.1fmin"%(name,min(bi+batch,len(sample)),len(sample),parsed,(time.time()-t0)/60), flush=True)
    return res, parsed

def canon(r):    return list(range(len(r["case"][K_CAND])))
def permuted(r):
    idx=list(range(len(r["case"][K_CAND])))
    random.Random(r["seed"]*100003+r["tick"]).shuffle(idx)   # deterministic per case
    return idx

def load_sample(DATA, N):
    """deterministic stratified sample (over-weight social)."""
    rows=[]
    for l in open(DATA, encoding="utf-8"):
        d=json.loads(l)
        if "case" in d and "id_map" in d:
            rows.append(d)
    soc=sorted([r for r in rows if r["cands"][r["pick"]]["kind"]=="social"], key=key)
    non=sorted([r for r in rows if r["cands"][r["pick"]]["kind"]!="social"], key=key)
    ns=min(len(soc), int(N*0.6)); nn=min(len(non), N-ns)
    def stride(a,k): return a[::max(1,len(a)//k)][:k] if k>0 else []
    sample=sorted(stride(soc,ns)+stride(non,nn), key=key)
    return sample, ns, nn

def main():
    DATA=sys.argv[1]; OUTD=sys.argv[2]
    N=int(sys.argv[3]) if len(sys.argv)>3 else 150
    B=int(sys.argv[4]) if len(sys.argv)>4 else 30
    os.makedirs(OUTD, exist_ok=True)
    sample, ns, nn = load_sample(DATA, N)
    M=MID()
    print("[calib] model=%s  sample=%d (social=%d/non=%d)  batch=%d"%(M,len(sample),ns,nn,B), flush=True)

    # ── condition passes ──
    print("[calib] pass 1/4: single (batch=1)", flush=True)
    S,   pS  = label_condition("single", sample, canon, 1, M)
    print("[calib] pass 2/4: batch-%d canonical order"%B, flush=True)
    Bc,  pBc = label_condition("batchC", sample, canon, B, M)
    print("[calib] pass 3/4: batch-%d candidate-permuted"%B, flush=True)
    Bp,  pBp = label_condition("batchP", sample, permuted, B, M)
    print("[calib] pass 4/4: batch-%d reversed case order (position test)"%B, flush=True)
    rev=list(reversed(sample))
    Br,  pBr = label_condition("batchR", rev, canon, B, M)

    # ── metrics ──
    tot=len(sample)
    CASE={key(r):r["case"] for r in sample}     # for signature lookup
    def agree(A,Bd,by_sig=True):
        both=n=0
        for k in A:
            a=A[k]["pick"]; b=Bd[k]["pick"]
            if a is not None and b is not None:
                both+=1
                if by_sig:
                    if sig_of(CASE[k],a)==sig_of(CASE[k],b): n+=1
                elif a==b: n+=1
        return (100.0*n/both if both else 0.0), both

    parse_total = pS+pBc+pBp+pBr
    parse_slots = tot*4
    parse_rate = 100.0*parse_total/parse_slots

    ag_sb, nb_sb = agree(S, Bc)          # single vs batch (canonical)  — by choice-signature
    ag_perm, nb_p = agree(Bc, Bp)        # canonical vs candidate-permuted
    ag_rev, nb_r = agree(Bc, Br)         # canonical vs reversed-order (corroborates position)
    ag_sb_raw,_ = agree(S, Bc, by_sig=False)     # raw-id (shows how much duplicate-collapse mattered)
    ag_perm_raw,_ = agree(Bc, Bp, by_sig=False)

    # position drift: signature-agreement-with-single for cases in the EARLY third vs LATE third of batch
    early=[]; late=[]; third=max(1,B//3)
    for k,v in Bc.items():
        if S[k]["pick"] is None or v["pick"] is None: continue
        hit = 1 if sig_of(CASE[k],S[k]["pick"])==sig_of(CASE[k],v["pick"]) else 0
        if v["pos"] < third: early.append(hit)
        elif v["pos"] >= B-third: late.append(hit)
    ag_early=100.0*sum(early)/len(early) if early else 0.0
    ag_late =100.0*sum(late)/len(late) if late else 0.0
    drift=abs(ag_early-ag_late)

    # teacher-vs-logic (informational; how often teacher matches the logic floor's CHOICE)
    tl_n=tl_hit=0
    logic={key(r):r["logic_pick_id"] for r in sample}
    for k in Bc:
        if Bc[k]["pick"] is not None:
            tl_n+=1
            if sig_of(CASE[k],Bc[k]["pick"])==sig_of(CASE[k],logic[k]): tl_hit+=1
    tl=100.0*tl_hit/tl_n if tl_n else 0.0

    GATES=[
        ("parse success",        parse_rate, ">=", 99.5),
        ("single-vs-batch",      ag_sb,      ">=", 90.0),
        ("candidate-perm stab",  ag_perm,    ">=", 85.0),
        ("batch-position drift", drift,      "<",  3.0),
    ]
    print("\n"+"="*56)
    print("PHASE C  CALIBRATION  (n=%d, batch=%d, model=%s)"%(tot,B,M))
    print("="*56)
    allpass=True
    for nm,val,op,thr in GATES:
        ok = (val>=thr) if op==">=" else (val<thr)
        allpass = allpass and ok
        print("  %-22s %6.1f%s  %s %s   %s"%(nm,val,("pp" if "drift" in nm else "%"),op,thr,"PASS" if ok else "FAIL"))
    print("  %-22s %6.1fpp  (early=%.1f late=%.1f)"%("  ↳ pos early/late",drift,ag_early,ag_late))
    print("  %-22s %6.1f%%   [informational — rev-order agreement]"%("rev-vs-canon",ag_rev))
    print("  %-22s %6.1f%%   [informational — RAW id, no dup-collapse]"%("single-vs-batch(raw)",ag_sb_raw))
    print("  %-22s %6.1f%%   [informational — RAW id, no dup-collapse]"%("perm-stab(raw)",ag_perm_raw))
    print("  %-22s %6.1f%%   [informational — teacher==logic floor]"%("teacher-vs-logic",tl))
    print("="*56)
    print("  RESULT:", "ALL GATES PASS ✅" if allpass else "GATES FAILED ❌")
    print("="*56, flush=True)

    summary={"n":tot,"batch":B,"model":M,"parse_rate":parse_rate,
        "single_vs_batch":ag_sb,"perm_stability":ag_perm,"rev_agreement":ag_rev,
        "single_vs_batch_raw":ag_sb_raw,"perm_stability_raw":ag_perm_raw,
        "pos_drift":drift,"pos_early":ag_early,"pos_late":ag_late,"teacher_vs_logic":tl,
        "gates_pass":allpass}
    json.dump(summary, open(os.path.join(OUTD,"phaseC_summary.json"),"w"), indent=2)
    det=open(os.path.join(OUTD,"phaseC_detail.jsonl"),"w",encoding="utf-8")
    for r in sample:
        k=key(r)
        det.write(json.dumps({"key":k,"single":S[k]["pick"],"batchC":Bc[k]["pick"],
            "batchP":Bp[k]["pick"],"batchR":Br[k]["pick"],"logic":logic[k],
            "pos":Bc[k]["pos"]},ensure_ascii=False)+"\n")
    det.close()
    print("[calib] wrote phaseC_summary.json + phaseC_detail.jsonl to", OUTD, flush=True)
    return 0 if allpass else 2

if __name__=="__main__":
    sys.exit(main())
