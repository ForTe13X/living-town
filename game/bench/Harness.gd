extends SceneTree
## bench/Harness.gd — Causal Bench S0：不变量回归门，跨 seed 网格 + 真确定性校验 + 跨进程金标锚。
## 用法：godot --headless --path . --script res://bench/Harness.gd -- [--suite S0] [--seeds 1-12] [--days 60] [--det 3]
##   --seeds  种子范围 "a-b" 或单值（默认 1-12）          --days  每局天数（默认 60，覆盖 S2 谣言变冷轨迹）
##   --det    抽样 N 个种子做"同 seed 两跑摘要一致"校验（默认 3，0=跳过）
##   --golden <path>       载入金标表比对（任一 seed 的 digest/event_digest/chain 对不上 → 门红 exit 1）
##   --bake-golden <path>  重烘金标表（仅在【有意的行为变更】后手工执行；会覆盖 seeds 段，保留 scenarios 段）
##   --chain-dump <path>   把逐 tick 前缀链全量写出（每 seed 一行）——排查"第几 tick 开始分叉"的参照物
##   --chain-ref <path>    与一份 --chain-dump 比对，报出【精确到 tick】的首个分叉点
##   --permute N           仅测试：N!=0 时打乱候选数组再评分（1=逆序 2=洗牌 3=枚举出口洗牌）。
##                         置换不变性机检——tie-break 的盐取自候选身份而非下标，故 digest 应【一字不变】。
## 输出：每 seed 一行 [S0]{json}（JSONL，便于机读）+ 每不变量跨 seed 通过率表 + 套件级活性表 + 最终红绿门；任一失败 quit(1)。
## 纪律同 sim_soak：--script 的 _init() 阶段 autoload 尚未挂上（docs/41 §2 更正：autoload 其实是加载的） → preload Sim/Invariants 实例化，backend=null 走确定性 logic。
##
## 四层证据（为什么要金标 + 前缀链）：
##   L1 同进程同 seed 两跑一致（--det）      → 只证「同一二进制、同一进程内可复现」
##   L2 两路摘要（批量 Inv.digest + 增量 Sim.event_digest）覆盖不同字段集 → 双独立见证
##   L3 【金标】跨进程/跨提交/跨引擎版本比对已提交的期望值 → 才真正锚住红线#1「逐字节可回放」。
##   L4 【逐 tick 前缀链 chain】H_t = h(H_{t-1} ‖ 状态_t ‖ 事件_t)：
##      L1-L3 全是【终态/滚动汇总】——中途分叉、末尾又合流的轨迹能把差异抹平（自愈路径确实存在：
##      LOD 生存兜底、承诺 pre-empt、需求钳位），且它们说不出【第一个分叉的 tick】。
##      链把每个 tick 的活状态串成不可复原的前缀 → 瞬时分叉也留痕，并能定位首个分叉 tick。
##
## 【B9】此前的两颗雷已拆（见 Sim.gd）：
##   (a) tie-break 抖动曾按候选的【数组下标】加盐 → 任何不改候选集合、只改枚举次序的重构都会静默改写全部历史。
##       现改为按候选【身份】(_cand_salt) 加盐 → --permute 可机检"置换不变"。
##   (b) _aid()/event_digest/Inv.digest 曾用引擎内部的 String.hash() → Godot 换版本即改写金标。
##       现改为仓库自有的 FNV-1a/32（Sim.fnv1a32，带提交进源码的测试向量），启动即自检。

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
##
## > **⚠ 2026-08-01 W1 更正：上面这一段里 `aid=0` 与 `pact_formed=1` 【已经过期】，而它们是这张表
## > 不收 `aid` 的【理由】——理由没了，表却没跟着改。** 那句话写于 2026-07-25，而**当天晚些时候的 B7**
## > 就把 `AID_NEED_TH` 30→60、`COMPLEMENT_LOW` 35→50 重标了一遍（见 Sim.gd 那段 B7 注释），
## > 互助窗口从此打开。出货树实测（backend=null，60 天）：
## >   N=12 seeds 1-12 **aid 68 次 · 覆盖 11/12**；N=16 seeds 1-12 **156 次 · 11/12**；
## >   seeds 13-30 **110 次 · 17/18**；seeds 31-60 **180 次 · 29/30**。
## > ⇒ 「B7 之后回来把 aid 加进本表」这件事**没有人做**，于是 `aid`（连同 #29）在 5 个 wave 里
## > 一直是这张表的盲区。下面的 `LIVENESS_QUORUM` 就是补这一格的，**但补的是"还活着"，不是"没变少"**。
const LIVENESS_GATED := {
	"greet": 20, "give": 20, "gossip": 20, "gossip_rep": 20, "discuss": 20,
	"conflict": 20, "confront": 20, "apologize": 20, "endorse": 20, "rally_oust": 20,
	"pay": 20, "election": 20, "festival_spawn": 20,
	"invite": 30, "meet": 30,
	"confide": 60,
}

## 套件级活性的**第二种形状：法定覆盖（quorum）**。
##
## `LIVENESS_GATED` 判的是「全网格合计 > 0」——对 `aid` 这类**逐 seed 极稀疏**的类没有判别力：
## 60 个 seed 里只要有一个发生过一次就恒绿，而"这个机制在绝大多数镇子里已经不发生了"照样过。
## 本表改判**覆盖率**：该类必须在 ≥ `frac` 比例的 seed 上出现过。
##
## 为什么只收 `aid` 一个（W1 2026-08-01，量过才收）：
##   · **它是 `#29` 的前件**。`#29「I-PACT互助偏内」` 的判据是 `aid_accepted < 8 or aid_nonpact == 0`
##     ——`aid` 越少，这条硬不变量越是**靠样本不够**通过。实测出货树上真正让 `#29` 有牙的 seed：
##     seeds 1-12 **4/12**、seeds 13-30 **5/18**（未开 craft_credit 的基线是 7/12 与 6/18）
##     ⇒ **#29 在六到七成的 seed 上是空过的，而这在 V1 之前就已经如此**（不是谁造成的回归）。
##   · **余量是量出来的，不是拍的**。`frac=0.5` 在下面这 10 条臂上的最低覆盖是 **10/12**
##     （`standing=0.5` 那条），要求 6/12 ⇒ 最小余量 **4 个 seed**；
##     CI 真正跑的两格（N=12 与 N=16，均 seeds 1-12）都是 11/12 ⇒ 余量 5。
##   · **历史负对照是真的**：B7 之前 `aid` 就是 **0/12**（上面那段注释自己记着），本门在那棵树上是红的。
## ⚠ 明写它**抓不到**什么：`aid` 从 118 掉到 68 这类**数量**变化它一概不管（覆盖仍 11/12）。
##   而 W1 实测那个 118→68 本身就不是回归（seeds 13-30 是 105→110、31-60 是 170→180，见 docs/88），
##   ⇒ **这道门刻意不去守一个连"是不是真的"都没立住的数**。它守的是"整条通道死掉"，那一格有过真实先例。
const LIVENESS_QUORUM := {
	"aid": {"days": 60, "frac": 0.5},
}
## quorum 判据的最小网格：单 seed / 极小网格上「覆盖率」没有意义（docs/41 §5：n 很小时读作"分辨不出"）。
const QUORUM_MIN_SEEDS := 4

## 前缀链在金标里的落盘粒度：每 CHAIN_STRIDE tick 存一个检查点（=1 天，Sim.TICKS_PER_DAY）。
## 为什么不逐 tick 落盘：60 天 = 14400 个值 × 12 seed ≈ 1.5MB，把一份人要 review 的金标撑爆。
## 每天一个点 → 金标只涨 ~7KB，就能把首个分叉锁进一个 240-tick 的窗口；
## 要【精确到 tick】用 --chain-dump 存一份参照，再 --chain-ref 比对（全量逐 tick，不进仓库）。
const CHAIN_STRIDE := 240

var _shadow := false        # --shadow：开 shadow 探针（Sim.shadow_on）——纯观测，digest 应逐字节不变
var _shadow_dump := ""      # --shadow-dump <path>：把每 seed 的 shadow_trace 追加成 JSONL（供反事实 / #15v2 分析）
var _agents := 0            # --agents N：克隆扩容到 N 个 agent（Sim.spawn_count）；0=数据原样 cast，逐字节不变
var _permute := 0           # --permute N：仅测试，打乱候选数组（置换不变性机检）；0=off 逐字节不变
var _chain_dump := ""       # --chain-dump <path>：逐 tick 前缀链全量写出（每 seed 一行）
var _chain_ref := ""        # --chain-ref <path>：与一份 dump 比对，报精确到 tick 的首个分叉

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
		elif args[i] == "--permute" and i + 1 < args.size():
			_permute = int(args[i + 1])          # 置换不变性机检（仅测试；0=off）
		elif args[i] == "--chain-dump" and i + 1 < args.size():
			_chain_dump = args[i + 1]
		elif args[i] == "--chain-ref" and i + 1 < args.size():
			_chain_ref = args[i + 1]
		elif args[i] == "--suite" and i + 1 < args.size():
			pass  # 目前仅 S0；保留位给 S5
	if _shadow_dump != "":
		var f0 := FileAccess.open(_shadow_dump, FileAccess.WRITE)   # 清空/新建
		if f0: f0.close()
	if _chain_dump != "":
		var fc := FileAccess.open(_chain_dump, FileAccess.WRITE)
		if fc: fc.close()

	# ── 哈希自检（红线#1 的地基）：仿真的每个随机流、每个金标数字都由 Sim.fnv1a32 定义。
	#    先证明它没变，后面的一切比对才有意义（否则"金标不符"到底是行为变了还是尺子变了分不清）。
	var hash_bad := SimScript.hash_self_test()
	if hash_bad != "":
		print("❌ 项目自有哈希测试向量不符：%s" % hash_bad)
		print("   → Sim.fnv1a32/mix32 的实现或其 UTF-8 输入路径被改动了。这不是行为回归，是【尺子变了】：")
		print("     在修好之前，任何金标比对都无意义。")
		quit(1)
		return
	print("  ✅ 哈希自检：%d 条 fnv1a32 + %d 条 mix32 测试向量全对（项目自有哈希，不依赖引擎 String.hash()）"
		% [SimScript.HASH_VECTORS.size(), SimScript.MIX_VECTORS.size()])

	print("=== Causal Bench S0 · 不变量回归门  seeds=%s days=%d%s ===" % [str(seeds), days,
		("  【--permute %d：候选数组被打乱，digest 应一字不变】" % _permute) if _permute != 0 else ""])
	var inv_pass := {}      # id -> 通过的 seed 数
	var inv_name := {}      # id -> 名称
	var inv_fail_eg := {}   # id -> 一个失败样例 "seed N: detail"
	var inv_ids := {}       # id -> true（动态收集，替代写死的 range(1,38)）
	var seed_pass := 0
	var first_run_digest := {}  # seed -> 批量摘要（供确定性校验）
	var first_run_edig := {}    # seed -> 增量滚动摘要（L4，独立见证）
	var first_run_events := {}  # seed -> 事件数（金标附带信息）
	var first_run_chain := {}   # seed -> 逐 tick 前缀链的终值（L4）
	var first_run_ticks := {}   # seed -> PackedInt64Array 全量逐 tick 链（dump/ref 用，不落金标）
	var live_total := {}    # 活性：类 -> 全网格出现次数
	var live_seeds := {}    # 活性：类 -> 出现过该类的 seed 数

	for sd in seeds:
		var res := _run_once(sd, days)
		var S = res["S"]
		first_run_digest[sd] = Inv.digest(S)
		first_run_edig[sd] = S.event_digest
		first_run_events[sd] = S.event_log.size()
		first_run_chain[sd] = int(res["chain"])
		first_run_ticks[sd] = res["chain_ticks"]
		_tally_liveness(S, live_total, live_seeds)
		var checks: Array = Inv.check_all(S, int(res["starved"]), res["starve_by_need"], res["starve_shape"])
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
		var s0 := {"seed": sd, "days": days, "pass": hard_fails.is_empty(),
			"hard_fails": hard_fails, "soft_fails": soft_fails, "diag_fails": diag_fails,
			"events": S.event_log.size(), "digest": str(first_run_digest[sd]),
			"event_digest": str(first_run_edig[sd]), "chain": str(first_run_chain[sd])}
		# 只在真触底时多带一个键 ⇒ 全绿网格的这一行与改动前逐字节相同（下游解析器不受影响）
		if not (res["starve_by_need"] as Dictionary).is_empty():
			s0["starve_by_need"] = res["starve_by_need"]
		if not (res["starve_shape"] as Dictionary).is_empty():
			s0["starve_shape"] = res["starve_shape"]
		print("[S0] " + JSON.stringify(s0))
		if _shadow_dump != "":
			_dump_shadow(sd, S.shadow_trace)   # 只在主循环 dump 一次（det 复跑不再重复）
		if _chain_dump != "":
			_write_chain_dump(sd, days, first_run_ticks[sd])
		_dispose(S)

	# ── 确定性校验：抽样种子两跑，摘要必须一致 ──
	var det_seeds: Array = seeds.slice(0, mini(det_n, seeds.size()))
	var det_ok := 0
	var det_fail: Array = []
	for sd in det_seeds:
		var res2 := _run_once(sd, days)
		var d2: int = Inv.digest(res2["S"])
		var e2: int = res2["S"].event_digest
		var c2: int = int(res2["chain"])
		var t2: PackedInt64Array = res2["chain_ticks"]
		_dispose(res2["S"])
		# 三路摘要(批量 + 增量滚动 + 逐 tick 前缀链)都须一致 → 独立见证确定性
		if d2 == int(first_run_digest[sd]) and e2 == int(first_run_edig[sd]) and c2 == int(first_run_chain[sd]):
			det_ok += 1
		else:
			# 同 seed 两跑手上都有【全量逐 tick 链】→ 这里能给出精确到 tick 的首个分叉点
			var ft := first_tick_mismatch(first_run_ticks[sd], t2)
			det_fail.append("seed %d%s" % [sd, tick_label(ft) if ft >= 0 else "  （链一致，分歧只在终态摘要）"])

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
		# ⚠️ n<=1 时 soft_min==0 ⇒ 软门的判据退化成「≥0」，恒真。此前这里照样打 ✅，
		#    于是 `--seeds 18` 会打印「✅ #40 … 0/1  首违 seed 18: … 满足率=0.42 … 断供38/60天」
		#    ——一个绿勾，紧挨着它自己的失败明细。T2 实测有【三根独立的棒】被这一行骗过。
		#    这里只改**报告**不改**判据**：退化时打 ⚠️ 而不是 ✅，退出码与 gate_ok 一个字节不变。
		var soft_vacuous: bool = (not is_diag) and (not is_hard) and need == 0
		var mark := "🔎" if is_diag else ("✅" if p >= need else "❌")   # 诊断永远不是红/绿，只是观测
		if soft_vacuous and p < seeds.size():
			mark = "⚠️"
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
		if LIVENESS_QUORUM.has(k):
			tag = "🔒Q" if _quorum_applies(String(k), days, seeds.size()) else "⏳Q"
		print("  %s %-18s 次数=%-6d 覆盖 seed=%d/%d%s" % [tag, k, int(live_total[k]),
			int(live_seeds.get(k, 0)), seeds.size(),
			("   (需 days≥%d 才入门，本跑 days=%d)" % [need_d, days]) if (need_d >= 0 and not gated) else ""])
	# 法定覆盖（quorum）：稀疏类判"还在多少个 seed 上发生"，不判"合计>0"（后者对稀疏类没有判别力）
	for k in LIVENESS_QUORUM:
		if not _quorum_applies(String(k), days, seeds.size()):
			live_skipped.append("%s(quorum)" % k)
			continue
		live_gated_n += 1
		var need_n := int(ceil(float(seeds.size()) * float((LIVENESS_QUORUM[k] as Dictionary)["frac"])))
		var got_n := int(live_seeds.get(k, 0))
		print("  🔒Q %-17s 法定覆盖 %d/%d（需 ≥%d，余量 %d）" % [k, got_n, seeds.size(), need_n, got_n - need_n])
		if got_n < need_n:
			live_red.append("%s(覆盖 %d/%d < 法定 %d)" % [k, got_n, seeds.size(), need_n])
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
		print("  ✅ 门控事件类 %d 种全部仍在发生（含法定覆盖 %d 种）" % [live_gated_n, LIVENESS_QUORUM.size()])
	else:
		print("  ❌ 门控事件类归零/跌破法定覆盖：%s —— 某个子系统被关掉了，而硬不变量对空输入恒过" % str(live_red))

	# ── 金标：跨进程/跨提交/跨引擎版本的锚（红线#1 真正的机检点）──
	# ⚠ ★Z1：`golden_red` 在【一次比较都没发生】时同样是 false —— 有两条路会落到这里：
	#     ① 根本没传 `--golden`（`ci.sh` 第 4a 步 N=16 就是这一条；Y1/Y3 各自独立撞到，docs/96 §〇④）；
	#     ② 传了 `--golden` 但 `cmp_n == 0`（seed/days 与金标表不重叠，如 CI_DAYS≠60 的快跑）。
	#   此前这两条都会在判决行上印出绿色的「金标 过」——**一行读起来是判决的输出，其实什么都没判**。
	#   这里只改**报告**不改**判据**：`golden_cmp_n` 只喂那一个字符串，`gate_ok` 与退出码一个字节不变。
	#   （同 84bd95d「单 seed 下软门恒过却照样打绿勾」的先例，改法逐条照抄。）
	var golden_red := false
	var golden_cmp_n := -1              # -1=未传 --golden；0=传了但 0 条可比；>0=真比过这么多条
	var golden_note := "(未启用 --golden)"
	if bake_path != "":
		golden_note = _bake_golden(bake_path, seeds_spec, days, seeds, first_run_digest, first_run_edig,
			first_run_events, first_run_chain, first_run_ticks, live_total, live_seeds)
	if golden_path != "":
		var gres := _check_golden(golden_path, days, seeds, first_run_digest, first_run_edig,
			first_run_chain, first_run_ticks)
		golden_red = bool(gres["red"])
		golden_note = String(gres["note"])
		golden_cmp_n = int(gres.get("cmp_n", 0))
	print("\n— 金标（跨进程锚）—\n  " + golden_note)

	# ── 逐 tick 前缀链：与一份 --chain-dump 参照物比对 → 精确到 tick 的首个分叉 ──
	var chain_ref_red := false
	if _chain_ref != "":
		var rres := _check_chain_ref(_chain_ref, days, seeds, first_run_ticks)
		chain_ref_red = bool(rres["red"])
		print("\n— 逐 tick 前缀链 vs 参照 —\n  " + String(rres["note"]))
	if _chain_dump != "":
		print("\n— 逐 tick 前缀链 —\n  🔨 已写出 %d 个 seed 的全量逐 tick 链到 %s（用 --chain-ref 与之比对可定位首个分叉 tick）"
			% [seeds.size(), _chain_dump])

	print("\n— 确定性 —")
	if det_n <= 0:
		print("  (跳过)")
	elif det_fail.is_empty():
		print("  ✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链)  %d/%d" % [det_ok, det_seeds.size()])
	else:
		print("  ❌ 非确定：")
		for f in det_fail:
			print("     " + String(f))

	var gate_ok := (seed_pass == seeds.size()) and not hard_red and not soft_red \
		and live_red.is_empty() and not golden_red and not chain_ref_red and (det_n <= 0 or det_fail.is_empty())
	# ★Z1：判决行上"金标"那一格。红永远先说话；只有**真比过 >0 条**才有资格说「过」。
	#   这个串**只喂 print**，`gate_ok` 与 `quit()` 一个字节都不读它（见 golden_cmp_n 的抬头）。
	var golden_verdict := "破" if golden_red else ("过" if golden_cmp_n > 0 else
		("N/A·0条可比" if golden_cmp_n == 0 else
			("N/A·本跑是--bake-golden不是比对" if bake_path != "" else "N/A·未传--golden")))
	print("\n=== S0 GATE: %s  (硬不变量 seed %d/%d 全绿, 软通过率门 ≥%d/%d(%d%%) %s, 活性 %s, 金标 %s, det %d/%d) ===" % [
		"PASS ✅" if gate_ok else "FAIL ❌", seed_pass, seeds.size(),
		soft_min, seeds.size(), int(round(SOFT_RATE * 100.0)),
		("过" if not soft_red else "破") if soft_min > 0 else "N/A·单seed无判别力",
		"过" if live_red.is_empty() else "破",
		golden_verdict, det_ok, det_seeds.size()])
	quit(0 if gate_ok else 1)

## 软门阈值：比率制（≥90%），但用 seeds-1 封顶 → 【永不严于】历史的绝对容差 1，小网格(1-3 seed)行为不变。
##   n=1 → 0（恒过，同旧）；n=3 → 2（容 1，同旧）；n=12 → 11（容 1，同旧）；n=24 → 22（容 2，旧为 23 会误红）。
static func soft_threshold(n: int) -> int:
	if n <= 1:
		return 0
	return mini(int(ceil(float(n) * SOFT_RATE)), n - 1)

## 法定覆盖判据在本次网格上生不生效：horizon 够 + 网格不小于 QUORUM_MIN_SEEDS。
static func _quorum_applies(k: String, days: int, n_seeds: int) -> bool:
	if not LIVENESS_QUORUM.has(k):
		return false
	return days >= int((LIVENESS_QUORUM[k] as Dictionary)["days"]) and n_seeds >= QUORUM_MIN_SEEDS

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
		chain: Dictionary, chain_ticks: Dictionary,
		live_total: Dictionary, live_seeds: Dictionary) -> String:
	var doc := load_golden(path)        # 保留 DetGate 烘的 scenarios 段
	var tbl := {}
	for sd in seeds:
		tbl[str(sd)] = {
			"digest": str(int(dig[sd])),
			"event_digest": str(int(edig[sd])),
			"days": days,
			"events": int(evs[sd]),
			"chain": str(int(chain[sd])),
			"chain_ck": ck_encode(chain_ticks[sd], CHAIN_STRIDE),
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

func _check_golden(path: String, days: int, seeds: Array, dig: Dictionary, edig: Dictionary,
		chain: Dictionary, chain_ticks: Dictionary) -> Dictionary:
	var doc := load_golden(path)
	if doc.is_empty():
		return {"red": true, "cmp_n": 0, "note": "❌ 金标文件缺失/不可解析：%s" % path}
	var tbl: Dictionary = doc.get("seeds", {})
	if tbl.is_empty():
		return {"red": true, "cmp_n": 0, "note": "❌ 金标文件无 seeds 段：%s" % path}
	var gmeta: Dictionary = doc.get("_meta", {})
	var cmp_n := 0
	var chain_cmp_n := 0
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
		# L4 逐 tick 前缀链：既抓"中途分叉又合流"（终态摘要抓不到），又报出首个分叉在哪一段
		var exp_c := String(row.get("chain", ""))
		if exp_c != "":
			chain_cmp_n += 1
			var got_c := str(int(chain[sd]))
			if exp_c != got_c:
				var loc := _locate_by_ck(String(row.get("chain_ck", "")), chain_ticks[sd])
				bad.append("seed %d chain        期望 %s  实得 %s%s" % [sd, exp_c, got_c, loc])
	if not bad.is_empty():
		var msg := "❌ 金标不符（%d 处；金标烘于 godot %s）：\n" % [bad.size(), String(gmeta.get("godot", "?"))]
		for b in bad:
			msg += "      " + b + "\n"
		msg += "    → 行为变了。若是【无意】的（引擎升级 / 候选枚举重构 / _aid() 播种变化），这是红线#1 被破，查代码；\n"
		msg += "      若是【有意】的基线移动，才重烘：--bake-golden game/bench/golden_digests.json（与该变更同一 commit）。\n"
		msg += "    → 要把首个分叉【精确到 tick】：先在已知良好的提交上 --chain-dump /tmp/ref.chain，\n"
		msg += "      再在本提交上 --chain-ref /tmp/ref.chain（逐 tick 比对，直接报 tick 号）。"
		return {"red": true, "cmp_n": cmp_n, "note": msg}
	if cmp_n == 0:
		return {"red": false, "cmp_n": 0, "note": "⚠ 金标 0 条可比（seed/days 与金标表不重叠）——本跑未构成跨进程校验"}
	return {"red": false, "cmp_n": cmp_n, "note": "✅ 金标一致 %d/%d seed（含逐 tick 前缀链 %d 条；烘于 godot %s，本机 %s）" % [
		cmp_n, seeds.size(), chain_cmp_n, String(gmeta.get("godot", "?")), godot_version()]}

# ── 逐 tick 前缀链的编码 / 定位 ──────────────────────────────────────────────
## 检查点编码：每 stride 个 tick 取一个链值，逗号分隔的小写十六进制。
## 存的是 tick=stride, 2*stride, … 处的 H（不存 tick 0，因为 chain[0] 是第 1 个 tick 之后的值）。
static func ck_encode(ticks: PackedInt64Array, stride: int) -> String:
	var parts := PackedStringArray()
	var i := stride - 1
	while i < ticks.size():
		parts.append("%x" % ticks[i])
		i += stride
	return ",".join(parts)

## 链下标 i ↔ Sim.tick_no：Sim.tick() 一进门就 tick_no += 1，故第 i 个链值对应 tick_no = i + 1。
## 报告一律用【tick_no】（人和 log 里看到的那个号），不用数组下标。
static func tick_label(idx: int) -> String:
	var tno := idx + 1
	return "  首个分叉 tick_no=%d（第 %d 天 · 当天第 %d tick）" % [tno, idx / CHAIN_STRIDE + 1, idx % CHAIN_STRIDE + 1]

## 两条全量逐 tick 链的首个不同下标（= 首个分叉 tick 的 0-based 序号；tick_no = 它 + 1）。-1 = 完全一致。
static func first_tick_mismatch(a: PackedInt64Array, b: PackedInt64Array) -> int:
	var n: int = mini(a.size(), b.size())
	for i in n:
		if a[i] != b[i]:
			return i
	if a.size() != b.size():
		return n           # 长度不同 → 短的那条结束处即首个分歧
	return -1

## 拿金标里的天级检查点，把首个分叉锁进一个 CHAIN_STRIDE 宽的 tick 窗口。
func _locate_by_ck(ck: String, ticks: PackedInt64Array) -> String:
	if ck == "":
		return "  （金标无 chain_ck，无法定位；重烘一次即可获得天级检查点）"
	var exp: PackedStringArray = ck.split(",", false)
	var got: PackedStringArray = ck_encode(ticks, CHAIN_STRIDE).split(",", false)
	var n: int = mini(exp.size(), got.size())
	for i in n:
		if exp[i] != got[i]:
			return "\n        ↳ 首个分叉落在 tick_no [%d..%d]（第 %d 天）——该天之前的逐日检查点全部吻合" % [
				i * CHAIN_STRIDE + 1, (i + 1) * CHAIN_STRIDE, i + 1]
	if exp.size() != got.size():
		return "\n        ↳ 逐日检查点在第 %d 天处长度不同（天数/步长变了？）" % (n + 1)
	return "\n        ↳ 逐日检查点全吻合，分歧只出现在最后一天的尾段（tick_no > %d）" % (n * CHAIN_STRIDE)

## 把一个 seed 的全量逐 tick 链追加进 dump 文件（每 seed 一行：seed<TAB>days<TAB>hex,hex,…）。
func _write_chain_dump(sd: int, days: int, ticks: PackedInt64Array) -> void:
	var f := FileAccess.open(_chain_dump, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%d\t%d\t%s" % [sd, days, ck_encode(ticks, 1)])
	f.close()

## 与一份 --chain-dump 参照物逐 tick 比对 → 精确到 tick 的首个分叉。
func _check_chain_ref(path: String, days: int, seeds: Array, ticks: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"red": true, "note": "❌ 参照文件不存在：%s" % path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"red": true, "note": "❌ 参照文件打不开：%s" % path}
	var ref := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var cols: PackedStringArray = line.split("\t")
		if cols.size() < 3:
			continue
		ref["%s:%s" % [cols[0], cols[1]]] = cols[2]
	f.close()
	var cmp_n := 0
	var bad: Array = []
	for sd in seeds:
		var key := "%d:%d" % [sd, days]
		if not ref.has(key):
			continue
		cmp_n += 1
		var exp: PackedStringArray = String(ref[key]).split(",", false)
		var got: PackedStringArray = ck_encode(ticks[sd], 1).split(",", false)
		var n: int = mini(exp.size(), got.size())
		var first := -1
		for i in n:
			if exp[i] != got[i]:
				first = i
				break
		if first < 0 and exp.size() != got.size():
			first = n
		if first >= 0:
			bad.append("seed %d：%s  参照 H=%s  实得 H=%s" % [sd, tick_label(first).strip_edges(),
				(exp[first] if first < exp.size() else "(无)"), (got[first] if first < got.size() else "(无)")])
	if not bad.is_empty():
		var msg := "❌ 逐 tick 前缀链与参照不符（%d 个 seed）：\n" % bad.size()
		for b in bad:
			msg += "      " + b + "\n"
		return {"red": true, "note": msg.rstrip("\n")}
	if cmp_n == 0:
		return {"red": false, "note": "⚠ 参照 0 条可比（seed/days 不重叠）"}
	return {"red": false, "note": "✅ 逐 tick 前缀链与参照逐 tick 一致 %d/%d seed" % [cmp_n, seeds.size()]}

## 跑一局确定性仿真，返回 {S, starved, starve_by_need, chain, chain_ticks}。S 由调用方 _dispose。
## `starved` 是喂给 `Inv.check_all` 的那个数，也就是 **#1 的口径由这里定义**：
##   Σ over (agent, tick, need) of [need ≤ 0.5] —— **任何一条 need**，不按 agent 去重（一个人同时饿又困计 2）。
## chain_ticks[i] = 第 i+1 个 tick 结束后的前缀链值（全量留在内存里：60 天 = 14400 个 int64 ≈ 115KB，可忽略）。
##
## ⚠ 这个循环在仓库里有 **8 份逐字复制**（引符号不引行号，见 Invariants.digest 抬头那条教训）：
##   本文件 · `BackendGate._run` · `DetGate._run` · `LodAblation` · `lod_observation_probe` ·
##   `ScaleSupply` · `scale_agg` · `BackendBench._starve_ticks`（那一份多一个 `break`，是 per-agent-tick 口径，
##   数会偏小）；另 `find_starve.gd` 是诊断探针，且它**跳过 player**，与上面 8 份都不同口径。
##   阈值 `0.5` 也被写死了 8 遍，而 `Sim.gd` 有一个**从未被调用**的 `const STARVE_NEED := 0.5` 就是它
##   （`git log -S STARVE_NEED` ⇒ `6e2ba78` 加进来的时候就没接上，**不是**后来被摘掉的；docs/41 §1.5①）。
##   本棒**没有**把这 8 处收敛：只改其中 1 处去引那个常量，会做出一个"改了它却只有 1/8 跟着变"的活陷阱，
##   比现在这种一致的重复更危险。要收就得 8 处一起收，那超出本棒的行（只有本文件与 Invariants.gd）。
func _run_once(seed: int, days: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.shadow_on = _shadow   # 探针开关（默认 false → 逐字节不变）；set before start_new
	S.cand_permute = _permute   # 置换不变性机检（默认 0=off → Sim 里一条分支都不进）
	if _agents > 0:
		S.spawn_count = _agents   # 扩 N 规模诊断（克隆扩容；0=数据原样 cast）
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var starved := 0
	var starve_by_need := {}    # need -> 触底 (agent,tick) 实例数。**纯观测**：只进 detail 字符串，不进判据
	# M1：`starved` 是 (人数 × need 种类 × 持续 tick) 的乘积，光看这个标量分不清
	# 「很多人各触底一下」与「一个人躺了六天」——而这两件事的处置完全不同（见 Invariants._starve_shape）。
	# 三个都是**纯观测**，只进 detail 字符串；判据吃的仍然只有 `starved` 这一个 int。
	var starve_agents := {}     # agent id -> true
	var starve_run_last := {}   # "agentneed" -> 上一次触底的 tick（判连续用）
	var starve_run_start := {}  # "agentneed" -> 当前连续段的起始 tick
	var starve_run_max := 0     # 全局最长连续触底段（tick）
	var starve_run_key := ""    # 该最长段属于谁的哪条 need
	var chain: int = Inv.CHAIN_INIT
	var chain_ticks := PackedInt64Array()
	chain_ticks.resize(total)
	var ev_seen: int = S.event_log.size()   # 开局种子事件不算任何一个 tick 的产物
	for t in range(total):
		S.tick()
		chain = Inv.chain_step(chain, S, ev_seen)   # H_t = h(H_{t-1} ‖ 状态_t ‖ 本 tick 新事件)
		ev_seen = S.event_log.size()
		chain_ticks[t] = chain
		for ag in S.agents:
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
					starve_by_need[nid] = int(starve_by_need.get(nid, 0)) + 1   # 分支几乎从不进 ⇒ 热路径零开销
					# ↓ 同一条冷分支里做，热路径仍然零开销（全绿的网格上这几行一次都不执行）
					var _sid := String(ag["id"])
					starve_agents[_sid] = true
					var _k := _sid + "/" + String(nid)
					if int(starve_run_last.get(_k, -2)) != t - 1:
						starve_run_start[_k] = t          # 断了 ⇒ 开新段
					starve_run_last[_k] = t
					var _len: int = t - int(starve_run_start[_k]) + 1
					if _len > starve_run_max:
						starve_run_max = _len; starve_run_key = _k
	var starve_shape := {}
	if not starve_agents.is_empty():
		var _who: Array = starve_agents.keys()
		_who.sort()   # 定序：报告可复现
		starve_shape = {"agents": _who, "max_run_ticks": starve_run_max,
			"max_run_days": float(starve_run_max) / float(S.TICKS_PER_DAY), "max_run_key": starve_run_key}
	# 注：dump 不在此做——否则 det 复跑(也调 _run_once)会把同 seed 追加两次（评审 P1）
	return {"S": S, "starved": starved, "starve_by_need": starve_by_need,
		"starve_shape": starve_shape, "chain": chain, "chain_ticks": chain_ticks}

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
