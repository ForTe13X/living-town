#!/usr/bin/env python
# Analyze the player-interaction eval: scores by type/persona, cross-persona differentiation, NPU latency projection.
import json, sys, collections, statistics as st
R=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8")]
ok=[r for r in R if r.get("in_char",-1)>0]
print("=== player-interaction eval: %d scenarios (%d scored) ==="%(len(R),len(ok)))
def mean(xs): return round(sum(xs)/len(xs),2) if xs else 0
for d in ("in_char","grounded","specific"):
    print("  %-9s mean %.2f/5   dist %s"%(d,mean([r[d] for r in ok]),dict(collections.Counter(r[d] for r in ok))))
comp=[ (r["in_char"]+r["grounded"]+r["specific"])/3 for r in ok]
print("  composite mean %.2f/5  (>=4 good, <=2 poor)"%mean(comp))
print("  scenarios composite>=4: %.0f%%   composite<=2: %.0f%%"%(100*sum(1 for c in comp if c>=4)/len(comp),100*sum(1 for c in comp if c<=2)/len(comp)))

print("\n=== by scenario type (composite) ===")
byt=collections.defaultdict(list)
for r in ok: byt[r["type"]].append((r["in_char"]+r["grounded"]+r["specific"])/3)
for t,v in sorted(byt.items(),key=lambda x:-mean(x[1])): print("  %-22s %.2f  (n=%d)"%(t,mean(v),len(v)))

print("\n=== cross-persona DIFFERENTIATION (same situation, different personas) ===")
sets=collections.defaultdict(list)
for r in ok:
    if r.get("diff_set"): sets[r["diff_set"]].append(r)
if not sets: print("  (no differentiation sets tagged)")
for sid,rs in sets.items():
    acts={r["action"] for r in rs}; lines={r["line"] for r in rs}
    print("  [%s] %d personas | distinct actions=%d lines=%d | mean 入戏 %.1f"%(sid,len(rs),len(acts),len(lines),mean([r["in_char"] for r in rs])))
    for r in rs: print("      %-5s → %s / %s"%(r["persona_name"],r["action"][:16],r["line"][:38]))

print("\n=== latency / NPU feasibility projection ===")
pre=[r["prompt_tokens"] for r in ok]; dec=[r["response_tokens"] for r in ok]; rea=[r["reasoning_tokens"] for r in ok]
print("  prefill tokens (prompt):  p50=%d p90=%d max=%d"%(int(st.median(pre)),sorted(pre)[int(.9*len(pre))-1],max(pre)))
print("  deployable decode (response only): p50=%d p90=%d  (reasoning tokens, ceiling-only: p50=%d)"%(int(st.median(dec)),sorted(dec)[int(.9*len(dec))-1],int(st.median(rea))))
# projections: prefill on NPU ~1500 tok/s (edge-npu measured 1000-1700 for 4B; small model faster); decode small-model on-device 10-30 tok/s
for label,pf,dcr in [("NPU prefill 1500 t/s + decode 30 t/s (optimistic small model)",1500,30),
                     ("NPU prefill 1500 t/s + decode 15 t/s (conservative)",1500,15)]:
    p50pre=st.median(pre)/pf*1000; p50dec=st.median(dec)/dcr*1000
    print("  %s:\n      p50 ≈ %.0fms prefill + %.0fms decode = %.0fms  (vs phone-CPU today ~5000ms+)"%(label,p50pre,p50dec,p50pre+p50dec))
print("  NOTE: prefill is the NPU's strength (short player msg + context); decode of a SHORT reply is the cost.")
print("        On-device you'd run a small non-reasoning model (decode=response only), NOT the 120B's reasoning.")

print("\n=== weakest 3 (composite) — sanity check the judge isn't rubber-stamping ===")
worst=sorted(ok,key=lambda r:(r["in_char"]+r["grounded"]+r["specific"]))[:3]
for r in worst:
    print("  [%s %s] 入%d扣%d具%d %s"%(r["type"],r["persona_name"],r["in_char"],r["grounded"],r["specific"],r.get("critique","")))
    print("      msg:%s\n      →%s / %s"%(r.get("player_message","")[:50],r["action"][:20],r["line"][:50]))
