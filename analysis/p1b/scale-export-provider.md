# P1-d scale export provider — reusable delivery card

Date: 2026-08-11 (CST)

Branch: `codex/p1a-takeover`

Code commit: the topic commit containing this card (see branch history)

Purpose: remove the N16/N24/N60 empty-set pass for hard invariant #46 while preserving the calibrated local-stock protection and the fixed physical route throughput.

## Contract and reusable seams

- Population input is the production pool ratio `prod_pool_num/prod_pool_den` (core residents), never `agents.size()` (which includes Tao).
- N=12 keeps the authored export lane unchanged. N<base remains fail-closed. N>12 only enables a lane with exact boolean `scale_floor=true`; absent, false or malformed flags remain inert.
- The effective local-stock floor is integer ceiling `ceil(authored_floor × pool_num / pool_den)`. For total N16/N24/N60, core is 15/23/59 and floor 36 becomes 45/69/177.
- `batch=6`, `every_days=3` and `price=1/2` remain fixed route throughput. Population growth does not silently multiply vessels, cadence, credit or money flow.
- `Invariants.export_pair_scan(log)` is the single filtered pay→stock scanner used by both #46 and the complement probe. It returns `{related,pairs,bad}`; a quantity-mismatch pair increments `pairs` before becoming bad, while orphan pay/stock remains a nonzero provider and becomes bad.
- Provider evidence is real event activity (`export_related>0`, `export_pairs>0`) plus #46 green. A green #46 with zero related events is still explicitly vacuous.

## Focused negative matrix

`p1d_scale_export_test` freezes the following boundaries:

- Empty stream: provider 0; orphan stock: provider nonzero and red; unrelated events between filtered pay/stock do not break a valid pair; quantity mismatch counts one pair and red.
- Stock at/below effective floor, external balance 0, and revenue flooring to 0 all produce zero stock/money/event effects.
- A non-opted/malformed N>12 lane and a pool ratio below base remain inert; N=12 deliberately ignores the new flag and preserves authored export.
- Partial affordability commits only the affordable even quantity through the same exact pay→stock wrapper.
- Core 15/23/59 each computes floor 45/69/177 and produces one nonempty, structurally valid #46 pair in the direct contract fixture. Odd-floor teeth freeze true ceil semantics: authored 35 becomes 44/68/173 rather than truncating.

## Full-grid evidence (no golden)

- Default N13 (12 core + Tao), seeds 1–12, 60d, det3: S0 PASS; hard/#40/#44/#45/#46 `12/12`; import/export `156/57`, both covering `12/12`; det `3/3`.
- Held-out seeds 13–30, 60d, det3: S0 PASS; hard/#44/#45/#46 `18/18`; #40 `17/18` (only seed14 soft red); import/export `252/59`, both covering `18/18`; det `3/3`.
- Total N16 (core15), seeds 1–12, 60d, det1: S0 PASS; hard/#40/#44/#45/#46 `12/12`; import/export `183/57`, both covering `12/12`; det `1/1`.
- Total N24 (core23): S0 PASS; hard/#44/#45/#46 `12/12`; #40 `11/12` (seed10 retains the known over-supply-arm soft red); import/export `167/82`, both covering `12/12`; det `1/1`.
- Total N60 (core59): S0 PASS; hard/#44/#45/#46 `12/12`; #40 `11/12` (seed12 retains the known over-supply-arm soft red); import/export `153/128`, both covering `12/12`; det `1/1`.
- Focused P1-b CargoManifest and P1-c carrier regressions PASS; `gate_fixture_audit.py --self-test` PASS. Crash-pattern scans found no `signal 11`, `FATAL`, out-of-bounds, segmentation, `CRASH`, or `SCRIPT ERROR`; the known optional NobodyWho load noise and exit-time ObjectDB warning remain non-gating.

## CI / delivery boundary

- PR #6 run `31490917062` checked the pre-P1-d head `a96ccf5` through a synthetic merge. Live code, determinism, P1-b/P1-c focused tests and standard S0 logic passed, but CI failed on deliberately stale evidence anchors: complement ledger schema/tree, 36 golden fields, and five ModelPath fields.
- That run is not an exact branch-tip receipt for this batch. Golden, ModelPath and complement ledger were not rebaked here. PR #6 must remain draft/unmergeable until a committed exact-tree finalize follows the existing rebake protocol and a fresh review/CI receipt is attached.

## Provenance / license / limits

- Code, tests and documentation are original project work; no external code or asset was copied. The implementation reuses the repository's existing production-pool, exact export wrapper and invariant interfaces.
- The scaled floor preserves the authored floor/cap proportion; it is not a proof of optimal economy balance for every future population. Any new scale needs a full provider + #40/#45/#46 + determinism grid.
- Opt-in is keyed to an active production-pool ratio greater than one. Under the existing production-scale ablation, missing/invalid scale data leaves the ratio at one and therefore follows the legacy N=12 lane path even if more agents were externally injected; strict population semantics would require a separate core-population authority and is outside this slice.
- `scale_floor` has runtime strict-type/fail-closed coverage but no dedicated JSON lint rule yet. Current shipping data is valid; a malformed future flag makes the N>12 lane inert and is caught by provider evidence rather than creating a false trade.
- Runtime `zero-import` is not a causal export-only fixture because external credit starts at zero and only real imports fund exports. Export-only and orphan-only cases in the parser self-test are synthetic contract teeth, not product-trajectory evidence.

## Hygiene / recovery

- No golden/modelpath/complement artifact, protected branch, README, generated frame or source task was modified.
- Unknown-owner worktrees remain untouched. A stale parser-test Godot process created by this batch was identified by exact PID/start time and stopped; no other process was changed.
- Recovery is the P1-d topic commit. Revalidation uses the focused scene plus the five Harness grids recorded above.
