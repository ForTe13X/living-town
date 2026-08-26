# P1-e schema-2 save migration + player-view product reference

Date: 2026-08-12 CST

Branch: `codex/p1a-takeover`

Purpose: make the P1-b/P1-c authoritative cargo state safe across old saves, while giving integration reviewers a reproducible player-position view of the East Ocean slice instead of relying on headless or map-only evidence.

## Save contract

- Current codec: `SAVE_SCHEMA=2`; schema 1 and 2 are accepted, any other schema is rejected.
- Atomic load: header/blob schema, magic, state keys, value types, population identity and CargoManifest cross-fields are validated on a migrated copy before any live `Sim` field is applied. A rejection leaves the receiving simulation unchanged.
- Schema-1 migration:
  - A pre-P1 manifest shape with neither cargo field receives explicit empty `cargo_manifests` / `cargo_manifest_order`; receiver state can never leak into the old save.
  - Missing `core_population` is derived from saved agents by excluding exact-boolean player/affiliate records.
  - A P1-a-only unload advert is upgraded with a `manifest_node` cargo gate and any old unload option is cleared, so a route-less old town cannot resume ghost unloading.
  - A transitional P1-b schema-1 save with both cargo fields and an engine-authorized mid-use option is validated and preserved.
- Runtime connections `backend`, `ext` and `decision_sink` are receiver-owned: they are never saved or applied from a save file.
- Honest boundary: a pre-P1 old world/logistics/agent snapshot remains that old world after migration. No manifest is synthesized from historical stock and no physical East Ocean upgrade is fabricated. The result is safe deterministic continuation, not byte-identical old-engine replay or automatic content migration.

## Exact legacy fixture

- Source commit: `d46cbb132595185c3420bb4eb8fd7f28512baa85`.
- Engine: Godot `4.6.2.stable.official.71f334935`.
- Seed/tick/schema: `20260626` / `0` / `1`.
- Raw `store_var` envelope: 271000 bytes, SHA-256 `84A9353F7C85A8BA191FEB45AFB644982DE273EB7380475930E509B4D68892B4`.
- Repository form: deterministic gzip + base64 split into four small transport parts under `game/fixtures/`; `save_schema1_legacy_contract.json` is the provenance and reassembly interface.
- License/source: generated solely from this repository's exact Git commit; no external code or asset input.

## Reusable product-visual interface

- `Main.gd --player-pos X Y` is a deterministic presentation/test seam. It only changes the spawn point supplied to `Sim.add_player`; default gameplay remains the plaza.
- Canonical P1-e reference command is wired into `tools/visual_gate.sh`: seed 3, tick 600, `--player --player-pos 58 8 --select player`.
- Output `vg_player_east_ocean.png` uses the real 1280x768 framebuffer. It frames the player, ready CargoManifest vessel, dock/crates, observation panel, timeline and the actual seven-verb interaction bar together.
- This is a presentation reference, not a pixel golden. Existing carrier ON/OFF same-seed negative control remains the automated art assertion; screenshots stay generated/rebuildable in the chosen output directory.
- Integration checklist for later vertical slices: place the player at the mechanic; show the affordance and resulting world state; inspect legibility, occlusion, interaction reach, HUD hierarchy, spatial storytelling and art consistency; retain one reproducible screenshot and, for motion/timing changes, a short deterministic recording.

## Verification

- `save_migration_test`: exact d46 fixture migrates identically into clean and polluted receivers, replays 300 ticks identically, resaves schema 2, retains runtime handles, closes P1-a ghost unload, and rejects header/blob mismatch, partial cargo, unknown key, wrong type, bad core, dangling cargo and non-bool identity atomically.
- `save_load_test`, `p1b_cargo_manifest_test`, `player_touch_test`, `p1c_east_ocean_carrier_test`, `p1d_scale_export_test`: PASS on Godot 4.6.2; no native-crash pattern.
- Player-view reference: fixed Docker/Xvfb `gamecraft-runner:4.6.2`, real framebuffer capture succeeded and was visually inspected for the gameplay/UI/UX/art composition above.

## Delivery and hygiene

- The fixture is active test data, not a golden/modelpath/complement rebake.
- Existing NobodyWho DLL and ObjectDB exit messages remain known environment noise; deliberate malformed-save teeth emit expected fail-closed warnings.
- README and its protected first-screen demo remain untouched. No archive/clean operation is part of this batch.
- PR delivery remains blocked by stale golden/modelpath/complement anchors and the lack of an exact integration-tip push receipt; this batch must stay draft until the authorized finalize protocol is satisfied.
