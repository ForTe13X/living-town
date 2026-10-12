# WorldGen authoring command protocol

WG40 adds one JSON request boundary shared by human and agent callers. The request is data on stdin; it cannot name a recipe file, output file, script, shell command, or executable. The Python adapter owns the project path, creates short-lived request/response files outside the project, and starts only the configured Godot 4.6.2 binary with the fixed `worldgen_authoring_command_cli.gd` entrypoint. Child execution uses an argument array with `shell=False` and a bounded timeout.

The contract is `game/addons/worldgen/contracts/authoring_command.schema.json`. Results use `worldgen.authoring_result/1`, repeat the request ID and canonical request digest, and include the native Godot version at the adapter boundary.

## Commands

- `inspect` reads a recipe and its current built package by stable world ID.
- `validate` loads a content-addressed package and runs `WorldGenPackageValidator`.
- `propose` binds to recipe/package digests and source revision, then calls `WorldGenEditCommand.prepare_patch`. It returns a detached candidate recipe, changed dependency closure, and protected IDs. It does not persist or activate the candidate.
- `repair` forwards the bounded `worldgen.local_repair_request/1` to `WorldGenLocalRepair`. The result remains `CANDIDATE_REQUIRES_GLOBAL_VALIDATION` unless that operator receives its independent global validator. The protocol does not upgrade local placement evidence into global validation.
- `publish-request` validates the immutable candidate and returns an approval request bound to its world ID, candidate digest, and expected revision. The adapter has no activation command and rejects `publish` as an unknown command. A separate publisher still requires an external approval token and candidate digest.

Request objects have closed command-specific field sets. The adapter rejects duplicate JSON keys, unsupported commands, arbitrary paths/scripts, freeform prompt or asset metadata keys, malformed patch paths, oversized input, and repair budgets above 250,000 operations. Proposals still pass through the same Godot allowlist and stale-base checks as the editor. Asset metadata is treated only as data and is not interpolated as code or instructions.

## Invoke

The Godot executable path is trusted adapter configuration, not part of the JSON request. Configure `WORLDGEN_GODOT_BIN` or pass `--godot-bin`; the adapter rejects versions other than 4.6.2.

```powershell
$request = '{"schema":"worldgen.authoring_command/1","request_id":"review-1","command":"inspect","world_id":"warm_bay_s1"}'
$request | python tools/worldgen_agent_adapter.py --godot-bin 'C:\path\to\Godot_v4.6.2-stable_win64_console.exe'
```

An approval object supplied by the same agent is not accepted as authorization. `publish-request` only prepares the digest-bound request; activation remains outside this protocol. The existing catalog publisher currently checks approval structure, revision, and candidate binding. A cryptographic reviewer-token service and direct user-driven dock click-through remain release work.
