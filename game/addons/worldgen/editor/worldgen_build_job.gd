@tool
extends RefCounted
class_name WorldGenBuildJob
## Detached worker entry point; it returns data only and never touches editor nodes.

const BUILD_SCRIPT := preload("res://addons/worldgen/core/worldgen_build_service.gd")

func build_candidate(recipe_snapshot: Dictionary) -> Dictionary:
	return BUILD_SCRIPT.build_package(recipe_snapshot.duplicate(true))
