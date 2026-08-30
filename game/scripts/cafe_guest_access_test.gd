extends Node

var fails := 0
func ck(ok: bool, label: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok: fails += 1

func _ready() -> void:
	Sim.start_new(17)
	Sim.add_player()
	var pl: Dictionary = Sim.get_agent("player")
	var aria: Dictionary = Sim.get_agent("aria")
	ck(not pl.is_empty() and not aria.is_empty(), "player and aria exist")
	# Deterministic fixture placement; the action and traversal still use public boundaries.
	Sim._move_agent(pl, aria.get("pos", Vector2i.ZERO))
	pl["space"] = "cafe"; pl["floor"] = "1f"; pl["area"] = aria.get("area", "")
	aria["space"] = "cafe"; aria["floor"] = "1f"
	Sim._rel(pl, "aria")["affinity"] = 100.0; Sim._rel(pl, "aria")["trust"] = 100.0
	Sim._rel(aria, "player")["affinity"] = 100.0; Sim._rel(aria, "player")["trust"] = 100.0
	var before := Sim.cafe_guest_capability.duplicate(true)
	ck(before.is_empty(), "no capability before invitation")
	ck(Sim.player_act("invite", "aria") == "", "real invite input accepted")
	for _i in range(12): Sim.tick()
	ck(Sim._cafe_guest_capability_valid(), "accepted invite grants canonical capability")
	ck(Sim.event_log.any(func(e): return String(e.get("type", "")) == "cafe_guest_grant"), "grant is chronicle event")
	# Traverse the authored private stairs through the canonical portal intent boundary.
	var stairs := Vector2i(1, 1)
	Sim._move_agent(pl, stairs)
	var receipt := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": stairs})
	ck(bool(receipt.get("ok", false)) and pl.get("floor") == "2f", "guest capability authorizes cafe stairs")
	var save_path := "user://cafe_guest_access_v1.save"
	ck(Sim.save_game(save_path, {"test": "cafe_guest_access"}), "capability save succeeds")
	Sim.cafe_guest_capability = {}
	ck(Sim.load_game(save_path) and Sim._cafe_guest_capability_valid(), "load restores active capability deterministically")
	pl = Sim.get_agent("player")
	ck(Sim.revoke_cafe_guest_capability(), "revocation is explicit and persistent")
	Sim._move_agent(pl, stairs); pl["space"] = "cafe"; pl["floor"] = "1f"
	var denied := Sim.player_portal_intent({"source_space": "cafe", "source_floor": "1f", "portal_pos": stairs})
	ck(not bool(denied.get("ok", false)) and denied.get("reason") == "portal_not_permitted", "revoked capability fails closed (%s)" % String(denied.get("reason", "")))
	# Forged identity can never authorize traversal.
	Sim.cafe_guest_capability = {"id": "forged", "holder": "player", "issuer": "aria", "status": "active", "granted_tick": 0}
	ck(not Sim._cafe_guest_capability_valid(), "forged capability rejected")
	print("CAFE_GUEST_ACCESS_TEST_FAILS=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
