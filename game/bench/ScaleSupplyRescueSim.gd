extends "res://bench/ScaleProbeSim.gd"

## LT-14 isolated trial: prefer a feasible low-stock shift without bypassing care.
const LOW_STOCK_QUARTER := 4
const SHIFT_END_TOD := 0.68
var min_healthy_need := 65.0
var work_bonus := 8.0

func _object_candidates(ag: Dictionary) -> Array:
	var out: Array = super._object_candidates(ag)
	var aid := String(ag.get("id", ""))
	if aid not in ["hai", "tie"] or _min_need(ag) < min_healthy_need:
		return out
	var job: Dictionary = _job_of(aid)
	if job.is_empty() or not _in_shift(job):
		return out
	var title := String(job.get("title", ""))
	var raw: Dictionary = production.get("produce", {}).get(title, {})
	var good := String(raw.get("good", ""))
	var cap := int(production.get("goods", {}).get(good, {}).get("cap", 0))
	if cap <= 0 or _stock_of(good) * LOW_STOCK_QUARTER > cap:
		return out
	var shift_end_tick := int(SHIFT_END_TOD * TICKS_PER_DAY)
	var remaining := shift_end_tick - tick_no % TICKS_PER_DAY
	for c in out:
		if not (c is Dictionary):
			continue
		var cand: Dictionary = c
		if String(cand.get("action", "")) != _job_action(job):
			continue
		var needed := ceili(_walk_cost(ag, cand)) + int(cand.get("dur_total", 0)) + 2
		if needed > remaining:
			continue
		cand["score"] = float(cand.get("score", 0.0)) + work_bonus
	return out
