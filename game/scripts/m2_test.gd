extends Node
## m2_test.gd — 验证 M2 异步 LLM 接线（mock 后端，不联网）。挂在 scenes/m2_test.tscn 上。
## 用法（autoload 可用，故跑场景而非 --script）：
##   godot --headless --path . res://scenes/m2_test.tscn
## 两部分：(1) parse_decision 脏输入/越界 glue 单测；(2) mock 后端跑 sim，断言异步决策驱动小镇、无冻结。

var _fails: Array = []

func _ck(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)

func _ready() -> void:
	_test_parse()
	_test_mock_async()
	print("\n— M2 验证 —")
	if _fails.is_empty():
		print("✅ parse glue + mock 异步链路全部通过")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("❌ " + f)
		get_tree().quit(1)

func _test_parse() -> void:
	var cands := [
		{"kind": "object", "action": "吃饭", "target": "stove_1", "need": "hunger", "amount": 55, "dur_total": 18, "score": 1.0},
		{"kind": "social", "action": "greet", "partner": "ben", "need": "social", "score": 2.0},
		{"kind": "social", "action": "gossip", "partner": "coco", "subject": "R1", "need": "social", "score": 1.5},
	]
	var r1: Dictionary = AIBackend.parse_decision('{"pick":1,"speech":"嗨，最近好吗？","emotion":"happy"}', cands)
	_ck(not r1.is_empty() and String(r1.get("action")) == "greet" and String(r1.get("say")) == "嗨，最近好吗？", "valid social pick+speech")
	var r2: Dictionary = AIBackend.parse_decision('{"pick":0}', cands)
	_ck(not r2.is_empty() and String(r2.get("action")) == "吃饭", "valid no-speech")
	var r3: Dictionary = AIBackend.parse_decision('好的 ```json\n{"pick":2,"speech":"悄悄说"}\n``` 完毕', cands)
	_ck(not r3.is_empty() and String(r3.get("action")) == "gossip", "substring extract")
	_ck(AIBackend.parse_decision('{"pick":9}', cands).is_empty(), "out-of-range -> {}")
	_ck(AIBackend.parse_decision('{"pick":-1}', cands).is_empty(), "negative pick -> {}")
	_ck(AIBackend.parse_decision('{"speech":"无pick"}', cands).is_empty(), "missing pick -> {}")
	_ck(AIBackend.parse_decision('完全不是json', cands).is_empty(), "garbage -> {}")
	_ck(AIBackend.parse_decision('', cands).is_empty(), "empty -> {}")
	var r4: Dictionary = AIBackend.parse_decision('{"pick":1,"affinity_delta":99}', cands)
	_ck(not r4.is_empty() and int(r4.get("affinity_delta", 0)) == 3, "affinity_delta clamp")
	print("parse_decision: 9 用例，失败 %d" % _fails.size())

func _test_mock_async() -> void:
	AIBackend.backend = "mock"
	AIBackend.mock = true
	Sim.backend = AIBackend
	Sim.auto_run = false
	Sim.start_new(20260626)
	var days := 10
	var starved := 0
	for t in range(days * Sim.TICKS_PER_DAY):
		Sim.tick()
		for ag in Sim.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	var accepted := 0
	for e in Sim.event_log:
		if bool(e.get("accepted", false)):
			accepted += 1
	var stuck := 0
	for ag in Sim.agents:
		if bool(ag.get("thinking", false)):
			stuck += 1
	print("mock 跑 %d 天：event_log=%d 接受=%d 触底=%d 末态thinking=%d" % [days, Sim.event_log.size(), accepted, starved, stuck])
	_ck(Sim.event_log.size() > 0, "mock: 异步决策产出了事件")
	_ck(accepted > 0, "mock: 决策驱动了社交")
	_ck(starved == 0, "mock: 无饿穿（异步等待不致饿死）")
	_ck(stuck <= AIBackend.MAX_INFLIGHT, "mock: 无大量 thinking 卡死（deadline 兜底有效）")
