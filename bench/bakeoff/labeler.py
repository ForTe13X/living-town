#!/usr/bin/env python
# Think-off teacher labeler for the bake-off baseline. Resumable, streaming, one call at a time (RAM-lean).
# Usage: python labeler.py <dataset.jsonl> <labels_out.jsonl> [N]
import json, re, sys, time, urllib.request
BASE="http://127.0.0.1:1234/v1"
DATA=sys.argv[1]; OUTP=sys.argv[2]; N=int(sys.argv[3]) if len(sys.argv)>3 else 1000

def call(payload,timeout=120):
    req=urllib.request.Request(BASE+"/chat/completions",data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=timeout) as r: return json.loads(r.read().decode())
def MID():
    with urllib.request.urlopen(BASE+"/models",timeout=30) as r: return json.loads(r.read().decode())["data"][0]["id"]
def split_prompt(p):
    s=re.search(r'<\|im_start\|>system\n(.*?)<\|im_end\|>',p,re.S); u=re.search(r'<\|im_start\|>user\n(.*?)<\|im_end\|>',p,re.S)
    return (s.group(1) if s else ""),(u.group(1) if u else "")
def lab(c):
    o=ord(c) if len(c)==1 else -1
    return o-48 if 48<=o<=57 else o-65+10 if 65<=o<=90 else -1
def parse_pick(t,n):
    if not t: return -1
    for ch in t.strip()[:8]:
        k=lab(ch)
        if 0<=k<n: return k
    ms=re.findall(r'(?<![0-9A-Za-z])([0-9A-Z])(?![0-9A-Za-z])',t)
    for ch in ms:
        k=lab(ch)
        if 0<=k<n: return k
    return -1
M=MID()

# deterministic stratified sample: every step-th row that has a prompt
allrows=[]
with open(DATA,encoding="utf-8") as f:
    for i,line in enumerate(f):
        d=json.loads(line)
        if "prompt" in d: allrows.append(d)
step=max(1,len(allrows)//N)
sample=allrows[::step][:N]
del allrows
print("[labeler] model=%s  pool→sample=%d (step=%d)  out=%s"%(M,len(sample),step,OUTP),flush=True)

# resume: skip already-labeled keys
done=set()
try:
    for line in open(OUTP,encoding="utf-8"):
        done.add(json.loads(line)["key"])
except FileNotFoundError:
    pass
print("[labeler] resuming, %d already done"%len(done),flush=True)

def ask(sysp,usr,n):
    for mt in (6,10):
        try:
            r=call({"model":M,"messages":[{"role":"system","content":sysp},{"role":"user","content":usr},{"role":"assistant","content":"</think>\n\n"}],"temperature":0,"max_tokens":mt})
            k=parse_pick(r["choices"][0]["message"].get("content") or "",n)
            if k>=0: return k
        except Exception as e:
            time.sleep(1)
    return -1

out=open(OUTP,"a",encoding="utf-8")
t0=time.time(); n_new=0; n_bad=0
for j,d in enumerate(sample):
    key="%d:%d:%s"%(d["seed"],d["tick"],d["agent"])
    if key in done: continue
    sysp,usr=split_prompt(d["prompt"]); n=len(d["cap_order"])
    tk=ask(sysp,usr,n)
    if tk<0: n_bad+=1
    rec={"key":key,"seed":d["seed"],"tick":d["tick"],"agent":d["agent"],"persona":d["persona"],
         "n_cap":n,"logic_label":d["pick_in_cap"],"teacher_label":tk}
    out.write(json.dumps(rec,ensure_ascii=False)+"\n"); out.flush()
    n_new+=1
    if n_new%25==0:
        el=time.time()-t0
        print("[labeler] %d/%d labeled (%.1fs, %.1fs/label, bad=%d)"%(n_new,len(sample)-len(done),el,el/n_new,n_bad),flush=True)
out.close()
print("[labeler] DONE: %d new labels, %d unparseable, %.1f min total"%(n_new,n_bad,(time.time()-t0)/60),flush=True)
