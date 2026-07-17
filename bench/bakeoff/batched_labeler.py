#!/usr/bin/env python
# Batched teacher labeler (exploits a 1M-context teacher): pack B decisions into ONE call → B picks.
# Answers the Phase-4 decision gate at scale: when a frontier teacher and the logic floor DISAGREE,
# who is right? Compares teacher pick vs the logic pick on the IDENTICAL capped candidate set.
# Resumable (append per batch). Usage: python batched_labeler.py <dataset.jsonl> <out.jsonl> [N] [B]
import json, re, sys, urllib.request, time
BASE="http://127.0.0.1:1234/v1"
DATA=sys.argv[1]; OUTP=sys.argv[2]
N=int(sys.argv[3]) if len(sys.argv)>3 else 3000
B=int(sys.argv[4]) if len(sys.argv)>4 else 30

def call(payload,timeout=600):
    req=urllib.request.Request(BASE+"/chat/completions",data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=timeout) as r: return json.loads(r.read().decode())
def MID():
    with urllib.request.urlopen(BASE+"/models",timeout=30) as r: return json.loads(r.read().decode())["data"][0]["id"]
def lab(c):
    o=ord(c) if len(c)==1 else -1
    return o-48 if 48<=o<=57 else (o-65+10 if 65<=o<=90 else -1)
def user_block(p):
    m=re.search(r'<\|im_start\|>user\n(.*?)<\|im_end\|>', p, re.S)
    return m.group(1).strip() if m else ""
def key(r): return "%d:%d:%s"%(r["seed"],r["tick"],r["agent"])
M=MID()

# ── load + deterministic stratified sample (over-weight social, where teacher/logic most likely differ) ──
rows=[]
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l)
    if "prompt" in d and int(d.get("pick_in_cap",-1))>=0:
        rows.append(d)
soc=sorted([r for r in rows if r["cands"][r["pick"]]["kind"]=="social"], key=key)
non=sorted([r for r in rows if r["cands"][r["pick"]]["kind"]!="social"], key=key)
ns=min(len(soc), int(N*0.66)); nn=min(len(non), N-ns)
def stride(a,k): return a[::max(1,len(a)//k)][:k] if k>0 else []
sample=sorted(stride(soc,ns)+stride(non,nn), key=key)
print("[batch] model=%s  sample=%d (social=%d/non=%d)  batch=%d  out=%s"%(M,len(sample),ns,nn,B,OUTP),flush=True)

done=set()
try:
    for l in open(OUTP,encoding="utf-8"): done.add(json.loads(l)["key"])
except FileNotFoundError: pass
sample=[r for r in sample if key(r) not in done]
print("[batch] resuming, %d remain"%len(sample),flush=True)

SYS=("下面是若干道彼此独立的选择题。每题给一位像素小镇居民的人设、此刻状态和一组【候选】行动。"
     "请为【每一题】挑一个此刻最像这个居民会做的行动——贴合其性格与处境，而不是只满足最低需求。"
     "只按 `题号:编号` 逐行输出（编号是候选前的那个字符，如 3 或 A），一行一题，别写任何解释。 /no_think")

def run_batch(batch):
    parts=[]
    for i,r in enumerate(batch):
        parts.append("【第%d题】\n%s"%(i+1, user_block(r["prompt"])))
    usr="\n\n".join(parts)
    msg=[{"role":"system","content":SYS},{"role":"user","content":usr},{"role":"assistant","content":"</think>\n\n"}]
    r=call({"model":M,"messages":msg,"temperature":0,"max_tokens":16*len(batch)+64})
    t=r["choices"][0]["message"].get("content") or ""
    picks={}
    for m in re.finditer(r'(?m)^\s*(\d+)\s*[:：\.\)]\s*([0-9A-Za-z])', t):
        picks[int(m.group(1))]=m.group(2)
    return picks, r.get("usage",{})

out=open(OUTP,"a",encoding="utf-8"); t0=time.time(); n=0; agree=0
for bi in range(0,len(sample),B):
    batch=sample[bi:bi+B]
    try:
        picks,us=run_batch(batch)
    except Exception as e:
        print("[batch] ERR @%d: %s"%(bi,str(e)[:80]),flush=True); continue
    got=0
    for i,r in enumerate(batch):
        ch=picks.get(i+1,"")
        tp=lab(ch) if ch else -1
        ncap=len(r.get("cap_order",[]))
        if not (0<=tp<ncap): tp=-1
        lp=int(r["pick_in_cap"])
        rec={"key":key(r),"teacher":tp,"logic":lp,"n":ncap,"kind":r["cands"][r["pick"]]["kind"],
             "logic_action":r["cands"][r["pick"]]["action"]}
        if tp>=0:
            got+=1; n+=1
            if tp==lp: agree+=1
        out.write(json.dumps(rec,ensure_ascii=False)+"\n")
    out.flush()
    print("[batch] %d/%d done | this batch parsed %d/%d | agree so far %.1f%% | %.1f min | pre=%d"%(
        min(bi+B,len(sample)),len(sample),got,len(batch),(100*agree/n if n else 0),(time.time()-t0)/60,us.get("prompt_tokens",0)),flush=True)
out.close()
print("[batch] DONE labeled=%d  teacher==logic agreement=%.1f%%  %.1f min"%(n,(100*agree/n if n else 0),(time.time()-t0)/60),flush=True)
