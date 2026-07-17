# Bake-off tooling (NPU decision path, Phase 0)

Reproduces the teacher-distillation baseline. Runtime state is regenerable, not committed.

1. **Generate the state dataset** (deterministic, ~18s):
   `godot --headless --path game --script res://bench/log_decisions.gd -- --seeds 1-6 --days 30 --out decisions_full.jsonl`
2. **Label with the teacher** (Nemotron-3-Super-120B @ LM Studio `127.0.0.1:1234`; think-off via `</think>` prefill; resumable, RAM-lean, ~2.9s/label):
   `python bench/bakeoff/labeler.py decisions_full.jsonl labels.jsonl 1000`
3. **Distill + held-out eval** (sklearn HistGBDT ranker vs logic vs random, all scored against the teacher):
   `python bench/bakeoff/train_eval.py decisions_full.jsonl labels.jsonl`

Phase-0 result (1000 labels): ranker 57.6% vs logic 18.3% vs random 8.6% top-1 to teacher.
Mechanism proven (tiny model distills the teacher), but the teacher is need-greedy realism, not
the logic floor's game-drama — so it's a mechanism win, not a quality win. See docs/22 §Phase-0.

## Re-aim: player-interaction eval (model-hard decisions)

`model_hard_scenarios.json` = 34 grounded scenarios (player free-text + emergent), anchored in the
town's real personas & secrets, with 4 cross-persona differentiation sets.

- `responder_judge.py scenarios.json results.jsonl` — model produces (action + in-character line) per
  scenario, then self-judges; records prefill/decode token profile.
- `analyze.py results.jsonl` — scores by type/persona, differentiation, NPU latency projection.
- The self-judge is UNRELIABLE (inflated 4.6→~3.4 vs independent review; missed 35% secret leaks +
  an empty answer). Use an INDEPENDENT reviewer.

Result: in-character VOICE strong (~4.0/5), but consequential JUDGMENT weak (secret_handling ~2.85,
35% leak a protected secret). Both experiments converge: engine decides facts/secrets/actions
(guardrailed), model only voices them. See docs/22 §Re-aim + docs/13.

## Decision-value study — status (after external Codex review, 2026-07-17)

The pivotal question is NOT "can a tiny GBDT distill Nemotron?" (already proven: 57.6%) but
**"is Nemotron's decision policy worth distilling?"** — i.e. when the teacher and the logic floor
DISAGREE, is the teacher's pick more *in-character*, or just *different*?

### exploratory_v0 (`batched_labeler.py`) — a DIVERGENCE STUDY, not quality evidence
- teacher = `nvidia/nemotron-3-super`, batch=30 (1M-context), N=3000 stratified from the
  6-seed×30-day dataset (19,204 decisions), OLD impoverished prompt (prompt-version v0).
- Offline-recomputed (never trust the streaming `agree so far`): **overall exact agreement 19.1%**,
  **logic-picked-social 2.3%**, logic-picked-object 51.7%, 100% parseable.
- **Confounds (do NOT train a production GBDT on these labels):**
  1. prompt framed needs as "最想满足:饥饿(71/100)" → induces need-greedy even when 71 is fine.
  2. teacher lacked bio/role, gossip subjects, secrets, factions, commitments → can't make a real
     social judgment.
  3. the "social" stratum was defined by `logic_pick.kind=="social"` → conditions on logic's output,
     mechanically manufacturing disagreement.
  4. sampling was order-biased (sort→stride→first-N gave seed-6 zero social); the terminal agreement
     line only covered the resume remainder.
- Read: strong evidence the STRATEGY changes a lot (teacher → everyday realism: 吃饭/洗澡/玩耍;
  logic → authored social drama: gossip_rep/confront/endorse), NOT yet evidence Nemotron is more
  in-character.

### Phase B (DONE): canonical case packet — `log_decisions.gd --packet`
Character-known-only info, shared by teacher AND the blind judge: resident {name,traits,bio,role},
moment {day,time,place, needs as a 0-100 SCALE, urgent-needs-only-if <45}, relationships as bands,
memories, **我知道的私密 (the actor's own + learned secrets)**, and candidates with **opaque shuffled
ids** (not score-ordered) + a plain-language **含义 (meaning)** per action. Pre-choice **strata** are
derived from candidates present (has_conflict/secret/reputation/social cand, object_only, need_urgent,
persona, ncand_bin) — never from logic's pick.

### Remaining plan (rigorous, per the review — multi-session)
- **Phase C — calibrate the teacher on the packet** before spending Claude budget: single-vs-batch
  agreement ≥90%, candidate-permutation stability ≥85%, parse ≥99.5%, batch-position drift <3pp.
- **Re-label** with the packet (natural distribution + a social-target stratum, reported separately).
- **Blind independent Claude pairwise judge** (A/B, balanced per persona×stratum, 15-20% mirror
  replays, 5-10% A=B negative controls, batch 8-12): "which is more in-character?" — never let the
  teacher grade itself; "more interesting/dramatic" is a SEPARATE prompt+endpoint, not weight-mixed.
- **Metrics**: p_eff = (teacher_win + 0.5·tie)/evaluable; net_gain; cluster-bootstrap CI by
  seed/trajectory over 30-50 seeds (6 is too few). Pre-registered gate: social-target p_eff≥0.60
  (CI lower >0.55) AND natural-weighted net-gain CI lower >0 AND no secret/conservation regression.
- **Trainer fixes** (`train_eval.py`): field names (`teacher`/`logic` ≠ `teacher_label`), whole-SEED
  split (MD5-key split leaks trajectories), LambdaRank group objective, strong baselines
  (global/persona action-prior, need-only), closed-loop trajectories (covariate shift).
- **Likely-best outcome** isn't teacher-vs-logic winner-take-all but a **layered** policy:
  logic owns crisis/constraints + whether to create a social opportunity (drama director); a learned
  character-ranker owns who-picks-what within a social opportunity; logic fallback on low-confidence.
