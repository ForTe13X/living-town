# Unreal editor bootstrap

Unreal is the primary target. This project contains a C++ café projection, the authoritative lease subsystem and the native MCP authoring bootstrap. Godot is an offline reference archive during migration. The adopted projection passes an actual walk/animated-limb/lease/end/ledger journey with source-bound venue components and a compact cached HUD. Its wallet/stewardship/lease-term card and context prompt pass actual player capture at1014×550, including minimum text height and removal of duplicate initial feedback. It remains opt-in until the qualified asset closure is packaged with a reviewed lit presentation map; the default map/GameMode has not been changed. Wider simulation migration and visual acceptance remain pending. See [native café scope and validation](../docs/asset_refinement/unreal_native_cafe.md).

The editor target also loads `LivingTownMaterialInspection` for typed material graph/static-parameter inspection and explicit motion-asset derivative authoring. It is excluded from the game target. The motion helper duplicates/resamples the named new café BlendSpace only; runtime code refuses missing interpolation instead of mutating assets. The fixture-bound Python vertex-color correction is explicit and does not run during startup; its qualified scope and reproduction evidence are in [the material adapter notes](../docs/asset_refinement/unreal_vertex_color.md).

The disabled native town-streaming pilot adds typed data assets, asynchronous dependency loading and shared-instance ownership. Registration, collision/visibility transitions and destruction share a per-tick operation budget, including cancellation and driver-loss drains. The current 60-input source cut compiles and passes ten native tests, including real transient world/component lifecycle and effective instanced-material usage checks. The material gate runs before cache reuse and component creation, refuses unprepared content with actionable paths, and never repairs or compiles materials at runtime. Editor-only helpers support disabled tile previews and scoped Westwood material inspection. Outdoor import and buffer readback have run, but full streamed-world and performance qualification remain pending. See [the native town pilot and its current limitations](../docs/asset_refinement/unreal_native_town_streaming.md). The existing café content recipe remains bound to its recorded source/build pair; a new native source cut requires its own matching build and qualification.

The native module owns one portable C++ kernel. Commands carry case-sensitive request/property IDs and Lease/EndLease action; session, clock, terms and interaction context come from the native authority. Its two-account pilot starts Aria/Ben at12coins each and supports one conserved4coin/720tick lease, idempotent retries, ending without refund and trusted expiry. The new adapter installs its resolver only after exact source assets, Ben's skeletal motion, floor/counter roles, spawn and possession validate. Without those inputs, actual counter commands still refuse with `spatial_binding_unqualified`.

Journal version1 binds the exact capability set and core/contract/world hashes. Unknown or missing fields, duplicate keys, legacy whole-world saves, unsupported provenance and failed event refolds reject atomically. No old save is loaded by dropping unported state. The bounded1024-event journal reserves an expiry slot. The source/core/test adoption bindings live in `Source/LivingTownNative/ThirdParty/QUALIFIED_SOURCE_BINDINGS.json`; the frozen core's historical comment is preserved with its bytes.

Use Python on Windows with installed UE5.8.4/58902052, MSVC ProductVersion14.44.35229, WindowsSDK10.0.22621.0 and .NET Framework4.8SDK. The compiler may live in family folder14.44.35207; its executable ProductVersion is what Unreal checks. The builder installs nothing and launches no editor. First choose a fresh F-drive output:

```powershell
python -B tools/unreal/build_native_module.py --engine-root D:/Dev/UE_5.8 --source-root . --artifact-root "F:/Living Town/native_build_001"
```

This only preflights. Add `--execute` to compile a fresh source copy with the installed UBT/MSVC. Project sources, UHT output, intermediates, DLLs, logs and TEMP stay in that F-drive output. The owned build allows two local actions, at most8GiB RSS/12GiB private memory and600seconds. Tiny normal installed-engine dependency/hash caches and run markers are accounted for; pre-existing configuration XML and engine inputs must remain exact.

The resulting `BUILD_RECEIPT.json` binds the current native sources/project descriptor, installed engine bytes/BuildId, successful Editor-target UBT evidence and a closed DLL/module-manifest set. Changing native code, targets or the project descriptor requires a fresh build. Bootstrap validates this receipt before an editor can start and stages only its exact matching DLL and `UnrealEditor.modules`. Source-tree Binaries, extra DLLs, PDBs and stale files are excluded. Compilation never happens during the guarded editor phase.

Then preflight MCP startup with that receipt:

```powershell
python -B tools/unreal/run_bootstrap.py --engine-root D:/Dev/UE_5.8 --source-root . --native-build-receipt "F:/Living Town/native_build_001/BUILD_RECEIPT.json" --artifact-root <FRESH_ARTIFACT_DIR> --cache-root <FRESH_CACHE_DIR> --port 19841
```

Choose artifact/cache paths on a disk with ample space, outside this repository and the engine installation. Omit `--cache-root` to use `<ARTIFACT_DIR>/cache`. The first command only preflights; add `--execute` to launch in the serial engine window.

Content-only projects with no Modules remain supported and omit `--native-build-receipt`. Native projects refuse startup without a successful matching receipt; the launcher never attempts a fallback compilation.

An existing editor is refused by default. To coexist with an observed idle project browser, explicitly record and review its identity:

```powershell
python -B tools/unreal/capture_idle_editor.py --pid <OBSERVED_PID> --output <FINGERPRINT_JSON>
python -B tools/unreal/run_bootstrap.py --engine-root <UE_ROOT> --native-build-receipt <MATCHING_BUILD_RECEIPT> --artifact-root <FRESH_ARTIFACT_DIR> --external-editor-fingerprint <FINGERPRINT_JSON> --execute
```

The host never closes an external editor. It compares PID, creation time, executable, idle project-browser title, window and no-project/no-MCP identity before and after. Any other engine or unowned shader worker refuses. Raw command lines are not recorded.

The editor is assigned to an owned Windows job before it runs. Its shader-worker descendants share a20GiB private cap; sampled aggregate RSS is limited to14GiB. Startup is600s and total execution720s. Successful discovery deliberately stops the owned job and waits for every descendant; all partial failures are retained.

Project Saved/Intermediate, DDC, shader workspace, generated INIs, Python cache, TEMP and logs use the artifact/cache paths. Shared UE profile changes are reported; existing global INI changes refuse qualification and are never restored over another editor. Existing Blender/Godot private archives remain byte-guarded; `--preserve-path <PATH>` adds another file/tree to that guard.

`-RenderOffScreen` retains hardware D3D12/SM6 and avoids native swapchain presentation. It is not NullRHI. `--expected-gpu-name <NAME>` additionally pins the exact GPU reported by a prior qualified log. No driver, HDR, Lumen, Nanite or scalability setting is changed.

The actual tool map starts empty. The client initializes native MCP, lists the real toolsets, describes their returned schemas and persists the transcript. It dispatches no asset-import or gameplay tool. Editor-only plugin references keep MCP/Python tooling out of game targets. A future import must bind its actual schema and source geometry/material receipts.

The earlier content-only launcher passed64 source/replay checks and its actual hardware run: all19 native toolsets were described, source/private/config guards passed, and the owned editor and descendants were reaped. That run used Radeon 8060S D3D12/SM6 with separate F-drive project/cache paths. `tools/unreal/qualification.json` retains its evidence hashes. The byte-identical native logical boundary also passed an isolated engine AutomationTest with12negative-save cases,1024capacity commands and92source-derived assertion invocations. These are bounded proofs; the current canonical native/MCP startup still requires its coordinated engine gate.

Source/staging tests run without launching an engine. The optional native receipt argument also replays the actual canonical build into a fresh consumer copy:

```powershell
python -B tools/unreal/test_bootstrap.py --scratch-root <FRESH_TEST_DIR> --native-build-receipt <BUILD_RECEIPT> --actual-engine-root D:/Dev/UE_5.8
```

The tests cover content-only compatibility, missing/failed/unreaped receipts, changed source or DLL bytes, engine and module BuildId mismatches, redirected/traversing paths, wrong PE architecture, unsuccessful UBT evidence and exclusion of unlisted binaries. A staged-copy pass does not establish an actual actor binding or playable parity.

For the verified local café content closure and normal game startup, follow [the content delivery recipe](../docs/asset_refinement/unreal_cafe_content_delivery.md). It supplies matching source, project-owned native modules and 405 assets separately from the installed engine, then explicitly selects the qualified Lumen map/native GameMode. The actual restored-project load has zero warnings/errors or authoring-bridge activity. The recorded observer replay retains the failed original monitor-file expectation and qualifies the zero-persistent-output lifecycle separately. This initial uncooked load is narrower than the independently tested walking journey and does not qualify cooking, full-town performance or final art.
