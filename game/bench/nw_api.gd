extends SceneTree
## bench/nw_api.gd — 打印 NobodyWhoChat/Model 暴露的方法+信号，确认 v9.4.0 是否有 reset_context / stop 之类（决定池化 worker 修法可行性）。
func _init() -> void:
	for cls in ["NobodyWhoChat", "NobodyWhoModel"]:
		print("==== %s exists=%s ====" % [cls, ClassDB.class_exists(cls)])
		if not ClassDB.class_exists(cls): continue
		var o: Object = ClassDB.instantiate(cls)
		var ms := []
		for m in o.get_method_list():
			var n := String(m["name"])
			if not n.begins_with("_") and not n.begins_with("emit_") and not n.begins_with("connect") and not n.begins_with("disconnect"):
				ms.append(n)
		ms.sort()
		print("  methods: ", ", ".join(ms))
		var sigs := []
		for s in o.get_signal_list(): sigs.append(String(s["name"]))
		sigs.sort()
		print("  signals: ", ", ".join(sigs))
		var props := []
		for p in o.get_property_list():
			var pn := String(p["name"])
			if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or (int(p["usage"]) & PROPERTY_USAGE_DEFAULT and not pn.begins_with("_") and pn == pn.to_lower()):
				props.append(pn)
		print("  props: ", ", ".join(props))
		if o is Node: o.free()
	quit(0)
