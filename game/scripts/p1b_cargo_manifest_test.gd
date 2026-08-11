extends Node
## P1-b CargoManifest 合同门：无 cargo 不能卸货；整单 cargo 的钱/货/cargo/工资按固定顺序同步提交。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _fails := 0

func ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
	print(("  OK   " if ok else "  FAIL ") + msg)

func _unload_adv(S) -> Dictionary:
	var port: Dictionary = S.world.get("objects", {}).get("port_dock", {})
	for adv in port.get("advertises", []):
		if adv is Dictionary and String(adv.get("action", "")) == "卸货":
			return adv
	return {}

func _install_use_option(worker: Dictionary, manifest_id: String = "") -> void:
	worker["option"] = {
		"kind": "object", "action": "卸货", "target": "port_dock", "need": "fun",
		"amount": 46, "dur_total": 28, "remaining": 1, "phase": "use",
	}
	if manifest_id != "":
		worker["option"]["manifest_node"] = "port_dock"
		worker["option"]["manifest_id"] = manifest_id

## manifest_id 为空时故意模拟旧存档/强制 option；完成门必须从 advert 恢复合同且仍 fail-closed。
func _force_complete(S, worker: Dictionary, manifest_id: String = "") -> void:
	_install_use_option(worker, manifest_id)
	S._advance_object(worker, worker["option"])

func _probe_blocked_use(S, worker: Dictionary, manifest_id: String, label: String) -> void:
	var stock0: Dictionary = S.town_stock.duplicate(true)
	var town0 := int(S.town_coin)
	var external0 := int(S.external_coin)
	var needs0: Dictionary = worker["needs"].duplicate(true)
	var skills0: Dictionary = (worker.get("skills", {}) as Dictionary).duplicate(true)
	var mem0 := int(worker["memory"].items.size())
	var wages0 := int(S.econ_stats.get("wages_paid", 0))
	var ev0 := int(S.event_log.size())
	var manifest0: Dictionary = (S.cargo_manifests.get(manifest_id, {}) as Dictionary).duplicate(true)
	S._advance_object(worker, worker["option"])
	ck(worker.get("option") == null and worker["needs"] == needs0 and worker.get("skills", {}) == skills0
		and int(worker["memory"].items.size()) == mem0 and int(S.econ_stats.get("wages_paid", 0)) == wages0,
		label + "：use tick 在 need/option/技能/记忆/工资上 fail-closed")
	ck(S.town_stock == stock0 and int(S.town_coin) == town0 and int(S.external_coin) == external0
		and S.event_log.size() == ev0 and S.cargo_manifests.get(manifest_id, {}) == manifest0,
		label + "：use tick 不改 cargo/库存/钱/事件")

func _events_since(S, start: int) -> Array:
	return S.event_log.slice(start)

## P1-b 之前的 option chain 口径；无 logistics/cargo 时新代码必须与这 6 字段折叠逐字节相同。
func _legacy_chain_without_cargo(S) -> int:
	var h: int = 0
	h = SimScript.mix32(h, int(S.tick_no))
	for ag in S.agents:
		h = SimScript.mix32(h, S._aid(ag))
		var p: Vector2i = ag["pos"]
		h = SimScript.mix32(h, int(p.x) * 65536 + int(p.y))
		for nid in ag["needs"]:
			h = SimScript.mix32(h, int(round(float(ag["needs"][nid]) * Inv.CHAIN_NEED_Q)))
		h = SimScript.mix32(h, int(ag.get("talking", 0)))
		var opt = ag["option"]
		if opt is Dictionary:
			h = SimScript.fnv1a32_into(h, "%s|%s|%s|%s|%s|%s" % [
				str(opt.get("kind", "")), str(opt.get("target", "")), str(opt.get("partner", "")),
				str(opt.get("area", "")), str(opt.get("phase", "")), str(opt.get("remaining", ""))])
		else:
			h = SimScript.mix32(h, -1)
	return h

func _off_gate_chain_matches_legacy() -> bool:
	var O = SimScript.new()
	add_child(O)
	O.auto_run = false
	O.backend = null
	O.start_new(1)
	O.logistics = {}
	O.cargo_manifests.clear()
	O.cargo_manifest_order.clear()
	var ag: Dictionary = O.get_agent("tao")
	ag["option"] = {
		"kind": "object", "target": "well", "partner": "", "area": "north",
		"phase": "travel", "remaining": 7,
	}
	var current := int(Inv.chain_step(0, O, O.event_log.size()))
	var legacy := _legacy_chain_without_cargo(O)
	remove_child(O)
	O.free()
	return current == legacy

func _canonical_case() -> String:
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.start_new(1)
	S.tick_no = int(S.TICKS_PER_DAY * 0.25)  # dawn：码头工在班，合同测试不被班次短路
	S.day = 3
	S._logi_import()
	_force_complete(S, S.get_agent("tao"))
	var out := JSON.stringify({
		"order": S.cargo_manifest_order,
		"manifests": S.cargo_manifests,
		"stock": S.town_stock,
		"town": S.town_coin,
		"external": S.external_coin,
		"events": S.event_log,
		"event_digest": S.event_digest,
	})
	remove_child(S)
	S.free()
	return out

func _ready() -> void:
	var S = SimScript.new()
	add_child(S)
	S.auto_run = false
	S.backend = null
	S.start_new(1)
	S.tick_no = int(S.TICKS_PER_DAY * 0.25)  # dawn：同时让负例证明“有资格但无货”仍为零
	var tao: Dictionary = S.get_agent("tao")
	var adv := _unload_adv(S)
	ck(not adv.is_empty() and String(adv.get("manifest_node", "")) == "port_dock", "卸货广告声明 manifest_node")

	# 负例：空港时广告 fail-closed；即便人工塞入一个已经完成的旧 option，也不得产生日志/技能/工资。
	var stock0: Dictionary = S.town_stock.duplicate(true)
	var town0: int = int(S.town_coin)
	var external0: int = int(S.external_coin)
	var needs0: Dictionary = tao["needs"].duplicate(true)
	var skills0 := int((tao.get("skills", {}) as Dictionary).get("卸货", 0))
	var mem0 := int(tao["memory"].items.size())
	var wages0 := int(S.econ_stats.get("wages_paid", 0))
	var ev0: int = S.event_log.size()
	ck(not S._adv_open(tao, adv), "无 cargo 时卸货候选关闭")
	_force_complete(S, tao)
	ck(S.town_stock == stock0 and S.town_coin == town0 and S.external_coin == external0,
		"空 cargo 强制完成不改库存/钱")
	ck(tao.get("option") == null and tao["needs"] == needs0 and S.event_log.size() == ev0
		and int((tao.get("skills", {}) as Dictionary).get("卸货", 0)) == skills0
		and int(tao["memory"].items.size()) == mem0 and int(S.econ_stats.get("wages_paid", 0)) == wages0,
		"空 cargo 为零 need/option/import/unload/完成记忆/技能/工资")

	# 付费整单若整数地板为零，arrival 必须拒绝；不能制造一个永久 ready、永远不可卸的 cargo。
	var import_lanes: Array = S.logistics.get("import_lanes", [])
	var invalid_lane: Dictionary = (import_lanes[0] as Dictionary).duplicate(true)
	invalid_lane["route_id"] = "invalid_floor"
	invalid_lane["batch"] = 1
	invalid_lane["price_per"] = 3
	invalid_lane["price_den"] = 4
	var invalid_order0: int = S.cargo_manifest_order.size()
	var invalid_manifest0: int = S.cargo_manifests.size()
	var invalid_ev0: int = S.event_log.size()
	ck(S._arrive_import_manifest(invalid_lane, 99) == ""
		and S.cargo_manifest_order.size() == invalid_order0
		and S.cargo_manifests.size() == invalid_manifest0 and S.event_log.size() == invalid_ev0,
		"整单价格地板为零的 paid lane 在 arrival fail-closed")

	# 正例：到期日只生成整单 cargo；真正完成卸货后才同步付款、入库、清 cargo、发工资。
	S.day = 3
	# 开局柴薪接近 cap；经唯一账本通道腾出恰一整单货位，避免把本合同测试变成 partial-floor 测试。
	var freed := -S._stock_move("柴薪", -4, "consume", "town", "manifest_fixture")
	ck(freed == 4, "fixture 经库存账本腾出一整单货位")
	var arr_stock: Dictionary = S.town_stock.duplicate(true)
	var arr_town: int = int(S.town_coin)
	var arr_ext: int = int(S.external_coin)
	var arr_ev: int = S.event_log.size()
	S._logi_import()
	var manifest_id := "manifest_east_ocean_3_0"
	ck(S.cargo_manifests.has(manifest_id) and int(S.cargo_manifests[manifest_id].get("remaining_qty", 0)) == 4,
		"East Ocean 到港生成确定 id 的 4 件整单 manifest")
	ck(S.town_stock == arr_stock and S.town_coin == arr_town and S.external_coin == arr_ext,
		"arrival 只落 cargo，不冒充 import 入库/付款")
	ck(S.event_log.size() == arr_ev + 1 and String(S.event_log[-1].get("note", "")).begins_with("cargo_arrive:"),
		"arrival 只写一条 world receipt")
	ck(S._adv_open(tao, adv), "有可整单提交 cargo 时卸货候选打开")

	var good := String(S.cargo_manifests[manifest_id].get("good", ""))
	var before_stock := int(S.town_stock.get(good, 0))
	var before_town: int = int(S.town_coin)
	var before_ext: int = int(S.external_coin)
	var commit_ev: int = S.event_log.size()
	_force_complete(S, tao)
	var suffix := _events_since(S, commit_ev)
	ck(int(S.town_stock.get(good, 0)) - before_stock == 4
		and int(S.cargo_manifests[manifest_id].get("remaining_qty", -1)) == 0
		and String(S.cargo_manifests[manifest_id].get("state", "")) == "complete",
		"cargo_delta == stock_delta == 4，manifest 完成（stock %d→%d cargo=%s）" % [before_stock,
			int(S.town_stock.get(good, 0)), str(S.cargo_manifests[manifest_id])])
	ck(before_town - S.town_coin == 7 and S.external_coin - before_ext == 3,
		"整单 import 付 3 钱，随后真实卸货工资付 4 钱（town %d→%d ext %d→%d）" % [
			before_town, int(S.town_coin), before_ext, int(S.external_coin)])
	ck(suffix.size() == 4
		and String(suffix[0].get("type", "")) == "pay" and String(suffix[0].get("note", "")) == "import*4"
		and String(suffix[1].get("type", "")) == "import" and String(suffix[1].get("note", "")) == "import*4"
		and String(suffix[2].get("type", "")) == "world" and String(suffix[2].get("note", "")).begins_with("cargo_unload:")
		and String(suffix[3].get("type", "")) == "pay" and String(suffix[3].get("note", "")) == "wage:卸货",
		"提交顺序固定为 import pay → stock → cargo receipt → wage（suffix=%s）" % JSON.stringify(suffix))
	var hard := {}
	for row in Inv.check_all(S, 0):
		if int(row.get("id", 0)) in [34, 38, 44, 45, 46]:
			hard[int(row["id"])] = bool(row.get("ok", false))
	ck(hard.size() == 5 and hard.values().all(func(v): return bool(v)),
		"既有 #34/#38/#44/#45/#46 结构门仍绿且 5 条全被命中")

	# 反射存档必须保住 pending cargo；普通 save fixture 未必命中这类中间态。
	S.day = 6
	S._logi_import()
	var pending_id := "manifest_east_ocean_6_0"
	var save_path := "user://p1b_manifest_contract_test.save"
	ck(S.save_game(save_path), "pending manifest 可存档")
	S.cargo_manifests[pending_id]["remaining_qty"] = 0
	ck(S.load_game(save_path) and int(S.cargo_manifests[pending_id].get("remaining_qty", 0)) == 4,
		"pending manifest 读档恢复 remaining_qty")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	tao = S.get_agent("tao")
	adv = _unload_adv(S)

	# 到港后若 use 期间货位、余额或 cargo 被别的提交抢走，捕获的 exact manifest 不得偷换或留下半提交。
	ck(S._adv_open(tao, adv), "pending cargo 初始可被候选选中")
	_install_use_option(tao, pending_id)
	var pending_good := String(S.cargo_manifests[pending_id].get("good", ""))
	var pending_cap := int((S.production.get("goods", {}) as Dictionary).get(pending_good, {}).get("cap", 0))
	var filled := S._stock_move(pending_good, pending_cap - int(S.town_stock.get(pending_good, 0)),
		"produce", "port_dock", "manifest_race_fixture")
	ck(filled >= 4 and not S._adv_open(tao, adv), "use 期间货位被填满后 pending cargo 候选关闭")
	_probe_blocked_use(S, tao, pending_id, "整单货位不足")
	freed = -S._stock_move(pending_good, -4, "consume", "town", "manifest_recovery")
	ck(freed == 4 and S._adv_open(tao, adv), "腾出整单货位后同一 pending manifest 可恢复")

	_install_use_option(tao, pending_id)
	var saved_town := int(S.town_coin)
	S.town_coin = 0
	_probe_blocked_use(S, tao, pending_id, "use 期间余额耗尽")
	S.town_coin = saved_town

	_install_use_option(tao, pending_id)
	S.cargo_manifests[pending_id]["remaining_qty"] = 0
	S.cargo_manifests[pending_id]["state"] = "complete"
	_probe_blocked_use(S, tao, pending_id, "use 期间 manifest 被抢先提交")
	S.cargo_manifests[pending_id]["remaining_qty"] = 4
	S.cargo_manifests[pending_id]["state"] = "ready"
	ck(S._adv_open(tao, adv), "货位/余额/cargo 恢复后原 manifest 再次可卸")
	_force_complete(S, tao, pending_id)
	ck(int(S.cargo_manifests[pending_id].get("remaining_qty", -1)) == 0
		and String(S.cargo_manifests[pending_id].get("state", "")) == "complete",
		"阻塞解除后提交的是原 pending manifest")

	# mutation 牙：option 的 exact cargo 绑定与 manifest 价格都会驱动未来，chain 必须逐字段可分辨。
	freed = -S._stock_move(pending_good, -4, "consume", "town", "manifest_shift_fixture")
	ck(freed == 4, "班次竞态 fixture 腾出新 manifest 的整单货位")
	S.day = 9
	S._logi_import()
	var chain_id := "manifest_east_ocean_9_0"
	ck(S._adv_open(tao, adv), "在班时新到 manifest 可被选中")
	_install_use_option(tao, chain_id)
	var in_shift_tick := int(S.tick_no)
	S.tick_no = int(S.TICKS_PER_DAY * 0.75)
	_probe_blocked_use(S, tao, chain_id, "use 期间跨出班次")
	S.tick_no = in_shift_tick
	ck(S._adv_open(tao, adv), "恢复班次后同一 manifest 仍可重选")
	_install_use_option(tao, chain_id)
	var chain_base := int(Inv.chain_step(0, S, S.event_log.size()))
	tao["option"]["manifest_id"] = chain_id + "_other"
	var chain_option_id := int(Inv.chain_step(0, S, S.event_log.size()))
	tao["option"]["manifest_id"] = chain_id
	tao["option"]["manifest_node"] = "other_node"
	var chain_option_node := int(Inv.chain_step(0, S, S.event_log.size()))
	tao["option"]["manifest_node"] = "port_dock"
	S.cargo_manifests[chain_id]["price_per"] = int(S.cargo_manifests[chain_id]["price_per"]) + 1
	var chain_price_per := int(Inv.chain_step(0, S, S.event_log.size()))
	S.cargo_manifests[chain_id]["price_per"] = int(S.cargo_manifests[chain_id]["price_per"]) - 1
	S.cargo_manifests[chain_id]["price_den"] = int(S.cargo_manifests[chain_id]["price_den"]) + 1
	var chain_price_den := int(Inv.chain_step(0, S, S.event_log.size()))
	S.cargo_manifests[chain_id]["price_den"] = int(S.cargo_manifests[chain_id]["price_den"]) - 1
	tao["option"] = null
	ck(chain_base != chain_option_id and chain_base != chain_option_node
		and chain_base != chain_price_per and chain_base != chain_price_den,
		"chain 对 manifest_id/manifest_node/price_per/price_den 单字段 mutation 全有牙")
	ck(_off_gate_chain_matches_legacy(), "logistics-off 普通 option 保持旧 6 字段 chain 逐字节不变")

	ck(_canonical_case() == _canonical_case(), "同 seed 同 manifest 的状态/事件/event_digest 逐字一致")
	print("p1b_cargo_manifest_test: %s (%d fail)" % [("PASS ✅" if _fails == 0 else "FAIL ❌"), _fails])
	get_tree().quit(1 if _fails > 0 else 0)
