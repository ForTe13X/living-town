# Verification log

## Environment and scope

- Repository: `ForTe13X/living-town`
- Reviewed local HEAD: `e56815189ba48acd50885999c2e0f1202023dff6`
- Remote PR base: `1d2be97ee1af291092b9c758c26287453737f335`
- Local divergence at review start: `master...origin/master [ahead 7]`
- Godot runtime: `4.6.2.stable.official`
- Node: `v24.14.0`
- OS shell: PowerShell on Windows
- Review method: static code/data/docs inspection plus local headless execution

The current `master` worktree was clean before and after review. All report edits were made in a separate worktree and branch.

## Repository inventory

| Item | Observed |
|---|---:|
| Tracked files | 406 |
| GDScript files | 31 |
| GDScript lines | 8,096 |
| `Sim.gd` | 2,423 lines |
| `Main.gd` | 935 lines |
| `AIBackend.gd` | 725 lines at reviewed HEAD |
| Git pack size | about 100.6 MiB |
| GitHub Actions workflows | 0 |

Largest tracked objects are demo MP4/GIF files and the CJK font, not source code.

## Executed checks

| Check | Command / scope | Result |
|---|---|---|
| Git baseline | `git status --short --branch`, log, remote, divergence | Clean; local master ahead 7 |
| Project import/parse | `godot --headless --path game --editor --quit-after 1` | PASS, exit 0 |
| Main scene smoke | `godot --headless --path game --quit-after 120` | PASS, exit 0 |
| README Node quick path | `node tools/sim_social_port.mjs --days 30 --seed 20260626 --verbose` | FAIL, exit 1; #5, #8, #20 |
| Node longer path | same, `--days 60` | PASS, 33/33 |
| README Godot soak | `godot --headless --path game --script res://scripts/sim_soak.gd -- --days 30 --seed 20260626` | FAIL, exit 1; #8 commitments 0/0 |
| Canonical S0 | `Harness.gd --seeds 1-12 --days 60 --det 3` | PASS; hard 12/12, soft gate pass, deterministic 3/3 |
| Causal S5 | `CausalHarness.gd --seeds 1-8 --days 40` | PASS; all 3 hypotheses met ACE gate |
| M2 backend mock/parse | `res://scenes/m2_test.tscn` | PASS, exit 0; expected invalid JSON cases emit stderr noise |
| S4 replay, 200 ticks | `res://scenes/s4_replay_test.tscn -- --ticks 200` | PASS; equal digest, drift 0 |
| S4 replay, 1,000 ticks | same, `--ticks 1000` | PASS; equal digest, drift 0 |
| Player agency | `res://scenes/player_agency_test.tscn` | FAIL, exit 1 only on stale agent-count assertion; remaining checks pass |
| Markdown relative links | local PowerShell link scan, repo Markdown only | 7 broken image references |
| Ignore audit | `git status --ignored`, `git check-ignore` | Models/build/keystores/binaries ignored as intended; 715 `.import` and 38 `.uid` files present locally but all over-ignored |
| Full Scale suite attempt | N80 and N160 LodAblation commands, run concurrently | Inconclusive; both hit 304 s command timeout; not counted as a test failure |

## Canonical S0 details

The strongest current signal is positive:

- 12 seeds, 60 days each
- 37 invariants
- every hard invariant passed 12/12
- soft #5 passed 11/12, satisfying the configured soft gate
- double-run deterministic digest passed 3/3
- overall S0 exit code 0

This is why the review does **not** classify the deterministic core as broken. The issue is that README exposes a shorter single-seed command as a reliable validation path even though the current social distribution needs the 60-day cross-seed gate.

## S5 details

The causal bench passed its configured threshold:

- standing → exclusion: ACE 1.00
- openness → attitude movement: ACE 0.38
- trust → investment: ACE 0.63

This is a meaningful strength: the project tests whether intended mechanisms cause outcomes, not only whether the simulation avoids crashes.

## Reproduced public-command failures

### Node 30-day quick path

Observed failures:

- #5 rumor propagation
- #8 commitment lifecycle
- #20 rumor stifling

The same seed at 60 days passed all 33 Node assertions. This supports changing the public contract rather than treating the 30-day output alone as a catastrophic regression.

### Godot 30-day soak

Observed:

- 36/37 pass
- #8 commitment lifecycle fails because no invite/meet occurred in the selected seed/window
- needs, money conservation, elections and the other social checks passed

### Player agency

The test still expects 6 NPCs + player = 7, while current data starts with 12 NPCs + player = 13. Every later player-action check in the run passed, including greet/give/gossip/invite, mediation, NPC-to-player interaction and player survival across scrub.

## Broken documentation references

The following references point to files that do not exist under their current names:

- `README.md:24` → `docs/media/shot-06-subtitled-demo.png`
- `README_EN.md:24` → `docs/media/shot-06-subtitled-demo.png`
- `docs/07-技术文档-社交底座.md:8` → `media/shot-04-midgame.png`
- `docs/07-技术文档-社交底座.md:110` → `media/shot-03-confront-reconcile.png`
- `docs/07-技术文档-社交底座.md:128` → `media/shot-05-relationship-graph.png`
- `docs/07-技术文档-社交底座.md:141` → `media/shot-06-subtitled-demo.png`
- `docs/08-测试与验证.md:76` → `media/shot-03-confront-reconcile.png`

In addition, `docs/18-android-apk-build.md:19` refers to a missing `tools/build_android.ps1`.

The README cover block itself was not modified.

## High-priority static proofs

The following findings do not depend on a real model being available:

1. Pending requests do not retain their prompt candidate set.
2. HTTP timeout cleanup does not cancel the HTTPRequest.
3. Callback identity is only the agent id, so a late request can target a newer pending entry.
4. restart/scrub does not establish a new AI request epoch.
5. job advertise injection queries an Array with a string id before converting objects to a Dictionary.
6. player actions are explicitly excluded from `goto_tick()` replay.
7. production Main does not enable decision recording or automatically load a replay trace.
8. candidate replay hash is sorted and omits target/effect fields while replay uses an array index.
9. `.uid` and `.import` are globally ignored.
10. the bundled SimHei font is acknowledged by the repository itself as unsuitable for formal release.

## Checks not completed

- No real LM Studio response-quality evaluation.
- No real NobodyWho/GGUF lifecycle stress test; static lifecycle findings remain valid, but crash/OOM frequency was not measured.
- No physical Android device test and no store submission policy check.
- No release APK rebuilt during this review.
- The full Scale suite was not completed because two heavy variants were launched concurrently and both hit the 304-second command timeout. This result is explicitly inconclusive.
- No legal opinion was produced; the font/asset section is a release-risk audit based on repository provenance and stated licenses.

## Representative read-only commands

```powershell
git status --short --branch
git log --oneline --decorate --graph --max-count=20 --all
git diff --stat origin/master..master
rg --files -g '!build/**' -g '!**/.git/**'
rg -n "TODO|FIXME|HACK|XXX" game tools docs
godot --headless --path game --editor --quit-after 1
godot --headless --path game --quit-after 120
godot --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3
godot --headless --path game --script res://bench/CausalHarness.gd -- --seeds 1-8 --days 40
godot --headless --path game res://scenes/m2_test.tscn
godot --headless --path game res://scenes/s4_replay_test.tscn -- --ticks 1000
godot --headless --path game res://scenes/player_agency_test.tscn
node tools/sim_social_port.mjs --days 30 --seed 20260626 --verbose
node tools/sim_social_port.mjs --days 60 --seed 20260626
```
