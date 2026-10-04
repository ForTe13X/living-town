# In-game observe–act capture

This lane runs the real Living Town scene in a rendered Godot process. An agent
reads each PNG and state observation, then sends one keyboard, click, wait, or
quit command. Inputs travel through Godot's viewport handlers; the bridge never
sets simulation state. It is useful for adaptive walkthroughs and visual review.
It does not prove physical host input in an exported executable or replace a
human novice session.

All capture code is under `tools/`; the exported `game/` tree is unchanged. The
launcher copies the **pinned Git game tree** outside the checkout. Its only
project change adds a unique `user://` directory to the copied `project.godot`.
`source_copy.py` checks every copied file against its pinned Git blob ID; optional
CRLF-to-LF normalization must be requested explicitly. It also removes exactly
the two user-directory lines and checks that the original project blob is
restored. The copy and output directory are retained for later verification.

## Run a session

Run from a clean committed worktree. Set `$godot` to the Godot 4.6.2 console
executable on this machine. Set `$sourceCommit` to the product commit being
captured; it can be older than the capture-tool commit if the game tree is the
same. The output path must be outside the source checkout.

```powershell
$godot = 'C:\path\to\Godot_v4.6.2-stable_win64_console.exe'
$sourceCommit = '4ba7749436c488112483da25f9e7436d9b1ee909'
$capture = Join-Path $env:TEMP ('living-town-capture-' + [guid]::NewGuid().ToString('N'))
& .\tools\in_game_capture\start.ps1 -Godot $godot -SourceCommit $sourceCommit `
  -CaptureRoot $capture -Leg session -AllowCrlfNormalization `
  -IdleTimeoutSec 900 -RunTimeoutSec 1800
```

The launcher prints `CAPTURE_ROOT` and `CAPTURE_COMMAND_DIR` before starting
Godot. Leave it running. In a second PowerShell terminal, read
`$capture\session\observations\000000.png` and `.json`; then choose one
action at a time. Observations include the read-only controlled-resident status,
recent canonical events, and event count/digest so a closed menu is not mistaken
for a completed service or social action. Each accepted action produces a
numbered receipt and the next rendered observation. Example:

```powershell
& .\tools\in_game_capture\send-command.ps1 -RunDir (Join-Path $capture 'session') `
  -Seq 1 -Action click -X 320 -Y 150
& .\tools\in_game_capture\send-command.ps1 -RunDir (Join-Path $capture 'session') `
  -Seq 2 -Action key -Code ENTER
```

The command set is `key`, `click`, `wait`, and `quit`. The supported keys are in
`live_bridge.gd`. For save/resume, press `SPACE` after play begins to pause,
then `F5`, then `quit`. This makes the saved day, tick, and position directly
comparable after F8. The wrapper retains `quicksave-after.dat` and its SHA-256. Wait for the
first launcher to exit before starting the resume leg.

## Fresh-process resume

```powershell
& .\tools\in_game_capture\start.ps1 -Godot $godot -CaptureRoot $capture `
  -Leg resume -IdleTimeoutSec 900 -RunTimeoutSec 1800
```

The resume leg verifies the first leg's saved bytes and reuses its isolated
`user://` directory. Send `F8`, inspect the restored resident/space frame, and
send `quit`. Then verify the retained bundle:

```powershell
python -X utf8 .\tools\in_game_capture\verify_run.py $capture --require-resume
```

The verifier resolves PNG and save paths **inside the bundle**, so moving the
bundle does not break its hashes. It rejects Windows drive, UNC, reserved-name,
and traversal components in bundle paths. Each accepted receipt hashes the exact
processed command and records the action result. The verifier also checks the
supervisor's original project/bridge path relationship and hashes the retained
Godot, stdout, and stderr logs by their bundle-local names. It checks contiguous
commands, receipts, rendered 1280×768 PNGs, source-copy proofs, supervisor
source stability and process cleanup, and the saved resident, space, day, tick,
and position restored by F8. Source-copy
proofs are repeated before and after each leg. The supervisor labels the run
`external_project_copy`; the Git blob proof supplies the product identity.

Fast path and evidence-tampering checks run without Godot:

```powershell
python -X utf8 -m unittest discover -s tools/in_game_capture -p test_capture_safety.py
```

Do not launch a second Godot run in the same checkout while this one is active.
The supervisor uses a checkout lock, timeout, and scoped process cleanup. A
timeout, crash, source drift, copy mismatch, or missing terminal `quit` fails
verification. Preserve the raw bundle if a run fails so its logs can be read.
