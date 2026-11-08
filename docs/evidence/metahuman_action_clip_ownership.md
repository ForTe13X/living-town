# Native MetaHuman action playback ownership

The technical action owner and focused PIE regression were introduced after
PR131 merge `7dc15c7b38bcc9d4082f19981ea02e5708ff528b`, using action-owner
cherry-pick `381ebc7691ecf80293d47dcd8a61c41a49bac378`. The regression has an
actual 032 native Success result admitted as technical data, with its raw host
post-reader failure preserved. It was not rerun or relabelled as a 034 test.
The later, separately admitted [034 meal journey](../asset_refinement/metahuman_meal_producer_v2.md)
exercises the conditional meal owner; this action-only test grants no meal or
contact authority.

`LivingTown.MetaHuman.ActionClipOwnership` uses the existing WorldV3 startup and public assembly APIs. It requires a fresh standalone EditorContext PIE session, normally selected Ben, the admitted 17-field v2 descriptor, accepted current tee and original Core assets, and source-grounded spawn. It neither selects another persona nor relocates the player.

The test pins `/Game/LivingTown_UEPilot/MetaHumanDailyActions_v001/AS_EatBread.AS_EatBread` to the positive authoring001 package: 2,324,237 bytes, SHA256 `0f88d5bcad7ac8b0f88de9a36b17c3324daa6c4e6f8eeefb291e90310ec560aa`. Its qualified fixture is the World481 package roster plus this one candidate (482 total), the existing 8 raw files, and the exact v2 descriptor. Core114 is contained in the qualified World481 closure; the older visual host's runtime/source metadata is not a new build authority. The action-only fixture deliberately omits the optional v2 meal capability: the test requires meals to remain unavailable, unchanged balances/stock, and no hunger/fun increase.

The one native regression checks:

1. `BeginActionClip` keeps the exact existing Body single-node instance, Body postprocess instance, Face ABP/postprocess instances and mode, and Outfit body leader. Natural stationary ticks retain the clip and advance animation time and bone revisions over at least 3 samples and 0.35 seconds.
2. Simulated W press/release enters the real controller/PlayerInput stack. Actual grounded displacement and speed must cause the character's normal tick to interrupt the clip and restore Walk on the same player. Natural stopping returns to Idle. An explicit owned end also restores the exact prior idle time and flags.
3. A separate normally begun, configured temporary actor deliberately assigns another asset/time/rate/flags to its same Body player. `EndActionClip` must return false and leave that foreign state untouched. This deliberate takeover assignment is not used as playback or walking evidence. Destroying the probe leaves the possessed player intact.

The test never manually ticks animation, sets the possessed player's pose/time, forces a transform, pauses the clock, changes animation tick policy, calls save/load or meal commands, or grants money/stock/needs. Natural needs decay remains allowed. Test cleanup releases W, ends any still-owned clip and destroys its temporary probe in the same observed live world.

The actual 032 consumer used the following native selection arguments with its
source-bound build pair, private WorldV3 configuration and fresh Saved mapping:

```text
-LivingTownCafeWorldV3 -CafeWorldPersona=ben
-LivingTownMetaHumanBen=<root-bound qualified v2 descriptor>
-LivingTownMetaHumanActionClipTest
-ExecCmds="Automation RunTests LivingTown.MetaHuman.ActionClipOwnership"
-ReportExportPath=<fresh owned output>/AutomationReport
```

Any future reproduction requires a fresh qualified host/output, default game
mode, assets, real input mappings, exact module/source binding and the same
action-only capability selection. Require exactly one exported test with state
Success, 0 errors, the qualified disclosed warning policy, and performed queue
count 1. Do not reuse or rewrite the retained 032 output. The native receipt is
`Saved/MetaHuman/ActionClipOwnership.json` under the actual owned project-user
Saved mapping.

## Actual 032 technical data admission

The native test exported Success in 8.258457 seconds with 0 errors and one exact
previously qualified external HTTP connectivity timeout warning. It ran on the
032 build family
`3662ce977491c0675e3f126a7a7a5d7ae9a5c23ba48f05d91a86b4925b99f421`;
this is distinct from the 034 meal family. The 1487-byte proof, SHA256
`60b1c81c7214e9f2b6920b515f25c5de717758540ca2e5d3deb2bcba3156efe4`,
records 20 natural stationary samples over 0.360542 seconds and matching action
time advancement, actual InputKey W movement, unchanged original pose owners,
and refusal to overwrite the isolated foreign same-player asset. Its measured
movement was 0.568891 cm at 34.1334 cm/s: sufficient for this narrow locomotion
transition assertion, not a walking-distance or navigation qualification.

The raw host remains `FAIL_RETAINED_NATIVE_HUD_INPUT_SEMANTIC`, SHA256
`b7c74584816991efeda75661a573f28f10d1935effa9b4c14ba688c67918b09d`.
After native assertions succeeded, the post-run saved-path reader received
`Path` values instead of strings. A separate CPU review rechecked the actual
path mapping, module identities, staged bytes/mtimes, frozen inputs and all six
closure checks with only those two argument conversions. Root admitted the
technical data in
`F:/Living Town/2026-10-20_Refined_Town/root_action032_semantic_data_review_v1_001/ROOT_ACTION032_DATA_ADMISSION.json`,
SHA256 `5bc065283d3f22554485dd21da389cf932b33ae2306080e2bb3057162d5e872a`.
There was no native rerun and no rewrite of the failed raw host status.

This admission covers technical playback ownership only. NullRHI supplied no
rendered eating contact, facial appearance, food art, hardware keypresses,
screenshots or FPS. The distinct 034 meal proof covers its real input/state
journey; neither scope establishes final art, all interruption cases or the
broader town goal. The [evidence index](metahuman_meal034_semantics.json) retains
the exact local receipt paths and hashes.
