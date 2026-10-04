extends SceneTree
## Writes a new save candidate using a reviewed explicit topology mapping. It never overwrites input.

const SimScript := preload("res://scripts/Sim.gd")
const MigrationScript := preload("res://addons/worldgen/consumers/ai_town_adapter/migrations.gd")
const CURRENT_SAVE_SCHEMA := 2

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		_fail("usage: -- <source-save> <migration.json> <new-output-save>")
		return
	var source_path := args[0]
	var migration_path := args[1]
	var output_path := args[2]
	if not FileAccess.file_exists(source_path) or not FileAccess.file_exists(migration_path):
		_fail("source save and migration manifest must exist")
		return
	if FileAccess.file_exists(output_path):
		_fail("output already exists; choose a new candidate path")
		return
	var save_file := FileAccess.open(source_path, FileAccess.READ)
	if save_file == null or save_file.get_length() < 8:
		_fail("source save is unreadable or truncated")
		return
	var header_schema := save_file.get_32()
	var blob_value: Variant = save_file.get_var()
	save_file.close()
	if header_schema != CURRENT_SAVE_SCHEMA or not blob_value is Dictionary:
		_fail("only current schema-2 package saves are eligible for structural migration")
		return
	var blob: Dictionary = blob_value
	if blob.get("magic") != "LTSAVE" or int(blob.get("schema", -1)) != header_schema \
			or not blob.get("state") is Dictionary or not blob.get("meta") is Dictionary:
		_fail("source save envelope is invalid")
		return
	if blob.has("player_trace"):
		_fail("save has player replay trace; structural migration cannot preserve its boundary evidence")
		return
	var manifest_file := FileAccess.open(migration_path, FileAccess.READ)
	if manifest_file == null:
		_fail("migration manifest is unreadable")
		return
	var manifest_text := manifest_file.get_as_text()
	var manifest_value: Variant = JSON.parse_string(manifest_text)
	manifest_file.close()
	if not manifest_value is Dictionary:
		_fail("migration manifest must be a JSON object")
		return
	var manifest_hasher := HashingContext.new()
	manifest_hasher.start(HashingContext.HASH_SHA256)
	manifest_hasher.update(manifest_text.to_utf8_buffer())
	var manifest_sha256 := manifest_hasher.finish().hex_encode()
	var candidate := SimScript.new()
	candidate._load_data()
	candidate.start_new(0)
	var source_meta: Dictionary = blob["meta"]
	var saved_ref: Variant = source_meta.get("_world_package_ref")
	if not saved_ref is Dictionary:
		candidate.free()
		_fail("source save has no package reference")
		return
	var migration: RefCounted = MigrationScript.new()
	var transformed: Dictionary = migration.prepare_offline_migration(blob["state"], manifest_value,
		saved_ref, candidate._authored_world_package_ref, candidate._authored_spaces,
		candidate._authored_portals, candidate._authored_interiors_data,
		candidate._interior_object_defs(candidate._authored_interiors_data))
	if not bool(transformed.get("ok", false)):
		candidate.free()
		_fail("migration refused: " + ";".join(transformed.get("errors", [])))
		return
	var migrated_state: Dictionary = transformed["state"]
	var state_error := candidate._validate_loaded_state(migrated_state, CURRENT_SAVE_SCHEMA)
	if state_error != "":
		candidate.free()
		_fail("migrated state rejected by current Sim: " + state_error)
		return
	var output_blob: Dictionary = blob.duplicate(true)
	output_blob["state"] = migrated_state
	(output_blob["meta"] as Dictionary)["_world_package_ref"] = transformed["world_package_ref"].duplicate(true)
	var shape_error := candidate._validate_current_save_shape(output_blob)
	if shape_error != "":
		candidate.free()
		_fail("migrated save rejected by current schema: " + shape_error)
		return
	var destination := FileAccess.open(output_path, FileAccess.WRITE)
	if destination == null:
		candidate.free()
		_fail("cannot create output candidate")
		return
	destination.store_32(CURRENT_SAVE_SCHEMA)
	destination.store_var(output_blob)
	destination.close()
	candidate.free()
	print(JSON.stringify({"ok": true, "output": output_path,
		"world_package_ref": transformed["world_package_ref"],
		"migration_manifest_sha256": manifest_sha256,
		"cancelled_options": int(transformed.get("cancelled_options", 0)),
		"migration": transformed.get("migration", "")}))
	quit(0)

func _fail(message: String) -> void:
	push_error("WORLDGEN_SAVE_MIGRATION_REFUSED: " + message)
	quit(1)
