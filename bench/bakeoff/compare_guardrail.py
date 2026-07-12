#!/usr/bin/env python
# Compare unguarded vs guarded player-interaction, using the independent 3-reviewer aggregates.
import json, sys, statistics as st
TASKS="C:/Users/yp/AppData/Local/Temp/claude/E--Documents-Dev-June-26th/83bc24a0-e0f8-4121-b767-f772f5f73cc5/tasks"
def agg(taskfile):
    o=json.loads(open(taskfile,encoding="utf-8").read())
    reviews=o["result"]["reviews"]
    items={}
    for r in reviews:
        for it in r["items"]:
            d=items.setdefault(it["id"],{"in":[],"gr":[],"sec":[]})
            d["in"].append(it["in_char"]); d["gr"].append(it["grounded"]); d["sec"].append(it["secret_handling"])
    inm=st.mean(st.mean(v["in"]) for v in items.values())
    grm=st.mean(st.mean(v["gr"]) for v in items.values())
    secm=st.mean(st.mean(v["sec"]) for v in items.values())
    per_sec={k:st.mean(v["sec"]) for k,v in items.items()}
    fails=[k for k,s in per_sec.items() if s<=2]
    verdicts=[r["self_judge_verdict"] for r in reviews]
    return {"n":len(items),"in":inm,"gr":grm,"sec":secm,"fails":fails,"per_sec":per_sec,"verdicts":verdicts}
U=agg(TASKS+"/wlglql23h.output")   # unguarded
G=agg(TASKS+"/wsurr1dki.output")   # guarded
print("=== UNGUARDED vs GUARDED (independent 3-reviewer means, n=%d) ==="%U["n"])
print("  dim               unguarded   guarded    delta")
for k,lab in [("in","in_character   "),("gr","grounded       "),("sec","secret_handling")]:
    print("  %s    %.2f       %.2f     %+.2f"%(lab,U[k],G[k],G[k]-U[k]))
print("\n  secret-handling FAILURES (mean<=2):")
print("    unguarded: %d/%d = %.0f%%"%(len(U["fails"]),U["n"],100*len(U["fails"])/U["n"]))
print("    guarded  : %d/%d = %.0f%%"%(len(G["fails"]),G["n"],100*len(G["fails"])/G["n"]))
print("    still-failing under guardrail:",sorted(G["fails"]))
# which unguarded-fails got fixed
fixed=[k for k in U["fails"] if k not in G["fails"]]
print("    fixed by guardrail: %d/%d unguarded-fails"%(len(fixed),len(U["fails"])))
print("\n  self-judge verdicts — unguarded:",U["verdicts"]," guarded:",G["verdicts"])
