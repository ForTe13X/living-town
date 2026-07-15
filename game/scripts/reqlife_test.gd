extends Node
## Unit test for the engine's legality boundaries:
##  · AI request lifecycle (P1-1/2/3): _cand_key completeness, _match (epoch,req_id) gating, cancel_all reset.
##  · Sim-side (P2-1/P2-2): replay candidate identity + agent_apply's object-intent boundary.
## Uses the AIBackend/Sim autoloads → must run via a scene (autoloads aren't loaded under --script):
##   godot --headless --path game res://scenes/reqlife_test.tscn
var _fails := 0
func ck(c: bool, m: String) -> void:
	if not c: _fails += 1
	print(("  OK   " if c else "  FAIL ") + m)
func _ready() -> void:
	var ab = AIBackend
	# _cand_key: complete stable identity (fixes P2-1's partial hash)
	var c1 = {"kind": "social", "action": "greet", "partner": "aria", "need": "social", "amount": 5, "duration": 2}
	var c2 = {"kind": "social", "action": "greet", "partner": "ben", "need": "social", "amount": 5, "duration": 2}
	var c3 = {"kind": "object", "action": "eat", "object": "stove_1", "need": "hunger", "amount": 30, "duration": 4}
	var c1b = {"kind": "object", "action": "eat", "object": "stove_1", "need": "hunger", "amount": 30, "duration": 8}  # only duration differs
	ck(ab._cand_key(c1) != ab._cand_key(c2), "_cand_key distinguishes partner")
	ck(ab._cand_key(c1) == ab._cand_key(c1.duplicate()), "_cand_key stable across duplicate")
	ck(ab._cand_key(c1) != ab._cand_key(c3), "_cand_key distinguishes kind/action")
	ck(ab._cand_key(c3) != ab._cand_key(c1b), "_cand_key distinguishes duration (P2-1 miss)")
	# cancel_all: bump epoch + clear pending + reset inflight
	ab.world_epoch = 5
	ab._pending = {"x": {"epoch": 5, "req_id": 1, "http": null, "slm_chat": null}}
	ab._inflight = 2
	ab.cancel_all()
	ck(ab.world_epoch == 6, "cancel_all bumps world_epoch")
	ck(ab._pending.is_empty(), "cancel_all clears _pending")
	ck(ab._inflight == 0, "cancel_all resets _inflight")
	# _match: only the same (epoch,req_id) still owns the slot
	ab._pending = {"y": {"epoch": 6, "req_id": 3}}
	ck(ab._match("y", 6, 3), "_match accepts same (epoch,req_id)")
	ck(not ab._match("y", 5, 3), "_match rejects stale epoch (cross-run reply)")
	ck(not ab._match("y", 6, 2), "_match rejects stale req_id (late reply after new request)")
	ck(not ab._match("z", 6, 3), "_match rejects unknown id")

	# ── Sim legality boundaries (P2-1 replay identity, P2-2 apply boundary) ──
	Sim.start_new(1)                                  # populate world.objects / agents for the checks
	var ag: Dictionary = Sim.agents[0]
	var need_id: String = String((ag["needs"] as Dictionary).keys()[0])
	var obj_id: String = String((Sim.world["objects"] as Dictionary).keys()[0])
	var good := {"kind": "object", "action": "x", "target": obj_id, "need": need_id, "amount": 10, "dur_total": 4}
	ck(Sim._object_intent_ok(ag, good), "P2-2 accepts a well-formed object intent")
	var z := good.duplicate(); z["dur_total"] = 0
	ck(not Sim._object_intent_ok(ag, z), "P2-2 rejects dur_total=0 (divide-by-zero guard)")
	var un := good.duplicate(); un["need"] = "no_such_need"
	ck(not Sim._object_intent_ok(ag, un), "P2-2 rejects unknown need (index guard)")
	var miss := good.duplicate(); miss.erase("amount")
	ck(not Sim._object_intent_ok(ag, miss), "P2-2 rejects missing field")
	var badt := good.duplicate(); badt["target"] = "no_such_object"
	ck(not Sim._object_intent_ok(ag, badt), "P2-2 rejects unknown target")
	# P2-1: the two-beds case the old hash could not tell apart (same action, different target)
	var b1 := {"kind": "object", "action": "睡觉", "target": "bed_1", "need": "energy", "amount": 30, "dur_total": 8}
	var b2 := {"kind": "object", "action": "睡觉", "target": "bed_2", "need": "energy", "amount": 30, "dur_total": 8}
	ck(Sim._cand_key(b1) != Sim._cand_key(b2), "P2-1 Sim._cand_key distinguishes target (two beds)")
	# P2-1: reorder must count as drift (old hash sorted → 'unchanged', while replay read by index → wrong pick)
	ck(Sim._cand_hash([b1, b2]) != Sim._cand_hash([b2, b1]), "P2-1 _cand_hash is order-sensitive (reorder = drift)")

	print("reqlife_test: %d fail" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
