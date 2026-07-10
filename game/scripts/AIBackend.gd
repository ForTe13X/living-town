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
var stats := {"fired": 0, "landed": 0, "bad_parse": 0, "timeout": 0}  # bench 用：合法率/截止线命中率埋点

func reset_stats() -> void:
	stats = {"fired": 0, "landed": 0, "bad_parse": 0, "timeout": 0}
	# L5 per-run 状态清零（否则跨 seed 的陈旧度/发声计数/预算窗口会串味）
	_fire_count = {}
	_last_llm = {}
	_pending = {}
	_inflight = 0
	_budget_window = -1
	_budget_used = 0
# ── 嵌入式 SLM（NobodyWho GDExtension + 本地 GGUF）──实测：Godot 4.6.2 加载需 glibc≥2.38 + libvulkan1 loader。
var slm_model_path := "res://models/qwen2.5-3b-instruct-q4_k_m.gguf"   # 默认 3B-Q4：中端 780M 实测 ~2.9s、质量明显优于 1.5B(docs/11 §12.2b)
var slm_model_override := ""                      # 设置面板里手选的 gguf 绝对路径（存 settings.cfg）；非空且存在则优先（换模型 A/B 用）
# 轻量备选(极致包体/最低端)：res://models/qwen2.5-1.5b-instruct-q4_k_m.gguf（~1.3s，质量中）。capability 探针太慢会自动降 logic。
var slm_use_gpu := true                          # 真机优先 GPU(Vulkan)；无设备自动回退 CPU（容器实测 CPU ~1字/s，故真机才实用）
var _slm_model: Object = null                    # 共享 NobodyWhoModel（懒加载，~1GB 仅载一次）

const DEADLINE_MS := 12000     # 截止线上限/默认（实时墙钟毫秒）
var deadline_ms := DEADLINE_MS # 自适应实时截止线：probe_capability 据本机 p50 设 clamp(6×p50,3000,12000)
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
const MAX_TOKENS := 128   # 决策 JSON(含台词)约 80–120 字符；80 token 会截断台词，故 128

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

## NobodyWho/llama.cpp 需要能 mmap 的【真实文件系统路径】。安卓上按序找一个存在的 gguf：
##   ① 公共可 MTP 拖放位置（Documents/LivingTown、Documents、Download）——用户经「此电脑\手机\Documents」直接拷入，
##      免 adb；读公共位置需一次性授「所有文件访问」权限（见 docs/18）。
##   ② user://model.gguf（app 私有外部 files 目录=真实路径，免权限，但需 adb push 送达）。
## 都没有 → 返回 user:// 路径（加载失败→算力探针超时→自动降确定性 logic，镇子照常运转）。桌面沿用 res:// 不变。
func _resolve_model_path() -> String:
	if slm_model_override != "" and FileAccess.file_exists(slm_model_override):
		return slm_model_override                 # 设置面板手选优先（桌面/安卓都认）
	if not OS.has_feature("android"):
		return slm_model_path
	for p in _android_model_candidates():
		if FileAccess.file_exists(p):
			return p
	return ProjectSettings.globalize_path("user://model.gguf")

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
	if _slm_model != null and is_instance_valid(_slm_model):
		_slm_model.queue_free()      # 卸掉旧模型 → _ensure_slm_model 会按新 override 重载
	_slm_model = null

# ── 启动算力探测（测一发暖决策 → 分档 + 自适应截止线 + 太慢自动降 logic）────────────
## 实测依据(docs/11 §12)：现代机决策 1–5s 都在 12s 线内；>~8s 即不实用 → 降确定性 logic。
## cb 收到 {tier, p50_ms, deadline_ms, backend}。logic/mock 立即返回（无需探测）。
func probe_capability(agent: Dictionary, candidates: Array, ctx: Dictionary, cb: Callable) -> void:
	if backend == "logic" or backend == "mock":
		tier = "instant"
		cb.call({"tier": tier, "p50_ms": 0, "deadline_ms": deadline_ms, "backend": backend})
		return
	var warm := 0
	for i in 2:                                   # 第1发付冷载，取第2发为暖延迟
		var t0 := Time.get_ticks_msec()
		await _probe_once(agent, candidates, ctx)
		warm = Time.get_ticks_msec() - t0
	p50_ms = warm
	if p50_ms < 1500: tier = "fast"
	elif p50_ms < 6000: tier = "host"
	elif p50_ms < 15000: tier = "slow"
	else: tier = "toolslow"
	deadline_ms = clampi(6 * p50_ms, 3000, DEADLINE_MS)
	if p50_ms > 8000:                             # 太慢：降级到确定性 logic（仍完整可玩）
		backend = "logic"
		backend_requested = "logic"               # 关键：同步意图，否则 decide() 的运行期切换会立刻把降级撤销（评审确认的回归）。
		                                          # 磁盘上的持久化意图只由显式 toggle 写入 → 不受影响，下次启动仍会重试 slm 并重新探测。
		tier = "demoted_logic"
	cb.call({"tier": tier, "p50_ms": p50_ms, "deadline_ms": deadline_ms, "backend": backend})

## 直连一发计时决策（绕过 pending 状态机），返回 raw 串。
func _probe_once(agent: Dictionary, candidates: Array, ctx: Dictionary) -> String:
	var sys := _system_prompt()
	var usr := build_prompt(agent, candidates, ctx)
	if backend == "slm" and ClassDB.class_exists("NobodyWhoModel"):
		var model := _ensure_slm_model()
		if model == null: return ""
		var chat: Object = ClassDB.instantiate("NobodyWhoChat")
		chat.set("model_node", model)
		chat.set("system_prompt", sys)
		chat.set("allow_thinking", false)
		add_child(chat)
		chat.call("start_worker")
		# 不设 json_schema 受限解码：worker 异步起、配置常在 ask 前未就绪被丢弃(WARN 刷屏)；且长 prompt 下受限解码实测卡死只吐"{"(见 _fire_slm)。靠 parse_decision 抽 {…} 最稳。
		chat.call("ask", usr)
		var resp = await chat.response_finished
		if is_instance_valid(chat): chat.queue_free()
		return String(resp)
	# llm：HTTPRequest 直连
	var http := HTTPRequest.new()
	add_child(http)
	var body := {"model": model, "max_tokens": MAX_TOKENS, "temperature": 0.6,
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

# ── 同步入口（Sim 每 tick 调）──────────────────────────────────────────────
func decide(agent: Dictionary, candidates: Array, ctx: Dictionary) -> Dictionary:
	# 运行期后端切换（手机上无 CLI 参数）：仅在无在飞请求时应用 backend_requested，
	# 否则旧后端的异步回包会被新后端的解析逻辑误读。logic 模式 digest 不受影响——
	# _logic_decide 的 RNG 只依赖 (seed,tick,salt,who)，与 backend 无关（红线守恒）。
	if backend != backend_requested and _pending.is_empty() and _inflight == 0:
		backend = backend_requested
	if backend == "logic":
		return Sim._logic_decide(agent, candidates)
	var id := String(agent["id"])
	# 算力档节流：距上次 LLM 决策还不够久 → 直接走引擎（省一次 fire+可能的超时），快档 interval=1 几乎不节流
	if not _pending.has(id) and Sim.tick_no - int(_last_llm.get(id, -99999)) < _decide_interval():
		return Sim._logic_decide(agent, candidates)
	var p: Dictionary = _pending.get(id, {})
	if p.is_empty():
		if _inflight >= MAX_INFLIGHT:
			return {"_wait": true}                       # 过载：稍后再问
		if not _budget_gate(id, agent):
			return {}                                    # L5 预算耗尽/被老化门挡下 → 本 tick 走引擎地板(LLM ∝ 预算而非 N；发声由优先级+老化公平分配)
		_fire(id, agent, candidates, ctx)
		return {"_wait": true}
	# 已就绪（且到了「揭晓」tick）→ 解析 + 校验
	if bool(p["has"]) and Sim.tick_no >= int(p["ready"]):
		_finish(id, agent)
		var intent := parse_decision(String(p["raw"]), candidates)   # {} → Sim 兜底；非空 → 落地
		if intent.is_empty(): stats["bad_parse"] += 1                # 脏/越界 → 兜底
		else:
			stats["landed"] += 1                                    # 合法落地
			_last_llm[id] = Sim.tick_no                             # 记录发言时刻 → 节流计时
		return intent
	# 超时（实时墙钟）→ 引擎兜底
	if Time.get_ticks_msec() >= int(p["due_ms"]):
		_finish(id, agent)
		stats["timeout"] += 1
		return {}
	return {"_wait": true}                                # 仍在等

func _finish(id: String, agent: Dictionary) -> void:
	var p: Dictionary = _pending.get(id, {})
	# slm 超时清理：丢弃仍在生成的 NobodyWho worker，避免慢机上 worker 堆积（GPU 下通常已完成）
	var chat = p.get("slm_chat")
	if chat != null and is_instance_valid(chat):
		if chat.has_method("stop_generation"):
			chat.call("stop_generation")
		chat.queue_free()
	_pending.erase(id)
	_inflight = maxi(0, _inflight - 1)
	agent["thinking"] = false

# ── pick → candidates[pick] 健壮 glue（移植 22nd _llm_pick：脏输入/越界全兜底）──────
## 任何解析失败/越界 → 返回 {}，调用方用引擎 logic 兜底。模型永不能凭空造非法动作。
func parse_decision(raw: String, candidates: Array) -> Dictionary:
	if raw.strip_edges() == "" or candidates.is_empty():
		return {}
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		# 抠出第一个 {...} 子串再试（模型常带前后缀/markdown）
		var s := raw.find("{")
		var e := raw.rfind("}")
		if s >= 0 and e > s:
			data = JSON.parse_string(raw.substr(s, e - s + 1))
	if not (data is Dictionary) or not data.has("pick"):
		return {}
	var pick := int(data.get("pick", -1))
	if pick < 0 or pick >= candidates.size():            # 越界 → 兜底
		return {}
	var intent: Dictionary = (candidates[pick] as Dictionary).duplicate()
	var speech := String(data.get("speech", "")).strip_edges()
	if speech != "":
		intent["say"] = speech.substr(0, 60)
	if data.has("emotion"):
		intent["emotion"] = String(data["emotion"])
	if data.has("affinity_delta"):
		intent["affinity_delta"] = clampi(int(data["affinity_delta"]), -3, 3)
	return intent

# ── 发起异步请求 ─────────────────────────────────────────────────────────
func _fire(id: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> void:
	_inflight += 1
	stats["fired"] += 1
	_budget_used += 1                                    # L5 消费令牌（窗口在 _budget_gate 已对齐）
	_fire_count[id] = int(_fire_count.get(id, 0)) + 1    # L5 per-agent 发声计数（bench 测公平性）
	agent["thinking"] = true
	_pending[id] = {"due_ms": Time.get_ticks_msec() + deadline_ms, "ready": Sim.tick_no, "raw": "", "has": false, "http": null}
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
	return JSON.stringify({"pick": bi, "speech": "嗯，就这么办。", "emotion": "neutral", "affinity_delta": 1})

## llm：OpenAI 兼容 chat-completions（异步 HTTPRequest）。完成回调把 content 存入 pending.raw。
func _fire_http(id: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	_pending[id]["http"] = http
	http.request_completed.connect(func(_r, code, _h, body):
		var raw := ""
		if code == 200:
			var j: Variant = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary and j.has("choices") and (j["choices"] as Array).size() > 0:
				raw = String(j["choices"][0].get("message", {}).get("content", ""))
		if debug_llm:
			print("[llm] code=%d raw=%s" % [code, raw.strip_edges().substr(0, 50)])
		if _pending.has(id):
			_pending[id]["raw"] = raw
			_pending[id]["has"] = true
			_pending[id]["ready"] = Sim.tick_no                # 下 tick 即可消费
		http.queue_free()
	)
	# 注：不发 response_format/json_schema——实测它在 qwen3 长 prompt 下受限解码卡死(只吐"{")；
	# 改靠 /no_think 压思考 + parse_decision 抽 {…}，实测 ~4.3s 稳定。(DECISION_SCHEMA 仅保留给 slm 的 GBNF 约束。)
	var body := {
		"model": model, "max_tokens": MAX_TOKENS, "temperature": 0.7,
		"messages": [
			{"role": "system", "content": _system_prompt()},
			{"role": "user", "content": build_prompt(agent, candidates, ctx)},
		],
	}
	var headers := ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	var err := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_pending[id]["has"] = true                             # 立即就绪为空串 → 解析失败 → 兜底
		_pending[id]["raw"] = ""

## slm：本地 GGUF（NobodyWho）。扩展内部已是异步（worker thread + 信号），勿再包 Thread。
## 每次决策起一个一次性 chat worker（json_schema 受限解码）→ response_finished 写回 raw → 释放。
## 注：per-call worker 略重（worker 启动开销），但能避免并发 ask 串扰；MAX_INFLIGHT 限并发。真机 GPU 下可接受。
func _fire_slm(id: String, agent: Dictionary, candidates: Array, ctx: Dictionary) -> void:
	var model := _ensure_slm_model()
	if model == null:
		_pending[id]["has"] = true                 # 无扩展/模型 → 空 → 兜底
		_pending[id]["raw"] = ""
		return
	var chat: Object = ClassDB.instantiate("NobodyWhoChat")
	chat.set("model_node", model)
	chat.set("system_prompt", _system_prompt())
	chat.set("allow_thinking", false)
	add_child(chat)
	_pending[id]["slm_chat"] = chat                 # 存句柄：超时(_finish)时可停止+释放，避免堆积
	chat.call("start_worker")
	# 不设 json_schema 受限解码：NobodyWho worker 异步起，配置常在 ask 前未就绪被丢弃(WARN×N)；且长 prompt(多候选)下受限解码实测卡死只吐"{"。去掉它，靠 _system_prompt 的 /no_think + parse_decision 抽 {…} 最稳。
	chat.connect("response_finished", func(resp):
		if _pending.has(id):
			_pending[id]["raw"] = String(resp)
			_pending[id]["has"] = true
			_pending[id]["ready"] = Sim.tick_no
		if is_instance_valid(chat):                 # _finish 可能已先释放（超时）
			chat.queue_free()
	, CONNECT_ONE_SHOT)
	chat.call("ask", build_prompt(agent, candidates, ctx))

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

## LLM 反思润色（可选皮肤，docs/03）：把引擎地板洞察 + 近期记忆 → 一句更自然的内心独白，异步写回记忆。
## 限预算(复用 L5 令牌桶)；纯 logic/超预算/无模型 → 直接返回(保留地板洞察)。Sim._reflect_llm 调用。
func reflect(agent: Dictionary, floor_insight: String, recent: Array, cb: Callable) -> void:
	if backend == "logic":
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
	var model_node := _ensure_slm_model()
	if model_node == null:
		cb.call("")
		return
	var chat: Object = ClassDB.instantiate("NobodyWhoChat")
	chat.set("model_node", model_node)
	chat.set("system_prompt", sys)
	chat.set("allow_thinking", false)
	add_child(chat)
	chat.call("start_worker")
	chat.connect("response_finished", func(resp):
		cb.call(String(resp).strip_edges().substr(0, 60))
		chat.queue_free()
	, CONNECT_ONE_SHOT)
	chat.call("ask", user)

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
	var sys := "你在扮演像素小镇居民 %s（%s，性格:%s，口吻:%s）。%s%s 用第一人称、你的口吻，贴合当下心情对玩家自然回 1-2 句，只输出台词本身、别复述设定。%s" % [
		p.get("name", ""), p.get("bio", ""), "·".join(p.get("traits", [])), p.get("style", ""), sit, mem, (" /no_think" if no_think else "")]
	var reqbody := {"model": model, "max_tokens": MAX_TOKENS, "temperature": 0.8,
		"messages": [{"role": "system", "content": sys}, {"role": "user", "content": player_text}]}
	var err := http.request(endpoint, ["Content-Type: application/json", "Authorization: Bearer " + api_key], HTTPClient.METHOD_POST, JSON.stringify(reqbody))
	if err != OK:
		http.queue_free()
		cb.call(_canned_reply(agent, player_text))

## slm 自由对话（NobodyWho，自由文本，无 json 约束）：一次性 chat worker → response_finished 回调。
func _chat_slm(agent: Dictionary, player_text: String, ctx: Dictionary, cb: Callable) -> void:
	var model := _ensure_slm_model()
	if model == null:
		cb.call(_canned_reply(agent, player_text))
		return
	var p: Dictionary = agent.get("persona", {})
	var mem := ""
	if agent.get("memory") != null:
		var ms: Array = agent["memory"].retrieve([], int(ctx.get("tick", 0)), 3)
		if not ms.is_empty():
			mem = " 你近期记得：" + "；".join(ms) + "。"
	var mm := _mood(agent)
	var sys := "你在扮演像素小镇居民 %s（%s，性格:%s，口吻:%s）。此刻是%s，你%s。%s 用第一人称、你的口吻，贴合当下心情对玩家自然回 1-2 句，只输出台词本身、别复述设定。" % [
		p.get("name", ""), p.get("bio", ""), "·".join(p.get("traits", [])), p.get("style", ""), _phase_zh(float(ctx.get("tod", 0.0))), String(mm[0]), mem]
	var chat: Object = ClassDB.instantiate("NobodyWhoChat")
	chat.set("model_node", model)
	chat.set("system_prompt", sys)
	chat.set("allow_thinking", false)
	add_child(chat)
	chat.call("start_worker")
	chat.connect("response_finished", func(resp):
		var reply := String(resp).strip_edges()
		cb.call(reply if reply != "" else _canned_reply(agent, player_text))
		chat.queue_free()
	, CONNECT_ONE_SHOT)
	chat.call("ask", player_text)

func _system_prompt() -> String:
	# 静态前缀（可被 prompt-cache 复用）：世界规则 + 输出契约
	# 实测(qwen3@LM Studio)：①不加 /no_think → 思考烧满 token、content 空、37s finish=length；
	#   ②json_schema 受限解码在长 prompt(9候选)下卡死只吐 "{"。故：去 json_schema + 加 /no_think + 靠 parse_decision 抽 {…}，最稳(~4.3s)。
	return "你在扮演一个像素小镇的居民。只能从【候选】里按下标 pick 选一个行动，并给≤2句符合人设的台词。" \
		+ "台词只用中文、不夹英文，要具体贴合[人设]的性格口吻 + [此刻]心情 + [状态]最想满足的需求 + [近事] + 与对方的关系(候选里括号提示)，" \
		+ "像真人随口说的一句话，避免泛泛的天气/寒暄套话，别复述行动名。" \
		+ "严格只输出 JSON：{\"pick\":整数下标,\"speech\":\"台词\",\"emotion\":\"neutral|happy|angry|sad|anxious|fond\",\"affinity_delta\":-3到3}。" \
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
	lines.append("[人设] 你是%s：%s 性格:%s 口吻:%s" % [p.get("name", ""), p.get("bio", ""), "·".join(traits), p.get("style", "")])
	var m := _mood(agent)
	lines.append("[此刻] 第%d天·%s，%s" % [int(ctx.get("day", 1)), _phase_zh(float(ctx.get("tod", 0.0))), String(m[0])])
	if String(m[1]) != "":
		lines.append("[状态] 最想满足:%s(%d/100)" % [NEED_ZH.get(m[1], m[1]), int(m[2])])
	var mem_obj = agent.get("memory")
	if mem_obj != null:
		var mem: Array = mem_obj.retrieve([], int(ctx.get("tick", 0)), 3)
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
		opts.append("%d=%s" % [i, label])
	lines.append("[候选] " + " ".join(opts))
	return "\n".join(lines)
