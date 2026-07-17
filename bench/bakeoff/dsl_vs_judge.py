#!/usr/bin/env python
# Feature probe + DSL calibration against the clean blind judge (in-character ground truth).
# The judge decisively prefers DEFER on open grievances. Which persona traits flip it to CONFRONT?
# Then: does a character-aware DSL (default defer; engage for confront-associated traits) match the judge
# far better than logic's always-confront? Offline, deterministic.
# Usage: python dsl_vs_judge.py <packet_v1.jsonl> <judge_dir>
import json, sys, os, glob
from collections import defaultdict, Counter

DATA=sys.argv[1]; JD=sys.argv[2]
# optional 3rd arg = comma-separated FROZEN confront-traits (held-out test: rule fit on judge #1,
# applied to a disjoint judge #2). If omitted, traits are derived in-sample (optimistic).
FROZEN=set(sys.argv[3].split(",")) if len(sys.argv)>3 and sys.argv[3] else None
mapping=json.load(open(os.path.join(JD,"mapping.json"),encoding="utf-8"))
verdicts=[]
for f in glob.glob(os.path.join(JD,"verdicts","verdict_*.json")): verdicts+=json.load(open(f,encoding="utf-8"))

# judge winner per case (combine mirror orientations)
SCORE={"confront":1.0,"tie":0.5,"defer":0.0}
bycase=defaultdict(list)
for v in verdicts:
    if v["tid"].endswith("#ctl"): continue
    m=mapping.get(v["tid"]);
    if not m: continue
    w = "tie" if v["choice"]=="平" else (m["A_src"] if v["choice"]=="A" else m["B_src"])
    bycase[m["key"]].append(SCORE[w])
judge={k: ("confront" if sum(v)/len(v)>0.5 else "defer" if sum(v)/len(v)<0.5 else "tie")
       for k,v in bycase.items()}

# join traits/severity/persona from packet_v1
rowk={}
for l in open(DATA,encoding="utf-8"):
    d=json.loads(l); rowk["%d:%d:%s"%(d["seed"],d["tick"],d["agent"])]=d
def traits_of(k):
    r=rowk.get(k); return set(r["case"].get("居民",{}).get("性格",[])) if r else set()
def persona_of(k):
    r=rowk.get(k); return r["persona"] if r else "?"

# ── feature probe: trait frequency by judge winner ──
tw=Counter(); td=Counter(); pw=Counter(); pd=Counter()
for k,w in judge.items():
    if w=="tie": continue
    for t in traits_of(k): (tw if w=="confront" else td)[t]+=1
    (pw if w=="confront" else pd)[persona_of(k)]+=1
print("="*60)
print("FEATURE PROBE — what flips the judge to CONFRONT?")
print("="*60)
print("  trait                 confront   defer")
alltr=sorted(set(tw)|set(td), key=lambda t:-(tw[t]-td[t]))
for t in alltr:
    print("    %-16s %6d %7d"%(t,tw[t],td[t]))
print("  persona (confront-leaning):", [p for p in pw if pw[p]>=pd.get(p,0) and pw[p]>0])

# ── confront-traits: FROZEN (held-out) or derived in-sample ──
if FROZEN is not None:
    CONFRONT_TRAITS=FROZEN
    print("\n  → FROZEN confront-traits (held-out, from judge #1):", CONFRONT_TRAITS)
else:
    CONFRONT_TRAITS={t for t in alltr if tw[t]>td[t] and tw[t]>=2}
    print("\n  → confront-associated traits (in-sample):", CONFRONT_TRAITS or "(none strong)")

# ── policies vs judge (exclude ties) ──
judged=[(k,w) for k,w in judge.items() if w!="tie"]
def agree(policy):
    ok=eng=0
    for k,w in judged:
        p="confront" if policy(k) else "defer"
        ok += (p==w); eng += (p=="confront")
    return 100*ok/len(judged), 100*eng/len(judged)
a_logic,e_logic=agree(lambda k: True)                                   # always confront
a_char,e_char=agree(lambda k: bool(traits_of(k)&CONFRONT_TRAITS))       # engage iff confront-trait
a_defer,_=agree(lambda k: False)                                        # always defer
print("\n"+"="*60)
print("POLICY vs BLIND JUDGE  (n=%d judged, ties excluded)"%len(judged))
print("="*60)
print("  logic  (always confront)   agree %.0f%%   engage %.0f%%"%(a_logic,e_logic))
print("  defer  (always defer)      agree %.0f%%   engage  0%%"%a_defer)
print("  char   (trait→confront)    agree %.0f%%   engage %.0f%%"%(a_char,e_char))
print("="*60)
print("  READ: a character-aware default-defer + trait-engage policy should track the judge far better")
print("        than logic's always-confront — first evidence the DSL can beat logic on in-character.")
