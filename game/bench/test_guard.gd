extends SceneTree
## Verify the chat() engine-fact guardrail. (a) Force _load_data() then start_new so real secrets seed,
## then check the guard on real agents. (b) Synthetic agents with the real belief shape as a definitive
## logic check (own secret + a learned secret + no-secret). Mirrors AIBackend._secret_guard exactly.
const SimScript = preload("res://scripts/Sim.gd")
func guard(ag) -> String:
	var beliefs = ag.get("beliefs", {})
	var claims := []
	for subj in beliefs:
		var b = beliefs[subj]
		if b is Dictionary and bool(b.get("secret", false)):
			var c := String(b.get("claim", "")).strip_edges()
			if c != "" and not claims.has(c): claims.append(c)
	return "" if claims.is_empty() else "护栏→ " + "；".join(claims)
func _init() -> void:
	var s = SimScript.new()
	get_root().add_child(s)
	s._load_data()                        # ensure JSON (incl secrets) loaded before seeding
	s.start_new(12)
	print("[real] scenario=[" + str(s.scenario) + "] secrets.seeds=" + str((s.secrets.get("seeds", []) as Array).size()))
	var n := 0
	for ag in s.agents:
		var g := guard(ag)
		if g != "":
			n += 1
			print("  [" + String(ag.get("id","")) + "] " + g)
	print("=== [real] " + str(n) + " / " + str(s.agents.size()) + " agents carry a protectable secret ===")
	# (b) synthetic definitive check
	var ben = {"id":"ben","beliefs":{"S_own_ben":{"secret":true,"claim":"阿本其实怕黑，晚上不敢一个人待着","owner":"ben"}}}
	var aria = {"id":"aria","beliefs":{
		"S_own_aria":{"secret":true,"claim":"阿丽在偷偷攒钱，想有天离开小镇去看海","owner":"aria"},
		"S_coco":{"secret":true,"claim":"可可偷偷喜欢着谁","owner":"coco","confidedBy":{"coco":0}},
		"R1":{"affinity":5}}}
	var plain = {"id":"x","beliefs":{"R1":{"affinity":3}}}
	print("[synthetic] ben  → " + guard(ben))
	print("[synthetic] aria → " + guard(aria))
	print("[synthetic] no-secret → [" + guard(plain) + "]")
	quit()
