extends RefCounted
## One authored civic project. Its events are the authority; this fold is also
## used to validate saved logs before a live Sim is changed by quickload.

const PROJECT_ID := "hydrangea_square_planters_v1"
const PAY_PREFIX := "civic_project:" + PROJECT_ID + "*"

static func _bad(message: String) -> Dictionary:
	return {"ok": false, "error": message, "state": {}, "attempts": {}}

static func fold(log: Array) -> Dictionary:
	var attempts := {}
	var state := {}
	var ever_paid := false
	for raw in log:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var kind := String(e.get("type", ""))
		var note := String(e.get("note", ""))
		var proposal_id := String(e.get("proposal_id", e.get("txid", "")))
		if kind == "civic_proposal" and String(e.get("subject", "")) == PROJECT_ID:
			if ever_paid or proposal_id == "" or attempts.has(proposal_id):
				return _bad("duplicate or post-payment proposal")
			if not state.is_empty() and String(state.get("status", "")) not in ["rejected", "unfunded"]:
				return _bad("prior proposal is not terminal")
			if not state.is_empty() and int(e.get("term_start", -1)) <= int(state.get("term_start", -1)):
				return _bad("new proposal does not belong to a later term")
			var members = e.get("council", [])
			if not (members is Array) or (members as Array).size() != 3:
				return _bad("proposal council is not three members")
			var unique := {}
			for member in members:
				if not (member is String) or String(member) == "" or unique.has(member):
					return _bad("proposal council has duplicate or invalid member")
				unique[member] = true
			var term_start := int(e.get("term_start", -1))
			if proposal_id != "%s:term:%d" % [PROJECT_ID, term_start] \
					or String(e.get("mayor", "")) not in members \
					or term_start < 28 or int(e.get("term_end", -1)) < term_start \
					or int(e.get("cost", -1)) != 5 or String(e.get("payee", "")) != "external" \
					or String(e.get("actor", "")) != String(e.get("mayor", "")) \
					or String(e.get("target", "")) != "plaza" or not bool(e.get("accepted", false)) \
					or int(e.get("tick", -1)) != (term_start - 1) * 240 + 1:
				return _bad("proposal identity, term or payment terms are invalid")
			var sorted_members := (members as Array).duplicate()
			sorted_members.sort()
			if sorted_members != members:
				return _bad("proposal council is not in stable ID order")
			state = {"id": PROJECT_ID, "proposal_id": proposal_id, "term_start": term_start,
				"term_end": int(e["term_end"]), "mayor": String(e["mayor"]),
				"council": (members as Array).duplicate(), "cost": 5, "payee": "external",
				"reserve_snapshot": int(e.get("reserve_snapshot", -1)),
				"treasury_snapshot": int(e.get("treasury_snapshot", -1)),
				"proposal_event_id": int(e.get("id", -1)), "proposal_tick": int(e.get("tick", -1)),
				"votes": {}, "status": "proposed"}
			if int(state["reserve_snapshot"]) < 0 or int(state["treasury_snapshot"]) < 0:
				return _bad("proposal finance snapshot is invalid")
			attempts[proposal_id] = state
			continue
		if kind == "civic_vote" and String(e.get("subject", "")) == PROJECT_ID:
			if state.is_empty() or proposal_id != String(state["proposal_id"]) or state["status"] != "proposed":
				return _bad("vote has no open proposal")
			var voter := String(e.get("actor", ""))
			var votes: Dictionary = state["votes"]
			var margin := int(state["treasury_snapshot"]) - int(state["cost"]) - int(state["reserve_snapshot"])
			var expected_vote := "yes" if margin >= (0 if voter == String(state["mayor"]) else 2) else "no"
			var vote_tick := int(e.get("tick", -1))
			if voter not in state["council"] or votes.has(voter) or note != expected_vote \
					or String(e.get("target", "")) != proposal_id or not bool(e.get("accepted", false)) \
					or vote_tick not in [int(state["proposal_tick"]), int(state["proposal_tick"]) + 1] \
					or (state.has("vote_tick") and vote_tick != int(state["vote_tick"])):
				return _bad("vote is duplicate, ineligible or invalid")
			state["vote_tick"] = vote_tick
			votes[voter] = note
			continue
		if kind == "civic_decision" and String(e.get("subject", "")) == PROJECT_ID:
			if state.is_empty() or proposal_id != String(state["proposal_id"]) or state["status"] != "proposed":
				return _bad("decision has no open proposal")
			var votes: Dictionary = state["votes"]
			if votes.size() != 3:
				return _bad("decision lacks full quorum")
			var yes_count := 0
			for vote in votes.values():
				if vote == "yes": yes_count += 1
			var expected := "approved" if yes_count >= 2 else "rejected"
			if note != expected or int(e.get("yes", -1)) != yes_count or int(e.get("no", -1)) != 3 - yes_count \
					or String(e.get("actor", "")) != String(state["mayor"]) \
					or String(e.get("target", "")) != proposal_id \
					or bool(e.get("accepted", false)) != (expected == "approved") \
					or int(e.get("tick", -1)) != int(state.get("vote_tick", -2)):
				return _bad("decision disagrees with frozen ballots")
			state["status"] = expected
			state["decision_event_id"] = int(e.get("id", -1))
			continue
		if kind == "pay" and note.begins_with("civic_project:"):
			if state.is_empty() or state["status"] != "approved" or proposal_id != String(state["proposal_id"]):
				return _bad("project payment has no approval")
			if note != PAY_PREFIX + str(state["cost"]) or String(e.get("actor", "")) != "town" \
					or String(e.get("target", "")) != "external" or int(e.get("amt", -1)) != int(state["cost"]) \
					or not bool(e.get("accepted", false)) or int(e.get("tick", -1)) < int(state["proposal_tick"]) \
					or int(e.get("tick", -1)) > int(state["term_end"]) * 240:
				return _bad("project payment recipient, reason or amount is invalid")
			state["status"] = "funded"
			state["pay_event_id"] = int(e.get("id", -1))
			ever_paid = true
			continue
		if kind == "civic_unfunded" and String(e.get("subject", "")) == PROJECT_ID:
			if state.is_empty() or proposal_id != String(state["proposal_id"]) or state["status"] != "approved":
				return _bad("unfunded event has no unpaid approval")
			if String(e.get("actor", "")) != "town" or String(e.get("target", "")) != "plaza" \
					or bool(e.get("accepted", true)):
				return _bad("unfunded event identity is invalid")
			state["status"] = "unfunded"
			state["unfunded_event_id"] = int(e.get("id", -1))
			continue
		if kind == "civic_start" and String(e.get("subject", "")) == PROJECT_ID:
			if state.is_empty() or state["status"] != "funded" or proposal_id != String(state["proposal_id"]):
				return _bad("start has no single funded proposal")
			if int(e.get("pay_event_id", -1)) != int(state.get("pay_event_id", -2)) \
					or int(e.get("due_tick", -1)) != int(e.get("tick", -2)) + 720 \
					or String(e.get("actor", "")) != "town" or String(e.get("target", "")) != "plaza" \
					or not bool(e.get("accepted", false)):
				return _bad("start receipt or due tick is invalid")
			state["status"] = "underway"
			state["start_tick"] = int(e["tick"])
			state["due_tick"] = int(e["due_tick"])
			state["start_event_id"] = int(e.get("id", -1))
			continue
		if kind == "civic_complete" and String(e.get("subject", "")) == PROJECT_ID:
			if state.is_empty() or state["status"] != "underway" or proposal_id != String(state["proposal_id"]):
				return _bad("completion has no underway project")
			if int(e.get("pay_event_id", -1)) != int(state.get("pay_event_id", -2)) \
					or int(e.get("start_event_id", -1)) != int(state.get("start_event_id", -2)) \
					or int(e.get("tick", -1)) < int(state["due_tick"]) \
					or String(e.get("actor", "")) != "town" or String(e.get("target", "")) != "plaza" \
					or not bool(e.get("accepted", false)):
				return _bad("completion receipt or time is invalid")
			state["status"] = "complete"
			state["complete_tick"] = int(e["tick"])
			state["complete_event_id"] = int(e.get("id", -1))
	return {"ok": true, "error": "", "state": state.duplicate(true), "attempts": attempts.duplicate(true)}

## Cross-check proposal snapshots against the existing mayor term authority and
## the town account reconstructed from prior pay events. This is separate from
## Sim's proposal/vote writer and can run on a prepared save before load.
static func authority_error(log: Array, mayor_log: Array, economy: Dictionary) -> String:
	var folded := fold(log)
	if not bool(folded.get("ok", false)):
		return String(folded.get("error", "invalid project events"))
	var attempts: Dictionary = folded.get("attempts", {})
	for proposal_id in attempts:
		var rec: Dictionary = attempts[proposal_id]
		var matches := 0
		var term := {}
		for raw in mayor_log:
			if not (raw is Dictionary):
				return "mayor term record is not a Dictionary"
			var row: Dictionary = raw
			if int(row.get("term_start", -1)) == int(rec["term_start"]):
				matches += 1
				term = row
		if matches != 1 or String(term.get("winner", "")) != String(rec["mayor"]) \
				or int(term.get("term_end", -1)) != int(rec["term_end"]):
			return "proposal has no matching unique elected mayor term"
		var candidates = term.get("candidates", [])
		if not (candidates is Array):
			return "election candidates are not an Array"
		var sorted_candidates := (candidates as Array).duplicate()
		sorted_candidates.sort()
		if sorted_candidates != rec["council"]:
			return "proposal electorate differs from mayor-election finalists"
		var fiscal = economy.get("fiscal", {})
		var base_floor := int((fiscal as Dictionary).get("subsidy_floor", 0)) if fiscal is Dictionary else 0
		var platform = term.get("platform", {})
		var floor_at_term := int((platform as Dictionary).get("subsidy_floor", base_floor)) if platform is Dictionary else base_floor
		if int(rec["reserve_snapshot"]) != maxi(0, floor_at_term):
			return "proposal reserve differs from elected fiscal platform"
		var town_balance := int(economy.get("town_start", 0))
		var found_proposal := false
		for raw_event in log:
			if not (raw_event is Dictionary):
				return "event log contains a non-Dictionary entry"
			var e: Dictionary = raw_event
			if int(e.get("id", -1)) == int(rec["proposal_event_id"]):
				if String(e.get("type", "")) != "civic_proposal" or String(e.get("proposal_id", "")) != String(proposal_id):
					return "proposal event ID points to a different event"
				found_proposal = true
				break
			if String(e.get("type", "")) == "pay":
				var amt := int(e.get("amt", -1))
				if amt <= 0:
					return "pre-proposal payment amount is invalid"
				if String(e.get("actor", "")) == "town": town_balance -= amt
				if String(e.get("target", "")) == "town": town_balance += amt
		if not found_proposal or town_balance != int(rec["treasury_snapshot"]):
			return "proposal treasury snapshot differs from prior payment fold"
	# A mayor review keeps the true treasury change, but its vote scorer adds
	# back only an independently witnessed civic capital payment from that term.
	# Old reviews without this field remain valid when no project was paid.
	for raw_term in mayor_log:
		if not (raw_term is Dictionary):
			return "mayor term record is not a Dictionary"
		var row: Dictionary = raw_term
		if not row.has("review_event_id"):
			continue
		var term_start := int(row.get("term_start", -1))
		var expected_spend := 0
		var txid := "%s:term:%d" % [PROJECT_ID, term_start]
		for raw_event in log:
			if not (raw_event is Dictionary):
				return "event log contains a non-Dictionary entry"
			var payment: Dictionary = raw_event
			if String(payment.get("type", "")) == "pay" \
					and String(payment.get("txid", "")) == txid \
					and String(payment.get("note", "")) == PAY_PREFIX + "5" \
					and String(payment.get("actor", "")) == "town" \
					and String(payment.get("target", "")) == "external":
				expected_spend += int(payment.get("amt", 0))
		if int(row.get("civic_capital_spend", 0)) != expected_spend:
			return "mayor review civic capital spending differs from paid receipts"
		var found_review := false
		for raw_event in log:
			if not (raw_event is Dictionary):
				return "event log contains a non-Dictionary entry"
			var review_event: Dictionary = raw_event
			if int(review_event.get("id", -1)) == int(row["review_event_id"]):
				if String(review_event.get("type", "")) != "mayor_review" \
						or int(review_event.get("term_start", -1)) != term_start \
						or int(review_event.get("civic_capital_spend", 0)) != expected_spend:
					return "mayor review event civic capital spending differs from paid receipts"
				found_review = true
				break
		if not found_review:
			return "mayor review event is missing"
	return ""
