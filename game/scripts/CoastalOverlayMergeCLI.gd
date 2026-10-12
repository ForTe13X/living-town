extends SceneTree
## Produce a disposable merged data set for inspection without replacing live project data.

const IMPORTER := preload("res://scripts/CoastalOverlayBundleImporter.gd")
const PACKAGE_COMPILER := preload("res://scripts/CoastalPackageCompiler.gd")
const DEFAULT_OVERLAY := "res://coastal/warm_bay_s1/export/sim_adapter"
const DEFAULT_OUTPUT := "res://coastal/warm_bay_s1/export/sim_adapter/merged_preview"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var overlay_dir := DEFAULT_OVERLAY if args.is_empty() else args[0]
	var output_dir := DEFAULT_OUTPUT if args.size() < 2 else args[1]
	var base_spaces: Variant = _read_json("res://data/spaces.json")
	var base_interiors: Variant = _read_json("res://data/interiors.json")
	if not base_spaces is Dictionary or not base_interiors is Dictionary:
		push_error("E_BASE_DATA: cannot load base spaces/interiors")
		quit(2)
		return
	var merged: Dictionary = IMPORTER.load_and_merge(overlay_dir, base_spaces, base_interiors)
	if not bool(merged.get("ok", false)):
		for error: String in merged.get("errors", []):
			push_error(error)
		quit(1)
		return
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("E_OUTPUT_DIR: could not create %s" % output_dir)
		quit(2)
		return
	var outputs := {
		"spaces.json": merged["spaces"],
		"interiors.json": merged["interiors"],
		"affordances.json": {"affordances": merged["affordances"], "home_anchors": merged["home_anchors"], "runtime_binding": merged["runtime_binding"]}
	}
	var output_hashes := {}
	for filename: String in outputs:
		output_hashes[filename] = _sha256(PACKAGE_COMPILER.canonical_json(outputs[filename]))
	for filename: String in outputs:
		if not _write_json(output_dir.path_join(filename), outputs[filename]):
			quit(2)
			return
	var bundle_manifest: Dictionary = merged["manifest"]
	var preview_manifest := {"schema": "living-town.coastal-merged-preview/1", "source_town_id": bundle_manifest.get("town_id", ""),
		"source_overlay_artifacts": bundle_manifest.get("artifacts", {}), "base_spaces_sha256": _sha256(PACKAGE_COMPILER.canonical_json(base_spaces)),
		"base_interiors_sha256": _sha256(PACKAGE_COMPILER.canonical_json(base_interiors)), "outputs": output_hashes,
		"runtime_binding": merged["runtime_binding"], "activates_sim": false}
	if not _write_json(output_dir.path_join("manifest.json"), preview_manifest):
		quit(2)
		return
	print("COAST_MERGE_OK spaces=%d portals=%d affordances=%d bound=%d unbound=%d output=%s" % [merged["spaces"]["spaces"].size(), merged["spaces"]["portals"].size(), merged["affordances"].size(), merged["runtime_binding"]["bound_count"], merged["runtime_binding"]["unbound_ids"].size(), output_dir])
	quit(0)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed := JSON.new()
	var error := parsed.parse(file.get_as_text())
	file.close()
	return parsed.data if error == OK else null


func _write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("E_OUTPUT: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
	file.close()
	return true


func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
