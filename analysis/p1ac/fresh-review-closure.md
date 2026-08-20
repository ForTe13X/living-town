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

The readiness verifier now requires an externally supplied review ref, report blob,
and SHA-256 when authorization is requested. The blob must be completed, bind the
candidate product head and game tree, and carry the expected verdict. The committed
readiness evidence explicitly remains `not_bound_until_external_report_is_supplied`;
it cannot self-approve an anchor rebake.

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
asserts completion plus a bounded projection-read counter (`<= 2`), providing a
behavioral/performance tooth rather than checking only a limit constant.

Narrative packet: DEFER. It is a useful observatory checklist but adds no human
consequence or new persistent state, so it is not consumed as product content here.
