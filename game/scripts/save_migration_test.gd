extends Node
## Schema 1 → 2 migration gate. The fixture descriptor freezes the d46cbb1 shape; this scene
## writes/reads the real store_var envelope, pollutes a live receiver first, and proves atomic reject.

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
const CONTRACT_PATH := "res://fixtures/save_schema1_legacy_contract.json"

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func _read_envelope(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 8:
		return {}
	var header := f.get_32()
	var blob = f.get_var()
	f.close()
	return {"header": header, "blob": blob}

func _write_envelope(path: String, header: int, blob: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(header)
	f.store_var(blob)
	f.close()
	return true

func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK or ctx.update(bytes) != OK:
		return ""
	return ctx.finish().hex_encode().to_upper()

func _materialize_exact_fixture(contract: Dictionary, path: String) -> bool:
	var payload_parts = contract.get("payload_parts")
	if not (payload_parts is Array) or (payload_parts as Array).is_empty():
		return false
	var b64 := ""
	for raw_path in payload_parts:
		var payload_path := String(raw_path)
		if payload_path == "" or not FileAccess.file_exists(payload_path):
			return false
		b64 += FileAccess.get_file_as_string(payload_path).strip_edges()
	var compressed := Marshalls.base64_to_raw(b64)
	var raw := compressed.decompress(int(contract.get("source_bytes", -1)), FileAccess.COMPRESSION_GZIP)
	if raw.size() != int(contract.get("source_bytes", -1)) or _sha256_hex(raw) != String(contract.get("source_sha256", "")):
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(raw)
	f.close()
	return true

func _legacyize(path: String, contract: Dictionary, p1a_only: bool = false) -> bool:
	var env := _read_envelope(path)
	if not (env.get("blob") is Dictionary):
		return false
	var blob: Dictionary = (env["blob"] as Dictionary).duplicate(true)
	var state: Dictionary = blob.get("state", {})
	for key in contract.get("absent_state_keys", []):
		if p1a_only and String(key) == "core_population":
			continue
		state.erase(String(key))
	var logistics: Dictionary = state.get("logistics", {})
	logistics.erase("carriers")
	for raw_lane in logistics.get("import_lanes", []):
		if raw_lane is Dictionary:
			(raw_lane as Dictionary).erase("route_id")
	for raw_lane in logistics.get("export_lanes", []):
		if raw_lane is Dictionary:
			(raw_lane as Dictionary).erase("scale_floor")
	for raw_node in logistics.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node: Dictionary = raw_node
		if String(node.get("id", "")) != "port_dock":
			continue
		node["pos"] = [33, 8]
		if p1a_only:
			for raw_adv in node.get("advertises", []):
				if raw_adv is Dictionary:
					(raw_adv as Dictionary).erase("manifest_node")
		else:
			node.erase("advertises")
	var world: Dictionary = state.get("world", {})
	var areas: Dictionary = world.get("areas", {})
	areas.erase("north_pier")
	if areas.get("dock") is Dictionary:
		var dock: Dictionary = areas["dock"]
		dock["rect"] = [30, 7, 4, 2]
		for key in ["facing", "berth", "route_id", "population_anchor"]:
			dock.erase(key)
	var objects: Dictionary = world.get("objects", {})
	if p1a_only:
		var port: Dictionary = objects.get("port_dock", {})
		for raw_adv in port.get("advertises", []):
			if raw_adv is Dictionary:
				(raw_adv as Dictionary).erase("manifest_node")
	else:
		objects.erase("port_dock")
	var production: Dictionary = state.get("production", {})
	for raw_ws in production.get("worksites", []):
		if raw_ws is Dictionary and String((raw_ws as Dictionary).get("id", "")) == "bench_pier":
			(raw_ws as Dictionary)["area"] = "dock"
			(raw_ws as Dictionary)["pos"] = [31, 7]
	if p1a_only:
		for raw_ag in state.get("agents", []):
			if raw_ag is Dictionary and String((raw_ag as Dictionary).get("id", "")) == "tao":
				(raw_ag as Dictionary)["option"] = {"kind": "object", "action": "卸货", "target": "port_dock",
					"need": "fun", "amount": 46, "dur_total": 28, "remaining": 2, "phase": "use"}
	blob["state"] = state
	blob["schema"] = 1
	blob["meta"] = {"fixture": "d46cbb1" if not p1a_only else "p1a-only"}
	return _write_envelope(path, 1, blob)

func _unload_candidate_count(S, worker: Dictionary) -> int:
	var n := 0
	for cand in S._object_candidates(worker):
		if cand is Dictionary and String(cand.get("action", "")) == "卸货":
			n += 1
	return n

func _wage_unload_count(S) -> int:
	var n := 0
	for ev in S.event_log:
		if String(ev.get("type", "")) == "pay" and String(ev.get("note", "")) == "wage:卸货":
			n += 1
	return n

func _reject_is_atomic(path: String, label: String) -> void:
	var S = SimScript.new(); add_child(S); S.auto_run = false; S.start_new(991)
	S.day = 3; S._logi_import(); S.core_population = 59
	S.festival_active = "__receiver_poison__"
	var digest0 := Inv.digest(S)
	var event0 := int(S.event_digest)
	var cargo0: Dictionary = S.cargo_manifests.duplicate(true)
	var order0: Array = S.cargo_manifest_order.duplicate(true)
	ck(not S.load_game(path), label + " 被拒绝")
	ck(Inv.digest(S) == digest0 and int(S.event_digest) == event0 and S.cargo_manifests == cargo0
		and S.cargo_manifest_order == order0 and int(S.core_population) == 59
		and String(S.festival_active) == "__receiver_poison__",
		label + " 拒绝前后 live state 原子不变")

func _ready() -> void:
	var contract = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	ck(contract is Dictionary and int(contract.get("schema", -1)) == 1
		and String(contract.get("source_commit", "")) == "d46cbb132595185c3420bb4eb8fd7f28512baa85",
		"legacy fixture provenance/版本冻结")
	if not (contract is Dictionary):
		get_tree().quit(1); return

	var legacy_path := "user://save_migration_schema1.dat"
	ck(_materialize_exact_fixture(contract, legacy_path), "materialize exact d46cbb1 schema-1 bytes + SHA-256")
	var inspector = SimScript.new(); add_child(inspector); inspector.auto_run = false
	var legacy_head := inspector.peek_save(legacy_path)
	ck(int(legacy_head.get("schema", -1)) == 1 and bool(legacy_head.get("requires_migration", false)),
		"peek_save 识别 exact baseline 为可迁移 schema 1")

	# Main.quickload 在 live Sim 上执行：先污染 cargo/core，迁移必须显式覆盖，不能依赖脚本默认。
	var A = SimScript.new(); add_child(A); A.auto_run = false; A.start_new(77)
	A.day = 3; A._logi_import(); A.core_population = 59
	ck(not A.cargo_manifests.is_empty(), "接收实例污染夹具含 pending cargo")
	ck(A.load_game(legacy_path), "pre-P1 schema 1 可迁移加载")
	ck(A.cargo_manifests.is_empty() and A.cargo_manifest_order.is_empty() and int(A.core_population) == 12,
		"迁移显式清 receiver cargo/order 并从 12 个 core 推导人口")
	ck(A.agents.size() == 12 and not A.get_agent("tao") and not A.world.get("areas", {}).has("north_pier")
		and not A.logistics.has("carriers") and not (A.logistics.get("import_lanes", [])[0] as Dictionary).has("route_id"),
		"旧 agents/北港/route-less logistics 原样保留，不伪造 East Ocean 世界")

	var B = SimScript.new(); add_child(B); B.auto_run = false; B.start_new(123)
	B.day = 3; B._logi_import(); B.core_population = 41
	ck(B.load_game(legacy_path), "同一 legacy fixture 第二次迁移成功")
	var drift := -1
	for i in 300:
		A.tick(); B.tick()
		if Inv.digest(A) != Inv.digest(B) or A.event_digest != B.event_digest:
			drift = i; break
	ck(drift == -1, "两次 schema-1 迁移续跑 300 tick 确定一致 (drift=%d)" % drift)

	var v2_path := "user://save_migration_schema2_resave.dat"
	ck(A.save_game(v2_path, {"fixture": "migrated"}), "迁移态可重存 schema 2")
	var v2_head := A.peek_save(v2_path)
	ck(int(v2_head.get("schema", -1)) == 2 and not bool(v2_head.get("requires_migration", true)),
		"重存后 peek_save 报 current schema")
	var C = SimScript.new(); add_child(C); C.auto_run = false
	ck(C.load_game(v2_path) and Inv.digest(C) == Inv.digest(A) and C.event_digest == A.event_digest,
		"迁移态 schema-2 round-trip 无漂移")

	# P1-a-only schema 1：有普通卸货广告/corePopulation，但没有 cargo pair。迁移必须同时门掉
	# saved logistics 与 compiled world，避免只清一次 option 后下一 tick 又 ghost-unload。
	var ghost_path := "user://save_migration_p1a_ghost.dat"
	var G = SimScript.new(); add_child(G); G.auto_run = false; G.start_new(88)
	ck(G.save_game(ghost_path, {"fixture": "p1a"}) and _legacyize(ghost_path, contract, true),
		"写出 P1-a-only schema-1 ghost 形状")
	var H = SimScript.new(); add_child(H); H.auto_run = false
	ck(H.load_game(ghost_path), "P1-a-only schema 1 安全迁移")
	var htao: Dictionary = H.get_agent("tao")
	var wage0 := _wage_unload_count(H)
	ck(htao.get("option") == null and _unload_candidate_count(H, htao) == 0,
		"旧未授权 option 清空且普通卸货广告改成空 cargo 门")
	for i in 720:
		H.tick()
	ck(H.cargo_manifests.is_empty() and _wage_unload_count(H) == wage0,
		"P1-a-only route-less 档续跑 3 天仍零 cargo/零卸货工资")

	# Runtime handles are receiver-owned: save never writes them, load never nulls an injected service.
	var handle_path := "user://save_migration_handles.dat"
	var HandleSrc = SimScript.new(); add_child(HandleSrc); HandleSrc.auto_run = false; HandleSrc.start_new(3)
	HandleSrc.add_player(Vector2i(57, 8))
	ck(HandleSrc.save_game(handle_path), "runtime-handle schema-2 fixture 写盘")
	var handle_env := _read_envelope(handle_path)
	var handle_state: Dictionary = (handle_env.get("blob", {}) as Dictionary).get("state", {})
	ck(not handle_state.has("backend") and not handle_state.has("ext") and not handle_state.has("decision_sink"),
		"schema 2 永不序列化 runtime handles")
	var expected_state_keys: Dictionary = HandleSrc._current_save_state_keys()
	ck(handle_state.size() == expected_state_keys.size()
		and expected_state_keys.keys().all(func(key): return handle_state.has(key)),
		"schema 2 state 字段集合逐项等于当前保存器合同")
	var current_blob: Dictionary = handle_env.get("blob", {})
	var every_envelope_missing_rejected := true
	for key in SimScript.SAVE_CURRENT_BLOB_KEYS:
		var missing_envelope: Dictionary = current_blob.duplicate(true)
		missing_envelope.erase(key)
		if HandleSrc._validate_current_save_shape(missing_envelope) == "":
			every_envelope_missing_rejected = false
			break
	ck(every_envelope_missing_rejected, "schema 2 任一 current envelope 字段缺失均 fail-closed")
	var every_missing_rejected := true
	for key in expected_state_keys:
		var missing_state: Dictionary = handle_state.duplicate(true)
		missing_state.erase(key)
		if HandleSrc._validate_loaded_state(missing_state, 2) == "":
			every_missing_rejected = false
			break
	ck(every_missing_rejected, "schema 2 任一当前 state 字段缺失均 fail-closed")
	var HandleDst = SimScript.new(); add_child(HandleDst); HandleDst.auto_run = false
	var service := Node.new(); add_child(service)
	HandleDst.backend = service; HandleDst.ext = service
	var sink := func(_ag, _cands, _pick): pass
	HandleDst.decision_sink = sink
	ck(HandleDst.load_game(handle_path) and HandleDst.backend == service and HandleDst.ext == service
		and HandleDst.decision_sink == sink, "load 保留接收实例 runtime handles")

	# P1-p: current-schema portal topology and agent addresses are authority, not mutable caches.
	# Every forged envelope must disappear from peek and reject before the polluted receiver changes.
	var portal_attack_paths: Array = []
	var portal_specs := [
		{"name": "id", "field": "id", "value": "p_cafe_stairs_forged"},
		{"name": "access", "field": "access", "value": "public"},
		{"name": "bidirectional", "field": "bidirectional", "value": false},
		{"name": "cost", "field": "traversal_cost", "value": 1.0},
		{"name": "from", "field": "from", "value": {"space": "town", "floor": "outdoor", "pos": [41.0, 19.0]}},
		{"name": "to", "field": "to", "value": {"space": "cafe", "floor": "1f", "pos": [1.0, 1.0]}},
	]
	for spec in portal_specs:
		var path := "user://save_migration_p1p_portal_%s.dat" % String(spec["name"])
		portal_attack_paths.append(path)
		var attack_blob: Dictionary = (handle_env["blob"] as Dictionary).duplicate(true)
		for raw_portal in (attack_blob["state"] as Dictionary)["_portals"]:
			if String((raw_portal as Dictionary).get("id", "")) == "p_cafe_stairs":
				(raw_portal as Dictionary)[String(spec["field"])] = spec["value"]
		ck(_write_envelope(path, 2, attack_blob), "schema-2 forged portal %s fixture 写盘" % spec["name"])
		ck(HandleSrc.peek_save(path).is_empty(), "peek_save 隐藏 forged portal %s" % spec["name"])
		_reject_is_atomic(path, "schema-2 forged portal %s" % spec["name"])

	var player_attack_paths: Array = []
	var player_specs := [
		{"name": "home_space", "field": "home_space", "value": "cafe"},
		{"name": "home_floor", "field": "home_floor", "value": "1f"},
		{"name": "position", "field": "pos", "value": Vector2i(-1, -1)},
		{"name": "area", "field": "area", "value": "cafe:2f"},
		{"name": "room", "field": "room", "value": "hall"},
	]
	for spec in player_specs:
		var path := "user://save_migration_p1p_player_%s.dat" % String(spec["name"])
		player_attack_paths.append(path)
		var attack_blob: Dictionary = (handle_env["blob"] as Dictionary).duplicate(true)
		for raw_agent in (attack_blob["state"] as Dictionary)["agents"]:
			if String((raw_agent as Dictionary).get("id", "")) == "player":
				(raw_agent as Dictionary)[String(spec["field"])] = spec["value"]
		ck(_write_envelope(path, 2, attack_blob), "schema-2 forged player %s fixture 写盘" % spec["name"])
		ck(HandleSrc.peek_save(path).is_empty(), "peek_save 隐藏 forged player %s" % spec["name"])
		_reject_is_atomic(path, "schema-2 forged player %s" % spec["name"])
	var coherent_location := "user://save_migration_p1p_player_authorized_component.dat"
	player_attack_paths.append(coherent_location)
	var coherent_blob: Dictionary = (handle_env["blob"] as Dictionary).duplicate(true)
	for raw_agent in (coherent_blob["state"] as Dictionary)["agents"]:
		if String((raw_agent as Dictionary).get("id", "")) == "player":
			var player: Dictionary = raw_agent
			player["space"] = "cafe"; player["floor"] = "2f"; player["pos"] = Vector2i(1, 1)
			player["area"] = "cafe:2f"; player["room"] = ""
	ck(_write_envelope(coherent_location, 2, coherent_blob), "schema-2 coherent unauthorized player address fixture 写盘")
	ck(HandleSrc.peek_save(coherent_location).is_empty(), "peek_save 隐藏几何合法但权限不可达的 player 地址")
	_reject_is_atomic(coherent_location, "schema-2 player outside authored authorized component")

	# Four malformed envelopes, all rejected before touching a polluted live receiver.
	var good_env := _read_envelope(legacy_path)
	var mismatch := "user://save_migration_bad_mismatch.dat"
	ck(_write_envelope(mismatch, 2, (good_env["blob"] as Dictionary).duplicate(true)), "header/blob mismatch fixture 写盘")
	_reject_is_atomic(mismatch, "header/blob schema mismatch")
	var partial := "user://save_migration_bad_partial.dat"
	var partial_blob: Dictionary = (good_env["blob"] as Dictionary).duplicate(true)
	(partial_blob["state"] as Dictionary)["cargo_manifests"] = {}
	ck(_write_envelope(partial, 1, partial_blob), "partial cargo fixture 写盘")
	_reject_is_atomic(partial, "partial cargo pair")
	var unknown := "user://save_migration_bad_unknown.dat"
	var unknown_blob: Dictionary = (good_env["blob"] as Dictionary).duplicate(true)
	(unknown_blob["state"] as Dictionary)["__unknown_authority"] = 1
	ck(_write_envelope(unknown, 1, unknown_blob), "unknown-key fixture 写盘")
	_reject_is_atomic(unknown, "unknown state key")
	var wrong_type := "user://save_migration_bad_type.dat"
	var type_blob: Dictionary = (good_env["blob"] as Dictionary).duplicate(true)
	(type_blob["state"] as Dictionary)["tick_no"] = "160"
	ck(_write_envelope(wrong_type, 1, type_blob), "wrong-type fixture 写盘")
	_reject_is_atomic(wrong_type, "wrong scalar type")
	var v2_env := _read_envelope(v2_path)
	var bad_core := "user://save_migration_bad_core.dat"
	var core_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	(core_blob["state"] as Dictionary)["core_population"] = 11
	ck(_write_envelope(bad_core, 2, core_blob), "schema-2 bad-core fixture 写盘")
	_reject_is_atomic(bad_core, "schema-2 core_population mismatch")
	var bad_cargo := "user://save_migration_bad_cargo.dat"
	var cargo_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	(cargo_blob["state"] as Dictionary)["cargo_manifests"] = {}
	(cargo_blob["state"] as Dictionary)["cargo_manifest_order"] = ["dangling_manifest"]
	ck(_write_envelope(bad_cargo, 2, cargo_blob), "schema-2 bad-cargo fixture 写盘")
	_reject_is_atomic(bad_cargo, "schema-2 dangling cargo order")
	var bad_flag := "user://save_migration_bad_flag.dat"
	var flag_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	((flag_blob["state"] as Dictionary)["agents"] as Array)[0]["affiliate"] = 0
	ck(_write_envelope(bad_flag, 2, flag_blob), "schema-2 bad-agent-flag fixture 写盘")
	_reject_is_atomic(bad_flag, "schema-2 non-bool affiliate flag")
	var missing_current := "user://save_migration_missing_current.dat"
	var missing_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	(missing_blob["state"] as Dictionary).erase("festival_active")
	ck(_write_envelope(missing_current, 2, missing_blob), "schema-2 missing-current-field fixture 写盘")
	ck(A.peek_save(missing_current).is_empty(), "peek_save 不把 missing-current 坏档列为可加载")
	_reject_is_atomic(missing_current, "schema-2 missing current authoritative field")
	var missing_active_ids := "user://save_migration_missing_active_ids.dat"
	var active_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	active_blob.erase("active_commit_ids")
	ck(_write_envelope(missing_active_ids, 2, active_blob), "schema-2 missing-active-ids fixture 写盘")
	ck(A.peek_save(missing_active_ids).is_empty(), "peek_save 不把 missing-active-ids 坏档列为可加载")
	_reject_is_atomic(missing_active_ids, "schema-2 missing active commitment membership")
	var extra_current := "user://save_migration_extra_current.dat"
	var extra_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	(extra_blob["state"] as Dictionary)["backend"] = null
	ck(_write_envelope(extra_current, 2, extra_blob), "schema-2 extra-runtime-handle fixture 写盘")
	ck(A.peek_save(extra_current).is_empty(), "peek_save 不把 extra-state 坏档列为可加载")
	_reject_is_atomic(extra_current, "schema-2 extra current state field")
	var extra_envelope := "user://save_migration_extra_envelope.dat"
	var envelope_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	envelope_blob["__future_envelope"] = 1
	ck(_write_envelope(extra_envelope, 2, envelope_blob), "schema-2 extra-envelope fixture 写盘")
	ck(A.peek_save(extra_envelope).is_empty(), "peek_save 不把 extra-envelope 坏档列为可加载")
	_reject_is_atomic(extra_envelope, "schema-2 extra envelope field")
	var lying_header := "user://save_migration_lying_header.dat"
	var lying_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	lying_blob["saved_tick"] = int(lying_blob.get("saved_tick", 0)) + 1
	ck(_write_envelope(lying_header, 2, lying_blob), "schema-2 lying-header fixture 写盘")
	ck(A.peek_save(lying_header).is_empty(), "peek_save 不展示与 state 不符的头信息")
	_reject_is_atomic(lying_header, "schema-2 envelope/state metadata mismatch")
	var dangling_active := "user://save_migration_dangling_active.dat"
	var dangling_blob: Dictionary = (v2_env["blob"] as Dictionary).duplicate(true)
	dangling_blob["active_commit_ids"] = [2147483647]
	ck(_write_envelope(dangling_active, 2, dangling_blob), "schema-2 dangling-active fixture 写盘")
	ck(A.peek_save(dangling_active).is_empty(), "peek_save 不展示悬空 active commitment 档")
	_reject_is_atomic(dangling_active, "schema-2 dangling active commitment")

	for path in [legacy_path, v2_path, ghost_path, handle_path, mismatch, partial, unknown, wrong_type, bad_core, bad_cargo, bad_flag, missing_current, missing_active_ids, extra_current, extra_envelope, lying_header, dangling_active] + portal_attack_paths + player_attack_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("save_migration_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
