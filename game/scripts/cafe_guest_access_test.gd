extends Node

var fails := 0
func ck(ok: bool, label: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok: fails += 1

func _same_authority(a: Dictionary, b: Dictionary) -> bool:
	return a.get("capability") == b.get("capability") and a.get("events") == b.get("events") \
		and a.get("digest") == b.get("digest") and a.get("player") == b.get("player")

func _authority_snapshot() -> Dictionary:
	var pl: Dictionary = Sim.get_agent("player")
	return {"capability": Sim.cafe_guest_capability.duplicate(true), "events": Sim.event_log.duplicate(true),
		"digest": Sim.event_digest, "player": {"space": pl.get("space", ""), "floor": pl.get("floor", ""), "pos": pl.get("pos", Vector2i.ZERO)}}

func _ready() -> void:
	Sim.start_new(17)
	Sim.add_player()
	var pl: Dictionary = Sim.get_agent("player")
	var aria: Dictionary = Sim.get_agent("aria")
	ck(not pl.is_empty() and not aria.is_empty(), "player and aria exist")
	# Deterministic fixture placement; invitation/traversal/revoke still cross public boundaries.
	Sim._move_agent(pl, aria.get("pos", Vector2i.ZERO))
	pl["space"] = "cafe"; pl["floor"] = "1f"; pl["area"] = aria.get("area", "")
	aria["space"] = "cafe"; aria["floor"] = "1f"
	Sim._rel(pl, "aria")["affinity"] = 100.0; Sim._rel(pl, "aria")["trust"] = 100.0
	Sim._rel(aria, "player")["affinity"] = 100.0; Sim._rel(aria, "player")["trust"] = 100.0
	ck(Sim.cafe_guest_capability.is_empty(), "no capability before invitation")
	ck(Sim.player_act("invite", "aria") == "", "real invite input accepted")
	for _i in range(12): Sim.tick()
	ck(Sim._cafe_guest_capability_valid(), "accepted invite grants authoritative capability")
	var active := Sim.cafe_guest_capability.duplicate(true)
	var grant_id := int(active.get("grant_event_id", -1))
	var grant_rows := Sim.event_log.filter(func(e): return int((e as Dictionary).get("id", -1)) == grant_id)
	ck(grant_rows.size() == 1 and String((grant_rows[0] as Dictionary).get("type", "")) == "cafe_guest_grant",
		"capability binds one exact cafe_guest_grant chronicle row")
	ck(int(active.get("grant_event_digest", -1)) == Sim._cafe_guest_event_digest_at(Sim.event_log, Sim.event_log.find(grant_rows[0])),
		"grant receipt binds exact authoritative chronicle prefix")

	var canonical_string_forgery := active.duplicate(true)
	canonical_string_forgery["grant_event_id"] = str(active["grant_event_id"])
	ck(Sim._cafe_guest_capability_error(canonical_string_forgery, Sim.event_log, Sim.tick_no) != "", "canonical-string event id forgery rejected")
	var future := active.duplicate(true); future["granted_tick"] = Sim.tick_no + 1
	ck(Sim._cafe_guest_capability_error(future, Sim.event_log, Sim.tick_no) != "", "future granted_tick rejected")
	var mismatched := active.duplicate(true); mismatched["grant_event_digest"] = int(mismatched["grant_event_digest"]) ^ 1
	ck(Sim._cafe_guest_capability_error(mismatched, Sim.event_log, Sim.tick_no) != "", "mismatched grant provenance rejected")
	var forged_events := Sim.event_log.duplicate(true)
	(forged_events[Sim.event_log.find(grant_rows[0])] as Dictionary)["actor"] = "player"
	ck(Sim._cafe_guest_capability_error(active, forged_events, Sim.tick_no) != "", "forged chronicle grant rejected")

	var stairs := Vector2i(1, 1)
	Sim._move_agent(pl, stairs)
	var receipt := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": stairs})
	ck(bool(receipt.get("ok", false)) and pl.get("floor") == "2f", "guest capability authorizes cafe stairs")
	var save_path := "user://cafe_guest_access_v1.save"
	ck(Sim.save_game(save_path, {"test": "cafe_guest_access"}), "capability save succeeds")
	Sim.cafe_guest_capability = {}
	ck(Sim.load_game(save_path) and Sim._cafe_guest_capability_valid(), "load restores active capability and provenance")
	pl = Sim.get_agent("player")
	var revoke_receipt := Sim.player_cafe_guest_pass("revoke")
	ck(bool(revoke_receipt.get("ok", false)) and bool(revoke_receipt.get("returned", false)), "typed player revoke returns private-floor guest")
	ck(String(pl.get("space", "")) == "cafe" and String(pl.get("floor", "")) == "1f" and pl.get("pos") == stairs, "revocation recovers player to authored cafe 1f")
	ck(String(Sim.cafe_guest_capability.get("status", "")) == "revoked", "capability is revoked after recovery commit")
	ck(Sim._cafe_guest_capability_error(Sim.cafe_guest_capability, Sim.event_log, Sim.tick_no) == "", "revoked receipt binds exact grant and revoke events")
	ck(Sim.event_log.any(func(e): return String(e.get("type", "")) == "cafe_guest_revoke_recovery"), "safe recovery is persistent chronicle event")
	ck(Sim.save_game(save_path, {"test": "cafe_guest_revoked_recovery"}), "revoked safe state saves")
	Sim.cafe_guest_capability = {}
	ck(Sim.load_game(save_path) and String(Sim.get_agent("player").get("floor", "")) == "1f", "revoked safe state loads")
	pl = Sim.get_agent("player")
	var denied := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": stairs})
	ck(not bool(denied.get("ok", false)) and denied.get("reason") == "portal_not_permitted", "revoked capability fails closed (%s)" % String(denied.get("reason", "")))

	var revoked := Sim.cafe_guest_capability.duplicate(true)
	var forged_revoke := revoked.duplicate(true); forged_revoke["revoke_event_id"] = str(revoked["revoke_event_id"])
	ck(Sim._cafe_guest_capability_error(forged_revoke, Sim.event_log, Sim.tick_no) != "", "canonical-string revoke forgery rejected")
	var future_revoke := revoked.duplicate(true); future_revoke["revoked_tick"] = Sim.tick_no + 1
	ck(Sim._cafe_guest_capability_error(future_revoke, Sim.event_log, Sim.tick_no) != "", "future revoke tick rejected")
	var stale := active.duplicate(true)
	ck(Sim._cafe_guest_capability_error(stale, Sim.event_log, Sim.tick_no) != "", "stale active receipt after revoke rejected")
	var before_second := _authority_snapshot()
	ck(not Sim.revoke_cafe_guest_capability(), "already revoked capability is rejected")
	ck(_same_authority(before_second, _authority_snapshot()), "rejected revoke is atomic for Sim/player/chronicle authority")

	var forged_live := active.duplicate(true); forged_live["grant_event_digest"] = int(forged_live["grant_event_digest"]) ^ 7
	Sim.cafe_guest_capability = forged_live
	var before_forged_revoke := _authority_snapshot()
	ck(not Sim.revoke_cafe_guest_capability(), "forged active receipt cannot revoke")
	ck(_same_authority(before_forged_revoke, _authority_snapshot()), "forged revoke is rejected atomically")

	# LT-05 hostile clearance control: obstruct the authored café exit endpoint
	# only in this fixture's derived navigation grid. The public movement and
	# portal APIs must both refuse it; restoring the cell must reopen the route.
	Sim.cafe_guest_capability = revoked.duplicate(true)
	var cafe_door := Vector2i(-1, -1)
	for raw_portal in Sim._authored_portals:
		if raw_portal is Dictionary and String((raw_portal as Dictionary).get("id", "")) == "p_cafe_door":
			var to_side: Dictionary = (raw_portal as Dictionary).get("to", {})
			var xy: Array = to_side.get("pos", [])
			if xy.size() == 2:
				cafe_door = Vector2i(int(xy[0]), int(xy[1]))
			break
	ck(cafe_door.x >= 0, "authored café doorway endpoint found")
	if cafe_door.x >= 0:
		var grid: Dictionary = Sim._grid_for("cafe", "1f")
		var blocks: Dictionary = grid.get("blocked", {})
		var doorway_index := cafe_door.y * int(grid.get("w", 0)) + cafe_door.x
		ck(not blocks.has(doorway_index), "authored café doorway starts walkable")
		var approach := Vector2i(-1, -1)
		for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var candidate: Vector2i = cafe_door + dir
			if Sim._cell_walkable(grid, candidate):
				approach = candidate
				break
		ck(approach.x >= 0, "walkable adjacent café approach exists")
		if approach.x >= 0 and not blocks.has(doorway_index):
			pl = Sim.get_agent("player")
			pl["talking"] = 0
			Sim._move_agent(pl, approach)
			var before_block := _authority_snapshot()
			blocks[doorway_index] = true
			Sim.player_move(cafe_door - approach)
			var trace_entries: Array = Sim.get_player_trace().get("entries", [])
			var last_move: Dictionary = trace_entries.back() if not trace_entries.is_empty() else {}
			var move_receipt: Dictionary = last_move.get("receipt", {})
			var move_result: Dictionary = move_receipt.get("result", {})
			ck(String(last_move.get("kind", "")) == "move" and String(move_result.get("reason", "")) == "blocked"
				and pl.get("pos") == approach, "blocked doorway refuses public player movement")
			var denied_door := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": cafe_door})
			ck(not bool(denied_door.get("ok", false)) and String(denied_door.get("reason", "")) == "source_endpoint_invalid",
				"blocked doorway refuses public portal transaction")
			ck(_same_authority(before_block, _authority_snapshot()), "blocked doorway leaves player and chronicle authority unchanged")
			blocks.erase(doorway_index)
			ck(Sim._cell_walkable(grid, cafe_door), "fixture obstruction removed")
			var reopened := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": cafe_door})
			ck(bool(reopened.get("ok", false)) and String(pl.get("space", "")) == "town"
				and String(pl.get("floor", "")) == "outdoor", "same authored doorway traverses after obstruction clears")
	print("CAFE_GUEST_ACCESS_TEST_FAILS=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
