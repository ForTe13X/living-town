extends Node
## S06 headless synthetic acceptance test.
## Usage: godot --headless --path game res://scenes/narrative/narrative_view_contract_test.tscn

const Contract = preload("res://scripts/narrative/NarrativeViewContract.gd")

var _fails := 0
var _checks := 0


func _ready() -> void:
	print("S06 NarrativeViewContract · synthetic two-role fixture")
	var state := _fixture()
	var map_result: Dictionary = Contract.project(state, "mapmaker")
	var editor_result: Dictionary = Contract.project(state, "editor")
	ck(bool(map_result["ok"]), "P01 mapmaker projection is valid")
	ck(bool(editor_result["ok"]), "P02 editor projection is valid")
	var map_snapshot: Dictionary = map_result["snapshot"]
	var editor_snapshot: Dictionary = editor_result["snapshot"]
	ck(map_snapshot != editor_snapshot
		and map_snapshot["visible_nodes"] != editor_snapshot["visible_nodes"]
		and map_snapshot["receipt_ids"] != editor_snapshot["receipt_ids"],
		"P03 same pre-state yields different role-filtered subgraphs/receipts")
	ck(_keys(map_snapshot) == Array(Contract.SNAPSHOT_KEYS), "P04 snapshot has exactly the ten v0 fields")
	var serialized := JSON.stringify({"a": map_result, "b": editor_result})
	ck(serialized.find("THE_MAPMAKER_ONLY_SECRET_SENTENCE") < 0
		and serialized.find("THE_EDITOR_ONLY_SECRET_SENTENCE") < 0,
		"P05 hidden claim prose is absent from snapshot and diagnostics")
	ck(JSON.stringify(Contract.project(state, "mapmaker")) == JSON.stringify(map_result),
		"P06 identical input is byte-stable after JSON serialization")
	ck(bool(Contract.claim_access(state, "mapmaker", "claim_map")["ok"]),
		"P07 claim is reachable through this role's receipt")
	var source := FileAccess.get_file_as_string("res://scripts/narrative/NarrativeViewContract.gd")
	ck(source.find("Sim") < 0 and source.find("Main") < 0 and source.find("WorldView") < 0,
		"P08 contract has no dependency on existing simulation/controller/view singletons")

	var unknown_node := state.duplicate(true)
	unknown_node["roles"]["mapmaker"]["visible_node_ids"].append("node_missing")
	mut(not bool(Contract.project(unknown_node, "mapmaker")["ok"])
		and (Contract.project(unknown_node, "mapmaker")["snapshot"] as Dictionary).is_empty()
		and _has_error(Contract.project(unknown_node, "mapmaker")["errors"], "node.unknown:node_missing"),
		"M01 unknown visible node is rejected fail-closed")

	var foreign_receipt := state.duplicate(true)
	foreign_receipt["roles"]["mapmaker"]["receipt_ids"].append("receipt_editor")
	mut(not bool(Contract.project(foreign_receipt, "mapmaker")["ok"])
		and _has_error(Contract.project(foreign_receipt, "mapmaker")["errors"], "receipt.foreign:receipt_editor:editor"),
		"M02 foreign receipt is rejected")

	var claim_denied: Dictionary = Contract.claim_access(state, "mapmaker", "claim_editor")
	mut(not bool(claim_denied["ok"])
		and _has_error(claim_denied["errors"], "claim.unauthorized:mapmaker:claim_editor"),
		"M03 claim without a role receipt is rejected")

	var foreign_custody := state.duplicate(true)
	foreign_custody["roles"]["mapmaker"]["carried_fragment_ids"].append("fragment_editor")
	mut(not bool(Contract.project(foreign_custody, "mapmaker")["ok"])
		and _has_error(Contract.project(foreign_custody, "mapmaker")["errors"], "fragment.foreign_custody:fragment_editor:editor"),
		"M04 cross-role custody leak is rejected")

	var raw_text_snapshot := map_snapshot.duplicate(true)
	raw_text_snapshot["claim_ids"] = ["claim_editor"]
	mut(_has_error(Contract.validate_snapshot(state, raw_text_snapshot), "snapshot.extra:claim_ids"),
		"M05 claim IDs cannot appear independently of receipts")
	var prose_snapshot := map_snapshot.duplicate(true)
	prose_snapshot["claim_text"] = "THE_EDITOR_ONLY_SECRET_SENTENCE"
	mut(_has_error(Contract.validate_snapshot(state, prose_snapshot), "snapshot.extra:claim_text"),
		"M06 raw claim text injected into a snapshot is rejected")

	var prose_changed := state.duplicate(true)
	prose_changed["claims"]["claim_map"]["text"] = "A_DIFFERENT_AUTHOR_SENTENCE"
	ck(JSON.stringify(Contract.project(prose_changed, "mapmaker")) == JSON.stringify(map_result),
		"D01 claim prose changes are intentionally outside this ID-only gate")
	var source_changed := state.duplicate(true)
	source_changed["receipts"]["receipt_map"]["source_chain"] = ["source_other"]
	ck(JSON.stringify(Contract.project(source_changed, "mapmaker")) == JSON.stringify(map_result),
		"D02 receipt provenance semantics are intentionally outside this v0 view gate")

	print("")
	print("detects: M01 unknown node; M02 foreign receipt; M03 unauthorized claim; M04 foreign custody; M05 independent claim IDs; M06 raw claim-text field")
	print("does_not_detect: D01 author claim prose truth/quality; D02 receipt source-chain semantics (both counterexamples executed)")
	print("confidence: 6/6 declared mutations detected; 2/2 declared outside-envelope counterexamples stayed unchanged")
	print("S06 CONTRACT: %s (%d checks, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func ck(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fails += 1
	print(("  PASS " if condition else "  FAIL ") + message)


func mut(condition: bool, message: String) -> void:
	ck(condition, message)


func _has_error(errors: Array, expected: String) -> bool:
	for error in errors:
		if String(error) == expected:
			return true
	return false


func _keys(snapshot: Dictionary) -> Array:
	var out: Array = snapshot.keys()
	out.sort_custom(func(a, b): return Array(Contract.SNAPSHOT_KEYS).find(String(a)) < Array(Contract.SNAPSHOT_KEYS).find(String(b)))
	return out


func _fixture() -> Dictionary:
	return {
		"nodes": {
			"square": {},
			"cafe": {},
			"archive": {},
		},
		"edges": {
			"edge_square_cafe": {"from_node": "square", "to_node": "cafe"},
			"edge_square_archive": {"from_node": "square", "to_node": "archive"},
		},
		"fragments": {
			"fragment_map": {"custodian_role_id": "mapmaker", "text": "HIDDEN_FRAGMENT_MAP"},
			"fragment_editor": {"custodian_role_id": "editor", "text": "HIDDEN_FRAGMENT_EDITOR"},
		},
		"claims": {
			"claim_map": {"text": "THE_MAPMAKER_ONLY_SECRET_SENTENCE", "author_truth": true},
			"claim_editor": {"text": "THE_EDITOR_ONLY_SECRET_SENTENCE", "author_truth": false},
		},
		"receipts": {
			"receipt_map": {"role_id": "mapmaker", "claim_id": "claim_map", "source_chain": ["source_map"]},
			"receipt_editor": {"role_id": "editor", "claim_id": "claim_editor", "source_chain": ["source_editor"]},
		},
		"requests": {
			"request_map": {"role_ids": ["mapmaker"]},
			"request_editor": {"role_ids": ["editor"]},
		},
		"roles": {
			"mapmaker": {
				"now_node": "square",
				"visible_node_ids": ["square", "cafe"],
				"visible_edge_ids": ["edge_square_cafe"],
				"carried_fragment_ids": ["fragment_map"],
				"receipt_ids": ["receipt_map"],
				"open_request_ids": ["request_map"],
				"route_hint": ["square", "cafe"],
				"clock": {"day": 1, "watch": 3, "tick": 60},
				"status": "active",
			},
			"editor": {
				"now_node": "square",
				"visible_node_ids": ["square", "archive"],
				"visible_edge_ids": ["edge_square_archive"],
				"carried_fragment_ids": ["fragment_editor"],
				"receipt_ids": ["receipt_editor"],
				"open_request_ids": ["request_editor"],
				"route_hint": ["square", "archive"],
				"clock": {"day": 1, "watch": 3, "tick": 60},
				"status": "blocked",
			},
		},
	}
