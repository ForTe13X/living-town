extends Node
## bench/ModelPathGate.gd — 【模型路径】的可证伪对照（Wave C · C6）。
## 用法：godot --headless --path game res://bench/ModelPathGate.tscn -- [--seeds 1-4] [--days 8] [--agents 12]
##
## 为什么必须单独有它（docs/41 §2）：
##   CI 的每一道门（金标 / LOD / DetGate）都恒 `Sim.backend = null` ⇒ `AIBackend.decide()` 从不被进入，
##   ⇒ 【闭集选号编码】与【SLM 熔断器】这两块代码在 CI 里的执行次数是 0。
##   「金标逐字节没动」对本棒是**必要不充分**条件。本门就是那个充分条件的一半。
##   4d BackendGate 补的是"外部后端挑的那条路上硬不变量还成立吗"；本门补的是它盖不到的两块：
##   ① 编码契约本身（label ↔ index 的往返、cap 上限、系统 prompt 里不得再有字面示例编号）；
##   ② 熔断器的**复位语义**（BackendGate 走 random 臂，永远不触发 SLM 熔断）。
##
## 三段，每段都能单独变红：
##   A. 闭集选号契约（C6-a）—— 纯函数自检，零 Sim
##   B. 熔断器复位（C6-b）—— 先证明它**真的开了**，再证明该复位的路复位了、**不该复位的路仍然是开的**
##   C. random 臂零扰动锚（C6-a 的副作用守门）—— cap 36→26 若挪动了 random 臂的轨迹，这里的 digest 会变
## exit 0/1。

const Inv = preload("res://bench/Invariants.gd")
const SimScript = preload("res://scripts/Sim.gd")

## 期望值【写死在门里】，故意不从 AIBackend 读常量：
##   ① 从被测对象取期望值 = 同义反复，门永远绿；
##   ② 这一份不引用任何新符号 ⇒ **同一个门可以原样跑在改动前的树上**，于是"这门会红"本身可复现（负对照）。
const CAP := 26           # docs/42 §7.3-2：闭集编号字母表 0-9/A-Z(36) → A-Z(26)

var _fails: Array = []

func _ck(ok: bool, what: String) -> void:
	if ok:
		print("    ✅ %s" % what)
	else:
		print("    ❌ %s" % what)
		_fails.append(what)

func _ready() -> void:
	var seeds_spec := "1-4"
	var days := 8
	var agents := 12
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds_spec = args[i + 1]
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): agents = int(args[i + 1])

	var hash_bad := SimScript.hash_self_test()
	if hash_bad != "":
		print("❌ 项目自有哈希测试向量不符：%s（尺子变了，任何比对无意义）" % hash_bad)
		get_tree().quit(1)
		return

	print("=== ModelPathGate · 模型路径对照 seeds=%s days=%d N=%d ===" % [seeds_spec, days, agents])
	_part_a()
	_part_b(agents)
	_part_c(_parse_seeds(seeds_spec), days, agents)

	print("\n=== ModelPathGate: %s  (失败 %d)" % ["PASS ✅" if _fails.is_empty() else "FAIL ❌", _fails.size()])
	for f in _fails:
		print("    · %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)


# ── A. 闭集选号编码契约（C6-a）────────────────────────────────────────────
## 断言的是**编码**，不是判断力。docs/42 §4.3 已证：八种编码下名次恒在 0.461-0.496（随机 0.495）——
## 这一段全绿只说明"模型不会再被两个字符串系统性地推离 0 号槽"，**不说明它选得更好**。
func _part_a() -> void:
	print("  [A] 闭集选号编码契约")
	# ① 系统 prompt 里不得再出现【任何 ASCII 数字】。那个字面示例「如 3」把 30.0% 的决策焊死在 index 3
	#    （docs/42 §4.3：删掉它 → index-3 的堆 204→78）。用"无数字"而不是"不含子串'如 3'"来断言，
	#    是为了让任何形式的示例编号复活都会变红。
	var sys: String = AIBackend._system_prompt()
	var digit_in_sys := ""
	for j in sys.length():
		var o := sys.unicode_at(j)
		if o >= 48 and o <= 57:
			digit_in_sys += sys.substr(j, 1)
	_ck(digit_in_sys == "", "系统 prompt 无字面示例编号（残留数字 '%s'）" % digit_in_sys)

	# ② label 全在 A-Z、单字符、且 index↔label 往返恒等。往返一旦破，模型答对了也会被判非法。
	var bad_label := ""
	var bad_trip := ""
	for i in CAP:
		var lb: String = AIBackend._idx_label(i)
		if lb.length() != 1 or lb.unicode_at(0) < 65 or lb.unicode_at(0) > 90:
			bad_label += "%d→'%s' " % [i, lb]
		if AIBackend._label_idx(lb) != i:
			bad_trip += "%d→'%s'→%d " % [i, lb, AIBackend._label_idx(lb)]
	_ck(bad_label == "", "[0,cap) 的 label 全是单个 A-Z（越界：%s）" % bad_label)
	_ck(bad_trip == "", "label↔index 往返恒等（破：%s）" % bad_trip)

	# ③ 数字**不再**是合法编号 → fail-closed。docs/42 §4.2：字符 '0' 的首 token 概率是 1.6e-4，
	#    这正是"从不选 0 号槽 → 系统性跳过吃饭睡觉"那条链的病灶。数字退出字母表后，
	#    模型若仍答数字，必须落到引擎兜底而不是被误读成某个下标。
	var digit_ok := true
	for d in 10:
		if AIBackend._label_idx(str(d)) != -1:
			digit_ok = false
	_ck(digit_ok, "数字不再是合法编号（fail-closed 到引擎兜底）")

	# ④ _cap_for_llm 真的按新上限裁剪，且 ≤cap 时【原样返回】（保持引擎枚举序——
	#    一旦这里开始按 score 重排，docs/42 §9-4 那个坑就会复活：等于把答案写在 0 号位上）。
	var many: Array = []
	for i in 40:
		many.append({"kind": "obj", "action": "a%d" % i, "score": float(i)})
	var capped: Array = AIBackend._cap_for_llm(many)
	_ck(capped.size() == CAP, "40 候选 → 裁到 %d（实测 %d）" % [CAP, capped.size()])
	# ★ 裁剪【必须保持枚举序】。many 的 score 随下标递增 ⇒ top-26 = 下标 14..39，放回枚举序后
	#   capped[j] 必须是 many[14+j]。若这里退回"按 score 降序返回"，capped[0] 会是分最高的 a39
	#   —— 等于把答案写在 0 号槽上（docs/42 §9-4），且摧毁"index 0 = 维生对象"这条自然序性质。
	var order_kept := capped.size() == CAP
	for j in capped.size():
		if String(capped[j].get("action", "")) != "a%d" % (40 - CAP + j):
			order_kept = false
	_ck(order_kept, "裁剪后保持枚举序（不是按 score 降序喂模型）—— 实测首项 '%s'（应为 'a%d'）" % [
		String(capped[0].get("action", "")) if not capped.is_empty() else "-", 40 - CAP])
	var few: Array = many.slice(0, 5)
	var same_order := true
	var few_capped: Array = AIBackend._cap_for_llm(few)
	for i in few.size():
		if String(few_capped[i].get("action", "")) != String(few[i].get("action", "")):
			same_order = false
	_ck(few_capped.size() == 5 and same_order, "≤cap 时原样返回、保持枚举序")

	# ⑤ 端到端：模型答 label → parse_decision 必须取回**同一个**候选。这是编码改动唯一会静默
	#    破坏产品的方式（答对被判错 / 答 A 落到 B）。
	var cands: Array = []
	for i in mini(CAP, 12):
		cands.append({"kind": "obj", "action": "act%d" % i, "score": float(i)})
	var bad_e2e := ""
	for i in cands.size():
		var got: Dictionary = AIBackend.parse_decision(AIBackend._idx_label(i), cands)
		if got.is_empty() or String(got.get("action", "")) != String(cands[i]["action"]):
			bad_e2e += "%d " % i
	_ck(bad_e2e == "", "parse_decision(label(i)) ≡ candidates[i]（破：%s）" % bad_e2e)
	# prose fail-closed 没被顺带改坏（P2-3：「A 去吃饭」不是编号）
	_ck(AIBackend.parse_decision("A 去 eat", cands).is_empty(), "prose fail-closed 仍然有效")


# ── B. SLM 熔断器复位（C6-b）──────────────────────────────────────────────
## 为什么要自己造失败而不是等真模型：红线#4 不许权重/二进制入库 ⇒ CI 里 NobodyWho 扩展恒不可用，
## slm 那条路一次也跑不到。所以这里**直接喂一条已过期的 _pending 记录**，让 `decide()` 走它
## 真正的超时分支（AIBackend.gd 的 `Time.get_ticks_msec() >= p["due_ms"]` → `_slm_fail_streak += 1`）。
## 白盒的只有"怎么造出失败"，被测的是**产品自己的那段状态机**，不是重实现。
func _part_b(agents: int) -> void:
	print("  [B] SLM 熔断器复位")
	# settings.cfg 快照：set_model_path / request_backend / set_slm_use_gpu 都会写盘，跑完原样还原。
	var cfg_path := "user://settings.cfg"
	var cfg_had := FileAccess.file_exists(cfg_path)
	var cfg_bytes := PackedByteArray()
	if cfg_had:
		cfg_bytes = FileAccess.get_file_as_bytes(cfg_path)

	var fx := _fixture(agents)
	if fx.is_empty():
		_ck(false, "取不到 (agent, candidates) fixture")
		return
	var agent: Dictionary = fx["agent"]
	var cands: Array = fx["cands"]
	var ctx: Dictionary = fx["ctx"]

	var be0: String = AIBackend.backend
	var br0: String = AIBackend.backend_requested
	var mp0: String = AIBackend.slm_model_override
	var gpu0: bool = AIBackend.slm_use_gpu

	# ① 熔断器**真的开了**——先证伪"我测的是一个从没关过的开关"。
	_ck(not AIBackend._slm_circuit_open, "起点：熔断器是关的")
	var trips := _trip(agent, cands, ctx)
	_ck(AIBackend._slm_circuit_open, "连续 %d 次超时 → 熔断器开（实测触发于第 %d 次）" % [AIBackend.SLM_CIRCUIT_TRIP, trips])
	# 开了之后 decide() 必须真的绕开模型（否则这个标志位是装饰品）
	var out_open: Dictionary = AIBackend.decide(agent, cands, ctx)
	var floor_pick: Dictionary = Sim._logic_decide(agent, cands)
	_ck(not out_open.is_empty() and Sim._cand_key(out_open) == Sim._cand_key(floor_pick),
		"熔断后 decide() 走引擎地板（不再 fire）")

	# ② 换权重文件 = 全新的失败假设 ⇒ 必须复位。
	AIBackend.set_model_path("res://models/__modelpathgate_probe.gguf")
	_ck(not AIBackend._slm_circuit_open, "set_model_path() 后熔断器关")
	_ck(AIBackend._slm_fail_streak == 0, "set_model_path() 后连败计数清零（否则新模型只剩 1 次机会，不是 %d 次）" % AIBackend.SLM_CIRCUIT_TRIP)

	# ③ **不该复位的那条路**：request_backend() 不改变任何失败假设（同权重、同 GPU 档、同 worker），
	#    且它是设置面板里被反复点的那一行 —— 若它复位，docs/34 的原生泄漏封顶就被"切走再切回"绕过了。
	AIBackend._slm_circuit_open = false
	AIBackend._slm_fail_streak = 0
	AIBackend.backend = "slm"
	AIBackend.backend_requested = "slm"
	_trip(agent, cands, ctx)
	_ck(AIBackend._slm_circuit_open, "③ 前置：熔断器再次打开")
	AIBackend.request_backend("logic")
	AIBackend.request_backend("mock")
	_ck(AIBackend._slm_circuit_open, "request_backend() 后熔断器**仍然开着**（这条路刻意没改）")

	# ④ 切 GPU/CPU 推理档同样是一个全新的失败假设——docs/34 那次挂死就是 Adreno **GPU** 特有的，
	#    "换成 CPU 再试" 正是文档给出的解法。若它不复位，用户按文档自救会得到无声失败。
	AIBackend.backend = "slm"
	AIBackend.backend_requested = "slm"
	AIBackend.set_slm_use_gpu(not AIBackend.slm_use_gpu)
	_ck(not AIBackend._slm_circuit_open, "set_slm_use_gpu() 后熔断器关")

	# 还原（本门自己零残留：状态 + 落盘的 settings.cfg 都回到进门前）
	AIBackend._slm_circuit_open = false
	AIBackend._slm_fail_streak = 0
	AIBackend.slm_model_override = mp0
	AIBackend.slm_use_gpu = gpu0
	AIBackend.backend = be0
	AIBackend.backend_requested = br0
	AIBackend.cancel_all()
	if cfg_had:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(cfg_bytes)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))


## 造 SLM_CIRCUIT_TRIP 次连续超时：每次塞一条【已到期、未就绪】的 _pending，再调真 decide()。
## 返回熔断器首次变开时的次数（0 = 全程没开）。
func _trip(agent: Dictionary, cands: Array, ctx: Dictionary) -> int:
	var id := String(agent["id"])
	AIBackend.backend = "slm"
	AIBackend.backend_requested = "slm"
	var tripped_at := 0
	for k in range(1, AIBackend.SLM_CIRCUIT_TRIP + 1):
		AIBackend._pending[id] = {
			"epoch": AIBackend.world_epoch, "req_id": -1, "prompt_tick": Sim.tick_no,
			"snapshot": cands.duplicate(true), "due_ms": 0, "ready": Sim.tick_no,
			"raw": "", "has": false, "http": null, "slm_chat": null}
		AIBackend.decide(agent, cands, ctx)
		if AIBackend._slm_circuit_open and tripped_at == 0:
			tripped_at = k
	return tripped_at


## 从一局真仿真里抓一个 (agent, candidates, ctx) fixture —— 手搓的候选会漏掉 _cand_key 需要的字段。
var _fx: Dictionary = {}
func _fixture(agents: int) -> Dictionary:
	Sim.spawn_count = agents
	Sim.auto_run = false
	Sim.backend = null
	Sim.start_new(1)
	_fx = {}
	Sim.decision_sink = Callable(self, "_on_decision")
	for t in int(Sim.TICKS_PER_DAY):
		Sim.tick()
		if not _fx.is_empty():
			break
	Sim.decision_sink = Callable()
	return _fx

func _on_decision(ag, cands, _pick_i) -> void:
	if _fx.is_empty() and cands.size() >= 3:
		_fx = {"agent": ag, "cands": (cands as Array).duplicate(true), "ctx": Sim._context(ag)}


# ── C. random 臂零扰动锚（C6-a 的副作用守门）──────────────────────────────
## `_cap_for_llm` 的 36→26 会改变 random/mock/slm 三条臂在 |C|>26 时看到的闭集 ⇒ 可能挪动 random 臂轨迹。
## 这是【模型路径上的行为变更】，本来就在允许范围内（4d 那道门存在的理由），但必须**量出来**而不是猜。
## 打印逐 seed 的 Inv.digest / event_digest：改前跑一遍、改后跑一遍，逐字节对。
func _part_c(seeds: Array, days: int, agents: int) -> void:
	print("  [C] random(full) 臂逐 seed 摘要（改前/改后逐字节对比用）")
	# 只读探针：Sim.backend 是鸭子类型（Sim.gd:1181 只查 has_method），套一层转发就能量到
	# 【模型路径真正看见的】|C| 分布。不能用 decision_sink —— 它挂在 _logic_decide 里，
	# random(full) 档根本不走那条路（_instant_random 直接返回），会量出一堆 0。
	var probe := DecideProbe.new()
	probe.cap = CAP
	for sd in seeds:
		AIBackend.backend = "random"
		AIBackend.backend_requested = "random"
		AIBackend.sim_decode_ticks = 0
		AIBackend.shadow_baseline = false
		Sim.spawn_count = agents
		Sim.start_new(sd)
		Sim.backend = probe
		Sim.auto_run = false
		AIBackend.reset_stats()
		for t in range(days * int(Sim.TICKS_PER_DAY)):
			Sim.tick()
		print("    seed=%d  inv_digest=%d  event_digest=%d  landed=%d" % [
			sd, Inv.digest(Sim), Sim.event_digest, int(AIBackend.stats["landed"])])
	# 这两个数解释 digest 为什么动/不动：|C| 从没超过 cap ⇒ 裁剪从未生效 ⇒ 轨迹必然逐字节相同。
	print("    候选规模：max|C|=%d，|C|>%d 的决策点 %d/%d（旧上限 |C|>36：%d/%d）" % [
		probe.max_n, CAP, probe.over_cap, probe.n_dec, probe.over_old, probe.n_dec])
	AIBackend.backend = "logic"
	AIBackend.backend_requested = "logic"
	Sim.backend = null

## 纯转发探针：只数 candidates.size()，不抽 RNG、不改任何参数 ⇒ 对被测轨迹零扰动。
class DecideProbe extends RefCounted:
	var cap := 26           # 由 _part_c 从外层 CAP 注入（内部类看不到外层常量）
	var max_n := 0
	var over_cap := 0
	var over_old := 0       # |C|>36：旧上限下裁剪就已经生效的那些（新旧差集才是本次真正新增的裁剪）
	var n_dec := 0
	func decide(ag: Dictionary, cands: Array, ctx: Dictionary) -> Dictionary:
		n_dec += 1
		max_n = maxi(max_n, cands.size())
		if cands.size() > cap:
			over_cap += 1
		if cands.size() > 36:
			over_old += 1
		return AIBackend.decide(ag, cands, ctx)
	func reflect(ag: Dictionary, floor_insight: String, recent: Array, cb: Callable) -> void:
		AIBackend.reflect(ag, floor_insight, recent, cb)


func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1): out.append(s)
	elif "," in spec:
		for s in spec.split(","): out.append(int(s))
	else: out.append(int(spec))
	return out
