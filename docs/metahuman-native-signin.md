# Native MetaHuman sign-in launcher

The Editor bridge exposes a small sign-in window without opening the full MetaHuman Creator viewport. Native service status is cached: reading it does not attempt persistent authentication or send network requests. Previously, reading status every Slate tick repeatedly invoked the SDK's silent persistent login and produced rate-limit errors.

`LivingTownMetaHumanAuth` is Editor-only. It performs one existing-session check when opening the window and one verification after successful manual sign-in. The button stays disabled during an outstanding check or login. A failed login permits a manual retry after 30 seconds; there is no automatic retry. The readback reports button events, readiness, and native login success without returning account names, account IDs, credentials, or tokens. Closing the launcher does not sign out.

## Private Editor setup

Before starting the Editor, create a directory inside the project for its JSON user configuration and set `LT_EDITOR_JSON_CONFIG_DIR` to that absolute path. Seed `EditorLayout.json`, `ContentBrowser.json`, and `FilterBar.json` with `{}` there. Module startup registers this directory as the last EditorConfig user layer. Registration is refused if the directory is absent, outside the project, or too late in Editor initialization. Launcher calls are refused outside the owning non-PIE Editor context or without that registration.

Once the Editor has initialized, these Python calls expose the native window and cached result:

```python
import unreal
print(unreal.LivingTownMetaHumanAuth.open_sign_in_launcher())
# Complete Epic authorization manually in the official flow.
print(unreal.LivingTownMetaHumanAuth.read_sign_in_state())
print(unreal.LivingTownMetaHumanAuth.close_sign_in_launcher())
```

Use an interactive Editor for the manual handoff. When staging prebuilt project DLLs, also stage the matching completed `LivingTownEditor.target` receipt; `-NoCompile` alone did not prevent the Editor's startup rebuild path when that receipt was missing. Keep the SDK and EditorConfig dependencies restricted to the Editor target.

## Observed validation and limits

The bridge compiled in an isolated Unreal Engine 5.8.4 Development Editor build in 412.704 seconds. The four C++/build-rule files match that tested source after line-ending normalization, and the project plugin configuration is equivalent. The containing build checkpoint also includes ongoing character work outside this PR; this is not a claim of an exact whole-PR Editor or packaged Game build. Repository CI does not compile Unreal.

In the live native trial, the enabled window received one user button event, issued one login request, and confirmed service sign-in. The status-check count stayed at two after successful authorization. That trial subsequently completed a full joints-and-blendshapes facial rig and all eight requested 2048-pixel source texture categories. The saved 145,316,588-byte character package had SHA-256 `87380c3ab8c4be4a1d6e758f69e6bce2b9cf945ec3eb4f3b1cc2b5479125dbeb`; a separate cold session restored its rig, textures, and assembly readiness without repeating cloud requests.

Optimized-High assembly remains incomplete. The combined session and a fresh assembly session exceeded a 16 GiB owned-job limit; a bounded 20 GiB assembly session progressed through texture export and then also exhausted its job memory. That last session preserved the immutable checkpoint and meaningful global content, exited with native code 3, and had its owned process tree waited and reaped. It recorded no successful assembly, visual approval, pawn replacement, or game performance result. The earlier interactive staging attempt triggered an unintended startup rebuild and retained a failed global-custody audit; its caches and binaries were not reused.

The licensed MetaHuman data, local authentication state, generated character package, failed build caches, and partial assembly outputs are not included in this PR. Visual, wardrobe, action, and runtime acceptance still require an assembled consumer asset and separate checks.
