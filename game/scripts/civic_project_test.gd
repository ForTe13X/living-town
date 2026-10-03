extends Node
## Directed LT-16/17 lifecycle: a real day-28 election authorizes one conserved
## payment, a fresh load finishes at the same tick, and no duplicate charge lands.
const SimScript = preload("res://scripts/Sim.gd")
const CivicProjectScript = preload("res://scripts/CivicProject.gd")
const CivicPresentation = preload("res://scripts/CivicPresentation.gd")
const LedgerScript = preload("res://scripts/Ledger.gd")
const Inv = preload("res://bench/Invariants.gd")

var failures := 0

func ck(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print(("  OK   " if ok else "  FAIL ") + message)

func _count_kind(log: Array, kind: String) -> int:
	var count := 0
	for e in log:
		if String((e as Dictionary).get("type", "")) == kind \
				and String((e as Dictionary).get("subject", "")) == CivicProjectScript.PROJECT_ID:
			count += 1
	return count

func _pay_events(log: Array) -> Array:
	var out := []
	for e in log:
		if String((e as Dictionary).get("type", "")) == "pay" \
				and String((e as Dictionary).get("note", "")).begins_with("civic_project:"):
			out.append(e)
	return out

func _hard_money_ok(S) -> bool:
	for raw in Inv.check_all(S, 0):
		var result: Dictionary = raw
		if int(result.get("id", -1)) in [34, 35, 37, 45] and not bool(result.get("ok", false)):
			print("  invariant failure: %s" % str(result))
			return false
	return true

func _ready() -> void:
	var expect_off := "--expect-off" in OS.get_cmdline_user_args()
	var S = SimScript.new(); add_child(S)
	S.backend = null; S.auto_run = false; S.start_new(7)
	for i in range(27 * S.TICKS_PER_DAY):
		S.tick()
	print("civic pre-proposal event_digest=%d town=%d external=%d" % [S.event_digest, S.town_coin, S.external_coin])
	S.tick()
	if expect_off:
		ck(not FileAccess.file_exists("res://data/civic_projects.json"), "off fixture has no project config")
		ck(S.civic_project_state().is_empty() and _pay_events(S.event_log).is_empty(),
			"missing project config produces no proposal or payment")
		ck(CivicPresentation.phase(S.civic_project_state()) == "", "missing project stays visually absent")
		ck(S.money_total() == S.econ_total0 and LedgerScript.fold(S.event_log, S.TICKS_PER_DAY).verify(S).is_empty(),
			"missing project config retains conserved baseline accounting")
		S.queue_free()
		print("civic_project_test off: %s (%d fail)" % ["PASS" if failures == 0 else "FAIL", failures])
		get_tree().quit(0 if failures == 0 else 1)
		return
	var planned := S.civic_project_state()
	ck(S.tick_no == 6481 and String(planned.get("status", "")) == "proposed"
		and CivicPresentation.phase(planned) == "planned"
		and CivicPresentation.receipt(planned).contains("尚未动用镇库")
		and _count_kind(S.event_log, "civic_vote") == 0
		and _pay_events(S.event_log).is_empty(),
		"day-28 proposal remains visibly planned and unpaid for one tick")
	var planned_path := "user://civic_project_planned_test.dat"
	ck(S.save_game(planned_path, {"fixture": "civic_planned"}), "open proposal saves")
	var P = SimScript.new(); add_child(P)
	P.backend = null; P.auto_run = false
	ck(P.load_game(planned_path) and P.civic_project_state() == planned
		and CivicPresentation.phase(P.civic_project_state()) == "planned",
		"fresh load restores the planned phase from events")
	S.tick(); P.tick()
	var underway := S.civic_project_state()
	ck(P.civic_project_state() == underway and P.event_digest == S.event_digest,
		"loaded proposal reaches the same council decision and payment")
	P.queue_free()
	ck(CivicPresentation.phase({"id": CivicProjectScript.PROJECT_ID, "proposal_event_id": 1,
		"status": "proposed"}) == "planned"
		and CivicPresentation.phase({"id": CivicProjectScript.PROJECT_ID, "proposal_event_id": 1,
		"decision_event_id": 2, "status": "approved"}) == "planned"
		and CivicPresentation.phase({"id": CivicProjectScript.PROJECT_ID, "proposal_event_id": 1,
		"status": "rejected"}) == "", "planned display exists only for an open proposal or approval")
	ck(CivicPresentation.receipt({"id": CivicProjectScript.PROJECT_ID, "proposal_event_id": 1,
		"decision_event_id": 2, "status": "rejected"}).contains("议事未通过")
		and CivicPresentation.receipt({"id": CivicProjectScript.PROJECT_ID, "proposal_event_id": 1,
		"decision_event_id": 2, "unfunded_event_id": 3, "status": "unfunded"}).contains("拨款未成功")
		and CivicPresentation.receipt({"id": CivicProjectScript.PROJECT_ID, "proposal_event_id": 1,
		"status": "rejected"}) == "", "refusal text requires the decision or failed-funding receipt")
	var plaza_rect: Array = (S.world.get("areas", {}).get("plaza", {}) as Dictionary).get("rect", [])
	ck(plaza_rect.size() == 4 and int(plaza_rect[0]) == 28 and int(plaza_rect[1]) == 21
		and int(plaza_rect[2]) == 8 and int(plaza_rect[3]) == 6,
		"project site matches the generated plaza footprint")
	ck(CivicPresentation.phase(underway) == "underway"
		and CivicPresentation.receipt(underway).contains("施工中"),
		"paid underway authority projects a construction display and receipt")
	var spatial_before := {
		"blockers": S.world.get("blockers", []).duplicate(true),
		"areas": S.world.get("areas", {}).duplicate(true),
		"landmarks": S.world.get("landmarks", []).duplicate(true),
		"portals": S.world.get("portals", []).duplicate(true),
	}
	print("civic state at first post-election tick: %s" % str(underway))
	ck(String(underway.get("status", "")) == "underway" and int(underway.get("cost", -1)) == 5,
		"seed 7 day-28 election approves and starts the authored project")
	ck(int(underway.get("due_tick", -1)) == S.tick_no + 720,
		"construction due tick is three simulation days after payment")
	var payments := _pay_events(S.event_log)
	ck(payments.size() == 1 and int((payments[0] as Dictionary).get("amt", -1)) == 5 \
		and String((payments[0] as Dictionary).get("target", "")) == "external" \
		and String((payments[0] as Dictionary).get("txid", "")) == String(underway.get("proposal_id", "")),
		"one exact town-to-external payment is bound to the proposal")
	ck(S.money_total() == S.econ_total0 and LedgerScript.fold(S.event_log, S.TICKS_PER_DAY).verify(S).is_empty()
		and _hard_money_ok(S), "payment conserves money and passes ledger plus #34/#35/#37/#45")
	var save_path := "user://civic_project_test.dat"
	ck(S.save_game(save_path, {"fixture": "civic_project"}), "underway project saves")
	var read_file := FileAccess.open(save_path, FileAccess.READ)
	var schema := read_file.get_32()
	var forged_blob: Dictionary = read_file.get_var().duplicate(true)
	read_file.close()
	for e in forged_blob["state"]["event_log"]:
		if String((e as Dictionary).get("type", "")) == "pay" \
				and String((e as Dictionary).get("note", "")).begins_with("civic_project:"):
			(e as Dictionary)["target"] = "missing_payee"
			break
	var forged_save_path := "user://civic_project_forged_test.dat"
	var write_file := FileAccess.open(forged_save_path, FileAccess.WRITE)
	write_file.store_32(schema)
	write_file.store_var(forged_blob)
	write_file.close()
	var C = SimScript.new(); add_child(C)
	C.backend = null; C.auto_run = false; C.start_new(11)
	var receiver_before := [C.tick_no, C.town_coin, C.event_log.size()]
	ck(not C.load_game(forged_save_path)
		and [C.tick_no, C.town_coin, C.event_log.size()] == receiver_before,
		"forged payment save is refused without changing the live receiver")
	C.queue_free()
	var B = SimScript.new(); add_child(B)
	B.backend = null; B.auto_run = false
	ck(B.load_game(save_path), "fresh Sim loads the paid project")
	ck(B.civic_project_state() == underway, "load reconstructs the same project state from events")
	ck(CivicPresentation.phase(B.civic_project_state()) == "underway",
		"fresh load projects the same construction phase without a view cache")
	for i in range(720):
		S.tick(); B.tick()
	var completed := S.civic_project_state()
	print("LT18 logic-only completion digest=%d %d %d" % [S.tick_no, Inv.digest(S), S.event_digest])
	ck(CivicPresentation.phase(completed) == "complete"
		and CivicPresentation.receipt(completed).contains("收据"),
		"paid completion projects two public displays and a notice receipt")
	ck(spatial_before == {
		"blockers": S.world.get("blockers", []),
		"areas": S.world.get("areas", {}),
		"landmarks": S.world.get("landmarks", []),
		"portals": S.world.get("portals", []),
	}, "civic completion leaves the authored spatial contract unchanged")
	var false_complete := completed.duplicate(true)
	false_complete.erase("pay_event_id")
	ck(CivicPresentation.phase(false_complete) == "",
		"display refuses a completion with no payment receipt")
	ck(String(completed.get("status", "")) == "complete"
		and int(completed.get("complete_tick", -1)) == int(underway.get("due_tick", -2)),
		"construction completes exactly at its saved due tick")
	ck(B.civic_project_state() == completed and B.event_digest == S.event_digest,
		"fresh-load continuation has matching project state and event digest")
	var complete_digest: int = int(B.event_digest)
	ck(B.goto_tick(6480) and CivicPresentation.phase(B.civic_project_state()) == "",
		"replay before proposal removes the civic display")
	ck(B.goto_tick(6481) and CivicPresentation.phase(B.civic_project_state()) == "planned"
		and _pay_events(B.event_log).is_empty(),
		"replay to the proposal restores the unpaid planned display")
	ck(B.goto_tick(6482) and CivicPresentation.phase(B.civic_project_state()) == "underway",
		"replay to the paid start restores the construction display")
	ck(B.goto_tick(7202) and CivicPresentation.phase(B.civic_project_state()) == "complete"
		and B.civic_project_state() == completed and B.event_digest == complete_digest,
		"replay to completion restores the exact project receipt and event digest")
	for i in range(10):
		S.tick(); B.tick()
	ck(_pay_events(S.event_log).size() == 1 and _pay_events(B.event_log).size() == 1
		and _count_kind(S.event_log, "civic_complete") == 1 and _count_kind(B.event_log, "civic_complete") == 1,
		"continued ticks do not charge or complete the project twice")
	var forged: Array = S.event_log.duplicate(true)
	for e in forged:
		if String((e as Dictionary).get("type", "")) == "pay" \
				and String((e as Dictionary).get("note", "")).begins_with("civic_project:"):
			(e as Dictionary)["target"] = "missing_payee"
			break
	ck(not bool(CivicProjectScript.fold(forged).get("ok", true)),
		"event fold rejects a forged project payment recipient")
	var duplicate_payment: Array = S.event_log.duplicate(true)
	for e in S.event_log:
		if String((e as Dictionary).get("type", "")) == "pay" \
				and String((e as Dictionary).get("note", "")).begins_with("civic_project:"):
			duplicate_payment.append((e as Dictionary).duplicate(true))
			break
	ck(not bool(CivicProjectScript.fold(duplicate_payment).get("ok", true)),
		"event fold rejects a second project charge")
	var duplicate_completion: Array = S.event_log.duplicate(true)
	for e in S.event_log:
		if String((e as Dictionary).get("type", "")) == "civic_complete":
			duplicate_completion.append((e as Dictionary).duplicate(true))
			break
	ck(not bool(CivicProjectScript.fold(duplicate_completion).get("ok", true)),
		"event fold rejects duplicate completion")
	var changed_vote: Array = S.event_log.duplicate(true)
	for e in changed_vote:
		if String((e as Dictionary).get("type", "")) == "civic_vote":
			(e as Dictionary)["note"] = "no"
			break
	ck(not bool(CivicProjectScript.fold(changed_vote).get("ok", true)),
		"event fold independently rejects a forged ballot")
	var stale_vote_tick: Array = S.event_log.duplicate(true)
	for e in stale_vote_tick:
		if String((e as Dictionary).get("type", "")) == "civic_vote":
			(e as Dictionary)["tick"] = int((e as Dictionary)["tick"]) + 1
			break
	ck(not bool(CivicProjectScript.fold(stale_vote_tick).get("ok", true)),
		"event fold rejects a late or split council vote")
	var legacy_ballots: Array = S.event_log.duplicate(true)
	for e in legacy_ballots:
		if String((e as Dictionary).get("type", "")) in ["civic_vote", "civic_decision"]:
			(e as Dictionary)["tick"] = int(planned["proposal_tick"])
	ck(bool(CivicProjectScript.fold(legacy_ballots).get("ok", false)),
		"event fold still accepts prior same-tick council ballots")
	var changed_treasury: Array = S.event_log.duplicate(true)
	for e in changed_treasury:
		if String((e as Dictionary).get("type", "")) == "civic_proposal":
			(e as Dictionary)["treasury_snapshot"] = int((e as Dictionary)["treasury_snapshot"]) + 1
			break
	ck(CivicProjectScript.authority_error(changed_treasury, S.mayor_log, S.economy) != "",
		"independent treasury fold rejects a forged proposal snapshot")
	ck(_hard_money_ok(S) and LedgerScript.fold(S.event_log, S.TICKS_PER_DAY).verify(S).is_empty(),
		"completed project still satisfies independent money checks")
	while S.tick_no < 55 * S.TICKS_PER_DAY + 1:
		S.tick()
	ck(String(S.civic_project_state().get("status", "")) == "complete" and _pay_events(S.event_log).size() == 1,
		"term rollover cannot reapprove or recharge a completed project")
	ck(_hard_money_ok(S) and LedgerScript.fold(S.event_log, S.TICKS_PER_DAY).verify(S).is_empty(),
		"project and mayor-term rollover retain governance and money invariants")
	var outgoing_review: Dictionary = S.mayor_log[0]
	var raw_delta := int(outgoing_review.get("treasury_delta", 0))
	ck(int(outgoing_review.get("civic_capital_spend", -1)) == 5 \
		and raw_delta == int(outgoing_review.get("town_coin_end", 0)) - int(outgoing_review.get("town_coin_start", 0)),
		"mayor review preserves raw treasury change and identifies the one civic capital payment")
	var sample_review := {"attendance_pct": 50, "treasury_delta": -10, "civic_capital_spend": 5}
	var sample_voter := {"id": "civic_fiscal_preview", "persona": {"traits": ["务实"]}, "relationships": {}}
	var neutralized: Dictionary = S.mayor_review_score(sample_voter, sample_review)
	sample_review["civic_capital_spend"] = 0
	var unadjusted: Dictionary = S.mayor_review_score(sample_voter, sample_review)
	ck(int(neutralized.get("treasury", 99)) > int(unadjusted.get("treasury", 99)),
		"civic capital payment is excluded from fiscal ballot score below the saturation cap")
	var forged_review_log: Array = S.event_log.duplicate(true)
	for e in forged_review_log:
		if String((e as Dictionary).get("type", "")) == "mayor_review":
			(e as Dictionary)["civic_capital_spend"] = 50
			break
	ck(CivicProjectScript.authority_error(forged_review_log, S.mayor_log, S.economy) != "",
		"independent authority check rejects forged civic spending in a mayor review")
	var reviewed_save_path := "user://civic_project_review_test.dat"
	ck(S.save_game(reviewed_save_path, {"fixture": "civic_review"}), "reviewed project saves")
	var review_file := FileAccess.open(reviewed_save_path, FileAccess.READ)
	var review_schema := review_file.get_32()
	var forged_review_blob: Dictionary = review_file.get_var().duplicate(true)
	review_file.close()
	(forged_review_blob["state"]["mayor_log"][0] as Dictionary)["civic_capital_spend"] = 50
	var forged_review_path := "user://civic_project_forged_review_test.dat"
	var forged_review_file := FileAccess.open(forged_review_path, FileAccess.WRITE)
	forged_review_file.store_32(review_schema)
	forged_review_file.store_var(forged_review_blob)
	forged_review_file.close()
	var receiver_review_before := [B.tick_no, B.town_coin, B.event_log.size()]
	ck(not B.load_game(forged_review_path)
		and [B.tick_no, B.town_coin, B.event_log.size()] == receiver_review_before,
		"forged mayor review save is refused without changing the live receiver")
	var R = SimScript.new(); add_child(R)
	R.backend = null; R.auto_run = false; R.start_new(1)
	for i in range(27 * R.TICKS_PER_DAY + 2):
		R.tick()
	var rejected := R.civic_project_state()
	ck(String(rejected.get("status", "")) == "rejected" and _pay_events(R.event_log).is_empty(),
		"seed 1 records a rejected three-member vote without payment")
	while R.tick_no < 55 * R.TICKS_PER_DAY + 1:
		R.tick()
	var attempts: Dictionary = CivicProjectScript.fold(R.event_log).get("attempts", {})
	ck(attempts.has("hydrangea_square_planters_v1:term:28")
		and attempts.has("hydrangea_square_planters_v1:term:56") and attempts.size() == 2
		and _pay_events(R.event_log).size() <= 1,
		"a rejected term may open one distinct later-term proposal without duplicate payment")
	var U = SimScript.new(); add_child(U)
	U.backend = null; U.auto_run = false; U.start_new(7)
	for i in range(27 * U.TICKS_PER_DAY + 1):
		U.tick()
	var open: Dictionary = U.civic_project_state()
	var drain: int = int(U.town_coin) - int(open.get("reserve_snapshot", 0)) - int(open.get("cost", 0)) + 1
	ck(String(open.get("status", "")) == "proposed" and drain > 0
		and U.transfer("town", "external", drain, "civic_fixture_post_proposal_expense"),
		"independent conserved expense can make an open proposal unaffordable")
	U.tick()
	var unfunded: Dictionary = U.civic_project_state()
	ck(String(unfunded.get("status", "")) == "unfunded"
		and CivicPresentation.phase(unfunded) == ""
		and CivicPresentation.receipt(unfunded).contains("拨款未成功")
		and _pay_events(U.event_log).is_empty(),
		"post-proposal treasury decline refuses project payment and explains the refusal")
	ck(U.money_total() == U.econ_total0 and LedgerScript.fold(U.event_log, U.TICKS_PER_DAY).verify(U).is_empty()
		and CivicProjectScript.authority_error(U.event_log, U.mayor_log, U.economy) == "",
		"unfunded branch retains conserved money and independent project authority")
	var unfunded_path := "user://civic_project_unfunded_test.dat"
	ck(U.save_game(unfunded_path, {"fixture": "civic_unfunded"}), "unfunded refusal saves")
	var V = SimScript.new(); add_child(V)
	V.backend = null; V.auto_run = false
	ck(V.load_game(unfunded_path) and V.civic_project_state() == unfunded
		and _pay_events(V.event_log).is_empty(),
		"fresh load retains the unfunded refusal without a project charge")
	var M = SimScript.new(); add_child(M)
	M.backend = null; M.auto_run = false; M.start_new(7)
	for i in range(27 * M.TICKS_PER_DAY + 2):
		M.tick()
	var original: Dictionary = M.civic_project_state()
	var replacement := ""
	for member in original.get("council", []):
		if String(member) != String(original.get("mayor", "")):
			replacement = String(member)
			break
	ck(String(original.get("status", "")) == "underway" and replacement != "",
		"hostile mayor-replacement fixture begins from a legitimately paid project")
	M.mayor_state["mayor"] = replacement
	for i in range(720):
		M.tick()
	var after_replacement: Dictionary = M.civic_project_state()
	ck(String(after_replacement.get("status", "")) == "complete"
		and String(after_replacement.get("proposal_id", "")) == String(original.get("proposal_id", ""))
		and int(after_replacement.get("pay_event_id", -1)) == int(original.get("pay_event_id", -2))
		and _pay_events(M.event_log).size() == 1
		and _count_kind(M.event_log, "civic_vote") == 3
		and _count_kind(M.event_log, "civic_complete") == 1,
		"changing the office holder mid-construction cannot revote, recharge, or cancel the paid project")
	S.queue_free(); B.queue_free(); R.queue_free(); U.queue_free(); V.queue_free(); M.queue_free()
	print("civic_project_test: %s (%d fail)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
