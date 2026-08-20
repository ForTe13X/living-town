extends RefCounted

## Two-phase, read-only bridge around a real MapTileLab terminal transition.
##
## A caller first records begin_terminal() while the model is LOCAL, performs
## the model's own action, then calls complete_terminal().  The result is
## inferred from the observed LOCAL -> WORLD transition; callers cannot label a
## still-running raid "extracted".  Collapse cargo is reconstructed from the
## lab's persistent taken/dead content flags because MapTileLab clears its pack.
## Neither function mutates the model or applies settlement a second time.

const ExpeditionContract = preload("res://scripts/labs/resource_pool/ExpeditionContract.gd")

const WITNESS_SCHEMA := "living-town.map-tile-terminal-witness/v1"
const MODE_WORLD := 0
const MODE_LOCAL := 1
const INVENTORY_KINDS := ["food", "meds", "parts", "scrap"]
const THREAT_SCRAP_VALUE := 8
const THREAT_SCRAP_GRAMS := 400


static func begin_terminal(model: Variant, peak_noise: int) -> Dictionary:
	if not _model_shape_valid(model) or int(model.get("mode")) != MODE_LOCAL:
		return {}
	var health := int(model.get("health"))
	var turns := int(model.get("local_turns"))
	var current_noise := int(model.get("noise"))
	var site_title_value: Variant = model.get("site_title")
	if health <= 0 or health > 100 or turns < 0 or current_noise < 0 or current_noise > 10 \
			or peak_noise < current_noise or peak_noise > 10 \
			or typeof(site_title_value) != TYPE_STRING or String(site_title_value).is_empty():
		return {}
	var content := _reconstruct_content(model)
	if content.is_empty() or not _current_pack_matches(model, content):
		return {}
	var base := {
		"schema": WITNESS_SCHEMA,
		"site_title": String(site_title_value),
		"turns": turns,
		"health": health,
		"peak_noise": peak_noise,
		"inventory": (content["inventory"] as Dictionary).duplicate(true),
		"cargo_value": int(content["cargo_value"]),
		"cargo_weight_grams": int(content["cargo_weight_grams"]),
		"threats_neutralized": int(content["threats_neutralized"]),
		"can_extract": model.get("player") == model.get("extraction"),
		"stash_before": int(model.get("stash_value")),
		"supplies_before_tenths": roundi(float(model.get("supplies")) * 10.0),
		"condition_before_tenths": roundi(float(model.get("condition")) * 10.0),
		"morale_before_tenths": roundi(float(model.get("morale")) * 10.0),
	}
	base["receipt"] = _witness_receipt(base)
	return base


static func validate_witness(value: Variant) -> Array[String]:
	if not (value is Dictionary):
		return ["terminal witness must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "site_title", "turns", "health", "peak_noise", "inventory",
		"cargo_value", "cargo_weight_grams", "threats_neutralized", "can_extract",
		"stash_before", "supplies_before_tenths", "condition_before_tenths",
		"morale_before_tenths", "receipt"]
	if not _exact_keys(data, required):
		return ["terminal witness fields must match V1 exactly"]
	if data.get("schema") != WITNESS_SCHEMA or typeof(data.get("site_title")) != TYPE_STRING \
			or String(data.get("site_title")).is_empty() or typeof(data.get("can_extract")) != TYPE_BOOL \
			or typeof(data.get("receipt")) != TYPE_STRING:
		return ["terminal witness scalar type mismatch"]
	var ranges := {
		"turns": Vector2i(0, 1000000), "health": Vector2i(1, 100),
		"peak_noise": Vector2i(0, 10), "cargo_value": Vector2i(0, 1000000000),
		"cargo_weight_grams": Vector2i(0, 1000000000),
		"threats_neutralized": Vector2i(0, 10000), "stash_before": Vector2i(0, 1000000000),
		"supplies_before_tenths": Vector2i(0, 240),
		"condition_before_tenths": Vector2i(0, 1000),
		"morale_before_tenths": Vector2i(0, 1000),
	}
	for key in ranges:
		var limits: Vector2i = ranges[key]
		if not _bounded_integer(data.get(key), limits.x, limits.y):
			return ["terminal witness field '%s' is out of range" % key]
	var inventory_value: Variant = data.get("inventory")
	if not _inventory_valid(inventory_value):
		return ["terminal witness inventory mismatch"]
	var base := data.duplicate(true)
	base.erase("receipt")
	if String(data["receipt"]) != _witness_receipt(base):
		return ["terminal witness receipt mismatch"]
	return []


static func complete_terminal(witness: Dictionary, model: Variant) -> Dictionary:
	if not validate_witness(witness).is_empty() or not _model_shape_valid(model) \
			or int(model.get("mode")) != MODE_WORLD \
			or String(model.get("site_title")) != String(witness["site_title"]):
		return {}
	var post_turns := int(model.get("local_turns"))
	var post_health := int(model.get("health"))
	var post_noise := int(model.get("noise"))
	if post_turns < int(witness["turns"]) or post_health < 0 or post_health > 100 \
			or post_noise < 0 or post_noise > 10:
		return {}
	var peak_noise := maxi(int(witness["peak_noise"]), post_noise)
	var content := _reconstruct_content(model)
	if content.is_empty():
		return {}
	var before_content := {
		"inventory": (witness["inventory"] as Dictionary).duplicate(true),
		"cargo_value": int(witness["cargo_value"]),
		"cargo_weight_grams": int(witness["cargo_weight_grams"]),
		"threats_neutralized": int(witness["threats_neutralized"]),
	}
	var supplies_after := roundi(float(model.get("supplies")) * 10.0)
	var condition_after := roundi(float(model.get("condition")) * 10.0)
	var morale_after := roundi(float(model.get("morale")) * 10.0)
	if post_health == 0:
		if not _pack_is_cleared(model) or int(model.get("stash_value")) != int(witness["stash_before"]) \
				or supplies_after != int(witness["supplies_before_tenths"]) \
				or condition_after != maxi(0, int(witness["condition_before_tenths"]) - 120) \
				or morale_after != maxi(0, int(witness["morale_before_tenths"]) - 180) \
				or not _content_contains(content, before_content):
			return {}
		return ExpeditionContract.make_snapshot(ExpeditionContract.RESOLUTION_COLLAPSED,
			content["inventory"], int(content["cargo_value"]), int(content["cargo_weight_grams"]),
			0, post_turns, peak_noise, int(content["threats_neutralized"]),
			int(witness["supplies_before_tenths"]))

	if not bool(witness["can_extract"]) or model.get("player") != model.get("extraction") \
			or post_turns != int(witness["turns"]) or post_health != int(witness["health"]) \
			or not _content_equal(content, before_content) or not _current_pack_matches(model, content) \
			or int(model.get("stash_value")) != int(witness["stash_before"]) + int(witness["cargo_value"]) \
			or condition_after != int(witness["condition_before_tenths"]) \
			or morale_after != int(witness["morale_before_tenths"]):
		return {}
	var inventory: Dictionary = witness["inventory"]
	var expected_supplies := mini(240, int(witness["supplies_before_tenths"]) + int(inventory["food"]) * 15)
	if supplies_after != expected_supplies:
		return {}
	return ExpeditionContract.make_snapshot(ExpeditionContract.RESOLUTION_EXTRACTED,
		inventory, int(witness["cargo_value"]), int(witness["cargo_weight_grams"]), post_health,
		post_turns, peak_noise, int(witness["threats_neutralized"]),
		int(witness["supplies_before_tenths"]))


static func _model_shape_valid(model: Variant) -> bool:
	if model == null or not (model is Object):
		return false
	return model.get("inventory") is Dictionary and model.get("loot") is Array \
		and model.get("threats") is Array and typeof(model.get("mode")) == TYPE_INT \
		and typeof(model.get("health")) == TYPE_INT and typeof(model.get("local_turns")) == TYPE_INT \
		and typeof(model.get("noise")) == TYPE_INT and typeof(model.get("cargo_value")) == TYPE_INT \
		and typeof(model.get("cargo_weight")) == TYPE_FLOAT and typeof(model.get("stash_value")) == TYPE_INT \
		and typeof(model.get("supplies")) == TYPE_FLOAT and typeof(model.get("condition")) == TYPE_FLOAT \
		and typeof(model.get("morale")) == TYPE_FLOAT


static func _reconstruct_content(model: Variant) -> Dictionary:
	var inventory := {"food": 0, "meds": 0, "parts": 0, "scrap": 0}
	var cargo_value := 0
	var cargo_weight_grams := 0
	var loot_value: Variant = model.get("loot")
	var threats_value: Variant = model.get("threats")
	if not (loot_value is Array) or not (threats_value is Array):
		return {}
	for raw_item in loot_value as Array:
		if not (raw_item is Dictionary):
			return {}
		var item: Dictionary = raw_item
		if not bool(item.get("taken", false)):
			continue
		var kind_value: Variant = item.get("kind")
		var value_value: Variant = item.get("value")
		var weight_value: Variant = item.get("weight")
		if typeof(kind_value) != TYPE_STRING or String(kind_value) not in INVENTORY_KINDS \
				or typeof(value_value) != TYPE_INT or int(value_value) < 0 \
				or typeof(weight_value) != TYPE_FLOAT or not is_finite(float(weight_value)) \
				or float(weight_value) < 0.0:
			return {}
		var kind := String(kind_value)
		inventory[kind] = int(inventory[kind]) + 1
		cargo_value += int(value_value)
		cargo_weight_grams += roundi(float(weight_value) * 1000.0)
	var threats_neutralized := 0
	for raw_threat in threats_value as Array:
		if not (raw_threat is Dictionary):
			return {}
		if bool((raw_threat as Dictionary).get("dead", false)):
			threats_neutralized += 1
			inventory["scrap"] = int(inventory["scrap"]) + 1
			cargo_value += THREAT_SCRAP_VALUE
			cargo_weight_grams += THREAT_SCRAP_GRAMS
	return {
		"inventory": inventory,
		"cargo_value": cargo_value,
		"cargo_weight_grams": cargo_weight_grams,
		"threats_neutralized": threats_neutralized,
	}


static func _current_pack_matches(model: Variant, content: Dictionary) -> bool:
	var current_value: Variant = model.get("inventory")
	if not _inventory_valid(current_value):
		return false
	var current: Dictionary = current_value
	var expected: Dictionary = content["inventory"]
	for kind in INVENTORY_KINDS:
		if int(current[kind]) != int(expected[kind]):
			return false
	return int(model.get("cargo_value")) == int(content["cargo_value"]) \
		and roundi(float(model.get("cargo_weight")) * 1000.0) == int(content["cargo_weight_grams"])


static func _pack_is_cleared(model: Variant) -> bool:
	var inventory_value: Variant = model.get("inventory")
	if not _inventory_valid(inventory_value) or int(model.get("cargo_value")) != 0 \
			or roundi(float(model.get("cargo_weight")) * 1000.0) != 0:
		return false
	for kind in INVENTORY_KINDS:
		if int((inventory_value as Dictionary)[kind]) != 0:
			return false
	return true


static func _inventory_valid(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var inventory: Dictionary = value
	if not _exact_keys(inventory, INVENTORY_KINDS):
		return false
	for kind in INVENTORY_KINDS:
		if not _bounded_integer(inventory.get(kind), 0, ExpeditionContract.MAX_INVENTORY_COUNT):
			return false
	return true


static func _content_equal(left: Dictionary, right: Dictionary) -> bool:
	if int(left["cargo_value"]) != int(right["cargo_value"]) \
			or int(left["cargo_weight_grams"]) != int(right["cargo_weight_grams"]) \
			or int(left["threats_neutralized"]) != int(right["threats_neutralized"]):
		return false
	var left_inventory: Dictionary = left["inventory"]
	var right_inventory: Dictionary = right["inventory"]
	for kind in INVENTORY_KINDS:
		if int(left_inventory[kind]) != int(right_inventory[kind]):
			return false
	return true


static func _content_contains(current: Dictionary, before: Dictionary) -> bool:
	if int(current["cargo_value"]) < int(before["cargo_value"]) \
			or int(current["cargo_weight_grams"]) < int(before["cargo_weight_grams"]) \
			or int(current["threats_neutralized"]) < int(before["threats_neutralized"]):
		return false
	var current_inventory: Dictionary = current["inventory"]
	var before_inventory: Dictionary = before["inventory"]
	for kind in INVENTORY_KINDS:
		if int(current_inventory[kind]) < int(before_inventory[kind]):
			return false
	return true


static func _witness_receipt(base: Dictionary) -> String:
	var inventory: Dictionary = base["inventory"]
	var fields := [
		String(base["schema"]), String(base["site_title"]), str(int(base["turns"])),
		str(int(base["health"])), str(int(base["peak_noise"])),
		str(int(inventory["food"])), str(int(inventory["meds"])),
		str(int(inventory["parts"])), str(int(inventory["scrap"])),
		str(int(base["cargo_value"])), str(int(base["cargo_weight_grams"])),
		str(int(base["threats_neutralized"])), "1" if bool(base["can_extract"]) else "0",
		str(int(base["stash_before"])), str(int(base["supplies_before_tenths"])),
		str(int(base["condition_before_tenths"])), str(int(base["morale_before_tenths"])),
	]
	var material := ""
	for field in fields:
		var bytes := String(field).to_utf8_buffer()
		material += "%d:" % bytes.size() + String(field)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
			or context.update(material.to_utf8_buffer()) != OK:
		return ""
	return "sha256:" + context.finish().hex_encode()


static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		var integer := int(value)
		return integer >= minimum and integer <= maximum
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) \
		and number >= float(minimum) and number <= float(maximum)


static func _exact_keys(data: Dictionary, required: Array) -> bool:
	if data.size() != required.size():
		return false
	for key in required:
		if not data.has(key):
			return false
	return true
