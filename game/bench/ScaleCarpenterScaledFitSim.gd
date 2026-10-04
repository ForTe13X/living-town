extends "res://scripts/Sim.gd"

## Bench-only hypothesis: the carpenter uses shift-fit eligibility only when
## the existing population work-scaling term is active. At the base roster the
## inherited fisher/sanitation rule runs unchanged.
func _shift_fit_work(ag: Dictionary, candidates: Array) -> Array:
	var kept: Array = super._shift_fit_work(ag, candidates)
	if work_pull_mult <= 1.0:
		return kept
	var job: Dictionary = _job_of(String(ag.get("id", "")))
	if String(job.get("title", "")) != "木匠" or not _in_shift(job):
		return kept
	var shifts: Array = job.get("shift", [])
	if shifts.is_empty() or _phase_of(time_of_day()) == "":
		return kept
	var remaining := TICKS_PER_DAY
	for ahead in range(1, TICKS_PER_DAY + 1):
		var phase := _phase_of(fmod(time_of_day() + float(ahead) / TICKS_PER_DAY, 1.0))
		if phase not in shifts:
			remaining = ahead
			break
	var result: Array = []
	for candidate in kept:
		if String(candidate.get("action", "")) == _job_action(job):
			var cost := _walk_cost(ag, candidate) + float(candidate.get("dur_total", 0))
			if cost >= remaining:
				continue
		result.append(candidate)
	return result
