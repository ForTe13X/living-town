extends RefCounted
class_name BenchMetrics
## bench/Metrics.gd — S5 系统级指标 + 因果结果检测器（纯读 Sim 终态/event_log，确定性）。
## 指标：PI(极化) / cascade(谣言级联) / Gini(社会接纳不平等)。
## 检测器：ostracized / opinion_moved / invested —— 供配对反事实 PN/PS 判定结果 Y。

# ── 系统级指标 ──────────────────────────────────────────────────────────

## PI 极化指数：各话题观点方差的均值（[-1,1] 观点 → PI∈[0,1]，越大越分裂）。
static func polarization(S) -> float:
	var topics: Array = S.TOPICS
	if topics.is_empty() or S.agents.is_empty():
		return 0.0
	var acc := 0.0
	for t in topics:
		var m := 0.0
		for ag in S.agents:
			m += float(ag["attitudes"][t])
		m /= float(S.agents.size())
		var v := 0.0
		for ag in S.agents:
			var d := float(ag["attitudes"][t]) - m
			v += d * d
		acc += v / float(S.agents.size())
	return acc / float(topics.size())

## cascade：单条信念传到的最大人数（谣言级联规模；含源）。
static func cascade_max(S) -> int:
	var cnt := {}
	for ag in S.agents:
		for cid in ag["beliefs"]:
			cnt[cid] = int(cnt.get(cid, 0)) + 1
	var mx := 0
	for cid in cnt:
		mx = maxi(mx, int(cnt[cid]))
	return mx

## Gini：以「作为发起方的被接受率」为社会资源，算不平等系数（[0,1]，0=均等）。
static func gini_acceptance(S) -> float:
	var xs: Array = []
	var prop := {}
	var acc := {}
	for ag in S.agents:
		prop[ag["id"]] = 0; acc[ag["id"]] = 0
	for e in S.event_log:
		if String(e["type"]) in ["greet", "give", "gossip", "invite", "gossip_rep", "discuss"]:
			prop[e["actor"]] = int(prop[e["actor"]]) + 1
			if bool(e["accepted"]): acc[e["actor"]] = int(acc[e["actor"]]) + 1
	for ag in S.agents:
		if int(prop[ag["id"]]) > 0:
			xs.append(float(acc[ag["id"]]) / float(prop[ag["id"]]))
	if xs.size() < 2:
		return 0.0
	var s := 0.0
	var tot := 0.0
	for a in xs:
		tot += a
		for b in xs:
			s += absf(a - b)
	if tot <= 0.0:
		return 0.0
	return s / (2.0 * float(xs.size()) * tot)

# ── 因果结果检测器 Y（供 PN/PS）─────────────────────────────────────────

## 某 agent 的"感知 standing"=他人对其 standing 的均值。
static func perceived_standing(S, id: String) -> float:
	var s := 0.0
	var n := 0
	for b in S.agents:
		if b["id"] != id:
			s += float(S._rel(b, id)["standing"]); n += 1
	return s / float(maxi(1, n))

## Y1 被放逐：作为发起方被接受率明显低于镇均（且本人发起够多次）。
static func ostracized(S, id: String) -> bool:
	var prop := {}
	var acc := {}
	for ag in S.agents:
		prop[ag["id"]] = 0; acc[ag["id"]] = 0
	for e in S.event_log:
		if String(e["type"]) in ["greet", "give", "gossip", "invite", "gossip_rep", "discuss"]:
			prop[e["actor"]] = int(prop[e["actor"]]) + 1
			if bool(e["accepted"]): acc[e["actor"]] = int(acc[e["actor"]]) + 1
	if int(prop.get(id, 0)) < 5:
		return false
	var town := 0.0
	var nt := 0
	for ag in S.agents:
		if int(prop[ag["id"]]) >= 5:
			town += float(acc[ag["id"]]) / float(prop[ag["id"]]); nt += 1
	town /= float(maxi(1, nt))
	var rate := float(acc[id]) / float(prop[id])
	return rate <= town - 0.12

## Y2 观点已迁移：任一话题偏离天生立场 > 阈。
static func opinion_moved(S, id: String, thresh: float = 0.15) -> bool:
	var ag: Dictionary = S.get_agent(id)
	if ag.is_empty():
		return false
	for t in S.TOPICS:
		if absf(float(ag["attitudes"][t]) - float(ag["attitude0"][t])) > thresh:
			return true
	return false

## Y3 a 向 b 投资：出现被接受的 give/invite（a→b）。
static func invested(S, a: String, b: String) -> bool:
	for e in S.event_log:
		if e["actor"] == a and e["target"] == b and bool(e["accepted"]) and String(e["type"]) in ["give", "invite"]:
			return true
	return false
