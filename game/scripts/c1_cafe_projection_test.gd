extends Node
## C1 café projection contract: real Main + canonical portal receipts + existing coffee consumer.
## Headless mode proves authority/save/replay behavior.  With --c1-evidence-out it also captures
## the same real viewport at each player-visible step; no product state is manufactured by View.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const SEED := 20260626

var _fails := 0
var _portal_signals := 0
var _main: Node
var _evidence_out := ""
var _evidence_head := ""
var _frames := []

func _ready() -> void:
	_parse_args()
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().process_frame
	Sim.auto_run = false
	Sim.backend = null
	Sim.start_new(SEED)
	Sim.add_player(Vector2i(40, 19))
	_main.set("_player_mode", true)
	_main.set("_selected_id", "player")
	_main.call("_sync_action_bar")
	_main.call("_update_status")
	_main.call("_update_obs")
	var probe = _main.get("_probe")
	probe.set_space("town", "outdoor", _main.get("_sg").bounds_px("town"))
	probe.focus_on(Vector2(40 * 48 + 24, 19 * 48 + 24), "player")
	Sim.agent_changed.connect(func(_id): _portal_signals += 1)
	await _settle()
	await _capture("01_exterior")

	# Public entrance: exact product click -> Main intent -> public Sim receipt -> one commit.
	var signal0 := _portal_signals
	var entered: bool = _main.call("_portal_click", Vector2(41 * 48 + 24, 19 * 48 + 24))
	var player := Sim.get_agent("player")
	_ck(entered and String(player.get("space", "")) == "cafe" and String(player.get("floor", "")) == "1f"
		and String(probe.active_space) == "cafe" and String(probe.active_floor) == "1f"
		and _portal_signals == signal0 + 1, "public door uses one authoritative receipt/commit")
	_ck(bool(_main.get("_c1_cafe_pan").visible), "C1 café adapter becomes visible on active café floor")
	await _settle()
	await _capture("02_public_1f")

	# Private stair denial is an exact Sim no-op; only the Main-side explanation changes.
	Sim._move_agent(player, Vector2i(1, 2))
	_main.call("_c1_cafe_return_to_player_floor")
	var denied_before := _sim_authority_snapshot()
	var denied_signal0 := _portal_signals
	var denied_hit: bool = _main.call("_portal_click", Vector2(1 * 48 + 24, 1 * 48 + 24))
	var denied_after := _sim_authority_snapshot()
	var denied_text := String(_main.get("_c1_cafe_text").text)
	_ck(denied_hit and denied_after == denied_before and _portal_signals == denied_signal0,
		"private stair denial leaves player/cache/signal/Sim authority unchanged")
	_ck("私人楼梯拒绝" in denied_text and "观察二楼" in denied_text,
		"denial gives visible observer/recovery guidance")
	await _settle()
	await _capture("03_private_denied")

	# Recovery is explicitly observer-only: distinct floor frame, unchanged player/Sim authority.
	_main.call("_c1_cafe_observe_private_floor")
	var observe_text := String(_main.get("_c1_cafe_text").text)
	_ck(String(probe.active_floor) == "2f" and String(player.get("floor", "")) == "1f"
		and _sim_authority_snapshot() == denied_before and "只读观察" in observe_text,
		"Probe may inspect distinct 2F while player remains denied on 1F")
	_ck(_main.call("_agent_on_active_plane", Sim.get_agent("aria")) == (String(Sim.get_agent("aria").get("floor", "")) == "2f"),
		"C1 picking follows active floor rather than hidden player floor")
	await _settle()
	await _capture("04_probe_2f")
	_main.call("_c1_cafe_return_to_player_floor")
	_ck(String(probe.active_floor) == "1f" and String(player.get("floor", "")) == "1f",
		"recovery returns view to the player's actionable floor")

	# Use the existing authored table advertisement and normal agent_apply/_advance_object path.
	var actor := _town_cafe_regular()
	var coffee := _coffee_candidate(actor)
	_ck(not actor.is_empty() and not coffee.is_empty() and String(coffee.get("action", "")) == "喝咖啡",
		"existing authored café table supplies the real 喝咖啡 consumer")
	if actor.is_empty() or coffee.is_empty():
		_finish()
		return
	Sim.agent_apply(actor, coffee)
	_ck(String((actor.get("option", {}) as Dictionary).get("action", "")) == "喝咖啡",
		"production consumer accepts the authored coffee intent")
	_main.call("_c1_cafe_sync")
	await _settle()
	await _capture("05_coffee_started")

	var before_path := "user://c1_cafe_before.dat"
	var after_path := "user://c1_cafe_after.dat"
	_ck(Sim.save_game(before_path, {"test": "c1-cafe-before"}), "pre-consequence save succeeds")
	var steps := 0
	while steps < 40 and not _has_coffee_memory(actor):
		Sim.tick()
		steps += 1
	_ck(_has_coffee_memory(actor) and steps > 0, "喝咖啡 completes through the existing production tick path")
	var completed := _coffee_consequence(actor)
	_ck(float(completed.get("fun", 0.0)) > 20.0 and "喝咖啡" in String(completed.get("memory", "")),
		"existing consequence is visible as restored fun plus resident memory")
	_ck(Sim.save_game(after_path, {"test": "c1-cafe-after"}), "post-consequence save succeeds")
	actor["needs"]["fun"] = 0.0
	_ck(Sim.load_game(after_path), "post-consequence save loads")
	actor = Sim.get_agent(String(completed.get("id", "")))
	_ck(_coffee_consequence(actor) == completed, "save/load preserves the same coffee consequence")

	_ck(Sim.load_game(before_path), "pre-consequence save reloads for replay")
	actor = Sim.get_agent(String(completed.get("id", "")))
	for _i in steps:
		Sim.tick()
	var replayed := _coffee_consequence(actor)
	_ck(replayed == completed, "save-based replay continuation reproduces the same consequence exactly")
	_main.call("_after_load")
	_main.call("_c1_cafe_return_to_player_floor")
	_main.call("_c1_cafe_sync")
	_ck("喝过咖啡" in String(_main.get("_c1_cafe_text").text),
		"real Main feedback derives from replayed Sim memory")
	await _settle()
	await _capture("06_replay_consequence")

	# Feature-off arm: projection controls disappear without touching Sim or canonical C0 camera data.
	var off_before := _sim_authority_snapshot()
	_main.set("_c1_cafe_enabled", false)
	_main.call("_c1_cafe_sync")
	_ck(not bool(_main.get("_c1_cafe_pan").visible) and _sim_authority_snapshot() == off_before,
		"C1 off restores the unadorned C0 view with exact Sim parity")
	_main.set("_c1_cafe_enabled", true)
	_main.call("_c1_cafe_sync")
	_finish()

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--c1-evidence-out" and i + 1 < args.size():
			_evidence_out = args[i + 1]
		elif args[i] == "--c1-head" and i + 1 < args.size():
			_evidence_head = args[i + 1]
	if _evidence_out != "":
		DirAccess.make_dir_recursive_absolute(_evidence_out)

func _town_cafe_regular() -> Dictionary:
	var table: Dictionary = {}
	for raw_id in Sim.world.get("objects", {}):
		var obj: Dictionary = Sim.world["objects"][raw_id]
		for raw_adv in obj.get("advertises", []):
			if raw_adv is Dictionary and String(raw_adv.get("action", "")) == "喝咖啡":
				table = obj
				break
		if not table.is_empty():
			break
	if table.is_empty():
		return {}
	var actor: Dictionary = {}
	for raw_agent in Sim.agents:
		var candidate: Dictionary = raw_agent
		if not bool(candidate.get("is_player", false)) and String(candidate.get("home_space", "town")) == "town":
			actor = candidate
			break
	if actor.is_empty():
		return {}
	actor["option"] = null
	actor["talking"] = 0
	for need_id in actor.get("needs", {}):
		actor["needs"][need_id] = 100.0
	actor["needs"]["fun"] = 20.0
	actor["space"] = "cafe"
	actor["floor"] = "1f"
	var target: Vector2i = table.get("pos", Vector2i(5, 3))
	var grid: Dictionary = Sim._nav_grids.get("cafe", {}).get("1f", {})
	for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var cell: Vector2i = target + delta
		if Sim._cell_walkable(grid, cell):
			Sim._move_agent(actor, cell)
			return actor
	return {}

func _coffee_candidate(actor: Dictionary) -> Dictionary:
	if actor.is_empty():
		return {}
	for raw in Sim._object_candidates(actor):
		if raw is Dictionary and String(raw.get("action", "")) == "喝咖啡":
			return (raw as Dictionary).duplicate(true)
	return {}

func _has_coffee_memory(actor: Dictionary) -> bool:
	var mem = actor.get("memory")
	if not (mem is Object) or not ("items" in mem):
		return false
	for raw in mem.items:
		if raw is Dictionary and "喝咖啡" in String(raw.get("text", "")):
			return true
	return false

func _coffee_consequence(actor: Dictionary) -> Dictionary:
	var latest := ""
	var mem = actor.get("memory")
	if mem is Object and "items" in mem:
		for raw in mem.items:
			if raw is Dictionary and "喝咖啡" in String(raw.get("text", "")):
				latest = String(raw.get("text", ""))
	return {"id": String(actor.get("id", "")), "fun": float(actor.get("needs", {}).get("fun", 0.0)),
		"memory": latest, "tick": Sim.tick_no, "event_digest": Sim.event_digest,
		"town_stock": Sim.town_stock.duplicate(true)}

func _sim_authority_snapshot() -> String:
	var player := Sim.get_agent("player")
	var pos: Vector2i = player.get("pos", Vector2i.ZERO)
	return JSON.stringify({"tick": Sim.tick_no, "day": Sim.day, "event_digest": Sim.event_digest,
		"player": [String(player.get("space", "")), String(player.get("floor", "")), pos.x, pos.y,
			String(player.get("area", "")), String(player.get("room", ""))],
		"path_cache": Sim._path_cache, "town_stock": Sim.town_stock, "events": Sim.event_log})

func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame

func _capture(name: String) -> void:
	if _evidence_out == "":
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.get_width() <= 1 or image.get_height() <= 1:
		_ck(false, "evidence framebuffer is available for %s" % name)
		return
	var path := _evidence_out.path_join(name + ".png")
	var err := image.save_png(path)
	_ck(err == OK, "evidence frame written: %s" % name)
	_frames.append({"name": name, "path": path, "width": image.get_width(), "height": image.get_height(),
		"space": String(_main.get("_probe").active_space), "floor": String(_main.get("_probe").active_floor)})

func _ck(ok: bool, label: String) -> void:
	print("  %s  %s" % ["OK " if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _finish() -> void:
	if _evidence_out != "":
		var receipt := {"contract": "living-town-c1-cafe-projection-v1", "head": _evidence_head,
			"seed": SEED, "frames": _frames, "failures": _fails}
		var file := FileAccess.open(_evidence_out.path_join("receipt.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(receipt, "  "))
			file.close()
	print("c1_cafe_projection_test: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
