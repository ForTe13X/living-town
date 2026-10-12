extends SceneTree
## Semantic snapshot transition, native UndoRedo wiring and late-job rejection checks.

const SESSION := preload("res://addons/worldgen/editor/semantic_edit_session.gd")
const ADAPTER := preload("res://addons/worldgen/editor/undo_adapter.gd")
const CANONICAL := preload("res://addons/worldgen/core/worldgen_canonical.gd")

func _initialize() -> void:
	var recipe := _recipe(3, "spring")
	var session = SESSION.new()
	var initialized: Dictionary = session.initialize(recipe, "build_3", "a".repeat(64))
	_assert(initialized.get("ok", false), "base recipe session initializes")
	var before: Dictionary = session.capture_snapshot()
	recipe["stages"][0]["parameters"]["palette_id"] = "mutated_outside"
	_assert(session.capture_snapshot()["recipe"]["stages"][0]["parameters"]["palette_id"] == "spring", "session is isolated from shared recipe mutation")
	var ticket: Dictionary = session.begin_job()
	var next_recipe := _recipe(4, "winter")
	var next_result: Dictionary = session.prepare_result_snapshot(ticket, next_recipe, "build_4", "b".repeat(64))
	_assert(next_result.get("ok", false), "candidate snapshot is bound to current worker ticket")
	var history := UndoRedo.new()
	var adapter = ADAPTER.new()
	var committed: Dictionary = adapter.record_transition(history, session, before, next_result["snapshot"], "WorldGen: Palette Edit")
	_assert(committed.get("ok", false), "one semantic transaction is recorded")
	_assert(session.capture_snapshot()["recipe_sha256"] == next_result["snapshot"]["recipe_sha256"], "commit installs the next snapshot")
	var late_result: Dictionary = session.prepare_result_snapshot(ticket, _recipe(4, "late"), "late_build", "c".repeat(64))
	_assert(late_result.get("status") == "STALE_RESULT", "late worker result is rejected after edit commit")
	history.undo()
	_assert(session.capture_snapshot()["recipe_sha256"] == before["recipe_sha256"] and session.capture_snapshot()["build_id"] == "build_3", "undo restores canonical recipe and build identity")
	history.redo()
	_assert(session.capture_snapshot()["recipe_sha256"] == next_result["snapshot"]["recipe_sha256"] and session.capture_snapshot()["build_id"] == "build_4", "redo restores next recipe and build identity")
	var reopened = SESSION.new()
	var decoded: Variant = JSON.parse_string(JSON.stringify(next_result["snapshot"]))
	var restored: Dictionary = reopened.restore_snapshot(decoded)
	_assert(restored.get("ok", false) and reopened.capture_snapshot().get("snapshot_sha256") == next_result["snapshot"].get("snapshot_sha256") and reopened.capture_snapshot().get("build_id") == "build_4", "serialized snapshot reopens with identical build binding")
	var stale_commit: Dictionary = adapter.record_transition(history, session, before, next_result["snapshot"], "stale")
	_assert(stale_commit.get("status") == "STALE_REVISION", "stale snapshot cannot create an undo action")
	if _failures.is_empty():
		print("WORLDGEN_UNDO_TESTS_OK snapshots=isolated undo=restores_redo=replays reopen=bound stale_result=rejected transaction_count=1")
		history.clear_history(false)
		session = null
		reopened = null
		adapter = null
		history = null
		quit(0)
	else:
		for failure: String in _failures: push_error(failure)
		history.clear_history(false)
		quit(1)

var _failures: Array[String] = []

func _recipe(revision: int, palette: String) -> Dictionary:
	return {"schema": "worldgen.recipe/1", "id": "undo_town", "source_revision": revision,
		"stages": [{"id": "layout", "operator": "test.layout/1", "inputs": {}, "parameters": {"palette_id": palette}}],
		"outputs": {"semantic": "layout.semantic"}}

func _assert(condition: bool, message: String) -> void:
	if not condition: _failures.append("E_UNDO_TEST: %s" % message)
