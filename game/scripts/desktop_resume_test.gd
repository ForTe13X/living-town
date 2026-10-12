extends "res://scripts/player_journey_test.gd"
## Two separate exported processes share only ordinary user:// save files.

const Inv = preload("res://bench/Invariants.gd")
const EXPECTED := "user://desktop_resume_expected.json"

func _signature() -> Dictionary:
	var id := String(_life.get("pid"))
	var actor := Sim.get_agent(id)
	return {"digest": str(Inv.digest(Sim)), "event_digest": str(Sim.event_digest),
		"tick": str(Sim.tick_no), "resident": id, "wallet": str(Sim._coin_of(id)),
		"position": str(actor.get("pos", Vector2i.ZERO)), "controlled": Sim.controlled_id}

func _run() -> void:
	_pin_settings()
	_main = MAIN_SCENE.instantiate() as Node2D
	add_child(_main)
	await _wait_frames(5)
	_life = _main.get("_life") as Node
	_check("fresh process opens resident selection", _life != null and bool(_life.get("selecting")))
	if _life == null:
		_finish()
		return
	var args := OS.get_cmdline_user_args()
	var mode := args[args.find("--desktop-check") + 1]
	var card: Control = (_life.get("_sel_cards") as Array)[1 if mode == "resume-write" else 0]
	await _click(card)
	await _send_key(KEY_ENTER)
	await _wait_frames(3)
	Sim.running = false
	if mode == "resume-write":
		var before := _signature()
		await _send_key(KEY_F5)
		await _wait_frames(2)
		_check("F5 creates the ordinary quicksave", FileAccess.file_exists("user://quicksave.dat"))
		_check("saving leaves authority unchanged", _signature() == before)
		var f := FileAccess.open(EXPECTED, FileAccess.WRITE)
		_check("expected signature is writable", f != null)
		if f != null:
			f.store_string(JSON.stringify(before))
			f.close()
	elif mode == "save-denied":
		var before := _signature()
		var saved_hash := FileAccess.get_sha256("user://quicksave.dat")
		_check("prior valid save is readable", not saved_hash.is_empty())
		await _send_key(KEY_F5)
		await _wait_frames(2)
		_check("F5 explains the denied write", str(_main.get("_log_recent")).contains("存档失败"))
		_check("denied save leaves live authority unchanged", _signature() == before)
		_check("denied save preserves previous bytes", FileAccess.get_sha256("user://quicksave.dat") == saved_hash)
	else:
		var expected = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		_check("prior process left a signature", expected is Dictionary)
		_check("new process starts with a different resident", expected is Dictionary and _signature().get("resident") != expected.get("resident"))
		await _send_key(KEY_F8)
		await _wait_frames(2)
		_check("F8 restores prior process authority and resident", expected is Dictionary and _signature() == expected,
			JSON.stringify(_signature()))
	_restore_settings()
	print("desktop_resume_test: %s (%d fail) mode=%s" % ["PASS" if _fails == 0 else "FAIL", _fails, mode])
	get_tree().quit(0 if _fails == 0 else 1)
