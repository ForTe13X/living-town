extends Node
## AIBackend.gd — autoload "AIBackend"：三档可插拔后端（复用《小鱼岛》Game.gd 的 ai_backend 范式）。
##   logic ── 纯需求/效用脚本，零模型，确定性，bench/Web/无 GPU 的默认与兜底（Sim._logic_decide 单一真相源）
##   llm   ── OpenAI 兼容 chat（HTTPRequest → LM Studio / Ollama / 远程），异步、结构化 JSON
##   slm   ── 本地 GGUF（NobodyWho GDExtension，扩展内异步 worker+信号，动态实例化，缺扩展即回退）
##   mock  ── 测试用：不联网，确定性返回合规 JSON，验证「异步→解析→pick glue→落地→兜底」全链
## 纪律：模型只在 Sim 给的「合法候选」里挑(pick 下标) + 给一句台词；非法/越界/超时/缺失 → 引擎兜底，永不破坏仿真。
##
## 异步契约（decide 的返回）：
##   {"_wait": true}  → 思考中，本 tick 不落地（Sim 跳过，保持 option==null 下 tick 再问）
##   {}（空）          → 放弃（脏输出/超时/不可用）→ Sim 用 logic 兜底
##   非空 intent       → 解析出的合法候选（cands[pick] + say）→ Sim 落地

var backend := "logic"                          # "logic" | "llm" | "slm" | "mock"（当前生效档；可能被算力探测自动降级）
var backend_requested := "logic"                # 用户意图档（手机 UI 切换/settings 持久化）；生效滞后到 decide() 安全点，与 backend 分离以免降级抹掉意图
var endpoint := "http://127.0.0.1:1234/v1/chat/completions"  # LM Studio 默认
var model := "qwen-3-8b-instruct"               # 实测选型：中文/JSON/速度均衡；推理由 no_think 关闭
var api_key := "lm-studio"
var mock := false                               # true → 强制走确定性 mock（不联网）
var no_think := true                            # 追加 /no_think 关推理模型(Qwen3)的思考——否则烧 token 返回空（实测）
var debug_llm := false                           # true → 在 _fire_http 完成回调打印 LLM 返回（诊断用）
## bench 埋点。calls/waits 是【诚实分母】的原料，别只看 fired（详见 decision_stats 的长注释与 docs/35）。
var stats := {"fired": 0, "landed": 0, "bad_parse": 0, "timeout": 0, "calls": 0, "waits": 0}
# SLM 熔断器（docs/34：真机 Adreno Vulkan 下推理挂死→全超时+卡死 worker 释放不了原生上下文→无界泄漏 OOM）：
# 连续 N 次超时(SLM 实质死了) → 停发 SLM、永久回退 logic，把泄漏封顶、防崩。backend=slm 本就非确定(live 模型)→不碰红线。
var _slm_fail_streak := 0
var _slm_circuit_open := false
const SLM_CIRCUIT_TRIP := 6      # 连续超时阈值（>MAX_INFLIGHT，给足重试余量；健康 SLM 不会连超 6 次）

# ── AI 请求生命周期（评审 P1-1/2/3/4 修复）───────────────────────────────────
# 每个在飞请求带 (epoch, req_id) + 候选快照。回包只在 _pending[id] 仍是同一 (epoch,req_id) 时才写回
# → 迟到/跨局回包一律作废(P1-2/3)；落地时用「模型当初看到的候选」在【当前】候选里按 stable key 重找
# → 世界在等待期变了(需求/位置/候选重排)就兜底 logic，绝不把旧编号套到新候选上(P1-1)。
var world_epoch := 0                            # 世界重置(start_new/scrub/切后端/换模型) → 自增；旧 epoch 回包即作废
var _req_seq := 0                               # 单调请求号

func reset_stats() -> void:
	stats = {"fired": 0, "landed": 0, "bad_parse": 0, "timeout": 0, "calls": 0, "waits": 0}
	# L5 per-run 状态清零（否则跨 seed 的陈旧度/发声计数/预算窗口会串味）
	_fire_count = {}
	_last_llm = {}
	cancel_all()                                # 清 _pending + 释放在飞节点 + 进新 epoch（旧回包作废）
	_budget_window = -1
	_budget_used = 0

func _ready() -> void:
	# 端上默认走 CPU 推理（docs/34 真机 A/B 实测：8Elite 满负载下 Adreno GPU 决策解码 ~16-20s（渲染抢 GPU）、
	# 远超 15s 截止线→从不落地；CPU ~3-8s（暖）多数落在线内→决策真落地（overlay 实测 landed 34/51）。故安卓默认 CPU。
	# 桌面(独显不与渲染抢)保持 GPU。覆盖优先级：本行=安卓默认 → 随后 Main 调 _load_user_settings 读 [slm] use_gpu（用户显式设了才盖）。
	if OS.has_feature("android"):
		slm_use_gpu = false
	# 订阅世界重置 → 取消所有在飞请求。deferred 确保 Sim 自动加载已就绪（autoload 顺序无关）。
	call_deferred("_connect_world_reset")
func _connect_world_reset() -> void:
	# 用节点路径 + 字符串信号 API（非 Sim.world_reset 成员访问）→ 不依赖 Sim 的编译期类型，任何加载序/上下文都安全。
	var sim := get_node_or_null("/root/Sim")
	if sim != null and sim.has_signal("world_reset") and not sim.is_connected("world_reset", cancel_all):
		sim.connect("world_reset", cancel_all)

## 取消所有在飞模型请求(decision/chat/reflect)：释放真实 HTTP/worker 节点、清 _pending、复位 _inflight、进新 epoch。
## 世界重置(start_new 信号)/切后端/换模型前调用 → 之后旧回包的 (epoch) 不匹配即被丢弃，不污染新局。
func cancel_all() -> void:
	world_epoch += 1
	for id in _pending.keys():
		var p: Dictionary = _pending[id]
		_free_transport(p.get("http"), p.get("slm_chat"))
	_pending = {}
	_inflight = 0
	# 池化 SLM worker：作废在飞发（world_epoch 已自增 → 迟包按 epoch 丢弃）+ 停当前生成，但【不 free】——持久复用。
	_slm_busy = false
	if _slm_chat != null and is_instance_valid(_slm_chat) and _slm_chat.has_method("stop_generation"):
		_slm_chat.call("stop_generation")
	# 兜底：扫掉仍挂在 AIBackend 下的一次性请求节点（旧 http/chat 路径）。不碰共享 _slm_model 与持久池化 _slm_chat。
	for c in get_children():
		if c == _slm_model or c == _slm_chat:
			continue
		if c is HTTPRequest or c.get_class() == "NobodyWhoChat":
			if c.has_method("cancel_request"): c.call("cancel_request")
			if c.has_method("stop_generation"): c.call("stop_generation")
			c.queue_free()

func _free_transport(http, slm_chat) -> void:
	if http != null and is_instance_valid(http):
		if http.has_method("cancel_request"): http.cancel_request()
		http.queue_free()
	if slm_chat != null and is_instance_valid(slm_chat):
		if slm_chat.has_method("stop_generation"): slm_chat.call("stop_generation")
		slm_chat.queue_free()

## 候选稳定 key（完整身份，含 P2-1 遗漏的 kind/target/need/amount/duration）：等待期间候选重排/替换后仍能重认同一动作。
func _cand_key(c: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(c.get("kind", "")), str(c.get("action", "")), str(c.get("partner", "")),
		str(c.get("target", "")), str(c.get("subject", "")), str(c.get("need", "")),
		str(c.get("object", "")), str(c.get("amount", "")), str(c.get("duration", ""))]
# ── 嵌入式 SLM（NobodyWho GDExtension + 本地 GGUF）──实测：Godot 4.6.2 加载需 glibc≥2.38 + libvulkan1 loader。
var slm_model_path := "res://models/qwen2.5-3b-instruct-q4_k_m.gguf"   # 默认 3B-Q4：中端 780M 实测 ~2.9s、质量明显优于 1.5B(docs/11 §12.2b)
var slm_model_override := ""                      # 设置面板里手选的 gguf 绝对路径（存 settings.cfg）；非空且存在则优先（换模型 A/B 用）
# 轻量备选(极致包体/最低端)：res://models/qwen2.5-1.5b-instruct-q4_k_m.gguf（~1.3s，质量中）。capability 探针太慢会自动降 logic。
var slm_use_gpu := true                          # 真机优先 GPU(Vulkan)；无设备自动回退 CPU（容器实测 CPU ~1字/s，故真机才实用）
var _slm_model: Object = null                    # 共享 NobodyWhoModel（懒加载，~1GB 仅载一次）
# 池化持久 SLM chat worker（docs/34 根治）：旧实现每次决策/反思/对话都 new 一个 NobodyWhoChat + start_worker + 完成即 queue_free，
# 高频决策下每秒起/放几十个 worker；一旦在 worker 仍在飞时释放它（超时/落地/cancel_all），扩展的异步回包会访问【已释放】的节点
# → godot-rust panic「access to instance after freed」→ 桌面段错误崩溃；手机 Adreno 挂死时 worker 释放不掉原生上下文 → 16GB 泄漏。
# 修法：全局只养一个持久 chat，reset_context 复用；串行(一次一发，本地推理本就串行)；绝不在在飞时 free。
var _slm_chat: Object = null                     # 持久池化 chat worker（只建一次，reset_context 复用）
var _slm_busy := false                           # 串行在飞标志：一次只跑一发 SLM 生成（决策/反思/对话共用此 worker）
var _slm_reload_pending := false                 # 换模型延后拆：有在飞时不可同步 free（会 UAF 崩），标记后等 worker 收尾/空闲再拆重建
var _slm_log_lines: Array = []                   # docs/34 真机诊断：前 N 发 SLM 的真实延迟+结果（adb-pull 读，量在飞延迟 vs 探针隔离值）

const DEADLINE_MS := 15000     # 截止线上限/默认（实时墙钟毫秒）。docs/34 真机 A/B：端上 CPU 暖发多在 3-8s、少数 8-14s
                               # 贴/略过旧 12s 线；提到 15s 把这些也捞回落地（host 档决策稀疏、等待期跑 logic，多等几秒代价可接受）。
const PROBE_TIMEOUT_MS := 150000  # 算力探测单发超时兜底（真机模型 load+暖发 ~85s；Adreno 挂死则 150s 后放弃→留 logic）
var deadline_ms := DEADLINE_MS # 自适应实时截止线：probe_capability 据本机 p50 设 clamp(6×p50,3000,15000)
var p50_ms := 0                # 启动探测得的暖决策中位延迟
var tier := "logic"            # 算力档：fast(<1.5s)|host(<6s)|slow(<15s)|logic（探测后设）
const DEADLINE_TICKS := 8      # （保留）mock/极速档参考
const MOCK_DELAY := 3          # mock 模拟推理延迟（tick）
const MAX_INFLIGHT := 2        # 同时在飞的模型请求上限（单机本地服串行，过载丢/等）
# L5 全镇令牌桶（docs/12 §L5）：每 sim-日最多 N 次 LLM 决策 → LLM 调用 ∝ 预算而非 agent 数；超额走引擎地板。
var llm_budget := 0            # 0=不限(默认,兼容现状)；>0=每 sim-日全镇 LLM 决策上限
var _budget_window := -1
var _budget_used := 0
# L5 老化+优先（docs/12 §S-scale-4「离屏 NPC 因老化偶尔发声」）：预算稀缺时不再先到先得(近端/靠前 agent 垄断)，
# 而按 优先级=陈旧度(距上次发声的 sim-日数) + 戏剧显著性(需求危机/卷入冲突) 门控。门槛随当日预算耗尽比例升高
# → 预算充裕时几乎都放行、越紧越只让最陈旧/最戏剧的发声；陈旧度无上界 → 任何长期合格 agent 终会跨过门槛(反饿死)。
var llm_aging := true          # true=优先+老化门控(仅 llm_budget>0 时起作用)；false=FCFS(旧行为)
const AGING_GATE := 1.5        # 预算耗尽比例=1 时要求的最低优先级
var _fire_count := {}          # id -> 本 run 该 agent 触发 LLM 的次数（bench 测发声公平性/反饿死）
const MAX_TOKENS := 128   # 自由对话(chat)用；决策见 DECIDE_MAX_TOKENS
const DECIDE_MAX_TOKENS := 8   # 决策=闭集选号(单字符 0-9/A-Z)，decode≈1 token → 与 80-token JSON 解耦(voice 走冻结语音库)。据 edge-npu-8elite「决策≠生成」洞察

# NPC 决策 schema（结构化输出契约，详见 docs/03 §3）：模型只输出 pick 下标 + 台词/情绪。
const DECISION_SCHEMA := {
	"type": "object",
	"properties": {
		"pick": {"type": "integer"},                 # 候选下标（Sim.agent_candidates 范围内）
		"speech": {"type": "string"},
		"emotion": {"type": "string", "enum": ["neutral", "happy", "angry", "sad", "anxious", "fond"]},
		"affinity_delta": {"type": "integer"},
	},
	"required": ["pick"],
}

var _pending := {}     # id -> {due:int, ready:int, raw:String, has:bool, http:HTTPRequest}
var _inflight := 0
var _last_llm := {}    # id -> 上次 LLM 决策落地的 tick（按算力档节流发言密度）

## 按算力档定「每 agent 两次 LLM 决策的最小 tick 间隔」：快档密、慢档稀（多走引擎），实现 docs/11 §5 自适应发言密度。
func _decide_interval() -> int:
	# 以 sim-时间为单位（TICKS_PER_DAY=240，自然决策约每 68 tick/人）→ 间隔须超自然 cadence 才显著节流
	match tier:
		"fast": return 1                          # 亚秒：几乎每次决策都可让 LLM 发声
		"host": return int(Sim.TICKS_PER_DAY / 2) # ~半 sim-日/人：适度稀疏(约腰斩 LLM 调用)
		"slow", "toolslow": return Sim.TICKS_PER_DAY  # ~每 sim-日/人：很稀疏，大多走引擎
		_: return 1                               # instant/未探测：不额外节流

func available_backends() -> Array:
	var out := ["logic"]
	if ClassDB.class_exists("NobodyWhoModel"):     # 嵌入式 SLM 需 NobodyWho GDExtension 已加载（手机上主力）
		out.append("slm")
	out.append("mock")
	if not OS.has_feature("android"):              # llm=HTTP→LM Studio；手机默认 127.0.0.1 不可达，不进手机轮换（免误选空转 3000 次）
		out.append("llm")
	return out

## 运行期切换后端（手机 UI 调用）：记录意图 + 持久化到 user://settings.cfg；真正生效在 decide() 安全点（无在飞请求时）。
## slm/llm 无需在此重探测：慢请求各自到截止线(默认 12s)超时 → 逐个 agent 回落 logic，仍确定兜底、不卡死。
func request_backend(mode: String) -> void:
	if not mode in available_backends():
		return
	backend_requested = mode
	cancel_all()                          # 切后端：作废旧后端所有在飞请求（不同解析/传输，别让旧回包被新后端误读）
	save_user_settings()

## 读 user://settings.cfg 的默认后端（仅窗口启动、且无 --backend 显式参数时调用）。
## 纪律：CLI --backend 永远优先；headless CI（Harness/soak 用 Sim.backend=null，从不经此路）→ 逐字节不变。
func _load_user_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:      # 缺文件/损坏 → 保持默认 logic
		return
	var m := String(cfg.get_value("backend", "mode", ""))
	if m != "" and m in available_backends():
		backend = m
		backend_requested = m
	# slm GPU/CPU 推理开关（docs/34 真机 A/B：Adreno GPU vs 8Elite CPU 延迟对照；安卓默认 CPU，见 _ready）。
	# 真机可 run-as 写 settings.cfg [slm] use_gpu=<bool> 后重开即切，免重打包。
	if cfg.has_section_key("slm", "use_gpu"):
		slm_use_gpu = bool(cfg.get_value("slm", "use_gpu", slm_use_gpu))

func save_user_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")                # 保留其他键（若有）
	cfg.set_value("backend", "mode", backend_requested)
	cfg.save("user://settings.cfg")

## L5 发声优先级 = 陈旧度(距上次发声的 sim-日数，无上界→反饿死) + 戏剧显著性(需求危机/卷入未了结冲突)。确定，无 RNG。
func _priority(id: String, agent: Dictionary) -> float:
	var last := int(_last_llm.get(id, Sim.tick_no - Sim.TICKS_PER_DAY))   # 从没发过声 → 视为已陈旧一天
	var staleness := float(Sim.tick_no - last) / float(Sim.TICKS_PER_DAY)  # 以 sim-日计
	var salience := 0.0
	if Sim._min_need(agent) < Sim.NEED_CRISIS:                            # 需求危机：让挣扎的人发声
		salience += 1.0
	for c in Sim.conflicts:                                               # 卷入未了结冲突：戏剧
		if (String(c["a"]) == id or String(c["b"]) == id) and String(c["status"]) in ["simmering", "escalated", "confronted"]:
			salience += 1.0
			break
	return staleness + salience

## L5 令牌桶 + 老化门（_fire 时消费）。0=不限。硬顶恒守；llm_aging 时叠加"预算越紧门槛越高"的优先门。
func _budget_gate(id: String, agent: Dictionary) -> bool:
	if llm_budget <= 0:
		return true
	var w := int(Sim.tick_no / Sim.TICKS_PER_DAY)
	if w != _budget_window:
		_budget_window = w
		_budget_used = 0
	if _budget_used >= llm_budget:
		return false                                                     # 硬顶：本 sim-日预算耗尽
	if not llm_aging:
		return true                                                      # 关老化 → FCFS（旧行为）
	var used_frac := float(_budget_used) / float(llm_budget)
	return _priority(id, agent) >= used_frac * AGING_GATE                 # 越紧越只让最陈旧/最戏剧的发声

## 懒加载共享 NobodyWhoModel（GGUF ~1GB 仅载一次；缺扩展返回 null → 调用方兜底）。
func _ensure_slm_model() -> Object:
	if _slm_model == null and ClassDB.class_exists("NobodyWhoModel"):
		_slm_model = ClassDB.instantiate("NobodyWhoModel")
		_slm_model.set("model_path", _resolve_model_path())
		_slm_model.set("use_gpu_if_available", slm_use_gpu)
		add_child(_slm_model)
	return _slm_model

## 懒加载持久池化 chat worker（绝不 per-call 起/放）。缺扩展/模型 → null（调用方兜底）。
func _ensure_slm_chat() -> Object:
	if _slm_chat != null and is_instance_valid(_slm_chat):
		return _slm_chat
	var model := _ensure_slm_model()
	if model == null:
		return null
	_slm_chat = ClassDB.instantiate("NobodyWhoChat")
	_slm_chat.set("model_node", model)
	_slm_chat.set("allow_thinking", false)
	add_child(_slm_chat)
	_slm_chat.call("start_worker")                # 预热一次；后续 reset_context 复用，不再起新 worker
	return _slm_chat

## 串行提交一发 SLM 生成（决策/反思/对话统一入口）。返回 true=受理(占用 worker)；false=忙/不可用→调用方兜底。
## route: {"mode":"decide","id","epoch","req"} 写回 _pending；{"mode":"cb","cb","cap","fallback"} 回调。
## 关键：signal 用【每发一次性闭包】捕获 world_epoch → cancel_all 后到达的迟包按 epoch 作废，不污染复用的 worker；
## 且用 fired[] 去重，防 response_finished/worker_failed 双触发导致重复投递。绝不在此 free chat（持久复用）。
func _slm_submit(sys: String, usr: String, route: Dictionary) -> bool:
	if _slm_busy or _slm_reload_pending:
		return false                              # 串行(上一发未回) 或 换模型待重建中 → 拒绝（调用方走地板/罐头）
	var chat := _ensure_slm_chat()
	if chat == null:
		return false
	_slm_busy = true
	var my_epoch := world_epoch                   # 捕获：cancel_all 会自增 world_epoch → 迟包作废
	var t0 := Time.get_ticks_msec()               # docs/34 诊断：量真·在飞推理延迟（对拍探针隔离值）
	var fired := [false]                          # 去重：response_finished 与 worker_failed 只认第一个
	var hs := []                                  # 两个 handler 引用（Array 引用型→闭包创建后 append 仍可见）
	# 触发即【显式断开两个连接】：worker_failed 在健康路径永不触发，若用 CONNECT_ONE_SHOT 其连接永不消费 → 每次成功
	# 决策都残留一个死闭包在持久 _slm_chat 上，O(submits) 累积泄漏(C2)。故不用 one-shot，靠 finish 断两条。
	var finish := func(resp: String, failed: bool):
		if fired[0]: return
		fired[0] = true
		if is_instance_valid(chat):
			if hs.size() >= 1 and chat.is_connected("response_finished", hs[0]): chat.disconnect("response_finished", hs[0])
			if hs.size() >= 2 and chat.is_connected("worker_failed", hs[1]): chat.disconnect("worker_failed", hs[1])
		# 池化 worker 有【任何】完成（即便这发已过决策截止线、结果被丢）→ 证明它活着 → 清熔断连败计数（docs/34）。
		# 慢·但·会返回的解码（lat>deadline）不是"挂死"，不该误触熔断把工作正常的 SLM 永久停发。无条件清（陈旧迟包也证活）。
		_slm_fail_streak = 0
		_slm_log(t0, "fail" if failed else "done")
		if world_epoch == my_epoch:               # 仅当前 owner：先投递、再清 busy——
			_deliver_slm(route, resp, failed)     #   ①清 busy 放投递【后】：同步重入的 cb 再 _slm_submit 会被 busy 挡下，不在信号发射中重入(评审 C2-d)
			_slm_busy = false                     #   ②仅 owner 清：陈旧(被 cancel)迟包 epoch 不匹配→不清，避免抹掉活跃后继的 busy(评审 finding5)
		if _slm_reload_pending and not _slm_busy: # 换模型延后拆：本发 worker 已完成 → 此刻安全 free 池化 chat（见 set_model_path）
			_teardown_slm_worker()
	var on_done := func(resp): finish.call(String(resp), false)
	hs.append(on_done)
	chat.connect("response_finished", on_done)
	if chat.has_signal("worker_failed"):
		var on_fail := func(_msg = ""): finish.call("", true)
		hs.append(on_fail)
		chat.connect("worker_failed", on_fail)
	chat.call("reset_context")                    # 清上一发历史（复用 worker 的关键）
	chat.set("system_prompt", sys)
	chat.call("ask", usr)
	return true

## 把一发 SLM 结果投给它的去向。decide→按 (epoch,req) 重验写回 _pending；cb→回调(失败/空则兜底串)。
func _deliver_slm(route: Dictionary, resp: String, failed: bool) -> void:
	if route.get("mode") == "decide":
		var id: String = route["id"]
		if _match(id, int(route["epoch"]), int(route["req"])):   # 仍是同一 (epoch,req) 才写回
			_pending[id]["raw"] = ("" if failed else resp)
			_pending[id]["has"] = true
			_pending[id]["ready"] = Sim.tick_no
	elif route.get("mode") == "cb":
		var cb: Callable = route["cb"]
		if cb.is_valid():
			var out := resp.strip_edges()
			cb.call(out.substr(0, int(route.get("cap", 60))) if (out != "" and not failed) else String(route.get("fallback", "")))

## docs/34 真机诊断：把 SLM 一发的【真实延迟+结果】落到可 adb-pull 的公共文件（前 60 发，防无界增长）。
## 关键用途：区分"慢·但·会返回"(done lat=13-18s → deadline 太紧而非挂死) vs "真挂死"(永无 done)；
## 并对拍 GPU(Adreno) vs CPU(8Elite) 在真机满负载下的解码延迟（决定端上默认走哪条）。overlay 只给计数，读不到延迟。
func _slm_log(t0: int, outcome: String) -> void:
	if _slm_log_lines.size() >= 60:
		return
	_slm_log_lines.append("#%d %s lat=%dms gpu=%s tier=%s deadline=%d tick=%d" % [
		_slm_log_lines.size() + 1, outcome, Time.get_ticks_msec() - t0, str(slm_use_gpu), tier, deadline_ms, Sim.tick_no])
	var path := "user://slm_latency.txt"
	if OS.has_feature("android"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if docs != "":
			path = docs.path_join("livingtown_slm.txt")   # 公共位置，免 run-as 直接 pull
	var f := FileAccess.open(path, FileAccess.WRITE)       # 整表重写（≤60 行，省去 append 语义）
	if f != null:
		for l in _slm_log_lines:
			f.store_line(l)
		f.close()

## NobodyWho/llama.cpp 需要能 mmap 的【真实文件系统路径】。安卓上按序找一个存在的 gguf：
##   ① 公共可 MTP 拖放位置（Documents/LivingTown、Documents、Download）——用户经「此电脑\手机\Documents」直接拷入，
##      免 adb；读公共位置需一次性授「所有文件访问」权限（见 docs/18）。
##   ② user://model.gguf（app 私有外部 files 目录=真实路径，免权限，但需 adb push 送达）。
## 都没有 → 返回 user:// 路径（加载失败→算力探针超时→自动降确定性 logic，镇子照常运转）。桌面沿用 res:// 不变。
func _resolve_model_path() -> String:
	if slm_model_override != "" and FileAccess.file_exists(slm_model_override):
		return slm_model_override                 # 设置面板手选优先（桌面/安卓都认）
	if not OS.has_feature("android"):
		# 桌面：配置路径【存在才用】。旧实现无条件返回 slm_model_path（默认 3B 文件名），而仓里的本地模型
		# 是 1.5B —— 照 README 往 game/models/ 放一个别的文件名的 gguf，加载必失败 → 探针 150s 超时
		# → 静默降级 logic，桌面【一句提示都没有】（Main 的"模型未就位"提示是安卓专属）。
		# 修法：缺文件就扫 game/models/（排序后取第一个，确定性：同样的目录内容 → 同样的选择），并明确打日志。
		if FileAccess.file_exists(slm_model_path):
			return slm_model_path
		var scanned := _scan_local_gguf()
		if scanned != "":
			print("[SLM] 配置的模型不存在：%s → 自动改用扫描到的 %s（要指定请用 --model / 设置面板）" % [slm_model_path, scanned])
			return scanned
		push_warning("[SLM] 未找到任何 *.gguf（%s 不存在，res://models/ 与 user:// 也没有）→ 算力探针会超时并留在确定性 logic 地板" % slm_model_path)
		return slm_model_path
	for p in _android_model_candidates():
		if FileAccess.file_exists(p):
			return p
	return ProjectSettings.globalize_path("user://model.gguf")

## 桌面兜底扫描：list_models() 的结果【排序后】取第一个真实存在的 gguf。
## 排序是刻意的——DirAccess 的枚举序是文件系统序，不排序会让"同一台机器同样的目录"在不同时刻选中不同模型。
func _scan_local_gguf() -> String:
	var found := list_models()
	found.sort()
	for p in found:
		if FileAccess.file_exists(p):
			return String(p)
	return ""

## 安卓上按优先级列出候选 gguf 路径（存在与否不判，判在调用方）。
func _android_model_candidates() -> Array:
	var out := []
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)     # 通常 /storage/emulated/0/Documents
	var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if docs != "":
		out.append(docs.path_join("LivingTown/model.gguf"))
		out.append(docs.path_join("model.gguf"))
	if dl != "":
		out.append(dl.path_join("model.gguf"))
	out.append(ProjectSettings.globalize_path("user://model.gguf"))
	return out

## 供 UI 展示（手机上无控制台）：解析到的模型路径 + 是否就位。缺则玩家知道往哪放。
func model_status() -> Dictionary:
	var p := _resolve_model_path()
	return {"path": p, "exists": FileAccess.file_exists(p)}

## 扫可放模型的目录，列出所有 *.gguf 的绝对路径（设置面板供手选/A-B 换模型）。
func list_models() -> Array:
	var dirs := []
	if OS.has_feature("android"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if docs != "":
			dirs.append(docs)
			dirs.append(docs.path_join("LivingTown"))
		if dl != "":
			dirs.append(dl)
		dirs.append(ProjectSettings.globalize_path("user://"))
	else:
		dirs.append(ProjectSettings.globalize_path("res://models"))
		dirs.append(ProjectSettings.globalize_path("user://"))
	var out := []
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if not da.current_is_dir() and f.to_lower().ends_with(".gguf"):
				var full: String = d.path_join(f)
				if not (full in out):
					out.append(full)
			f = da.get_next()
		da.list_dir_end()
	return out

## 设置面板选定某个 gguf：记住路径 + 存盘 + 释放已加载的共享模型（下次 slm 决策按新路径重载）。
func set_model_path(path: String) -> void:
	slm_model_override = path
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("slm", "model_path", path)
	cfg.save("user://settings.cfg")
	# 换模型：绝不在 worker 在飞时【同步 free】池化 chat——扩展异步回包会访问已释放节点 → UAF 崩（docs/34 + 对抗评审 C1）。
	# 有在飞 → 只作废其结果(cancel_all epoch++) + 标记延后拆；真正的 free 由该 worker 的 finish 收尾时执行（那时它已完成）。
	# 期间 _slm_submit 被 _slm_reload_pending 挡住不起新活 → 避免"新发在旧 chat 上跑、又被延后拆 free 掉"的竞态。
	# 无在飞 → 立刻安全拆（没有 worker 会回包）。slm_model_override 已在上面设好 → 重建走新路径。
	if _slm_busy:
		_slm_reload_pending = true
		cancel_all()                 # 作废在飞结果（epoch++）；stop_generation 但不 free
	else:
		_teardown_slm_worker()

## 运行期切 GPU/CPU 推理（docs/34 真机 A/B；未来 UI 旋钮/settings 用）：存盘 + 安全拆重建（同 set_model_path 的 C1 延后拆）。
func set_slm_use_gpu(v: bool) -> void:
	if v == slm_use_gpu:
		return
	slm_use_gpu = v
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("slm", "use_gpu", v)
	cfg.save("user://settings.cfg")
	# 同 set_model_path：绝不同步 free 在飞 chat（UAF）。有在飞 → 延后拆；无在飞 → 立即拆重建按新 GPU/CPU 标志。
	if _slm_busy:
		_slm_reload_pending = true
		cancel_all()
	else:
		_teardown_slm_worker()

## 安全拆掉池化 SLM worker（chat+model）并置空 → 下次 _ensure_slm_chat 按当前 override 重建。
## 【只可在无在飞生成时调用】（set_model_path 空闲分支 / finish 收尾）——否则 free 掉 worker 仍在写的节点会 UAF 崩。
func _teardown_slm_worker() -> void:
	if _slm_chat != null and is_instance_valid(_slm_chat):
		if _slm_chat.has_method("stop_generation"): _slm_chat.call("stop_generation")
		_slm_chat.queue_free()
	_slm_chat = null
	if _slm_model != null and is_instance_valid(_slm_model):
		_slm_model.queue_free()
	_slm_model = null
	_slm_reload_pending = false

# ── 启动算力探测（测一发暖决策 → 分档 + 自适应截止线 + 太慢自动降 logic）────────────
## 实测依据(docs/11 §12)：现代机决策 1–5s 都在 12s 线内；>~8s 即不实用 → 降确定性 logic。
## cb 收到 {tier, p50_ms, deadline_ms, backend}。logic/mock 立即返回（无需探测）。
## be=想启用的后端(slm/llm)。调用前 backend/backend_requested 已置 logic → 探测期间镇子跑地板(不冻/不黑屏，
## 真机 1.9GB 模型 load+2 暖发要 ~85s)；够快(≤8s/发)才切到 be，太慢/坏则留 logic。
func probe_capability(be: String, agent: Dictionary, candidates: Array, ctx: Dictionary, cb: Callable) -> void:
	if be == "logic" or be == "mock":
		tier = "instant"
		cb.call({"tier": tier, "p50_ms": 0, "deadline_ms": deadline_ms, "backend": backend})
		return
	var warm := 0
	for i in 2:                                   # 第1发付冷载(含模型 mmap)，取第2发为暖延迟
		var t0 := Time.get_ticks_msec()
		await _probe_once(be, agent, candidates, ctx)
		warm = Time.get_ticks_msec() - t0
		if warm >= PROBE_TIMEOUT_MS - 1000:       # 该发超时(含 Adreno 挂死)→ 判不可用即刻收手：别复用挂死 worker 跑第2发
			warm = PROBE_TIMEOUT_MS               #   （其迟包会触发第2发的 handler → 误判为"快"→错误启用 slm，评审 C3-d）
			break
	p50_ms = warm
	if p50_ms < 1500: tier = "fast"
	elif p50_ms < 6000: tier = "host"
	elif p50_ms < 15000: tier = "slow"
	else: tier = "toolslow"
	deadline_ms = clampi(6 * p50_ms, 3000, DEADLINE_MS)
	if p50_ms > 8000:                             # 太慢(>8s/发)：不启用，留在确定性 logic 地板（镇子照常）
		tier = "demoted_logic"
	else:                                         # 够快：启用目标后端（backend_requested 同步，decide() 才不会又切回 logic）
		backend = be
		backend_requested = be
	print("[算力探测] be=%s tier=%s p50=%dms deadline=%dms → backend=%s" % [be, tier, p50_ms, deadline_ms, backend])
	# 探针结果落一个可 adb-pull 的文件（真机 logcat 收不到 Godot print、UI 日志又被社交事件刷掉）→ 严格延迟对拍可靠读数。
	var ppath := "user://probe_result.txt"
	if OS.has_feature("android"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if docs != "": ppath = docs.path_join("livingtown_probe.txt")   # 公共位置，免 run-as 直接 pull
	var pf := FileAccess.open(ppath, FileAccess.WRITE)
	if pf != null:
		pf.store_line("be=%s tier=%s p50=%dms deadline=%dms backend=%s" % [be, tier, p50_ms, deadline_ms, backend])
		pf.close()
	cb.call({"tier": tier, "p50_ms": p50_ms, "deadline_ms": deadline_ms, "backend": backend})

## 直连一发计时决策（绕过 pending 状态机），返回 raw 串。
func _probe_once(be: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> String:
	var sys := _system_prompt()
	var usr := build_prompt(agent, candidates, ctx)
	if be == "slm" and ClassDB.class_exists("NobodyWhoModel"):
		# C3 修：走池化持久 worker（不再 per-call new+free，避免与决策路径同款 use-after-free），且给 await 加【超时兜底】——
		# 旧实现【裸 await response_finished】在 Adreno 挂死时永阻 → probe_capability 的 cb 永不触发、卡启动探测。
		# 注：超时靠 await process_frame 轮询墙钟——只兜得住 worker 线程级挂死（此时镇子仍跑、帧继续，正是真机实测所见 FPS79）；
		#    若真机整卡 GPU 锁死连渲染帧都停（实测未见此模式），则全 app 冻结，无任何引擎内超时可救——那是不可恢复态，非本修范围。
		var chat := _ensure_slm_chat()
		if chat == null: return ""
		_slm_busy = true                            # 占用池化 worker：防探测 await 期间 set_model_path 走空闲分支把正在用的 chat 同步 free（UAF）
		var got := [false, ""]
		var h := func(r): got[0] = true; got[1] = String(r)
		chat.connect("response_finished", h, CONNECT_ONE_SHOT)
		chat.call("reset_context")
		chat.set("system_prompt", sys)
		chat.call("ask", usr)                       # 长 prompt 不设 json_schema 受限解码（实测卡死只吐"{"）；靠 parse_decision 抽 {…}
		var t0 := Time.get_ticks_msec()
		while not got[0] and Time.get_ticks_msec() - t0 < PROBE_TIMEOUT_MS:
			await get_tree().process_frame
		_slm_busy = false
		if not got[0] and is_instance_valid(chat):  # 超时（含 Adreno 挂死）→ 断连+停生成 → 返回空 → probe 判太慢 → 留 logic 地板
			if chat.is_connected("response_finished", h): chat.disconnect("response_finished", h)
			if chat.has_method("stop_generation"): chat.call("stop_generation")
		if _slm_reload_pending:                     # 探测期间发生换模型 → 此刻本发已收/停 → 安全拆，下发按新路径重建
			_teardown_slm_worker()
		return String(got[1]) if got[0] else ""
	# llm：HTTPRequest 直连
	var http := HTTPRequest.new()
	add_child(http)
	var body := {"model": model, "max_tokens": DECIDE_MAX_TOKENS, "temperature": 0.6,
		"messages": [{"role": "system", "content": sys}, {"role": "user", "content": usr}]}
	var err := http.request(endpoint, ["Content-Type: application/json", "Authorization: Bearer " + api_key], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free(); return ""
	var res = await http.request_completed
	http.queue_free()
	if int(res[1]) == 200:
		var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if j is Dictionary and j.has("choices"):
			return String(j["choices"][0].get("message", {}).get("content", ""))
	return ""

## ── 诚实分母（docs/35）────────────────────────────────────────────────────
## landed/fired 回答的是「我们【选择发出】的请求里，有多少按时回来了」。
## 它【不】回答「全镇的 NPC 决策里，有几成真的是模型做的」——那个问题的分母是【落地的决策总数】。
## 为什么必须区分：SLM worker 是严格串行的（_slm_submit 的 _slm_busy 一次只放一发），
## 于是全镇每 sim-日能产出的模型决策数被【墙钟】封顶，与 N 无关：
##     1 sim-日 = TICKS_PER_DAY(240) × tick_interval(0.08s) = 19.2 s 实时（Sim._process 用累加器，
##     掉帧只会多补 tick，不会拉长 sim-日）→ 每发解码 D 秒 ⇒ 全镇上限 ≈ 19.2/D 次/ sim-日。
## 而分母（全镇决策数/ sim-日）随 N 线性涨。所以 N 越大，模型的真实份额越小——
## 但 landed/fired 完全看不出这件事，因为忙时我们干脆【不发】(decide 早退走 logic)，
## 没发出去的请求既不进分子也不进分母。分母越"方便"，结论越好看，正是本项目一再自查的失败模式。
##
## 怎么数才对（对照 Sim.gd:1076-1086 的 backend 路径）：
##   · 非空 intent  → agent_apply 落地（模型决策）
##   · 空 {}        → Sim 用 _logic_decide 兜底后落地（引擎决策，仍然是一次决策）
##   · {"_wait":true} → 本 tick 不落地，下 tick 用同一 agent 再问一次
## ⇒ 落地的决策数 = calls − waits。等待期的重复轮询【必须】剔掉：它不但虚增分母，
##    虚增幅度还与推理延迟正相关（模型越慢，轮询越多，分母越大）——留着会让慢模型显得更"忙"。
## 注：CI 恒 Sim.backend=null，decide 根本不被调用；这两个计数器只在 window/bench 里动，
##    不读不写任何 sim 态、不抽 RNG ⇒ 对 digest 零扰动（红线 #1 守恒）。
func decision_stats() -> Dictionary:
	var calls := int(stats.get("calls", 0))
	var waits := int(stats.get("waits", 0))
	var decisions := maxi(0, calls - waits)          # 真·落地决策数（引擎的 + 模型的）
	var fired := int(stats.get("fired", 0))
	var landed := int(stats.get("landed", 0))
	return {
		"calls": calls, "waits": waits, "decisions": decisions, "fired": fired, "landed": landed,
		"landed_over_fired": (float(landed) / float(fired)) if fired > 0 else 0.0,          # 截止线命中率（旧口径）
		"landed_over_decisions": (float(landed) / float(decisions)) if decisions > 0 else 0.0,  # 决策占比（诚实口径）
	}

## 串行 worker 的全镇吞吐天花板（次/ sim-日），与 N 无关。decode_s = 单发解码秒数（真机 CPU 实测 3-8s）。
## 供 bench/docs 直接引用，免得每次手算又抄错常数。
func slm_ceiling_per_sim_day(decode_s: float) -> float:
	var day_s := float(Sim.TICKS_PER_DAY) * Sim.tick_interval
	return day_s / maxf(0.001, decode_s)

# ── 同步入口（Sim 每 tick 调）──────────────────────────────────────────────
func decide(agent: Dictionary, candidates: Array, ctx: Dictionary) -> Dictionary:
	stats["calls"] = int(stats.get("calls", 0)) + 1   # 诚实分母原料：见 decision_stats
	# 运行期后端切换（手机上无 CLI 参数）：仅在无在飞请求时应用 backend_requested，
	# 否则旧后端的异步回包会被新后端的解析逻辑误读。logic 模式 digest 不受影响——
	# _logic_decide 的 RNG 只依赖 (seed,tick,salt,who)，与 backend 无关（红线守恒）。
	if backend != backend_requested and _pending.is_empty() and _inflight == 0:
		backend = backend_requested
	if backend == "logic" or Sim.replaying:              # P1-6：回放(scrub)期不发 live 请求，走确定性 logic
		return Sim._logic_decide(agent, candidates)
	if _slm_circuit_open:                                # 熔断后：不再 fire 注定挂死的推理（防原生泄漏），走 logic 地板
		return Sim._logic_decide(agent, candidates)
	var id := String(agent["id"])
	# 算力档节流：距上次 LLM 决策还不够久 → 直接走引擎（省一次 fire+可能的超时），快档 interval=1 几乎不节流
	if not _pending.has(id) and Sim.tick_no - int(_last_llm.get(id, -99999)) < _decide_interval():
		return Sim._logic_decide(agent, candidates)
	var capped := _cap_for_llm(candidates)  # 仅喂 LLM(_fire) + 回包重验用 top-36；logic 兜底/过载仍用全量 candidates
	var p: Dictionary = _pending.get(id, {})
	if p.is_empty():
		if _inflight >= MAX_INFLIGHT:
			return Sim._logic_decide(agent, candidates)  # P1-4：过载立即走 logic，不让 agent 干等到 need 触底
		if backend == "slm" and _slm_busy:
			return Sim._logic_decide(agent, candidates)  # 池化 worker 正忙（另一发在飞）→ 本 tick 走 logic，不空烧 fire/预算
		if not _budget_gate(id, agent):
			return {}                                    # L5 预算耗尽/被老化门挡下 → 本 tick 走引擎地板(LLM ∝ 预算而非 N；发声由优先级+老化公平分配)
		_fire(id, agent, capped, ctx)                    # 只把 top-36 喂给模型
		stats["waits"] = int(stats.get("waits", 0)) + 1  # 本 tick 未落地任何决策 → 不进诚实分母
		return {"_wait": true}
	# 已就绪（且到「揭晓」tick）→ 用「模型看到的候选快照」解析，再对【当前】候选按 stable key 重验(P1-1)
	if bool(p["has"]) and Sim.tick_no >= int(p["ready"]):
		var snap: Array = p.get("snapshot", [])
		_finish(id, agent)
		var picked := parse_decision(String(p["raw"]), snap)         # snap[pick]（+JSON 老路的台词/情绪）；{}=脏/越界
		if picked.is_empty():
			stats["bad_parse"] += 1
			return {}
		# 等待期间世界会变：模型选的候选必须在【当前】候选里仍存在（同 stable key）→ 用当前候选做基底落地；
		# 不在了(需求已满足/对象离开/候选重排) → 兜底 logic，绝不把旧选择套到变了的世界(P1-1)。
		var key := _cand_key(picked)
		var chosen := {}
		for c in capped:                                            # 本 tick 的 top-36（模型当初看的也是 top-36）
			if _cand_key(c) == key:
				chosen = c
				break
		if chosen.is_empty():
			stats["bad_parse"] += 1
			return {}
		var intent: Dictionary = (chosen as Dictionary).duplicate()
		stats["landed"] += 1
		_slm_fail_streak = 0                                     # 有成功 → 熔断计数清零
		_last_llm[id] = Sim.tick_no
		intent["say"] = String(picked["say"]) if picked.has("say") else Sim._canned_say(agent, intent)  # 有模型台词(JSON 老路)则留，否则冻结语音库
		if picked.has("emotion"): intent["emotion"] = picked["emotion"]
		if picked.has("affinity_delta"): intent["affinity_delta"] = picked["affinity_delta"]
		return intent
	# 超时（实时墙钟）→ 引擎兜底
	if Time.get_ticks_msec() >= int(p["due_ms"]):
		_finish(id, agent)
		stats["timeout"] += 1
		if backend == "slm":                                    # SLM 超时累计 → 到阈值熔断（防挂死 worker 无界泄漏 OOM，docs/34）
			_slm_fail_streak += 1
			if _slm_fail_streak >= SLM_CIRCUIT_TRIP and not _slm_circuit_open:
				_slm_circuit_open = true
				push_warning("[SLM] 熔断触发：连续 %d 次超时且无成功 → 停发 SLM、永久回退 logic 地板（防原生内存泄漏 OOM，见 docs/34）" % _slm_fail_streak)
				cancel_all()                                    # 清在飞 + 尽力释放，止血
		return {}
	stats["waits"] = int(stats.get("waits", 0)) + 1        # 同上：等待期轮询不算一次决策
	return {"_wait": true}                                # 仍在等

func _finish(id: String, agent: Dictionary) -> void:
	var p: Dictionary = _pending.get(id, {})
	_free_transport(p.get("http"), p.get("slm_chat"))    # 单一收尾：http 请求 + slm worker 都停止+释放（P1-2：旧代码只放 slm，超时的 http 仍在飞→污染下次）
	_pending.erase(id)
	_inflight = maxi(0, _inflight - 1)
	agent["thinking"] = false

# ── pick → candidates[pick] 健壮 glue（移植 22nd _llm_pick：脏输入/越界全兜底）──────
## 任何解析失败/越界 → 返回 {}，调用方用引擎 logic 兜底。模型永不能凭空造非法动作。
func parse_decision(raw: String, candidates: Array) -> Dictionary:
	if raw.strip_edges() == "" or candidates.is_empty():
		return {}
	var s := raw.strip_edges()
	# 主路（闭集选号）：仅当响应本质就是编号——首字符是合法编号(0-9/A-Z)、且其后无任何字母/数字续接。
	# fail-closed 防 prose（P2-3）："The answer is 2"(T=29)、"I choose A"(I)、"2 talk" 都不当编号 → 落 JSON 兜底/logic。
	# 台词不在此，由 decide() 从冻结语音库补。
	var pk := _label_idx(s.substr(0, 1))
	if pk >= 0 and pk < candidates.size():
		var pure := true
		var rest := s.substr(1)
		for j in rest.length():                          # 编号后若有任何字母/数字 → 是 prose，不采纳
			if _is_alnum_ascii(rest.substr(j, 1)):
				pure = false
				break
		if pure:
			return (candidates[pk] as Dictionary).duplicate()
	# 兼容旧 JSON({"pick":N,speech,emotion,...})：单测 + llm 老路仍可能这么回（含台词则保留）
	var data: Variant = JSON.parse_string(s)
	if not (data is Dictionary):
		var a := s.find("{")
		var b := s.rfind("}")
		if a >= 0 and b > a:
			data = JSON.parse_string(s.substr(a, b - a + 1))
	if not (data is Dictionary) or not (data as Dictionary).has("pick"):
		return {}
	var pick := int((data as Dictionary).get("pick", -1))
	if pick < 0 or pick >= candidates.size():            # 越界 → 兜底
		return {}
	var intent: Dictionary = (candidates[pick] as Dictionary).duplicate()
	var speech := String((data as Dictionary).get("speech", "")).strip_edges()
	if speech != "":
		intent["say"] = speech.substr(0, 60)
	if (data as Dictionary).has("emotion"):
		intent["emotion"] = String((data as Dictionary)["emotion"])
	if (data as Dictionary).has("affinity_delta"):
		intent["affinity_delta"] = clampi(int((data as Dictionary)["affinity_delta"]), -3, 3)
	return intent

## 闭集选号上限=36（单字符 0-9/A-Z 全是单 token）。候选 >36 时取 score 最高的 36 个喂 LLM；
## 低分候选（logic 几乎不会选）被裁掉，顺带缩 prefill。只作用于 LLM prompt，logic 兜底看全量。
func _cap_for_llm(candidates: Array) -> Array:
	if candidates.size() <= 36:
		return candidates
	var dup := candidates.duplicate()
	dup.sort_custom(func(a, b): return float((a as Dictionary).get("score", 0.0)) > float((b as Dictionary).get("score", 0.0)))
	return dup.slice(0, 36)

## 候选下标 ↔ 单字符编号（0-9 → A-Z，共 36）。闭集决策让模型只回一个字符 → decode≈1 token。
func _idx_label(i: int) -> String:
	if i < 10: return str(i)
	if i < 36: return String.chr(65 + i - 10)            # A-Z
	return str(i)                                        # >36：多字符(罕见)，回落数字
func _label_idx(c: String) -> int:
	if c.length() != 1: return -1
	var code := c.unicode_at(0)
	if code >= 48 and code <= 57: return code - 48        # 0-9
	if code >= 65 and code <= 90: return code - 65 + 10   # A-Z（大写，小写不认→JSON 里的字母不会误读）
	return -1
## ASCII 字母/数字判定（parse_decision 的 fail-closed prose 检测用）。
func _is_alnum_ascii(c: String) -> bool:
	if c.length() == 0: return false
	var o := c.unicode_at(0)
	return (o >= 48 and o <= 57) or (o >= 65 and o <= 90) or (o >= 97 and o <= 122)

# 回包只在该 NPC 的 pending 仍是发起它的同一 (epoch,req_id) 时才有效 → 迟到/跨局回包一律作废。
func _match(id: String, ep: int, rq: int) -> bool:
	return _pending.has(id) and int(_pending[id].get("epoch", -1)) == ep and int(_pending[id].get("req_id", -1)) == rq

# ── 发起异步请求 ─────────────────────────────────────────────────────────
func _fire(id: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> void:
	_inflight += 1
	stats["fired"] += 1
	_budget_used += 1                                    # L5 消费令牌（窗口在 _budget_gate 已对齐）
	_fire_count[id] = int(_fire_count.get(id, 0)) + 1    # L5 per-agent 发声计数（bench 测公平性）
	agent["thinking"] = true
	_req_seq += 1
	_pending[id] = {
		"epoch": world_epoch, "req_id": _req_seq, "prompt_tick": Sim.tick_no,
		"snapshot": candidates.duplicate(true),          # 模型看到的候选(decide 已截 top-36)：回包按此解析、再对当前候选重验
		"due_ms": Time.get_ticks_msec() + deadline_ms, "ready": Sim.tick_no, "raw": "", "has": false, "http": null, "slm_chat": null}
	if backend == "mock" or mock:
		_pending[id]["raw"] = _mock_raw(agent, candidates)
		_pending[id]["has"] = true
		_pending[id]["ready"] = Sim.tick_no + MOCK_DELAY      # 模拟推理延迟
	elif backend == "slm" and ClassDB.class_exists("NobodyWhoModel"):
		_fire_slm(id, agent, candidates, ctx)
	else:
		_fire_http(id, agent, candidates, ctx)

## mock：确定性挑最高分候选 + 一句台词（仅供链路验证；真模型给真选择）。
func _mock_raw(agent: Dictionary, candidates: Array) -> String:
	var bi := 0
	var bs := -INF
	for i in candidates.size():
		var s := float(candidates[i].get("score", 0.0))
		if s > bs:
			bs = s
			bi = i
	return _idx_label(bi)   # 闭集编号（与新决策契约一致；台词由 decide() 从语音库补）

## llm：OpenAI 兼容 chat-completions（异步 HTTPRequest）。完成回调把 content 存入 pending.raw。
func _fire_http(id: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	_pending[id]["http"] = http
	var ep := world_epoch
	var rq := int(_pending[id]["req_id"])
	http.request_completed.connect(func(_r, code, _h, body):
		var raw := ""
		if code == 200:
			var j: Variant = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary and j.has("choices") and (j["choices"] as Array).size() > 0:
				raw = String(j["choices"][0].get("message", {}).get("content", ""))
		if debug_llm:
			print("[llm] code=%d raw=%s" % [code, raw.strip_edges().substr(0, 50)])
		if _match(id, ep, rq):                                 # 仅同一 (epoch,req_id) 才写回 → 迟到/跨局回包作废(P1-2/3)
			_pending[id]["raw"] = raw
			_pending[id]["has"] = true
			_pending[id]["ready"] = Sim.tick_no                # 下 tick 即可消费
		if is_instance_valid(http): http.queue_free()
	)
	# 注：不发 response_format/json_schema——实测它在 qwen3 长 prompt 下受限解码卡死(只吐"{")；
	# 改靠 /no_think 压思考 + parse_decision 抽 {…}，实测 ~4.3s 稳定。(DECISION_SCHEMA 仅保留给 slm 的 GBNF 约束。)
	var body := {
		"model": model, "max_tokens": DECIDE_MAX_TOKENS, "temperature": 0.7,
		"messages": [
			{"role": "system", "content": _system_prompt()},
			{"role": "user", "content": build_prompt(agent, candidates, ctx)},
		],
	}
	var headers := ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	var err := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		if _match(id, ep, rq):
			_pending[id]["has"] = true                         # 立即就绪空串 → 解析失败 → 兜底
			_pending[id]["raw"] = ""
		if is_instance_valid(http): http.queue_free()

## slm：本地 GGUF（NobodyWho）。扩展内部已是异步（worker thread + 信号），勿再包 Thread。
## 每次决策起一个一次性 chat worker（json_schema 受限解码）→ response_finished 写回 raw → 释放。
## 注：per-call worker 略重（worker 启动开销），但能避免并发 ask 串扰；MAX_INFLIGHT 限并发。真机 GPU 下可接受。
func _fire_slm(id: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> void:
	# 走池化持久 worker（根治 per-call churn 的 use-after-free 崩溃 + worker 原生泄漏）。
	# 不设 json_schema 受限解码：长 prompt 下实测卡死只吐"{"；靠 _system_prompt 的 /no_think + parse_decision 抽 {…} 最稳。
	var route := {"mode": "decide", "id": id, "epoch": world_epoch, "req": int(_pending[id]["req_id"])}
	if not _slm_submit(_system_prompt(), build_prompt(agent, candidates, ctx), route):
		_pending[id]["has"] = true                 # worker 忙/不可用 → 空 → 本发兜底 logic（decide 下 tick 消费）
		_pending[id]["raw"] = ""

## ── 玩家 → NPC 自由对话（自由文本回复，区别于 decide 的 pick）──────────────
## 玩家面对的对话：不设 deadline-to-罐头（docs/07 §10），等真回复；缺模型/出错 → 人设化罐头兜底。
func chat(agent: Dictionary, player_text: String, ctx: Dictionary, cb: Callable) -> void:
	if backend == "mock" or mock:
		cb.call(_canned_reply(agent, player_text))
		return
	if backend == "llm":
		_chat_http(agent, player_text, ctx, cb)
		return
	if backend == "slm" and ClassDB.class_exists("NobodyWhoModel"):
		_chat_slm(agent, player_text, ctx, cb)
		return
	cb.call(_canned_reply(agent, player_text))      # logic/无模型 → 罐头兜底

func _canned_reply(agent: Dictionary, _player_text: String) -> String:
	var p: Dictionary = agent.get("persona", {})
	var traits: Array = p.get("traits", [])
	if "爱八卦" in traits: return "哎呀你来啦！正好，我跟你说个新鲜事～"
	if "寡言" in traits: return "嗯。……你说。"
	if "温柔" in traits: return "你来啦，最近身体还好吗？"
	if "豁达" in traits: return "哈哈，小子，坐下唠唠！"
	if "好奇" in traits: return "真的假的？！快跟我讲讲！"
	return "嗨，找我有事吗？"

## 引擎事实护栏（chat 用）：把"这个 NPC 知道、但绝不可外露的秘密"这条引擎事实喂给模型 → 对话安全靠构造。
## 收 agent.beliefs 里所有 secret==true 的 claim（自己的秘密 + 别人吐露/说漏给它的）。
## 对拍验证（docs/22 护栏）：喂此约束后对话泄密率 35%→0%、入戏不降反升。只读旁路：不抽 RNG、不进 digest，
## 且 chat 玩家发起、CI(backend=null) 从不触达 → 红线零影响。放养的 LLM 每三次漏一次秘密，故这条是必需。
func _secret_guard(agent: Dictionary) -> String:
	var beliefs: Dictionary = agent.get("beliefs", {})
	var claims := []
	for subj in beliefs:
		var b = beliefs[subj]
		if b is Dictionary and bool(b.get("secret", false)):
			var c := String(b.get("claim", "")).strip_edges()
			if c != "" and not claims.has(c):
				claims.append(c)
	if claims.is_empty():
		return ""
	return " 【护栏·守口如瓶】以下私密你知道、但绝不可向人透露、暗示或让人推断出来：%s。被追问就用你的口吻自然岔开、否认或沉默，绝不说破。" % "；".join(claims)

## LLM 反思润色（可选皮肤，docs/03）：把引擎地板洞察 + 近期记忆 → 一句更自然的内心独白，异步写回记忆。
## 限预算(复用 L5 令牌桶)；纯 logic/超预算/无模型 → 直接返回(保留地板洞察)。Sim._reflect_llm 调用。
func reflect(agent: Dictionary, floor_insight: String, recent: Array, cb: Callable) -> void:
	if backend == "logic" or _slm_circuit_open:      # 熔断后不发 SLM 反思（保留引擎地板洞察，同 logic）
		return
	if llm_budget > 0:                               # 复用 L5 全镇令牌桶的窗口+硬顶（反思是后台任务，不走老化优先门）
		var w := int(Sim.tick_no / Sim.TICKS_PER_DAY)
		if w != _budget_window:
			_budget_window = w
			_budget_used = 0
		if _budget_used >= llm_budget:
			return
	_budget_used += 1                                # 与决策共用全镇令牌桶
	var p: Dictionary = agent.get("persona", {})
	var sys := "你在扮演像素小镇居民%s（%s，口吻:%s）。回顾最近的经历，用一句你自己口吻的内心独白，说出此刻心境或对某人的看法。第一人称、不超过25字、只输出这一句、不要引号。%s" % [
		p.get("name", ""), p.get("bio", ""), p.get("style", ""), (" /no_think" if no_think else "")]
	var user := "最近：" + "；".join(recent) + "。（心里大概是：" + floor_insight + "）"
	if backend == "mock" or mock:
		cb.call("（夜里想着）" + floor_insight)         # 确定性 mock：验证 plumbing
	elif backend == "llm":
		_gen_http(sys, user, cb)
	elif backend == "slm" and ClassDB.class_exists("NobodyWhoModel"):
		_gen_slm(sys, user, cb)

## 通用一次性生成（自由文本，无 json 约束）—— HTTP（OpenAI 兼容）。reflect 复用。
func _gen_http(sys: String, user: String, cb: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		var out := ""
		if code == 200:
			var j: Variant = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary and j.has("choices") and (j["choices"] as Array).size() > 0:
				out = String(j["choices"][0].get("message", {}).get("content", "")).strip_edges()
		http.queue_free()
		cb.call(out.substr(0, 60)))
	var reqbody := {"model": model, "max_tokens": MAX_TOKENS, "temperature": 0.85,
		"messages": [{"role": "system", "content": sys}, {"role": "user", "content": user}]}
	if http.request(endpoint, ["Content-Type: application/json", "Authorization: Bearer " + api_key], HTTPClient.METHOD_POST, JSON.stringify(reqbody)) != OK:
		http.queue_free()
		cb.call("")

## 通用一次性生成 —— NobodyWho（嵌入式 SLM）。reflect 复用。
func _gen_slm(sys: String, user: String, cb: Callable) -> void:
	if _slm_circuit_open:                             # 熔断后不发 SLM（reflect/chat 共用此路）→ 调用方走罐头兜底
		cb.call("")
		return
	if not _slm_submit(sys, user, {"mode": "cb", "cb": cb, "cap": 60, "fallback": ""}):
		cb.call("")                                  # 池化 worker 忙/不可用 → 调用方兜底（reflect 保留地板洞察）

func _chat_http(agent: Dictionary, player_text: String, ctx: Dictionary, cb: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		var reply := _canned_reply(agent, player_text)
		if code == 200:
			var j: Variant = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary and j.has("choices") and (j["choices"] as Array).size() > 0:
				var c := String(j["choices"][0].get("message", {}).get("content", "")).strip_edges()
				if c != "":
					reply = c.substr(0, 80)
		http.queue_free()
		cb.call(reply)
	)
	var p: Dictionary = agent.get("persona", {})
	var mem := ""
	if agent.get("memory") != null:
		var ms: Array = agent["memory"].retrieve([], int(ctx.get("tick", 0)), 3)
		if not ms.is_empty():
			mem = " 你近期记得：" + "；".join(ms) + "。"
	var mm := _mood(agent)
	var sit := "此刻是%s，你%s。" % [_phase_zh(float(ctx.get("tod", 0.0))), String(mm[0])]
	var sys := "你在扮演像素小镇居民 %s（%s，性格:%s，口吻:%s）。%s%s%s 用第一人称、你的口吻，贴合当下心情对玩家自然回 1-2 句，只输出台词本身、别复述设定。%s" % [
		p.get("name", ""), p.get("bio", ""), "·".join(p.get("traits", [])), p.get("style", ""), sit, mem, _secret_guard(agent), (" /no_think" if no_think else "")]
	var reqbody := {"model": model, "max_tokens": MAX_TOKENS, "temperature": 0.8,
		"messages": [{"role": "system", "content": sys}, {"role": "user", "content": player_text}]}
	var err := http.request(endpoint, ["Content-Type: application/json", "Authorization: Bearer " + api_key], HTTPClient.METHOD_POST, JSON.stringify(reqbody))
	if err != OK:
		http.queue_free()
		cb.call(_canned_reply(agent, player_text))

## slm 自由对话（NobodyWho，自由文本，无 json 约束）：一次性 chat worker → response_finished 回调。
func _chat_slm(agent: Dictionary, player_text: String, ctx: Dictionary, cb: Callable) -> void:
	var p: Dictionary = agent.get("persona", {})
	var mem := ""
	if agent.get("memory") != null:
		var ms: Array = agent["memory"].retrieve([], int(ctx.get("tick", 0)), 3)
		if not ms.is_empty():
			mem = " 你近期记得：" + "；".join(ms) + "。"
	var mm := _mood(agent)
	var sys := "你在扮演像素小镇居民 %s（%s，性格:%s，口吻:%s）。此刻是%s，你%s。%s%s 用第一人称、你的口吻，贴合当下心情对玩家自然回 1-2 句，只输出台词本身、别复述设定。" % [
		p.get("name", ""), p.get("bio", ""), "·".join(p.get("traits", [])), p.get("style", ""), _phase_zh(float(ctx.get("tod", 0.0))), String(mm[0]), mem, _secret_guard(agent)]
	if not _slm_submit(sys, player_text, {"mode": "cb", "cb": cb, "cap": 200, "fallback": _canned_reply(agent, player_text)}):
		cb.call(_canned_reply(agent, player_text))    # 池化 worker 忙/不可用 → 罐头兜底

func _system_prompt() -> String:
	# 决策=闭集选号（edge-npu-8elite「决策≠生成」洞察）：只让模型出一个编号 → decode≈1 token（不再生成 80-token JSON），
	# 台词改由冻结·70B 语音库补（decouple）。系统 prompt 缩到最短，prefill 也随之降。/no_think 关思考(否则烧满 token)。
	return "你是像素小镇的居民。从下面【候选】里挑一个此刻最想做的行动，只回它的【编号】（一个字符，如 3 或 A），别回任何其它字。" \
		+ (" /no_think" if no_think else "")

# ── 语音深化辅助（docs/03）：把 agent 当下处境喂给模型，产更贴人设/更 grounded 的台词 ──
const NEED_ZH := {"hunger": "饥饿", "energy": "精力", "social": "社交", "fun": "趣味", "hygiene": "卫生"}
# 社交动作 → 中文（物件动作 action 本就是中文）；喂模型统一中文，别中英混。
const ACTION_ZH := {
	"greet": "打招呼", "give": "送礼", "gossip": "说八卦", "gossip_rep": "提醒名声",
	"discuss": "聊看法", "invite": "约见", "confront": "当面理论", "apologize": "道歉",
	"confide": "说心事", "leak": "说漏秘密", "endorse": "统一口径", "rally_oust": "联合施压", "aid": "搭把手",
}

func _phase_zh(tod: float) -> String:
	if tod < 0.22: return "深夜"
	elif tod < 0.34: return "清晨"
	elif tod < 0.55: return "上午"
	elif tod < 0.68: return "午后"
	elif tod < 0.86: return "黄昏"
	return "夜里"

## 与某人的关系一言蔽之（读 agent 自己的关系账本，无需 Sim）。
func _rel_hint(agent: Dictionary, oid: String) -> String:
	var rels: Dictionary = agent.get("relationships", {})
	if not rels.has(oid):
		return "还不熟"
	var r: Dictionary = rels[oid]
	var aff := float(r.get("affinity", 0.0))
	var fam := float(r.get("familiarity", 0.0))
	if aff <= -15.0: return "有过节"
	if fam >= 8.0 and aff >= 15.0: return "老友"
	if fam >= 8.0: return "熟人"
	if aff >= 15.0: return "投缘"
	return "点头之交"

## 当下心情（由最缺需求派生，给模型一个情绪锚）。返回 [mood, low_need_id, low_val]。
func _mood(agent: Dictionary) -> Array:
	var low_id := ""
	var low_v := 101.0
	for nid in agent.get("needs", {}):
		var v := float(agent["needs"][nid])
		if v < low_v:
			low_v = v; low_id = nid
	var mood := "还算自在"
	if low_v < 25.0:
		mood = "有点撑不住了"
	elif low_v < 45.0:
		match low_id:
			"hunger": mood = "肚子有点饿"
			"energy": mood = "有些困乏"
			"social": mood = "想找人说说话"
			"fun": mood = "有点无聊"
			"hygiene": mood = "想收拾一下自己"
			_: mood = "有些不自在"
	return [mood, low_id, low_v]

## 模板化 prompt（PERSONA / NOW / STATE / MEMORIES / 候选）；静态人设在前以利 KV 复用，易变态在后。
## 语音深化：喂 心情/最缺需求/近事/与每个候选对象的关系 → 模型能说出"为什么"的、贴人设的台词，而非泛泛寒暄。
func build_prompt(agent: Dictionary, candidates: Array, ctx: Dictionary) -> String:
	var p: Dictionary = agent.get("persona", {})
	var traits: Array = p.get("traits", [])
	var lines := []
	lines.append("[人设] %s：性格%s，口吻%s" % [p.get("name", ""), "·".join(traits), p.get("style", "")])   # 砍 bio：口吻+性格已够定调，省 prefill
	var m := _mood(agent)
	lines.append("[此刻] 第%d天·%s，%s" % [int(ctx.get("day", 1)), _phase_zh(float(ctx.get("tod", 0.0))), String(m[0])])
	if String(m[1]) != "":
		lines.append("[状态] 最想满足:%s(%d/100)" % [NEED_ZH.get(m[1], m[1]), int(m[2])])
	var mem_obj = agent.get("memory")
	if mem_obj != null:
		var mem: Array = mem_obj.retrieve([], int(ctx.get("tick", 0)), 2)   # 3→2：省 prefill
		if not mem.is_empty():
			lines.append("[近事] " + "；".join(mem))
	var opts := []
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		var act := String(c.get("action", ""))
		var label := String(ACTION_ZH.get(act, act))     # 社交动作转中文；物件动作本就中文
		if String(c.get("kind", "")) == "social":
			var pid := String(c.get("partner", ""))
			label += "→%s(%s)" % [Sim._name(Sim.get_agent(pid)), _rel_hint(agent, pid)]
		opts.append("%s=%s" % [_idx_label(i), label])   # 单字符编号(0-9/A-Z)→ 模型只回这一个字符
	lines.append("[候选] " + " ".join(opts))
	return "\n".join(lines)
