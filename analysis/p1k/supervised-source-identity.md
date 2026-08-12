# P1-k supervised Godot source identity

Date: 2026-08-13 CST

Branch: `codex/p1a-takeover`

Purpose: prevent a supervised local run from presenting committed SHA/tree metadata as proof of the dirty files that Godot actually executed.

## Root cause

P1-f v1 recorded `source_head`, `HEAD:game` and `status_before`, but it never rejected a dirty tree and did not fingerprint the dirty content. Several historical receipts therefore named a commit while executing additional working-tree changes. Their process cleanup evidence remains valid; their exact-source claim does not.

## v2 contract

- Clean tree, stable for the whole run: `source_identity=exact_commit`.
- Dirty tree without explicit opt-in: preflight receipt, `source_identity=rejected_dirty`, exit 78, Godot never starts.
- Dirty tree with `-AllowDirtyCandidate`: `source_identity=dirty_candidate`; receipt binds status, tracked binary-diff SHA-256, every untracked file's Git-blob SHA-1, and a combined SHA-256 fingerprint.
- After Godot exits (or times out), HEAD, branch, committed game tree and the full worktree fingerprint are recomputed. Any before/after drift overrides an otherwise clean result with `outcome=source_drift`, exit 79; cleanup failure and native-crash evidence retain higher severity.
- Receipt contract is `living-town-supervised-godot-v2`; before/after fields remain explicit so consumers need not infer provenance from prose.

Ignored files are intentionally outside the product-source fingerprint. The source-drift control uses a unique, unignored `.probe` file; using the repository's ignored `*.tmp` pattern was an invalid negative control and was discarded.

## Verification teeth

`tools/test-run-godot-provenance.ps1` executes three independent arms:

1. create an untracked probe and prove the default lane rejects dirty state before launch;
2. opt in and prove a real P1-d focused run is labeled `dirty_candidate`, source-stable and fingerprint-equal before/after;
3. start a real Harness run, mutate only the dedicated probe after the checkout lock appears, and prove the otherwise running process is reported as `source_drift/79` with unequal fingerprints.

`tools/test-run-godot-supervised.ps1` retains the original success, timeout, concurrent-owner and zero-survivor controls. It opts into candidate mode because the test necessarily runs while the v2 scripts themselves are uncommitted; it now exits 0 explicitly after validating the expected blocked child exit 78.

## Player / visual boundary

P1-k changes evidence infrastructure only. It does not alter Godot state, player controls, UI, art or framebuffer output, so the canonical P1-i East Ocean player/warehouse frames remain the product visual reference. New screenshots would test no changed presentation property.

## Provenance, limitations and recovery

- Original repository PowerShell/tests/docs; no external code/assets or new license obligations.
- Fingerprinting runs `git status`, a binary tracked diff and hashes of every untracked non-ignored file. This is intentionally more expensive than v1 and is appropriate for verification runs, not per-frame code.
- Git identity/fingerprint commands are checked individually; a failed Git read aborts instead of silently producing an `exact_commit` label. Endpoint equality cannot detect a file that changes and is restored byte-for-byte between both snapshots, so callers must still honor the checkout lock and avoid editing a running evidence tree.
- The v2 runner proves stable source identity and supervised execution. It does not make stale golden/modelpath/complement anchors current, certify the GitHub synthetic merge, or authorize rebake/merge/release.
- Recover by checking out the P1-k topic commit, running both PowerShell self-tests, then running one focused scene from the clean committed tree and requiring `exact_commit`, `source_stable=true`, clean before/after status and cleanup success.
