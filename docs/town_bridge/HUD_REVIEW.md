# HUD and lighting calibration

`tools/town_upgrade/runtime_presentation_probe.gd` runs one actual `Main.tscn`
with the staged town and existing LifeMode. It selects Aria through
`start_life`, pauses through viewport input, and holds the observed semantic
state while comparing four light settings at three authored camera locations.
It also exercises the compact/expanded HUD at **1280×768** and **960×540**.
This is a reusable diagnostic, separate from the normal gameplay walkthrough.

Use an already imported, verified local project and an installed Godot 4.6
desktop binary. It needs a real framebuffer; `--headless` cannot supply these
screenshots. It does not fetch assets, install packages, download model weights
or invoke an AI backend. Run one engine job at a time and leave the diagnostic
window alone while its scripted input runs.

From the repository root in PowerShell, replace the two executable paths and
choose a **new absolute evidence directory** for every attempt:

```powershell
$GodotPath = 'C:/path/to/Godot_v4.6.2-stable_win64.exe'
$PythonPath = 'C:/path/to/python.exe'  # Pillow and NumPy already installed
$RepoRoot = (Get-Location).Path
$RunDir = 'F:/Living Town/2026-10-20_Refined_Town/gameplay/presentation_probe_001'
$ProbeArgs = @(
  '--rendering-method', 'gl_compatibility', '--resolution', '1280x768',
  '--script', (Join-Path $RepoRoot 'tools/town_upgrade/runtime_presentation_probe.gd'),
  '--', '--town3d', '--life', '--backend', 'logic', '--seed', '7',
  '--agents', '12', '--speed', '0', '--presentation-probe-dir', $RunDir
)
& (Join-Path $RepoRoot 'tools/run-godot-supervised.ps1') -Godot $GodotPath -TimeoutSec 900 -AllowDirtyCandidate -GodotArgs $ProbeArgs
if ($LASTEXITCODE -ne 0) { throw 'Calibration failed; retain its report and log.' }
& $PythonPath (Join-Path $RepoRoot 'tools/town_upgrade/runtime_presentation_stats.py') $RunDir
```

The canonical supervisor binds source identity, keeps unique logs and cleans up
only its own timed-out process tree. `-AllowDirtyCandidate` explicitly labels an
uncommitted candidate; omit it when running a clean reviewed commit. The probe
requires the explicit logic backend and paused startup flags shown above and
rejects extra gameplay, warmup or actor-position flags.

The capture script rejects a nonempty destination. The offline statistics
script refuses an existing `clipping_histograms.json`; retain previous evidence
instead of replacing it. Both scripts return a nonzero exit on a failed check.
The capture has no save/load or actor relocation step. It records the existence,
size and hash of existing settings/quicksaves before and after, without copying
their contents or restoring over a user's files.

The normal presentation order stays active: camera keeper at priority **49**,
actual `WorldView3D` at **50**, then a light-only override at **51**. Do not freeze
WorldView processing to stabilize lighting: that leaves cached bodies or
overlays from another camera/space. Each paired capture records actual camera
transform, camera size, renderer, light settings, image size and SHA-256.
Raw `__actual_subviewport.png` frames omit HUD; `__labeled_main.png` frames
retain the diagnostic label. `hud__*.png` frames retain the actual HUD.

The report checks every declared raw town/catalog and character model hash and
length before/after, required project/profile/projection sources, runtime script
and scene sources, and the probe itself. It records viewport mouse/key input
and its resulting expand/collapse state. It compares actor addresses, needs,
options, wallets, jobs, inventory, tick/day, event digest and invariant digest/
chain throughout the paused comparison. These observations do not replace a
complete save/replay or simulation equivalence suite.

| Control | Actual HUD behavior |
|---|---|
| Pause; 1×/2×/4× | Shared clock controls; blocked during selection, action menus, chat and bank/civic panels |
| H; activity title | Expand/collapse retained activity and history |
| Shift+H; wishes title | Expand/collapse wishes and aspiration progress |
| F | Toggle resident autonomy |
| E; Tab; Escape | Open nearby interaction, cycle target, close menu |
| F5 / F8 | Product save/load controls; deliberately **not exercised** by this calibration |

If an authored object is already safely in reach, the probe opens its real menu,
checks that its clock control is disabled, and closes it without selecting an
action. Otherwise `hud_safe_skips` records **SKIP** with the observed focus.
It never teleports a resident or fabricates a nearby fixture to turn a skip into
a pass. Clicking pause while already paused proves control reachability; it
does not prove a running pause/resume transition or speed progression.

Review every PNG at native resolution for clipped bilingual text, all five
needs, panel overlap, world occlusion and feedback contrast. Histogram white/
black fractions and weighted display-RGB values are **DESCRIPTIVE_ONLY**;
bright plaster may be intentional and no threshold grants aesthetic approval.
`DIAGNOSTIC_COMPLETE` only means the diagnostic's recorded checks passed.
Calibration remains **not gameplay evidence**, and does not approve actor
alignment, the whole town's concept fidelity or the final assets.

The first actual calibration's four HUD frames showed readable controls,
visible needs and separated panels at both sizes. Its disabled WorldView
processing made body/name alignment unsuitable for approval.

A fresh normal-process run on 2026-10-23 completed with stable sources and a
normal engine exit. Its four native-size HUD images and upper-home comparison
show readable needs, separated panels, a higher-contrast footer and aligned
stationary body/name markers. Ten actual mouse clicks and nine key events
exercise the panel controls. Existing settings and saves stayed unchanged.
The nearby-fixture menu checks remain two explicit skips. The local evidence
is `F:/Living Town/2026-10-20_Refined_Town/gameplay/presentation_v14_hud_normal_001`;
its calibration report SHA-256 is
`fb7990a7e55e126a5933178d59169af9f7afa06e8ca4c3e8c3f7c12ecbc526a7`.
This accepts the scoped stationary HUD calibration on the V14 staged town and
V5 characters. Use normal gameplay footage to prove movement, legal fixture
approach, action completion, modal choices, speed transitions and save/load
behavior on the final assets before delivery.

The fresh 90-second product preview on 2026-10-23 passed **32 checks** with
normal WorldView processing: real stair and door traversal, walked approach
and completed café counter use, a visible paused header while the real fixture
menu owns input, disabled clock buttons, autonomy and F5/F8 save/resume.
The compressed counter chapter uses the existing public 8× shortcut; this
does not change the full walkthrough's timing. The run restored the user's
prior save and exited normally with stable sources. Evidence:
`F:/Living Town/2026-10-20_Refined_Town/gameplay/preview_portal_product_002`,
report SHA-256
`31ce9b08abdcbb3a1b60a269ec68d74ca916dcd918cc86c4bf80d65d1e80272e`.
This proves the scoped HUD and preview route on V14 assets; the final asset
revision and complete 840-second route still require fresh evidence.
