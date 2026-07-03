extends SceneTree
## sim_soak.gd — headless 单 seed 详细诊断 + 社交不变量门（范式同《小鱼岛》sim.gd）。
## 用法：godot --headless --path . --script res://scripts/sim_soak.gd -- --days 30 [--seed 20260626]
## 只驱动 Sim 规则引擎、无 UI/网络/LLM（确定性）。任一不变量不过 → quit(1)（可当 bench build_check）。
## 不变量为单一真相源 bench/Invariants.gd（与跨 seed 的 bench/Harness.gd 共用）；本脚本=单 seed 详细视图。
## 关键：--script 模式不加载 autoload，故手动 preload Sim.gd 实例化（backend 留 null → 内置 logic），同 22nd sim.gd。

const Inv = preload("res://bench/Invariants.gd")
const Met = preload("res://bench/Metrics.gd")
const SimExt = preload("res://scripts/SimExtensions.gd")            # L7 注册中枢（docs/14 §1）
const DataScen = preload("res://scripts/DataScenarioProvider.gd")  # 数据驱动场景 provider

func _init() -> void:
	var days := 30
	var seed := 20260626
	var scen := ""
	var _agents := 0
	var _period := 1
	var _lod := false
	var _lod_agg := false        # --lod-agg：L3 激进 LOD（远端只被动维持）
	var _cap := 0                # --cap：near cohort=最近 K 人（0=按半径）
	var _trace := false          # --trace-rhythm：采样 need 均值随天数轨迹 + 各时段「正在满足的需求」分布(同频诊断)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
		elif args[i] == "--scenario" and i + 1 < args.size():
			scen = args[i + 1]
		elif args[i] == "--agents" and i + 1 < args.size():
			_agents = int(args[i + 1])
		elif args[i] == "--period" and i + 1 < args.size():
			_period = int(args[i + 1])
		elif args[i] == "--lod":
			_lod = true
		elif args[i] == "--lod-agg":
			_lod_agg = true
		elif args[i] == "--cap" and i + 1 < args.size():
			_cap = int(args[i + 1])
		elif args[i] == "--trace-rhythm":
			_trace = true

	var S = preload("res://scripts/Sim.gd").new()
	get_root().add_child(S)
	S._load_data()              # 不依赖 _ready 时序，确保数据就绪（同 22nd）
	S.auto_run = false
	S.backend = null            # soak 走内置确定性 logic
	S.scenario = scen           # S3 定向场景（""/faction/betray/freerider）
	# L7：若 --scenario 指向 data/scenarios/<id>.json → 经注册中枢加载数据驱动场景（零 GDScript 加场景，docs/14 §1）。
	if scen != "" and FileAccess.file_exists("res://data/scenarios/%s.json" % scen):
		var _ext = SimExt.new()
		_ext.register_scenario(DataScen.new(scen))
		_ext.freeze()
		S.ext = _ext
	S.spawn_count = _agents     # 扩 N（0=数据原样）
	S.decide_period = _period   # L2 决策切片周期（1=不切片）
	S.lod = _lod                # L3 保守 LOD
	S.lod_aggregate = _lod_agg  # L3 激进 LOD
	S.lod_near_cap = _cap       # near cohort 上限（最近 K 人）
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)

	var starved := 0            # 任一需求触底的 tick 计数
	var day_need := {}          # day -> {need -> [sum,cnt]}（need 均值随天数）
	var phase_serve := {}       # phase 标签 -> {need -> cnt}（各时段正被满足的需求）
	var _t_loop := Time.get_ticks_msec()   # ⏱ 分相计时（仅诊断,不入 sim 状态）
	for t in range(total):
		S.tick()
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
		if _trace:
			_sample_rhythm(S, day_need, phase_serve)

	var _loop_ms := Time.get_ticks_msec() - _t_loop
	print("⏱ tick-loop=%d ms (%.3f ms/tick, N=%d)" % [_loop_ms, float(_loop_ms) / float(maxi(1, total)), S.agents.size()])
	if _trace:
		_report_rhythm(S, days, day_need, phase_serve)
	var code := _report_and_check(S, days, seed, starved)
	quit(code)

## 固定 5 时段（探针自带,不依赖 rhythm.json → 稳定测量仪）：夜/晨/昼/暮/夜2。
func _phase_label(tod: float) -> String:
	if tod < 0.2: return "夜"
	elif tod < 0.4: return "晨"
	elif tod < 0.6: return "昼"
	elif tod < 0.8: return "暮"
	return "夜2"

func _served_need(opt) -> String:
	if opt == null: return ""
	var kind := String(opt.get("kind", "object"))
	if kind == "social": return "social"
	if kind == "object": return String(opt.get("need", ""))
	return ""   # attend 等不计

func _sample_rhythm(S, day_need: Dictionary, phase_serve: Dictionary) -> void:
	var d: int = S.day
	var ph := _phase_label(S.time_of_day())
	if not day_need.has(d): day_need[d] = {}
	if not phase_serve.has(ph): phase_serve[ph] = {}
	var dn: Dictionary = day_need[d]
	var ps: Dictionary = phase_serve[ph]
	for ag in S.agents:
		for nid in ag["needs"]:
			var acc: Array = dn.get(nid, [0.0, 0])
			acc[0] = float(acc[0]) + float(ag["needs"][nid]); acc[1] = int(acc[1]) + 1
			dn[nid] = acc
		var served := _served_need(ag.get("option"))
		if served != "":
			ps[served] = int(ps.get(served, 0)) + 1

func _report_rhythm(S, days: int, day_need: Dictionary, phase_serve: Dictionary) -> void:
	var order := ["hunger", "energy", "social", "fun", "hygiene"]
	print("\n— 节律诊断①：need 均值随天数（稳态判定：应收敛到带内、非单调下滑/贴顶）—")
	for d in [1, 5, 10, 15, 20, days]:
		if not day_need.has(d): continue
		var parts := []
		for nid in order:
			var acc: Array = (day_need[d] as Dictionary).get(nid, [0.0, 1])
			parts.append("%s=%.0f" % [nid, float(acc[0]) / float(maxi(1, int(acc[1])))])
		print("  第%02d天: %s" % [d, "  ".join(parts)])
	print("— 节律诊断②：各时段「正在满足的需求」占比（同频信号：接节律前应各时段近似均匀）—")
	for ph in ["夜", "晨", "昼", "暮", "夜2"]:
		if not phase_serve.has(ph): continue
		var tbl: Dictionary = phase_serve[ph]
		var tot := 0
		for k in tbl: tot += int(tbl[k])
		var parts := []
		for nid in order:
			parts.append("%s=%d%%" % [nid, int(round(100.0 * float(int(tbl.get(nid, 0))) / float(maxi(1, tot))))])
		print("  %-3s: %s  (n=%d)" % [ph, "  ".join(parts), tot])

func _report_and_check(S, days: int, seed: int, starved: int) -> int:
	var log: Array = S.event_log
	var accepted: Array = []
	for e in log:
		if bool(e["accepted"]):
			accepted.append(e)

	print("=== 社交底座 soak  days=%d seed=%d agents=%d ===" % [days, seed, S.agents.size()])
	print("event_log: %d 条（接受 %d / 拒绝 %d）  总 tick=%d" % [log.size(), accepted.size(), log.size() - accepted.size(), S.tick_no])
	var by_type := {}
	for e in accepted:
		by_type[e["type"]] = int(by_type.get(e["type"], 0)) + 1
	var bt := []
	for k in by_type:
		bt.append("%s=%d" % [k, by_type[k]])
	print("接受明细: " + (" ".join(bt) if not bt.is_empty() else "(无)"))

	for ag in S.agents:
		var parts := []
		var nsum := 0.0
		var n := 0
		for nid in ag["needs"]:
			parts.append("%s=%d" % [nid, int(ag["needs"][nid])])
			nsum += float(ag["needs"][nid]); n += 1
		var avg := nsum / float(maxi(1, n))
		var flag := "OK " if avg > 30.0 else "LOW"
		print("  [%s] %s  均=%.0f  关系=%d人 记忆=%d条  %s" % [
			flag, S._name(ag), avg, ag["relationships"].size(), ag["memory"].items.size(), " ".join(parts)])

	# 系统指标（LOD ablation 用：lod off/on 下 PI/cascade/Gini 应分布不漂）
	print("系统指标: PI %.3f  cascade %d  Gini %.3f" % [Met.polarization(S), Met.cascade_max(S), Met.gini_acceptance(S)])

	# ── 不变量（单一真相源 bench/Invariants.gd；与多 seed Harness 共用，避免逻辑漂移）──
	var _tc := Time.get_ticks_msec()
	var checks: Array = Inv.check_all(S, starved)
	print("⏱ check_all=%d ms" % (Time.get_ticks_msec() - _tc))
	print("\n— 不变量（详情见每条 detail）—")
	var fails := 0
	for c in checks:
		var mark := "✅" if c["ok"] else "❌"
		print("  %s #%02d %s  %s" % [mark, int(c["id"]), String(c["name"]), String(c["detail"])])
		if not c["ok"]:
			fails += 1
	if fails == 0:
		print("\n✅ 全部 %d 条断言通过（承诺+冲突+S1 声誉/放逐/恢复+S2 意见/有界信任/谣言变冷）。" % checks.size())
		print("   跨 seed 网格 + 确定性校验请跑 bench/Harness.gd（Causal Bench S0）。")
		return 0
	print("\n❌ %d 条断言未通过（见上 ❌ 行）。" % fails)
	return 1
