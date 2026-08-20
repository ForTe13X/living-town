extends Node

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
const Contract = preload("res://scripts/labs/resource_pool/ExpeditionContract.gd")
const Adapter = preload("res://scripts/labs/resource_pool/MapTileExpeditionAdapter.gd")
const MapTileModel = preload("res://scripts/labs/MapTileLabModel.gd")
const MANIFEST_PATH := "res://scenes/labs/resource_pool/manifest.json"

var _fails := 0
var _checks := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s %s%s" % [("PASS" if condition else "FAIL"), label,
		("  " + detail if detail != "" else "")])
	if not condition:
		_fails += 1


func _ready() -> void:
	print("=== expedition brief + causal debrief contract ===")
	var destination: Dictionary = ScaleAddress.site_address("ashfall", 0, Vector2i(7, -1), "ash_market")
	var destination_id := ScaleAddress.canonical_id(destination)
	var briefs := {}
	for mission in Contract.mission_ids():
		briefs[mission] = Contract.make_brief(260814, destination_id, mission, "day12-board-a")

	var all_briefs_valid := true
	var contract_ids := {}
	for mission in Contract.mission_ids():
		var brief: Dictionary = briefs[mission]
		all_briefs_valid = all_briefs_valid and Contract.validate_brief(brief).is_empty()
		contract_ids[String(brief.get("contract_id", ""))] = true
	_check("three authored briefs are valid and distinct", all_briefs_valid and contract_ids.size() == 3)
	_check("mission objectives use three different real loot kinds",
		String((briefs["field_medicine"]["objective"] as Dictionary)["kind"]) == "meds"
		and String((briefs["winter_rations"]["objective"] as Dictionary)["kind"]) == "food"
		and String((briefs["relay_parts"]["objective"] as Dictionary)["kind"]) == "parts")
	_check("authored totals match the current Ash Market loot table",
		_profile_exact(briefs["field_medicine"], 70, 1400, 3)
		and _profile_exact(briefs["winter_rations"], 38, 2600, 4)
		and _profile_exact(briefs["relay_parts"], 91, 3500, 8))
	_check("same seed, site, mission, and board slot reproduce exactly",
		JSON.stringify(briefs["relay_parts"]) == JSON.stringify(
			Contract.make_brief(260814, destination_id, "relay_parts", "day12-board-a")))
	_check("terms-bound relay brief has an exact golden contract id",
		briefs["relay_parts"]["terms_version"] == "ash-market-v1"
		and briefs["relay_parts"]["contract_id"] == "exp1:1559bd902070291f")
	_check("a later board slot cannot replay the same contract id",
		briefs["relay_parts"]["contract_id"] != Contract.make_brief(
			260814, destination_id, "relay_parts", "day13-board-a")["contract_id"])
	_check("brief builders reject tile-only, unknown, and ambiguous inputs",
		Contract.make_brief(260814, ScaleAddress.canonical_id(ScaleAddress.parent(destination)),
			"relay_parts", "day12-board-a").is_empty()
		and Contract.make_brief(260814, destination_id, "scrap_run", "day12-board-a").is_empty()
		and Contract.make_brief(260814, destination_id, "relay_parts", "Day12").is_empty())
	var tampered_brief: Dictionary = briefs["relay_parts"].duplicate(true)
	(tampered_brief["objective"] as Dictionary)["required"] = 1
	var tampered_terms: Dictionary = briefs["relay_parts"].duplicate(true)
	tampered_terms["terms_version"] = "ash-market-v2"
	_check("authored objective or terms-version tampering fails closed",
		not Contract.validate_brief(tampered_brief).is_empty()
		and not Contract.validate_brief(tampered_terms).is_empty())

	var success_snapshots := {
		"field_medicine": Contract.make_snapshot("extracted", _inventory(0, 2, 0, 0), 70, 1400, 84, 25, 5, 1),
		"winter_rations": Contract.make_snapshot("extracted", _inventory(2, 0, 0, 0), 38, 2600, 100, 35, 4, 0),
		"relay_parts": Contract.make_snapshot("extracted", _inventory(0, 0, 2, 0), 91, 3500, 65, 36, 8, 2),
	}
	var clean_outcomes := {}
	var all_clean := true
	for mission in Contract.mission_ids():
		var outcome: Dictionary = Contract.evaluate(briefs[mission], success_snapshots[mission])
		clean_outcomes[mission] = outcome
		all_clean = all_clean and outcome.get("status") == "success" and outcome.get("grade") == "clean"
		all_clean = all_clean and Contract.validate_outcome(briefs[mission], outcome).is_empty()
	_check("all three missions have a clean full-success arm", all_clean)
	_check("food delivery exposes the existing +3.0 supply effect",
		int((clean_outcomes["winter_rations"]["settlement"] as Dictionary)["supply_gain_tenths"]) == 30)
	var capped_food_snapshot: Dictionary = Contract.make_snapshot(
		"extracted", _inventory(2, 0, 0, 0), 38, 2600, 100, 35, 4, 0, 230)
	var capped_food: Dictionary = Contract.evaluate(briefs["winter_rations"], capped_food_snapshot)
	_check("food settlement reports the applied gain at the 24.0 supply cap",
		int((capped_food["settlement"] as Dictionary)["supply_gain_tenths"]) == 10
		and int((capped_food["settlement"] as Dictionary)["supply_after_tenths"]) == 240)

	var strained_snapshot: Dictionary = Contract.make_snapshot(
		"extracted", _inventory(0, 2, 0, 0), 70, 1400, 60, 28, 6, 1)
	var strained: Dictionary = Contract.evaluate(briefs["field_medicine"], strained_snapshot)
	_check("meeting the target while breaching its safety constraint is visible",
		strained.get("status") == "success" and strained.get("grade") == "strained"
		and not bool((strained["constraint"] as Dictionary)["passed"]))

	var partial_snapshot: Dictionary = Contract.make_snapshot(
		"extracted", _inventory(0, 0, 1, 0), 55, 1100, 93, 34, 7, 0)
	var partial: Dictionary = Contract.evaluate(briefs["relay_parts"], partial_snapshot)
	_check("one target item extracts as partial success",
		partial.get("status") == "partial" and partial.get("grade") == "incomplete"
		and int((partial["objective"] as Dictionary)["delivered"]) == 1
		and int((partial["objective"] as Dictionary)["missing"]) == 1)

	var retreat_snapshot: Dictionary = Contract.make_snapshot(
		"extracted", _inventory(0, 0, 0, 1), 24, 2000, 100, 12, 3, 0)
	var retreat: Dictionary = Contract.evaluate(briefs["field_medicine"], retreat_snapshot)
	_check("optional scrap can be banked without pretending the objective succeeded",
		retreat.get("status") == "retreat"
		and int((retreat["settlement"] as Dictionary)["banked_value"]) == 24
		and int((retreat["objective"] as Dictionary)["delivered"]) == 0)

	var collapse_snapshot: Dictionary = Contract.make_snapshot(
		"collapsed", _inventory(0, 0, 2, 1), 99, 3900, 0, 41, 10, 2)
	var collapse: Dictionary = Contract.evaluate(briefs["relay_parts"], collapse_snapshot)
	_check("collapse overrides picked progress and loses all carried value",
		collapse.get("status") == "collapse" and collapse.get("grade") == "lost"
		and int((collapse["objective"] as Dictionary)["carried"]) == 2
		and int((collapse["objective"] as Dictionary)["delivered"]) == 0
		and int((collapse["settlement"] as Dictionary)["lost_value"]) == 99
		and int((collapse["settlement"] as Dictionary)["banked_value"]) == 0)

	var all_outcomes := [clean_outcomes["field_medicine"], clean_outcomes["winter_rations"],
		clean_outcomes["relay_parts"], strained, partial, retreat, collapse]
	var conservation_holds := true
	var outcome_envelopes_valid := true
	var concise_lines := true
	for raw_outcome in all_outcomes:
		var outcome: Dictionary = raw_outcome
		var settlement: Dictionary = outcome["settlement"]
		var snapshot: Dictionary = outcome["snapshot"]
		conservation_holds = conservation_holds \
			and int(settlement["banked_value"]) + int(settlement["lost_value"]) == int(snapshot["cargo_value"])
		outcome_envelopes_valid = outcome_envelopes_valid \
			and Contract.validate_outcome(briefs[String(outcome["mission"])], outcome).is_empty()
		concise_lines = concise_lines and (outcome["lines"] as Array).size() <= 6
	_check("every result conserves cargo value exactly", conservation_holds)
	_check("success, strained, partial, retreat, and collapse all recompute", outcome_envelopes_valid)
	_check("causal card stays within six factual rows", concise_lines)
	_check("debrief keeps exposure and injury as separate facts",
		"high_noise" in (partial["reason_codes"] as Array)
		and "health_cost" in (partial["reason_codes"] as Array)
		and not _lines_contain(partial["lines"], "noise caused"))

	var integral_float: Dictionary = partial_snapshot.duplicate(true)
	integral_float["cargo_value"] = 55.0
	(integral_float["inventory"] as Dictionary)["parts"] = 1.0
	var invalid_fraction: Dictionary = partial_snapshot.duplicate(true)
	invalid_fraction["cargo_value"] = 55.5
	var invalid_huge: Dictionary = partial_snapshot.duplicate(true)
	invalid_huge["cargo_value"] = 1.0e300
	var invalid_extra: Dictionary = partial_snapshot.duplicate(true)
	invalid_extra["camera_open"] = true
	var invalid_collapse: Dictionary = collapse_snapshot.duplicate(true)
	invalid_collapse["health"] = 1
	var dead_extraction: Dictionary = partial_snapshot.duplicate(true)
	dead_extraction["health"] = 0
	var inventory_overflow: Dictionary = partial_snapshot.duplicate(true)
	(inventory_overflow["inventory"] as Dictionary)["parts"] = Contract.MAX_INVENTORY_COUNT + 1
	var inventory_total_overflow: Dictionary = partial_snapshot.duplicate(true)
	inventory_total_overflow["inventory"] = _inventory(64, 64, 1, 0)
	_check("JSON integral floats normalize to integer authority",
		int(Contract.normalize_snapshot(integral_float)["cargo_value"]) == 55
		and int((Contract.normalize_snapshot(integral_float)["inventory"] as Dictionary)["parts"]) == 1)
	_check("fraction, huge number, observer field, dead extraction, and living collapse fail closed",
		Contract.normalize_snapshot(invalid_fraction).is_empty()
		and Contract.normalize_snapshot(invalid_huge).is_empty()
		and Contract.normalize_snapshot(invalid_extra).is_empty()
		and Contract.normalize_snapshot(invalid_collapse).is_empty()
		and Contract.normalize_snapshot(dead_extraction).is_empty()
		and Contract.normalize_snapshot(inventory_overflow).is_empty()
		and Contract.normalize_snapshot(inventory_total_overflow).is_empty())

	var partial_again: Dictionary = Contract.evaluate(briefs["relay_parts"], partial_snapshot)
	_check("same brief + snapshot is idempotent byte for byte",
		JSON.stringify(partial_again) == JSON.stringify(partial))
	_check("alternative outcomes share one owner settlement key",
		partial["settlement_key"] == collapse["settlement_key"]
		and partial["outcome_id"] != collapse["outcome_id"])
	var tampered_outcome: Dictionary = partial.duplicate(true)
	(tampered_outcome["settlement"] as Dictionary)["banked_value"] = 999
	_check("derived settlement tampering fails recomputation",
		not Contract.validate_outcome(briefs["relay_parts"], tampered_outcome).is_empty())

	var receipt: Dictionary = Contract.receipt_summary(partial)
	var receipt_text := Contract.canonical_receipt_json(briefs["relay_parts"], partial, receipt)
	var receipt_json: Variant = JSON.parse_string(receipt_text)
	var receipt_binary: Variant = bytes_to_var(var_to_bytes(receipt))
	_check("receipt survives JSON and Variant binary roundtrips",
		receipt_json is Dictionary and receipt_binary is Dictionary
		and Contract.validate_receipt_summary(briefs["relay_parts"], partial, receipt_json).is_empty()
		and Contract.validate_receipt_summary(briefs["relay_parts"], partial, receipt_binary).is_empty())
	_check("partial outcome has an exact authority-only golden receipt",
		partial["outcome_id"] == "exo1:a28cc2f66e82ee7f"
		and partial["receipt"] == "sha256:a28cc2f66e82ee7fea096838d4b0034f0428d062ea42f4a0eada803af984605d")
	var reordered_receipt := {
		"receipt": receipt["receipt"], "grade": receipt["grade"], "status": receipt["status"],
		"settlement_key": receipt["settlement_key"], "outcome_id": receipt["outcome_id"],
		"contract_id": receipt["contract_id"], "schema": receipt["schema"],
	}
	_check("canonical expedition receipt ignores Dictionary insertion order",
		Contract.canonical_receipt_json(briefs["relay_parts"], partial, reordered_receipt) == receipt_text)
	var bad_receipt: Dictionary = receipt.duplicate(true)
	bad_receipt["status"] = "success"
	_check("receipt summary tampering fails closed",
		not Contract.validate_receipt_summary(briefs["relay_parts"], partial, bad_receipt).is_empty()
		and not Contract.validate_receipt_summary(briefs["field_medicine"], partial, receipt).is_empty())
	_check("brief and outcome authority survive Variant roundtrip",
		Contract.validate_brief(bytes_to_var(var_to_bytes(briefs["relay_parts"]))).is_empty()
		and Contract.validate_outcome(briefs["relay_parts"], bytes_to_var(var_to_bytes(partial))).is_empty())
	var json_brief: Variant = JSON.parse_string(JSON.stringify(briefs["relay_parts"]))
	var json_snapshot: Variant = JSON.parse_string(JSON.stringify(partial_snapshot))
	var json_outcome: Variant = JSON.parse_string(JSON.stringify(partial))
	_check("full brief, snapshot, and outcome survive Godot JSON number decoding",
		json_brief is Dictionary and json_snapshot is Dictionary and json_outcome is Dictionary
		and Contract.validate_brief(json_brief).is_empty()
		and not Contract.normalize_snapshot(json_snapshot).is_empty()
		and Contract.validate_outcome(json_brief, json_outcome).is_empty())

	var lab = MapTileModel.new(81426)
	lab.caravan_tile = Vector2i(7, 2)
	lab.selected_tile = lab.caravan_tile
	lab.plan_route(lab.caravan_tile)
	lab.enter_local()
	_take_kind(lab, "meds", 2)
	lab.health = 86
	lab.local_turns = 29
	lab.noise = 2
	var first_threat: Dictionary = lab.threats[0]
	first_threat["dead"] = true
	lab.threats[0] = first_threat
	lab.inventory["scrap"] = 1
	lab.cargo_value += 8
	lab.cargo_weight += 0.4
	lab.player = lab.extraction
	var lab_before := _lab_receipt(lab)
	var terminal_witness: Dictionary = Adapter.begin_terminal(lab, 8)
	var lab_after := _lab_receipt(lab)
	_check("MapTile adapter begins from a real, internally consistent LOCAL pack",
		not terminal_witness.is_empty() and Adapter.validate_witness(terminal_witness).is_empty()
		and lab_before == lab_after)
	var terminal_witness_json: Variant = JSON.parse_string(JSON.stringify(terminal_witness))
	_check("terminal witness survives Godot JSON number decoding",
		terminal_witness_json is Dictionary and Adapter.validate_witness(terminal_witness_json).is_empty())
	_check("a caller cannot label a still-running LOCAL raid extracted",
		Adapter.complete_terminal(terminal_witness, lab).is_empty())
	var tampered_witness: Dictionary = terminal_witness.duplicate(true)
	tampered_witness["cargo_value"] = int(tampered_witness["cargo_value"]) + 1
	_check("terminal witness tampering fails closed",
		not Adapter.validate_witness(tampered_witness).is_empty())
	_check("MapTile model performs its own real extraction", lab.extract_local())
	var extracted_before_adapter := _lab_receipt(lab)
	var adapted: Dictionary = Adapter.complete_terminal(terminal_witness, lab)
	var extracted_after_adapter := _lab_receipt(lab)
	_check("MapTile adapter verifies the real LOCAL to WORLD extraction",
		int((adapted["inventory"] as Dictionary)["meds"]) == 2
		and int(adapted["cargo_value"]) == 78 and int(adapted["cargo_weight_grams"]) == 1800
		and int(adapted["health"]) == 86 and int(adapted["turns"]) == 29
		and int(adapted["peak_noise"]) == 8 and int(adapted["threats_neutralized"]) == 1)
	_check("MapTile terminal verification is observation-only",
		extracted_before_adapter == extracted_after_adapter)
	var adapted_outcome: Dictionary = Contract.evaluate(briefs["field_medicine"], adapted)
	_check("an adapted real-lab snapshot evaluates without special casing",
		adapted_outcome.get("status") == "success"
		and Contract.validate_outcome(briefs["field_medicine"], adapted_outcome).is_empty())

	var collapsed_lab = MapTileModel.new(81426)
	collapsed_lab.caravan_tile = Vector2i(7, 2)
	collapsed_lab.selected_tile = collapsed_lab.caravan_tile
	collapsed_lab.plan_route(collapsed_lab.caravan_tile)
	collapsed_lab.enter_local()
	_take_kind(collapsed_lab, "parts", 1)
	collapsed_lab.health = 7
	collapsed_lab.local_turns = 1
	var collapse_threat: Dictionary = collapsed_lab.threats[0]
	collapse_threat["pos"] = collapsed_lab.player
	collapse_threat["alerted"] = true
	collapsed_lab.threats[0] = collapse_threat
	var collapse_witness: Dictionary = Adapter.begin_terminal(collapsed_lab, 4)
	collapsed_lab._spend_turn(10)
	var collapsed_before_adapter := _lab_receipt(collapsed_lab)
	var adapted_collapse: Dictionary = Adapter.complete_terminal(collapse_witness, collapsed_lab)
	var collapsed_after_adapter := _lab_receipt(collapsed_lab)
	var collapsed_outcome: Dictionary = Contract.evaluate(briefs["relay_parts"], adapted_collapse)
	_check("real MapTile collapse preserves pre-clear cargo as lost evidence",
		collapsed_lab.mode == MapTileModel.Mode.WORLD and collapsed_lab.health == 0
		and int((adapted_collapse["inventory"] as Dictionary)["parts"]) == 1
		and int(adapted_collapse["cargo_value"]) > 0
		and collapsed_outcome.get("status") == "collapse"
		and int((collapsed_outcome["settlement"] as Dictionary)["lost_value"]) == int(adapted_collapse["cargo_value"])
		and collapsed_before_adapter == collapsed_after_adapter)

	_check("resource-pool manifest records RP-0002", _manifest_has_batch("RP-0002"))
	print("EXPEDITION_CONTRACT_RECEIPT=%s" % receipt_text)
	print("expedition_contract_test: %s (%d fail, %d checks)" % [
		("PASS" if _fails == 0 else "FAIL"), _fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _inventory(food: int, meds: int, parts: int, scrap: int) -> Dictionary:
	return {"food": food, "meds": meds, "parts": parts, "scrap": scrap}


func _take_kind(lab, kind: String, count: int) -> void:
	var taken := 0
	for i in lab.loot.size():
		var item: Dictionary = lab.loot[i]
		if taken >= count or bool(item.get("taken", false)) or String(item.get("kind", "")) != kind:
			continue
		item["taken"] = true
		lab.loot[i] = item
		lab.inventory[kind] = int(lab.inventory.get(kind, 0)) + 1
		lab.cargo_value += int(item["value"])
		lab.cargo_weight += float(item["weight"])
		taken += 1


func _profile_exact(brief: Dictionary, value: int, weight: int, noise: int) -> bool:
	var profile: Dictionary = brief["profile"]
	return int(profile["value"]) == value and int(profile["weight_grams"]) == weight \
		and int(profile["noise"]) == noise


func _lines_contain(lines: Variant, fragment: String) -> bool:
	if not (lines is Array):
		return false
	for line in lines:
		if fragment in String(line).to_lower():
			return true
	return false


func _lab_receipt(lab) -> String:
	return JSON.stringify({
		"inventory": lab.inventory,
		"cargo_value": lab.cargo_value,
		"cargo_weight": lab.cargo_weight,
		"health": lab.health,
		"turns": lab.local_turns,
		"noise": lab.noise,
		"threats": lab.threats,
		"mode": lab.mode,
		"world_hour": lab.world_hour,
		"stash_value": lab.stash_value,
		"supplies": lab.supplies,
		"condition": lab.condition,
		"morale": lab.morale,
	})


func _manifest_has_batch(batch_id: String) -> bool:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		return false
	var batches: Variant = (parsed as Dictionary).get("batches")
	if not (batches is Array):
		return false
	for raw_batch in batches:
		if raw_batch is Dictionary and (raw_batch as Dictionary).get("id") == batch_id:
			return true
	return false
