extends Node
## LocalLlama.gd — 端上 llama.cpp 推理服务（docs/191）：把 APK 里打包的 llama-server（libllamad.so）起成
## 常驻子进程，AIBackend 的 `local` 档经 127.0.0.1 HTTP（OpenAI 兼容，与 `llm` 档同一套传输/解析）调用它。
##
## 为什么不再用 NobodyWho（进程内 GDExtension）：真机实测同一台 8 Elite 上，自编 llama.cpp（i8mm/dotprod +
## Q4_0 在线重排 + flash-attn + 前缀 KV 复用）比 NobodyWho 路 prefill/decode 都快数倍，且旋钮全在我们手里；
## 另外子进程与游戏进程隔离——推理崩/泄漏只死服务，不拖垮游戏（docs/34 的那类原生泄漏被进程边界封顶）。
##
## 安卓约束：targetSdk≥29 禁止 exec 应用数据目录里的文件（W^X），唯一合法可执行位置是 APK 解出的
## nativeLibraryDir ⇒ 可执行文件以 lib*.so 名打进 jniLibs，并需 legacy packaging（导出预设
## gradle_build/compress_native_libraries=true）让系统把它解到磁盘。桌面：找 PATH/同目录的 llama-server。

signal ready_changed(ok: bool)

const PORT := 18089
const BIN_ANDROID := "libllamad.so"
const HEALTH_TIMEOUT_MS := 90000        # 冷启 mmap 1GB 模型 + 首次重排 ≈ 3-6s；给足余量
var threads := 6                        # 真机：8 核里留 2 个给 Godot 主线程/渲染线程（docs/191 §4）
var ctx_size := 4096
var up := false                         # 服务已就绪（/health=200）
var model_path := ""
var _pid := -1
var _starting := false

func endpoint() -> String:
	return "http://127.0.0.1:%d/v1/chat/completions" % PORT

## 可执行文件位置。安卓：从 /proc/self/maps 找 libgodot_android.so 所在目录 = nativeLibraryDir。
func binary_path() -> String:
	if OS.has_feature("android"):
		var d := _native_lib_dir()
		return d.path_join(BIN_ANDROID) if d != "" else ""
	var env := OS.get_environment("LT_LLAMA_SERVER")   # 桌面测试：显式指一个 llama-server 可执行文件
	if env != "" and FileAccess.file_exists(env):
		return env
	var exe_dir := OS.get_executable_path().get_base_dir()
	for p in [exe_dir.path_join("llama-server.exe"), exe_dir.path_join("llama-server")]:
		if FileAccess.file_exists(p):
			return p
	return ""

## 安卓上 Godot 的 FileAccess 只认应用自己的目录，/data/app/…/lib 与 /proc 都判"不存在"（真机实测）
## ⇒ 可执行文件存在性交给系统 sh 的 `test -x`，结果缓存（路径在进程生命周期内不变）。
var _bin_ok := -1
func _bin_exists(b: String) -> bool:
	if b == "":
		return false
	if not OS.has_feature("android"):
		return FileAccess.file_exists(b)
	if _bin_ok < 0:
		_bin_ok = 1 if OS.execute("/system/bin/sh", ["-c", "test -x \"%s\"" % b]) == 0 else 0
	return _bin_ok == 1

func available() -> bool:
	var b := binary_path()
	var ok := _bin_exists(b)
	if not _avail_logged:
		_avail_logged = true
		diag("available bin=%s exists=%s" % [b, ok])
	return ok

var _lib_dir_cache := ""
var _avail_logged := false

func _native_lib_dir() -> String:
	if _lib_dir_cache != "":
		return _lib_dir_cache
	# 真机实测：JavaClassWrapper 读 ApplicationInfo.nativeLibraryDir 字段拿到 null（只包方法不包字段），不走那条。
	# ① /proc/self/maps 里 libgodot_android.so 所在目录（安卓上 FileAccess 打不开 /proc，桌面/将来放开时仍可用）
	if _lib_dir_cache == "":
		var f := FileAccess.open("/proc/self/maps", FileAccess.READ)
		diag("maps open=%s err=%d" % [f != null, FileAccess.get_open_error()])
		if f != null:
			_lib_dir_cache = _dir_from_maps(f.get_as_text())
			if _lib_dir_cache == "":
				while not f.eof_reached():
					var ln := f.get_line()
					if ln.contains("/libgodot_android.so"):
						_lib_dir_cache = _dir_from_maps(ln)
						break
	# ③ 系统 sh 读父进程（= 本游戏进程）的 maps
	if _lib_dir_cache == "":
		var out := []
		var rc := OS.execute("/system/bin/sh", ["-c", "grep -m1 libgodot_android.so /proc/$PPID/maps"], out)
		diag("sh maps rc=%d out=%s" % [rc, str(out).substr(0, 200)])
		if not out.is_empty():
			_lib_dir_cache = _dir_from_maps(String(out[0]))
	diag("native_lib_dir=%s" % _lib_dir_cache)
	return _lib_dir_cache

func _dir_from_maps(text: String) -> String:
	var i := text.find("/libgodot_android.so")
	if i <= 0:
		return ""
	var s := text.rfind(" ", i)
	return text.substr(s + 1, i - s - 1).strip_edges()

## 手机上 Godot print 进不了 logcat ⇒ 关键节点落 user://local_llama.log（adb run-as 可读），≤200 行。
var _diag_n := 0
func diag(msg: String) -> void:
	if _diag_n >= 200:
		return
	_diag_n += 1
	var f := FileAccess.open("user://local_llama.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://local_llama.log") and _diag_n > 1 else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%d %s" % [Time.get_ticks_msec(), msg])
		f.close()

## 起服务（幂等）。已就绪/同模型 → 立即 true；换模型 → 杀旧起新。返回是否就绪。
func ensure_started(model: String) -> bool:
	if up and model == model_path and _alive():
		return true
	while _starting:
		await get_tree().process_frame
	if up and model == model_path and _alive():
		return true
	_starting = true
	stop()
	var bin := binary_path()
	if not _bin_exists(bin) or not FileAccess.file_exists(model):
		push_warning("[local] 缺可执行文件或模型：bin=%s model=%s" % [bin, model])
		diag("missing bin=%s(%s) model=%s(%s)" % [bin, _bin_exists(bin), model, FileAccess.file_exists(model)])
		_starting = false
		return false
	var args := ["-m", model, "--host", "127.0.0.1", "--port", str(PORT),
		"-t", str(threads), "-tb", str(threads), "-c", str(ctx_size), "-np", "1",
		"-fa", "on", "--no-webui", "--cache-reuse", "64", "-lv", "1"]
	# 可选投机解码：模型同目录放一个同 tokenizer 的小模型 draft.gguf（如 Qwen2.5-0.5B Q4_0）。
	# 真机实测台词 decode 36→44 t/s（+22%，贪心等价、输出逐字相同）；决策 1 token 不受影响。代价：多 ~0.4GB 内存。
	var draft := model.get_base_dir().path_join("draft.gguf")
	if FileAccess.file_exists(draft):
		args.append_array(["-md", draft, "-td", str(threads), "--spec-draft-n-max", "8", "--spec-draft-n-min", "2"])
	if OS.has_feature("android"):
		# 经 sh exec：进程号不变（exec 替换 sh），且 stdout/stderr 落 user://llamad.log —— 手机上服务起不来时唯一的死因记录。
		var logp := ProjectSettings.globalize_path("user://llamad.log")
		var q := PackedStringArray()
		for a in [bin] + args:
			q.append("'%s'" % String(a).replace("'", "'\\''"))
		_pid = OS.create_process("/system/bin/sh", ["-c", "exec %s > '%s' 2>&1" % [" ".join(q), logp]])
	else:
		_pid = OS.create_process(bin, args)
	model_path = model
	print("[local] spawn pid=%d %s %s" % [_pid, bin, " ".join(args)])
	diag("spawn pid=%d bin=%s model=%s" % [_pid, bin, model])
	var ok := false
	if _pid > 0:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < HEALTH_TIMEOUT_MS and _alive():
			if await _health():
				ok = true
				break
			await get_tree().create_timer(0.25).timeout
	up = ok
	_starting = false
	diag("ready=%s alive=%s" % [ok, _alive()])
	if not ok:
		stop()
	ready_changed.emit(ok)
	return ok

func _alive() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)

func _health() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	if http.request("http://127.0.0.1:%d/health" % PORT) != OK:
		http.queue_free()
		return false
	var res = await http.request_completed
	http.queue_free()
	return int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200

func stop() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	up = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop()
