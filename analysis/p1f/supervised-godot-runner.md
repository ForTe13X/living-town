# P1-f supervised local Godot runner + player-frame receipt

> **P1-k provenance correction (2026-08-13):** the v1 receipts below record `HEAD` and `HEAD:game`, but several were produced from a dirty worktree. They prove supervised execution/cleanup of that worktree, not exact-commit source identity. The canonical runner is now v2: dirty trees are rejected by default; explicit `-AllowDirtyCandidate` receipts are labeled `dirty_candidate` and bind a stable worktree fingerprint. See `analysis/p1k/supervised-source-identity.md`.

Date: 2026-08-12 CST

Branch: `codex/p1a-takeover`

Purpose: turn local Godot evidence from an unsupervised shell convention into a recoverable run contract. The immediate trigger was four old Living Town test families that had printed PASS/returned control while leaving a console/GUI Godot pair alive for hours, contaminating CPU and later measurements.

## Interface

Canonical Windows command:

```powershell
& .\tools\run-godot-supervised.ps1 -TimeoutSec 180 -GodotArgs @(
  '--headless', 'res://scenes/p1d_scale_export_test.tscn'
)
```

Inputs:

- concrete Godot executable or the existing `godot.cmd` launcher (the runner resolves the console executable before launch);
- timeout in seconds;
- Godot arguments excluding `--path` and `--log-file`, which are supervisor-owned;
- optional receipt root (default `%TEMP%\living-town-godot-runs`).

Outputs:

- one GUID run directory containing `godot.log`, `stdout.log`, `stderr.log` and `receipt.json`;
- receipt identity (v1 historical boundary): UTC run id, branch, recorded source HEAD and `HEAD:game`, executable, absolute project path and arguments; only an empty `status_before` could make those fields commit-exact;
- verdict: exit code, timeout, native-crash scan, duration and process-tree cleanup assertion;
- SHA-256/length/path for every emitted log.

Exit contract:

- `0`: Godot exited cleanly, no fatal pattern, cleanup verified;
- Godot's non-zero exit: preserved as the run result;
- `70/71`: supervisor/native-crash or cleanup failure;
- `78`: another run owns this checkout, a pre-existing project Godot exists, or the default exact-evidence lane finds a dirty tree;
- `79`: HEAD/branch/committed game tree/worktree fingerprint changed during the run;
- `124`: timeout; the owned process tree is still required to be absent before the receipt is written.

The checkout lock is exclusive and owner-scoped. Cleanup never sweeps by executable name: it follows the launched parent/descendant chain and the run's unique injected log path, then stops leaves before parents and rechecks zero survivors. A PID is considered the root only while its command line still contains that same token, protecting against PID reuse.

## Failure provenance and cleanup

Read-only CIM preflight found four project-owned stale families, each with exact `--path game`, P1 scene and TEMP log evidence:

| Console → GUI PIDs | Scene | retained TEMP log |
|---|---|---|
| `24584 → 29684` | `p1b_cargo_manifest_test.tscn` | `p1b_manifest_focus.log` |
| `3076 → 22496` | `p1b_cargo_manifest_test.tscn` | `p1b_cargo_manifest_test.log` |
| `35268 → 38136` | `p1c_east_ocean_carrier_test.tscn` | `p1c_east_ocean_focused.log` |
| `37972 → 37912` | `save_migration_test.tscn` | `p1e_save_migration_exact.log` |

All eight exact PIDs were stopped child-first after command/parent revalidation. The processes are not recoverable (nor useful); all four logs were retained and the follow-up project Godot count was zero. No unrelated Godot, terminal, worktree or file was removed.

## Verification teeth

`tools/test-run-godot-supervised.ps1` provides three independent controls:

1. real focused scene `p1d_scale_export_test.tscn` exits `0`, reports `outcome=pass`, no crash marker and cleanup true;
2. the real game main loop is intentionally left running and must become `outcome=timeout`, exit `124`, cleanup true;
3. while an owner holds the checkout, a second run must emit its own `preflight_blocked` receipt and exit `78` without deleting the owner's lock; the owner then times out and cleans up.

Final control receipts:

- success `20260812T091601610Z_176d96de9c0540d4b09963efe27e049f`;
- timeout `20260812T091603191Z_f51c25614eeb4207b039b980faedb03d`;
- blocked `20260812T091616726Z_697c13c567e74912bb06f0f4ee8d76a4`.

All three recorded source `0cfc495de0cbfc9936006325b7085fd7e0a4ca9f`, game tree `1d16ae580e14fbde4f7543d2b8212226fb662e9b`; their dirty `status_before` means they are candidate-tree process controls, not exact-commit receipts. Final scoped Godot count was zero. PowerShell parser and `git diff --check` also pass.

## Player-position visual reference

The runner captured three real Windows/OpenGL framebuffer frames at seed 3, ticks `580/600/620`, with the player selected and positioned at East Ocean dock `[58,8]`. Each run has an independent receipt and cleanup proof:

- tick 580: run `20260812T090629656Z_962951f7caa84facb817b31c4935d8f1`, PNG SHA-256 `8c9fd3ed43c50f611063c571848ccfbc6c9b860362167d54b8d8884953897450`;
- tick 600: run `20260812T090633849Z_a407319be5d6483d83a2af41d2a8822a`, PNG SHA-256 `fab0e6b2b523d57d65ad74bb0e5dbed5285fd0e25e0e7a478762536f7f5e18ae`;
- tick 620: run `20260812T090637778Z_40f44a034d8f4e47887d7257ccea029a`, PNG SHA-256 `92dd70ecefbb17199fdd0e44b1b6f6cd1f11e8563032ae2dc2b5193f7b4778c5`.

Generated files live under `%TEMP%\p1f-player-east-ocean-frames` and are rebuildable, not pixel goldens. Visual inspection confirms the actual player, ready vessel, berth/crates, seven interaction verbs, event log, needs/coin panel and timeline fit in one frame without the core mechanic being hidden. Product limitation retained for the next batch: the vessel is readable, but manifest identity/unload eligibility is not yet an explicit player-facing prompt. Motion/timing changes should continue to use the existing Xvfb/ffmpeg recording lane; three fixed-time frames are sufficient for this process-hygiene batch because no animation or art behavior changed.

## Scope and limitations

- This runner governs local Windows evidence. Container and GitHub Actions jobs retain their own process namespace/timeout lifecycle; migrating every historical raw call is a separate mechanical batch.
- Existing unsupervised scripts are not silently rewritten here. New local P1 evidence should call this wrapper; old raw invocations remain `legacy-supported` until migrated with their own exit-code tests.
- The runner does not make stale golden/modelpath/complement evidence current and does not authorize merge/release/rebake.
- Source/license: repository-authored PowerShell and repository-generated evidence only; no external code or asset was copied.
