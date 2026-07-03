extends RefCounted
class_name DataScenarioProvider
## scripts/DataScenarioProvider.gd — 纯数据驱动的 ScenarioProvider（docs/14 §1 步骤7）。
## 让"加一个定向场景"= 写一个 data/scenarios/<id>.json 声明式补丁，零 GDScript、零改 Sim 核心。
## 契约：id()/seed(S)/distorts_harmony()。确定：只按 JSON 设值，无 RNG/Time；键序不影响（各键独立赋值）。
##
## JSON 结构（全部可选）：
## { "harmony": true,                         # 是否扭曲和睦局（默认 true → Invariants 豁免涌现软不变量）
##   "agents": [
##     { "id": "aria",
##       "attitudes": {"cafe_expand": 0.9},    # 覆写观点(∈[-1,1])
##       "relationships": {"coco": {"standing": -3, "affinity": -20, "trust": -30}}  # 覆写对某人的关系账本字段
##     } ] }

var _id: String
var _path: String
var _harmony_distort := true

func _init(id: String) -> void:
	_id = id
	_path = "res://data/scenarios/%s.json" % id

func id() -> String:
	return _id

func distorts_harmony() -> bool:
	return _harmony_distort

func seed(S: Object) -> void:
	if not FileAccess.file_exists(_path):
		push_error("缺数据场景文件: " + _path)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if not (d is Dictionary):
		push_error("数据场景非法 JSON: " + _path)
		return
	_harmony_distort = bool(d.get("harmony", true))
	for patch in d.get("agents", []):
		var aid := String(patch.get("id", ""))
		if not S._agent_by_id.has(aid):
			push_error("数据场景 %s：未知 agent id=%s（跳过）" % [_id, aid])
			continue
		var ag: Dictionary = S._agent_by_id[aid]
		for t in patch.get("attitudes", {}):
			if ag["attitudes"].has(t):
				ag["attitudes"][t] = clampf(float(patch["attitudes"][t]), -1.0, 1.0)
				ag["attitude0"][t] = ag["attitudes"][t]   # 同步天生立场锚（否则 FJ 会把它拉回旧锚）
		for oid in patch.get("relationships", {}):
			var rr: Dictionary = S._rel(ag, oid)
			for k in patch["relationships"][oid]:
				if rr.has(k):
					rr[k] = float(patch["relationships"][oid][k])
