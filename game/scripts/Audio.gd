extends Node
## Audio.gd — autoload "Audio"：小镇的音景，**全部由数学合成、运行时生成 PCM**。
##
## 为什么是合成而不是素材：红线#4（不碰版权）——仓库里一个音频文件都不进，因此不存在授权/来源问题；
## 且合成结果由固定常数决定，逐字节可复现（同一份代码在任何机器上烘出同一段 PCM）。
## 复用来源：`godot-game-pipeline` 技能的 `scripts/gen_audio.py`（红线#5 复用优先）——
##   包络 `env_ad`、加性 `tone`、`seq` 叠加、以及"BGM 两端淡入淡出避免接缝爆音"的配方全部沿用；
##   本文件做了三处**针对本项目的改写**，原因写在各自的函数注释里：
##   ① 配方是"离线写 .wav 文件 + 引擎里 load"，这里改成**内存里直接建 `AudioStreamWAV`**（零文件入库）；
##   ② 配方的无缝 BGM 靠"两端淡到静音"，代价是每圈都有一次可听的呼吸；这里改成**频率量子化**
##      （所有分音取 1/时长 的整数倍 → 接缝处相位天然连续），底噪因此可以真正持续；
##   ③ 配方按每样本调 `sin()`；底噪有 3.2 万样本 × 多声部，在 GDScript 里太贵 →
##      底噪走 1024 点正弦查表 + 线性插值，SFX（短）仍用真 `sin()`。
##
## 接线纪律（这是本文件能与其它棒并行改动的**全部原因**）：
##   本文件**只在自己的 `_ready()` 里连 `Sim` 的信号**，不改 `Main.gd` / `WorldView.gd` / `Sim.gd` 一个字符。
##   对 `Sim` **只读**（`time_of_day()` / `agents` / `festival_active`），**从不写**——
##   因此对仿真轨迹零影响，金标逐字节不动（docs/43 §三 C2）。
##
## headless 纪律：`tools/ci.sh` 全程 `--headless`（=Dummy 音频驱动）。Dummy 驱动**仍然推进混音**，
##   所以 `AudioEffectRecord` 能在无声卡的环境里录到真实输出（技能 `references/recording-pipeline.md` §1）。
##   本文件自带 `--audiocap <wav> <secs>` 采集钩子（**放在这里而不是 `Main.gd`**，同样是为了不越界）。
##
## 限流走**渲染时钟**（`_process(delta)` 累加），不读墙钟（`Time.*`）、不用 `randi()/randf()`：
##   副作用之一正好是需要的——`goto_tick()` 暖机会在**一帧之内**重放上千条事件，
##   而渲染时钟在那一帧里不前进 ⇒ 整个暖机最多出一声，不会炸成一片噪音。
##
## 对外 API（给后续棒用，不需要改本文件）：
##   `Audio.enabled`、`Audio.master_db`、`Audio.play_cue(name, gain_db)`、`Audio.play_ui_click()`。

# ── 合成参数 ─────────────────────────────────────────────────────────────────
const SR_SFX := 22050          # SFX 采样率（短，够亮）
const SR_BED := 8000           # 底噪采样率：内容全在 500Hz 以下，8k 的 Nyquist 绰绰有余，合成成本降到 1/3
const BED_SECS := 4.0          # 底噪循环长度（秒）——同时是频率量子 1/BED_SECS = 0.25Hz 的来源
const TBL := 1024              # 正弦查表点数

# ── 混音电平 ─────────────────────────────────────────────────────────────────
const BED_DAY_DB := -16.0      # 白昼底噪
const BED_NIGHT_DB := -18.0    # 夜晚底噪（更暗更轻）
const SILENT_DB := -60.0       # 交叉淡入的"静音端"（不用 -inf，避免 volume_db 出现 -inf 传播）
const SFX_VOICES := 6          # SFX 复音数（轮转池）
## SFX 统一衰减。实测调出来的（见报告的 cap_*.wav）：不加这一档时 12 秒采集的全局峰值到 0.74 满量程，
## 多声叠加离削波只剩 2.6dB；-3dB 后回到约 0.5 满量程，留足余量。
const SFX_DB := -3.0

# ── 限流（秒，渲染时钟）─────────────────────────────────────────────────────
## 这几个数是**实测**定的，不是拍的：初版 ANY_MIN_S=0.07 在 12 秒采集里量到 41-54 次起音（约 4 次/秒）——
## 20 个居民 × 12.5 tick/秒，社交事件本来就密，不限流会变成持续的口哨声而不是"小镇的动静"。
const CUE_MIN_S := 0.30        # 同一类事件音的最小间隔
const ANY_MIN_S := 0.15        # 任意两声之间的最小间隔（上限约 6.7 声/秒）
const STEP_MIN_S := 0.21       # 脚步最小间隔（走另一条配额，见 play_cue 的 bypass_any）

## 稀有且最戏剧的事件（和解 / 选举 / 节日）走**更松的全局配额**。
## 这是量出来的、不是设计出来的：ANY_MIN_S=0.15 的那一版，40 秒 / 2000 tick 的采集里
## `warm` 响了 51 次而 `resolve` **一次都没有**——不是那 10 天没发生和解，
## 是和解被"打招呼"的洪流从全局配额里挤掉了。小镇最该被听见的恰恰是稀有的那几声。
const PRIO_CUES := {"resolve": true, "bell": true, "festive": true}
const PRIO_ANY_MIN_S := 0.03

## 事件类型 → 音效名。事件字典的形状见 `Sim._log_event()`：
##   {id, tick, type, actor, target, subject, accepted, witnesses, note}
## 两张表合起来覆盖 `Sim.gd` 里 22 个 `_log_event(` 调用点产出的**全部** type
## （含 `:1768`/`:1901` 那两处由 `action` 变量传入的社交动词）。
## 唯一故意留空的是 `world`（`:2395`/`:2406` 的 spawn/despawn）——节日开场已由 `day_changed` 单独报，
## 而每日清场是机械事件，不该有声音。
const CUE_BY_TYPE := {
	"greet": "warm", "give": "warm", "invite": "warm", "discuss": "warm",
	"aid": "warm", "endorse": "warm", "pay": "warm",
	"gossip": "whisper", "gossip_rep": "whisper", "confide": "whisper", "leak": "whisper",
	"conflict": "tense", "betray": "tense", "rally_oust": "tense",
	"election": "bell",
}
## 这几类"成则和解、败则紧张"，按 accepted 分叉。
const CUE_BY_ACCEPT := {
	"apologize": ["resolve", "tense"],
	"mediate": ["resolve", "tense"],
	"meet": ["resolve", "tense"],
	"pact": ["resolve", "tense"],
	"confront": ["tense", "tense"],
}

# ── 状态 ─────────────────────────────────────────────────────────────────────
var enabled := true            # 总闸（`--no-audio` 关闭；也可由 UI 层直接置）
var master_db := 0.0           # 全局增益偏移（叠加在每个 cue 上）
var log_cues := false          # `--audio-log`：每出一声打一行 + 退出前打分类计数（默认关，CI 里零输出）
var cue_tally := {}            # cue 名 → 已播放次数（诊断/断言用，永远统计，与 log_cues 无关）

var _sim: Node = null
var _bank := {}                            # cue 名 → AudioStreamWAV
var _voices: Array[AudioStreamPlayer] = []
var _vi := 0
var _bed_day: AudioStreamPlayer = null
var _bed_night: AudioStreamPlayer = null
var _clock := 0.0                          # 渲染时钟（_process delta 累加）
var _last_cue := {}                        # cue 名 → 上次播放的 _clock
var _last_any := -999.0
var _last_step := -999.0
var _bed_sync := -999.0                    # 上次刷新昼夜交叉淡入的 _clock
var _prev_pos := {}                        # agent id → Vector2i（推断"有人在走"）
var _sin := PackedFloat32Array()
var _rng_state := 20260726                 # 合成用的本地 LCG（只在 _ready 烘一次噪声，**不参与任何仿真**）

# ── 启动 ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-audio" in args:
		enabled = false
	if "--audio-log" in args:
		log_cues = true
	_build_sin_table()
	_build_bank()
	_build_players()
	# 只连 Sim 的信号；用 /root 查找而不是编译期 singleton，是为了让"autoload 顺序被人改了"
	# 只退化成"没有事件音"，而不是启动即崩。本 autoload 登记在 Sim 之后，正常路径必定找得到。
	_sim = get_node_or_null(^"/root/Sim")
	if _sim != null:
		_sim.social_event.connect(_on_social_event)
		_sim.day_changed.connect(_on_day_changed)
		_sim.ticked.connect(_on_ticked)
	_start_beds()
	_setup_audiocap(args)

## dev 钩子：`-- --audiocap <绝对路径.wav> <秒>`。
## 在 Master 总线上挂 `AudioEffectRecord`，到点存 WAV 并退出——headless 下唯一能拿到"真实混音输出"的路。
## 放在 Audio.gd 而不是 Main.gd：C2 不得改 Main.gd（docs/43 §三 文件所有权表）。
func _setup_audiocap(args: PackedStringArray) -> void:
	for i in args.size():
		if args[i] == "--audiocap" and i + 2 < args.size():
			var path := args[i + 1]
			var secs := maxf(0.5, float(args[i + 2]))
			var rec := AudioEffectRecord.new()
			AudioServer.add_bus_effect(0, rec)      # 0 = Master
			rec.set_recording_active(true)
			get_tree().create_timer(secs).timeout.connect(func() -> void:
				rec.set_recording_active(false)
				var smp: AudioStreamWAV = rec.get_recording()
				if smp != null:
					smp.save_to_wav(path)
				if log_cues:
					print("[audio] tally %s" % JSON.stringify(cue_tally))
				get_tree().quit())
			return

func _build_players() -> void:
	for i in range(SFX_VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)                                # 必须先入树再 play()，否则 "Playback can only happen when a node is inside the scene tree"
		_voices.append(p)
	_bed_day = AudioStreamPlayer.new()
	_bed_day.bus = &"Master"
	_bed_day.stream = _bank["bed_day"]
	_bed_day.volume_db = SILENT_DB
	add_child(_bed_day)
	_bed_night = AudioStreamPlayer.new()
	_bed_night.bus = &"Master"
	_bed_night.stream = _bank["bed_night"]
	_bed_night.volume_db = SILENT_DB
	add_child(_bed_night)

## 起底噪。写成幂等的（`play()` 前先查 `playing`），因为 `enabled` 是个**运行时**开关——
## 设置面板日后把它从 false 翻成 true 时，底噪必须跟着起来，而不是只有事件音能响。
func _start_beds() -> void:
	if not enabled:
		return
	if not _bed_day.playing:
		_bed_day.play()
	if not _bed_night.playing:
		_bed_night.play()
	_sync_beds()

# ── 每帧：渲染时钟 + 昼夜交叉淡入 ────────────────────────────────────────────
func _process(delta: float) -> void:
	_clock += delta
	if not enabled:
		if _bed_day.playing:                    # 刚被关掉：停底噪（事件音自己会因 enabled 短路）
			_bed_day.stop()
			_bed_night.stop()
		return
	if _clock - _bed_sync >= 0.1:               # 10Hz 足够平滑，省掉每帧写属性
		_bed_sync = _clock
		_start_beds()                           # 幂等：正常帧里就是一次 playing 判断
		_sync_beds()

## 昼夜两层底噪的交叉淡入。曲线**刻意对齐** `Main.gd:_daylight()` 的色停
## （夜 <0.24 / 天亮 0.24→0.38 / 白昼 0.38→0.68 / 入夜 0.68→0.86 / 夜 >0.86），
## 这样耳朵听到的"天黑了"和画面上的 `CanvasModulate` 是同一刻，而不是各走各的。
func _sync_beds() -> void:
	var w := 0.0
	if _sim != null:
		w = _day_weight(float(_sim.time_of_day()))
	_bed_day.volume_db = lerpf(SILENT_DB, BED_DAY_DB + master_db, w)
	_bed_night.volume_db = lerpf(SILENT_DB, BED_NIGHT_DB + master_db, 1.0 - w)

func _day_weight(tod: float) -> float:
	if tod < 0.24 or tod >= 0.86:
		return 0.0
	if tod < 0.38:
		return (tod - 0.24) / 0.14
	if tod < 0.68:
		return 1.0
	return 1.0 - (tod - 0.68) / 0.18

# ── Sim 信号（只读 Sim）─────────────────────────────────────────────────────
func _on_social_event(e: Dictionary) -> void:
	if not enabled:
		return
	var cue := _cue_for(e)
	if cue != "":
		play_cue(cue)

func _on_day_changed(_d: int) -> void:
	if not enabled or _sim == null:
		return
	if String(_sim.festival_active) != "":       # 节日开场（Sim.gd:_update_festival 在日界置位）
		play_cue("festive", 2.0)

## 脚步：Sim 没有"移动"信号，所以按 tick 比对 agents 的格位。
## **先查限流再扫描**是刻意的：`goto_tick()` 暖机 / `m2_test` 这类同步 tick 循环会在一帧里跑几千 tick，
## 渲染时钟不前进 ⇒ 第一次之后全部 O(1) 直接返回，整段回放的代价接近零。
func _on_ticked(_t: int) -> void:
	if not enabled or _sim == null:
		return
	if _clock - _last_step < STEP_MIN_S:
		return
	var moved := 0
	for ag in _sim.agents:
		var id = ag["id"]
		var p = ag["pos"]
		if _prev_pos.get(id, p) != p:
			moved += 1
		_prev_pos[id] = p
	if moved <= 0:
		return
	_last_step = _clock
	# 走的人越多脚步越实（封顶 +4dB），但仍然只出一声——不是每人一声
	play_cue("step", minf(4.0, float(moved) * 0.7), true)

func _cue_for(e: Dictionary) -> String:
	var t := String(e.get("type", ""))
	if CUE_BY_ACCEPT.has(t):
		var pair: Array = CUE_BY_ACCEPT[t]
		return String(pair[0]) if bool(e.get("accepted", false)) else String(pair[1])
	return String(CUE_BY_TYPE.get(t, ""))

# ── 输入：UI 点击/触屏反馈 ───────────────────────────────────────────────────
## 挂在 autoload 的 `_input` 上，因此**不需要改任何 UI 代码**就能给全部按钮/点触加反馈。
## 只观察、**绝不** `set_input_as_handled()`——不吃掉任何一个事件。滚轮不出声（否则缩放会变成机关枪）。
func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			play_ui_click()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index <= MOUSE_BUTTON_MIDDLE:
			play_ui_click()

# ── 对外 API ────────────────────────────────────────────────────────────────
func play_ui_click() -> void:
	play_cue("click")

## 播一个音效。`bypass_any` 让脚步不占用"任意两声"的全局配额（脚步有自己的节奏）。
func play_cue(cue: String, gain_db := 0.0, bypass_any := false) -> void:
	if not enabled or not _bank.has(cue):
		return
	var any_gate := PRIO_ANY_MIN_S if PRIO_CUES.has(cue) else ANY_MIN_S
	if not bypass_any and _clock - _last_any < any_gate:
		return
	if _clock - float(_last_cue.get(cue, -999.0)) < CUE_MIN_S:
		return
	_last_cue[cue] = _clock
	if not bypass_any:
		_last_any = _clock
	cue_tally[cue] = int(cue_tally.get(cue, 0)) + 1
	if log_cues:
		print("[audio] %7.2fs  %s" % [_clock, cue])
	var p := _voices[_vi]
	_vi = (_vi + 1) % _voices.size()
	p.stream = _bank[cue]
	p.volume_db = SFX_DB + gain_db + master_db
	p.play()

# ── 合成 ─────────────────────────────────────────────────────────────────────
func _build_sin_table() -> void:
	_sin.resize(TBL + 1)                        # 末尾多一格，线性插值不必回绕取模
	for i in range(TBL + 1):
		_sin[i] = sin(TAU * float(i) / float(TBL))

## 查表正弦。入参是**圈数**（turns），不是弧度——量子化无缝循环的推导直接用圈数最省事。
func _tsin(turns: float) -> float:
	var x := fposmod(turns, 1.0) * float(TBL)
	var i := int(x)
	var f := x - float(i)
	return _sin[i] + (_sin[i + 1] - _sin[i]) * f

## 本地 LCG：只在 `_ready()` 烘噪声用。**与仿真无关**——不进 `Sim`，不影响任何 digest。
## 红线#1 管的是"仿真侧的随机"；这里刻意不用 `randi()/randf()`，就是为了在 grep 层面也和仿真 RNG 划清界限。
func _lcg() -> float:
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_rng_state) / 1073741823.5 - 1.0     # → [-1, 1)

## AD 包络：atk 秒线性起，其后指数衰减（沿用技能 gen_audio.py 的 env_ad）。
func _env(n: int, rate: int, atk: float) -> PackedFloat32Array:
	var e := PackedFloat32Array()
	e.resize(n)
	var a := maxi(1, int(atk * float(rate)))
	for i in range(n):
		if i < a:
			e[i] = float(i) / float(a)
		else:
			e[i] = exp(-3.0 * float(i - a) / float(maxi(1, n - a)))
	return e

## 加性合成的一个音（沿用技能 gen_audio.py 的 tone：基频 + 分音表 + 可选颤音）。
func _tone(freq: float, dur: float, vol: float, atk: float, partials: Array, vib := 0.0) -> PackedFloat32Array:
	var n := int(dur * float(SR_SFX))
	var e := _env(n, SR_SFX, atk)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(SR_SFX)
		var f := freq * (1.0 + vib * sin(TAU * 5.5 * t))
		var s := 0.0
		for k in range(partials.size()):
			s += float(partials[k]) * sin(TAU * f * float(k + 1) * t)
		out[i] = s * e[i] * vol
	return out

## 带通感的噪声爆（脚步/耳语用）：LCG 噪声 → 一阶低通 → 一阶高通 → AD 包络。
func _noise(dur: float, vol: float, atk: float, lp: float, hp: float) -> PackedFloat32Array:
	var n := int(dur * float(SR_SFX))
	var e := _env(n, SR_SFX, atk)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 0.0
	var prev_lo := 0.0
	var hi := 0.0
	for i in range(n):
		lo = lo + lp * (_lcg() - lo)                # 一阶低通
		hi = (1.0 - hp) * (hi + lo - prev_lo)       # 一阶高通
		prev_lo = lo
		out[i] = hi * e[i] * vol
	return out

## 把若干 (起始秒, 采样) 叠成一段（沿用技能 gen_audio.py 的 seq）。
func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for pr in parts:
		n = maxi(n, int(float(pr[0]) * float(SR_SFX)) + (pr[1] as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(n)
	for pr in parts:
		var off := int(float(pr[0]) * float(SR_SFX))
		var sm: PackedFloat32Array = pr[1]
		for i in range(sm.size()):
			out[off + i] += sm[i]
	return out

## 持续底噪。**与技能配方的关键差异**：不靠"两端淡到静音"求无缝，而是把每个分音的频率
## 量子化到 `1/secs` 的整数倍——一圈刚好走整数个周期，接缝处相位天然连续，
## 于是底噪可以真正**持续**（原配方每 20 秒会有一次可听的呼吸，用作"海浪"没问题，
## 用作"小镇一直在那儿"的底噪就不行了）。
func _bed(voices: Array, secs: float, amp: float, lfo_hz: float, lfo_depth: float) -> AudioStreamWAV:
	var n := int(secs * float(SR_BED))
	var q := 1.0 / secs                              # 频率量子
	var lfo := roundf(lfo_hz / q) * q            # roundf 而非 round：round() 返回 Variant，`:=` 推不出类型（技能 gotcha #1）
	var norm := 0.0
	for v in voices:
		norm += float(v[1])
	norm = maxf(0.001, norm)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / float(SR_BED)
		var s := 0.0
		for v in voices:
			var f: float = roundf(float(v[0]) / q) * q
			s += float(v[1]) * _tsin(f * t)
		var m := 1.0 - lfo_depth + lfo_depth * (0.5 + 0.5 * _tsin(lfo * t))
		buf[i] = s / norm * amp * m
	return _wav(buf, SR_BED, true)

## float[-1,1] → 16bit PCM 的 AudioStreamWAV（内存里建，**不落任何文件**）。
func _wav(buf: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w

const N := {
	"E2": 82.41, "A2": 110.00, "B2": 123.47, "C3": 130.81, "E3": 164.81, "G3": 196.00,
	"A3": 220.00, "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00,
	"B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "C6": 1046.50,
}

func _build_bank() -> void:
	# ── 两层环境底噪 ──
	# 白昼：A 大三和弦的开放排列，明亮、有呼吸；夜晚：E 小、更低更暗、呼吸更慢。
	_bank["bed_day"] = _bed([
		[N["A2"], 1.00], [N["E3"], 0.55], [N["A3"], 0.40], [N["C5"] / 2.0, 0.22], [N["E4"], 0.14],
	], BED_SECS, 0.55, 0.5, 0.28)
	_bank["bed_night"] = _bed([
		[N["E2"], 1.00], [N["B2"], 0.48], [N["E3"], 0.32], [N["G3"], 0.20],
	], BED_SECS, 0.50, 0.25, 0.34)

	# ── UI 点击：极短软点 ──
	_bank["click"] = _wav(_tone(660.0, 0.05, 0.30, 0.002, [1.0, 0.2]), SR_SFX, false)

	# ── 脚步：低频闷响 + 一小撮沙沙 ──
	_bank["step"] = _wav(_mix([
		[0.0, _tone(96.0, 0.085, 0.30, 0.001, [1.0, 0.35])],
		[0.0, _noise(0.075, 0.10, 0.001, 0.45, 0.55)],
	]), SR_SFX, false)

	# ── 事件音 ──
	# warm：打招呼/送礼/邀约/互助——两个上行的软音
	_bank["warm"] = _wav(_mix([
		[0.00, _tone(N["A4"], 0.16, 0.26, 0.004, [1.0, 0.35, 0.12])],
		[0.07, _tone(N["E5"], 0.20, 0.24, 0.004, [1.0, 0.35, 0.12])],
	]), SR_SFX, false)
	# whisper：说闲话/吐露/泄密——气声为主，只有一点点音高，听得出"在嘀咕"但不抢戏
	_bank["whisper"] = _wav(_mix([
		[0.00, _noise(0.22, 0.16, 0.02, 0.28, 0.72)],
		[0.03, _tone(1180.0, 0.10, 0.05, 0.02, [1.0])],
	]), SR_SFX, false)
	# tense：结怨/背叛/对质失败——低音小二度打架 + 轻微颤音
	_bank["tense"] = _wav(_mix([
		[0.00, _tone(98.00, 0.38, 0.26, 0.006, [1.0, 0.5, 0.28], 0.012)],
		[0.00, _tone(103.83, 0.38, 0.22, 0.006, [1.0, 0.4, 0.2], 0.012)],
		[0.02, _tone(207.65, 0.26, 0.10, 0.006, [1.0, 0.3])],
	]), SR_SFX, false)
	# resolve：道歉被接受/说和成功/赴约/结盟——C-E-G 上行，干净收束
	_bank["resolve"] = _wav(_mix([
		[0.00, _tone(N["C5"], 0.24, 0.22, 0.004, [1.0, 0.35])],
		[0.08, _tone(N["E5"], 0.24, 0.22, 0.004, [1.0, 0.35])],
		[0.16, _tone(N["G5"], 0.34, 0.22, 0.004, [1.0, 0.35])],
	]), SR_SFX, false)
	# bell：选举出结果——一记带泛音的钟
	_bank["bell"] = _wav(_mix([
		[0.00, _tone(N["G4"], 0.85, 0.20, 0.004, [1.0, 0.6, 0.3, 0.18], 0.006)],
		[0.00, _tone(N["D5"], 0.70, 0.11, 0.004, [1.0, 0.4, 0.2])],
		[0.10, _tone(N["B4"], 0.60, 0.09, 0.004, [1.0, 0.4])],
	]), SR_SFX, false)
	# festive：节日开场——四音上行小号角
	_bank["festive"] = _wav(_mix([
		[0.00, _tone(N["C5"], 0.40, 0.20, 0.004, [1.0, 0.5, 0.25], 0.010)],
		[0.13, _tone(N["E5"], 0.40, 0.20, 0.004, [1.0, 0.5, 0.25], 0.010)],
		[0.26, _tone(N["G5"], 0.40, 0.20, 0.004, [1.0, 0.5, 0.25], 0.010)],
		[0.39, _tone(N["C6"], 0.75, 0.22, 0.004, [1.0, 0.5, 0.3, 0.15], 0.018)],
	]), SR_SFX, false)
