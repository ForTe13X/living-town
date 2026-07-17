#!/usr/bin/env python
# Scoped decisive re-test — STEP B1: build BLIND pairwise-judge tasks from decisive labels.
# For each case where teacher-salient-pick DIFFERS from logic-pick (by choice-signature), emit a
# blind A/B comparison of the two ACTIONS over the SAME salient context. Judge (Claude, independent —
# never the Nemotron teacher) will pick which is more in-character. We mirror-flip every case (A/B
# swapped) to cancel position bias, and keep which-side-is-teacher SECRET in the prompt but recorded.
# Output judge_tasks.json feeds the judge Workflow. Usage: python build_judge_tasks.py <labels.jsonl> <out.json>
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from calibrate import render_case, canon

LABELS=sys.argv[1]; OUTP=sys.argv[2]

def context_text(case):
    """Salient context WITHOUT the candidate list (judge compares only the two given actions)."""
    full=render_case(case, canon({"case":case}) if False else list(range(len(case["候选"]))), salient=True)
    return full.split("【候选】")[0].strip()

rows=[json.loads(l) for l in open(LABELS,encoding="utf-8")]
tasks=[]; agree=0; skipped=0; divergent=0
CONFLICT={"confront","apologize","mediate"}
for r in rows:
    ts=r.get("tsal_mean"); lg=r.get("logic_mean")
    if not ts or not lg:
        skipped+=1; continue
    if ts==lg:                        # teacher chose the same action → no comparison needed
        agree+=1; continue
    divergent+=1
    ctx=context_text(r["case"])
    for orient in (0,1):
        # orient 0: A=teacher, B=logic ; orient 1: swapped
        if orient==0: A_text,B_text,A_src=ts,lg,"teacher"
        else:         A_text,B_text,A_src=lg,ts,"logic"
        tasks.append({"tid":"%s#%d"%(r["key"],orient),"key":r["key"],"seed":r["seed"],
            "orient":orient,"A_text":A_text,"B_text":B_text,"A_src":A_src,
            "stance":r["stance"],"status":r["status"],"severity":r["severity"],
            "teacher_action":r.get("tsal_action"),"logic_action":r.get("logic_action"),
            "teacher_engaged":r.get("tsal_action") in CONFLICT,
            "logic_engaged":r.get("logic_action") in CONFLICT,
            "packet":ctx})
json.dump({"tasks":tasks,"n_cases":divergent,"n_agree":agree,"n_skipped":skipped,
    "n_tasks":len(tasks)}, open(OUTP,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
print("labels=%d | teacher==logic(agree)=%d | divergent=%d | skipped(parse)=%d | judge tasks=%d (mirror x2)"%(
    len(rows),agree,divergent,skipped,len(tasks)))
# divergence structure: what does the teacher pick INSTEAD of logic?
from collections import Counter
bykind=Counter()
for r in rows:
    ts=r.get("tsal_mean"); lg=r.get("logic_mean")
    if not ts or not lg or ts==lg: continue
    te=r.get("tsal_action") in CONFLICT; le=r.get("logic_action") in CONFLICT
    bykind[("engage" if le else "defer")+"→"+("engage" if te else "defer")]+=1
print("divergence structure (logic→teacher):",dict(bykind))
print("  teacher_action distribution on divergent:",dict(Counter(r.get("tsal_action") for r in rows
    if r.get("tsal_mean") and r.get("logic_mean") and r["tsal_mean"]!=r["logic_mean"])))
