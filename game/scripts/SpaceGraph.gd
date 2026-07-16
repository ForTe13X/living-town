extends RefCounted
## SpaceGraph — P1 空间合同（analysis §5.1）：Space / Floor / SpatialAddress / Portal 的读取、查询与校验。
##
## 定位：**纯数据 + 纯查询**。不写 Sim、不进 digest、不抽 RNG。
##   - Probe 用它拿 active Space 的 bounds（相机边界不再直读 Sim.GRID —— analysis §11 的批评）。
##   - 兼容层 address_of()：agent 没有 spatial_address 时兜底成 town/outdoor + agent.pos
##     → 现有 24x16 内容一行不改就能跑，digest 逐字节不变（analysis §5.3 渐进迁移）。
##   - Portal 是【角色】跨 Space/Floor 的唯一合法通道（P3 才接导航）；Probe 可以直接 inspect，两者严格分离。
##
## 缺 data/spaces.json → spaces 为空 → address_of 仍兜底 town/outdoor、bounds 回落 Sim.GRID（off 门：零扰动）。

const TILE := 48

var spaces := {}          # id -> {kind,label,bounds:[x,y,w,h],floors:[],default_floor}
var portals := []         # [{id,kind,from:{space,floor,pos},to:{...},bidirectional,access,traversal_cost}]
var loaded := false

func load_from(path := "res://data/spaces.json") -> void:
	loaded = false
	spaces = {}
	portals = []
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return
	var dd: Dictionary = d
	if dd.get("spaces") is Dictionary:
		for sid in dd["spaces"]:
			if dd["spaces"][sid] is Dictionary:
				spaces[String(sid)] = dd["spaces"][sid]
	if dd.get("portals") is Array:
		for p in dd["portals"]:
			if p is Dictionary:
				portals.append(p)
	loaded = true

# ── 查询 ────────────────────────────────────────────────────────────────────
func has_space(sid: String) -> bool:
	return spaces.has(sid)

func has_floor(sid: String, fid: String) -> bool:
	if not spaces.has(sid):
		return false
	return fid in (spaces[sid].get("floors", []) as Array)

func floors_of(sid: String) -> Array:
	return (spaces.get(sid, {}) as Dictionary).get("floors", []) as Array

func default_floor(sid: String) -> String:
	var sp: Dictionary = spaces.get(sid, {})
	var fl: Array = sp.get("floors", [])
	return String(sp.get("default_floor", fl[0] if not fl.is_empty() else "outdoor"))

func label_of(sid: String) -> String:
	return String((spaces.get(sid, {}) as Dictionary).get("label", sid))

## Space 的世界像素边界。缺 space（或没加载）→ 回落 Sim.GRID 全图（兼容期行为不变）。
func bounds_px(sid: String) -> Rect2:
	var sp: Dictionary = spaces.get(sid, {})
	var b: Array = sp.get("bounds", [])
	if b.size() == 4:
		return Rect2(float(b[0]) * TILE, float(b[1]) * TILE, float(b[2]) * TILE, float(b[3]) * TILE)
	return Rect2(0, 0, float(Sim.GRID.x) * TILE, float(Sim.GRID.y) * TILE)

## 从某个 (space,floor) 出发的 Portal（含双向的反向边）。P3 导航用；本阶段先给查询与校验。
func portals_from(sid: String, fid: String) -> Array:
	var out := []
	for p in portals:
		var fr: Dictionary = p.get("from", {})
		var to: Dictionary = p.get("to", {})
		if String(fr.get("space", "")) == sid and String(fr.get("floor", "")) == fid:
			out.append({"id": p.get("id", ""), "kind": p.get("kind", ""), "to": to,
				"access": p.get("access", "public"), "cost": int(p.get("traversal_cost", 1))})
		elif bool(p.get("bidirectional", false)) and String(to.get("space", "")) == sid \
				and String(to.get("floor", "")) == fid:
			out.append({"id": p.get("id", ""), "kind": p.get("kind", ""), "to": fr,
				"access": p.get("access", "public"), "cost": int(p.get("traversal_cost", 1))})
	return out

# ── 兼容层（analysis §5.3）：不改 agent.pos，也不改 Sim ─────────────────────
## agent → SpatialAddress。带 spatial_address 就用它；否则兜底 town/outdoor + agent.pos。
## 这样"第一栋多层建筑"可以单独长出 spatial_address，而其余居民一行不动 → digest drift 可控。
func address_of(agent: Dictionary) -> Dictionary:
	var sa: Variant = agent.get("spatial_address")
	if sa is Dictionary and (sa as Dictionary).has("space_id"):
		var d: Dictionary = sa
		return {"space_id": String(d.get("space_id", "town")), "floor_id": String(d.get("floor_id", "outdoor")),
			"position": d.get("position", agent.get("pos", Vector2i.ZERO)), "room_id": String(d.get("room_id", ""))}
	return {"space_id": "town", "floor_id": "outdoor", "position": agent.get("pos", Vector2i.ZERO), "room_id": ""}

# ── 校验（P1 Gate：无悬挂 Portal 引用）───────────────────────────────────────
## 返回错误列表（空=通过）。CI 由 tools/lint_data.py 跑同源检查，这里供运行期/测试用。
func validate() -> Array:
	var errs := []
	for sid in spaces:
		var sp: Dictionary = spaces[sid]
		var b: Array = sp.get("bounds", [])
		if b.size() != 4 or int(b[2]) <= 0 or int(b[3]) <= 0:
			errs.append("space '%s': bounds 必须是 [x,y,w,h] 且 w/h>0" % sid)
		var fl: Array = sp.get("floors", [])
		if fl.is_empty():
			errs.append("space '%s': floors 不能为空" % sid)
		if sp.has("default_floor") and not (String(sp["default_floor"]) in fl):
			errs.append("space '%s': default_floor '%s' 不在 floors 里" % [sid, sp["default_floor"]])
	var seen := {}
	for p in portals:
		var pid := String(p.get("id", ""))
		if pid == "":
			errs.append("portal 缺 id")
			continue
		if seen.has(pid):
			errs.append("portal id 重复: '%s'" % pid)
		seen[pid] = true
		for side in ["from", "to"]:
			var e: Dictionary = p.get(side, {})
			var sid := String(e.get("space", ""))
			var fid := String(e.get("floor", ""))
			if not has_space(sid):
				errs.append("portal '%s'.%s: 未知 space '%s'" % [pid, side, sid])
			elif not has_floor(sid, fid):
				errs.append("portal '%s'.%s: space '%s' 没有 floor '%s'" % [pid, side, sid, fid])
			var pos: Array = e.get("pos", [])
			if pos.size() != 2:
				errs.append("portal '%s'.%s: pos 必须是 [x,y]" % [pid, side])
	return errs
