extends Node

const Address = preload("res://scripts/labs/resource_pool/ScaleAddress.gd")
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
	print("=== planet scale address contract ===")

	var planet: Dictionary = Address.planet_address("ashfall")
	var region: Dictionary = Address.child_region(planet, 4, Vector2i(-1, 0))
	var tile: Dictionary = Address.child_tile(region, Vector2i(15, 0))
	var site: Dictionary = Address.with_site(tile, "ash_market")
	var cell: Dictionary = Address.with_cell(site, Vector2i(9, 10))
	var chain := [planet, region, tile, site, cell]
	var all_valid := true
	for address in chain:
		all_valid = all_valid and Address.validate(address).is_empty()
	_check("five scale builders produce valid JSON-safe DTOs", all_valid)
	_check("child tile uses floor division across zero",
		Address.coordinate(tile, "tile") == Vector2i(-1, 0)
		and Address.region_of(tile) == Vector2i(-1, 0)
		and Address.local_tile_of(tile) == Vector2i(15, 0))

	var golden_id := "psa1|p:ashfall|f:4|r:-1,0|t:15,0|s:ash_market|l:surface,9,10"
	_check("cell address has an exact canonical golden id", Address.canonical_id(cell) == golden_id,
		Address.canonical_id(cell))
	_check("canonical parser is an exact inverse",
		Address.canonical_id(Address.parse_id(golden_id)) == golden_id)

	var parent_ids := [
		"psa1|p:ashfall|f:4|r:-1,0|t:15,0|s:ash_market",
		"psa1|p:ashfall|f:4|r:-1,0|t:15,0",
		"psa1|p:ashfall|f:4|r:-1,0",
		"psa1|p:ashfall",
	]
	var cursor := cell
	var parent_chain_exact := true
	for expected in parent_ids:
		cursor = Address.parent(cursor)
		parent_chain_exact = parent_chain_exact and Address.canonical_id(cursor) == expected
	_check("parent removes exactly one authority level", parent_chain_exact)
	_check("planet has no invented parent", Address.parent(planet).is_empty())
	_check("child(parent(tile), local) round-trips",
		Address.canonical_id(Address.child_tile(Address.parent(tile), Address.local_tile_of(tile)))
		== Address.canonical_id(tile))

	var detached_parent: Dictionary = Address.parent(cell)
	detached_parent["site"] = "mutated_copy"
	_check("parent results do not alias their child", Address.canonical_id(cell) == golden_id)
	var detached_child: Dictionary = Address.with_cell(site, Vector2i(3, 4))
	(detached_child["cell"] as Array)[0] = 99
	_check("child results do not alias their parent", Address.canonical_id(site) == parent_ids[0])
	var basement: Dictionary = Address.with_cell(site, Vector2i(9, 10), "b1")
	_check("floor identity separates stacked local cells",
		Address.canonical_id(basement) != golden_id
		and Address.canonical_id(Address.parse_id(Address.canonical_id(basement))) == Address.canonical_id(basement))

	var floor_cases := [
		[-33, -3, 15], [-32, -2, 0], [-17, -2, 15], [-16, -1, 0],
		[-1, -1, 15], [0, 0, 0], [15, 0, 15], [16, 1, 0], [31, 1, 15], [32, 2, 0],
	]
	var floor_math_exact := true
	for values in floor_cases:
		var probe: Dictionary = Address.tile_address("ashfall", 0, Vector2i(int(values[0]), 0))
		floor_math_exact = floor_math_exact \
			and Address.region_of(probe).x == int(values[1]) \
			and Address.local_tile_of(probe).x == int(values[2]) \
			and Address.region_of(probe).x * Address.REGION_SIDE_TILES + Address.local_tile_of(probe).x == int(values[0])
	_check("negative and edge coordinates obey floor-div identity", floor_math_exact)
	var maximum_region: Dictionary = Address.region_address("ashfall", 5,
		Vector2i(Address.MAX_ABS_REGION_COORD, -Address.MAX_ABS_REGION_COORD))
	var maximum_child: Dictionary = Address.child_tile(maximum_region,
		Vector2i(Address.REGION_SIDE_TILES - 1, 0))
	var minimum_region: Dictionary = Address.region_address("ashfall", 0,
		Vector2i(-Address.MAX_ABS_REGION_COORD, Address.MAX_ABS_REGION_COORD))
	var minimum_child: Dictionary = Address.child_tile(minimum_region, Vector2i.ZERO)
	_check("every accepted region has valid children and an exact parent",
		not maximum_child.is_empty() and not minimum_child.is_empty()
		and Address.coordinate(maximum_child, "tile").x == Address.MAX_TILE_COORD
		and Address.coordinate(minimum_child, "tile").x == Address.MIN_TILE_COORD
		and Address.canonical_id(Address.parent(maximum_child)) == Address.canonical_id(maximum_region)
		and Address.canonical_id(Address.parent(minimum_child)) == Address.canonical_id(minimum_region))

	var inserted_out_of_order := {
		"cell": [9, 10], "floor": "surface", "site": "ash_market", "tile": [-1, 0], "face": 4,
		"planet": "ashfall", "level": "cell", "schema": Address.SCHEMA,
	}
	_check("Dictionary insertion order cannot change identity",
		Address.canonical_id(inserted_out_of_order) == golden_id)
	var integral_float := inserted_out_of_order.duplicate(true)
	integral_float["face"] = 4.0
	integral_float["tile"] = [-1.0, 0.0]
	integral_float["cell"] = [9.0, 10.0]
	_check("JSON integral floats normalize without identity drift",
		Address.canonical_id(integral_float) == golden_id)

	var fractional := inserted_out_of_order.duplicate(true)
	fractional["tile"] = [-1.5, 0]
	var string_coord := inserted_out_of_order.duplicate(true)
	string_coord["cell"] = ["9", 10]
	var bool_coord := inserted_out_of_order.duplicate(true)
	bool_coord["cell"] = [true, 10]
	var unknown_field := inserted_out_of_order.duplicate(true)
	unknown_field["camera_zoom"] = 4
	var numeric_planet := inserted_out_of_order.duplicate(true)
	numeric_planet["planet"] = 7
	var huge_face := inserted_out_of_order.duplicate(true)
	huge_face["face"] = 1.0e300
	var huge_coordinate := inserted_out_of_order.duplicate(true)
	huge_coordinate["tile"] = [1.0e300, 0.0]
	_check("fraction, string, bool, and unknown authority fields fail closed",
		Address.normalize(fractional).is_empty() and Address.normalize(string_coord).is_empty()
		and Address.normalize(bool_coord).is_empty() and Address.normalize(unknown_field).is_empty()
		and Address.normalize(numeric_planet).is_empty())
	_check("finite integral floats are range-checked before int conversion",
		Address.normalize(huge_face).is_empty() and Address.normalize(huge_coordinate).is_empty())

	var invalid_ids := [
		"", "psa1|p:Ashfall", "psa1|p:-ashfall", "psa1|p:ash.fall",
		"psa1|p:ashfall|", "psa1|p:ashfall|f:+0|r:0,0",
		"psa1|p:ashfall|f:0|r:-0,0", "psa1|p:ashfall|f:0|r:01,0",
		"psa1|p:ashfall|f:6|r:0,0", "psa1|p:ashfall|f:0|t:0,0",
		"psa1|p:ashfall|f:0|r:0,0|t:16,0",
		"psa1|p:ashfall|f:0|r:0,0|t:0,0|s:ash market",
		"psa1|p:ashfall|f:0|r:10000001,0",
		"psa1|p:ashfall|f:0|r:0,0|t:0,0|s:ash|l:Surface,0,0",
		golden_id + "|tail:1",
	]
	var invalid_ids_rejected := true
	for invalid_id in invalid_ids:
		invalid_ids_rejected = invalid_ids_rejected and Address.parse_id(String(invalid_id)).is_empty()
	_check("canonical parser rejects aliases, gaps, and overflow", invalid_ids_rejected)
	_check("stable keys accept useful separators but reject ambiguous forms",
		not Address.planet_address("p0").is_empty()
		and Address.canonical_id(Address.planet_address("a-b")) != ""
		and Address.canonical_id(Address.planet_address("a_b")) != ""
		and Address.canonical_id(Address.planet_address("A")) == ""
		and Address.canonical_id(Address.planet_address("_a")) == "")

	var token := Address.seed_token_for(260814, cell, "site-layout")
	_check("seed namespace has an exact SHA-256 i63 golden token", token == "s63:1330409f87853412", token)
	_check("same root/address/purpose produces the same token",
		token == Address.seed_token_for(260814, Address.parse_id(golden_id), "site-layout"))
	_check("root, address, and purpose each separate seed streams",
		token != Address.seed_token_for(260815, cell, "site-layout")
		and token != Address.seed_token_for(260814, site, "site-layout")
		and token != Address.seed_token_for(260814, cell, "loot-layout"))
	_check("runtime RNG seed is deterministic but not receipt authority",
		Address.seed_for(260814, cell, "site-layout") == 1382676139520373778)

	var receipt: Dictionary = Address.receipt(260814, cell, "site-layout")
	var receipt_text := Address.canonical_receipt_json(receipt)
	var decoded: Variant = JSON.parse_string(receipt_text)
	_check("receipt survives JSON roundtrip and revalidation",
		decoded is Dictionary and Address.validate_receipt(decoded).is_empty()
		and Address.canonical_receipt_json(decoded) == receipt_text)
	var binary_roundtrip: Variant = bytes_to_var(var_to_bytes(receipt))
	_check("receipt survives Variant binary roundtrip",
		binary_roundtrip is Dictionary and Address.validate_receipt(binary_roundtrip).is_empty()
		and Address.canonical_receipt_json(binary_roundtrip) == receipt_text)
	var reordered_receipt := {
		"seed_token": receipt["seed_token"], "purpose": receipt["purpose"],
		"root_seed": receipt["root_seed"], "seed_algorithm": receipt["seed_algorithm"],
		"address": receipt["address"], "schema": receipt["schema"],
	}
	_check("canonical receipt bytes ignore Dictionary insertion order",
		Address.canonical_receipt_json(reordered_receipt) == receipt_text)
	var negative_root: Dictionary = Address.receipt(-1, cell, "site-layout")
	_check("signed root seed token is canonical and independently derived",
		negative_root.get("root_seed") == "i64:-1"
		and Address.validate_receipt(negative_root).is_empty()
		and negative_root.get("seed_token") != receipt.get("seed_token"))
	var tampered: Dictionary = receipt.duplicate(true)
	tampered["seed_token"] = "0000000000000000"
	var extra_receipt: Dictionary = receipt.duplicate(true)
	extra_receipt["camera"] = "forbidden"
	var numeric_root: Dictionary = receipt.duplicate(true)
	numeric_root["root_seed"] = 260814
	var overflow_root: Dictionary = receipt.duplicate(true)
	overflow_root["root_seed"] = "i64:9223372036854775808"
	var underflow_root: Dictionary = receipt.duplicate(true)
	underflow_root["root_seed"] = "i64:-9223372036854775809"
	_check("tampered and extended receipts fail closed",
		not Address.validate_receipt(tampered).is_empty()
		and not Address.validate_receipt(extra_receipt).is_empty()
		and not Address.validate_receipt(numeric_root).is_empty())
	_check("root tokens outside signed int64 fail before conversion",
		not Address.validate_receipt(overflow_root).is_empty()
		and not Address.validate_receipt(underflow_root).is_empty())

	var map_tile: Dictionary = Address.map_tile_lab_address(Vector2i(7, 2), "ashfall", 0)
	_check("MapTileLab odd-q coordinates adapt to stable axial identity without Sim",
		Address.coordinate(map_tile, "tile") == Vector2i(7, -1)
		and Address.canonical_id(map_tile) == "psa1|p:ashfall|f:0|r:0,-1|t:7,15")

	var canonical_seen := {}
	var seed_seen := {}
	var sample_collision_free := true
	for face in 6:
		for y in range(-10, 11):
			for x in range(-10, 11):
				var sample: Dictionary = Address.tile_address("sample", face, Vector2i(x, y))
				var sample_id := Address.canonical_id(sample)
				var sample_seed := Address.seed_token_for(77, sample, "terrain")
				if canonical_seen.has(sample_id) or seed_seen.has(sample_seed):
					sample_collision_free = false
				canonical_seen[sample_id] = true
				seed_seen[sample_seed] = true
	_check("2646-address regression sample is collision-free", sample_collision_free
		and canonical_seen.size() == 2646 and seed_seen.size() == 2646)

	_check("resource-pool manifest is present and parseable", _manifest_valid())
	print("PLANET_SCALE_ADDRESS_RECEIPT=%s" % receipt_text)
	print("planet_scale_address_test: %s (%d fail, %d checks)" % [
		("PASS" if _fails == 0 else "FAIL"), _fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _manifest_valid() -> bool:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		return false
	var manifest: Dictionary = parsed
	var batches: Variant = manifest.get("batches")
	return manifest.get("schema") == "living-town.resource-pool/v1" \
		and batches is Array and not (batches as Array).is_empty() \
		and (batches as Array)[0] is Dictionary \
		and ((batches as Array)[0] as Dictionary).get("id") == "RP-0001"
