# P1-q cross-platform portal numeric contract

Status: implemented and exact-commit verified on 2026-08-13. This is a runtime data-contract
repair, not an anchor rebake, merge receipt, or claim that draft PR #6 is fully green.

## Delivery target and provenance

P1-q closes the one new product failure in hosted run `31690429941` for P1-p exact tip
`340159252337e1f3cbd7b85145a19bb2ac0b5f0e`: `space_test` ended with one failure on Linux while
the same committed tree passed the canonical Windows supervisor. The stale complement, golden,
DetGate and modelpath anchors remain separate known delivery blockers and were not modified.

The isolated pinned-Linux reproduction exposed the actual assertion: every canonical portal was
reported as having a non-integer `traversal_cost` and endpoint position. Godot 4.6.2 on the Linux
runner decodes JSON numeric literals as exactly integral `float` values here, while the Windows
build had yielded `int`. The P1-p validator accidentally authenticated the runtime representation
instead of the authored mathematical value.

The accepted contract is narrow: `int`, or a finite `float` exactly equal to its floor, is an
integer JSON number. Strings, fractions, NaN/infinity and non-positive traversal costs remain
fail-closed. Conversion happens only after this proof, so no lossy `int()` cast can make `1.5` or
`"1"` look valid. Portal access, owner, graph reachability and the atomic traversal transaction
remain unchanged.

## Coherent strides and teeth

1. Reconciled branch, review, PR and hosted-check exact identities.
2. Separated known stale anchors from the new `space_test` failure.
3. Extracted the hosted job route and isolated the truncated failing scene.
4. Reproduced the committed tip in `gamecraft-runner:4.6.2` on Linux.
5. Compared the complete Linux output with the Windows exact receipt.
6. Reduced the cause to JSON numeric runtime types, not authored-data drift.
7. Added one pure numeric predicate at the SpaceGraph validation boundary.
8. Kept all portal authority and transaction semantics unchanged.
9. Added integral-float positive teeth for cost and endpoint coordinates.
10. Added fractional, string and zero cost negatives plus fractional/string position negatives.
11. Proved fixture restoration leaves the canonical graph valid after every mutation arm.
12. Ran focused Windows and Linux gates, adjacent save/cargo/projection gates, map/static gates,
    a standard 12-seed no-golden grid and player-position framebuffer roundtrip.
13. Bound the implementation and this handoff to separate recoverable topic commits.

## Verification receipts

Implementation exact commit: `1b38961a28ac25d8fea35fbac17cea24a27fd09f`.

- Windows exact `space_test`: supervisor run
  `20260813T111303955Z_ee815a577b924a6cb691eec33d49300b`, outcome `pass`, source identity
  `exact_commit`, source/game-tree stable, cleanup verified.
- Linux exact `space_test`: a `git archive` of that commit in pinned
  `gamecraft-runner:4.6.2` / Godot 4.6.2 ended `space_test: 0 fail`; both numeric positives,
  five negatives and the restoration assertion passed.
- Adjacent candidate gates: P1-g manifest transaction, save migration and state projection passed
  Windows supervisor runs `20260813T110731499Z_b774d8da7c1c401d8ab2138883c2175f`,
  `20260813T110734081Z_d3da429525894fb7ad34842b3b85dfee`, and
  `20260813T110737422Z_9e752fbf5ac14e9b96b154b5f2540bc3`.
- Static/integration: `lint_data` passed 24 JSON / 13 agents; `audit_map` passed 64x48,
  walkable 2485, blockers 569, all reachability and foreign-key checks. Standard seeds 1-12,
  60 days, det3, no golden passed candidate receipt
  `20260813T110903661Z_cd62d5df6f45481f84e07f4cb220071a` and committed exact receipt
  `20260813T111419035Z_81ad1350aee148ceb585b661dc65fd57`.
- Player presentation recheck: pinned OpenGL roundtrip at seed 3 / tick 600 / player `[57,8]`
  retained zero changed pixels between town before/after and 98.59% interior/town difference.
  Exterior/interior hashes remained the canonical
  `2346d32d825f597bbc448d05283df213e07e48879925216bbec385a30ac4a60f` and
  `8265f061bdc84ca44ae8772255645540cc967b07e7bed27a1beb74c0e4dd2ae1`.

The isolated Linux framebuffer/scene copies live only under `%TEMP%` and are
`generated/rebuildable`; no external code or art entered the repository. The pinned image can
print missing optional NobodyWho GDExtension errors because the repository checkout does not carry
the platform binary; the established CI scanner filters that named optional extension only, while
any other runtime error remains fatal.

## Review, Git, hygiene, limits and recovery

The latest completed review brief read for this batch was 2026-08-13 09:00 CST, review head
`486353a` and frozen product `e01c5a1`; it was REQUEST CHANGES and stale before both P1-p and P1-q.
Its portal-authority concern maps to P1-p, while P1-q is the live hosted drift found after that
brief. A fresh scheduled review is still required.

No README, protected branch, anchor, golden, modelpath, complement ledger, user file, unknown-owner
worktree or source task was changed or cleaned. Recovery is a normal revert of the P1-q code and
evidence commits. Draft PR #6 must stay draft: after push it needs a new exact-tip hosted receipt,
and even a green `space_test` does not authorize anchor rebaking or erase the known stale-anchor
delivery blockers.
