extends "res://bench/ScaleCarpenterStockFitSim.gd"

## LT-14 bench-only directed hypothesis: when seafood is empty and the fisher
## has no need below 70, give a small score preference to a shift-fit job.
## The carpenter stock-gated eligibility trial remains inherited.
func _object_candidates(ag: Dictionary) -> Array:
	var out: Array = super._object_candidates(ag)
	if _min_need(ag) < 70.0:
		return out
	var job: Dictionary = _job_of(String(ag.get("id", "")))
	if String(job.get("title", "")) != "渔夫" or not _in_shift(job):
		return out
	var raw: Dictionary = production.get("produce", {}).get("渔夫", {})
	var good := String(raw.get("good", ""))
	if good.is_empty() or _stock_of(good) != 0:
		return out
	var shifts: Array = job.get("shift", [])
	if shifts.is_empty() or _phase_of(time_of_day()) == "":
		return out
	var remaining := TICKS_PER_DAY
	for ahead in range(1, TICKS_PER_DAY + 1):
		var phase := _phase_of(fmod(time_of_day() + float(ahead) / TICKS_PER_DAY, 1.0))
		if phase not in shifts:
			remaining = ahead
			break
	for candidate in out:
		if String(candidate.get("action", "")) != _job_action(job):
			continue
		var cost := _walk_cost(ag, candidate) + float(candidate.get("dur_total", 0))
		if cost >= remaining:
			continue
		candidate["score"] = float(candidate.get("score", 0.0)) + 6.0
	return out
