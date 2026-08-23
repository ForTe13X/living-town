# P1-ac fresh-review closure (corrective pass, 2026-08-21)

This batch closes the live review blockers without rebaking protected anchors.

## Corrective review findings addressed

The corrective pass is intentionally limited to this file, `Main.gd`, the focused
warehouse test, and the P1-w readiness verifier/evidence. Protected anchors remain
untouched. The asynchronous context now binds target id, target position, player
context, Sim instance identity, session identity, and request generation. A stale
callback cannot clear a newer request's thinking state or write UI/memory; only the
request that owns the current presentation may clear its own thinking flag.

The focused test covers target movement while still in range, request A replaced by
request B followed by late A, portal/load invalidation, and a duplicate txid separated
by 5,001 unrelated rows. The projection receipt budget is asserted against the
existing projection query counter rather than the history-size constant.

The third corrective pass adds lifecycle cancellation outside the failed callback,
with exact no-mutation assertions for wrong Sim instance and session-only replacement.
The query-budget mutation control injects one extra counted dereference and observes
the budget failure before restoring the counter, proving a discriminating red path.

The readiness verifier now requires an externally supplied review ref, report blob,
and SHA-256 when authorization is requested. `ExternalReviewReportPath` is a
repository-relative path resolved with `git show <ref>:<path>`; the verifier first
resolves the ref commit, rejects the candidate branch/upstream and same-head refs,
hashes the exact Git-provided UTF-8 bytes, and then checks the completed report's
candidate head, game tree, and verdict. Missing ref/path/blob, hash mismatch,
tampering, same-ref, and candidate-owned controls all fail closed. The committed
readiness evidence explicitly remains `not_bound_until_external_report_is_supplied`;
it cannot self-approve an anchor rebake.

Detached QA mode is fail-closed: it is permitted only for the non-authorizing
`prepared_not_authorized` decision, requires a genuinely detached HEAD, and requires
the externally resolved upstream candidate ref to equal the exact expected head.
Attached execution still requires the named product branch. The positive fixture is a
committed external `REQUEST_CHANGES` report only; no authorizing verdict is fabricated.

## Chat authority

`Main._on_player_say` is the single authority used by the LineEdit, `KEY_C`, and demo
chat steps. In player context it requires a non-self target on the player's current
space/floor and Manhattan distance `<= 2` (adjacent/one-hop positive; farther targets
are denied). Observer/demo context has no player body, so its explicit scope is the
active space/floor. A generation token, immutable target id, and captured player
context are passed to the callback; `_apply_chat_reply` re-resolves the target and
rechecks generation, identity, space/floor, position, reachability, and observatory
read-only context before any thinking/UI/memory write.

Focused evidence includes adjacent positive, same-plane remote denial, portal-entry
negative, and generation/session replacement negative callbacks.

## Cargo history authority

Arrival, latest receipt, and unload transaction membership are maintained by an index
rebuilt on load and incrementally updated by `_log_event`. The ledger remains the
authority: event-log size or indexed-row mismatches return `invalid`; no redraw path
scans unrelated history. Exact transaction membership uses every indexed row for the
txid, so a far-separated duplicate cannot be hidden by a local neighborhood.

The focused test appends 5,000 unrelated events, projects the same receipt, and
asserts completion plus bounded event reads (`<= 2`) and a fixed production query
contract of exactly `91` operations covering ledger/index/transaction dereferences.
The mutation hook injects one concrete production-path dereference (`92`) and must
trip the fixed budget before the hook/state is restored to the exact `91`-operation
positive path. This is a behavioral/performance tooth rather than checking only a
limit constant.

The hosted run `32431484183` completed with visual canary PASS and only the four
known protected anchor families red (complement ledger, S0 golden, DetGate golden,
and ModelPath anchor). Its core failure is recorded as stale-anchor evidence, not
as permission to rebake. Visual and focused/integration runtime paths passed; no
fifth runtime/determinism/focused/provenance family was observed. The run head is
`ded53e95db0c8b8666aeac64a199b59cf6fb8574` with game tree
`ce46441a3e16e863752704375d0a01f814b75399`.

External-binding control matrix (run from a clean detached checkout):

1. Positive: external review ref + repository-relative report path + exact SHA-256
   of `git show <ref>:<path>` ⇒ accepts only when head/tree/verdict match.
2. Negative: omit ref/path/hash; use missing path; alter one report byte; supply a
   wrong SHA; use `codex/p1a-takeover`/its upstream; or use a ref resolving to the
   candidate head ⇒ each is rejected before any anchor decision.

Narrative packet: DEFER. It is a useful observatory checklist but adds no human
consequence or new persistent state, so it is not consumed as product content here.
