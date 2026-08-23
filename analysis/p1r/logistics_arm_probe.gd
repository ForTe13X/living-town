extends SceneTree
## Read-only P1-r recovery probe. Run from an isolated exact-tree copy. The ON
## arm proves all four trade event families are live per seed; the OFF arm removes
## game/data/logistics.json and proves genuine emptiness rather than relying on
## the conditional wording of #44/#45/#46.

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _fails := 0

func _ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func _inv_ok(S, iid: int) -> bool:
	for row in Inv.check_all(S, 0):
		if int(row.get("id", -1)) == iid:
			return bool(row.get("ok", false))
	return false

func _parse_seeds(spec: String) -> Array:
	if "-" in spec:
		var parts := spec.split("-", false, 1)
		var out: Array = []
		for seed in range(int(parts[0]), int(parts[1]) + 1):
			out.append(seed)
		return out
	return [int(spec)]

func _run(seed: int, days: int, core: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if core > 0:
		S.spawn_count = core
	S.start_new(seed)
	for _tick in range(days * int(S.TICKS_PER_DAY)):
		S.tick()
	var trade := {"arrival": 0, "import": 0, "export": 0, "unload": 0}
	for event in S.event_log:
		if not (event is Dictionary):
			continue
		var ty := String(event.get("type", ""))
		if ty == "world" and String(event.get("note", "")).begins_with("cargo_arrive:"):
			trade["arrival"] = int(trade["arrival"]) + 1
		elif trade.has(ty):
			trade[ty] = int(trade[ty]) + 1
		if ty == "world" and String(event.get("note", "")).begins_with("cargo_unload:"):
			trade["unload"] = int(trade["unload"]) + 1
	var out := {
		"seed": seed,
		"core": int(S.core_population),
		"total": S.agents.size(),
		"logistics_empty": S.logistics.is_empty(),
		"manifest_count": S.cargo_manifests.size(),
		"manifest_order_count": S.cargo_manifest_order.size(),
		"arrival": int(trade["arrival"]),
		"import": int(trade["import"]),
		"export": int(trade["export"]),
		"unload": int(trade["unload"]),
		"i44": _inv_ok(S, 44),
		"i45": _inv_ok(S, 45),
		"i46": _inv_ok(S, 46),
		"digest": Inv.digest(S),
		"event_digest": str(S.event_digest),
	}
	get_root().remove_child(S)
	S.free()
	return out

func _init() -> void:
	var seeds := [1, 2, 3]
	var days := 20
	var core := 0
	var expect := "off"
	var det := 2
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--core" and i + 1 < args.size():
			core = int(args[i + 1])
		elif args[i] == "--expect" and i + 1 < args.size():
			expect = args[i + 1]
		elif args[i] == "--det" and i + 1 < args.size():
			det = int(args[i + 1])
	_ck(expect == "off" or expect == "on", "expect is off or on")
	_ck(FileAccess.file_exists("res://data/logistics.json") == (expect == "on"),
		"isolated product tree logistics.json matches expected arm")
	var totals := {"arrival": 0, "import": 0, "export": 0, "unload": 0}
	var covered := {"arrival": 0, "import": 0, "export": 0, "unload": 0}
	for seed in seeds:
		var a := _run(seed, days, core)
		print("[P1R-ARM] " + JSON.stringify(a))
		for key in totals:
			totals[key] = int(totals[key]) + int(a[key])
			if int(a[key]) > 0:
				covered[key] = int(covered[key]) + 1
		if expect == "off":
			_ck(bool(a["logistics_empty"]), "seed %d compiles no logistics" % seed)
			_ck(int(a["manifest_count"]) == 0 and int(a["manifest_order_count"]) == 0,
				"seed %d has no cargo queue" % seed)
			_ck(int(a["arrival"]) == 0 and int(a["import"]) == 0
				and int(a["export"]) == 0 and int(a["unload"]) == 0,
				"seed %d has zero arrival/import/export/unload events" % seed)
		else:
			_ck(not bool(a["logistics_empty"]), "seed %d compiles authored logistics" % seed)
			_ck(int(a["arrival"]) > 0 and int(a["import"]) > 0
				and int(a["export"]) > 0 and int(a["unload"]) > 0,
				"seed %d has non-vacuous arrival/import/export/unload events" % seed)
		_ck(bool(a["i44"]) and bool(a["i45"]) and bool(a["i46"]),
			"seed %d conditional trade invariants remain green" % seed)
		for _repeat in range(1, det):
			_ck(a == _run(seed, days, core), "seed %d arm summary is deterministic" % seed)
	print("[P1R-SUM] " + JSON.stringify({"expect": expect, "seeds": seeds.size(),
		"days": days, "core": core, "totals": totals, "covered": covered}))
	if _fails == 0:
		print("P1-r logistics arm probe: PASS")
	else:
		print("P1-r logistics arm probe: FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
