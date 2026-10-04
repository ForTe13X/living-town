extends RefCounted
class_name WorldGenCanonical
## Restricted deterministic JSON/hash helpers shared by authoring and import paths.

const PROFILE := "canon.ascii_int32/1"
const INT32_MIN := -2147483648
const INT32_MAX := 2147483647

static func canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical(value), "", false, true)

static func sha256(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_json(value).to_utf8_buffer())
	return context.finish().hex_encode()

static func validate_value(value: Variant, path := "$", depth := 0) -> Array[String]:
	var errors: Array[String] = []
	if depth > 64:
		errors.append("E_CANON_DEPTH: %s exceeds 64 levels" % path)
		return errors
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			if typeof(value) == TYPE_STRING and not _is_ascii(String(value)):
				errors.append("E_CANON_ASCII: %s contains non-ASCII semantic text" % path)
		TYPE_INT:
			if int(value) < INT32_MIN or int(value) > INT32_MAX:
				errors.append("E_CANON_RANGE: %s is outside signed int32" % path)
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number) or not is_equal_approx(number, round(number)) or number < INT32_MIN or number > INT32_MAX:
				errors.append("E_CANON_FLOAT: %s must be a finite signed int32 value" % path)
		TYPE_ARRAY:
			for index in range(value.size()):
				errors.append_array(validate_value(value[index], "%s[%d]" % [path, index], depth + 1))
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not _is_ascii(String(key)):
					errors.append("E_CANON_KEY: %s has a non-ASCII string key" % path)
				else:
					errors.append_array(validate_value(value[key], "%s.%s" % [path, key], depth + 1))
		_:
			errors.append("E_CANON_TYPE: %s has unsupported type %d" % [path, typeof(value)])
	return errors

static func _is_ascii(value: String) -> bool:
	for index in range(value.length()):
		if value.unicode_at(index) > 127:
			return false
	return true

static func _canonical(value: Variant) -> Variant:
	if value is float and is_finite(value) and is_equal_approx(float(value), round(float(value))):
		return int(round(float(value)))
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var sorted := {}
		for key: Variant in keys:
			sorted[str(key)] = _canonical(value[key])
		return sorted
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical(item))
		return result
	return value
