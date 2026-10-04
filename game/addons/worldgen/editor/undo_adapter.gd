@tool
extends RefCounted
class_name WorldGenUndoAdapter
## Bridges one semantic recipe snapshot transition into the editor's native undo stack.

func record_transition(undo_manager: Object, session: Object, before_snapshot: Dictionary, after_snapshot: Dictionary, action_name := "WorldGen: Edit", custom_context: Object = null) -> Dictionary:
	if undo_manager == null or session == null or not session.has_method("capture_snapshot") or not session.has_method("restore_snapshot"):
		return {"ok": false, "errors": ["E_UNDO_ADAPTER_TARGET: undo manager or semantic session is invalid"]}
	var current: Dictionary = session.capture_snapshot()
	if WorldGenCanonical.sha256(current) != WorldGenCanonical.sha256(before_snapshot):
		return {"ok": false, "status": "STALE_REVISION", "errors": ["E_UNDO_STALE: session no longer matches the captured before snapshot"]}
	if not _valid_snapshot(before_snapshot) or not _valid_snapshot(after_snapshot):
		return {"ok": false, "errors": ["E_UNDO_SNAPSHOT: before/after snapshots failed canonical binding"]}
	if int(after_snapshot.get("source_revision", -1)) <= int(before_snapshot.get("source_revision", -2)):
		return {"ok": false, "errors": ["E_UNDO_REVISION: semantic edit must advance the recipe revision"]}
	var before := before_snapshot.duplicate(true)
	var after := after_snapshot.duplicate(true)
	if undo_manager.get_class() == "EditorUndoRedoManager":
		undo_manager.create_action(action_name, 0, custom_context)
		undo_manager.add_do_method(session, "restore_snapshot", after)
		undo_manager.add_undo_method(session, "restore_snapshot", before)
		undo_manager.commit_action()
	else:
		if not undo_manager is UndoRedo:
			return {"ok": false, "errors": ["E_UNDO_MANAGER_TYPE: expected EditorUndoRedoManager or UndoRedo"]}
		undo_manager.create_action(action_name)
		undo_manager.add_do_method(session.restore_snapshot.bind(after))
		undo_manager.add_undo_method(session.restore_snapshot.bind(before))
	undo_manager.commit_action()
	return {"ok": true, "snapshot": session.capture_snapshot(), "before_sha256": WorldGenCanonical.sha256(before), "after_sha256": WorldGenCanonical.sha256(after)}

func _valid_snapshot(snapshot: Dictionary) -> bool:
	if String(snapshot.get("schema", "")) != "worldgen.semantic_edit_snapshot/1" or not snapshot.get("recipe", {}) is Dictionary: return false
	if int(snapshot.get("source_revision", -1)) != int(snapshot.get("recipe", {}).get("source_revision", -2)) or String(snapshot.get("recipe_sha256", "")) != WorldGenCanonical.sha256(snapshot.get("recipe", {})): return false
	var content: Dictionary = snapshot.duplicate(true)
	var digest := String(content.get("snapshot_sha256", ""))
	content.erase("snapshot_sha256")
	return digest == WorldGenCanonical.sha256(content)
