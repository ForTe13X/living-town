extends Node
## P5a bank contract: conservation, full reserves, authenticated receipts and defensive UI projection.

const SimScript = preload("res://scripts/Sim.gd")
const MainScene = preload("res://scenes/Main.tscn")
const Inv = preload("res://bench/Invariants.gd")
var fails := 0

func ck(ok: bool, message: String, detail := "") -> void:
	if not ok: fails += 1
	print(("  OK   " if ok else "  FAIL ") + message + (" — " + detail if detail != "" else ""))

func bank_invariant(S) -> bool:
	for result in Inv.check_all(S, 0):
		if int((result as Dictionary).get("id", -1)) == 47:
			return bool((result as Dictionary).get("ok", false))
	return false

func banking_invariants(S) -> Dictionary:
	var seen := {}
	for result: Dictionary in Inv.check_all(S, 0):
		var id := int(result.get("id", -1))
		if id in [34, 35, 47]:
			seen[id] = bool(result.get("ok", false))
	return seen

func _find_named_button(root: Node, target_name: String) -> Button:
	if root is Button and String(root.name) == target_name:
		return root as Button
	for child: Node in root.get_children():
		var found := _find_named_button(child, target_name)
		if found != null:
			return found
	return null

func _click_button(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.global_position = point
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	up.global_position = point
	up.pressed = false
	up.button_mask = 0
	get_viewport().push_input(up, true)
	await get_tree().process_frame

func _bank_replay_state(S) -> Dictionary:
	var loan: Dictionary = S.bank_loans.get("player", {})
	return {"money_total": S.money_total(), "wallet": S._coin_of("player"),
		"bank_coin": S.bank_coin, "deposit": int(S.bank_deposits.get("player", 0)),
		"loan": loan.duplicate(true), "event_digest": S.event_digest,
		"events": S.event_log.duplicate(true)}

func _run_bank_refusal_contracts() -> void:
	var S = SimScript.new(); add_child(S)
	S.backend = null; S.auto_run = false; S.start_new(20260923)
	var start_total: int = S.money_total()
	var start_wallet: int = S._coin_of("aria")
	var start_reserve: int = int(S.bank_coin)
	var start_deposit: int = int(S.bank_deposits.get("aria", 0))
	var invalid_amounts_rejected := not S.bank_deposit("aria", 0) and not S.bank_deposit("aria", -1) \
		and not S.bank_withdraw("aria", 0) and not S.bank_withdraw("aria", -1)
	ck(invalid_amounts_rejected and S.money_total() == start_total
		and S._coin_of("aria") == start_wallet and S.bank_coin == start_reserve
		and int(S.bank_deposits.get("aria", 0)) == start_deposit,
		"zero and negative direct bank requests leave balances unchanged")
	var excess_accepted := S.bank_deposit("aria", 999)
	ck(not excess_accepted and int(S.bank_deposits.get("aria", 0)) == start_deposit
		and S._coin_of("aria") == start_wallet and S.bank_coin == start_reserve
		and S.money_total() == start_total and bank_invariant(S),
		"excess deposit request is refused without corrupting invariant #47")
	var loan_config: Dictionary = S.banking.get("loan", {})
	loan_config["principal"] = S.bank_available_capital() + 1
	S.banking["loan"] = loan_config
	var before_exhausted_loan := _bank_replay_state(S)
	ck(not S.bank_request_loan("aria") and _bank_replay_state(S) == before_exhausted_loan
		and bank_invariant(S),
		"loan beyond available cooperative capital is refused without balance changes")
	S.queue_free()

func _run_bank_ui_trace() -> void:
	var main: Node = MainScene.instantiate()
	main.set("_player_mode", false)
	add_child(main)
	await get_tree().process_frame
	# Main defaults to the resident-selection modal when launched without user
	# arguments. This bank fixture opens the finance card directly, so clear that
	# unrelated first-session overlay before dispatching clicks to the real buttons.
	var life_layer: Node = main.get("_life")
	if life_layer != null:
		life_layer.queue_free()
		await get_tree().process_frame
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(20260921)
	Sim.possess("aria")
	Sim.running = false
	main.call("_open_bank_panel")
	await get_tree().process_frame
	var deposit_button := _find_named_button(main, "BankDepositButton")
	var withdraw_button := _find_named_button(main, "BankWithdrawButton")
	var loan_button := _find_named_button(main, "BankLoanButton")
	ck(deposit_button != null and withdraw_button != null and loan_button != null,
		"bank view builds the three named transaction controls")
	if deposit_button == null or withdraw_button == null or loan_button == null:
		return
	var opened_account := String(main.get("_bank_account_at_open"))
	var aria_wallet_before := Sim._coin_of("aria")
	var spawned := Sim.add_player()
	var start_wallet := Sim._coin_of("player")
	var conserved_total := Sim.money_total()
	var event_count := Sim.event_log.size()
	await _click_button(deposit_button)
	var stale_trace: Dictionary = Sim.get_player_trace()
	var stale_entry: Dictionary = stale_trace["entries"][-1]
	ck(opened_account == "aria" and not spawned.is_empty() and String(stale_entry.get("kind", "")) == "bank_action"
		and String(stale_entry.get("payload", {}).get("account_id", "")) == "aria"
		and String(stale_entry.get("receipt", {}).get("result", {}).get("reason", "")) == "resident_changed"
		and Sim._coin_of("aria") == aria_wallet_before and int(Sim.bank_deposits.get("aria", 0)) == 0
		and Sim.event_log.size() == event_count,
		"resident change invalidates the panel's stale account without transferring funds",
		"opened=%s spawned=%s entry=%s aria_wallet=%d/%d events=%d/%d feedback=%s point=%s rect=%s visible=%s" % [
			opened_account, str(not spawned.is_empty()), str(stale_entry), Sim._coin_of("aria"), aria_wallet_before,
			Sim.event_log.size(), event_count, String(main.get("_bank_feedback")), str(deposit_button.get_global_rect().get_center()),
			str(deposit_button.get_global_rect()), str(deposit_button.is_visible_in_tree())])
	ck(String(main.get("_bank_feedback")).contains("账户已变化"), "stale bank confirmation explains why it was refused",
		String(main.get("_bank_feedback")))
	main.call("_close_bank_panel")
	main.call("_open_bank_panel")
	await get_tree().process_frame
	var player_account := String(main.get("_bank_account_at_open"))
	await _click_button(deposit_button)
	await _click_button(deposit_button)
	await _click_button(withdraw_button)
	await _click_button(loan_button)
	var wallet_after := Sim._coin_of("player")
	var player_loan: Dictionary = Sim.bank_loans.get("player", {})
	var trace: Dictionary = Sim.get_player_trace()
	var invariant_results := banking_invariants(Sim)
	var deposit_entries: Array[Dictionary] = []
	var bank_action_count := 0
	for raw: Dictionary in trace.get("entries", []):
		if String(raw.get("kind", "")) != "bank_action":
			continue
		bank_action_count += 1
		var payload: Dictionary = raw.get("payload", {})
		var result: Dictionary = raw.get("receipt", {}).get("result", {})
		if String(payload.get("action", "")) == "deposit" and bool(result.get("ok", false)):
			deposit_entries.append(raw)
	var duplicate := trace.duplicate(true)
	var duplicate_entries: Array = duplicate.get("entries", [])
	if not deposit_entries.is_empty():
		var repeated: Dictionary = deposit_entries[0].duplicate(true)
		duplicate_entries.insert(int(repeated.get("seq", 0)) + 1, repeated)
		duplicate["next_seq"] = duplicate_entries.size()
	var state_before_replay := _bank_replay_state(Sim)
	ck(player_account == "player" and bank_action_count == 5 and deposit_entries.size() == 2
		and int(deposit_entries[0].get("seq", -1)) != int(deposit_entries[1].get("seq", -1))
		and int(deposit_entries[0].get("order", -1)) + 1 == int(deposit_entries[1].get("order", -1)),
		"two equal deposit clicks are distinct ordered bank commands", "account=%s bank_actions=%d deposit_seq=%s" % [player_account, bank_action_count,
			str(deposit_entries.map(func(entry: Dictionary) -> int: return int(entry.get("seq", -1))))])
	ck(wallet_after == start_wallet - 1 + 6 and int(Sim.bank_deposits.get("player", 0)) == 1
		and int(player_loan.get("outstanding", 0)) == 6 and Sim.money_total() == conserved_total
		and Sim.bank_coin >= Sim.bank_deposit_total() and invariant_results == {34: true, 35: true, 47: true},
		"actual bank buttons commit deposit, withdrawal and loan with conserved totals",
		"wallet=%d start=%d deposits=%d loan_outstanding=%d total=%d/%d invariants=%s" % [wallet_after, start_wallet,
			int(Sim.bank_deposits.get("player", 0)), int(player_loan.get("outstanding", 0)), Sim.money_total(), conserved_total, str(invariant_results)])
	ck(not Sim.set_player_trace_for_replay(duplicate) and _bank_replay_state(Sim) == state_before_replay,
		"redelivery of one trace identity is rejected without a second transfer")
	ck(Sim.goto_tick(0) and _bank_replay_state(Sim) == state_before_replay,
		"tick/order replay reproduces every bank balance, obligation and event")

func _run_legacy_trace_upgrade() -> void:
	var old_sim = SimScript.new()
	add_child(old_sim)
	old_sim.backend = null
	old_sim.auto_run = false
	old_sim.start_new(20260922)
	old_sim.add_player()
	var legacy: Dictionary = old_sim.get_player_trace()
	legacy["version"] = Sim.PLAYER_TRACE_LEGACY_VERSION
	var first: Dictionary = (legacy.get("entries", []) as Array)[0].duplicate(true)
	first["version"] = Sim.PLAYER_TRACE_LEGACY_VERSION
	first.erase("seal")
	first["seal"] = old_sim._player_trace_entry_seal(first)
	legacy["entries"] = [first]
	legacy["next_seq"] = 1
	ck(old_sim.set_player_trace_for_replay(legacy), "legacy V1 player history remains importable")
	var old_save := "user://banking_legacy_trace.save"
	ck(old_sim.save_game(old_save), "legacy V1 history saves in the existing save envelope")
	var loaded = SimScript.new(); add_child(loaded); loaded.backend = null; loaded.auto_run = false
	var load_ok := loaded.load_game(old_save)
	var upgraded: Dictionary = loaded.get_player_trace()
	ck(load_ok and int(upgraded.get("version", -1)) == Sim.PLAYER_TRACE_VERSION
		and loaded._player_trace_validate(upgraded) == "",
		"loading V1 upgrades entry seals to V2 without losing history")
	ck(loaded.goto_tick(0) and not loaded.get_agent("player").is_empty(),
		"upgraded legacy spawn trace still replays")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_save))
	old_sim.queue_free(); loaded.queue_free()

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
	await _run_bank_refusal_contracts()
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
	await _run_bank_ui_trace()
	await _run_legacy_trace_upgrade()
	print("banking_test: %s (%d fail)" % [("PASS" if fails == 0 else "FAIL"), fails])
	get_tree().quit(1 if fails > 0 else 0)
