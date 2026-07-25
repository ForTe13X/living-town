# 34 · 真机严重 bug：SLM 推理挂死 → 0 成功 + 16GB 原生内存泄漏 → OOM

**2026-07-25 真机（NX789J / 红魔 8 Elite，Android 15）实测发现。** 这是只有真机才挖得出的旗舰级 bug（见 memory `reference-godot-android-loop`）。

## 现象（perf overlay 实测）

- `后端 slm · 并发 2 · LLM 发起 40 · 成功 0 · 超时 38 · 无效 0` —— **40 次推理全超时，0 成功**，2 个永远挂在飞。
- 内存（`dumpsys meminfo` Native Heap）：15s→**3GB**，90s→**7.5GB**，160s→**16GB**——**无界线性增长 ≈ 90MB/s**。8 Elite 12-16GB RAM，几分钟必 OOM。
- 后果：①**旗舰 SLM 决策/语音实际从未生效**——每次超时都回退 logic 地板，玩家看到的"台词"全是罐头 logic 输出，不是 SLM；②内存泄漏几分钟崩。
- 注意：`OS.get_static_memory_usage()`（overlay 的"内存 145MB"）**只算 GDScript 侧**，看不到 llama.cpp/nobodywho 的原生分配——必须 `dumpsys meminfo` 看 Native Heap 才发现。FPS 78 正常（town 跑 logic 顺）。

## 机制（AIBackend.gd 读码定位）

1. **根因 = 推理【挂死】不返回**（不是慢）：2 个 worker 永远 inflight、40 发 0 成，`chat.response_finished` 信号从不触发。最可能是 **model.gguf（2026-06-28）↔ 当前构建的 NobodyWho GDExtension 不兼容 / 版本漂移 / 回归**（README 记录过它能跑，说明是后来坏的）。也可能是该 gguf 本身对当前 loader 不合。
2. **泄漏是挂死的症状**：主决策路径（AIBackend.gd:563-568）把 worker 存进 `_pending[id]["slm_chat"]`，超时 `_finish`(:408) 会 `_free_transport`→`stop_generation`+`queue_free`。但 **对一个卡在原生生成里的 worker，`stop_generation`+`queue_free` 释放不了那块原生 llama 上下文**（原生线程卡死 → KV/上下文不回收）。每次挂死漏 ~400MB × 40 ≈ 16GB。
3. **探测路径更漏**：`_probe_once`(:320-333) 是裸 `await chat.response_finished`、不进 `_pending`，挂死则 `await` 永阻、chat 永不 free、`cancel_all`/`_finish` 也够不着它。

## 建议修法（未做，需专门一轮）

- **治本**：查 SLM 挂死——换/验证一个与当前 NobodyWho 版本兼容的 gguf；或对齐 NobodyWho GDExtension 版本；桌面同款复现（`--backend slm`）二分是模型问题还是集成回归。
- **防 OOM（防御性，独立于治本）**：加**熔断器**——连续 N 次推理 0 成功（或超时率 100%）就【停发 SLM、永久回退 logic】，避免继续 fire 注定挂死的推理堆积泄漏。这样即使 SLM 坏了，也只是"没有 LLM 增强"，而不是崩。
- **探测路径**：给 `_probe_once` 的 `await` 加超时兜底 + 无条件 free（别裸 await 挂死信号）。
- **可观测**：把 Native Heap（`dumpsys meminfo`）纳入真机 perf 检查——`OS.get_static_memory_usage` 看不到原生泄漏。

## 更新（同日）：根因收窄 + 熔断器已修并【真机验证】

**根因收窄到 Adreno GPU Vulkan**：写了 `bench/slm_smoke.gd`（最小推理冒烟）在【桌面】跑同一个 gguf——
- CPU：✅ 1498ms 返回 `{"i":1}`；GPU（AMD Radeon 8060S Vulkan）：✅ 1207ms 返回。
- 即 **NobodyWho 集成 + 模型本身在桌面 CPU/GPU 都好**（~1.2-1.5s，合 README）。→ 真机挂死是 **arm64 / Adreno GPU Vulkan 特定**（llama.cpp/ggml 的 Adreno Vulkan compute 是出了名的坑）。`slm_use_gpu` 默认 true → 真机走 Adreno GPU → 挂死。另观察到**模型 LOAD 本身也会卡住主线程**（真机启动探测期 FPS 掉到 1）。

**熔断器已修 + 真机验证通过**（AIBackend.gd）：连续 `SLM_CIRCUIT_TRIP=6` 次超时 → 开熔断、停发 SLM、永久回退 logic（decide/reflect/chat=_gen_slm 三处 fire 全门控）+ `cancel_all` 止血。真机实测对比：
| | 无熔断 | 熔断后 |
|---|---|---|
| LLM stats | 发起40·成功0·超时38 | **发起7·超时6→触发熔断**、并发0 |
| Native Heap | 3→7.5→**16GB**(OOM) | **~2.3GB 封顶不涨** |
| FPS | 卡死 | **恢复 79**、tick 12/s |
| 镇子 | — | logic 地板照常活（八卦/discuss/送礼） |
熔断器为 slm-only + 默认关 → logic 确定性红线不受影响（V1 逐字节验证）。残留 ~1.2GB（6-7 个卡死 worker 未释放）已封顶不涨，可接受（防了 OOM）。

**剩余（交专门一轮，见 spawn_task）**：治本 Adreno GPU 挂死——①真机试 CPU 推理(`slm_use_gpu=false`，但容器测 ~1字/s 恐太慢，需 8Elite CPU 实测)；②升级/换 NobodyWho arm64 构建或换 llama.cpp Vulkan 后端；③`_probe_once` 裸 await 加超时兜底 + 无条件 free（现在探测挂死漏 1 worker + 卡主线程）。

## 影响评级

**高**：旗舰功能（端侧 SLM 决策 + 语音）在真机上【完全不生效】。**熔断器已消除 OOM 崩溃风险**（降级到 logic 地板，红线：无模型也能玩），但要真正恢复 SLM 还需治本 Adreno GPU 挂死。
