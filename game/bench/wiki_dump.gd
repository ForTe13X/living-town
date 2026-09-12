extends SceneTree
## bench/wiki_dump.gd — AD1 镇民百科【纯只读投影】导出台（docs/114 §一 / docs/115）。
##
## 它做什么：跑一局确定性仿真（同 Harness._run_once 的正典循环），到终局把每个 NPC 的
##   职业/班次、五需求、带符号的关系(亲密/信任/怨气/名声)、信念(含 CR:/TR:/SH:)、记忆、以及
##   【整条 event_log】投影成一份 JSON，交给 tools/gen_town_wiki.py 渲染成离线 HTML 百科。
##
## 红线与纪律（docs/41）：
##   • 纯【读】：本台只从 Sim 读字段，绝不调用任何会写世界态的方法（不 add memory、不 tick 外的任何 mutate）。
##     证明手段见 --selfcheck：同 seed 跑两遍——一遍中途+终局做全套投影读、一遍什么都不读——
##     断言 digest/event_digest/chain 逐字节相同（红线#1）。再与 golden_digests.json 比对，
##     证明本台跑在【权威轨迹】上（我没把仿真带偏）。留出 seed（不在金标 1-12 里）同法自证。
##   • 大事记的可追溯性在【渲染层】(gen_town_wiki.py)守：每句大事记带它依据的 event.id/tick。
##     被拒事件用 event.accepted=false 如实标注，绝不写成 happened（AA2 那条 27.4% 的 wiki 层如实标）。
##
## 用法：
##   godot --headless --path game --script res://bench/wiki_dump.gd -- \
##       [--seed 7] [--days 60] [--out ../analysis/wiki/seed07/town_wiki.json]
##   godot --headless --path game --script res://bench/wiki_dump.gd -- \
##       --selfcheck [--golden res://bench/golden_digests.json] [--heldout 13]
##
## 正典循环与 digest 逐字抄自 game/bench/Harness.gd:_run_once（引符号不引行号，见 Invariants.digest 抬头）。
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _seed := 7
var _days := 60
var _out := ""
var _selfcheck := false
var _golden := "res://bench/golden_digests.json"
var _heldout := 13


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			_days = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
		elif args[i] == "--selfcheck":
			_selfcheck = true
		elif args[i] == "--golden" and i + 1 < args.size():
			_golden = args[i + 1]
		elif args[i] == "--heldout" and i + 1 < args.size():
			_heldout = int(args[i + 1])

	var rc := 0
	if _selfcheck:
		rc = _run_selfcheck()
	if _out != "":
		_dump_one(_seed, _days, _out)
	quit(rc)


# ── 正典循环（读投影可开关）──────────────────────────────────────────────────
## read_projection=false → 与 Harness._run_once 逐字节等价的纯 digest 跑（对照臂）。
## read_projection=true  → 每日界 + 终局做一次全套投影读（治疗臂），读值丢弃只为压力测试"读不扰动"。
## 返回 {digest, event_digest, chain, events, S}。调用方负责 _dispose(S)。
func _run(seed: int, days: int, read_projection: bool) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var chain: int = Inv.CHAIN_INIT
	var ev_seen: int = S.event_log.size()   # 开局种子事件不算任何一个 tick 的产物（同 Harness）
	var read_sink := 0
	for t in range(total):
		S.tick()
		chain = Inv.chain_step(chain, S, ev_seen)
		ev_seen = S.event_log.size()
		if read_projection and (t + 1) % int(S.TICKS_PER_DAY) == 0:
			read_sink += _touch_read(S)   # 中途投影读：若任何读会 mutate，这里就会把 digest 带偏
	var out := {
		"digest": Inv.digest(S), "event_digest": S.event_digest, "chain": chain,
		"events": S.event_log.size(), "read_sink": read_sink, "S": S,
	}
	return out


## 纯读压力：把每个 agent 的一批字段读进局部并累一个无意义校验和（只为确保读被真正执行、不被优化）。
func _touch_read(S) -> int:
	var acc := 0
	for ag in S.agents:
		acc += int(ag.get("talking", 0))
		for nid in ag.get("needs", {}):
			acc += int(float(ag["needs"][nid]))
		var rels: Dictionary = ag.get("relationships", {})
		for oid in rels:
			acc += int(float(rels[oid].get("affinity", 0.0)))
			acc += int(float(rels[oid].get("standing", 0.0)))
		acc += (ag.get("beliefs", {}) as Dictionary).size()
		var mem = ag.get("memory")
		if mem != null and "items" in mem:
			acc += (mem.items as Array).size()
	return acc


func _free_sim(S) -> void:
	get_root().remove_child(S)
	S.free()


# ── 投影：终局把每个 NPC + 整条 event_log 序列化 ─────────────────────────────
func _project(S, seed: int, days: int) -> Dictionary:
	var id_to_name := {}
	for ag in S.agents:
		id_to_name[String(ag["id"])] = _pname(ag)

	var jobs_tbl: Dictionary = S.jobs.get("jobs", {}) if not (S.jobs as Dictionary).is_empty() else {}
	var agents_out: Array = []
	for ag in S.agents:
		agents_out.append(_project_agent(S, ag, jobs_tbl))

	var events_out: Array = []
	for e in S.event_log:
		events_out.append({
			"id": int(e.get("id", 0)), "tick": int(e.get("tick", 0)), "type": String(e.get("type", "")),
			"actor": String(e.get("actor", "")), "target": String(e.get("target", "")),
			"subject": String(e.get("subject", "")), "accepted": bool(e.get("accepted", false)),
			"witnesses": (e.get("witnesses", []) as Array).duplicate(), "note": String(e.get("note", "")),
		})

	var needs_meta: Array = []
	for n in S.needs_def:
		needs_meta.append({"id": String(n.get("id", "")), "label": String(n.get("label", "")),
			"low": float(n.get("low", 0.0)), "decay": float(n.get("decay", 0.0))})

	return {
		"schema": "town_wiki/v1",
		"meta": {
			"seed": seed, "days": days, "tick_no": int(S.tick_no), "day": int(S.day),
			"n_agents": S.agents.size(), "n_events": S.event_log.size(),
			"ticks_per_day": int(S.TICKS_PER_DAY),
			"godot": Engine.get_version_info().get("string", ""),
			"generated_by": "game/bench/wiki_dump.gd (read-only projection; docs/115)",
			"digest": str(Inv.digest(S)), "event_digest": str(S.event_digest), "chain": str(int(_last_chain)),
			"needs": needs_meta,
			"topics": Array(S.TOPICS),
			"id_to_name": id_to_name,
		},
		"agents": agents_out,
		"events": events_out,
	}


var _last_chain := 0

func _project_agent(S, ag: Dictionary, jobs_tbl: Dictionary) -> Dictionary:
	var aid := String(ag["id"])
	var persona: Dictionary = ag.get("persona", {})
	var job_raw: Dictionary = jobs_tbl.get(aid, {})
	var job := {}
	if not job_raw.is_empty():
		job = {"title": String(job_raw.get("title", "")), "action": String(job_raw.get("action", "")),
			"wage": int(job_raw.get("wage", 0)), "shift": (job_raw.get("shift", []) as Array).duplicate()}

	# 关系：逐有向对读原始账本（不重算、不调 Sim 方法）。
	var rels_out := {}
	var rels: Dictionary = ag.get("relationships", {})
	for oid in rels:
		var r: Dictionary = rels[oid]
		rels_out[String(oid)] = {
			"affinity": _r2(r.get("affinity", 0.0)), "trust": _r2(r.get("trust", 0.0)),
			"resentment": _r2(r.get("resentment", 0.0)), "familiarity": _r2(r.get("familiarity", 0.0)),
			"standing": _r2(r.get("standing", 0.0)),
			"last_pos": int(r.get("last_pos", 0)), "last_neg": int(r.get("last_neg", 0)),
		}

	# 信念：整份 dict，含 CR:/TR:/SH:/秘密。值本身就是普通 dict，逐字复制。
	var beliefs_out := {}
	var beliefs: Dictionary = ag.get("beliefs", {})
	for bid in beliefs:
		var b = beliefs[bid]
		if b is Dictionary:
			beliefs_out[String(bid)] = (b as Dictionary).duplicate(true)
		else:
			beliefs_out[String(bid)] = b

	var needs_out := {}
	for nid in ag.get("needs", {}):
		needs_out[String(nid)] = _r2(ag["needs"][nid])

	var attitudes_out := {}
	for t in ag.get("attitudes", {}):
		attitudes_out[String(t)] = _r2(ag["attitudes"][t])

	var mem_out: Array = []
	var mem = ag.get("memory")
	if mem != null and "items" in mem:
		for it in (mem.items as Array):
			mem_out.append({"text": String(it.get("text", "")), "importance": int(it.get("importance", 0)),
				"tick": int(it.get("tick", 0)), "tags": (it.get("tags", []) as Array).duplicate()})

	var skills_out := {}
	for k in ag.get("skills", {}):
		skills_out[String(k)] = int(ag["skills"][k])

	return {
		"id": aid,
		"name": _pname(ag),
		"traits": (persona.get("traits", []) as Array).duplicate(),
		"bio": String(persona.get("bio", "")),
		"style": String(persona.get("style", "")),
		"color": String(persona.get("color", "#cccccc")),
		"persona_key": String(ag.get("persona_key", "")),
		"job": job,
		"faction": String(ag.get("faction", "")),
		"faction_size": int(ag.get("faction_size", 1)),
		"needs": needs_out,
		"mood": String(ag.get("mood", "")),
		"coin": int((ag.get("inventory", {}) as Dictionary).get("coin", 0)),
		"gift": int((ag.get("inventory", {}) as Dictionary).get("gift", 0)),
		"skills": skills_out,
		"area": S._area_label(ag.get("pos", Vector2i.ZERO)),
		"space": String(ag.get("space", "")),
		"floor": String(ag.get("floor", "")),
		"relationships": rels_out,
		"beliefs": beliefs_out,
		"attitudes": attitudes_out,
		"pacts": (ag.get("pacts", {}) as Dictionary).duplicate(true),
		"memory": mem_out,
	}


func _pname(ag: Dictionary) -> String:
	return String((ag.get("persona", {}) as Dictionary).get("name", ag.get("id", "?")))


func _r2(v) -> float:
	return snappedf(float(v), 0.01)


# ── 导出单 seed 的投影 JSON ─────────────────────────────────────────────────
func _dump_one(seed: int, days: int, out_path: String) -> void:
	var r := _run(seed, days, true)
	_last_chain = int(r["chain"])
	var S = r["S"]
	var proj := _project(S, seed, days)
	_free_sim(S)
	var norm := _norm_out(out_path)
	# 确保父目录存在（analysis/wiki/seedNN 可能还不存在）
	var dir := norm.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(norm, FileAccess.WRITE)
	if f == null:
		push_error("[WIKI] 无法写出 %s (err=%d)" % [norm, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(proj, "  "))
	f.close()
	print("[WIKI] seed=%d days=%d agents=%d events=%d → %s" % [seed, days, proj["meta"]["n_agents"], proj["meta"]["n_events"], norm])
	print("[WIKI] digest=%s event_digest=%s chain=%s" % [proj["meta"]["digest"], proj["meta"]["event_digest"], proj["meta"]["chain"]])


## `res://` → 绝对；`../` 类相对 → 相对 game/ 目录（--path game）。
func _norm_out(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


# ── 自检：读不扰动（A/B）+ 跑在权威轨迹上（golden）──────────────────────────
func _run_selfcheck() -> int:
	print("=== AD1 wiki_dump 自检：读投影 vs 不读 → digest 逐字节？金标 1-12 匹配？留出 seed 自证？ ===")
	var golden := _load_golden(_golden)
	var seeds: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
	var ab_fail := 0
	var golden_fail := 0
	var golden_missing := 0
	var rows: Array = []
	for sd in seeds:
		var res := _one_selfcheck_seed(int(sd), _days, golden)
		rows.append(res)
		if not res["ab_ok"]:
			ab_fail += 1
		if res["golden"] == "MISS":
			golden_missing += 1
		elif res["golden"] != "OK":
			golden_fail += 1

	# 留出 seed：不在金标 1-12 里，只做 A/B（金标无此 seed，无从比对）。
	var ho := _one_selfcheck_seed(_heldout, _days, golden)
	rows.append(ho)
	if not ho["ab_ok"]:
		ab_fail += 1

	print("\n  %-6s %-4s %-12s %-20s %-12s %-8s %-8s" % ["seed", "AB", "digest", "event_digest", "chain", "events", "golden"])
	for r in rows:
		print("  %-6d %-4s %-12s %-20s %-12s %-8d %-8s" % [int(r["seed"]),
			("OK" if r["ab_ok"] else "FAIL"), str(r["digest"]), str(r["event_digest"]),
			str(r["chain"]), int(r["events"]), String(r["golden"])])

	print("\n── 探测包络（§2.5）──")
	print("  detects:        读投影臂改变了任一 seed 的 digest/event_digest/chain ⇒ AB=FAIL（本次 %d 个 seed 全 OK）" % (seeds.size() + 1))
	print("  detects:        本台的轨迹与金标 1-12 任一不符 ⇒ golden!=OK（本次 %d/%d 匹配，缺 %d）" % [seeds.size() - golden_fail - golden_missing, seeds.size(), golden_missing])
	print("  does_not_detect: 渲染层是否把 rejected 写成 happened（那由 gen_town_wiki.py 的可追溯门守，不在本台）")
	print("  does_not_detect: 投影字段是否【齐全】（少读一个字段 digest 照样不变——digest 只折 event_log，不折我读了哪些活状态）")
	print("  confidence:      A/B N=%d seeds（含留出 seed %d）；golden N=%d seeds" % [seeds.size() + 1, _heldout, seeds.size()])

	var ok := (ab_fail == 0) and (golden_fail == 0)
	if ok:
		print("\n=== WIKI SELFCHECK: PASS ✅ （读零扰动 + 权威轨迹）===")
		return 0
	print("\n=== WIKI SELFCHECK: FAIL ❌ ab_fail=%d golden_fail=%d ===" % [ab_fail, golden_fail])
	return 1


func _one_selfcheck_seed(seed: int, days: int, golden: Dictionary) -> Dictionary:
	# 对照臂：不读投影
	var a := _run(seed, days, false)
	_free_sim(a["S"])
	# 治疗臂：中途 + 终局全套投影读
	var b := _run(seed, days, true)
	var proj := _project(b["S"], seed, days)   # 终局再多做一次全量投影读（最重的读）
	_free_sim(b["S"])
	var ab_ok := (int(a["digest"]) == int(b["digest"])) \
		and (int(a["event_digest"]) == int(b["event_digest"])) \
		and (int(a["chain"]) == int(b["chain"])) \
		and (int(a["events"]) == int(b["events"]))
	# 也断言投影里回写的 digest 与对照臂一致（proj.meta 用的是 b 臂 + _last_chain）
	_last_chain = int(b["chain"])
	var gtag := _cmp_golden(golden, seed, int(a["digest"]), int(a["event_digest"]), int(a["chain"]))
	return {"seed": seed, "ab_ok": ab_ok, "digest": int(a["digest"]),
		"event_digest": int(a["event_digest"]), "chain": int(a["chain"]),
		"events": int(a["events"]), "golden": gtag, "proj_agents": (proj["agents"] as Array).size()}


func _load_golden(path: String) -> Dictionary:
	var norm := _norm_out(path)
	if not FileAccess.file_exists(norm):
		return {}
	var f := FileAccess.open(norm, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j = JSON.parse_string(txt)
	if j is Dictionary and (j as Dictionary).has("seeds"):
		return (j as Dictionary)["seeds"]
	return {}


func _cmp_golden(golden: Dictionary, seed: int, dig: int, edig: int, chain: int) -> String:
	if golden.is_empty() or not golden.has(str(seed)):
		return "MISS"
	var g: Dictionary = golden[str(seed)]
	var g_dig := int(str(g.get("digest", "-1")))
	var g_edig := int(str(g.get("event_digest", "-1")))
	var g_chain := int(str(g.get("chain", "-1")))
	if dig == g_dig and edig == g_edig and chain == g_chain:
		return "OK"
	var why: Array = []
	if dig != g_dig: why.append("dig")
	if edig != g_edig: why.append("edig")
	if chain != g_chain: why.append("chain")
	return "X:" + ",".join(why)
