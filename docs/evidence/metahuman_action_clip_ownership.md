# Native MetaHuman action playback ownership

This source candidate is based on PR131 merge `7dc15c7b38bcc9d4082f19981ea02e5708ff528b`, followed only by the technical action-owner cherry-pick `381ebc7691ecf80293d47dcd8a61c41a49bac378` and one focused PIE regression. It grants no meal/contact authority and does not alter existing meal refusals.

`LivingTown.MetaHuman.ActionClipOwnership` uses the existing WorldV3 startup and public assembly APIs. It requires a fresh standalone EditorContext PIE session, normally selected Ben, the admitted17-field v2 descriptor, accepted current tee and original Core assets, and source-grounded spawn. It neither selects another persona nor relocates the player.

The test pins `/Game/LivingTown_UEPilot/MetaHumanDailyActions_v001/AS_EatBread.AS_EatBread` to the positive authoring001 package:2324237 bytes, SHA256 `0f88d5bcad7ac8b0f88de9a36b17c3324daa6c4e6f8eeefb291e90310ec560aa`. Root's future consumer must stage the qualified World481 package roster plus this one candidate (482 total), the existing8 raw files, and the exact v2 descriptor. Core114 is contained in the qualified World481 closure; the older visual host's runtime/source metadata is not a new build authority.

The one native regression checks:

1. `BeginActionClip` keeps the exact existing Body single-node instance, Body postprocess instance, Face ABP/postprocess instances and mode, and Outfit body leader. Natural stationary ticks retain the clip and advance animation time and bone revisions over at least3 samples and0.35 seconds.
2. Simulated W press/release enters the real controller/PlayerInput stack. Actual grounded displacement and speed must cause the character's normal tick to interrupt the clip and restore Walk on the same player. Natural stopping returns to Idle. An explicit owned end also restores the exact prior idle time and flags.
3. A separate normally begun, configured temporary actor deliberately assigns another asset/time/rate/flags to its same Body player. `EndActionClip` must return false and leave that foreign state untouched. This deliberate takeover assignment is not used as playback or walking evidence. Destroying the probe leaves the possessed player intact.

The test never manually ticks animation, sets the possessed player's pose/time, forces a transform, pauses the clock, changes animation tick policy, calls save/load or meal commands, or grants money/stock/needs. Natural needs decay remains allowed. Test cleanup releases W, ends any still-owned clip and destroys its temporary probe in the same observed live world.

After root integrates the remaining Face/food source and creates a fresh positive Game/Editor build pair, its finite qualified consumer can run the exact test with these additional arguments:

```text
-LivingTownCafeWorldV3 -CafeWorldPersona=ben
-LivingTownMetaHumanBen=<root-bound qualified v2 descriptor>
-LivingTownMetaHumanActionClipTest
-ExecCmds="Automation RunTests LivingTown.MetaHuman.ActionClipOwnership"
-ReportExportPath=<fresh owned output>/AutomationReport
```

Reuse the qualified WorldV3 private configuration, default game mode, assets, real input mappings, actual module/source binding and normal PIE lifecycle. Require exactly one exported test with state Success,0 errors, the qualified disclosed warning policy, and performed queue count1. The fresh native receipt is `Saved/MetaHuman/ActionClipOwnership.json` under the actual owned project-user Saved mapping.

No app, build or native test was run for this source candidate. Source review and `git diff --check` do not establish runtime success. The regression qualifies technical playback ownership only; it does not qualify eating contact, facial motion, food art, a full meal journey, screenshots or performance. Root owns fresh build/test execution and final integration.
