extends Node
## P4b/P4c governance contract: elections are deterministic and the elected mayor alone can perform weekly town-hall duty.

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
var fails := 0

func ck(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
	print(("  OK   " if ok else "  FAIL ") + message)

func _run(S, ticks: int) -> void:
	for i in range(ticks):
		S.tick()

func _mayor_invariant(S) -> bool:
	for result in Inv.check_all(S, 0):
		if int((result as Dictionary).get("id", -1)) == 37:
			return bool((result as Dictionary).get("ok", false))
	return false

func _ready() -> void:
	var S = SimScript.new(); add_child(S)
	S.backend = null; S.auto_run = false; S.start_new(20260918)
	# The off gate is meaningful: lack of the mayor config cannot leave a stale office behind.
	var authored_elections: Dictionary = S.elections.duplicate(true)
	S.elections = {}
	S.day = 28; S._update_mayor_election()
	ck(S.mayor_log.is_empty() and S.mayor_state.is_empty(), "missing mayor config keeps office closed")

	S.start_new(20260918)
	S.elections = authored_elections
	_run(S, 28 * int(S.TICKS_PER_DAY))
	ck(S.mayor_log.size() == 1 and not S.mayor_state.is_empty(), "day 28 creates the first mayoral term")
	var first: Dictionary = S.mayor_log[0] if not S.mayor_log.is_empty() else {}
	var candidates: Array = first.get("candidates", [])
	var ballots: Dictionary = first.get("ballots", {})
	var votes := 0
	for cid in ballots: votes += int(ballots[cid])
	ck(candidates.size() == 3 and candidates.has(String(first.get("winner", ""))), "winner belongs to the three visible candidates")
	ck(votes == int(first.get("voters", -1)) and int(first.get("voters", -1)) == S.agents.size(), "every resident contributes exactly one ballot")
	ck(int(first.get("term_start", -1)) == 28 and int(first.get("term_end", -1)) == 55 and S.mayor_state.get("mayor", "") == first.get("winner", ""), "state exposes the elected 28-day term")
	ck(_mayor_invariant(S), "governance invariant accepts a real election")

	# A replay from the same seed must reproduce candidate ordering, ballots, winner, and active term byte-for-byte.
	var R = SimScript.new(); add_child(R)
	R.backend = null; R.auto_run = false; R.start_new(20260918)
	_run(R, 28 * int(R.TICKS_PER_DAY))
	ck(R.mayor_log == S.mayor_log and R.mayor_state == S.mayor_state, "same seed reproduces the entire mayoral record")

	# Exercise the duty contract directly after replay comparison: the weekly window remains open while the mayor travels,
	# only the elected mayor may complete it, and completion is idempotent within that duty period.
	S.day = 30
	S.tick_no = 29 * int(S.TICKS_PER_DAY) + int(0.4 * int(S.TICKS_PER_DAY))
	var duty_adv := {"action": "办公", "need": "fun", "amount": 18, "duration": 8, "mayor_duty": true}
	var mayor = null; var other = null
	for ag in S.agents:
		if String(ag.get("id", "")) == String(S.mayor_state.get("mayor", "")):
			mayor = ag
		elif other == null:
			other = ag
	ck(mayor != null and S._adv_open(mayor, duty_adv), "elected mayor can use the town-hall desk before the weekly window closes")
	ck(other != null and not S._adv_open(other, duty_adv), "unelected residents cannot use the mayor desk")
	S._complete_mayor_duty(mayor, duty_adv)
	S._complete_mayor_duty(mayor, duty_adv)
	var perf: Dictionary = S.mayor_performance()
	ck(int(perf.get("duties_done", 0)) == 1 and int(perf.get("duties_due", 0)) == 1, "one completed duty produces one attendance mark")
	ck(int((S.mayor_log[0] as Dictionary).get("duties_done", 0)) == 1, "term history retains completed duty attendance")
	ck(_mayor_invariant(S), "governance invariant accepts an authenticated duty event")

	S.day = 56; S._update_mayor_election()
	ck(S.mayor_log.size() == 2 and int((S.mayor_log[1] as Dictionary).get("term_start", -1)) == 56, "a second term begins on day 56")
	var reviewed: Dictionary = S.mayor_log[0]
	var review_events: Array = S.event_log.filter(func(e): return String(e.get("type", "")) == "mayor_review")
	ck(int(reviewed.get("duties_due", 0)) == 4 and int(reviewed.get("attendance_pct", -1)) == 25, "outgoing term freezes attendance against all four weekly periods")
	ck(int(reviewed.get("town_coin_end", -1)) == S.town_coin and int(reviewed.get("treasury_delta", 1)) == int(reviewed.get("town_coin_end", 0)) - int(reviewed.get("town_coin_start", 0)), "outgoing term freezes its treasury result")
	ck(review_events.size() == 1 and int((review_events[0] as Dictionary).get("id", -2)) == int(reviewed.get("review_event_id", -1)), "one visible review is linked to the finalized term")
	ck(_mayor_invariant(S), "governance invariant accepts consecutive terms")

	print("governance_test: %s (%d fail)" % [("PASS" if fails == 0 else "FAIL"), fails])
	get_tree().quit(1 if fails > 0 else 0)
