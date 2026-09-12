# P1-s exact-tip delivery and fresh-review handoff

Date: 2026-08-14 CST
Branch: `codex/p1a-takeover`
Frozen head: `614ec1444ebf37430def111aa6275c8a7c3fe825`
Frozen base: `d46cbb132595185c3420bb4eb8fd7f28512baa85`
Frozen game tree: `d3668111f41d5384e0ed17efd3f2328d355d927c`

## Single delivery target

Turn P1-r's local non-anchor closure into a fail-closed hosted-delivery receipt and a compact input
packet for the next independent review and, only after that review allows it, the R12 anchor-finalize
batch. This batch owns only this card, its read-only identity verifier and the short baton-ledger
entry. It does not modify `game/`, README, any golden/ModelPath/complement anchor, protected branch,
release state or another worktree.

Internal DAG: freeze PR identities -> verify review cutoff -> bind Actions run -> verify synthetic
merge parents -> require terminal run -> classify every failure family -> reconcile P1-r local
receipts -> publish review/finalize inputs -> record stop/recovery boundary -> lint/stage/commit ->
normal push -> reconcile the new docs-only exact-tip run.

Stop conditions: a non-anchor product failure, mismatched head/base/merge parent/game tree, a run that
is not terminal, a new completed review that still identifies an unclosed product blocker, or any
dirty/unknown-owner overlap. Any such result keeps PR #6 draft and forbids anchor writes.

## Fail-closed identity verifier

`verify-exact-tip-delivery.ps1` reads only `gh` and local Git objects. It requires exact run
head/event/terminal status, association to PR #6, exact synthetic-merge SHA and ordered base/head
parents, at least one terminal job, and equality of product-head versus merge `game/` tree.
`-RequireLivePr` additionally proves that the mutable live PR still has the same head/base. It
deliberately does **not** equate
`conclusion=failure` with an identity failure: the handoff card separately classifies the terminal
job log so stale evidence anchors cannot hide a product failure, and expected anchor failures cannot
be mislabeled as infrastructure or product regressions.

Canonical invocation for this packet:

```powershell
& analysis/p1s/verify-exact-tip-delivery.ps1 `
  -RunId 31701895953 `
  -ExpectedHead 614ec1444ebf37430def111aa6275c8a7c3fe825 `
  -ExpectedBase d46cbb132595185c3420bb4eb8fd7f28512baa85 `
  -ExpectedMerge a688b1c56ca45626aa544fbab7a619ca06d67804
```

Two negative teeth ran before the positive receipt:

- while run `31701895953` was `in_progress`, the command stopped on
  `run status mismatch: actual=in_progress expected=completed` and emitted no receipt;
- substituting the previous completed run `31694970713` with `-RequireLivePr` stopped on live
  PR-head mismatch because PR #6 had advanced from `b0a501b` to `614ec14`. A stale run therefore
  cannot impersonate the current PR even when its own immutable run identity is internally coherent.

The positive receipt also passed once with `-RequireLivePr` before this docs-only handoff commit.
The canonical invocation above intentionally omits that switch so the run-head + merge-parent receipt
remains reproducible after this card advances the live PR head; a later live-head claim must always
add the switch and supply the later run's own identities. GitHub's run API currently reports the
associated PR's **live** head/base under `pull_requests[]`; a negative replay proved those refs drift
even for an old run, so the verifier uses that array only for PR-number association and never calls
it an immutable snapshot.

The implementation originally typed `RunId` as 32-bit; the first negative invocation correctly
failed because modern GitHub run IDs exceed that range. It now uses `Int64`, and both semantic
negative teeth above exercise the intended verifier rather than parameter binding.

## Hosted terminal classification

Run `31701895953` completed `failure` at 2026-08-13 21:14:22 CST. The positive verifier receipt is:

- PR head `614ec1444ebf37430def111aa6275c8a7c3fe825`, base
  `d46cbb132595185c3420bb4eb8fd7f28512baa85`, Draft/UNSTABLE;
- checkout/synthetic merge `a688b1c56ca45626aa544fbab7a619ca06d67804`, whose ordered parents are
  exactly base then head; the GitHub merge commit is signed/verified;
- head and merge `game/` tree are both `d3668111f41d5384e0ed17efd3f2328d355d927c`;
- pull-request run and its only job are both terminal; run conclusion and job conclusion are
  `failure` rather than being silently recoded as green.

The complete `gh run view --log` stream is 270,836 bytes with SHA-256
`1871dd211ed1157defd6c20adf9a3baa274ec3ab35faf7bf6e056885b0459061`. Its CI gate took 1,447
seconds and contains exactly four `FAIL:` markers:

1. complement ledger stale (`eabcb07...` versus `d366811...`) and missing valid
   `_meta.hard_ids_at_bake`;
2. S0 golden mismatch, while hard 12/12, soft threshold, liveness and same-seed det 3/3 pass;
3. DetGate golden mismatch 0/16, while hard 16/16, same-seed repeat 16/16 and data fingerprint
   16/16 pass;
4. ModelPath submitted anchor differs in four seed summaries and its candidate-scale summary;
   the encoding, cap, fail-closed parser and SLM breaker teeth pass before those five anchor rows.

There is no fifth product/infrastructure failure. The runtime-scanner exact-set/duplicate/missing/
unexpected self-test passes; the P1-g owning scene passes after its private exact-set scan; the
state-projection gate passes with all twelve declared writer-rejection families appearing once.
All sixteen unit/integration scenes pass: m2, reqlife, player agency/touch, P1-a/b/c/d/g, S4 replay,
space, save/load/migration, goals, story and event prose. BackendGate passes 8/8 hard/repeat/closed
set plus its adversarial controls. Optional NobodyWho GDExtension startup noise remains the named
existing import exception. GitHub visual is an explicit SKIP because Mesa/GL is unpinned and is not
claimed as hosted presentation coverage.

## Review/finalize handoff and stop decision

The latest completed independent review available at batch start was the 2026-08-13 09:00 CST brief,
review head `486353a`, frozen product `e01c5a1`, verdict REQUEST CHANGES. Its P1-m writer/supervisor,
pending-manifest authority and portal-authority blockers are closed by later committed P1-m through
P1-q product work and P1-r receipts, but that makes the brief stale rather than approving the newer
tree. The 21:10 scheduled window is now actively reviewing exact `614ec14`. Its in-progress findings
agree that the old P1-m/o/p/q blockers and the four hosted failure families are closed/classified,
but its provisional product judgment separates mechanical bake readiness from semantic freeze:
East Ocean draw/navigation consistency and the intended warehouse milestone still require
adjudication. This is adversarial evidence, not a completed verdict, so it cannot authorize a rebake.

Inputs already prepared for a fresh review are in `analysis/p1r/anchor-finalize-readiness.md`:
held-out 13-30, exact-total N24, non-vacuous logistics ON, true-zero OFF, deterministic repeats and
old-anchor-tree pre/post attribution. A fresh review must freeze at least head `614ec14`, inspect the
hosted terminal classification below, and explicitly adjudicate the authored manifest plus portal
contracts. Until then the stop decision is unchanged: PR #6 stays draft/unmergeable and no anchor is
rebaked. The recovery trigger is a completed review covering this exact product game tree, followed
by a dedicated single-committed-tree Harness + DetGate + ModelPath + complement finalize batch.

## Provenance, limitations and hygiene

No external code or asset is used. The verifier composes repository Git objects and GitHub metadata;
it does not make network results timeless, so every consumer must supply expected run/merge SHAs and
must not silently substitute current PR refs. GitHub-hosted visual remains outside this packet unless
the run uses a pinned framebuffer stack. Unknown-owner worktrees, generated caches and source tasks
remain untouched; no archive or clean action is performed.
