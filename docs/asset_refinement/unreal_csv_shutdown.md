# Windows CSV capture shutdown workaround

On the tested Unreal 5.8.4 Windows Development build, a completed CSV capture can request exit status 0 and still terminate with status `777003`. Wait for the actual process handle and read its exit code; the `RequestExitWithStatus` log is only a request.

For development CSV captures on this build, add the stock command-line argument:

```text
-csvNoProcessingThread
```

Keep the existing capture length, viewport instrumentation, screenshot, warmup, timeout, and process-exit checks. This flag moves CSV processing onto the game thread. Use the same profiling configuration throughout a comparison and collect fresh samples; do not compare these timings directly with captures that used the CSV worker. This is a capture workaround, not a production configuration or a frame-rate optimization.

## Observed failure and bounded validation

A debugger attached after the native player view was ready recorded two first-chance access violations, in this order:

1. `CSVProfiler`: a write to address `0x24`, with matching local symbols for `FPerThreadFreeBlockLists::ClearTLS` and `FCsvProfilerProcessingThread::Run`.
2. `CrashReportingThread`: the same invalid write address, with frames for `ForEachThreadStackBackTrace`, `CaptureAllThreadContexts`, and crash handling. The process then exited with `777003` (`CrashReporterCrashed`).

Both saved minidumps agree with their captured exception thread, code, and x64 instruction pointer. This identifies the observed failure path. It does not prove the exact invalid object, a destruction-order race, or an engine correction. Debugger attachment can change subsequent exception handling and scheduling.

A fresh **undebugged** run added only `-csvNoProcessingThread` to the normalized runtime arguments. The executable, cooked café, Binned3 allocator, Full-HD viewport, offscreen D3D12/SM6 rendering, and 3,600-frame capture remained the same. It completed all 3,600 frames, retained the required two-second warmup and ten-second observation window, and **exited naturally with code 0 before cleanup**. All nine source, installed-engine, runtime-package, and profile preservation checks passed. The log confirmed Binned3 and contained no CSV processing-worker startup.

This is one positive shutdown diagnostic for the legacy café on AMD Radeon 8060S. It establishes neither whole-town stability nor current character quality, visible presentation rate, a balanced performance gain, or Shipping readiness. The failed historical runs remain failed.

## Source and evidence

The installed 5.8.4 source explains the relevant controls:

- `Engine/Source/Runtime/Core/Private/ProfilingDebugging/CsvProfiler.cpp`: the worker clears allocator TLS at line 3366; `FCsvProfiler` deletes the worker at lines 3840–3847; lines 5158–5161 recognize `csvNoProcessingThread`.
- `Engine/Source/Runtime/Core/Public/HAL/MallocBinnedCommon.h`: lines 553–568 unregister, unlock, destroy, and free the thread-local free lists.
- `Engine/Source/Runtime/Core/Public/GenericPlatform/GenericPlatformCrashContext.h`: `CrashReporterCrashed` is `777003`.

Local evidence is retained outside Git under the existing `F:/Living Town/2026-10-20_Refined_Town` and `D:/Dev/LivingTownNativeRuns/2026-11-01` evidence roots:

| Artifact | SHA-256 |
| --- | --- |
| `native110_exit_debug_captured_recovery_actual_v1_001/CAPTURED_EXIT_DIAGNOSTIC_DATA_PROOF.json` | `67d4030a90dc81f42a9d4c8b5e4f62bf82655aa7afb4e37724b1c4992bd98025` |
| `Native110CafeCsvNoThread_v001/COLD_PROOF.json` | `162819f77248e531b2b8d44040a5d4f36bcea34e14d6387fe2d1342df7acef55` |
| `Native110CafeCsvNoThread_v001/COLD_RECEIPT.json` | `a91a26c0ff2eadb3ac5948c6bec3a7324a0cbe28026913e321aab53ebf19311d` |

These machine-local artifacts are not bundled with the repository. No engine binary, allocator setting, project source, or asset was changed by the workaround test.
