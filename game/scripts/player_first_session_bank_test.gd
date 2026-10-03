extends "res://scripts/player_first_session_test.gd"
## Supplemental consumer journey: follow the ordinary first-session capture,
## then enter the halles, use its bank counter, and save through F5.

const Inv = preload("res://bench/Invariants.gd")
const QUICKSAVE := "user://quicksave.dat"

func _post_service_leg() -> void:
	_scenario_id = "first_session_cafe_social_bank_save"
	var reached_town := await _traverse_to_town()
	_check("resident exits the cafe through ordinary portal controls", reached_town)
	if not reached_town:
		return
	await _save_checkpoint("09_return_to_town")
	var actor: Dictionary = Sim.get_agent(pid)
	var hop: Dictionary = Sim._route_next_hop(String(actor.get("space", "")),
		String(actor.get("floor", "")), "halles", "1f", actor)
	_check("halles bank appears in authored town routes", not hop.is_empty(), str(hop))
	if hop.is_empty():
		return
	var door: Vector2i = hop["from_pos"]
	var stand := _nearest_walkable_stand_pos(door)
	var reached_stand := stand.x >= 0 and await _walk_by_controls(stand, 160)
	_check("movement keys reach the halles entrance", reached_stand,
		"stand=%s actor=%s portal=%s" % [str(stand), str(Sim.get_agent(pid).get("pos")), str(door)])
	if not reached_stand:
		return
	await _click_world_cell(door)
	var enter := _button_containing("走进去") if bool(_life.get("_modal_open")) else null
	_check("halles entrance offers its real entry option", enter != null)
	if enter == null:
		return
	await _click(enter)
	await _wait_frames(5)
	var in_halles := String(Sim.get_agent(pid).get("space", "")) == "halles" \
		and String(Sim.get_agent(pid).get("floor", "")) == "1f"
	_check("portal enters the halles bank interior", in_halles,
		"space=%s floor=%s" % [String(Sim.get_agent(pid).get("space", "")),
			String(Sim.get_agent(pid).get("floor", ""))])
	if not in_halles:
		return
	await _save_checkpoint("10_bank_arrival")
	var counter: Vector2i = Sim.bank_counter_cell()
	_check("bank counter is authored inside the halles", counter.x >= 0, str(counter))
	if counter.x < 0:
		return
	var counter_stand := _nearest_walkable_stand_pos(counter)
	var reached_counter := counter_stand.x >= 0 and await _walk_by_controls(counter_stand, 120)
	_check("movement keys reach a visible bank counter stand", reached_counter,
		"stand=%s actor=%s counter=%s" % [str(counter_stand), str(Sim.get_agent(pid).get("pos")), str(counter)])
	if not reached_counter:
		return
	await _click_world_cell(counter)
	await _wait_frames(3)
	var panel: Panel = _main.get("_bank_panel") as Panel
	var bank_open := panel != null and panel.visible
	_check("clicking the bank counter opens its account card", bank_open)
	var before: Dictionary = Sim.bank_projection(pid)
	var after: Dictionary = Sim.bank_projection(pid)
	var deposit_ok := false
	if bank_open:
		_check("resident has at least one coin to deposit", int(before.get("wallet", 0)) >= 1, JSON.stringify(before))
		await _save_checkpoint("11_bank_account_before_deposit")
		var deposit: Button = panel.get_node_or_null("BankDepositButton") as Button
		_check("bank account card exposes a deposit control", deposit != null and not deposit.disabled)
		if deposit != null and not deposit.disabled and int(before.get("wallet", 0)) >= 1:
			await _click(deposit)
			await _wait_frames(2)
			after = Sim.bank_projection(pid)
			var feedback := String(_main.get("_bank_feedback"))
			deposit_ok = int(after.get("wallet", -1)) == int(before.get("wallet", -1)) - 1 \
				and int(after.get("deposit", -1)) == int(before.get("deposit", -1)) + 1 \
				and int(after.get("reserve", -1)) == int(before.get("reserve", -1)) + 1 \
				and int(after.get("deposit_total", -1)) == int(before.get("deposit_total", -1)) + 1
			_check("deposit button moves one coin into the account and cash reserve", deposit_ok,
				"before=%s after=%s feedback=%s" % [JSON.stringify(before), JSON.stringify(after), feedback])
			_check("bank card reports the committed transaction", feedback == "交易已记入账簿", feedback)
			await _save_checkpoint("12_bank_deposit_receipt")
		await _send_key(KEY_ESCAPE)
		await _send_key(KEY_ESCAPE, false)
		_check("Escape closes the bank account card", not panel.visible)
	else:
		await _save_checkpoint("11_bank_counter_unresponsive")
	await _send_key(KEY_0)
	await _send_key(KEY_0, false)
	_check("ordinary pause control freezes the save point", not Sim.running)
	await _send_key(KEY_F5)
	await _send_key(KEY_F5, false)
	var save_absolute := ProjectSettings.globalize_path(QUICKSAVE)
	var saved := FileAccess.file_exists(QUICKSAVE)
	_check("F5 writes a quicksave in the isolated test profile", saved, save_absolute)
	if not saved:
		return
	var position: Vector2i = Sim.get_agent(pid).get("pos", Vector2i(-99, -99))
	var baseline := {
		"schema": "living-town.bank-first-session-save/1",
		"controlled_id": pid, "tick": Sim.tick_no, "day": Sim.day,
		"position": [position.x, position.y],
		"space": String(Sim.get_agent(pid).get("space", "")),
		"floor": String(Sim.get_agent(pid).get("floor", "")),
		"digest": Inv.digest(Sim), "bank": after, "bank_deposit_succeeded": deposit_ok,
		"save_sha256": FileAccess.get_sha256(save_absolute),
		"save_path": save_absolute,
	}
	var file := FileAccess.open(_evidence_dir.path_join("pre_resume.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(baseline, "  "))
		file.close()
	_check("first process records a verifiable saved-state baseline", file != null)
	await _save_checkpoint("13_paused_after_save")
