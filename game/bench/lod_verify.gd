extends SceneTree
## bench/lod_verify.gd — 观察无关 aggregate LOD 的红线验证（V2 相机路径无关 + V3 确定性/存读/fresh-vs-restart）。
## 用法：godot --headless --path . --script res://bench/lod_verify.gd -- [N] [days]
##   全程 lod_aggregate=true。摘要 = [Inv.digest(S), S.event_digest] 双见证。任一 FAIL → quit(1)。
## 纪律：backend=null 走确定性 logic；不加载 autoload → preload 实例化。
const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _N := 100
var _days := 4
var _fails: Array = []

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _N = int(a[0])
	if a.size() > 1: _days = int(a[1])
	print("=== LOD 观察无关红线验证  N=%d days=%d  (lod_aggregate=true) ===" % [_N, _days])

	# ── V2：相机路径无关（证明历史不依赖 lod_focus）──
	# 用四种 lod_focus（含被擦除的 (-1,-1)）跑同一 seed，摘要必须完全一致 → viewer-independence。
	var base := _run(7, _days, Vector2i(12, 8))         # 默认焦点
	var foci := [Vector2i(1, 1), Vector2i(30, 20), Vector2i(-1, -1), Vector2i(999, 999)]
	var v2_ok := true
	for f in foci:
		var r := _run(7, _days, f)
		if r != base:
			v2_ok = false
			print("  V2 ✗ lod_focus=%s 摘要 %s ≠ 基准 %s" % [str(f), str(r), str(base)])
	_report("V2 相机路径无关（观察无关）", v2_ok)

	# ── V3a：同 seed 两跑摘要一致（确定性）──
	var d1 := _run(11, _days, Vector2i(5, 5))
	var d2 := _run(11, _days, Vector2i(5, 5))
	_report("V3a 同 seed 确定性", d1 == d2)

	# ── V3b：中途存档→读档→续跑 == 不存档直跑 ──
	var straight := _run(13, _days, Vector2i(12, 8))
	var split := _run_saveload(13, _days, Vector2i(12, 8))
	_report("V3b 存档/读档 == 直跑", straight == split)

	# ── V3c：fresh 实例 vs 复用实例 restart（测 start_new 全重置，含 cohort 缓存）──
	var fresh := _run(17, _days, Vector2i(12, 8))
	var restart := _run_restart(17, _days, Vector2i(12, 8))
	_report("V3c fresh == restart", fresh == restart)

	print("")
	if _fails.is_empty():
		print("=== LOD-VERIFY GATE: ✅ PASS  (V2+V3abc 全绿) ===")
		quit(0)
	else:
		print("=== LOD-VERIFY GATE: ❌ FAIL  失败项=%s ===" % str(_fails))
		quit(1)

## 建一个配好的 Sim（lod_aggregate=true），可选设 lod_focus。
func _mk(focus: Vector2i) -> Object:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.spawn_count = _N
	S.lod_aggregate = true
	S.decide_period = 4
	if focus.x >= -1 or focus.y >= -1:
		S.lod_focus = focus     # 观察无关档下这【应该毫无影响】——V2 正是验证这点
	return S

func _digest(S: Object) -> Array:
	return [int(Inv.digest(S)), int(S.event_digest)]

## 直跑 days 天，返回摘要。
func _run(seed: int, days: int, focus: Vector2i) -> Array:
	var S := _mk(focus)
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	for t in range(total): S.tick()
	var d := _digest(S)
	S.free()
	return d

## 跑一半 → 存档 → 读进【全新实例】→ 续跑另一半 → 摘要。
func _run_saveload(seed: int, days: int, focus: Vector2i) -> Array:
	var S := _mk(focus)
	S.start_new(seed)
	var total: int = days * int(S.TICKS_PER_DAY)
	var half: int = total / 2
	for t in range(half): S.tick()
	var path := "user://lod_verify_save.dat"
	var ok: bool = S.save_game(path)
	S.free()
	if not ok:
		print("  V3b ✗ save_game 失败"); return [-1, -1]
	var S2 := _mk(focus)          # 全新实例（配置同，但状态从档还原）
	if not S2.load_game(path):
		print("  V3b ✗ load_game 失败"); S2.free(); return [-2, -2]
	for t in range(total - half): S2.tick()
	var d := _digest(S2)
	S2.free()
	return d

## 复用同一实例：先跑一个【别的】seed 弄脏它，再 start_new(seed) 重来 → 摘要应等于 fresh。
func _run_restart(seed: int, days: int, focus: Vector2i) -> Array:
	var S := _mk(focus)
	S.start_new(seed + 99)               # 弄脏：先跑别的 seed
	for t in range(days * int(S.TICKS_PER_DAY)): S.tick()
	S.start_new(seed)                    # restart 到目标 seed（须全重置，含 _near_set/_commit_ids/...）
	var total: int = days * int(S.TICKS_PER_DAY)
	for t in range(total): S.tick()
	var d := _digest(S)
	S.free()
	return d

func _report(name: String, ok: bool) -> void:
	print("  %s  %s" % ["✅" if ok else "❌", name])
	if not ok: _fails.append(name)
