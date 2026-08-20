extends RefCounted

## Pure expedition brief -> raid snapshot -> causal debrief contract.
##
## This utility never mutates a caravan, stash, resident, clock, or Sim.  It
## produces a deterministic settlement key and a fully recomputable outcome;
## an eventual authority owner must still validate and commit that key once.

const ScaleAddress = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")

const BRIEF_SCHEMA := "living-town.expedition-brief/v1"
const SNAPSHOT_SCHEMA := "living-town.expedition-snapshot/v1"
const OUTCOME_SCHEMA := "living-town.expedition-outcome/v1"
const RECEIPT_SCHEMA := "living-town.expedition-receipt/v1"
const TERMS_VERSION := "ash-market-v1"

const RESOLUTION_EXTRACTED := "extracted"
const RESOLUTION_COLLAPSED := "collapsed"
const INVENTORY_KINDS := ["food", "meds", "parts", "scrap"]
const MAX_INVENTORY_COUNT := 64
const MAX_TOTAL_INVENTORY := 128
const MAX_SAFE_JSON_INT := 9007199254740991

const TEMPLATES := {
	"field_medicine": {
		"title": "BRING BACK CLINIC STOCK",
		"objective": {"kind": "meds", "required": 2, "label": "medical caches"},
		"constraint": {"kind": "health_floor", "value": 70, "label": "return with crew health 70+"},
		"profile": {"value": 70, "weight_grams": 1400, "noise": 3, "location": "east field clinic"},
		"stakes": "The next injury becomes a crisis without antiseptic and trauma dressings.",
		"choice_hint": "Light and valuable, but both caches sit beyond the main road.",
	},
	"winter_rations": {
		"title": "PROVISION THE RETURN ROAD",
		"objective": {"kind": "food", "required": 2, "label": "ration caches"},
		"constraint": {"kind": "turn_ceiling", "value": 40, "label": "extract within 40 turns"},
		"profile": {"value": 38, "weight_grams": 2600, "noise": 4, "location": "store and south tenement"},
		"stakes": "Recovered food repays expedition supply instead of merely raising stash value.",
		"choice_hint": "The caches are split; a long sweep gains endurance but burns daylight.",
	},
	"relay_parts": {
		"title": "REPAIR THE LONG-RANGE RELAY",
		"objective": {"kind": "parts", "required": 2, "label": "machine-part caches"},
		"constraint": {"kind": "weight_ceiling", "value": 4000, "label": "keep total pack at or below 4.0 kg"},
		"profile": {"value": 91, "weight_grams": 3500, "noise": 8, "location": "locksmith and south tenement"},
		"stakes": "The caravan cannot navigate the next region while its relay remains intermittent.",
		"choice_hint": "Highest value and noise; extra opportunistic loot can break the pack limit.",
	},
}


static func mission_ids() -> Array[String]:
	return ["field_medicine", "winter_rations", "relay_parts"]


static func make_brief(root_seed: int, destination_id: String, mission_id: String,
		offer_slot: String = "lab-board-a") -> Dictionary:
	var destination := ScaleAddress.parse_id(destination_id)
	if ScaleAddress.level_of(destination) != ScaleAddress.LEVEL_SITE \
			or not TEMPLATES.has(mission_id) or not _slot_valid(offer_slot):
		return {}
	var purpose := "brief-%s-%s-%s" % [TERMS_VERSION, mission_id, offer_slot]
	var token := ScaleAddress.seed_token_for(root_seed, destination, purpose)
	if token == "":
		return {}
	var template: Dictionary = (TEMPLATES[mission_id] as Dictionary).duplicate(true)
	return {
		"schema": BRIEF_SCHEMA,
		"contract_id": "exp1:" + token.substr(4),
		"terms_version": TERMS_VERSION,
		"root_seed": "i64:%d" % root_seed,
		"destination": ScaleAddress.canonical_id(destination),
		"mission": mission_id,
		"offer_slot": offer_slot,
		"title": String(template["title"]),
		"objective": (template["objective"] as Dictionary).duplicate(true),
		"constraint": (template["constraint"] as Dictionary).duplicate(true),
		"profile": (template["profile"] as Dictionary).duplicate(true),
		"stakes": String(template["stakes"]),
		"choice_hint": String(template["choice_hint"]),
	}


static func validate_brief(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (value is Dictionary):
		return ["brief must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "contract_id", "terms_version", "root_seed", "destination", "mission", "offer_slot",
		"title", "objective", "constraint", "profile", "stakes", "choice_hint"]
	if not _exact_keys(data, required):
		errors.append("brief fields must match the V1 envelope exactly")
	for key in ["schema", "contract_id", "terms_version", "root_seed", "destination", "mission", "offer_slot",
			"title", "stakes", "choice_hint"]:
		if not data.has(key) or typeof(data[key]) != TYPE_STRING:
			errors.append("brief field '%s' must be a String" % key)
	for key in ["objective", "constraint", "profile"]:
		if not data.has(key) or not (data[key] is Dictionary):
			errors.append("brief field '%s' must be a Dictionary" % key)
	if not errors.is_empty():
		return errors
	var root_seed := _root_seed(String(data["root_seed"]))
	if root_seed.is_empty():
		return ["root_seed must be a canonical i64 token"]
	var expected := make_brief(int(root_seed[0]), String(data["destination"]),
		String(data["mission"]), String(data["offer_slot"]))
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		errors.append("brief does not match its deterministic contract")
	return errors


static func make_snapshot(resolution: String, inventory: Dictionary, cargo_value: int,
		cargo_weight_grams: int, health: int, turns: int, peak_noise: int,
		threats_neutralized: int, supply_before_tenths: int = 120) -> Dictionary:
	var raw := {
		"schema": SNAPSHOT_SCHEMA,
		"resolution": resolution,
		"inventory": inventory.duplicate(true),
		"cargo_value": cargo_value,
		"cargo_weight_grams": cargo_weight_grams,
		"health": health,
		"turns": turns,
		"peak_noise": peak_noise,
		"threats_neutralized": threats_neutralized,
		"supply_before_tenths": supply_before_tenths,
	}
	return normalize_snapshot(raw)


static func normalize_snapshot(value: Variant) -> Dictionary:
	if not validate_snapshot(value).is_empty():
		return {}
	var data: Dictionary = value
	var inventory: Dictionary = data["inventory"]
	return {
		"schema": SNAPSHOT_SCHEMA,
		"resolution": String(data["resolution"]),
		"inventory": {
			"food": int(inventory["food"]),
			"meds": int(inventory["meds"]),
			"parts": int(inventory["parts"]),
			"scrap": int(inventory["scrap"]),
		},
		"cargo_value": int(data["cargo_value"]),
		"cargo_weight_grams": int(data["cargo_weight_grams"]),
		"health": int(data["health"]),
		"turns": int(data["turns"]),
		"peak_noise": int(data["peak_noise"]),
		"threats_neutralized": int(data["threats_neutralized"]),
		"supply_before_tenths": int(data["supply_before_tenths"]),
	}


static func validate_snapshot(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (value is Dictionary):
		return ["snapshot must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "resolution", "inventory", "cargo_value", "cargo_weight_grams",
		"health", "turns", "peak_noise", "threats_neutralized", "supply_before_tenths"]
	if not _exact_keys(data, required):
		errors.append("snapshot fields must match the V1 envelope exactly")
	if data.get("schema") != SNAPSHOT_SCHEMA:
		errors.append("snapshot schema mismatch")
	var resolution := _string_if(data.get("resolution"))
	if typeof(data.get("resolution")) != TYPE_STRING \
			or resolution not in [RESOLUTION_EXTRACTED, RESOLUTION_COLLAPSED]:
		errors.append("snapshot resolution must be extracted|collapsed")
	var inventory_value: Variant = data.get("inventory")
	if not (inventory_value is Dictionary):
		errors.append("snapshot inventory must be a Dictionary")
	else:
		var inventory: Dictionary = inventory_value
		if not _exact_keys(inventory, INVENTORY_KINDS):
			errors.append("snapshot inventory kinds must be exact")
		for kind in INVENTORY_KINDS:
			if not inventory.has(kind) or not _bounded_integer(inventory[kind], 0, MAX_INVENTORY_COUNT):
				errors.append("inventory.%s must be an integer from 0 through %d" % [kind, MAX_INVENTORY_COUNT])
		var total_inventory := 0
		for kind in INVENTORY_KINDS:
			if inventory.has(kind) and _bounded_integer(inventory[kind], 0, MAX_INVENTORY_COUNT):
				total_inventory += int(inventory[kind])
		if total_inventory > MAX_TOTAL_INVENTORY:
			errors.append("snapshot inventory total exceeds %d" % MAX_TOTAL_INVENTORY)
	var ranges := {
		"cargo_value": Vector2i(0, 1000000000),
		"cargo_weight_grams": Vector2i(0, 1000000000),
		"health": Vector2i(0, 100),
		"turns": Vector2i(0, 1000000),
		"peak_noise": Vector2i(0, 10),
		"threats_neutralized": Vector2i(0, 10000),
		"supply_before_tenths": Vector2i(0, 240),
	}
	for key in ranges:
		var limits: Vector2i = ranges[key]
		if not _bounded_integer(data.get(key), limits.x, limits.y):
			errors.append("snapshot.%s is out of range or not an integer" % key)
	if resolution == RESOLUTION_COLLAPSED \
			and (not _bounded_integer(data.get("health"), 0, 100) or int(data.get("health")) != 0):
		errors.append("collapsed snapshots must have zero health")
	if resolution == RESOLUTION_EXTRACTED \
			and (not _bounded_integer(data.get("health"), 0, 100) or int(data.get("health")) == 0):
		errors.append("extracted snapshots must have positive health")
	return errors


static func evaluate(brief: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not validate_brief(brief).is_empty():
		return {}
	var normalized_snapshot := normalize_snapshot(snapshot)
	if normalized_snapshot.is_empty():
		return {}
	var objective: Dictionary = brief["objective"]
	var constraint: Dictionary = brief["constraint"]
	var inventory: Dictionary = normalized_snapshot["inventory"]
	var objective_kind := String(objective["kind"])
	var required := int(objective["required"])
	var carried := int(inventory[objective_kind])
	var extracted := String(normalized_snapshot["resolution"]) == RESOLUTION_EXTRACTED
	var delivered := carried if extracted else 0
	var status := "retreat"
	if not extracted:
		status = "collapse"
	elif delivered >= required:
		status = "success"
	elif delivered > 0:
		status = "partial"

	var constraint_result := _constraint_result(constraint, normalized_snapshot)
	var grade := "empty"
	if status == "collapse":
		grade = "lost"
	elif status == "partial":
		grade = "incomplete"
	elif status == "success":
		grade = "clean" if bool(constraint_result["passed"]) else "strained"

	var cargo_value := int(normalized_snapshot["cargo_value"])
	var supply_before := int(normalized_snapshot["supply_before_tenths"])
	var supply_gain := mini(int(inventory["food"]) * 15, 240 - supply_before) if extracted else 0
	var settlement := {
		"banked_value": cargo_value if extracted else 0,
		"lost_value": 0 if extracted else cargo_value,
		"supply_before_tenths": supply_before,
		"supply_gain_tenths": supply_gain,
		"supply_after_tenths": supply_before + supply_gain,
	}
	var objective_result := {
		"kind": objective_kind,
		"label": String(objective["label"]),
		"required": required,
		"carried": carried,
		"delivered": delivered,
		"missing": maxi(0, required - delivered),
	}
	var reason_codes := _reason_codes(status, constraint_result, normalized_snapshot)
	var lines := _debrief_lines(status, objective_result, settlement, constraint_result, normalized_snapshot)
	var base := {
		"schema": OUTCOME_SCHEMA,
		"contract_id": String(brief["contract_id"]),
		"settlement_key": "exps1:" + String(brief["contract_id"]).substr(5),
		"destination": String(brief["destination"]),
		"mission": String(brief["mission"]),
		"status": status,
		"grade": grade,
		"headline": _headline(status, grade),
		"objective": objective_result,
		"constraint": constraint_result,
		"settlement": settlement,
		"metrics": {
			"health_lost": 100 - int(normalized_snapshot["health"]),
			"minutes_elapsed": int(normalized_snapshot["turns"]) * 6,
			"peak_noise": int(normalized_snapshot["peak_noise"]),
			"threats_neutralized": int(normalized_snapshot["threats_neutralized"]),
			"cargo_weight_grams": int(normalized_snapshot["cargo_weight_grams"]),
		},
		"reason_codes": reason_codes,
		"lines": lines,
		"snapshot": normalized_snapshot,
	}
	var authority := {
		"schema": OUTCOME_SCHEMA,
		"contract_id": base["contract_id"],
		"settlement_key": base["settlement_key"],
		"destination": base["destination"],
		"mission": base["mission"],
		"status": status,
		"grade": grade,
		"objective": {
			"kind": objective_result["kind"], "required": objective_result["required"],
			"carried": objective_result["carried"], "delivered": objective_result["delivered"],
			"missing": objective_result["missing"],
		},
		"constraint": {
			"kind": constraint_result["kind"], "limit": constraint_result["limit"],
			"actual": constraint_result["actual"], "passed": constraint_result["passed"],
		},
		"settlement": settlement,
		"metrics": base["metrics"],
		"reason_codes": reason_codes,
		"snapshot": normalized_snapshot,
	}
	var digest := _sha256_hex(_canonical_json(authority))
	if digest == "":
		return {}
	base["outcome_id"] = "exo1:" + digest.substr(0, 16)
	base["receipt"] = "sha256:" + digest
	return base


static func validate_outcome(brief: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["outcome must be a Dictionary"]
	var data: Dictionary = value
	if not (data.get("snapshot") is Dictionary):
		return ["outcome.snapshot must be a Dictionary"]
	var expected := evaluate(brief, data["snapshot"])
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(data):
		return ["outcome does not recompute from brief + snapshot"]
	return []


static func receipt_summary(outcome: Dictionary) -> Dictionary:
	if not outcome.has("receipt"):
		return {}
	return {
		"schema": RECEIPT_SCHEMA,
		"contract_id": String(outcome.get("contract_id", "")),
		"outcome_id": String(outcome.get("outcome_id", "")),
		"settlement_key": String(outcome.get("settlement_key", "")),
		"status": String(outcome.get("status", "")),
		"grade": String(outcome.get("grade", "")),
		"receipt": String(outcome.get("receipt", "")),
	}


static func validate_receipt_summary(brief: Dictionary, outcome: Dictionary, value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["receipt summary must be a Dictionary"]
	if not validate_outcome(brief, outcome).is_empty():
		return ["receipt summary requires a valid brief + outcome"]
	var expected := receipt_summary(outcome)
	if expected.is_empty() or _canonical_json(expected) != _canonical_json(value):
		return ["receipt summary does not match its outcome"]
	return []


static func canonical_receipt_json(brief: Dictionary, outcome: Dictionary, value: Variant) -> String:
	if not validate_receipt_summary(brief, outcome, value).is_empty():
		return ""
	var data: Dictionary = value
	return "{\"schema\":%s,\"contract_id\":%s,\"outcome_id\":%s,\"settlement_key\":%s,\"status\":%s,\"grade\":%s,\"receipt\":%s}" % [
		JSON.stringify(String(data["schema"])), JSON.stringify(String(data["contract_id"])),
		JSON.stringify(String(data["outcome_id"])), JSON.stringify(String(data["settlement_key"])),
		JSON.stringify(String(data["status"])), JSON.stringify(String(data["grade"])),
		JSON.stringify(String(data["receipt"])),
	]


static func _constraint_result(constraint: Dictionary, snapshot: Dictionary) -> Dictionary:
	var kind := String(constraint["kind"])
	var limit := int(constraint["value"])
	var actual := 0
	var passed := false
	match kind:
		"health_floor":
			actual = int(snapshot["health"])
			passed = actual >= limit
		"turn_ceiling":
			actual = int(snapshot["turns"])
			passed = actual <= limit
		"weight_ceiling":
			actual = int(snapshot["cargo_weight_grams"])
			passed = actual <= limit
	return {
		"kind": kind,
		"label": String(constraint["label"]),
		"limit": limit,
		"actual": actual,
		"passed": passed,
	}


static func _reason_codes(status: String, constraint: Dictionary, snapshot: Dictionary) -> Array[String]:
	var codes: Array[String] = []
	codes.append("objective_met" if status == "success" else ("objective_partial" if status == "partial" else "objective_unmet"))
	codes.append("cargo_lost" if status == "collapse" else "cargo_banked")
	if int(snapshot["health"]) < 100:
		codes.append("health_cost")
	if int(snapshot["peak_noise"]) >= 7:
		codes.append("high_noise")
	if int(snapshot["threats_neutralized"]) > 0:
		codes.append("threats_neutralized")
	codes.append("constraint_met" if bool(constraint["passed"]) else "constraint_breached")
	return codes


static func _debrief_lines(status: String, objective: Dictionary, settlement: Dictionary,
		constraint: Dictionary, snapshot: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if status == "collapse":
		lines.append("Carried %d/%d %s; delivered 0 after the raid collapsed." % [
			int(objective["carried"]), int(objective["required"]), String(objective["label"])])
	else:
		lines.append("Delivered %d/%d %s; %d still missing." % [int(objective["delivered"]),
			int(objective["required"]), String(objective["label"]), int(objective["missing"])])
	if int(settlement["lost_value"]) > 0:
		lines.append("All %d carried value was lost before extraction." % int(settlement["lost_value"]))
	else:
		lines.append("Banked %d value; no carried value was discarded." % int(settlement["banked_value"]))
	if status == "collapse":
		lines.append("Crew hit 0 health after %d minutes; no extraction completed." % (int(snapshot["turns"]) * 6))
	else:
		lines.append("Crew returned at %d health after %d minutes." % [int(snapshot["health"]), int(snapshot["turns"]) * 6])
	lines.append("Peak noise %d; %d threats neutralized." % [int(snapshot["peak_noise"]), int(snapshot["threats_neutralized"])])
	lines.append("Constraint %s: %s (%s vs %s limit)." % [
		("held" if bool(constraint["passed"]) else "breached"), String(constraint["label"]),
		_constraint_value(String(constraint["kind"]), int(constraint["actual"])),
		_constraint_value(String(constraint["kind"]), int(constraint["limit"]))])
	if int(settlement["supply_gain_tenths"]) > 0:
		lines.append("Recovered food adds %.1f caravan supply." % (float(int(settlement["supply_gain_tenths"])) / 10.0))
	return lines


static func _constraint_value(kind: String, value: int) -> String:
	if kind == "weight_ceiling":
		return "%.1f kg" % (float(value) / 1000.0)
	if kind == "turn_ceiling":
		return "%d turns" % value
	return "%d health" % value


static func _headline(status: String, grade: String) -> String:
	if status == "collapse":
		return "EXPEDITION LOST"
	if status == "retreat":
		return "CREW SAFE, OBJECTIVE EMPTY"
	if status == "partial":
		return "PARTIAL DELIVERY"
	return "OBJECTIVE MET" if grade == "clean" else "OBJECTIVE MET AT A COST"


static func _sha256_hex(text: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


static func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size():
		return false
	for key in required:
		if not data.has(key):
			return false
	return true


static func _slot_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 24:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		var lower := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not (lower or digit or (i > 0 and (code == 45 or code == 95))):
			return false
	return true


static func _root_seed(token: String) -> Array:
	if not token.begins_with("i64:"):
		return []
	var number := token.substr(4)
	if not _canonical_i64(number):
		return []
	return [int(number)]


static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) \
		and number >= float(minimum) and number <= float(maximum)


static func _canonical_i64(value: String) -> bool:
	if value == "0":
		return true
	if value.is_empty() or value.length() > 20:
		return false
	var first_digit := 0
	if value[0] == "-":
		if value.length() == 1 or value[1] == "0":
			return false
		first_digit = 1
	elif value[0] == "0":
		return false
	for i in range(first_digit, value.length()):
		var code := value.unicode_at(i)
		if code < 48 or code > 57:
			return false
	var magnitude := value.substr(first_digit)
	var limit := "9223372036854775808" if first_digit == 1 else "9223372036854775807"
	if magnitude.length() != limit.length():
		return magnitude.length() < limit.length()
	for i in magnitude.length():
		var digit := magnitude.unicode_at(i)
		var limit_digit := limit.unicode_at(i)
		if digit != limit_digit:
			return digit < limit_digit
	return true


## Stable JSON subset used for IDs and semantic equality. Dictionary keys sort
## lexically; JSON integral floats normalize to integers after the validators
## have bounded them. No caller relies on Dictionary insertion order.
static func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number) or number != floor(number) or absf(number) > float(MAX_SAFE_JSON_INT):
				return ""
			return str(int(number))
		TYPE_STRING:
			return JSON.stringify(String(value))
		TYPE_ARRAY:
			var items: Array[String] = []
			for item in value as Array:
				var encoded := _canonical_json(item)
				if encoded == "":
					return ""
				items.append(encoded)
			return "[" + ",".join(items) + "]"
		TYPE_DICTIONARY:
			var data: Dictionary = value
			var keys: Array[String] = []
			for raw_key in data:
				if typeof(raw_key) != TYPE_STRING:
					return ""
				keys.append(String(raw_key))
			keys.sort()
			var fields: Array[String] = []
			for key in keys:
				var encoded := _canonical_json(data[key])
				if encoded == "":
					return ""
				fields.append("%s:%s" % [JSON.stringify(key), encoded])
			return "{" + ",".join(fields) + "}"
	return ""


static func _string_if(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return value
	return ""
