extends Node
## nbw_introspect.gd — 列出 NobodyWho GDExtension 在本 Godot(4.6.2) 下注册的类/方法/属性/信号，拿到确切 API。
func _ready() -> void:
	for cls in ["NobodyWhoModel", "NobodyWhoChat", "NobodyWhoEmbedding"]:
		print("\n==== %s exists=%s ====" % [cls, ClassDB.class_exists(cls)])
		if not ClassDB.class_exists(cls):
			continue
		print("-- properties --")
		for p in ClassDB.class_get_property_list(cls, true):
			print("  %s : %s" % [p.get("name", ""), p.get("type", "")])
		print("-- methods --")
		for m in ClassDB.class_get_method_list(cls, true):
			var args := []
			for a in m.get("args", []):
				args.append(String(a.get("name", "")))
			print("  %s(%s)" % [m.get("name", ""), ", ".join(args)])
		print("-- signals --")
		for s in ClassDB.class_get_signal_list(cls, true):
			var args2 := []
			for a in s.get("args", []):
				args2.append(String(a.get("name", "")))
			print("  %s(%s)" % [s.get("name", ""), ", ".join(args2)])
	get_tree().quit(0)
