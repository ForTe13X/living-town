extends RefCounted

## Owner-independent identity contract for content that can be observed at several
## scales.  Canonical strings are the persistence/evidence authority; decoded
## JSON-safe Dictionaries are temporary exchange values for labs, migrators,
## authoring tools, and presentation layers that must not load Sim.
##
## V1 deliberately defines identity, hierarchy, and seed namespaces only.  It
## does not choose a planet projection, biome model, save authority, or camera.

const SCHEMA := "living-town.scale-address/v1"
const RECEIPT_SCHEMA := "living-town.scale-address-receipt/v1"
const SEED_ALGORITHM := "sha256-s63-nul-terminated-parts-v1"
const REGION_SIDE_TILES := 16
const MAX_ABS_REGION_COORD := 10000000
const MIN_TILE_COORD := -MAX_ABS_REGION_COORD * REGION_SIDE_TILES
const MAX_TILE_COORD := MAX_ABS_REGION_COORD * REGION_SIDE_TILES + REGION_SIDE_TILES - 1
const MAX_ABS_CELL_COORD := 10000000

const LEVEL_PLANET := "planet"
const LEVEL_REGION := "region"
const LEVEL_TILE := "tile"
const LEVEL_SITE := "site"
const LEVEL_CELL := "cell"
const LEVELS := [LEVEL_PLANET, LEVEL_REGION, LEVEL_TILE, LEVEL_SITE, LEVEL_CELL]

static func planet_address(planet_id: String) -> Dictionary:
	return normalize({
		"schema": SCHEMA,
		"level": LEVEL_PLANET,
		"planet": planet_id,
	})


static func region_address(planet_id: String, face: int, region: Vector2i) -> Dictionary:
	return normalize({
		"schema": SCHEMA,
		"level": LEVEL_REGION,
		"planet": planet_id,
		"face": face,
		"region": [region.x, region.y],
	})


static func tile_address(planet_id: String, face: int, global_tile: Vector2i) -> Dictionary:
	return normalize({
		"schema": SCHEMA,
		"level": LEVEL_TILE,
		"planet": planet_id,
		"face": face,
		"tile": [global_tile.x, global_tile.y],
	})


static func site_address(planet_id: String, face: int, global_tile: Vector2i, site_key: String) -> Dictionary:
	return normalize({
		"schema": SCHEMA,
		"level": LEVEL_SITE,
		"planet": planet_id,
		"face": face,
		"tile": [global_tile.x, global_tile.y],
		"site": site_key,
	})


static func cell_address(planet_id: String, face: int, global_tile: Vector2i, site_key: String,
		cell: Vector2i, floor_id: String = "surface") -> Dictionary:
	return normalize({
		"schema": SCHEMA,
		"level": LEVEL_CELL,
		"planet": planet_id,
		"face": face,
		"tile": [global_tile.x, global_tile.y],
		"site": site_key,
		"floor": floor_id,
		"cell": [cell.x, cell.y],
	})


## Adapter for the existing MapTileLab convention.  Face zero is an atlas slot,
## not a claim that the lab's 11x7 rectangle is already a spherical projection.
static func map_tile_lab_address(map_tile: Vector2i, planet_id: String = "map-tile-lab", face: int = 0) -> Dictionary:
	var axial := Vector2i(map_tile.x, map_tile.y - (map_tile.x - (map_tile.x & 1)) / 2)
	return tile_address(planet_id, face, axial)


static func child_region(planet: Dictionary, face: int, region: Vector2i) -> Dictionary:
	var normalized := normalize(planet)
	if String(normalized.get("level", "")) != LEVEL_PLANET:
		return {}
	return region_address(String(normalized["planet"]), face, region)


static func child_tile(region: Dictionary, local_tile: Vector2i) -> Dictionary:
	var normalized := normalize(region)
	if String(normalized.get("level", "")) != LEVEL_REGION or not _local_tile_valid(local_tile):
		return {}
	var parent_coord := coordinate(normalized, "region")
	var global_tile := parent_coord * REGION_SIDE_TILES + local_tile
	return tile_address(String(normalized["planet"]), int(normalized["face"]), global_tile)


static func with_site(tile: Dictionary, site_key: String) -> Dictionary:
	var normalized := normalize(tile)
	if String(normalized.get("level", "")) != LEVEL_TILE:
		return {}
	return site_address(String(normalized["planet"]), int(normalized["face"]),
		coordinate(normalized, "tile"), site_key)


static func with_cell(site: Dictionary, cell: Vector2i, floor_id: String = "surface") -> Dictionary:
	var normalized := normalize(site)
	if String(normalized.get("level", "")) != LEVEL_SITE:
		return {}
	return cell_address(String(normalized["planet"]), int(normalized["face"]),
		coordinate(normalized, "tile"), String(normalized["site"]), cell, floor_id)


static func parent(address: Dictionary) -> Dictionary:
	var normalized := normalize(address)
	match String(normalized.get("level", "")):
		LEVEL_CELL:
			return site_address(String(normalized["planet"]), int(normalized["face"]),
				coordinate(normalized, "tile"), String(normalized["site"]))
		LEVEL_SITE:
			return tile_address(String(normalized["planet"]), int(normalized["face"]),
				coordinate(normalized, "tile"))
		LEVEL_TILE:
			return region_address(String(normalized["planet"]), int(normalized["face"]), region_of(normalized))
		LEVEL_REGION:
			return planet_address(String(normalized["planet"]))
	return {}


static func level_of(address: Dictionary) -> String:
	return String(normalize(address).get("level", ""))


static func coordinate(address: Dictionary, key: String) -> Vector2i:
	var value: Variant = address.get(key)
	var valid := false
	match key:
		"region":
			valid = _coordinate_symmetric_valid(value, MAX_ABS_REGION_COORD)
		"tile":
			valid = _coordinate_range_valid(value, MIN_TILE_COORD, MAX_TILE_COORD)
		"cell":
			valid = _coordinate_symmetric_valid(value, MAX_ABS_CELL_COORD)
	if not valid:
		return Vector2i.ZERO
	var values: Array = value
	return Vector2i(int(values[0]), int(values[1]))


static func region_of(address: Dictionary) -> Vector2i:
	var normalized := normalize(address)
	if String(normalized.get("level", "")) not in [LEVEL_TILE, LEVEL_SITE, LEVEL_CELL]:
		return Vector2i.ZERO
	var tile := coordinate(normalized, "tile")
	return Vector2i(_floor_div(tile.x, REGION_SIDE_TILES), _floor_div(tile.y, REGION_SIDE_TILES))


static func local_tile_of(address: Dictionary) -> Vector2i:
	var normalized := normalize(address)
	if String(normalized.get("level", "")) not in [LEVEL_TILE, LEVEL_SITE, LEVEL_CELL]:
		return Vector2i.ZERO
	var tile := coordinate(normalized, "tile")
	return Vector2i(_floor_mod(tile.x, REGION_SIDE_TILES), _floor_mod(tile.y, REGION_SIDE_TILES))


## Returns a fresh canonical-order Dictionary.  Invalid or non-canonical input
## fails closed as {}, including unknown fields that could otherwise fork IDs.
static func normalize(address: Variant) -> Dictionary:
	if not validate(address).is_empty():
		return {}
	return _normalized(address as Dictionary)


static func canonical_id(address: Dictionary) -> String:
	var normalized := normalize(address)
	if normalized.is_empty():
		return ""
	var result := "psa1|p:%s" % String(normalized["planet"])
	var level := String(normalized["level"])
	if level == LEVEL_PLANET:
		return result
	result += "|f:%d" % int(normalized["face"])
	if level == LEVEL_REGION:
		var region := coordinate(normalized, "region")
		return result + "|r:%d,%d" % [region.x, region.y]
	var derived_region := region_of(normalized)
	var local_tile := local_tile_of(normalized)
	result += "|r:%d,%d|t:%d,%d" % [derived_region.x, derived_region.y, local_tile.x, local_tile.y]
	if level in [LEVEL_SITE, LEVEL_CELL]:
		result += "|s:%s" % String(normalized["site"])
	if level == LEVEL_CELL:
		var cell := coordinate(normalized, "cell")
		result += "|l:%s,%d,%d" % [String(normalized["floor"]), cell.x, cell.y]
	return result


static func canonical_json(address: Dictionary) -> String:
	var normalized := normalize(address)
	return "" if normalized.is_empty() else JSON.stringify(normalized)


## Strict inverse of canonical_id().  It rejects aliases such as +0, -0, 01,
## missing hierarchy segments, uppercase keys, and out-of-range coordinates.
static func parse_id(value: String) -> Dictionary:
	var segments := value.split("|", true)
	if segments.size() < 2 or segments[0] != "psa1" or not segments[1].begins_with("p:"):
		return {}
	var planet_id := segments[1].substr(2)
	if not _key_valid(planet_id):
		return {}
	if segments.size() == 2:
		return _parsed_if_exact(value, planet_address(planet_id))
	if segments.size() < 4 or not segments[2].begins_with("f:") \
			or not _canonical_bounded_int_valid(segments[2].substr(2), 0, 5):
		return {}
	var face := int(segments[2].substr(2))
	if not segments[3].begins_with("r:"):
		return {}
	var region := _parse_coordinate_token(segments[3].substr(2),
		-MAX_ABS_REGION_COORD, MAX_ABS_REGION_COORD)
	if region.is_empty():
		return {}
	var region_coord := Vector2i(int(region[0]), int(region[1]))
	if segments.size() == 4:
		return _parsed_if_exact(value, region_address(planet_id, face, region_coord))
	if not segments[4].begins_with("t:"):
		return {}
	var local_values := _parse_coordinate_token(segments[4].substr(2), 0, REGION_SIDE_TILES - 1)
	if local_values.is_empty():
		return {}
	var local_tile := Vector2i(int(local_values[0]), int(local_values[1]))
	if not _local_tile_valid(local_tile):
		return {}
	var global_tile := region_coord * REGION_SIDE_TILES + local_tile
	var parsed := tile_address(planet_id, face, global_tile)
	if segments.size() == 5:
		return _parsed_if_exact(value, parsed)
	if not segments[5].begins_with("s:"):
		return {}
	parsed = with_site(parsed, segments[5].substr(2))
	if segments.size() == 6:
		return _parsed_if_exact(value, parsed)
	if segments.size() != 7 or not segments[6].begins_with("l:"):
		return {}
	var local_values_full := segments[6].substr(2).split(",", true)
	if local_values_full.size() != 3 or not _key_valid(local_values_full[0]) \
			or not _canonical_bounded_int_valid(local_values_full[1], -MAX_ABS_CELL_COORD, MAX_ABS_CELL_COORD) \
			or not _canonical_bounded_int_valid(local_values_full[2], -MAX_ABS_CELL_COORD, MAX_ABS_CELL_COORD):
		return {}
	parsed = with_cell(parsed, Vector2i(int(local_values_full[1]), int(local_values_full[2])), local_values_full[0])
	return _parsed_if_exact(value, parsed)


static func seed_for(root_seed: int, address: Dictionary, purpose: String) -> int:
	var token := seed_token_for(root_seed, address, purpose)
	if token == "":
		return -1
	return token.substr(4).hex_to_int()


## The token is the persistence/evidence identity.  SHA-256 is a specified
## algorithm; each UTF-8 material part, including the final purpose, is followed
## by one NUL byte.  The first digest bit is cleared and the first eight bytes
## become a positive i63 string, so JSON never rounds or sign-extends it.
static func seed_token_for(root_seed: int, address: Dictionary, purpose: String) -> String:
	var address_id := canonical_id(address)
	if address_id == "" or not _key_valid(purpose):
		return ""
	var material := PackedByteArray()
	for part in ["living-town-seed-v1", "i64:%d" % root_seed, address_id, purpose]:
		material.append_array(String(part).to_utf8_buffer())
		material.append(0)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(material) != OK:
		return ""
	var digest := context.finish()
	if digest.size() != 32:
		return ""
	digest[0] = digest[0] & 0x7F
	return "s63:" + digest.slice(0, 8).hex_encode()


static func receipt(root_seed: int, address: Dictionary, purpose: String) -> Dictionary:
	var address_id := canonical_id(address)
	var seed_token := seed_token_for(root_seed, address, purpose)
	if address_id == "" or seed_token == "":
		return {}
	return {
		"schema": RECEIPT_SCHEMA,
		"address": address_id,
		"seed_algorithm": SEED_ALGORITHM,
		"root_seed": "i64:%d" % root_seed,
		"purpose": purpose,
		"seed_token": seed_token,
	}


## Receipts cross implementation boundaries through this fixed field order,
## never through the incidental insertion order of a decoded JSON object.
static func normalize_receipt(value: Variant) -> Dictionary:
	if not validate_receipt(value).is_empty():
		return {}
	var data: Dictionary = value
	return {
		"schema": String(data["schema"]),
		"address": String(data["address"]),
		"seed_algorithm": String(data["seed_algorithm"]),
		"root_seed": String(data["root_seed"]),
		"purpose": String(data["purpose"]),
		"seed_token": String(data["seed_token"]),
	}


static func canonical_receipt_json(value: Variant) -> String:
	var data := normalize_receipt(value)
	if data.is_empty():
		return ""
	return "{\"schema\":%s,\"address\":%s,\"seed_algorithm\":%s,\"root_seed\":%s,\"purpose\":%s,\"seed_token\":%s}" % [
		JSON.stringify(String(data["schema"])),
		JSON.stringify(String(data["address"])),
		JSON.stringify(String(data["seed_algorithm"])),
		JSON.stringify(String(data["root_seed"])),
		JSON.stringify(String(data["purpose"])),
		JSON.stringify(String(data["seed_token"])),
	]


static func validate_receipt(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (value is Dictionary):
		return ["receipt must be a Dictionary"]
	var data: Dictionary = value
	var required := ["schema", "address", "seed_algorithm", "root_seed", "purpose", "seed_token"]
	for key in required:
		if not data.has(key):
			errors.append("missing receipt field '%s'" % key)
	for raw_key in data:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in required:
			errors.append("unknown receipt field '%s'" % str(raw_key))
	for key in required:
		if data.has(key) and typeof(data[key]) != TYPE_STRING:
			errors.append("receipt field '%s' must be a String" % key)
	if data.get("schema") != RECEIPT_SCHEMA:
		errors.append("receipt schema mismatch")
	if data.get("seed_algorithm") != SEED_ALGORITHM:
		errors.append("seed algorithm mismatch")
	var address_text := _string_if(data.get("address"))
	var parsed := parse_id(address_text)
	if parsed.is_empty():
		errors.append("receipt address is not canonical")
	var root_token := _string_if(data.get("root_seed"))
	var root_text := root_token.substr(4) if root_token.begins_with("i64:") else ""
	if not _canonical_int64_valid(root_text):
		errors.append("root_seed must be a canonical i64 token")
	var purpose := _string_if(data.get("purpose"))
	if not _key_valid(purpose):
		errors.append("purpose must be a lowercase stable key")
	var token := _string_if(data.get("seed_token"))
	if not token.begins_with("s63:") or not _lower_hex_valid(token.substr(4), 16) \
			or token.substr(4, 1).hex_to_int() > 7:
		errors.append("seed_token must be a positive 63-bit lowercase hex token")
	if errors.is_empty() and token != seed_token_for(int(root_text), parsed, purpose):
		errors.append("seed_token does not match the receipt namespace")
	return errors


static func validate(address: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (address is Dictionary):
		return ["address must be a Dictionary"]
	var data: Dictionary = address
	var level := _string_if(data.get("level"))
	if typeof(data.get("schema")) != TYPE_STRING or data.get("schema") != SCHEMA:
		errors.append("schema must be %s" % SCHEMA)
	if typeof(data.get("level")) != TYPE_STRING or level not in LEVELS:
		errors.append("level must be one of %s" % str(LEVELS))
	if typeof(data.get("planet")) != TYPE_STRING or not _key_valid(_string_if(data.get("planet"))):
		errors.append("planet must be a lowercase stable key")
	if not errors.is_empty() and level not in LEVELS:
		return errors

	var required := _required_keys(level)
	for key in required:
		if not data.has(key):
			errors.append("missing required field '%s'" % key)
	for raw_key in data:
		if typeof(raw_key) != TYPE_STRING or String(raw_key) not in required:
			errors.append("unknown field '%s'" % str(raw_key))

	if level != LEVEL_PLANET:
		if not _bounded_integer_number(data.get("face"), 0, 5):
			errors.append("face must be an integer from 0 through 5")
	if level == LEVEL_REGION and not _coordinate_symmetric_valid(data.get("region"), MAX_ABS_REGION_COORD):
		errors.append("region must be two bounded integers")
	if level in [LEVEL_TILE, LEVEL_SITE, LEVEL_CELL] \
			and not _coordinate_range_valid(data.get("tile"), MIN_TILE_COORD, MAX_TILE_COORD):
		errors.append("tile must be two bounded integers")
	if level in [LEVEL_SITE, LEVEL_CELL] and (typeof(data.get("site")) != TYPE_STRING \
			or not _key_valid(_string_if(data.get("site")))):
		errors.append("site must be a lowercase stable key")
	if level == LEVEL_CELL and (typeof(data.get("floor")) != TYPE_STRING \
			or not _key_valid(_string_if(data.get("floor")))):
		errors.append("floor must be a lowercase stable key")
	if level == LEVEL_CELL and not _coordinate_symmetric_valid(data.get("cell"), MAX_ABS_CELL_COORD):
		errors.append("cell must be two bounded integers")
	return errors


static func _normalized(address: Dictionary) -> Dictionary:
	var level := String(address.get("level", ""))
	var result := {
		"schema": String(address.get("schema", "")),
		"level": level,
		"planet": String(address.get("planet", "")),
	}
	if level != LEVEL_PLANET:
		result["face"] = int(address.get("face", -1))
	if level == LEVEL_REGION:
		var region := coordinate(address, "region")
		result["region"] = [region.x, region.y]
	elif level in [LEVEL_TILE, LEVEL_SITE, LEVEL_CELL]:
		var tile := coordinate(address, "tile")
		result["tile"] = [tile.x, tile.y]
	if level in [LEVEL_SITE, LEVEL_CELL]:
		result["site"] = String(address.get("site", ""))
	if level == LEVEL_CELL:
		result["floor"] = String(address.get("floor", ""))
		var cell := coordinate(address, "cell")
		result["cell"] = [cell.x, cell.y]
	return result


static func _required_keys(level: String) -> Array[String]:
	var keys: Array[String] = ["schema", "level", "planet"]
	if level != LEVEL_PLANET:
		keys.append("face")
	if level == LEVEL_REGION:
		keys.append("region")
	elif level in [LEVEL_TILE, LEVEL_SITE, LEVEL_CELL]:
		keys.append("tile")
	if level in [LEVEL_SITE, LEVEL_CELL]:
		keys.append("site")
	if level == LEVEL_CELL:
		keys.append("floor")
		keys.append("cell")
	return keys


static func _integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)


static func _bounded_integer_number(value: Variant, minimum: int, maximum: int) -> bool:
	if not _integer_number(value):
		return false
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	var number := float(value)
	return number >= float(minimum) and number <= float(maximum)


static func _string_if(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return value
	return ""


static func _coordinate_range_valid(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is Array) or (value as Array).size() != 2:
		return false
	var values: Array = value
	for component in values:
		if not _bounded_integer_number(component, minimum, maximum):
			return false
	return true


static func _coordinate_symmetric_valid(value: Variant, maximum_absolute: int) -> bool:
	return _coordinate_range_valid(value, -maximum_absolute, maximum_absolute)


static func _local_tile_valid(value: Vector2i) -> bool:
	return value.x >= 0 and value.y >= 0 and value.x < REGION_SIDE_TILES and value.y < REGION_SIDE_TILES


static func _key_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not (is_lower or is_digit or (i > 0 and (code == 45 or code == 95))):
			return false
	return true


static func _floor_div(value: int, divisor: int) -> int:
	var quotient: int = value / divisor
	if value % divisor < 0:
		quotient -= 1
	return quotient


static func _floor_mod(value: int, divisor: int) -> int:
	var remainder := value % divisor
	return remainder + divisor if remainder < 0 else remainder


static func _canonical_bounded_int_valid(value: String, minimum: int, maximum: int) -> bool:
	if value == "0":
		return minimum <= 0 and maximum >= 0
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
	if not _canonical_int64_valid(value):
		return false
	var parsed := int(value)
	return parsed >= minimum and parsed <= maximum


static func _canonical_int64_valid(value: String) -> bool:
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
	return _unsigned_decimal_at_most(magnitude, limit)


static func _unsigned_decimal_at_most(value: String, limit: String) -> bool:
	if value.length() != limit.length():
		return value.length() < limit.length()
	for i in value.length():
		var digit := value.unicode_at(i)
		var limit_digit := limit.unicode_at(i)
		if digit != limit_digit:
			return digit < limit_digit
	return true


static func _lower_hex_valid(value: String, width: int) -> bool:
	if value.length() != width:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _parse_coordinate_token(value: String, minimum: int, maximum: int) -> Array:
	var parts := value.split(",", true)
	if parts.size() != 2 or not _canonical_bounded_int_valid(parts[0], minimum, maximum) \
			or not _canonical_bounded_int_valid(parts[1], minimum, maximum):
		return []
	return [int(parts[0]), int(parts[1])]


static func _parsed_if_exact(source: String, parsed: Dictionary) -> Dictionary:
	return parsed if not parsed.is_empty() and canonical_id(parsed) == source else {}
