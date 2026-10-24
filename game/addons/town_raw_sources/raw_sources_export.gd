@tool
extends EditorExportPlugin

const STAGE_PATH := "res://assets/town3d/stage_manifest.json"
const SOURCE_ROOT := "res://assets/town3d/"
const PRESET_NAME := "Windows Town3D"
const EXPECTED_ASSETS := 11


func _get_name() -> String:
	return "LivingTownVerifiedRawSources"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform.get_os_name() == "Windows"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var preset: EditorExportPreset = get_export_preset()
	if get_export_platform().get_os_name() != "Windows" or preset == null or preset.get_preset_name() != PRESET_NAME:
		return
	var stage_bytes: PackedByteArray = FileAccess.get_file_as_bytes(STAGE_PATH)
	var parsed: Variant = JSON.parse_string(stage_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		_fail("Missing or invalid stage manifest.")
		return
	var stage: Dictionary = parsed
	if stage.get("schema") != "living_town.game_stage.v2" or stage.get("status") != "PASS":
		_fail("A passing v2 stage manifest is required.")
		return
	var assets: Variant = stage.get("assets")
	var files: Variant = stage.get("files")
	if not assets is Array or assets.size() != EXPECTED_ASSETS or not files is Array:
		_fail("The current stage must bind exactly eleven town GLBs and their file records.")
		return
	var file_records: Dictionary = {}
	for record: Variant in files:
		if not record is Dictionary or not record.get("file") is String or file_records.has(record["file"]):
			_fail("Invalid or duplicate stage file record.")
			return
		file_records[record["file"]] = record
	# Verify every payload before adding any. PackedByteArray preserves these exact
	# checked bytes even if a source file changes later during the export process.
	var pending: Array[Dictionary] = []
	var seen: Dictionary = {}
	var total_bytes: int = 0
	for asset: Variant in assets:
		if not asset is Dictionary or not asset.get("file") is String:
			_fail("Invalid stage asset record.")
			return
		var name: String = asset["file"]
		if name.is_empty() or name != name.get_file() or not name.ends_with(".glb") or seen.has(name) or not file_records.has(name):
			_fail("Invalid, duplicate, or unbound town GLB name: " + name)
			return
		var record: Dictionary = file_records[name]
		var expected_sha: String = str(asset.get("sha256", ""))
		if expected_sha.length() != 64 or expected_sha != str(record.get("sha256", "")) or int(record.get("bytes", 0)) <= 0:
			_fail("Inconsistent GLB size/hash bindings: " + name)
			return
		var source_path: String = SOURCE_ROOT + name
		var payload: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
		if payload.size() != int(record["bytes"]) or _sha256(payload) != expected_sha:
			_fail("Town GLB source bytes do not match the current stage: " + name)
			return
		seen[name] = true
		pending.append({"path": source_path, "bytes": payload})
		total_bytes += payload.size()
	for source: Dictionary in pending:
		# This adds raw source bytes. Existing .glb.import remaps and imported .scn
		# resources remain unchanged and continue to serve ResourceLoader.
		add_file(source["path"], source["bytes"], false)
	print("TOWN_RAW_SOURCES_EXPORT_GATE: PASS assets=%d bytes=%d stage_sha256=%s" % [pending.size(), total_bytes, _sha256(stage_bytes)])


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


func _fail(message: String) -> void:
	get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Town raw source verification", message)
	push_error("TOWN_RAW_SOURCES_EXPORT_GATE: FAIL " + message)
