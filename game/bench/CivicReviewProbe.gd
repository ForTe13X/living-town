extends SceneTree
## LT-17 measurement only: hold the day-56 voters and relationships fixed, then
## compare the policy-adjusted mayor review with a raw-treasury counterfactual
## using the same voters. This does not change the election.

const SimScript = preload("res://scripts/Sim.gd")
const PROJECT_ID := "hydrangea_square_planters_v1"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed := 7
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--seed="):
			seed = int(String(arg).substr(7))
	var sim = SimScript.new()
	root.add_child(sim)
	sim.backend = null
	sim.auto_run = false
	sim.start_new(seed)
	while sim.tick_no < 55 * sim.TICKS_PER_DAY + 1:
		sim.tick()
	if sim.mayor_log.size() < 2:
		printerr("CivicReviewProbe: missing consecutive mayor terms")
		quit(1)
		return
	var review: Dictionary = sim.mayor_log[0]
	var next_term: Dictionary = sim.mayor_log[1]
	var raw_delta := int(review.get("treasury_delta", 0))
	if raw_delta != int(review.get("town_coin_end", 0)) - int(review.get("town_coin_start", 0)):
		printerr("CivicReviewProbe: raw treasury review is not conserved")
		quit(1)
		return
	var capital_spend := 0
	var paid_receipts := 0
	for raw in sim.event_log:
		var e: Dictionary = raw
		if String(e.get("type", "")) == "pay" \
				and String(e.get("txid", "")) == "%s:term:%d" % [PROJECT_ID, int(review["term_start"])] \
				and String(e.get("note", "")) == "civic_project:%s*5" % PROJECT_ID \
				and String(e.get("actor", "")) == "town" and String(e.get("target", "")) == "external":
			capital_spend += int(e.get("amt", 0))
			paid_receipts += 1
	var raw_review := review.duplicate(true)
	raw_review.erase("civic_capital_spend")
	var candidates: Array = next_term.get("candidates", [])
	var raw_ballots := {}
	var adjusted_ballots := {}
	var changed_voters := []
	var score_changes := []
	for voter in sim.agents:
		if bool(voter.get("is_player", false)):
			continue
		var raw_score: Dictionary = sim.mayor_review_score(voter, raw_review)
		var adjusted_score: Dictionary = sim.mayor_review_score(voter, review)
		var raw_choice: String = sim._mayor_vote(voter, candidates, raw_review)
		var adjusted_choice: String = sim._mayor_vote(voter, candidates, review)
		raw_ballots[raw_choice] = int(raw_ballots.get(raw_choice, 0)) + 1
		adjusted_ballots[adjusted_choice] = int(adjusted_ballots.get(adjusted_choice, 0)) + 1
		if raw_choice != adjusted_choice:
			changed_voters.append(String(voter.get("id", "")))
		if raw_score != adjusted_score:
			score_changes.append({"voter": String(voter.get("id", "")),
				"raw": raw_score.get("treasury", 0), "adjusted": adjusted_score.get("treasury", 0)})
	var result := {"seed": seed, "tick": sim.tick_no, "core_population": sim.core_population,
		"agents_total": sim.agents.size(), "backend": "logic", "term_start": int(review["term_start"]),
		"next_term_start": int(next_term["term_start"]),
		"raw_treasury_delta": raw_delta, "civic_capital_spend": capital_spend,
		"paid_receipts": paid_receipts, "adjusted_treasury_delta": raw_delta + capital_spend,
		"actual_ballots": next_term.get("ballots", {}), "raw_recomputed_ballots": raw_ballots,
		"adjusted_ballots": adjusted_ballots, "changed_voters": changed_voters,
		"score_changes": score_changes}
	print("CivicReviewProbe " + JSON.stringify(result))
	if adjusted_ballots != next_term.get("ballots", {}):
		printerr("CivicReviewProbe: adjusted recomputation disagrees with recorded election")
		quit(1)
		return
	print("CivicReviewProbe: PASS")
	quit(0)
