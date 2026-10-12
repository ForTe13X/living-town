extends Node
## LT-10: fresh-load continuation across ordinary actions and pending commitments.

const SimScript = preload("res://scripts/Sim.gd")
const MainScene = preload("res://scenes/Main.tscn")
const Inv = preload("res://bench/Invariants.gd")

var fails := 0

func ck(ok: bool, label: String, detail := "") -> void:
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, " — " + detail if detail != "" else ""])
	if not ok:
		fails += 1

func _new_sim(seed: int):
	var S = SimScript.new()
	add_child(S)
	S.backend = null
	S.auto_run = false
	S.start_new(seed)
	return S

func _state(S) -> Dictionary:
	return {"digest": Inv.digest(S), "event_digest": S.event_digest,
		"trace": S.get_player_trace() if not S.get_agent("player").is_empty() else {}, "controlled_id": S.controlled_id,
		"money_total": S.money_total(), "bank_coin": S.bank_coin,
		"deposits": S.bank_deposits.duplicate(true), "loans": S.bank_loans.duplicate(true)}

func _compare_ticks(A, B, count: int) -> int:
	for index in count:
		A.tick()
		B.tick()
		if _state(A) != _state(B):
			return index
	return -1

func _invariant_ok(S, target_id: int) -> bool:
	for result: Dictionary in Inv.check_all(S, 0):
		if int(result.get("id", -1)) == target_id:
			return bool(result.get("ok", false))
	return false

func _load_peer(A, path: String, label: String):
	ck(A.save_game(path), label + " saves the live continuation")
	var B = _new_sim(5)
	var loaded := B.load_game(path)
	# LifeMode is transient view state, intentionally excluded from the save schema.
	# A surviving UI reattaches its current resident after world_reset; mirror that handoff here.
	if loaded and String(A.controlled_id) != "":
		B.possess(String(A.controlled_id))
	var state_a := _state(A)
	var state_b := _state(B)
	var initial_match := state_a == state_b
	var detail := ""
	if not initial_match:
		detail = "loaded=%s digest=%d/%d event_digest=%d/%d trace=%s controller=%s/%s" % [str(loaded),
			int(state_a.get("digest", -1)), int(state_b.get("digest", -1)), A.event_digest, B.event_digest,
			str(A.get_player_trace() == B.get_player_trace()), String(A.controlled_id), String(B.controlled_id)]
	ck(loaded and initial_match, label + " fresh instance restores state after view rebind", detail)
	if loaded:
		ck(B._agent_by_id.get("ben", {}) == B.get_agent("ben")
			and B._active_commitments.all(func(c): return c in B.commitments),
			label + " rebuilds agent and active-commitment references")
	return B

func _clear_options(S, except_id := "") -> void:
	for agent: Dictionary in S.agents:
		if String(agent.get("id", "")) == except_id:
			continue
		agent["option"] = null
		agent["talking"] = 0

func _free_neighbor(S, obj: Dictionary) -> Vector2i:
	var grid: Dictionary = S._grid_for(String(obj.get("space", "town")), String(obj.get("floor", "outdoor")))
	var pos: Vector2i = obj.get("pos", Vector2i(-99, -99))
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if S._cell_walkable(grid, pos + direction):
			return pos + direction
	return Vector2i(-99, -99)

func _find_seated_meal(S, actor: Dictionary) -> Dictionary:
	for object_id in S.world.get("objects", {}).keys():
		var obj: Dictionary = S.world["objects"][object_id]
		for action: Dictionary in S._life_object_actions(actor, obj):
			if String(action.get("action", "")) != "吃饭" or not bool(action.get("ok", false)):
				continue
			for advert: Dictionary in obj.get("advertises", []):
				if String(advert.get("action", "")) == "吃饭" and bool(advert.get("seated", false)) \
						and int(advert.get("seats", 0)) > 0:
					return {"id": String(object_id), "object": obj, "action": action, "advert": advert}
	return {}

func _walking_roundtrip() -> void:
	var A = _new_sim(20260924)
	A.add_player()
	var player: Dictionary = A.get_agent("player")
	var first := Vector2i.ZERO
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if A._cell_walkable(A._grid_for("town", "outdoor"), player["pos"] + direction):
			first = direction
			break
	A.player_move(first)
	A.tick()
	var B = _load_peer(A, "user://lt10_walking.save", "walking")
	var next_dir := Vector2i.ZERO
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if A._cell_walkable(A._grid_for("town", "outdoor"), A.get_agent("player")["pos"] + direction):
			next_dir = direction
			break
	A.player_move(next_dir)
	B.player_move(next_dir)
	var drift := _compare_ticks(A, B, 24)
	ck(drift == -1, "walking save resumes with identical future input for 24 ticks", "drift_tick=%d" % drift)
	A.free(); B.free()

func _queued_service_roundtrip() -> void:
	var A = _new_sim(20260925)
	A.possess("ben")
	_clear_options(A)
	var actor: Dictionary = A.get_agent("ben")
	var candidate := _find_seated_meal(A, actor)
	if candidate.is_empty():
		ck(false, "queued service fixture finds an authored seated meal")
		A.free()
		return
	var obj: Dictionary = candidate["object"]
	var stand := _free_neighbor(A, obj)
	actor["space"] = String(obj.get("space", "town")); actor["floor"] = String(obj.get("floor", "outdoor"))
	A._move_agent(actor, stand)
	var blockers: Array[String] = []
	for resident: Dictionary in A.agents:
		if String(resident.get("id", "")) == "ben":
			continue
		resident["option"] = {"kind": "object", "target": String(candidate["id"]), "action": "吃饭",
			"need": "hunger", "amount": int(candidate["action"].get("amount", 50)),
			"dur_total": int(candidate["action"].get("duration", 18)), "phase": "use", "remaining": 100}
		blockers.append(String(resident.get("id", "")))
		if blockers.size() >= int(candidate["advert"].get("seats", 1)):
			break
	var started := A.life_use(String(candidate["id"]), "吃饭")
	A.tick()
	var queued: Dictionary = actor.get("option", {})
	ck(started == "" and String(queued.get("phase", "")) == "travel" and queued.has("queued_at"),
		"service save point contains a real queued seat commitment", "option=%s" % str(queued))
	var B = _load_peer(A, "user://lt10_service.save", "queued service")
	for id in blockers:
		A.get_agent(id)["option"] = null; A.get_agent(id)["talking"] = 0
		B.get_agent(id)["option"] = null; B.get_agent(id)["talking"] = 0
	var drift := _compare_ticks(A, B, 80)
	ck(drift == -1 and A.get_agent("ben").get("option") == null,
		"released service queue settles identically after fresh load", "drift_tick=%d events=%d/%d event_digest=%d/%d ben_option=%s/%s" % [drift,
			A.event_log.size(), B.event_log.size(), A.event_digest, B.event_digest,
			str(A.get_agent("ben").get("option")), str(B.get_agent("ben").get("option"))])
	A.free(); B.free()

func _social_roundtrip() -> void:
	var A = _new_sim(20260926)
	A.possess("ben")
	_clear_options(A)
	var ben: Dictionary = A.get_agent("ben")
	var pos: Vector2i = A._area_centroid("plaza")
	ben["space"] = "town"; ben["floor"] = "outdoor"; ben["option"] = null; ben["talking"] = 0
	A._move_agent(ben, pos)
	var aria: Dictionary = A.get_agent("aria")
	aria["space"] = "town"; aria["floor"] = "outdoor"; aria["option"] = null; aria["talking"] = 0
	A._move_agent(aria, pos + Vector2i(1, 0))
	var result := A.life_social("greet", "aria")
	var pending_value: Variant = A.get_agent("ben").get("option")
	var pending: Dictionary = pending_value if pending_value is Dictionary else {}
	ck(result == "" and String(pending.get("kind", "")) == "social"
		and int(A.get_agent("ben").get("talking", 0)) > 0,
		"social save point contains a pending conversation", "result=%s option=%s" % [result, str(pending)])
	var B = _load_peer(A, "user://lt10_social.save", "pending social")
	var drift := _compare_ticks(A, B, 24)
	ck(drift == -1 and A.get_agent("ben").get("option") == null
		and B.get_agent("ben").get("option") == null,
		"pending social action resolves identically after fresh load", "drift_tick=%d events=%d" % [drift, A.event_log.size()])
	A.free(); B.free()

func _bank_roundtrip() -> void:
	var A = _new_sim(20260927)
	A.add_player()
	var receipt: Dictionary = A.player_bank_action("deposit", "player", 2)
	ck(bool(receipt.get("ok", false)), "bank save point follows a committed traced deposit")
	var B = _load_peer(A, "user://lt10_bank.save", "bank transfer")
	var withdrawal_a: Dictionary = A.player_bank_action("withdraw", "player", 1)
	var withdrawal_b: Dictionary = B.player_bank_action("withdraw", "player", 1)
	var drift := _compare_ticks(A, B, 24)
	ck(bool(withdrawal_a.get("ok", false)) and withdrawal_a == withdrawal_b and drift == -1
		and A.get_player_trace() == B.get_player_trace() and _invariant_ok(A, 34)
		and _invariant_ok(A, 35) and _invariant_ok(A, 47),
		"bank balances, obligations and continuation trace match after resume", "drift_tick=%d wallet=%d deposit=%d loan=%s" % [drift,
			A._coin_of("player"), int(A.bank_deposits.get("player", 0)), str(A.bank_loans.get("player", {}))])
	A.free(); B.free()

func _write_corrupt_spatial_copy(source_path: String, corrupt_path: String) -> void:
	var source := FileAccess.open(source_path, FileAccess.READ)
	var schema := source.get_32()
	var blob: Dictionary = source.get_var()
	source.close()
	var state: Dictionary = blob.get("state", {})
	var agents: Array = state.get("agents", [])
	(agents[0] as Dictionary)["space"] = "not_an_authored_space"
	state["agents"] = agents
	blob["state"] = state
	var out := FileAccess.open(corrupt_path, FileAccess.WRITE)
	out.store_32(schema)
	out.store_var(blob)
	out.close()

func _reset_and_corrupt_save_checks() -> void:
	var main: Node = MainScene.instantiate()
	main.set("_player_mode", false)
	add_child(main)
	await get_tree().process_frame
	Sim.backend = AIBackend
	Sim.auto_run = false
	Sim.start_new(20260928)
	var life: Node = main.get("_life")
	life.call("start_life", "ben")
	var save_path := "user://lt10_live_resume.save"
	var corrupt_path := "user://lt10_corrupt_spatial.save"
	ck(Sim.save_game(save_path), "active life-mode authority saves before resident change")
	var original_hash := FileAccess.get_sha256(ProjectSettings.globalize_path(save_path))
	var saved_digest := Inv.digest(Sim)
	var old_epoch := int(AIBackend.world_epoch)
	AIBackend._pending["aria"] = {"epoch": old_epoch, "req_id": 777, "http": null, "slm_chat": null}
	AIBackend._inflight = 1
	Sim.possess("aria")
	var loaded := Sim.load_game(save_path)
	await get_tree().process_frame
	ck(loaded and AIBackend.world_epoch > old_epoch and AIBackend._pending.is_empty()
		and not AIBackend._match("aria", old_epoch, 777),
		"load invalidates an old resident response using the existing AI epoch boundary")
	ck(Sim.controlled_id == "ben" and String(life.get("pid")) == "ben" and bool(life.get("active"))
		and String(Sim.life_status().get("id", "")) == "ben" and Inv.digest(Sim) == saved_digest
		and not bool(Sim.player_trace_status().get("available", true)) and Sim.get_player_trace().is_empty(),
		"life-mode UI returns to the saved resident and rebuilds from loaded authority",
		"controlled=%s pid=%s active=%s status=%s digest=%s trace=%s" % [Sim.controlled_id, String(life.get("pid")),
			str(life.get("active")), String(Sim.life_status().get("id", "")), str(Inv.digest(Sim) == saved_digest),
			str(Sim.player_trace_status())])
	_write_corrupt_spatial_copy(save_path, corrupt_path)
	var before_rejection := Inv.digest(Sim)
	var rejected := not Sim.load_game(corrupt_path)
	ck(rejected and Inv.digest(Sim) == before_rejection
		and FileAccess.get_sha256(ProjectSettings.globalize_path(save_path)) == original_hash,
		"corrupt spatial identity is refused; live world and original save remain intact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))
	main.free()

func _ready() -> void:
	_walking_roundtrip()
	_queued_service_roundtrip()
	_social_roundtrip()
	_bank_roundtrip()
	await _reset_and_corrupt_save_checks()
	print("save_resume_test: %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
