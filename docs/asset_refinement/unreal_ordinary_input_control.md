# Ordinary native input control

`tools/unreal/ordinary_input.py` supplies bounded WASD key pairs over callbacks
owned by an explicitly authorized native session. It opens no app or connection,
selects no toolset, dispatches no general MCP tool and supplies no actor, clock,
pose, collision or needs setters. The owning runner still verifies source bytes,
exact native tool schema, world/controller/pawn identity, floor/contact policy,
actual stock edges, route completion and owned session shutdown.

Fine holds below 0.25 seconds release before a blocking held read. A later native
released/settled snapshot is mandatory; the owner validator returns True or
raises ObservationPending for bounded rereads. Other errors trigger the release
finally. Coarse holds retain a held observation. A submission receipt is not an
input-dispatch acknowledgment. Default ceilings remain 128 calls, 70 business /
100 wall seconds, 8 cleanup calls and 2 seconds for pulse work; callers may
only narrow them. Each operational RPC uses the remaining pulse time, checked
after supervision. Release cleanup remains separately bounded by the wall/call
budget even after a pulse expires. A malformed release receipt retains key
ownership so the owner can retry cleanup. Receipts still do not prove dispatch;
the later native observation and owned session shutdown remain mandatory.
The owner reserves remaining calls for its own session end.

KeyPairs records callback responses in memory and performs no file I/O.
Persist these records after owned input cleanup. For a caller-authorized control
phase using Client.request, set defer_history_persistence=True, release/close the
owned input session in finally, then reset the flag and call flush_history().
Discovery keeps immediate transcript persistence by default. The optional finite
request timeout may shorten the existing 15 second maximum. The client subtracts
its own supervision time before opening the request and refuses an expired
deadline before sending. These tracing hooks
add no dispatch authorization; do not use them to turn discovery into a general
remote-control CLI. The owner must bound response size and lifetime as before.

The motivating closed native 006 run used 19 pairs / 38 stock edges and 26
snapshots, 66 total control calls in 7.516 seconds. Closed replay checked 83
recorded natural route samples, a settled PERSISTENT_GROUND endpoint and a
settled return under the original 5.5 cm XY / 4 cm anchor-Z / speed 2 tolerances.
Intermediate legacy guide-Z was advisory; actual grounded support remained
mandatory. Source/canonical/global custody checks passed; the owned process was
waited/reaped with no remaining PIDs. This is recorded-route evidence. It is not
a visual, FPS, meal, sleep, whole-town or every-physics-frame qualification.

Run `python -B tools/unreal/test_ordinary_input.py` for inert timing/cleanup and
actual-client transcript tests. The numerical acceleration/braking fixture tests
timing behavior; no raw native trace, asset or private data bundle is distributed.
These inert tests do not qualify future geometry.
A real runner must retain closed actual-stock-edge and same-session replay. If
its RPC delay cannot resolve the arrival tolerance, stop within the finite
budget; a separately reviewed natural-frame release adapter may be needed.
