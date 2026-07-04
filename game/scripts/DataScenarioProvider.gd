extends RefCounted
class_name DataScenarioProvider
## scripts/DataScenarioProvider.gd — 纯数据驱动的 ScenarioProvider（docs/14 §1 步骤7）。
## 让"加一个定向场景"= 写一个 data/scenarios/<id>.json 声明式补丁，零 GDScript、零改 Sim 核心。
## 契约：id()/seed(S)/distorts_harmony()（+ 可选 seed_day(S,day)）。确定：只按 JSON 设值，无 RNG/Time；键序不影响。
##
## JSON 结构（全部可选）：
## { "harmony": true,                          # 是否扭曲和睦局（默认 true → Invariants 豁免涌现软不变量）
##   "agents": [ { "id":"aria",                 # 开局补丁（start_new 时 seed 一次）
##       "attitudes": {"cafe_expand": 0.9},     # 覆写观点(∈[-1,1])
##       "relationships": {"coco": {"standing": -3, "affinity": -20}},  # 覆写关系账本字段
##       "beliefs": [{"id":"S_x","claim":"…","subject":"coco","secret":true}] } ],
##   "schedule": [ { "day": 7, "agents": [ …同上补丁… } ] ] }   # 70B 周更编剧：到指定天注入的补丁（seed_day 应用）
##
## 「周更编剧」确定性：schedule 是【冻结的数据】，日界到点确定性注入 → goto_tick 重演逐字节一致。70B 的非确定
## 全在【引擎外的离线编排器】(scriptwriter.gd --recurring)里发生：跑一段→快照→70B→冻进 schedule→再跑，sim 只消费数据。

var _id: String
var _path: String
var _harmony_distort := true
var _data := {}
var _loaded := false

func _init(id: String) -> void:
	_id = id
	_path = "res://data/scenarios/%s.json" % id

func id() -> String:
	return _id

func distorts_harmony() -> bool:
	_ensure_loaded()
	return _harmony_distort

## 开局补丁：start_new 时注入 agents（含 goto_tick 反复 start_new，_apply 幂等设值）。
func seed(S: Object) -> void:
	_ensure_loaded()
	_apply(S, _data.get("agents", []))

## 周更编剧补丁：日界到点注入 schedule 里 day==当天 的补丁（Sim 在 _update_election 后调 ext.seed_day）。
## schedule 缺失 → 空循环 → 逐字节不变（对所有既有无 schedule 的场景零影响）。
func seed_day(S: Object, day: int) -> void:
	_ensure_loaded()
	for entry in _data.get("schedule", []):
		var ed: Dictionary = entry if entry is Dictionary else {}
		if int(ed.get("day", -1)) == day:
			_apply(S, ed.get("agents", []))

## 直接注入内存数据（供离线编排器 scriptwriter.gd --recurring 用增长中的 schedule 反复重跑，免中途落盘）。
func set_data(d: Dictionary) -> void:
	_data = d
	_loaded = true
	_harmony_distort = bool(d.get("harmony", true))

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_path):
		push_error("缺数据场景文件: " + _path)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if not (d is Dictionary):
		push_error("数据场景非法 JSON: " + _path)
		return
	_data = d
	_harmony_distort = bool(d.get("harmony", true))

## 应用一组 agent 补丁（attitudes/relationships/beliefs）。开局与周更共用；纯设值、无 RNG、键序无关。
func _apply(S: Object, agents_list) -> void:
	for patch in (agents_list if agents_list is Array else []):
		var pd: Dictionary = patch if patch is Dictionary else {}
		var aid := String(pd.get("id", ""))
		if not S._agent_by_id.has(aid):
			push_error("数据场景 %s：未知 agent id=%s（跳过）" % [_id, aid])
			continue
		var ag: Dictionary = S._agent_by_id[aid]
		for t in pd.get("attitudes", {}):
			if ag["attitudes"].has(t):
				ag["attitudes"][t] = clampf(float(pd["attitudes"][t]), -1.0, 1.0)
				ag["attitude0"][t] = ag["attitudes"][t]   # 同步天生立场锚（否则 FJ 会把它拉回旧锚）
		for oid in pd.get("relationships", {}):
			var rr: Dictionary = S._rel(ag, oid)
			for k in pd["relationships"][oid]:
				if rr.has(k):
					rr[k] = float(pd["relationships"][oid][k])
		# 70B 编剧扩展：种信念——谣言(经 gossip 扩散)或自持秘密(喂 confide 秘密博弈)。via=seed 走秘密专道(#21 允许)。
		# 确定性：只按 JSON 设值、via 固定、无 RNG。subject/owner 缺省=本人；已存在同 id 则跳过。
		for bel in pd.get("beliefs", []):
			var bd: Dictionary = bel if bel is Dictionary else {}
			var bid := String(bd.get("id", ""))
			if bid == "" or ag["beliefs"].has(bid):
				continue
			var rec := {"claim": String(bd.get("claim", "")), "subject": String(bd.get("subject", aid)),
				"source": "__seed__", "via": "seed", "tick": 0}
			if bool(bd.get("secret", false)):
				rec["secret"] = true
				rec["owner"] = aid            # V1：仅自持秘密(owner=self)，confidedBy 空；转述由引擎自演
				rec["confidedBy"] = {}
			ag["beliefs"][bid] = rec
