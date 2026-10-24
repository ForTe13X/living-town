extends Node
## Receiver-owned bounded storage; no incoming metadata can enlarge its budget.
const SimScript = preload("res://scripts/Sim.gd")
const ProfileScript = preload("res://scripts/TownWorldProfile.gd")
const Inv = preload("res://bench/Invariants.gd")
const BASE_BYTES: int = 8*1024*1024
const MAX_BYTES: int = 64*1024*1024

class BudgetProvider extends RefCounted:
	var allowance: int = 0
	func save_topology_allowance_bytes() -> int:
		return allowance

var failures: int = 0
var checks: Array = []
var paths: Array[String] = []

func ck(name: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"passed":passed,"detail":detail})
	if not passed: failures += 1
	print(("PASS " if passed else "FAIL ") + "SAVE BUDGET " + name)

func fixture_path(label: String) -> String:
	var path: String = "user://save_budget_" + str(Time.get_ticks_usec()) + "_" + label + ".dat"
	paths.append(path)
	return path

func oversized_fixture(path: String, limit: int) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_32(2)
	file.seek(limit)
	file.store_8(0)
	file.close()

func _ready() -> void:
	var sim: Node = SimScript.new()
	add_child(sim)
	sim.auto_run = false
	sim.start_new(7)
	ck("ordinary_receiver_keeps8MiB", sim.save_byte_limit() == BASE_BYTES and sim.player_trace_status()["max_save_bytes"] == BASE_BYTES)
	var provider: BudgetProvider = BudgetProvider.new()
	sim.ext = provider
	provider.allowance = -9000000000
	ck("negative_allowance_cannot_reduce_or_increase_default", sim.save_byte_limit() == BASE_BYTES)
	provider.allowance = 1024
	ck("receiver_owned_allowance_is_measured_not_metadata", sim.save_byte_limit() == BASE_BYTES+1024)
	provider.allowance = 9000000000
	ck("oversized_provider_cannot_exceed64MiB", sim.save_byte_limit() == MAX_BYTES and sim.player_trace_status()["max_save_bytes"] == MAX_BYTES)
	var huge_path: String = fixture_path("over_absolute")
	oversized_fixture(huge_path, MAX_BYTES)
	ck("absolute_oversize_rejected_before_decode", sim.peek_save(huge_path).is_empty() and not sim.load_game(huge_path))
	sim.ext = null
	var empty_profile: RefCounted = ProfileScript.new()
	ck("unloaded_profile_has_no_topology_allowance", empty_profile.save_topology_allowance_bytes() == 0)
	ck("invalid_profile_cannot_grant_allowance", not empty_profile.load_profile("user://save_budget_missing_profile.json") and empty_profile.save_topology_allowance_bytes() == 0)
	var path: String = fixture_path("ordinary")
	for tick: int in range(8): sim.tick()
	ck("ordinary_schema2_save_still_writes", sim.save_game(path, {"max_save_bytes":MAX_BYTES,"save_topology_allowance_bytes":MAX_BYTES,"world_profile":{"id":"forged"}}))
	ck("metadata_does_not_choose_budget", sim.save_byte_limit() == BASE_BYTES)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var actual_bytes: int = file.get_length()
	var schema: int = file.get_32()
	var stored_payload_bytes: int = file.get_32()
	file.seek(4)
	var envelope: Dictionary = file.get_var()
	file.close()
	ck("writer_accounts_for_schema_and_store_var_length_prefix", schema == 2 and actual_bytes == stored_payload_bytes+8 and actual_bytes == sim.save_encoded_file_bytes(envelope) and actual_bytes <= BASE_BYTES,
		{"actual_file_bytes":actual_bytes,"stored_payload_bytes":stored_payload_bytes,"limit_bytes":sim.save_byte_limit()})
	var peer: Node = SimScript.new()
	add_child(peer)
	peer.auto_run = false
	peer.start_new(999)
	ck("ordinary_peek_and_restore_still_work", peer.peek_save(path).get("saved_tick", -1) == sim.tick_no and peer.load_game(path))
	var sim_chain: int = Inv.chain_step(Inv.CHAIN_INIT, sim, 0)
	var peer_chain: int = Inv.chain_step(Inv.CHAIN_INIT, peer, 0)
	var same: bool = sim_chain == peer_chain and Inv.digest(sim) == Inv.digest(peer) and sim.event_digest == peer.event_digest
	for tick: int in range(12):
		var sim_events: int = sim.event_log.size()
		var peer_events: int = peer.event_log.size()
		sim.tick(); peer.tick()
		sim_chain = Inv.chain_step(sim_chain, sim, sim_events)
		peer_chain = Inv.chain_step(peer_chain, peer, peer_events)
		same = same and sim_chain == peer_chain and Inv.digest(sim) == Inv.digest(peer) and sim.event_digest == peer.event_digest
	ck("ordinary_resume_future_remains_deterministic", same)
	var stable_digest: int = Inv.chain_step(Inv.CHAIN_INIT, sim, 0)
	var prior_sha: String = FileAccess.get_sha256(path)
	ck("oversized_mutable_metadata_is_refused", not sim.save_game(path, {"padding":"x".repeat(BASE_BYTES),"max_save_bytes":MAX_BYTES}))
	ck("refused_write_preserves_existing_save_and_live_state", FileAccess.get_sha256(path) == prior_sha and Inv.chain_step(Inv.CHAIN_INIT, sim, 0) == stable_digest)
	var too_large: String = fixture_path("over_default")
	oversized_fixture(too_large, BASE_BYTES)
	ck("ordinary_oversize_file_rejected_without_live_mutation", sim.peek_save(too_large).is_empty() and not sim.load_game(too_large) and Inv.chain_step(Inv.CHAIN_INIT, sim, 0) == stable_digest and sim.save_byte_limit() == BASE_BYTES)
	var forged_length: String = fixture_path("forged_length")
	file = FileAccess.open(forged_length, FileAccess.WRITE)
	file.store_32(2); file.store_32(0x7fffffff); file.store_8(0); file.close()
	ck("huge_declared_payload_in_tiny_file_rejected_before_allocation", sim.peek_save(forged_length).is_empty() and not sim.load_game(forged_length) and Inv.chain_step(Inv.CHAIN_INIT, sim, 0) == stable_digest)
	for cleanup: String in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup))
	var report_path: String = "user://save_budget_test_report.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report=") and argument.substr(9).is_absolute_path(): report_path=argument.substr(9)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path).get_base_dir())
	file = FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema":"living_town.save_budget_test.v1","status":"PASS" if failures == 0 else "FAIL","failures":failures,"checks":checks,"ordinary_limit_bytes":BASE_BYTES,"absolute_limit_bytes":MAX_BYTES},"\t")+"\n")
		file.close()
	else: ck("report_written", false, report_path)
	print("save_budget_test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
