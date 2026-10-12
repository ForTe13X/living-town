The 3D town uses one large, engine-neutral GLB distributed as a public release asset. The source repository keeps its verification metadata under `game/assets/town3d/stage_manifest.json`.

- Repository: `ForTe13X/living-town`
- Release tag: `town3d-walkthrough-2026-10-12`
- Asset: `living_town_game.glb`
- Required size: **203,666,604 bytes**
- SHA256: `b90b37e40f6f38e61b095a45671fed40008e9423dfef52ef7db74cb34cb0c00c`
- [Public asset download](https://github.com/ForTe13X/living-town/releases/download/town3d-walkthrough-2026-10-12/living_town_game.glb)

Run `tools/run-town3d.ps1 -EnginePath <Godot-executable>` normally. When the GLB is missing, the launcher runs the downloader before importing or opening Godot. This first download needs Python 3.10+ and internet access. `-Legacy` skips the 3D asset download.

Manual retrieval:

```powershell
py -3 tools/fetch_town_assets.py
```

The downloader streams into a temporary file beside the destination, verifies the byte count and SHA256, flushes it, then installs it atomically. A valid existing asset is preserved. An incorrect existing file is preserved and reported; replace it only explicitly:

```powershell
py -3 tools/fetch_town_assets.py --replace-mismatched
```

If the direct public download cannot connect and `gh` is installed, the tool tries `gh release download` for the same tagged asset. It does not request or print credentials. `--no-gh-fallback` disables this fallback. The release must be published before either route can succeed.

`--asset-dir <directory>` changes the destination. `--url <http-or-https-url>` supports a local test server or mirror; it never changes the pinned size/hash, and URL overrides do not invoke GitHub as a fallback. After retrieval, copy or place the verified file in `game/assets/town3d` before launching the game. These overrides do not alter the frozen Blender delivery or the simulation profile.
