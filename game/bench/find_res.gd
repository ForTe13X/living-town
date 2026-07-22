extends SceneTree
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 1
	if OS.get_cmdline_user_args().size() > 0: seed = int(OS.get_cmdline_user_args()[0])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run=false; S.backend=null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var stay := {}; var slept := {}; var low := {}
	for t in range(12*TPD):
		S.tick()
		for aid in ["ben","coco","aria"]:
			var a: Dictionary = S.get_agent(aid)
			if a.is_empty(): continue
			var k := String(a.get("space"))+"/"+String(a.get("floor"))
			stay[aid] = stay.get(aid, {}); stay[aid][k] = int((stay[aid] as Dictionary).get(k,0))+1
			var o = a.get("option")
			if o != null and String((o as Dictionary).get("action",""))=="睡觉" and String(a.get("space"))!="town":
				slept[aid] = int(slept.get(aid,0))+1
			var mn := 100.0
			for nid in a["needs"]: mn = minf(mn, float(a["needs"][nid]))
			low[aid] = minf(float(low.get(aid,100.0)), mn)
	for aid in ["ben","coco","aria"]:
		var st: Dictionary = stay[aid]; var tot := 0
		for k in st: tot += int(st[k])
		var inside := tot - int(st.get("town/outdoor",0))
		print("%-5s 室内占比=%d%%  在家睡觉tick=%d  min_need=%.1f  stay=%s" % [aid, 100*inside/maxi(1,tot), int(slept.get(aid,0)), low[aid], JSON.stringify(st)])
	quit()
