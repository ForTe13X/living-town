extends Node
## P5a bank contract: conservation, full reserves, authenticated receipts and defensive UI projection.

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
var fails := 0

func ck(ok: bool, message: String) -> void:
	if not ok: fails += 1
	print(("  OK   " if ok else "  FAIL ") + message)

func bank_invariant(S) -> bool:
	for result in Inv.check_all(S, 0):
		if int((result as Dictionary).get("id", -1)) == 47:
			return bool((result as Dictionary).get("ok", false))
	return false

func _ready() -> void:
	var S = SimScript.new(); add_child(S)
	S.backend = null; S.auto_run = false; S.start_new(20260919)
	ck(S.bank_coin == 24 and S.money_total() == S.econ_total0, "opening cooperative capital enters the conserved money set")
	ck(S.bank_counter_cell() == Vector2i(7, 2), "bank interaction anchor comes from authored interior data")
	var before_total := S.money_total(); var aria_before := S._coin_of("aria")
	ck(S.bank_deposit("aria", 2), "resident can deposit wallet coin")
	ck(S._coin_of("aria") == aria_before - 2 and int(S.bank_deposits.get("aria", 0)) == 2 and S.bank_coin == 26, "deposit moves one conserved balance and creates one liability")
	ck(S.bank_withdraw("aria", 1), "resident can withdraw an owned deposit")
	ck(S.money_total() == before_total and int(S.bank_deposits.get("aria", 0)) == 1, "deposit round trip preserves money exactly")
	ck(S.bank_request_loan("aria"), "configured business owner can receive one startup loan")
	ck(int((S.bank_loans.get("aria", {}) as Dictionary).get("outstanding", 0)) == 6 and S.bank_available_capital() >= 0, "loan uses only capital above full reserves")
	ck(not S.bank_request_loan("aria"), "second concurrent loan is refused")
	ck(S._bank_repay("aria") and int((S.bank_loans["aria"] as Dictionary).get("outstanding", 0)) == 5, "repayment reduces the authenticated receivable")
	ck(S.money_total() == before_total and bank_invariant(S), "bank flow preserves money and passes invariant #47")
	var p: Dictionary = S.bank_projection("aria"); (p["loan"] as Dictionary)["outstanding"] = 999; p["deposit"] = 999
	ck(int((S.bank_loans["aria"] as Dictionary).get("outstanding", 0)) == 5 and int(S.bank_deposits["aria"]) == 1, "HUD projection is a defensive copy")
	var save_path := "user://banking_test.save"
	ck(S.save_game(save_path), "bank state writes through the canonical save envelope")
	var L = SimScript.new(); add_child(L); L.backend = null; L.auto_run = false
	ck(L.load_game(save_path) and L.bank_coin == S.bank_coin and L.bank_deposits == S.bank_deposits \
		and L.bank_loans == S.bank_loans and bank_invariant(L), "bank cash, liabilities and receivables survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path)); L.queue_free()
	S.bank_deposits["aria"] = 999
	ck(not bank_invariant(S), "forged deposit liability turns invariant #47 red")
	print("banking_test: %s (%d fail)" % [("PASS" if fails == 0 else "FAIL"), fails])
	get_tree().quit(1 if fails > 0 else 0)
