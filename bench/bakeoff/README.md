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
