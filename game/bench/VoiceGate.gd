extends SceneTree
## bench/VoiceGate.gd — 台词覆盖门：**每一个被摆到决策桌上的候选动作，都必须有本人格的话可说。**
##
## 为什么需要它（2026-07-30，F4）：此前 14 个动作在【任何】人格下都没有台词 = 111 对
## (人格,动作) 让 _canned_say 返回 ""，而**没有任何一道门会响**。
## 更阴的是它不表现为沉默：WorldView._set_dialogue 在 last_say=="" 时回落到 DIALOG[type]，
## 于是屏幕上照样有气泡——只是 12 个人共用一套 12 行通用词。**缺陷是人格声音丢失，不是哑巴。**
##
## 口径：数的是**被 offer 的候选**，不是被选中的那一个。理由很简单——
## 一句台词只在动作被【选中】时才上屏，但候选一旦能被选中就可能上屏；
## 只查被选中的那个，等于让门的判别力随机波动。
##
## ★ 本门自证覆盖（docs/48 §六 的教训：门打印自己的 fixture 参数时，那些参数得有人读）：
##   它同时断言【本次真的枚举到了足够多的 (人格,动作) 对】。否则哪天枚举塌成 0，
##   "0 个空对" 会以全绿的样子通过——那正是本仓库反复中招的空门。
##
## ── 网格与地板是【量出来的】，不是拍的 ──────────────────────────────────────
## 覆盖 vs 成本（负对照树 = F4 之前的旧词库，故"空对"列可见）：
##     seeds 1-3 × 20 天   262 对 / 28 动作   空 70     ← 动作没覆盖全
##     seeds 1-6 × 30 天   266 对 / 29 动作   空 73     ← 还差两个
##     seeds 1-2 × 60 天   290 对 / 31 动作   空 97     19s  ← 61 天起才见全
##     seeds 1-3 × 60 天   293 对 / 31 动作   空 100    28s  ← CI 用这一格
##     seeds 1-6 × 60 天   300 对 / 31 动作   空 107
## 31 = F4 普查出的全镇可选动作数（13 社交 + 18 物件/行程）⇒ CI 这一格看得见每一个动作。
##
## ★ 地板为什么是 250 而不是 293、也不是"31 个动作全在"：
##   地板要防的是【枚举塌掉】（decision_sink 不再触发、候选集合崩成空）——那种情况下
##   "0 对为空" 会以全绿的样子通过，正是本仓库反复中招的空门。
##   它**不该**用来冻结动作集合：F5 这一波正在决定渔夫的去留，而删掉一个岗位会
##   合法地少掉若干动作/对。把地板设成 293 或 "必须 31 个动作"，等于给一次正当的删除
##   预埋一条假红——docs/46 R11 与 docs/48 §五记的就是这个病。
##   250 = 实测 293 留约 15% 余量，同时远高于崩溃态。**宁可漏报一次缩水，不可假红一次正当删除。**
##
## 用法：godot --headless --path game --script res://bench/VoiceGate.gd -- [--seeds a-b] [--days N] [--min-pairs N]

const SimScript = preload("res://scripts/Sim.gd")

var _S = null
var _empty := {}      # "persona|action" -> 次数
var _pairs := {}      # "persona|action" -> true（覆盖面）
var _actions := {}    # action -> true
var _seen_personas := {}   # 真的被枚举到的人格
var _cast_personas := {}   # 阵容里【应该】被枚举到的人格

func _on_decide(ag: Dictionary, cands: Array, _best_i: int) -> void:
	var pk := String(ag.get("persona_key", ""))
	_seen_personas[pk] = true
	for c in cands:
		var act := String(c.get("action", ""))
		if act == "":
			continue
		var key := pk + "|" + act
		_pairs[key] = true
		_actions[act] = true
		if String(_S._canned_say(ag, c)).strip_edges() == "":
			_empty[key] = int(_empty.get(key, 0)) + 1

func _initialize() -> void:
	var s0 := 1
	var s1 := 3
	var days := 60
	var min_pairs := 0            # 默认关：结构性判据已经在守，不再用魔数
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var nx: String = args[i + 1] if i + 1 < args.size() else ""
		if args[i] == "--seeds":
			var p := nx.split("-")
			s0 = int(p[0]); s1 = int(p[1]) if p.size() > 1 else int(p[0])
		elif args[i] == "--days": days = int(nx)
		elif args[i] == "--min-pairs": min_pairs = int(nx)

	for seed in range(s0, s1 + 1):
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		S.auto_run = false
		S.backend = null
		_S = S
		S.decision_sink = Callable(self, "_on_decide")
		S.start_new(seed)
		for ag in S.agents:
			_cast_personas[String(ag.get("persona_key", ""))] = true
		for t in days * int(S.TICKS_PER_DAY):
			S.tick()
		S.decision_sink = Callable()
		get_root().remove_child(S)
		S.free()

	print("VoiceGate  seeds=%d-%d days=%d" % [s0, s1, days])
	print("  覆盖：%d 个 (人格,动作) 对 · %d 个不同动作" % [_pairs.size(), _actions.size()])
	var rc := 0
	# ★ 结构性地板（2026-07-30 外审后改；原来是 --min-pairs 250 这个拍出来的数）。
	#   外审的原话：250 与实测 293 之间【没有理论依据】，只是 85%；而且
	#   "数量不是语义"——删掉一个【人格】可能让对数从 293 掉到 280 仍然过门，
	#   而那个人格的声音已经全没了。⇒ 不数数，改判集合相等：
	#   阵容里出现过的每一个人格，都必须真的被枚举到过。
	#   这样一来：decision_sink 塌掉 ⇒ 枚举集合空 ⇒ 红；
	#   合法删掉一个岗位 ⇒ 阵容与枚举同时少掉 ⇒ 仍然绿（不假红）；
	#   而"某个人格一次都没被问过决策" ⇒ 红。没有魔数。
	var missing: Array = []
	for pk2 in _cast_personas:
		if not _seen_personas.has(pk2):
			missing.append(String(pk2))
	missing.sort()
	if _cast_personas.is_empty():
		print("  ❌ 阵容为空：一个 agent 都没有 ⇒ 本次运行【没有资格】说全绿")
		rc = 1
	elif not missing.is_empty():
		print("  ❌ 覆盖塌陷：阵容里有 %d 个人格从未被枚举到 [%s] ⇒ 本次运行【没有资格】说全绿"
			% [missing.size(), ", ".join(missing)])
		rc = 1
	else:
		print("  ✅ 结构覆盖：阵容 %d 个人格全部被枚举到（不靠数量地板）" % _cast_personas.size())
	if min_pairs > 0 and _pairs.size() < min_pairs:   # 可选的额外数量地板，默认关
		print("  ❌ 对数 %d 低于显式地板 %d" % [_pairs.size(), min_pairs])
		rc = 1
	if _empty.is_empty():
		print("  ✅ 每个被 offer 的候选都有本人格的话可说（0 对为空）")
	else:
		var ks: Array = _empty.keys()
		ks.sort()
		print("  ❌ %d 对 (人格,动作) 没有台词：" % _empty.size())
		for k in ks:
			print("      %-24s 被 offer %d 次" % [k, int(_empty[k])])
		rc = 1
	print("=== VoiceGate: %s ===" % ("PASS ✅" if rc == 0 else "FAIL ❌"))
	quit(rc)
