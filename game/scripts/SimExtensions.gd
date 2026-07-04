extends RefCounted
class_name SimExtensions
## scripts/SimExtensions.gd — 场景/行为策略的松耦合注册中枢（docs/14 §1）。
## 复用 Sim.backend=null 的鸭子类型范式：Sim 持 `var ext: Object = null`，所有挂点 `if ext != null: ...` 短路。
## ext=null 或空注册 → 引擎行为逐字节不变（挂点无副作用）。注入方式（与 S.backend=null 同位）：
##   var ext := SimExtensions.new(); ext.register_nightly(MyHook.new()); ext.freeze(); S.ext = ext; S.start_new(seed)
##
## 四类可选契约（鸭子类型，用 has_method 判定即可，无需继承）：
##   ScenarioProvider   : id()->String, seed(S)->void, distorts_harmony()->bool
##   CandidateProvider  : id()->String, candidates(S, ag)->Array
##   AcceptanceModifier : id()->String, modify(S, actor, target, action, subject)->float
##   NightlyHook        : id()->String, order()->int, run(S)->void
##   ActionExecutor     : id()->String, execute(S, ag, opt)->bool —— 新动作的效果提交（docs/15 §3 挂点#2）。
##                        处理则返 true；效果自负（改账本须走 S 的既有通道并 _log_event 记账保溯源/digest）。
##
## 确定性铁律（docs/14 §1 两坑）：
##  · 无 live RNG（provider 抖动一律经 S._rng_at(salt,who) 子流）、无 Time/墙钟、无字典插入序依赖。
##  · **注册幂等**：注册只在注入时做一次（绝不在 start_new 内 append，否则 goto_tick 反复 start_new 会翻倍数组 → digest 漂移）。
##    freeze() 仅排序（幂等，可安全重复调用）；start_new 只调 freeze() 不做注册。
##  · **AcceptanceModifier 等值**：内建 modifier 须逐动作等值复刻既有内联修正（对原本不叠加的动作返回 0）。

var _scenarios := {}       # id -> ScenarioProvider
var _cand: Array = []      # CandidateProvider（freeze 后按 id 定序）
var _accept: Array = []    # AcceptanceModifier（freeze 后按 id 定序）
var _nightly: Array = []   # NightlyHook（freeze 后按 (order,id) 定序）
var _execs: Array = []     # ActionExecutor（freeze 后按 id 定序）
var _weights := {}         # 数据驱动效用权重（name -> float）

# ── 注册（只在注入时调，绝不在 start_new 内）───────────────────────────
func register_scenario(p: Object) -> void:
	_scenarios[String(p.id())] = p

func register_candidate(p: Object) -> void:
	_cand.append(p)

func register_acceptance(p: Object) -> void:
	_accept.append(p)

func register_nightly(p: Object) -> void:
	_nightly.append(p)

func register_executor(p: Object) -> void:
	_execs.append(p)

func load_weights(path: String) -> void:
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			_weights = d

func weight(name: String, deflt: float) -> float:
	return float(_weights.get(name, deflt))

## 冻结成确定序只读集合。幂等：仅排序，重复调用安全（goto_tick→start_new 可反复调）。
func freeze() -> void:
	_cand.sort_custom(func(a, b): return String(a.id()) < String(b.id()))
	_accept.sort_custom(func(a, b): return String(a.id()) < String(b.id()))
	_nightly.sort_custom(func(a, b):
		var oa := int(a.order()); var ob := int(b.order())
		if oa != ob: return oa < ob
		return String(a.id()) < String(b.id()))
	_execs.sort_custom(func(a, b): return String(a.id()) < String(b.id()))

# ── 分发（Sim 挂点调用）──────────────────────────────────────────────
func seed_scenario(S: Object, sid: String) -> bool:
	var p = _scenarios.get(sid)
	if p == null:
		return false                 # 无对应 provider → 调用方回落到内建 if/elif
	p.seed(S)
	return true

func distorts_harmony(sid: String) -> bool:
	var p = _scenarios.get(sid)
	return p != null and bool(p.distorts_harmony())

## 周更编剧：日界把当前 active 场景 provider 的 schedule 中 day==当天 的补丁注入（provider 无 seed_day → 跳过=零扰动）。
func seed_day(S: Object, sid: String, day: int) -> void:
	var p = _scenarios.get(sid)
	if p != null and p.has_method("seed_day"):
		p.seed_day(S, day)

func candidates(S: Object, ag: Dictionary) -> Array:
	var out: Array = []
	for p in _cand:
		out.append_array(p.candidates(S, ag))
	return out

func accept_delta(S: Object, actor: Dictionary, target: Dictionary, action: String, subject: String) -> float:
	var s := 0.0
	for m in _accept:
		s += float(m.modify(S, actor, target, action, subject))
	return s

func nightly(S: Object) -> void:
	for h in _nightly:
		h.run(S)

## 效果提交分发（docs/15 §3 挂点#2）：按 id 定序轮询，首个认领者执行并返 true；无人认领返 false（调用方不落任何通用效果）。
func execute(S: Object, ag: Dictionary, opt: Dictionary) -> bool:
	for e in _execs:
		if bool(e.execute(S, ag, opt)):
			return true
	return false
