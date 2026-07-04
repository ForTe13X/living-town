extends SceneTree
## bench/PrivacyProbe.gd — 一次性度量探针（吸取 visit 教训：先量真瓶颈）。
## 问题：invite→meet 承诺实际把多少「高 trust+高 aff」对送到了同一区，却因 _secret_private=false
##       （耳边两格内有第三者 / 无封闭房）而 confide 落空？即「到场但没能私语」的对数/占比。
## 纯读态、不改 Sim → 不扰动 digest。用法：
##   godot --headless --path . --script res://bench/PrivacyProbe.gd -- [--seeds 1-12] [--days 60]

const SimScript = preload("res://scripts/Sim.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-8")
	var days := 60
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])

	print("=== PrivacyProbe · invite→meet→confide 漏斗  seeds=%s days=%d ===" % [str(seeds), days])

	# 跨 seed 汇总
	var G := {
		"invites": 0, "invite_hi": 0,          # 全部 invite 事件 / 其中「高trust+高aff」对之间的
		"meet_fulfilled": 0, "meet_broken": 0,
		"copresent_ticks": 0,                  # 高trust对 同区共处的 tick 数（去重按 tick·pair）
		"copresent_private_ticks": 0,          # 其中 _secret_private=true 的
		"copresent_notprivate_ticks": 0,       # 到场但耳边有第三者 → 没能私语
		"confide": 0, "betray": 0,
		"ready_pairs_ever": 0,                 # 曾满足 trust≥25&aff≥floor 的有序对（去重）
		"ready_pairs_copresent": 0,            # 其中曾同区共处
		"ready_pairs_private": 0,              # 其中曾达成私密独处（confide 的必要条件全齐）
		"ready_pairs_confided": 0,             # 其中真的 confide 了
	}
	var per_seed_lines: Array = []
	var thr_trust := 0.0                        # 展示用：门槛值(引擎常量，各 seed 一致)
	var thr_aff := 0.0

	for sd in seeds:
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		S.auto_run = false
		S.backend = null
		S.start_new(sd)
		var TT: int = int(S.TICKS_PER_DAY)
		var total := days * TT
		var CONFIDE_TRUST: float = S.CONFIDE_TRUST
		var AFF_FLOOR: float = S.SECRET_AFF_FLOOR
		thr_trust = CONFIDE_TRUST; thr_aff = AFF_FLOOR

		# per-seed 累加器
		var s_copre := 0
		var s_copre_priv := 0
		var s_copre_np := 0
		# 有序对状态集合（"a|b"）
		var ready := {}            # 曾 ready(trust&aff 达门)
		var ready_copre := {}      # ready 且曾同区
		var ready_priv := {}       # ready 且曾私密独处
		var ready_conf := {}       # ready 且真 confide

		for t in range(total):
			S.tick()
			# 扫所有有序对，判定「到场但没能私语」——只看 owner 有可吐露秘密的对（否则 confide 本就不该发生）
			for a in S.agents:
				for b in S.agents:
					if a["id"] == b["id"]:
						continue
					var r: Dictionary = S._rel(a, b["id"])
					var trust := float(r["trust"])
					var aff := float(r["affinity"])
					if trust < CONFIDE_TRUST or aff < AFF_FLOOR:
						continue
					# a 是否对 b 有「可吐露的私密秘密」（否则谈私密相处无意义）
					var cs: String = S._confidable_secret(a, b)
					if cs == "":
						continue
					var key: String = String(a["id"]) + "|" + String(b["id"])
					ready[key] = true
					# 同区共处？
					var same_area := String(a.get("area", "")) != "" and String(a.get("area", "")) == String(b.get("area", ""))
					if same_area:
						ready_copre[key] = true
						s_copre += 1
						if S._secret_private(a, b):
							ready_priv[key] = true
							s_copre_priv += 1
						else:
							s_copre_np += 1

		# 扫 event_log 统计 invite / meet / confide / betray，并标注 invite 是否发生在「高trust」对
		var n_inv := 0; var n_inv_hi := 0; var n_mf := 0; var n_mb := 0; var n_conf := 0; var n_bet := 0
		for e in S.event_log:
			var ty := String(e["type"])
			if ty == "invite":
				n_inv += 1
			elif ty == "meet":
				if bool(e["accepted"]): n_mf += 1
				else: n_mb += 1
			elif ty == "confide":
				n_conf += 1
				var k := String(e["actor"]) + "|" + String(e["target"])
				ready_conf[k] = true
			elif ty == "betray":
				n_bet += 1

		G["invites"] += n_inv
		G["meet_fulfilled"] += n_mf
		G["meet_broken"] += n_mb
		G["confide"] += n_conf
		G["betray"] += n_bet
		G["copresent_ticks"] += s_copre
		G["copresent_private_ticks"] += s_copre_priv
		G["copresent_notprivate_ticks"] += s_copre_np
		G["ready_pairs_ever"] += ready.size()
		G["ready_pairs_copresent"] += ready_copre.size()
		G["ready_pairs_private"] += ready_priv.size()
		G["ready_pairs_confided"] += ready_conf.size()

		per_seed_lines.append("[seed %d] invite=%d meet(ok/broken)=%d/%d confide=%d betray=%d | ready_pairs=%d copresent=%d private=%d confided=%d | copre_ticks=%d (priv=%d notpriv=%d)" % [
			sd, n_inv, n_mf, n_mb, n_conf, n_bet, ready.size(), ready_copre.size(), ready_priv.size(), ready_conf.size(), s_copre, s_copre_priv, s_copre_np])

		get_root().remove_child(S)
		S.free()

	print("\n— 每 seed —")
	for l in per_seed_lines:
		print("  " + l)

	print("\n— 跨 seed 汇总 —")
	print("  invite 事件总数: %d" % G["invites"])
	print("  meet 达成/爽约: %d / %d" % [G["meet_fulfilled"], G["meet_broken"]])
	print("  confide 事件总数: %d   betray: %d" % [G["confide"], G["betray"]])
	print("")
	print("  【核心漏斗·按有序对(去重)】—— 分母=曾满足 trust≥%d & aff≥%d 且 owner 手握可吐露秘密的对" % [int(thr_trust), int(thr_aff)])
	var rp := int(G["ready_pairs_ever"])
	print("    ready 对（达信任门+有秘密）      : %d" % rp)
	print("    └ 曾同区共处                     : %d  (%.1f%%)" % [G["ready_pairs_copresent"], _pct(G["ready_pairs_copresent"], rp)])
	print("      └ 曾达成私密独处(confide必要门): %d  (%.1f%%)" % [G["ready_pairs_private"], _pct(G["ready_pairs_private"], rp)])
	print("        └ 真的 confide 了            : %d  (%.1f%%)" % [G["ready_pairs_confided"], _pct(G["ready_pairs_confided"], rp)])
	print("")
	print("  【到场但没能私语·按 tick·pair】")
	var ct := int(G["copresent_ticks"])
	print("    高信任对同区共处 tick 总数       : %d" % ct)
	print("    └ 其中私密(可 confide)           : %d  (%.1f%%)" % [G["copresent_private_ticks"], _pct(G["copresent_private_ticks"], ct)])
	print("    └ 其中耳边有旁人(私语落空)       : %d  (%.1f%%)" % [G["copresent_notprivate_ticks"], _pct(G["copresent_notprivate_ticks"], ct)])
	print("")
	print("  === 判定 ===")
	var copre := int(G["ready_pairs_copresent"])
	var priv := int(G["ready_pairs_private"])
	if rp == 0:
		print("  瓶颈更靠上游：几乎没有 ready 对（信任门 + 有可吐露秘密都难同时成立）。")
	elif copre > 0 and priv == 0:
		print("  杠杆在【隐私门/meet目的地】：ready 对到了同区却从未私密独处。")
	elif copre == 0:
		print("  杠杆在【上游】：ready 对存在，但 invite→meet 从未把它们送到同一区。")
	else:
		print("  混合：部分 ready 对达成私密独处；剩余瓶颈见占比。")
	quit(0)

func _pct(x, d) -> float:
	if int(d) == 0:
		return 0.0
	return 100.0 * float(x) / float(d)

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1):
			out.append(s)
	elif "," in spec:
		for s in spec.split(","):
			out.append(int(s))
	else:
		out.append(int(spec))
	return out
