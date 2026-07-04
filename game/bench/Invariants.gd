extends RefCounted
class_name BenchInvariants
## bench/Invariants.gd — 把「确定性社交底座」的 20 条机检不变量抽成单一真相源（语义照搬 sim_soak.gd / sim_social_port.mjs）。
## check_all(S, starved) → [{id:int, name:String, ok:bool, detail:String}]，供 bench Harness 跨 seed 网格与 soak 共用。
## 注：现为「终态断言」（跑完整局后评估），非逐 tick；首违 tick 粒度留作后续细化。

static func check_all(S, starved: int) -> Array:
	var R: Array = []
	var log: Array = S.event_log
	var accepted: Array = []
	for e in log:
		if bool(e["accepted"]) and not (String(e["type"]) in ["pay", "world"]):
			accepted.append(e)   # 经济(pay)/世界变更(world)事件不算社交参与——否则 inv2/3 被稀释成空门

	var harmony: bool = String(S.scenario) == ""   # 定向场景(faction/betray/freerider)会扭曲关系/致饿穿 → 豁免和睦不变量
	var small_n: bool = S.agents.size() <= 12       # 涌现/单源传播类只在设计 N(≤12)硬断言；大 N 单源谣言 fizzle 是现实(docs/12 L4)
	# 1) 无饿穿
	R.append(_chk(1, "无饿穿", starved == 0 or not harmony, "触底 need·tick=%d (应=0;场景豁免)" % starved))
	# 2) 社交发生
	R.append(_chk(2, "社交发生", not accepted.is_empty(), "已接受社交事务=%d (应>0)" % accepted.size()))
	# 3) 无永久孤立
	var participated := {}
	for e in accepted:
		participated[e["actor"]] = true
		participated[e["target"]] = true
	var isolated := []
	for ag in S.agents:
		if not participated.has(ag["id"]):
			isolated.append(ag["id"])
	R.append(_chk(3, "无永久孤立", isolated.is_empty(), "孤立 NPC=[%s]" % ", ".join(isolated)))
	# 4) 关系分化
	var aff_max := 0.0
	var aff_min := 0.0
	var any_nonzero := false
	for ag in S.agents:
		for oid in ag["relationships"]:
			var a := float(ag["relationships"][oid]["affinity"])
			aff_max = maxf(aff_max, a); aff_min = minf(aff_min, a)
			if a != 0.0:
				any_nonzero = true
	R.append(_chk(4, "关系分化", any_nonzero and aff_max - aff_min > 0.0, "affinity 跨度 %.0f..%.0f" % [aff_min, aff_max]))
	# 5) 谣言传播：R1 至少 2 人知道
	var r1 := []
	for ag in S.agents:
		if ag["beliefs"].has("R1"):
			r1.append(ag["id"])
	R.append(_chk(5, "谣言传播", r1.size() >= 2 or not harmony or not small_n, "知道 R1=[%s] (应≥2;场景/大N豁免)" % ", ".join(r1)))
	# 6) 知识边界
	var boundary_bad := 0
	for ag in S.agents:
		for cid in ag["beliefs"]:
			var b: Dictionary = ag["beliefs"][cid]
			if String(b.get("via", "")) in ["seed", "seen"]:
				continue   # seed=开局种子 / seen=亲眼所见(阶层 gossip 的财富目击)——一手知识无上游事件,豁免溯源
			var has_source: bool = S._agent_by_id.has(b.get("source", ""))
			var has_event := false
			for e in log:
				if String(e["type"]) == String(b.get("via", "")) and bool(e["accepted"]) and e["target"] == ag["id"] and e["subject"] == cid:
					has_event = true; break
			if not has_source or not has_event:
				boundary_bad += 1
	R.append(_chk(6, "知识边界", boundary_bad == 0, "无来源/无事件 belief=%d (应=0)" % boundary_bad))
	# 7) 账本可溯源
	var ids := {}
	for e in log:
		ids[e["id"]] = true
	var prov_bad := 0
	for ag in S.agents:
		for oid in ag["relationships"]:
			var r: Dictionary = ag["relationships"][oid]
			if int(r["last_pos"]) > 0 and not ids.has(int(r["last_pos"])):
				prov_bad += 1
			if int(r["last_neg"]) > 0 and not ids.has(int(r["last_neg"])):
				prov_bad += 1
	R.append(_chk(7, "账本可溯源", prov_bad == 0, "指向不存在事件=%d (应=0)" % prov_bad))

	# ── 承诺系统 ──
	var c_created: int = S.commitments.size()
	var c_fulfilled := 0
	var c_broken := 0
	var c_leaked := 0
	for c in S.commitments:
		match String(c["status"]):
			"fulfilled": c_fulfilled += 1
			"broken": c_broken += 1
			"active":
				if int(c["deadline"]) < S.tick_no:
					c_leaked += 1
	var broken_events := 0
	for e in log:
		if e["type"] == "meet" and not bool(e["accepted"]):
			broken_events += 1
	# 8) 承诺生命周期
	R.append(_chk(8, "承诺生命周期", c_created > 0 and c_fulfilled > 0, "创建=%d 兑现=%d (均应>0)" % [c_created, c_fulfilled]))
	# 9) 无悬挂承诺
	R.append(_chk(9, "无悬挂承诺", c_leaked == 0, "已过点仍 active=%d (应=0)" % c_leaked))
	# 10) 违约可溯源且有后果
	R.append(_chk(10, "违约可溯源有后果", broken_events == c_broken and (c_broken == 0 or S.st_neg_events > 0),
		"broken=%d 违约事件=%d 负向声誉=%d" % [c_broken, broken_events, S.st_neg_events]))

	# ── 冲突生命周期 ──
	var cf_created: int = S.conflicts.size()
	var cf_confronted := 0
	var cf_repaired := 0
	var bad_repair := 0
	var bad_repair_prov := 0
	for c in S.conflicts:
		if int(c["confronted"]) > 0:
			cf_confronted += 1
		match String(c["status"]):
			"repaired":
				cf_repaired += 1
				if int(c["confronted"]) <= 0:
					bad_repair += 1
				var has_apo := false
				for e in log:
					if e["type"] == "apologize" and bool(e["accepted"]) and e["actor"] == c["b"] and e["target"] == c["a"]:
						has_apo = true; break
				if not has_apo:
					bad_repair_prov += 1
	# 11) 冲突生命周期
	R.append(_chk(11, "冲突生命周期", cf_created > 0 and (cf_repaired + cf_confronted) > 0,
		"触发=%d 对质=%d 修复=%d" % [cf_created, cf_confronted, cf_repaired]))
	# 12) 先对质后和解
	R.append(_chk(12, "先对质后和解", bad_repair == 0, "未对质即修复=%d (应=0)" % bad_repair))
	# 13) 修复可溯源
	R.append(_chk(13, "修复可溯源", bad_repair_prov == 0, "无道歉支撑的修复=%d (应=0)" % bad_repair_prov))

	# ── S1 声誉 ──
	var st_max := 0.0
	var st_min := 0.0
	for ag in S.agents:
		for oid in ag["relationships"]:
			var sv := float(ag["relationships"][oid]["standing"])
			st_max = maxf(st_max, sv); st_min = minf(st_min, sv)
	var rep_events := 0
	for e in log:
		if e["type"] == "gossip_rep" and bool(e["accepted"]):
			rep_events += 1
	var perceived := {}
	var prop_a := {}
	var acc_a := {}
	for ag in S.agents:
		var s := 0.0
		var n := 0
		for b in S.agents:
			if b["id"] != ag["id"]:
				s += float(S._rel(b, ag["id"])["standing"]); n += 1
		perceived[ag["id"]] = s / max(1, n)
		prop_a[ag["id"]] = 0; acc_a[ag["id"]] = 0
	for e in log:
		if String(e["type"]) in ["greet", "give", "gossip", "invite", "gossip_rep"]:
			prop_a[e["actor"]] = int(prop_a[e["actor"]]) + 1
			if bool(e["accepted"]): acc_a[e["actor"]] = int(acc_a[e["actor"]]) + 1
	var actives: Array = []
	for ag in S.agents:
		if int(prop_a[ag["id"]]) >= 5: actives.append(ag["id"])
	actives.sort_custom(func(x, y): return float(perceived[x]) < float(perceived[y]))
	var ostr := "n/a"
	var ostracism_ok := true
	if actives.size() >= 2:
		var town_acc := 0.0
		for id in actives:
			town_acc += float(acc_a[id]) / float(prop_a[id])
		town_acc /= float(actives.size())
		var worst: String = actives[0]
		var rw := float(acc_a[worst]) / float(prop_a[worst])
		ostr = "最坏 %s(%.1f) 接受率 %.2f / 镇均 %.2f" % [worst, perceived[worst], rw, town_acc]
		if float(perceived[worst]) <= -0.8:
			ostracism_ok = rw <= town_acc + 0.08
	# 14) standing 分化
	R.append(_chk(14, "standing分化", st_max - st_min > 0.0, "跨度 %.0f..%.0f" % [st_min, st_max]))
	# 15) 涌现放逐
	R.append(_chk(15, "涌现放逐", ostracism_ok or not small_n, ostr + (" (大N豁免:密集社交下放逐不锐利)" if not small_n else "")))
	# 16) 声誉传播
	var bad_rep_exists := st_min <= float(S.REP_GOSSIP_TH)
	R.append(_chk(16, "声誉传播", (not bad_rep_exists) or rep_events > 0, "坏名声=%s gossip_rep=%d" % [str(bad_rep_exists), rep_events]))
	# 17) 坏名声形成且可恢复
	R.append(_chk(17, "坏名声形成可恢复", S.st_neg_events > 0 and cf_repaired > 0, "L3负向=%d 修复=%d (均应>0)" % [S.st_neg_events, cf_repaired]))

	# ── S2 意见动力学 ──
	var att_spread := 0.0
	for t in S.TOPICS:
		var vmax := -2.0
		var vmin := 2.0
		for ag in S.agents:
			var v := float(ag["attitudes"][t])
			vmax = maxf(vmax, v); vmin = minf(vmin, v)
		att_spread = maxf(att_spread, vmax - vmin)
	var att_moved := 0
	for ag in S.agents:
		for t in S.TOPICS:
			if absf(float(ag["attitudes"][t]) - float(ag["attitude0"][t])) > 0.02:
				att_moved += 1
	var discuss_events := 0
	for e in log:
		if e["type"] == "discuss" and bool(e["accepted"]):
			discuss_events += 1
	var stifled_count := 0
	for ag in S.agents:
		stifled_count += ag["stifled"].size()
	# 18) 观点演化不坍缩
	R.append(_chk(18, "观点演化不坍缩", (att_spread > 0.3 and att_moved > 0) or not harmony, "跨度 %.2f 变动者 %d (场景豁免)" % [att_spread, att_moved]))
	# 19) 有界信任门
	R.append(_chk(19, "有界信任Deffuant", (discuss_events > 0 and S.refused_by_bound > 0) or not harmony, "discuss=%d 因ε拒谈=%d (场景豁免)" % [discuss_events, S.refused_by_bound]))
	# 20) 谣言变冷
	R.append(_chk(20, "谣言变冷MakiThompson", stifled_count > 0 or not small_n, "stifler=%d (应>0;大N豁免:依赖单源谣言充分传播)" % stifled_count))

	# ── S3c 秘密信息博弈 (21-24，含小N守护) ──
	var betray_ev: Array = []
	for e in log:
		if e["type"] == "betray": betray_ev.append(e)
	var secret_cids := {}
	var secret_bad_via := 0
	for ag in S.agents:
		for cid in ag["beliefs"]:
			var b: Dictionary = ag["beliefs"][cid]
			if bool(b.get("secret", false)):
				secret_cids[cid] = true
				if not (String(b.get("via", "")) in ["confide", "leak", "seed"]): secret_bad_via += 1
	for e in log:
		if e["type"] == "gossip" and secret_cids.has(e["subject"]): secret_bad_via += 1
	R.append(_chk(21, "秘密专道", secret_bad_via == 0, "秘密漏进gossip/非法via=%d (应=0)" % secret_bad_via))
	var betray_bad := 0
	for be in betray_ev:
		var betrayed: Dictionary = S._agent_by_id.get(be["target"], {})
		var has_rel: bool = (not betrayed.is_empty()) and betrayed["relationships"].has(be["actor"])
		var has_conflict := false
		for c in S.conflicts:
			if c["a"] == be["target"] and c["b"] == be["actor"]: has_conflict = true; break
		var ln_ok: bool = has_rel and int(betrayed["relationships"][be["actor"]]["last_neg"]) > 0 and ids.has(int(betrayed["relationships"][be["actor"]]["last_neg"]))
		if not (has_rel and has_conflict and ln_ok): betray_bad += 1
	R.append(_chk(22, "背叛有后果可溯源", betray_bad == 0, "无冲突/不可溯源的背叛=%d (应=0)" % betray_bad))
	R.append(_chk(23, "背叛重挫名声", betray_ev.is_empty() or S.st_neg_events > 0, "背叛=%d 累积负判=%d" % [betray_ev.size(), S.st_neg_events]))
	var false_betray := 0
	for be in betray_ev:
		var has := false
		for e in log:
			if int(e["id"]) < int(be["id"]) and bool(e["accepted"]) and (e["type"] == "confide" or e["type"] == "leak") and e["actor"] == be["target"] and e["target"] == be["actor"] and e["subject"] == be["subject"]:
				has = true; break
		if not has: false_betray += 1
	R.append(_chk(24, "背叛无误判", false_betray == 0, "无直接上游吐露证据的背叛=%d (应=0)" % false_betray))

	# ── S3a 观点派系 (25-28，含小N守护) ──
	var fac_inc := 0
	for ag in S.agents:
		if (String(ag["faction"]) == "") != (int(ag["faction_size"]) == 1): fac_inc += 1
		if String(ag["faction"]) != "" and String(ag["faction"]) != String(ag["id"]) and not S._aligned(ag, S._agent_by_id[ag["faction"]]): fac_inc += 1
	R.append(_chk(25, "S3派系派生一致", fac_inc == 0, "不一致=%d (应=0)" % fac_inc))
	var fac_count: int = S.factions.size()
	var in_sum := 0.0
	var in_n := 0
	var cr_sum := 0.0
	var cr_n := 0
	for a in S.agents:
		for b in S.agents:
			if a["id"] == b["id"] or String(a["faction"]) == "" or String(b["faction"]) == "": continue
			var aff := float(S._rel(a, b["id"])["affinity"])
			if String(a["faction"]) == String(b["faction"]): in_sum += aff; in_n += 1
			else: cr_sum += aff; cr_n += 1
	var fac_aff_ok := true
	var fac_msg := "派系=%d ingroup对=%d cross对=%d" % [fac_count, in_n, cr_n]
	if harmony and fac_count >= 2 and in_n >= 3 and cr_n >= 3:
		var in_avg := in_sum / float(in_n)
		var cr_avg := cr_sum / float(cr_n)
		fac_aff_ok = in_avg > cr_avg + float(S.FACTION_AFF_MARGIN)
		fac_msg = "同派系均%.1f vs 跨派系均%.1f" % [in_avg, cr_avg]
	else: fac_msg += " (小N/场景跳过)"
	R.append(_chk(26, "S3同派系亲和>跨派系", fac_aff_ok, fac_msg))
	var st_overflow := 0
	var endorse_bad := 0
	for ag in S.agents:
		for oid in ag["relationships"]:
			if absf(float(ag["relationships"][oid]["standing"])) > float(S.STANDING_CAP) + 0.001: st_overflow += 1
	for e in log:
		if e["type"] == "endorse" and not S._agent_by_id.has(e["subject"]): endorse_bad += 1
	R.append(_chk(27, "S3协同守边界", st_overflow == 0 and endorse_bad == 0, "|standing|越界=%d 无效endorse=%d" % [st_overflow, endorse_bad]))
	var fac_bucket_bad := 0
	for m in S.factions:
		if (S.factions[m] as Array).size() < 2: fac_bucket_bad += 1
		for id in (S.factions[m] as Array):
			if String(S._agent_by_id[id]["faction"]) != String(m): fac_bucket_bad += 1
	R.append(_chk(28, "S3派系视图自洽", fac_bucket_bad == 0, "坏桶/标签不符=%d" % fac_bucket_bad))

	# ── S3b 互助盟约 (29-33，含小N守护) ──
	var aid_ev: Array = []
	for e in log:
		if e["type"] == "aid" and bool(e["accepted"]): aid_ev.append(e)
	var pact_pairs := {}
	for p in S.pacts_index: pact_pairs[p["key"]] = true
	var aid_nonpact := 0
	for e in aid_ev:
		if not pact_pairs.has(S._pact_key(e["actor"], e["target"])): aid_nonpact += 1
	R.append(_chk(29, "I-PACT互助偏内", S.aid_accepted < 8 or aid_nonpact == 0, "非盟约aid=%d (aid总%d,样本≥8应=0)" % [aid_nonpact, S.aid_accepted]))
	var pact_b_bad := 0
	for p in S.pacts_index:
		if String(p["status"]) == "broken" and String(p.get("reason", "")).begins_with("freerider"):
			var has_ev := false
			for e in log:
				if e["type"] == "pact" and not bool(e["accepted"]) and String(e.get("note", "")) == "dissolved:freerider" and ((e["actor"] == p["a"] and e["target"] == p["b"]) or (e["actor"] == p["b"] and e["target"] == p["a"])):
					has_ev = true; break
			if not has_ev or int(p.get("breakGap", 0)) < S.FREERIDER_GAP: pact_b_bad += 1
	R.append(_chk(30, "I-PACT-free-rider可溯源", pact_b_bad == 0, "异常=%d (应=0)" % pact_b_bad))
	var pact_c_bad := 0
	for p in S.pacts_index:
		if String(p["status"]) == "active" and not (float(p["formTrustA"]) >= float(S.PACT_TRUST_TH) and float(p["formTrustB"]) >= float(S.PACT_TRUST_TH) and float(p["formFam"]) >= float(S.PACT_FAM_TH) and int(p["formComplement"]) >= S.PACT_COMPLEMENT_TH): pact_c_bad += 1
	R.append(_chk(31, "I-PACT结盟门达标", pact_c_bad == 0, "低门被结的active=%d" % pact_c_bad))
	var pact_d_bad := 0
	var active_keys := {}
	for p in S.pacts_index:
		if not (String(p["status"]) in ["active", "broken"]): pact_d_bad += 1
		if String(p["status"]) == "active":
			active_keys[p["key"]] = int(active_keys.get(p["key"], 0)) + 1
			var A: Dictionary = S._agent_by_id.get(p["a"], {})
			var B: Dictionary = S._agent_by_id.get(p["b"], {})
			if A.is_empty() or B.is_empty() or not (A["pacts"].has(p["b"]) and String(A["pacts"][p["b"]]["status"]) == "active" and B["pacts"].has(p["a"]) and String(B["pacts"][p["a"]]["status"]) == "active"): pact_d_bad += 1
	for k in active_keys:
		if int(active_keys[k]) > 1: pact_d_bad += 1
	R.append(_chk(32, "I-PACT无悬挂无重复对称", pact_d_bad == 0, "异常=%d" % pact_d_bad))
	var pact_e_bad := 0
	for p in S.pacts_index:
		if String(p["status"]) == "broken" and int(S._agent_by_id[p["a"]]["complementSeen"].get(p["b"], 0)) == 0: pact_e_bad += 1
	R.append(_chk(33, "I-PACT解体可恢复", pact_e_bad == 0, "complementSeen被清=%d" % pact_e_bad))

	# ── Wave 1b 经济 (34-35，economy.json 缺失时恒过=零扰动) ──
	var econ_on: bool = not S.economy.is_empty()
	var neg_coin := 0
	for ag in S.agents:
		if int(ag["inventory"].get("coin", 0)) < 0: neg_coin += 1
	# 34) 金钱守恒：Σagent coin + 镇库 恒等于开局总量（transfer 唯一通道的结构保证，机检兜底）
	R.append(_chk(34, "金钱守恒", (not econ_on) or int(S.money_total()) == int(S.econ_total0),
		"总量=%d 基准=%d (应相等)" % [int(S.money_total()), int(S.econ_total0)]))
	# 35) 货币非负：transfer 不足即拒 → 任何人不可能透支
	R.append(_chk(35, "货币非负", neg_coin == 0 and S.town_coin >= 0, "负余额agent=%d 镇库=%d" % [neg_coin, int(S.town_coin)]))

	# ── Wave 2b 节日 (36，festivals.json 缺失时恒过) ──
	# 36) 节日无残留且账实相符：fest_ 对象只在节日进行中存在；spawn-despawn 事件差 == 现存 fest 对象数
	var fest_now := 0
	for oid in S.world.get("objects", {}):
		if String(oid).begins_with("fest_"): fest_now += 1
	var sp_ev := 0
	var dsp_ev := 0
	for e in log:
		if String(e["type"]) == "world":
			if String(e.get("note", "")) == "spawn": sp_ev += 1
			elif String(e.get("note", "")) == "despawn": dsp_ev += 1
	var fest_ok: bool = (fest_now == 0 or String(S.festival_active) != "") and (sp_ev - dsp_ev == fest_now)
	R.append(_chk(36, "节日对象配对无残留", fest_ok, "现存=%d 活动=%s spawn=%d despawn=%d" % [fest_now, String(S.festival_active), sp_ev, dsp_ev]))
	return R

static func _chk(id: int, name: String, ok: bool, detail: String) -> Dictionary:
	return {"id": id, "name": name, "ok": ok, "detail": detail, "hard": id in HARD_IDS}

## L4 不变量两分（docs/12 §L4）：
##  · 硬（结构）= 状态合法性/可溯源/边界/生命周期合法性。任何 LOD/规模/激进降频下都必须为真——
##    冻结一个远端 agent 不会让它的状态变非法，只是不再产生涌现行为。
##  · 软（涌现统计）= 需要活动才会显现的量（社交发生、分化、放逐锐利度、观点演化…），
##    已按 场景/大N 豁免；激进 LOD 下远端=背景群演，软不变量按设计会漂。
## 消费方：激进 LOD 门只查硬不变量（split_fails().hard==0）；soak/Harness 仍查全 33 条。
const HARD_IDS := [1, 6, 7, 9, 10, 12, 13, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36]

static func split_fails(S, starved: int) -> Dictionary:
	var hard := 0
	var soft := 0
	for c in check_all(S, starved):
		if bool(c["ok"]):
			continue
		if bool(c["hard"]): hard += 1
		else: soft += 1
	return {"hard": hard, "soft": soft}

## event_log 确定性摘要：同 seed 两跑应得同一值（覆盖 id/类型/双方/接受/主题/时刻）。
static func digest(S) -> int:
	var parts := PackedStringArray()
	for e in S.event_log:
		parts.append("%d:%s:%s:%s:%d:%s:%d" % [
			int(e.get("id", 0)), String(e.get("type", "")), String(e.get("actor", "")),
			String(e.get("target", "")), int(bool(e.get("accepted", false))),
			String(e.get("subject", "")), int(e.get("tick", 0))])
	return "|".join(parts).hash()
