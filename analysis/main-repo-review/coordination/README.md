# Coordination Room event stream

`room_state.json` is the producer-owned current-state snapshot.

The canonical append-only event stream is `room_events.v1.jsonl`. It contains one UTF-8 JSON object per LF-terminated line. Only the producer may append to it, and existing bytes must not be changed.

`room_events.v1.provenance.json` maps every migrated event to both its original raw-object SHA-256 and its canonical v1 line SHA-256. It also records the immutable Docker generator, source commit, stream hashes, object counts, and migration authority.

`room_events.jsonl` is the immutable legacy source. It contains historical concatenated objects and is retained byte-for-byte for provenance; it is no longer the canonical append target.

Current migration identity:

- Legacy commit: `5918d49ae1f21e8030e7a87c063b5e18b79c1a5d`
- Legacy SHA-256: `6adf2d4dff7b007c3ce25bdeecfd0d042586c25dd8a4a017a88b10c981ead18c`
- Legacy objects: 292
- Migration-baseline v1 SHA-256: `65e9b33307ef3588424daf36ea73b49dcc555d0e6b76e49ec01b21c9654a7ea4`
- Migration-baseline objects: 293, including the migration event
- Current canonical v1 SHA-256: `b32ac45ca8c487cf4594e856124e4640ebbc327b35d4c8b093f75867436c20c0`
- Current canonical v1 objects: 296, including the publication-recovery reservation
- Provenance SHA-256: `baac249233a690211c1c735095da6b4e5bef3c48c3c85550ddf707dd35cf8574`

Rollback is pointer-only: restore the legacy path in `room_state.json` and remove the two v1 artifacts through a reviewed coordination commit. Never rewrite master, integration, or the legacy event bytes.
