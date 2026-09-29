extends RefCounted
## Validate path operands before a gate runs or opens any output file.
## A missing bake operand must never silently turn a bake into a comparison.

static func path_error(args: PackedStringArray, flags: Array) -> String:
	for i in args.size():
		if args[i] not in flags:
			continue
		if i + 1 >= args.size() or args[i + 1].strip_edges().is_empty() or args[i + 1].begins_with("--"):
			return "%s requires a non-empty path argument (example: %s game/bench/output.json)" % [args[i], args[i]]
	return ""
