extends SceneTree
## scriptwriter.gd — V1「70B 夜间/周更编剧」离线工具（docs/15 §2.4 确定性接法：70B 产出不进 sim）。
## 离线异步管线：读镇情 → 提示 70B → 拿 JSON 剧本 → schema 校验+净化 → 冻结落盘 data/scenarios/<out>.json。
## 之后 sim --scenario <out> 经 DataScenarioProvider 【确定性】注入 → 逐字节可回放。LLM 的非确定被隔离在本工具内，
## 一旦冻结成数据，回放读同一 JSON → digest 不破。本工具自带"同剧本两跑逐字节一致"自检坐实这一点。
## （运行期 TownDirector 见 director.gd，是另一回事：本工具在【引擎外】离线产出数据。）
##
## 用法：godot --headless --path . --script res://scripts/scriptwriter.gd -- \
##        --seed 20260626 --out director_1 [--model llama-3.3-70b-instruct] [--mock] [--days 30] \
##        [--endpoint http://127.0.0.1:1234/v1/chat/completions]
##   --mock：跳过 LLM，写一份确定性罐头剧本（快速验证管线+确定性，无需真模型）。

const SimScript = preload("res://scripts/Sim.gd")
const SimExt = preload("res://scripts/SimExtensions.gd")
const DataScen = preload("res://scripts/DataScenarioProvider.gd")
const Inv = preload("res://bench/Invariants.gd")

var _endpoint := "http://127.0.0.1:1234/v1/chat/completions"
var _model := "llama-3.3-70b-instruct"

func _init() -> void:
	_run.call_deferred()   # 延到 idle 帧：此时 SceneTree 在跑，可 await HTTP

func _run() -> void:
	var seed := 20260626
	var out_id := "director_1"
	var mock := false
	var days := 30
	var recurring := 0     # >0：周更编剧 N 周（离线编排：跑一段→快照→70B→冻进 schedule→再跑）
	var interval := 7      # 每几天一次编剧介入
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var nx: String = args[i + 1] if i + 1 < args.size() else ""
		if args[i] == "--seed": seed = int(nx)
		elif args[i] == "--out": out_id = nx
		elif args[i] == "--model": _model = nx
		elif args[i] == "--endpoint": _endpoint = nx
		elif args[i] == "--days": days = int(nx)
		elif args[i] == "--recurring": recurring = int(nx)
		elif args[i] == "--interval": interval = maxi(1, int(nx))
		elif args[i] == "--mock": mock = true

	if recurring > 0:
		await _orchestrate(seed, recurring, interval, out_id, mock)
		return

	# 1) 载入一局干净镇（无场景）→ 提炼镇情摘要供编剧
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(seed)
	var summary := _town_summary(S)
	print("=== Scriptwriter  seed=%d  out=%s  model=%s  mock=%s ===" % [seed, out_id, _model, str(mock)])
	print("镇情：\n" + summary)

	# 2) 生成剧本 JSON（mock=罐头确定性；live=HTTP 调 70B）
	var raw: Dictionary
	if mock:
		raw = _mock_script()
	else:
		print("→ 调用 70B（离线，可能 2-3 分钟）…")
		raw = await _generate(summary)
	if raw.is_empty():
		print("❌ 生成失败/空剧本")
		quit(1); return

	# 3) 校验+净化（绝不信任 LLM 原样输出：只留合法 id/话题/字段，越界钳制）→ 冻结落盘
	var clean := _validate(raw, S)
	if (clean.get("agents", []) as Array).is_empty():
		print("❌ 净化后无有效补丁（LLM 用了未知 id/话题？）")
		quit(1); return
	var path := "res://data/scenarios/%s.json" % out_id
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("❌ 写盘失败: " + path)
		quit(1); return
	f.store_string(JSON.stringify(clean, "  "))
	f.close()
	print("✅ 剧本已冻结 → res://data/scenarios/%s.json" % out_id)
	print(JSON.stringify(clean, "  "))

	# 4) 确定性自检：同一冻结剧本，同 seed 两跑 → digest+event_digest 必须逐字节一致（capstone 铁证）
	var d1 := _run_scenario(out_id, seed, days)
	var d2 := _run_scenario(out_id, seed, days)
	var ok: bool = d1[0] == d2[0] and d1[1] == d2[1]
	print("确定性自检（%d 天·同剧本两跑）：digest %d/%d  vs  %d/%d → %s" % [
		days, d1[0], d1[1], d2[0], d2[1], "✅ 逐字节一致（回放不破）" if ok else "❌ 漂移"])
	quit(0 if ok else 1)

## 提炼给编剧看的镇情（居民+性格）。
func _town_summary(S) -> String:
	var lines: Array = []
	for ag in S.agents:
		var p: Dictionary = ag.get("persona", {})
		var traits: Array = p.get("traits", [])
		lines.append("- id=%s 名=%s 性格=[%s]" % [ag["id"], S._name(ag), ", ".join(traits)])
	return "\n".join(lines)

func _sys_prompt() -> String:
	return "你是一个像素小镇生活模拟游戏的『编剧/导演』。角色的具体行动由确定性引擎自主演绎——你不替他们行动，只在开局埋下戏剧张力：观点分歧、恩怨、暗恋、秘密、派系倾向。你的唯一产出是【严格合法的 JSON】，符合给定 schema，不要任何解释、不要 markdown 围栏、不要多余文字。"

func _user_prompt(summary: String, ids: String, topics: String) -> String:
	return "小镇居民：\n%s\n\n合法角色 id：%s\n合法话题（attitudes 键）：%s\n\nJSON schema（字段全可选）：\n{\n  \"harmony\": true,\n  \"agents\": [\n    { \"id\": \"<合法id>\",\n      \"attitudes\": { \"<合法话题>\": <-1..1> },\n      \"relationships\": { \"<另一合法id>\": { \"affinity\": <-100..100>, \"trust\": <-100..100>, \"standing\": <-100..100>, \"resentment\": <0..100> } },\n      \"beliefs\": [ { \"id\": \"<唯一串,如 S_x/R_x>\", \"claim\": \"<一句话中文>\", \"subject\": \"<合法id>\", \"secret\": true } ]\n    }\n  ]\n}\n\n要求：①只用上面列出的 id 与话题；②埋 1–2 段恩怨或分歧（用 relationships，负 affinity/加 resentment）；③至少 1 条观点倾向（attitudes）；④可选 1 条秘密(secret:true, subject=本人)或谣言(secret 省略)；⑤张力可信、有戏、克制。只输出 JSON。" % [summary, ids, topics]

## 罐头确定性剧本（--mock）：不调模型，直接给一份合法戏剧设定，验证管线+确定性。
func _mock_script() -> Dictionary:
	return {
		"harmony": true,
		"agents": [
			{"id": "aria", "attitudes": {"cafe_expand": 0.9},
				"relationships": {"ben": {"affinity": -25.0, "standing": -3.0, "resentment": 14.0}}},
			{"id": "ben", "attitudes": {"cafe_expand": -0.85},
				"relationships": {"aria": {"affinity": -20.0, "resentment": 10.0}}},
			{"id": "coco", "beliefs": [
				{"id": "S_mock_coco", "claim": "可可偷偷记着一笔没跟人说的旧账", "subject": "coco", "secret": true}]},
			{"id": "dan", "attitudes": {"night_market": 0.7}}
		]
	}

## HTTP 调 LM Studio（OpenAI 兼容）。70B 慢 → 长 timeout。返回解析后的 JSON dict（失败=空）。
func _generate(summary: String) -> Dictionary:
	var ids := ", ".join(["aria", "ben", "coco", "dan", "evy", "fei"])
	var topics := ", ".join(["cafe_expand", "night_market", "old_tales"])
	var http := HTTPRequest.new()
	get_root().add_child(http)
	http.timeout = 600.0
	var body := {"model": _model, "temperature": 0.9, "max_tokens": 1400, "stream": false,
		"messages": [{"role": "system", "content": _sys_prompt()},
			{"role": "user", "content": _user_prompt(summary, ids, topics)}]}
	var err := http.request(_endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		print("❌ HTTP 发起失败 err=%d（LM Studio 未开/端口不对？）" % err)
		http.queue_free(); return {}
	var res: Array = await http.request_completed   # [result, code, headers, body]
	http.queue_free()
	if int(res[1]) != 200:
		print("❌ HTTP code=%d" % int(res[1]))
		return {}
	var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (j is Dictionary) or not (j as Dictionary).has("choices"):
		print("❌ 响应缺 choices")
		return {}
	var content := String(j["choices"][0].get("message", {}).get("content", ""))
	print("--- 70B 原文 ---\n%s\n---" % content)
	return _extract_json(content)

## 从可能夹带说明/围栏的文本里抠出第一个 {...} JSON 块。
func _extract_json(s: String) -> Dictionary:
	var a := s.find("{")
	var b := s.rfind("}")
	if a < 0 or b <= a:
		return {}
	var j: Variant = JSON.parse_string(s.substr(a, b - a + 1))
	return j if j is Dictionary else {}

## 校验+净化：只保留合法 id/话题/关系字段/信念，数值钳制。冻结前最后一道护栏（吸取 review 教训）。
func _validate(raw: Dictionary, S) -> Dictionary:
	var valid_ids := {}
	for ag in S.agents:
		valid_ids[String(ag["id"])] = true
	var valid_topics := {}
	for t in S.TOPICS:
		valid_topics[String(t)] = true
	var rel_fields := {"affinity": true, "trust": true, "standing": true, "resentment": true, "familiarity": true}
	var out := {"harmony": bool(raw.get("harmony", true)), "agents": []}
	for patch in raw.get("agents", []):
		var pd: Dictionary = patch if patch is Dictionary else {}
		var aid := String(pd.get("id", ""))
		if not valid_ids.has(aid):
			continue
		var ao := {"id": aid}
		var atts := {}
		var atts_in = pd.get("attitudes", {})
		if atts_in is Dictionary:
			for t in atts_in:
				if valid_topics.has(String(t)):
					atts[String(t)] = clampf(float(atts_in[t]), -1.0, 1.0)
		if not atts.is_empty():
			ao["attitudes"] = atts
		var rels := {}
		var rels_in = pd.get("relationships", {})
		if rels_in is Dictionary:
			for oid in rels_in:
				if not valid_ids.has(String(oid)) or String(oid) == aid:
					continue
				var rf := {}
				var rfi = rels_in[oid]
				if rfi is Dictionary:
					for k in rfi:
						if rel_fields.has(String(k)):
							rf[String(k)] = clampf(float(rfi[k]), -100.0, 100.0)
				if not rf.is_empty():
					rels[String(oid)] = rf
		if not rels.is_empty():
			ao["relationships"] = rels
		var bels := []
		var bels_in = pd.get("beliefs", [])
		if bels_in is Array:
			for bel in bels_in:
				var bd: Dictionary = bel if bel is Dictionary else {}
				var bid := String(bd.get("id", ""))
				var claim := String(bd.get("claim", ""))
				if bid == "" or claim == "":
					continue
				var subj := String(bd.get("subject", aid))
				if not valid_ids.has(subj):
					subj = aid
				bels.append({"id": bid, "claim": claim, "subject": subj, "secret": bool(bd.get("secret", false))})
		if not bels.is_empty():
			ao["beliefs"] = bels
		if ao.size() > 1:
			out["agents"].append(ao)
	return out

func _run_scenario(out_id: String, seed: int, days: int) -> Array:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.scenario = out_id
	var ext := SimExt.new()
	ext.register_scenario(DataScen.new(out_id))
	ext.freeze()
	S.ext = ext
	S.start_new(seed)
	var total := days * int(S.TICKS_PER_DAY)
	for i in total:
		S.tick()
	var r := [int(Inv.digest(S)), int(S.event_digest)]
	get_root().remove_child(S)
	S.free()
	return r

## ── 周更编剧编排器（--recurring）──────────────────────────────────────────────
## 每周：用【当前部分 schedule】从头重跑到本周边界（前几周补丁经 seed_day 到点注入=反映累积剧情）→ 快照 → 70B →
## 净化 → 追进 schedule。sim 只消费冻结的 schedule；70B 的非确定全在这个引擎外循环里。最后冻结落盘 + 两跑自检。
## 从头重跑保证「编排器状态==回放状态」（两者都经同一 seed_day 路径注入），O(周²) tick 但确定、简单、对得上。
func _orchestrate(seed: int, weeks: int, interval: int, out_id: String, mock: bool) -> void:
	print("=== Scriptwriter·周更编剧  seed=%d weeks=%d interval=%d out=%s mock=%s ===" % [seed, weeks, interval, out_id, str(mock)])
	var schedule: Array = []
	for w in range(1, weeks + 1):
		var day_target := w * interval
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		S.auto_run = false
		S.backend = null
		S.scenario = out_id
		var ext := SimExt.new()
		var prov := DataScen.new(out_id)
		prov.set_data({"harmony": true, "agents": [], "schedule": schedule})   # 内存部分 schedule，免中途落盘
		ext.register_scenario(prov)
		ext.freeze()
		S.ext = ext
		S.start_new(seed)
		for i in day_target * int(S.TICKS_PER_DAY):
			S.tick()
		var snap := _state_summary(S)
		print("\n— 第 %d 周（到第 %d 天）镇情 —\n%s" % [w, day_target, snap])
		var raw: Dictionary
		if mock:
			raw = _mock_week_patch(w)
		else:
			print("→ 第 %d 周调 70B…" % w)
			raw = await _generate_patch(snap)
		var clean := _validate(raw, S)                # 复用净化护栏（合法 id/话题、越界钳制）
		get_root().remove_child(S)
		S.free()
		if (clean.get("agents", []) as Array).is_empty():
			print("⚠ 第 %d 周产出净化后为空，跳过本周" % w)
			continue
		schedule.append({"day": day_target, "agents": clean["agents"]})
		print("✅ 第 %d 周补丁冻进 schedule（day=%d，%d 处改动）" % [w, day_target, (clean["agents"] as Array).size()])
	var doc := {"harmony": true, "agents": [], "schedule": schedule}
	var path := "res://data/scenarios/%s.json" % out_id
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("❌ 写盘失败: " + path); quit(1); return
	f.store_string(JSON.stringify(doc, "  "))
	f.close()
	print("\n✅ 周更剧本已冻结（%d 周补丁）→ res://data/scenarios/%s.json" % [schedule.size(), out_id])
	print(JSON.stringify(doc, "  "))
	var vdays := weeks * interval + interval
	var d1 := _run_scenario(out_id, seed, vdays)
	var d2 := _run_scenario(out_id, seed, vdays)
	var ok: bool = d1[0] == d2[0] and d1[1] == d2[1]
	print("确定性自检（%d 天·同 schedule 两跑）：digest %d/%d vs %d/%d → %s" % [
		vdays, d1[0], d1[1], d2[0], d2[1], "✅ 逐字节一致（周更回放不破）" if ok else "❌ 漂移"])
	quit(0 if ok else 1)

## 中途镇情（比开局摘要更细：当前显著关系/怨气 + 明显观点，供编剧顺势推进）。
func _state_summary(S) -> String:
	var lines: Array = ["第 %d 天。" % S.day]
	for ag in S.agents:
		var rels: Array = []
		for oid in ag["relationships"]:
			var r: Dictionary = ag["relationships"][oid]
			var aff := float(r.get("affinity", 0.0))
			var res := float(r.get("resentment", 0.0))
			if absf(aff) >= 25.0 or res >= 6.0:
				rels.append("%s好感%d%s" % [S._name(S.get_agent(oid)), int(aff), ("怨%d" % int(res)) if res >= 6.0 else ""])
		var att: Array = []
		for t in S.TOPICS:
			var a := float(ag["attitudes"].get(t, 0.0))
			if absf(a) >= 0.3: att.append("%s%.1f" % [t, a])
		lines.append("- %s(%s)：%s%s" % [ag["id"], S._name(ag),
			("关系[" + "，".join(rels) + "]") if not rels.is_empty() else "关系平淡",
			("  观点[" + "，".join(att) + "]") if not att.is_empty() else ""])
	return "\n".join(lines)

func _user_prompt_week(summary: String, ids: String, topics: String) -> String:
	return "小镇现况：\n%s\n\n合法角色 id：%s\n合法话题：%s\n\n你是这个镇的编剧。基于【现况】为接下来一周埋一个【推进剧情】的小转折（新恩怨/和解苗头/新秘密/观点转向），输出 JSON（schema：{agents:[{id,attitudes,relationships,beliefs}]}）。要求：①只用合法 id/话题；②顺着现况自然推进、别重置已有张力；③克制，1-2 处改动；④只输出 JSON。" % [summary, ids, topics]

func _generate_patch(summary: String) -> Dictionary:
	var ids := ", ".join(["aria", "ben", "coco", "dan", "evy", "fei"])
	var topics := ", ".join(["cafe_expand", "night_market", "old_tales"])
	var http := HTTPRequest.new()
	get_root().add_child(http)
	http.timeout = 600.0
	var body := {"model": _model, "temperature": 0.9, "max_tokens": 1000, "stream": false,
		"messages": [{"role": "system", "content": _sys_prompt()},
			{"role": "user", "content": _user_prompt_week(summary, ids, topics)}]}
	if http.request(_endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		print("❌ HTTP 发起失败"); http.queue_free(); return {}
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[1]) != 200:
		print("❌ HTTP code=%d" % int(res[1])); return {}
	var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (j is Dictionary) or not (j as Dictionary).has("choices"):
		print("❌ 响应缺 choices"); return {}
	return _extract_json(String(j["choices"][0].get("message", {}).get("content", "")))

## 确定性罐头周补丁（--mock）：循环三种小转折，验证编排逻辑+确定性，无需真模型。
func _mock_week_patch(w: int) -> Dictionary:
	var wk := [
		{"agents": [{"id": "ben", "relationships": {"aria": {"resentment": 18.0, "affinity": -20.0}}}]},
		{"agents": [{"id": "coco", "beliefs": [{"id": "S_wk_coco", "claim": "可可这周攒下一桩没说出口的心事", "subject": "coco", "secret": true}]}]},
		{"agents": [{"id": "dan", "attitudes": {"old_tales": 0.9}, "relationships": {"evy": {"affinity": 40.0, "trust": 30.0}}}]}
	]
	return wk[(w - 1) % wk.size()]
