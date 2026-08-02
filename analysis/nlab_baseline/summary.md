# Narrative Lab P0 union baseline

## Outcome

**PASS, for the pinned source union only.** The complete CI suite finished with
exit code `0` at detached commit
`9bad1f411982a4c3c52268ca08b80412b7265699` after the existing Codex Python
runtime was added to the launcher environment. The literal requested command
remained:

```text
GODOT=C:/Users/yp/.local/bin/godot bash tools/ci.sh
```

- Isolated worktree: `E:\Documents\Dev\June\26th-nlab-baseline-9bad`
- Started: `2026-08-02T13:09:52.0345545+08:00`
- Ended: `2026-08-02T13:30:07.6922265+08:00`
- Wrapper elapsed: `1,215,658 ms` (CI-reported whole-run time: `1,215 s`)
- Exit code: `0`
- Full log: `ci.txt` (`52,953` bytes, `693` lines)
- `ci.txt` SHA-256: `53A828018101E4279B134064B61D19E1EC248FAE219CD27EF7205A2AFA8C8E11`
- Rendering: Docker runner was available and the visual gate ran; it was not
  skipped.

No tracked source was edited. After the run, both worktree and index diffs were
empty; `git status --short` in the isolated worktree contained only the
untracked `analysis/nlab_baseline/` evidence directory.

## Step-by-step verdicts

| Step | Verdict | Observed coverage / evidence | CI time |
|---|---|---|---:|
| 0 tracked weights/binaries | PASS | 2,072 tracked files inspected; filename/content arms 0 hits; three negative controls detected | 10 s |
| 1 data lint | PASS | 23 JSON files parsed; 16 required files; FKs for 12 agents, 12 personas, 8 objects | 0 s |
| 1b map audit | PASS | 64x48; 2,653 walkable; 403 blockers; 8 objects/worksites; 12 agents | 0 s |
| 2 link lint | PASS with default-mode warning | 123 Markdown files and 104 numbered docs; 12 branch-present/document-absent links were deliberately allowed because `LT_LINKS_STRICT` was not set | 1 s |
| 2b art gate | PASS with soft encoding note | 10/10 images pixel-identical to rebuild; 1,966,080 pixels; PNG container bytes are non-gating | 1 s |
| 2c terrain gate | PASS with soft encoding note | 13/13 tiles pixel-identical; 3,328 pixels; PNG container bytes are non-gating | 0 s |
| 2d asset gate | PASS | 22/22 shipped assets pixel-identical; 22/22 mutation probes detected; all 45 emote pairs above floors | 0 s |
| 2e recomputation gate | PASS | All 5 gated values matched; two explicitly record-only values did not match and printed red by design | 2 s |
| 2f complementarity guard | PASS with coverage warning | Negative controls worked and known unique inputs remained; baked ledger does not know invariant #43 | 0 s |
| 3 Godot import/parse | PASS | Import/parse clean | 9 s |
| 4 S0 | PASS | 12 seeds x 60 days; hard invariants 12/12; soft floor >=11/12; liveness; golden 12/12; determinism 3/3 | 160 s |
| 4a N=16 pool scale | PASS at the floor | 12 seeds x 60 days; hard invariants 12/12; #26 and #40 each 11/12; determinism 1/1; golden not enabled | 190 s |
| 4b LOD | PASS | N=48 x 3 days; camera-path independence, determinism, save/load and fresh/restart | 13 s |
| 4c DetGate | PASS | 4 tracks x 4 seeds x 20 days; hard/deterministic/golden 16/16 | 110 s |
| 4d BackendGate | PASS | 2 arms x 4 seeds x 30 days at N=12; hard/deterministic/closed-set 8/8; all internal negative controls detected | 111 s |
| 4e ModelPathGate | PASS | Encoding, cap 26, order, fail-closed parsing, breaker reset, 4 anchored seeds | 7 s |
| 4f VoiceGate | PASS | 3 seeds x 60 days; 300 `(persona, action)` pairs, 35 actions, all 12 personas, 0 empty | 27 s |
| 5 unit/integration scenes | PASS | 9/9: m2, reqlife, player agency/touch, replay, space, save/load, goals (12x14 days), story (12x40 days) | 385 s |
| 6 visual gate | PASS, executed | Docker screenshots plus day/night, void redraw, town/interior roundtrip, pond, 7-building shell, furniture roles and tree stands | 189 s |
| Whole suite | **PASS** | Final line `=== CI PASS ✅ ===`; wrapper exit `0` | 1,215 s |

## Non-gating findings and log interpretation

1. Link lint reported 12 references whose named branch exists but whose document
   does not. This is intentionally allowed in default mode; `LT_LINKS_STRICT=1`
   would make it red.
2. The recomputation registry printed red for two explicitly record-only rows:
   `palette-gpl-de00-6p3` (`6.3` documented vs `8.0659` measured) and
   `lint-links-md-count` (`93` vs `123`). The five gated rows all matched.
3. The complementarity ledger was baked before invariant #43, so CI does not
   currently prove that #43 has an independently audited fixture capable of
   turning it red.
4. Main S0's diagnostic-only #15 passed 10/12. At N=16, soft #26 and #40 each
   passed 11/12, exactly the configured floor rather than with spare seed
   margin. All hard invariants passed 12/12.
5. Every headless Godot gate logged the missing optional NobodyWho GDExtension
   and an `ObjectDB instances leaked at exit` warning. The gates still returned
   PASS. ModelPathGate also deliberately caused a JSON parse error and SLM
   breaker warnings as negative/fail-closed probes.
6. Pillow 12.2.0 emitted `Image.getdata` deprecation warnings in asset and visual
   assertions. They are future-maintenance warnings, not current assertion
   failures. A few Python-produced Chinese status lines are mojibake in the
   mixed Windows/Git-Bash log; their adjacent machine counts and PASS verdicts
   remain readable.

## Launcher history

Two failed attempts are retained, because deleting them would hide an important
reproducibility condition:

- `ci_launch_failed_wsl.txt`: PATH resolved `bash` to Windows' WSL launcher,
  which could not start `/bin/bash`; exit `1`, 354 ms, 10 lines, SHA-256
  `5F4044E50745B277EC64BBBF29D800B288AAA3881C176ECFC575536304485B28`.
- `ci_env_failed_missing_python.txt`: Git Bash ran the entire non-fail-fast CI,
  but `python` was absent from its PATH. Steps 0-2f failed immediately and the
  visual gate ended with exit 127; exit `1`, 941,215 ms, 391 lines, SHA-256
  `352B1CBEB6B6C651A35A4C5F021A601CC9B24B1E794DBC80D4F0C9CE76BA061E`.

The successful run used `E:\Program Files\Git\bin\bash.exe` and prepended the
existing runtime directory
`C:\Users\yp\.cache\codex-runtimes\codex-primary-runtime\dependencies\python`
to PATH. No package was installed and no repository file was changed to make
the run green.

## Detection envelope

### Detects

- Whether the exact pinned union passes the repository's complete automated CI
  under Godot `4.6.2-stable (official).71f334935` and the available Python
  dependencies.
- The enumerated static/data/map/art gates, fixed-grid simulation invariants,
  cross-process goldens, same-seed determinism, scale and LOD probes, scenario
  tracks, synthetic external-backend closed-set behavior, model-path encoding,
  voice coverage, the nine scene tests, and the automated rendered-image
  metrics listed above.
- Whether the visual runner was actually used in this run: it was, via Docker,
  with screenshots at 1280x768 and explicit per-gate measurements.

### Does not detect

- Any change after pinned commit `9bad1f4`. The active main branch advanced
  while this baseline was running; this evidence intentionally does not claim
  that later commits pass.
- A Narrative Lab runtime or web-maze integration. That feature does not exist
  in the pinned union, so a green baseline is only a safe pre-integration
  reference point.
- Real NobodyWho/SLM-native inference: the optional extension was unavailable.
  BackendGate uses controlled/synthetic arms, and ModelPathGate tests encoding
  and fail-closed/fallback behavior.
- Exhaustive seeds, population sizes, durations, phone/browser UX, manual art
  judgment, human narrative quality, accessibility, performance under product
  load, or exploratory playtesting beyond the configured fixtures.
- Strict Markdown link integrity, because `LT_LINKS_STRICT=1` was not enabled;
  the 12 allowed broken references remain debt.
- Independently audited fixture sensitivity for invariant #43, or fresh golden
  coverage for the N=16 scale arm (that arm explicitly ran without `--golden`).
- Replay of arbitrary player action history by `goto_tick`, or inclusion of all
  future narrative receipt/custody state in the existing invariant digest. A
  CI pass must not be used as evidence for those planned Narrative Lab
  contracts.

### Confidence

**High** that the repository's current complete CI suite passes at the exact
pinned commit in the recorded environment: the SHA was verified, all 693 log
lines were audited, the final process returned 0, the render gate executed, and
the evidence log is hashed. **Limited** confidence for Narrative Lab production
readiness, because that subsystem and the user-facing/manual checks above are
outside this baseline's detection envelope.
