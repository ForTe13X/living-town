extends SceneTree
## bench/Harness.gd — Causal Bench S0：不变量回归门，跨 seed 网格 + 真确定性校验 + 跨进程金标锚。
## 用法：godot --headless --path . --script res://bench/Harness.gd -- [--suite S0] [--seeds 1-12] [--days 60] [--det 3]
##   --seeds  种子范围 "a-b" 或单值（默认 1-12）          --days  每局天数（默认 60，覆盖 S2 谣言变冷轨迹）
##   --det    抽样 N 个种子做"同 seed 两跑摘要一致"校验（默认 3，0=跳过）
##   --golden <path>       载入金标表比对（任一 seed 的 digest/event_digest 对不上 → 门红 exit 1）
##   --bake-golden <path>  重烘金标表（仅在【有意的行为变更】后手工执行；会覆盖 seeds 段，保留 scenarios 段）
## 输出：每 seed 一行 [S0]{json}（JSONL，便于机读）+ 每不变量跨 seed 通过率表 + 套件级活性表 + 最终红绿门；任一失败 quit(1)。
## 纪律同 sim_soak：--script 不加载 autoload → preload Sim/Invariants 实例化，backend=null 走确定性 logic。
##
## 三层证据（为什么要金标）：
##   L1 同进程同 seed 两跑一致（--det）      → 只证「同一二进制、同一进程内可复现」
##   L2 两路摘要（批量 Inv.digest + 增量 Sim.event_digest）覆盖不同字段集 → 双独立见证
##   L3 【金标】跨进程/跨提交/跨引擎版本比对已提交的期望值 → 才真正锚住红线#1「逐字节可回放」。
##   没有 L3 时，Godot 升级或一次候选枚举重构可以把全部历史改写而 CI 全绿
##   （_aid() 用引擎内部的 String.hash() 播种；tie-break 抖动按候选【数组下标】加盐）。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

const GOLDEN_DEFAULT := "res://bench/golden_digests.json"

## 软（涌现统计）不变量的跨 seed 通过率门：比率制，且【永不严于】历史的「允许 1 个 seed 反转」。
##   旧实现是 soft_min = seeds-1（绝对容差 1）——网格越宽门越严，1-24 会在零代码变更下变红。
const SOFT_RATE := 0.90

## 套件级活性（liveness）门控的事件类。
## 为什么需要：23 条硬不变量里 22 条是「若 X 发生则 X 良构」——空输入恒过
##   （#29 在 aid_accepted<8 时直接过 Invariants.gd:294；#34/#35 在 economy.json 缺失时恒过 :331/:334；
##    #37 在 election_log 为空时恒过 :353）。所以「整个子系统被关掉」是 CI 全绿的。
## 选取标准（实测，不拍脑袋）：只门控在网格上【每一个 seed 都出现】的类 → 与网格大小无关，单 seed 快跑也不误红。
## 值 = 该类被门控所需的【最短天数】。有些机制天生要时间：invite→meet 是「约了，到点真赴约」，
##   confide 要先攒到信任。用实测的最短 horizon 而不是一刀切，门在每个 horizon 上都尽可能多地生效。
## 2026-07-25 实测（backend=null，seeds 1-3 × {20,30}d 与 1-12 × 60d 三次网格）：
##   days≥20 即 3/3 seed 出现：pay · greet · gossip_rep · discuss · conflict · give · confront ·
##                             apologize · endorse · rally_oust · gossip · festival_spawn · election
##   days≥30 才出现：invite · meet          days≥60 才出现：confide
##   60d×12seed 计数：pay 8381 · greet 5997 · gossip_rep 5344 · invite 1345 · meet 1344 · discuss 1308 ·
##     conflict 908 · give 432 · confront 360 · apologize 348 · endorse 250 · rally_oust 203 ·
##     gossip 177 · festival_spawn 80 · confide 73 · election 48（均覆盖 12/12 seed）
## 【故意不门控】的类，因为实测就是 0 / 近 0，门控它们等于当场把 CI 焊红：
##   aid=0 · betray=0 · leak=0 · mediate=0 · pact_dissolved=0 · pact_formed=1（只出现在 1/12 个 seed）
##   ↑ 这正是本门要暴露的东西：#22/#23/#24（背叛三条硬不变量）与 #29（互助偏内）今天全绿，
##     纯粹是因为 betray/aid 一次都没发生——「若 X 发生则 X 良构」对空输入恒真。
##     它们归零是【已知的产品缺口】（暖向社交太稀），不是回归；等基线调平后再把它们加进本表。
const LIVENESS_GATED := {
	"greet": 20, "give": 20, "gossip": 20, "gossip_rep": 20, "discuss": 20,
	"conflict": 20, "confront": 20, "apologize": 20, "endorse": 20, "rally_oust": 20,
	"pay": 20, "election": 20, "festival_spawn": 20,
	"invite": 30, "meet": 30,
	"confide": 60,
}

var _shadow := false        # --shadow：开 shadow 探针（Sim.shadow_on）——纯观测，digest 应逐字节不变
var _shadow_dump := ""      # --shadow-dump <path>：把每 seed 的 shadow_trace 追加成 JSONL（供反事实 / #15v2 分析）
var _agents := 0            # --agents N：克隆扩容到 N 个 agent（Sim.spawn_count）；0=数据原样 cast，逐字节不变

func _init() -> void:
	var seeds := _parse_seeds("1-12")
	var seeds_spec := "1-12"
	var days := 60
	var det_n := 3
	var golden_path := ""
	var bake_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds_spec = args[i + 1]; seeds = _parse_seeds(seeds_spec)
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--det" and i + 1 < args.size():
			det_n = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			_agents = int(args[i + 1])   # 扩 N 规模诊断
		elif args[i] == "--shadow":
			_shadow = true
		elif args[i] == "--shadow-dump" and i + 1 < args.size():
			_shadow = true; _shadow_dump = args[i + 1]
		elif args[i] == "--golden" and i + 1 < args.size():
			golden_path = norm_path(args[i + 1])
		elif args[i] == "--bake-golden" and i + 1 < args.size():
			bake_path = norm_path(args[i + 1])
		elif args[i] == "--suite" and i + 1 < args.size():
			pass  # 目前仅 S0；保留位给 S5
	if _shadow_dump != "":
		var f0 := FileAccess.open(_shadow_dump, FileAccess.WRITE)   # 清空/新建
		if f0: f0.close()

	print("=== Causal Bench S0 · 不变量回归门  seeds=%s days=%d ===" % [str(seeds), days])
	var inv_pass := {}      # id -> 通过的 seed 数
	var inv_name := {}      # id -> 名称
	var inv_fail_eg := {}   # id -> 一个失败样例 "seed N: detail"
	var inv_ids := {}       # id -> true（动态收集，替代写死的 range(1,38)）
	var seed_pass := 0
	var first_run_digest := {}  # seed -> 批量摘要（供确定性校验）
	var first_run_edig := {}    # seed -> 增量滚动摘要（L4，独立见证）
	var first_run_events := {}  # seed -> 事件数（金标附带信息）
	var live_total := {}    # 活性：类 -> 全网格出现次数
	var live_seeds := {}    # 活性：类 -> 出现过该类的 seed 数

	for sd in seeds:
		var res := _run_once(sd, days)
		var S = res["S"]
		first_run_digest[sd] = Inv.digest(S)
		first_run_edig[sd] = S.event_digest
		first_run_events[sd] = S.event_log.size()
		_tally_liveness(S, live_total, live_seeds)
		var checks: Array = Inv.check_all(S, int(res["starved"]))
		var hard_fails: Array = []
		var soft_fails: Array = []
		var diag_fails: Array = []
		for c in checks:
			inv_name[c["id"]] = c["name"]
			inv_ids[int(c["id"])] = true
			if c["ok"]:
				inv_pass[c["id"]] = int(inv_pass.get(c["id"], 0)) + 1
			else:
				if int(c["id"]) in Inv.DIAG_IDS:
					diag_fails.append(int(c["id"]))       # 诊断档：报告，不入门
				elif bool(c.get("hard", false)):
					hard_fails.append(int(c["id"]))
				else:
					soft_fails.append(int(c["id"]))
				if not inv_fail_eg.has(c["id"]):
					inv_fail_eg[c["id"]] = "seed %d: %s" % [sd, c["detail"]]
		# L4 两分落到 CI（docs/12 R2）：硬(结构)不变量每 seed 必绿；软(涌现统计)不再单 seed 硬断言,
		# 改为跨种子通过率门(见下)——单 seed 的涌现反转(如节日桥接派系削掉 inv26 的 margin)不再误伤整门。
		if hard_fails.is_empty():
			seed_pass += 1
		# JSONL 机读行（digest/event_digest 以字符串输出：event_digest 可达 2^63，JSON number 会丢精度）
		print("[S0] " + JSON.stringify({"seed": sd, "days": days, "pass": hard_fails.is_empty(),
			"hard_fails": hard_fails, "soft_fails": soft_fails, "diag_fails": diag_fails,
			"events": S.event_log.size(), "digest": str(first_run_digest[sd]),
			"event_digest": str(first_run_edig[sd])}))
		if _shadow_dump != "":
			_dump_shadow(sd, S.shadow_trace)   # 只在主循环 dump 一次（det 复跑不再重复）
		_dispose(S)

	# ── 确定性校验：抽样种子两跑，摘要必须一致 ──
	var det_seeds: Array = seeds.slice(0, mini(det_n, seeds.size()))
	var det_ok := 0
	var det_fail: Array = []
	for sd in det_seeds:
		var res2 := _run_once(sd, days)
		var d2: int = Inv.digest(res2["S"])
		var e2: int = res2["S"].event_digest
		_dispose(res2["S"])
		# 两路摘要(批量 + 增量滚动)都须一致 → 双独立见证确定性
		if d2 == int(first_run_digest[sd]) and e2 == int(first_run_edig[sd]):
			det_ok += 1
		else:
			det_fail.append(sd)

	# ── 报告：硬=每 seed 必绿；软=跨种子通过率门（比率制）；诊断=只报告 ──
	var soft_min := soft_threshold(seeds.size())
	print("\n— 不变量跨 seed 通过率（硬=全绿必需 / 软=通过率≥%d/%d / 诊断=只报不门）—" % [soft_min, seeds.size()])
	var hard_red := false
	var soft_red := false
	var ids_sorted: Array = inv_ids.keys()
	ids_sorted.sort()
	for id in ids_sorted:
		var p := int(inv_pass.get(id, 0))
		var is_diag: bool = id in Inv.DIAG_IDS
		var is_hard: bool = (id in Inv.HARD_IDS) and not is_diag
		var need := (0 if is_diag else (seeds.size() if is_hard else soft_min))
		var mark := "🔎" if is_diag else ("✅" if p >= need else "❌")   # 诊断永远不是红/绿，只是观测
		if (not is_diag) and p < need:
			if is_hard: hard_red = true
			else: soft_red = true
		var tag := "[诊断]" if is_diag else ("[硬]" if is_hard else "[软]")
		var line := "  %s #%02d %s%s  %d/%d" % [mark, id, tag, String(inv_name.get(id, "?")), p, seeds.size()]
		if is_diag:
			line += "  (不入门·度量已知泄漏,见 docs/31)"
		if inv_fail_eg.has(id):
			line += "   首违 " + String(inv_fail_eg[id])
		print(line)

	# ── 套件级活性：硬不变量几乎全是「若 X 发生则良构」，X 归零它们也全绿 → 补一条「X 还在发生」 ──
	print("\n— 套件级活性（跨全网格计数；门控类归零即红）—")
	var live_red: Array = []
	var live_skipped: Array = []
	var live_gated_n := 0
	var live_keys: Array = live_total.keys()
	live_keys.sort()
	for k in live_keys:
		var need_d := int(LIVENESS_GATED.get(k, -1))
		var gated: bool = need_d >= 0 and days >= need_d
		var tag := "🔒" if gated else ("⏳" if need_d >= 0 else "  ")
		print("  %s %-18s 次数=%-6d 覆盖 seed=%d/%d%s" % [tag, k, int(live_total[k]),
			int(live_seeds.get(k, 0)), seeds.size(),
			("   (需 days≥%d 才入门，本跑 days=%d)" % [need_d, days]) if (need_d >= 0 and not gated) else ""])
	for k in LIVENESS_GATED:
		if days < int(LIVENESS_GATED[k]):
			live_skipped.append(k)          # horizon 不够，该机制本就没到发生的时候 → 不门（并明示跳过）
			continue
		live_gated_n += 1
		if int(live_total.get(k, 0)) <= 0:
			live_red.append(k)
	if not live_skipped.is_empty():
		live_skipped.sort()
		print("  ⏳ 本跑 days=%d，以下类未达最短 horizon 故不入门：%s" % [days, str(live_skipped)])
	if live_red.is_empty():
		print("  ✅ 门控事件类 %d 种全部仍在发生" % live_gated_n)
	else:
		print("  ❌ 门控事件类归零：%s —— 某个子系统被关掉了，而硬不变量对空输入恒过" % str(live_red))

	# ── 金标：跨进程/跨提交/跨引擎版本的锚（红线#1 真正的机检点）──
	var golden_red := false
	var golden_note := "(未启用 --golden)"
	if bake_path != "":
		golden_note = _bake_golden(bake_path, seeds_spec, days, seeds, first_run_digest, first_run_edig,
			first_run_events, live_total, live_seeds)
	if golden_path != "":
		var gres := _check_golden(golden_path, days, seeds, first_run_digest, first_run_edig)
		golden_red = bool(gres["red"])
		golden_note = String(gres["note"])
	print("\n— 金标（跨进程锚）—\n  " + golden_note)

	print("\n— 确定性 —")
	if det_n <= 0:
		print("  (跳过)")
	elif det_fail.is_empty():
		print("  ✅ 同 seed 两跑摘要一致(批量+增量滚动)  %d/%d" % [det_ok, det_seeds.size()])
	else:
		print("  ❌ 非确定 seeds=%s" % str(det_fail))

	var gate_ok := (seed_pass == seeds.size()) and not hard_red and not soft_red \
		and live_red.is_empty() and not golden_red and (det_n <= 0 or det_fail.is_empty())
	print("\n=== S0 GATE: %s  (硬不变量 seed %d/%d 全绿, 软通过率门 ≥%d/%d(%d%%) %s, 活性 %s, 金标 %s, det %d/%d) ===" % [
		"PASS ✅" if gate_ok else "FAIL ❌", seed_pass, seeds.size(),
		soft_min, seeds.size(), int(round(SOFT_RATE * 100.0)),
		"过" if not soft_red else "破", "过" if live_red.is_empty() else "破",
		"过" if not golden_red else "破", det_ok, det_seeds.size()])
	quit(0 if gate_ok else 1)

## 软门阈值：比率制（≥90%），但用 seeds-1 封顶 → 【永不严于】历史的绝对容差 1，小网格(1-3 seed)行为不变。
##   n=1 → 0（恒过，同旧）；n=3 → 2（容 1，同旧）；n=12 → 11（容 1，同旧）；n=24 → 22（容 2，旧为 23 会误红）。
static func soft_threshold(n: int) -> int:
	if n <= 1:
		return 0
	return mini(int(ceil(float(n) * SOFT_RATE)), n - 1)

## 把一局的 event_log 折成活性计数（类 -> 次数 / 覆盖 seed 数）。
func _tally_liveness(S, total: Dictionary, per_seed: Dictionary) -> void:
	var here := {}
	for e in S.event_log:
		var k := live_key(e)
		total[k] = int(total.get(k, 0)) + 1
		here[k] = true
	for k in here:
		per_seed[k] = int(per_seed.get(k, 0)) + 1

## 事件 → 活性分类键。pact/world 靠 note 细分（formed/dissolved、节日 spawn/despawn）。
static func live_key(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	var note := String(e.get("note", ""))
	if t == "pact":
		if note == "formed": return "pact_formed"
		if note.begins_with("dissolved"): return "pact_dissolved"
		return "pact_other"
	if t == "world":
		if String(e.get("target", "")).begins_with("fest_"):
			return "festival_spawn" if note == "spawn" else "festival_despawn"
		return "world_other"
	return t

# ── 金标读写 ────────────────────────────────────────────────────────────────
## 允许传 "game/bench/x.json"（仓库相对，CI 里顺手）或 "res://bench/x.json"（引擎内）。
static func norm_path(p: String) -> String:
	var q := p.replace("\\", "/")
	if q.begins_with("res://") or q.begins_with("user://"):
		return q
	if q.begins_with("./"):
		q = q.substr(2)
	if q.begins_with("game/"):
		return "res://" + q.substr(5)
	return q

static func load_golden(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var v = JSON.parse_string(txt)
	return v if v is Dictionary else {}

## ⚠ Godot 的 JSON 解析器把【所有】数字解成 float：读一遍再写回，60 就变成 60.0，
##   而 2^53 以上的整数（event_digest 最大到 2^63）会直接丢精度。
##   → 摘要一律以【字符串】存（load/save 都不碰它们）；days/events 这类小整数在落盘前显式收回 int，
##     免得 Harness 烘完 seeds 段、DetGate 再烘 scenarios 段时把前者的数字改写成浮点。
static func save_golden(path: String, doc: Dictionary) -> bool:
	var d := doc.duplicate(true)
	if d.has("_meta") and (d["_meta"] as Dictionary).has("days"):
		d["_meta"]["days"] = int(d["_meta"]["days"])
	for sec in ["seeds", "scenarios"]:
		if not d.has(sec):
			continue
		_coerce_rows(d[sec], sec == "scenarios")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  ", true) + "\n")
	f.close()
	return true

static func _coerce_rows(node, nested: bool) -> void:
	if not (node is Dictionary):
		return
	for k in node:
		var v = node[k]
		if not (v is Dictionary):
			continue
		if nested:
			_coerce_rows(v, false)
		else:
			for f in ["days", "events"]:
				if v.has(f): v[f] = int(v[f])

## Godot 版本串（金标的 provenance——引擎升级改写历史时，这里能立刻指认元凶）。
static func godot_version() -> String:
	var vi := Engine.get_version_info()
	return "%s.%s" % [String(vi.get("string", "?")), String(vi.get("hash", "")).substr(0, 9)]

func _bake_golden(path: String, seeds_spec: String, days: int, seeds: Array,
		dig: Dictionary, edig: Dictionary, evs: Dictionary,
		live_total: Dictionary, live_seeds: Dictionary) -> String:
	var doc := load_golden(path)        # 保留 DetGate 烘的 scenarios 段
	var tbl := {}
	for sd in seeds:
		tbl[str(sd)] = {
			"digest": str(int(dig[sd])),
			"event_digest": str(int(edig[sd])),
			"days": days,
			"events": int(evs[sd]),
		}
	var live_obs := {}
	for k in live_total:
		live_obs[k] = {"count": int(live_total[k]), "seeds": int(live_seeds.get(k, 0))}
	var meta: Dictionary = doc.get("_meta", {})
	meta["godot"] = godot_version()
	meta["backend"] = "null (零模型 logic 底座；红线#2)"
	meta["seeds"] = seeds_spec
	meta["days"] = days
	meta["baked_by"] = "godot --headless --path game --script res://bench/Harness.gd -- --seeds %s --days %d --bake-golden game/bench/golden_digests.json" % [seeds_spec, days]
	meta["liveness_observed"] = live_obs
	meta["note"] = "跨进程金标：红线#1『逐字节可回放』的机检锚。只在【有意的行为变更】后重烘，" \
		+ "且重烘必须与该变更同一个 commit、并在 commit message 里写明为什么摘要该动。" \
		+ "CI 意外变红时，正确反应是查代码，不是重烘。摘要以【字符串】存：event_digest 可达 2^63，JSON number 会丢精度。"
	doc["_meta"] = meta
	doc["seeds"] = tbl
	if save_golden(path, doc):
		return "🔨 已烘 %d 个 seed 到 %s（godot %s, days=%d）" % [seeds.size(), path, godot_version(), days]
	return "❌ 写入失败：%s" % path

func _check_golden(path: String, days: int, seeds: Array, dig: Dictionary, edig: Dictionary) -> Dictionary:
	var doc := load_golden(path)
	if doc.is_empty():
		return {"red": true, "note": "❌ 金标文件缺失/不可解析：%s" % path}
	var tbl: Dictionary = doc.get("seeds", {})
	if tbl.is_empty():
		return {"red": true, "note": "❌ 金标文件无 seeds 段：%s" % path}
	var gmeta: Dictionary = doc.get("_meta", {})
	var cmp_n := 0
	var bad: Array = []
	for sd in seeds:
		var key := str(sd)
		if not tbl.has(key):
			continue                      # 网格比金标宽（如 1-24 vs 金标 1-12）→ 多出的 seed 不比
		var row: Dictionary = tbl[key]
		if int(row.get("days", -1)) != days:
			continue                      # 天数不同 → 摘要本就不同，跳过而非误红（支持 CI_DAYS=20 的快跑）
		cmp_n += 1
		var exp_d := String(row.get("digest", ""))
		var exp_e := String(row.get("event_digest", ""))
		var got_d := str(int(dig[sd]))
		var got_e := str(int(edig[sd]))
		if exp_d != got_d:
			bad.append("seed %d digest       期望 %s  实得 %s" % [sd, exp_d, got_d])
		if exp_e != got_e:
			bad.append("seed %d event_digest 期望 %s  实得 %s" % [sd, exp_e, got_e])
	if not bad.is_empty():
		var msg := "❌ 金标不符（%d 处；金标烘于 godot %s）：\n" % [bad.size(), String(gmeta.get("godot", "?"))]
		for b in bad:
			msg += "      " + b + "\n"
		msg += "    → 行为变了。若是【无意】的（引擎升级 / 候选枚举重构 / _aid() 播种变化），这是红线#1 被破，查代码；\n"
		msg += "      若是【有意】的基线移动，才重烘：--bake-golden game/bench/golden_digests.json（与该变更同一 commit）。"
		return {"red": true, "note": msg}
	if cmp_n == 0:
		return {"red": false, "note": "⚠ 金标 0 条可比（seed/days 与金标表不重叠）——本跑未构成跨进程校验"}
	return {"red": false, "note": "✅ 金标一致 %d/%d seed（烘于 godot %s，本机 %s）" % [
		cmp_n, seeds.size(), String(gmeta.get("godot", "?")), godot_version()]}

## 跑一局确定性仿真，返回 {S, starved}。S 由调用方 _dispose。
func _run_once(seed: int, days: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.shadow_on = _shadow   # 探针开关（默认 false → 逐字节不变）；set before start_new
	if _agents > 0:
		S.spawn_count = _agents   # 扩 N 规模诊断（克隆扩容；0=数据原样 cast）
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var starved := 0
	for t in range(total):
		S.tick()
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
	return {"S": S, "starved": starved}   # 注：dump 不在此做——否则 det 复跑(也调 _run_once)会把同 seed 追加两次（评审 P1）

## 把一 seed 的 shadow_trace 追加进 JSONL（每行一条决策，带 seed 前缀）。
func _dump_shadow(seed: int, trace: Array) -> void:
	var f := FileAccess.open(_shadow_dump, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	for rec in trace:
		var r: Dictionary = (rec as Dictionary).duplicate()
		r["seed"] = seed
		f.store_line(JSON.stringify(r))
	f.close()

func _dispose(S) -> void:
	get_root().remove_child(S)
	S.free()

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		var a := int(ab[0])
		var b := int(ab[1])
		for s in range(a, b + 1):
			out.append(s)
	elif "," in spec:
		for s in spec.split(","):
			out.append(int(s))
	else:
		out.append(int(spec))
	return out
