extends Node
## P1-t — social transactions share one plane-aware reach contract.
##
## The adversarial arms deliberately collide cached `area` values across spaces/floors.  A cache is
## useful for enumeration, but it must never outrank the authored `(space,floor)` address at either
## the apply or commit boundary.  The adjacent-boundary arm is the positive complement: two actors
## one tile apart on the same plane remain reachable even when only one tile is inside a named area.

var _fails := 0

func _ck(name: String, ok: bool, detail: String = "") -> void:
	print("  %s %s  %s" % [("✅" if ok else "❌"), name, detail])
	if not ok:
		_fails += 1

func _clear_social(ag: Dictionary) -> void:
	ag["option"] = null
	ag["talking"] = 0
	ag["talk_with"] = ""

func _place(ag: Dictionary, space: String, floor: String, pos: Vector2i) -> void:
	ag["space"] = space
	ag["floor"] = floor
	Sim._move_agent(ag, pos)
	_clear_social(ag)

func _agent_projection(ag: Dictionary) -> Dictionary:
	var mem = ag.get("memory")
	return {
		"id": String(ag.get("id", "")),
		"space": String(ag.get("space", "")),
		"floor": String(ag.get("floor", "")),
		"pos": ag.get("pos", Vector2i.ZERO),
		"area": String(ag.get("area", "")),
		"room": String(ag.get("room", "")),
		"option": (ag.get("option") as Dictionary).duplicate(true) if ag.get("option") is Dictionary else ag.get("option"),
		"talking": int(ag.get("talking", 0)),
		"talk_with": String(ag.get("talk_with", "")),
		"last_say": String(ag.get("last_say", "")),
		"needs": (ag.get("needs", {}) as Dictionary).duplicate(true),
		"inventory": (ag.get("inventory", {}) as Dictionary).duplicate(true),
		"relationships": (ag.get("relationships", {}) as Dictionary).duplicate(true),
		"beliefs": (ag.get("beliefs", {}) as Dictionary).duplicate(true),
		"memory": (mem.items as Array).duplicate(true) if mem is Object and "items" in mem else [],
	}

func _social_projection(ids: Array) -> Dictionary:
	var projected_agents: Array = []
	for id in ids:
		projected_agents.append(_agent_projection(Sim.get_agent(String(id))))
	return {
		"agents": projected_agents,
		"conflicts": Sim.conflicts.duplicate(true),
		"commitments": Sim.commitments.duplicate(true),
		"active_commitments": Sim._active_commitments.duplicate(true),
		"event_log": Sim.event_log.duplicate(true),
		"event_digest": Sim.event_digest,
		"next_event_id": Sim._next_event_id,
		"next_commit_id": Sim._next_commit_id,
		"next_conflict_id": Sim._next_conflict_id,
		"st_neg_events": Sim.st_neg_events,
		"refused_by_bound": Sim.refused_by_bound,
		"confide_events": Sim.confide_events,
		"betray_events": Sim.betray_events,
	}

func _has_partner(cands: Array, partner_id: String) -> bool:
	for cand in cands:
		if cand is Dictionary and String(cand.get("kind", "")) == "social" \
				and String(cand.get("partner", "")) == partner_id:
			return true
	return false

func _ready() -> void:
	Sim.backend = null
	Sim.auto_run = false
	Sim.start_new(7)
	var pl: Dictionary = Sim.add_player()
	var aria: Dictionary = Sim.get_agent("aria")
	var ben: Dictionary = Sim.get_agent("ben")
	var coco: Dictionary = Sim.get_agent("coco")
	print("=== P1-t social plane authority ===")

	# 1-2) The existing address primitive is the source of truth, including floors within one space.
	_place(pl, "town", "outdoor", Vector2i(27, 21))
	_place(aria, "town", "outdoor", Vector2i(28, 21))
	_ck("same-plane primitive positive", Sim._same_plane(pl, aria))
	_place(aria, "cafe", "1f", Vector2i(4, 5))
	_ck("same-plane primitive rejects another space", not Sim._same_plane(pl, aria))
	_place(ben, "cafe", "2f", Vector2i(2, 2))
	_ck("same-plane primitive rejects another floor", not Sim._same_plane(aria, ben))

	# 3) Candidate enumeration was already plane-aware; keep this as the calibration tooth.
	pl["needs"]["social"] = 50.0
	aria["needs"]["social"] = 50.0
	aria["area"] = String(pl["area"]) # hostile cache collision must not defeat `_nearby_agents`.
	_ck("cross-plane cache collision yields zero social candidates",
		not _has_partner(Sim._social_candidates(pl), "aria"))

	# 4-5) Apply boundary: neither another space nor another floor may bind a conversation, even when
	# a stale/malformed cache makes the two `area` strings equal.
	var before := _social_projection(["player", "aria"])
	Sim._apply_social(pl, {"kind": "social", "action": "greet", "partner": "aria", "subject": "", "say": ""})
	_ck("apply rejects cross-space area collision atomically",
		_social_projection(["player", "aria"]) == before)
	_place(pl, "cafe", "1f", Vector2i(4, 5))
	_place(aria, "cafe", "2f", Vector2i(4, 5))
	aria["area"] = String(pl["area"])
	before = _social_projection(["player", "aria"])
	Sim._apply_social(pl, {"kind": "social", "action": "greet", "partner": "aria", "subject": "", "say": ""})
	_ck("apply rejects cross-floor area collision atomically",
		_social_projection(["player", "aria"]) == before)

	# 6) Player entry must reject the real canonical cross-plane address before action-specific state
	# can be bound, with a truthful reason instead of the old second-stage "刚走开" diagnosis.
	_place(pl, "town", "outdoor", Vector2i(4, 5))
	_place(aria, "cafe", "1f", Vector2i(4, 5))
	before = _social_projection(["player", "aria"])
	var msg := Sim.player_act("greet", "aria")
	_ck("player entry names cross-plane denial", msg == "对方不在同一空间", msg)
	_ck("player cross-plane denial is atomic", _social_projection(["player", "aria"]) == before)

	# 7) Same-plane adjacency across an area boundary is the positive complement.  `player_act` has
	# always promised this (`same area OR distance <= 2`); the apply/commit layers must not veto it.
	_place(pl, "town", "outdoor", Vector2i(27, 21)) # outside plaza, area=""
	_place(aria, "town", "outdoor", Vector2i(28, 21)) # first plaza tile, area="plaza"
	msg = Sim.player_act("greet", "aria")
	_ck("adjacent actors may talk across area boundary", msg == "" and pl.get("option") is Dictionary
		and int(pl["talking"]) > 0 and int(aria["talking"]) > 0,
		"msg='%s' areas=%s/%s" % [msg, String(pl["area"]), String(aria["area"])])
	_clear_social(pl); _clear_social(aria)

	# 8) Same-plane but genuinely distant actors remain an exact no-op.
	_place(pl, "town", "outdoor", Vector2i(0, 0))
	_place(aria, "town", "outdoor", Vector2i(14, 2))
	before = _social_projection(["player", "aria"])
	msg = Sim.player_act("greet", "aria")
	_ck("same-plane distance negative remains denied", msg == "太远了，走近点（同一区域或贴身）", msg)
	_ck("distance denial is atomic", _social_projection(["player", "aria"]) == before)

	# 9) Commit is an independent authority boundary: a forged/stale option cannot mutate needs,
	# relations, memory, witnesses or the event ledger after the actors diverge to another plane.
	_place(pl, "town", "outdoor", Vector2i(0, 0))
	_place(aria, "cafe", "1f", Vector2i(0, 0))
	aria["area"] = String(pl["area"])
	before = _social_projection(["player", "aria"])
	Sim._commit_social(pl, {"kind": "social", "action": "greet", "partner": "aria", "subject": ""})
	_ck("commit rejects cross-plane area collision atomically",
		_social_projection(["player", "aria"]) == before)

	# 10) The timed transaction re-checks the same authority immediately before commit.
	_place(pl, "town", "outdoor", Vector2i(0, 0))
	_place(aria, "town", "outdoor", Vector2i(1, 0))
	Sim._apply_social(pl, {"kind": "social", "action": "greet", "partner": "aria", "subject": "", "say": ""})
	aria["space"] = "cafe"; aria["floor"] = "1f" # preserve colliding cached area on purpose
	(pl["option"] as Dictionary)["remaining"] = 1
	var ledger_before := {
		"events": Sim.event_log.duplicate(true), "digest": Sim.event_digest,
		"next": Sim._next_event_id, "pl_rel": (pl["relationships"] as Dictionary).duplicate(true),
		"aria_rel": (aria["relationships"] as Dictionary).duplicate(true),
	}
	Sim._advance_social(pl, pl["option"])
	var ledger_after := {
		"events": Sim.event_log.duplicate(true), "digest": Sim.event_digest,
		"next": Sim._next_event_id, "pl_rel": (pl["relationships"] as Dictionary).duplicate(true),
		"aria_rel": (aria["relationships"] as Dictionary).duplicate(true),
	}
	_ck("timed transaction cancels after plane divergence", pl.get("option") == null
		and int(pl["talking"]) == 0 and ledger_after == ledger_before)
	_clear_social(aria)

	# 11) Mediation is an immediate social commit, so all three participants must share the player's
	# plane as well as the named area.  A colliding cache must not repair a remote conflict.
	_place(pl, "town", "outdoor", Vector2i(30, 23))
	_place(ben, "town", "outdoor", Vector2i(31, 23))
	_place(coco, "town", "outdoor", Vector2i(32, 23))
	Sim._rel(ben, "player")["affinity"] = 20.0
	Sim._rel(coco, "player")["affinity"] = 20.0
	Sim.conflicts.append({"a": "ben", "b": "coco", "status": "simmering", "severity": 8.0,
		"escalations": 0, "confronted": 0, "repaired": 0, "triggered": Sim.tick_no, "lastEscalate": Sim.tick_no})
	ben["space"] = "cafe"; ben["floor"] = "1f" # keep `area=plaza` as the hostile collision
	before = _social_projection(["player", "ben", "coco"])
	msg = Sim.player_mediate("ben")
	_ck("mediation rejects cross-plane participant", msg != "", msg)
	_ck("cross-plane mediation denial is atomic",
		_social_projection(["player", "ben", "coco"]) == before)

	# 12) Restore the authored plane and prove the authority gate is not a permanent mask.
	_place(ben, "town", "outdoor", Vector2i(31, 23))
	msg = Sim.player_mediate("ben")
	var repaired: Dictionary = Sim.conflicts[Sim.conflicts.size() - 1]
	_ck("same-plane mediation still commits", msg == "" and String(repaired.get("status", "")) == "repaired", msg)

	print("=== p1t_social_plane_test: %s (%d fail) ===" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(0 if _fails == 0 else 1)
