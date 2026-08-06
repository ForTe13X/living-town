extends Node
## event_prose_test.gd — AE1 回归门（docs/118）：`Main._event_prose` 必须对被拒
## （`accepted=false`）的社交事件讲成「被婉拒/没接茬」，而不是恒讲成「做成了」。
##
## 用法：godot --headless --path game res://scenes/event_prose_test.tscn -- [--census] [--seed 7] [--days 60]
##
## 两段：
##   ① 可分性门（合成 A/B，不进金标）：对每个受影响社交类型，喂 accepted=true / false 两版事件，
##      断言 —— 被拒版≠接受版；被拒版含【被拒语义】且不含该类型的【做成了语义】；接受版反之。
##      对 gossip_rep / endorse 另测 subject 解析不出名字（C=="")的第二个措辞分支。
##   ② 普查（真事件，--census）：驱动 Sim 一格 60 天，统计 event_log 里 accepted=false 的
##      受影响事件中「被 _event_prose 讲成成功」的条数。改前≈AA2 那条量级、改后应为 0。
##
## §2.5 探测包络（完整版见 docs/118）：
##   detects：删掉任一受影响类型的 `if ok else` 被拒分岔 ⇒ 该类型两条断言变红（该类型未改动的
##            出货树本身就是「十条分岔全删」的负对照：可分性门整体红、普查门整体红）。
##   does_not_detect：台词【质量/语气】（只查关键短语在不在，不查好不好）；`meet/confront/apologize/
##            mediate/election` 已有的分岔（不在受影响集里，本门不重复守）；经济族与 conflict/shortage
##            这些 `accepted` 无判别力的类型（它们本就不该分岔，本门不碰）。
##   confidence：N=10 类型 × {C!="" , 另加 gossip_rep/endorse 的 C=="" } + 1 格 60 天普查。
##
## 红线纪律：本门是【表现层只读派生】，只 `.new()` 一个 Main 调 `_event_prose`，从不写世界状态；
## 用的 `Sim` 是全局 autoload（数据在 `_ready` 前已由它自己的 `_ready` 装好，与 goals_test 同路）。

const MainScript = preload("res://scripts/Main.gd")

# 受影响的十个社交类型：都走 KNOWN_SOCIAL_ACTIONS 的通用「接受/婉拒」路（Sim.gd:2419-2568），
# 真能 accepted=false（拒绝落 _log_event(...,false,...) @Sim.gd:2426）。
# 值 = 该类型「做成了」语义的关键短语列表（接受版必含其一、被拒版必不含任何一个）。
const SUCCESS_PHRASES := {
	"greet": ["唠了两句"],
	"give": ["送了"],
	"gossip": ["传了个八卦"],
	"invite": ["约了"],
	"confide": ["吐露了心事"],
	"leak": ["说漏了嘴"],
	"gossip_rep": ["议论起", "说起了别人的长短"],
	"endorse": ["统一了口径", "把话说到了一处"],
	"discuss": ["聊起了各自的看法"],
	"aid": ["搭了把手"],
}

# 被拒语义词库：被拒版必含其一，接受版必不含任何一个。
const REJECT_LEXICON := ["没接茬", "婉言谢绝", "谢绝", "没搭理", "婉拒", "没接住",
	"话没递进去", "没人搭腔", "没能说到一块", "没应声", "被回绝", "回绝"]

var _fail := 0

func _has_reject(s: String) -> bool:
	for w in REJECT_LEXICON:
		if s.contains(w):
			return true
	return false

func _has_success(t: String, s: String) -> bool:
	for w in SUCCESS_PHRASES[t]:
		if s.contains(w):
			return true
	return false

func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ✅ " + msg)
	else:
		print("  ❌ " + msg)
		_fail += 1

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var census := false
	var seed := 7
	var days := 60
	for i in args.size():
		if args[i] == "--census":
			census = true
		elif args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])

	var main = MainScript.new()

	# 用真居民驱动，好让 gossip_rep/endorse 的 subject 能解析出名字（C!=""）。
	Sim.backend = null
	Sim.record_decisions = false
	Sim.auto_run = false
	Sim.start_new(seed)
	if Sim.agents.size() < 3:
		print("❌ Sim 居民不足 3（%d），无法构造合成事件" % Sim.agents.size())
		main.free()
		get_tree().quit(1)
		return
	var a1 := String(Sim.agents[0]["id"])
	var a2 := String(Sim.agents[1]["id"])
	var a3 := String(Sim.agents[2]["id"])

	print("=== EVENT-PROSE GATE (AE1 / docs/118) ===")
	print("① 可分性门：%d 个受影响类型 × accepted=true/false" % SUCCESS_PHRASES.size())
	for t in SUCCESS_PHRASES:
		# C!="" 变体（subject = 真居民 → _nm_opt 解析出名字）
		_check_type(main, t, a1, a2, a3)
		# gossip_rep / endorse 另测 C=="" 变体（subject = 查不到的 id → _nm_opt=""）
		if t == "gossip_rep" or t == "endorse":
			_check_type(main, t, a1, a2, "___no_such_subject___")

	if census:
		_run_census(main, seed, days)

	main.free()
	print("")
	if _fail == 0:
		print("=== EVENT-PROSE GATE: ✅ PASS ===")
	else:
		print("=== EVENT-PROSE GATE: ❌ FAIL (%d 条断言红) ===" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _check_type(main, t: String, a1: String, a2: String, subj: String) -> void:
	var ev_ok := {"type": t, "actor": a1, "target": a2, "subject": subj, "accepted": true, "note": ""}
	var ev_no := {"type": t, "actor": a1, "target": a2, "subject": subj, "accepted": false, "note": ""}
	var p_ok: String = main._event_prose(ev_ok)
	var p_no: String = main._event_prose(ev_no)
	var tag := t + (" (C=\"\")" if subj.begins_with("___") else "")
	_expect(p_ok != p_no, "%s：被拒版 ≠ 接受版" % tag)
	_expect(_has_success(t, p_ok) and not _has_reject(p_ok),
		"%s：接受版含【做成了】语义、无被拒语义" % tag)
	_expect(_has_reject(p_no) and not _has_success(t, p_no),
		"%s：被拒版含【被拒】语义、无【做成了】语义" % tag)

func _run_census(main, seed: int, days: int) -> void:
	print("")
	print("② 普查：seed %d × %d 天（真 event_log）" % [seed, days])
	Sim.backend = null
	Sim.record_decisions = false
	Sim.auto_run = false
	Sim.start_new(seed)
	var total := days * int(Sim.TICKS_PER_DAY)
	for _t in range(total):
		Sim.tick()
	var affected: Array = SUCCESS_PHRASES.keys()
	var by_rej := {}       # type -> accepted=false 的受影响事件条数
	var by_success := {}   # type -> 其中被讲成成功（无被拒语义）的条数
	for e in Sim.event_log:
		var ty := String(e.get("type", ""))
		if not (ty in affected):
			continue
		if bool(e.get("accepted", false)):
			continue
		by_rej[ty] = int(by_rej.get(ty, 0)) + 1
		var prose: String = main._event_prose(e)
		if not _has_reject(prose):
			by_success[ty] = int(by_success.get(ty, 0)) + 1
	var total_rej := 0
	var total_success := 0
	for ty in affected:
		var r := int(by_rej.get(ty, 0))
		var s := int(by_success.get(ty, 0))
		total_rej += r
		total_success += s
		if r > 0:
			print("  %-12s 被拒 %4d 条 · 被讲成成功 %4d 条" % [ty, r, s])
	print("  ── 合计：受影响类被拒 %d 条 · 其中被讲成成功 %d 条 ──" % [total_rej, total_success])
	_expect(total_success == 0, "普查门：0 条被拒事件被讲成成功（实得 %d）" % total_success)
