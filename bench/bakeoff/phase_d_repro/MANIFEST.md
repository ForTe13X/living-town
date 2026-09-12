# Phase D — reproducibility manifest

Everything needed to re-run / re-check the Phase-D confirmatory eval + closed-loop A/B, minus the 638 MiB
raw packet (referenced by SHA only — regenerate it deterministically with the command below).

## Artifacts in this dir (tracked; small)
| file | what |
|---|---|
| `combined_judge_wf.js` | the actual judge Workflow script (neutral 3-axis, mirror, 2 passes) that produced the verdicts |
| `combined_payload.json` | 190 judge tasks (88 real cases × mirror + 14 A=A controls) across the 4 opportunities + their packets |
| `T_{conflict,secret,endorse,faction}.json` | per-opportunity judge tasks before combining |
| `verdicts_all.json` | 380 raw judge verdicts (the workflow return value) — re-aggregate to reproduce every number |
| `ab_results.txt` | the 4-config closed-loop A/B ABMETRIC lines (Step 3) |
| `verdict_summary.txt` | `aggregate_phase_d.py` output (p_eff per axis + CI + mirror-consistency + A=A tie-rate + per-persona) |

## SHA-256 (integrity)
```
packet_c30.jsonl (638 MiB, NOT committed)   17932c499bbf4ed2...   # regenerate; see cmd 1
combined_payload.json                        53ae5c3e61f3d412...
verdicts_all.json                            174c76a0c05635e9...
T_conflict.json  edac4195...  T_secret.json  f24ac576...
T_endorse.json   d3609d34...  T_faction.json dc48267a...
```

## Commands (deterministic; run from repo root)
```bash
# 1) regenerate the packet (deterministic, ~2 min) — should hash to 17932c49...
godot --headless --path game --script res://bench/log_decisions.gd -- \
  --seeds 1-30 --days 45 --out "$PWD/analysis/phase_d/packet_c30.jsonl" --packet

# 2) build the 4 opportunities' judge tasks (first-class passive intents; event-window dedup; seed-strided)
P=analysis/phase_d/packet_c30.jsonl
python bench/bakeoff/build_conflict_judge.py $P analysis/phase_d/T_conflict.json 48
python bench/bakeoff/build_secret_judge.py   $P analysis/phase_d/T_secret.json   48
python bench/bakeoff/build_endorse_judge.py  $P analysis/phase_d/T_endorse.json  48
python bench/bakeoff/build_faction_judge.py  $P analysis/phase_d/T_faction.json  48

# 3) combine (cap 22 cases + 4 controls/opportunity, round-robin by seed) + generate the judge workflow
python analysis/phase_d/gen_combined_payload.py 22 4
python analysis/phase_d/gen_judge_wf.py analysis/phase_d/combined_payload.json analysis/phase_d/combined_judge_wf.js 2

# 4) run combined_judge_wf.js via the Workflow tool (380 blind Claude judgments); save its return → verdicts_all.json

# 5) aggregate (p_eff per axis, cluster-bootstrap CI by seed, mirror-consistency, A=A tie-rate, per-persona)
python bench/bakeoff/aggregate_phase_d.py analysis/phase_d/verdicts_all.json

# 6) closed-loop A/B (Step 3) — 4 configs × 12 seeds × 45 days
for cfg in "--char off --gate 30 --blunt new" "--char on --gate 30 --blunt old" \
           "--char on --gate 30 --blunt new" "--char on --gate 22 --blunt new"; do
  godot --headless --path game --script res://bench/ab_metrics.gd -- $cfg --seeds 1-12 --days 45
done
# forgiveness-fade off/on (Step 5): add --fade off | --fade on
```

## Honest reporting caveats (per external audit — do NOT overstate)
- **"380 judgments" ≠ 380 independent cases.** It is **88 underlying cases** (22/opportunity) + 14 A=A controls,
  each judged under mirror-flip × 2 same-model passes. Treat the case, not the judgment, as the unit.
- **Mirror-consistency (same verdict irrespective of A/B position), in_character:** conflict 95%, secret 100%,
  faction 95%, **endorse 82%** — endorse's position-robustness is the weakest; weight it accordingly.
- **The "extended-blunt" signal is thin:** evy = **1** underlying conflict case, tie = **2**. That the closed-loop
  A/B (#15 emergent-ostracism) still vetoed the extension is the point — 1–2 cases don't override a broken invariant.
- **Two arms are structurally empty in this packet, not merely unsampled:** all 267 endorse-candidate cases are
  aria (the CHARACTER rule pre-suppresses the endorse candidate for every other persona), and aria has **0**
  secret-stake cases (her leak is DRAMA-boosted + rare). Verifying "non-gossip default-abstain on endorse" and
  "aria's gossip-leak exception" needs targeted follow-up evals (a rule-off packet; captured aria-leak moments),
  which Phase D did NOT run. The reported endorse result is aria-only; the secret result excludes aria.
- **Not a clean teacher-vs-logic adjudication.** Phase D compared constructed aggressive/passive intents on a
  blind Claude judge; it did **not** re-run the Nemotron teacher on the clean packet. Conclusion supported:
  "no evidence to restart GBDT". Conclusion NOT claimed: "the teacher is disproven".
