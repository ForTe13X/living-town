extends Node
## PlayerTraceV1 focused contract: public inputs are authority; receipts are
## recomputed witnesses; replay never calls private Sim methods or live AI.
const Inv = preload("res://bench/Invariants.gd")

var fails := 0

func _ck(label: String, ok: bool, detail := "") -> void:
	print("  %s  %s%s" % [("OK" if ok else "FAIL"), label, (" — " + detail if detail != "" else "")])
	if not ok: fails += 1

func _tickn(n: int) -> void:
	for _i in range(n): Sim.tick()

func _player_state() -> Dictionary:
	var pl: Dictionary = Sim.get_agent("player")
	return {"tick": Sim.tick_no, "digest": Inv.digest(Sim), "event_digest": Sim.event_digest,
		"events": Sim.event_log.duplicate(true), "capability": Sim.cafe_guest_capability.duplicate(true), "player": {
			"pos": pl.get("pos", Vector2i.ZERO), "space": pl.get("space", ""), "floor": pl.get("floor", ""),
			"inventory": (pl.get("inventory", {}) as Dictionary).duplicate(true),
			"relationships": (pl.get("relationships", {}) as Dictionary).duplicate(true),
			"memory": (pl.get("memory").items as Array).duplicate(true) if pl.get("memory") != null else []}}

func _trace_canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "true" if value else "false"
		TYPE_INT: return "i:%d" % int(value)
		TYPE_FLOAT: return "f:%.9f" % float(value)
		TYPE_STRING, TYPE_STRING_NAME: return "s:%s" % JSON.stringify(String(value))
		TYPE_VECTOR2I: return "v2i:%d,%d" % [value.x, value.y]
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item in value: parts.append(_trace_canonical(item))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var keys: Array = value.keys(); keys.sort_custom(func(a, b): return String(a) < String(b))
			var parts: Array[String] = []
			for key in keys: parts.append("%s:%s" % [JSON.stringify(String(key)), _trace_canonical(value[key])])
			return "{" + ",".join(parts) + "}"
	return "unsupported:%d" % typeof(value)

func _save_bytes(path: String) -> PackedByteArray:
	if not Sim.save_game(path, {"test": "goto_tick_atomicity"}): return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return PackedByteArray()
	var bytes := file.get_buffer(file.get_length()); file.close()
	return bytes

func _find_player_event(kind: String) -> Dictionary:
	for raw in Sim.event_log:
		var ev: Dictionary = raw
		if String(ev.get("type", "")) == kind and String(ev.get("actor", "")) == "player": return ev
	return {}

func _start_near(seed: int, target_id := "fei") -> Dictionary:
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(seed)
	var target: Dictionary = Sim.get_agent(target_id)
	return Sim.add_player(target.get("pos", Vector2i.ZERO))

func _mutations_reject(trace: Dictionary) -> void:
	var before := Sim.get_player_trace()
	var dropped := trace.duplicate(true); (dropped["entries"] as Array).remove_at(0); dropped["next_seq"] = (dropped["entries"] as Array).size()
	_ck("dropped entry rejected", not Sim.set_player_trace_for_replay(dropped))
	var duplicated := trace.duplicate(true); (duplicated["entries"] as Array).insert(1, (duplicated["entries"] as Array)[0].duplicate(true)); duplicated["next_seq"] = (duplicated["entries"] as Array).size()
	_ck("duplicated entry rejected", not Sim.set_player_trace_for_replay(duplicated))
	if (trace["entries"] as Array).size() >= 2:
		var reordered := trace.duplicate(true); var a = reordered["entries"][0]; reordered["entries"][0] = reordered["entries"][1]; reordered["entries"][1] = a
		_ck("reordered entries rejected", not Sim.set_player_trace_for_replay(reordered))
	var payload_tampered := trace.duplicate(true); payload_tampered["entries"][0]["payload"]["pos"] = Vector2i(999, 999)
	_ck("payload tamper rejected", not Sim.set_player_trace_for_replay(payload_tampered))
	var receipt_forged := trace.duplicate(true); receipt_forged["entries"][0]["receipt"]["event_digest"] = 42
	_ck("forged receipt rejected", not Sim.set_player_trace_for_replay(receipt_forged))
	var future := trace.duplicate(true); future["version"] = 2
	_ck("future trace rejected", not Sim.set_player_trace_for_replay(future))
	var wrong_session := trace.duplicate(true); wrong_session["session"]["seed"] = int(wrong_session["session"]["seed"]) + 1
	_ck("wrong session fingerprint rejected", not Sim.set_player_trace_for_replay(wrong_session))
	var wrong_actor := trace.duplicate(true); wrong_actor["entries"][0]["actor"] = "observer"
	_ck("non-player actor rejected", not Sim.set_player_trace_for_replay(wrong_actor))
	_ck("failed trace import is atomic", Sim.get_player_trace() == before)

func _goto_tick_failure_is_atomic(valid_trace: Dictionary) -> void:
	Sim.backend = null; Sim.auto_run = true; Sim.start_new(7); Sim.add_player(Vector2i(1, 0))
	var forged := valid_trace.duplicate(true)
	var forged_entry: Dictionary = (forged["entries"] as Array)[0]
	forged_entry["receipt"]["event_digest"] = int(forged_entry["receipt"].get("event_digest", 0)) + 1
	var unsigned := forged_entry.duplicate(true); unsigned.erase("seal")
	forged_entry["seal"] = Sim.fnv1a32(_trace_canonical(unsigned))
	_ck("coherently resealed forged receipt imports structurally", Sim.set_player_trace_for_replay(forged))
	var before_path := "user://player_trace_atomic_before.save"
	var after_path := "user://player_trace_atomic_after.save"
	var before_bytes := _save_bytes(before_path)
	var before_trace := Sim.get_player_trace()
	var before_status := Sim.player_trace_status(); before_status.erase("error")
	var before_auto_run := Sim.auto_run; var before_replaying := Sim.replaying
	var before_pos: Vector2i = Sim.get_agent("player").get("pos", Vector2i.ZERO)
	var replay_ok := Sim.goto_tick(0)
	var failure_error := Sim.player_trace_last_error
	var after_status := Sim.player_trace_status(); after_status.erase("error")
	var after_bytes := _save_bytes(after_path)
	_ck("forged replay fails at recomputed receipt", not replay_ok and failure_error == "recomputed_receipt_mismatch", failure_error)
	_ck("failed goto_tick restores complete authoritative save state", not before_bytes.is_empty() and after_bytes == before_bytes)
	_ck("failed goto_tick restores trace index and runtime controls", Sim.get_player_trace() == before_trace and after_status == before_status \
		and Sim.auto_run == before_auto_run and Sim.replaying == before_replaying)
	_ck("failed goto_tick restores player position", Sim.get_agent("player").get("pos", Vector2i.ZERO) == before_pos, \
		"%s -> %s" % [str(before_pos), str(Sim.get_agent("player").get("pos", Vector2i.ZERO))])

func _rewrite_save_without_trace(source: String, target: String) -> bool:
	var f := FileAccess.open(source, FileAccess.READ)
	if f == null: return false
	var schema := f.get_32(); var blob = f.get_var(); f.close()
	if not (blob is Dictionary): return false
	blob.erase("player_trace")
	f = FileAccess.open(target, FileAccess.WRITE)
	if f == null: return false
	f.store_32(schema); f.store_var(blob); f.close()
	return true

func _rewrite_save_bad_trace(source: String, target: String) -> bool:
	var f := FileAccess.open(source, FileAccess.READ)
	if f == null: return false
	var schema := f.get_32(); var blob = f.get_var(); f.close()
	if not (blob is Dictionary) or not (blob.get("player_trace") is Dictionary): return false
	blob["player_trace"]["version"] = 99
	f = FileAccess.open(target, FileAccess.WRITE)
	if f == null: return false
	f.store_32(schema); f.store_var(blob); f.close()
	return true

func _social_trace(seed: int, target_id := "fei", check_invalid := true) -> Dictionary:
	_start_near(seed, target_id)
	if check_invalid:
		var invalid_before := Sim.event_log.size()
		var invalid := Sim.player_act("not_a_social_verb", target_id)
		_ck("invalid social is canonical no-op", invalid == "未知动作" and Sim.event_log.size() == invalid_before, invalid)
		var mediate_before := Sim.event_log.size()
		var mediate_invalid := Sim.player_mediate(target_id)
		_ck("mediation public boundary records invalid no-op", mediate_invalid != "" and Sim.event_log.size() == mediate_before, mediate_invalid)
	var start_msg := Sim.player_act("greet", target_id)
	_tickn(12)
	var ev := _find_player_event("greet")
	return {"trace": Sim.get_player_trace(), "state": _player_state(), "event": ev, "start_msg": start_msg}

func _public_refused_greet_trace() -> Dictionary:
	# Passive town life can establish a negative dyad through the same social
	# transaction.  Wait for such a nearby dyad, then issue the player's greet;
	# no state injection/private helper is used to manufacture refusal.
	for seed in range(1, 9):
		Sim.backend = null; Sim.auto_run = false; Sim.start_new(seed); Sim.add_player()
		for _step in range(6 * int(Sim.TICKS_PER_DAY)):
			Sim.tick()
			var pl: Dictionary = Sim.get_agent("player")
			if pl.is_empty() or int(pl.get("talking", 0)) > 0: continue
			for raw in Sim.agents:
				var target: Dictionary = raw
				if String(target.get("id", "")) == "player" or int(target.get("talking", 0)) > 0: continue
				if String(target.get("space", "")) != String(pl.get("space", "")) or String(target.get("floor", "")) != String(pl.get("floor", "")): continue
				var pp: Vector2i = pl.get("pos", Vector2i.ZERO); var tp: Vector2i = target.get("pos", Vector2i(999, 999))
				if absi(pp.x - tp.x) + absi(pp.y - tp.y) > 2: continue
				var toward_player: Dictionary = target.get("relationships", {}).get("player", {})
				if float(toward_player.get("affinity", 0.0)) >= 0.0: continue
				var mark := Sim.event_log.size()
				var start_msg := Sim.player_act("greet", String(target.get("id", "")))
				_tickn(12)
				for i in range(mark, Sim.event_log.size()):
					var ev: Dictionary = Sim.event_log[i]
					if String(ev.get("type", "")) == "greet" and String(ev.get("actor", "")) == "player" and not bool(ev.get("accepted", true)):
						return {"trace": Sim.get_player_trace(), "state": _player_state(), "event": ev, "start_msg": start_msg}
	return {}


func _portal_endpoint(from_space: String, from_floor: String, to_space: String, to_floor: String) -> Vector2i:
	for raw in Sim._authored_portals:
		var p: Dictionary = raw
		for side in ["from", "to"]:
			var a: Dictionary = p.get(side, {})
			var b: Dictionary = p.get("to") if side == "from" else p.get("from")
			if String(a.get("space", "")) == from_space and String(a.get("floor", "")) == from_floor \
					and String(b.get("space", "")) == to_space and String(b.get("floor", "")) == to_floor:
				var pos: Array = a.get("pos", [])
				if pos.size() == 2: return Vector2i(int(pos[0]), int(pos[1]))
	return Vector2i(-1, -1)

func _walk_player_to(target: Vector2i) -> bool:
	var pl: Dictionary = Sim.get_agent("player")
	if pl.is_empty() or target.x < 0: return false
	var start: Vector2i = pl.get("pos", Vector2i(-1, -1))
	var path: Array = Sim._astar_path(Sim._grid_for(String(pl.get("space", "town")), String(pl.get("floor", "outdoor"))), start, target)
	if path.is_empty(): return false
	for i in range(1, path.size()):
		var before: Vector2i = pl.get("pos", Vector2i.ZERO)
		Sim.player_move((path[i] as Vector2i) - (path[i - 1] as Vector2i))
		if Vector2i(pl.get("pos", Vector2i.ZERO)) == before: return false
	return Vector2i(pl.get("pos", Vector2i.ZERO)) == target

func _guest_access_revoke_trace() -> Dictionary:
	for seed in range(1, 33):
		Sim.backend = null; Sim.auto_run = false; Sim.start_new(seed)
		# Aria starts in her private 2F home. Advance the autonomous, no-player
		# prefix until she is publicly reachable, then begin the PlayerTrace.
		if not Sim.goto_tick(600): continue
		var aria: Dictionary = Sim.get_agent("aria")
		var pl := Sim.add_player(aria.get("pos", Vector2i.ZERO))
		if Sim.player_act("invite", "aria") != "": continue
		_tickn(12)
		if not Sim._cafe_guest_capability_valid(): continue
		var town_door := _portal_endpoint("town", "outdoor", "cafe", "1f")
		if not _walk_player_to(town_door): continue
		var enter := Sim.player_portal_intent({"source_space": "town", "source_floor": "outdoor", "portal_pos": town_door})
		if not bool(enter.get("ok", false)): continue
		var stairs := _portal_endpoint("cafe", "1f", "cafe", "2f")
		if not _walk_player_to(stairs): continue
		var access := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": stairs})
		if not bool(access.get("ok", false)) or String(pl.get("floor", "")) != "2f": continue
		var revoke := Sim.player_cafe_guest_pass("revoke")
		if not bool(revoke.get("ok", false)) or not bool(revoke.get("returned", false)): continue
		return {"trace": Sim.get_player_trace(), "state": _player_state(), "seed": seed,
			"access": access, "revoke": revoke}
	return {}

func _ready() -> void:
	print("=== PlayerTraceV1 deterministic player intervention replay ===")

	# No-player C0 remains byte-for-byte autonomous and produces no player trace entries.
	Sim.backend = null; Sim.auto_run = false; Sim.start_new(20260825); _tickn(80)
	var no_player_a := {"digest": Inv.digest(Sim), "event_digest": Sim.event_digest}
	var no_player_status := Sim.player_trace_status()
	Sim.start_new(20260825); _tickn(80)
	_ck("no-player autonomous digest unchanged", no_player_a == {"digest": Inv.digest(Sim), "event_digest": Sim.event_digest})
	_ck("view-free baseline has empty bounded trace", int(no_player_status["entries"]) == 0 and int(no_player_status["indexed_ticks"]) == 0)

	# Accepted social + invalid no-op, then exact same-seed public-boundary replay.
	var accepted := _social_trace(7)
	_ck("accepted greet recorded", accepted["start_msg"] == "" and not (accepted["event"] as Dictionary).is_empty() and bool(accepted["event"].get("accepted", false)))
	var accepted_trace: Dictionary = accepted["trace"]
	var accepted_state: Dictionary = accepted["state"]
	_ck("strict seq/order and typed inputs recorded", int(accepted_trace["next_seq"]) == (accepted_trace["entries"] as Array).size() and (accepted_trace["entries"] as Array).size() == 4)
	_ck("goto_tick replays accepted social exactly", Sim.goto_tick(int(accepted_state["tick"])) and _player_state() == accepted_state)
	_ck("identical trace repeats exact state", Sim.goto_tick(int(accepted_state["tick"])) and _player_state() == accepted_state)

	# Find a deterministic first-greet refusal using only public inputs; preserve the found trace.
	var refused := _public_refused_greet_trace()
	_ck("refused greet fixture found through public boundary", not refused.is_empty())
	if not refused.is_empty():
		var refused_state: Dictionary = refused["state"]
		_ck("refusal is consequential, not no-op", (refused_state["player"]["memory"] as Array).size() > 0 and int(refused_state["event_digest"]) != 0)
		_ck("refused greet replay reproduces memory/relationship/digest", Sim.goto_tick(int(refused_state["tick"])) and _player_state() == refused_state)

	# Cardinal movement and public portal intent use the same public APIs during replay.
	Sim.start_new(22)
	var mover := Sim.add_player()
	var move_from: Vector2i = mover.get("pos", Vector2i.ZERO)
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		Sim.player_move(direction)
		if Vector2i(mover.get("pos", Vector2i.ZERO)) != move_from: break
	var move_state := _player_state()
	_ck("cardinal movement records a real public mutation", Vector2i(mover.get("pos", Vector2i.ZERO)) != move_from)
	_ck("cardinal movement replay exact", Sim.goto_tick(int(move_state["tick"])) and _player_state() == move_state)

	Sim.start_new(33)
	var portal_player := Sim.add_player(Vector2i(57, 8))
	var portal_receipt := Sim.player_portal_intent({"source_space": "town", "source_floor": "outdoor", "portal_pos": Vector2i(57, 8)})
	var portal_state := _player_state(); var portal_trace := Sim.get_player_trace()
	_ck("public portal intent recorded success", bool(portal_receipt.get("ok", false)) and String(portal_player.get("space", "")) == "port_warehouse")
	_ck("portal replay exact", Sim.goto_tick(int(portal_state["tick"])) and _player_state() == portal_state)
	var denied_before := _player_state()
	var denied := Sim.player_portal_intent({"source_space": "town", "source_floor": "outdoor", "portal_pos": Vector2i(57, 8)})
	_ck("stale-plane portal denial remains no-state-mutation", not bool(denied.get("ok", true)) and _player_state() == denied_before)
	_ck("portal trace remains bounded/indexed", int(Sim.player_trace_status()["entries"]) == (Sim.get_player_trace()["entries"] as Array).size())


	# Cafe guest grant/access/revoke are all real public player inputs and replay
	# to the same player address, capability receipt and chronicle digest.
	var guest := _guest_access_revoke_trace()
	_ck("public guest grant/access/revoke fixture found", not guest.is_empty())
	if not guest.is_empty():
		var guest_trace: Dictionary = guest["trace"]
		var guest_state: Dictionary = guest["state"]
		var kinds: Array = []
		for raw in guest_trace.get("entries", []): kinds.append(String((raw as Dictionary).get("kind", "")))
		_ck("trace explicitly records grant social + portal access + revoke", "social" in kinds and kinds.count("portal") >= 2 and "cafe_guest_pass" in kinds, str(kinds))
		_ck("revoke receipt returned invited player from cafe/2f", String((guest_state["player"] as Dictionary).get("space", "")) == "cafe" \
			and String((guest_state["player"] as Dictionary).get("floor", "")) == "1f" and String((guest_state["capability"] as Dictionary).get("status", "")) == "revoked")
		_ck("guest grant/access/revoke replay exact", Sim.goto_tick(int(guest_state["tick"])) and _player_state() == guest_state)

	# Completed chat memory is behind Sim and replays without live AI.
	_start_near(41)
	var chat_result := Sim.player_chat_commit("fei", "今天好吗？", "挺好的。")
	var chat_state := _player_state()
	_ck("completed chat reply commits through public Sim boundary", bool(chat_result.get("ok", false)))
	_ck("chat replay reproduces canonical memory without AI", Sim.goto_tick(int(chat_state["tick"])) and _player_state() == chat_state)
	var chat_count := int(Sim.player_trace_status()["entries"])
	var too_long := Sim.player_chat_commit("fei", "x".repeat(Sim.PLAYER_TRACE_MAX_CHAT_BYTES + 1), "no")
	_ck("chat byte cap refuses visibly without truncation", not bool(too_long.get("ok", true)) and int(Sim.player_trace_status()["entries"]) == chat_count)

	# Save/load carries an optional trace; malformed saves reject before touching live state.
	var save_path := "user://player_trace_v1.save"
	var old_path := "user://player_trace_v1_old.save"
	var bad_path := "user://player_trace_v1_bad.save"
	_ck("trace save under explicit size cap", Sim.save_game(save_path, {"test": "player_trace"}))
	var saved_state := _player_state()
	Sim.start_new(99); _tickn(3)
	_ck("save/load restores trace and state", Sim.load_game(save_path) and Sim.player_trace_status()["available"] and _player_state() == saved_state)
	_ck("save/load then goto_tick remains exact", Sim.goto_tick(int(saved_state["tick"])) and _player_state() == saved_state)
	_ck("old-save fixture created", _rewrite_save_without_trace(save_path, old_path))
	_ck("old save loads with replay explicitly unavailable", Sim.load_game(old_path) and not bool(Sim.player_trace_status()["available"]))
	var old_state := _player_state()
	_ck("old save goto fails closed without changing live world", not Sim.goto_tick(int(old_state["tick"])) and _player_state() == old_state)
	_ck("corrupt-save fixture created", _rewrite_save_bad_trace(save_path, bad_path))
	var before_bad_load := _player_state()
	_ck("corrupt/future trace save rejects atomically", not Sim.load_game(bad_path) and _player_state() == before_bad_load)

	# Public import mutation teeth; failed import cannot replace the current authority.
	Sim.start_new(7)
	_ck("restore accepted trace for mutation controls", Sim.set_player_trace_for_replay(accepted_trace))
	_mutations_reject(accepted_trace)
	_goto_tick_failure_is_atomic(accepted_trace)

	var caps := Sim.player_trace_status()
	_ck("explicit finite trace/query/payload/chat/save budgets", int(caps["max_entries"]) == 4096 and int(caps["max_entries_per_tick"]) == 64 and int(caps["max_payload_bytes"]) == 4096 \
		and int(caps["max_chat_bytes"]) == 1024 and int(caps["max_save_bytes"]) == 8388608)

	print("player_replay_test: %s (%d fail)" % [("PASS" if fails == 0 else "FAIL"), fails])
	get_tree().quit(0 if fails == 0 else 1)
