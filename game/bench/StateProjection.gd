extends RefCounted
## StateProjection.gd — AO1 · state_projection_v1（docs/137）
##
## 权威状态投影：从 **save codec 落盘的 blob** 抽一个 canonical / versioned / hashable 的状态指纹，
## 覆盖 `save_game` 反射保存的【全部权威字段】（world script-var + 每 agent 字典，memory 用 save 的序列化形）。
##
## ★单一真相源（docs/121 §三.3 / Codex §三.11）：本模块折的就是 `Sim.save_game` 落盘的那一坨——
##   成员集 == `blob["state"]`。**不重新声明** DERIVED/BENCH_ONLY/VIEW_PARAMS、**不重实现反射**
##   （那会与 save_game 悄悄漂：AC1 点名的"分母耦合"）。派生缓存的排除【继承自 save_game】，本模块零重复。
## ★与 `Inv.digest`/`chain_step` 【并行、解耦】（docs/121 路 b）：本函数是**新函数**，不进 S0 比对的四个量
##   （digest/event_digest/chain/events），不烘金标 ⇒ 金标零影响。除非有人蓄意为它新增一份锚（用户旋钮）。
## ★确定性（红线#1）：字段序固定 = **dict 键按 [typeof,str] 规范序**（与插入序无关 → 冷热镇/跨机等价）；
##   float 折 8 字节 IEEE-754（-0.0/NaN/Inf 归一）→ 无浮点歧义；无 RNG、无 Time、无 String.hash()。
## ★性能（docs/121 §五）：只在 checkpoint/存读档【边界】按需算，**不每 tick**。折一次成本见 state_projection_gate。
##
## 用法：
##   var pr := StateProjection.project_sim(S)          # S 存盘→读回→规范折 ⇒ {hash, version}
##   var pr := StateProjection.project_file(path)       # 折一个已存在的存档文件
##   var pr := StateProjection.project_blob(blob)        # 折一个已解码的 blob（纯折叠，无 I/O，测折叠成本用）

const PROJECTION_VERSION := 1

# 与 Sim 同族 FNV-1a/32（金标的每个数字都由本仓库源码定义，不用引擎 String.hash()；红线#1）。
const OFF := 2166136261       # = Sim.HASH_OFFSET32
const PRIME := 16777619       # = Sim.HASH_PRIME32
const MASK := 0xFFFFFFFF      # = Sim.HASH_MASK32

# 类型标签（ASCII，前缀无歧义：不同类型即使 str 相同也折不同）。
const TAG_NIL := "tn"
const TAG_BOOL_T := "tb1"
const TAG_BOOL_F := "tb0"
const TAG_INT := "ti"
const TAG_FLOAT := "tf"
const TAG_STR := "ts"
const TAG_V2I := "tvi"
const TAG_V2F := "tvf"
const TAG_ARR := "ta"
const TAG_DICT := "td"
const TAG_OBJ := "tobj"

# ── 底层 FNV 折叠原语（字节级，规范）──────────────────────────────────────────
static func _fb(h: int, b: PackedByteArray) -> int:
	var x := h
	for i in b.size():
		x = ((x ^ b[i]) * PRIME) & MASK
	return x

static func _fs(h: int, s: String) -> int:
	return _fb(h, s.to_utf8_buffer())

static func _fi(h: int, v: int) -> int:
	var b := PackedByteArray(); b.resize(8); b.encode_s64(0, v)   # 8 字节小端，确定
	return _fb(h, b)

static func _ff(h: int, f: float) -> int:
	# float 归一：把 NaN / ±Inf / -0.0 折成稳定 token，其余折 8 字节 IEEE-754 → 位精确、无歧义。
	if is_nan(f):
		return _fs(h, "fNaN")
	if is_inf(f):
		return _fs(h, "fInfNeg" if f < 0.0 else "fInfPos")
	if f == 0.0:
		f = 0.0   # -0.0 == 0.0 为真 → 赋 +0.0，消除 -0.0/+0.0 位差
	var b := PackedByteArray(); b.resize(8); b.encode_double(0, f)
	return _fb(h, b)

# ── dict 规范序：按 [typeof(key), str(key)] 升序，与插入序无关（红线#1 cross-history 命门）──
## 无 sort_custom lambda（静态上下文无 self）：映射到可排序字符串再默认排序。
static func _sorted_keys(d: Dictionary) -> Array:
	var back := {}    # sortstr -> 原 key
	var arr: Array = []
	for k in d.keys():
		var s := "%02d|%s" % [typeof(k), str(k)]   # 类型前缀 → int 1 与 string "1" 不同序
		back[s] = k
		arr.append(s)
	arr.sort()        # 默认字典序（codepoint），确定
	var out: Array = []
	for s in arr:
		out.append(back[s])
	return out

# ── 递归规范折叠（类型标签前缀 → 类型不混；长度前缀 → 拼接无歧义）──────────────
static func fold(h: int, v) -> int:
	var t := typeof(v)
	match t:
		TYPE_NIL:
			return _fs(h, TAG_NIL)
		TYPE_BOOL:
			return _fs(h, TAG_BOOL_T if v else TAG_BOOL_F)
		TYPE_INT:
			return _fi(_fs(h, TAG_INT), int(v))
		TYPE_FLOAT:
			return _ff(_fs(h, TAG_FLOAT), float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(v)
			var hh := _fs(h, TAG_STR)
			var bytes := s.to_utf8_buffer()
			hh = _fi(hh, bytes.size())     # 长度前缀
			return _fb(hh, bytes)
		TYPE_VECTOR2I:
			var vi: Vector2i = v
			return _fi(_fi(_fs(h, TAG_V2I), vi.x), vi.y)
		TYPE_VECTOR2:
			var vf: Vector2 = v
			return _ff(_ff(_fs(h, TAG_V2F), vf.x), vf.y)
		TYPE_ARRAY:
			var a: Array = v
			var hh := _fi(_fs(h, TAG_ARR), a.size())
			for e in a:
				hh = fold(hh, e)
			return hh
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var hh := _fi(_fs(h, TAG_DICT), d.size())
			for k in _sorted_keys(d):
				hh = fold(hh, k)      # 折 key（带类型标签）
				hh = fold(hh, d[k])   # 折 value
			return hh
		TYPE_OBJECT:
			# 不该出现：save_game 已 fail-closed 拒绝残留 Object（memory 已序列化成 __mem_items__）。
			# 折稳定 token 兜底、不崩，若真出现则投影会指向它（不静默吞）。
			return _fs(h, TAG_OBJ)
		_:
			# 兜底：其它标量/Packed 类型（Color/PackedInt.../Vector3…）走 var_to_bytes，确定但粗。
			return _fb(_fs(h, "tz%d" % t), var_to_bytes(v))

# ── 非权威注入句柄：从投影 & 覆盖分母里一律剔除（红线#1 跨机/冷热等价）───────────
## backend/ext 是运行时注入的服务 Object 句柄（AI 后端，`Sim.gd:407/410`）。它们**不是权威持久态**：
##   load 时重新接线、不从存档还原。可 GDScript `null is Object == false`：headless 存盘时它们是 null，
##   `save_game` 的 `if v is Object` 跳不掉 → 键 `backend:null/ext:null` 落进 blob.state；真机注入了
##   AIBackend Object 时 `v is Object == true` → 整个键消失。同一权威态却两套键集 → 两个投影哈希，
##   直接违反本模块卖点"冷热镇/跨机等价"。⇒ 在此**统一剔除顶层这两个键**，投影与注入态无关。
##   （AO1 原实现漏了这条：把 headless 的 backend:null 也折了进去。审查 F1 收口。）
## Spatial config snapshots remain in the schema-2 envelope for exact compatibility checks, but
## they are not mutable Sim authority anymore: save_game always rewrites them from receiver-owned
## authored data and runtime traversal/nav never reads the restored copies.  Counting them in the
## projection mutation denominator would therefore create a deliberate false hole (mutating the
## live compatibility copy is correctly erased by the writer).  Strip them at the same boundary
## as runtime handles; graph drift is guarded by Sim's exact current-schema validator instead.
const NONAUTH_STATE_KEYS := ["backend", "ext", "_spaces", "_portals", "_interiors_data"]

## 权威 state：剥掉顶层非权威注入句柄。只动顶层键（浅拷 + erase），不递归污染同名嵌套键。
static func _auth_state(blob: Dictionary) -> Dictionary:
	var raw = blob.get("state", {})
	if not (raw is Dictionary):
		return {}
	var st: Dictionary = (raw as Dictionary).duplicate()   # 浅拷：只为剥顶层键，值只读
	for k in NONAUTH_STATE_KEYS:
		st.erase(k)
	return st

# ── 顶层入口 ─────────────────────────────────────────────────────────────────
## 折一个已解码的存档 blob（无文件 I/O；测【纯折叠成本】用）。
## 折的范围 = 存档权威面里【决定 sim 状态等价】的部分：state（全反射面，剥非权威注入句柄）+ 影响恢复的
##   header（schema/seed/active_commit_ids）。**不折 meta**（玩家给的存档名，非 sim 状态——改档名不该改投影）。
static func project_blob(blob: Dictionary) -> Dictionary:
	var h := OFF
	h = _fi(_fs(h, "ver"), PROJECTION_VERSION)   # 版本入指纹 → 换折叠算法即换指纹族
	h = _fi(_fs(h, "schema"), int(blob.get("schema", -1)))
	h = _fi(_fs(h, "seed"), int(blob.get("seed", -1)))
	h = fold(_fs(h, "acids"), blob.get("active_commit_ids", []))
	h = fold(_fs(h, "state"), _auth_state(blob))   # F1：剥 backend/ext，键集与注入态无关
	return {"hash": h & MASK, "version": PROJECTION_VERSION}

## 折一个已存在的存档文件（读法与 load_game 同源：先跳 4 字节 schema 头，再 get_var）。
static func project_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"hash": 0, "version": PROJECTION_VERSION, "error": "no file"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 8:
		return {"hash": 0, "version": PROJECTION_VERSION, "error": "cannot open"}
	f.get_32()               # 4 字节 schema 头（与 load_game 同）
	var blob = f.get_var()
	f.close()
	if not (blob is Dictionary):
		return {"hash": 0, "version": PROJECTION_VERSION, "error": "bad blob"}
	return project_blob(blob)

## 折一个活 Sim：走 save_game 落盘 → 读回 → 折。这是【单一真相源】的兑现——
## 折的就是 save_game 落的字节，成员集与存档权威面逐字一致。边界调用，不每 tick。
static func project_sim(S, tmp_path := "user://__ao1_proj_tmp.dat") -> Dictionary:
	if not S.save_game(tmp_path):
		return {"hash": 0, "version": PROJECTION_VERSION, "error": "save_game refused"}
	var r := project_file(tmp_path)
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	return r

# ── 覆盖清单（gate 的覆盖报告用）：从 blob 列出 world + agent 字段名 ──────────────
static func manifest(blob: Dictionary) -> Dictionary:
	var state: Dictionary = blob.get("state", {})
	var world_fields: Array = []
	for k in state.keys():
		if str(k) == "agents":
			continue
		if str(k) in NONAUTH_STATE_KEYS:
			continue   # F1：非权威注入句柄，不进覆盖分母（否则 world_count 随 headless/真机注入态漂移）
		world_fields.append(str(k))
	world_fields.sort()
	var agent_fields: Array = []
	var ags: Array = state.get("agents", [])
	if ags.size() > 0 and ags[0] is Dictionary:
		for k in (ags[0] as Dictionary).keys():
			agent_fields.append(str(k))
		agent_fields.sort()
	return {
		"world_fields": world_fields,
		"world_count": world_fields.size(),
		"agent_count": ags.size(),
		"agent_fields": agent_fields,
		"agent_field_count": agent_fields.size(),
	}
