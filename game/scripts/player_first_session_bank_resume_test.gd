extends "res://scripts/player_first_session_test.gd"
## A separate Godot process resumes the F5 save through the game's F8 control.

const Inv = preload("res://bench/Invariants.gd")
const QUICKSAVE := "user://quicksave.dat"

func _run() -> void:
	_pin_settings()
	_scenario_id = "fresh_process_f8_bank_resume"
	_evidence_dir = OS.get_environment("LT_JOURNEY_EVIDENCE_DIR")
	if _evidence_dir.is_empty():
		_evidence_dir = ProjectSettings.globalize_path("user://bank_resume_evidence")
	DirAccess.make_dir_recursive_absolute(_evidence_dir)
	var source_dir := OS.get_environment("LT_JOURNEY_SOURCE_DIR")
	var baseline_path := source_dir.path_join("pre_resume.json")
	var baseline_text := FileAccess.get_file_as_string(baseline_path)
	var baseline_value = JSON.parse_string(baseline_text)
	var baseline: Dictionary = baseline_value if baseline_value is Dictionary else {}
	_check("fresh process receives the first process's saved-state baseline", not baseline.is_empty(), baseline_path)
	if baseline.is_empty():
		_finish()
		return
	_check("fresh process sees the same isolated quicksave bytes",
		FileAccess.file_exists(QUICKSAVE) and FileAccess.get_sha256(ProjectSettings.globalize_path(QUICKSAVE))
			== String(baseline.get("save_sha256", "")), ProjectSettings.globalize_path(QUICKSAVE))
	_main = MAIN_SCENE.instantiate() as Node2D
	add_child(_main)
	await _wait_frames(5)
	_life = _main.get("_life") as Node
	_check("fresh launch opens the normal resident selection", _life != null and bool(_life.get("selecting")))
	if _life == null:
		_finish()
		return
	await _save_checkpoint("01_fresh_process_selection")
	await _send_key(KEY_F8)
	await _send_key(KEY_F8, false)
	await _wait_frames(8)
	pid = String(baseline.get("controlled_id", ""))
	var actor: Dictionary = Sim.get_agent(pid)
	var position: Vector2i = actor.get("pos", Vector2i(-99, -99))
	var expected_position: Array = baseline.get("position", [])
	var same_position := expected_position.size() == 2 and position == Vector2i(int(expected_position[0]), int(expected_position[1]))
	_check("F8 restores the saved resident, location, and tick",
		bool(_life.get("active")) and String(_life.get("pid")) == pid and Sim.controlled_id == pid
		and Sim.tick_no == int(baseline.get("tick", -1)) and same_position
		and String(actor.get("space", "")) == String(baseline.get("space", ""))
		and String(actor.get("floor", "")) == String(baseline.get("floor", "")),
		"controlled=%s pid=%s tick=%d location=%s/%s@%s" % [Sim.controlled_id,
			String(_life.get("pid")), Sim.tick_no, String(actor.get("space", "")),
			String(actor.get("floor", "")), str(position)])
	_check("fresh process restores the canonical saved simulation digest",
		Inv.digest(Sim) == int(baseline.get("digest", -1)),
		"saved=%s loaded=%s" % [str(baseline.get("digest", -1)), str(Inv.digest(Sim))])
	var bank: Dictionary = Sim.bank_projection(pid)
	var saved_bank: Dictionary = baseline.get("bank", {})
	var bank_equal: bool = String(bank.get("account_id", "")) == String(saved_bank.get("account_id", "")) \
		and String(bank.get("label", "")) == String(saved_bank.get("label", "")) \
		and String(bank.get("mode", "")) == String(saved_bank.get("mode", "")) \
		and bank.get("loan", {}) == saved_bank.get("loan", {})
	for field in ["wallet", "deposit", "reserve", "deposit_total", "available_capital"]:
		bank_equal = bank_equal and int(bank.get(field, -1)) == int(saved_bank.get(field, -2))
	_check("fresh process restores the bank balance and public ledger",
		bank_equal, "saved=%s loaded=%s" % [JSON.stringify(saved_bank), JSON.stringify(bank)])
	await _save_checkpoint("02_f8_resumed_bank_interior")
	var counter: Vector2i = Sim.bank_counter_cell()
	await _click_world_cell(counter)
	await _wait_frames(3)
	var panel: Panel = _main.get("_bank_panel") as Panel
	var bank_open := panel != null and panel.visible
	_check("resumed resident can reopen the bank counter card", bank_open)
	if not bank_open:
		_finish()
		return
	var withdraw: Button = panel.get_node_or_null("BankWithdrawButton") as Button
	_check("resumed bank card exposes withdrawal", withdraw != null and not withdraw.disabled)
	if withdraw == null or withdraw.disabled:
		_finish()
		return
	await _click(withdraw)
	await _wait_frames(2)
	var after: Dictionary = Sim.bank_projection(pid)
	_check("resumed resident can withdraw one saved coin through the card",
		int(after.get("wallet", -1)) == int(bank.get("wallet", -1)) + 1
		and int(after.get("deposit", -1)) == int(bank.get("deposit", -1)) - 1
		and int(after.get("reserve", -1)) == int(bank.get("reserve", -1)) - 1,
		"before=%s after=%s feedback=%s" % [JSON.stringify(bank), JSON.stringify(after),
			String(_main.get("_bank_feedback"))])
	await _save_checkpoint("03_fresh_process_withdrawal")
	_finish()
