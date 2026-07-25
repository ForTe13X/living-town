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

## 建议修法（原计划）

- **治本**：查 SLM 挂死——换/验证一个与当前 NobodyWho 版本兼容的 gguf；或对齐 NobodyWho GDExtension 版本；桌面同款复现（`--backend slm`）二分是模型问题还是集成回归。
- **防 OOM（防御性，独立于治本）**：加**熔断器**——连续 N 次推理 0 成功（或超时率 100%）就【停发 SLM、永久回退 logic】，避免继续 fire 注定挂死的推理堆积泄漏。这样即使 SLM 坏了，也只是"没有 LLM 增强"，而不是崩。
- **探测路径**：给 `_probe_once` 的 `await` 加超时兜底 + 无条件 free（别裸 await 挂死信号）。
- **可观测**：把 Native Heap（`dumpsys meminfo`）纳入真机 perf 检查——`OS.get_static_memory_usage` 看不到原生泄漏。

## 已修复（2026-07-25，本轮）——防御层 + 桌面二分

### ① 熔断器（防 OOM，`AIBackend.gd`）— 已落地 + 已验证
- 连续 `BREAKER_MAX_FAILS=5` 次决策失败（**超时** 或 **脏解析**、其间 0 成功）→ `_trip_breaker`：`cancel_all` 释放在飞请求 + `backend/backend_requested` 【钉死 logic】+ 落一条 `livingtown_breaker.txt`（adb-pull 复盘）。挂死 worker 的原生上下文虽难回收，**熔断保证不再新增 → 把泄漏封顶在 ~5×400MB≈2GB**（12-16GB 机安全），而非无界涨到 OOM。
- 记账细节（避免误熔断）：**超时**=OOM 关键信号（worker 卡死漏原生上下文）计失败；**脏解析**（`picked` 空）计失败；但**"模型给了合法 pick、只是等待期世界变了"**（`chosen` 空，P1-1）→ 模型活着、无泄漏 → 计为**健康信号清零连败**；任何**成功落地**清零。
- 复位（给修好的模型/新档一次新机会）**仅在显式动作**：`reset_stats`（bench 换 seed）、`request_backend`（用户手动切档）、`set_model_path`（换模型）。**单纯新开局/读档不自动复位**——不静默重试已知坏的模型。
- 验证：`res://scenes/breaker_test.tscn`（**无模型/无网络确定性测试，18/18 通过**）覆盖 阈值触发 / 成功清零 / 三条复位 / `decide()` 超时分支端到端喂熔断 / 熔断后走 logic 且不再 fire。

### ② `_probe_once` 硬化（探测路径，`AIBackend.gd`）— 已落地 + 已验证
- 裸 `await chat.response_finished` → 换成 `_await_signal_or_timeout(chat, "response_finished", deadline_ms)`：`deadline_ms` 内每帧轮询等信号（非阻塞，镇子继续跑），到点**无条件** `stop_generation`+`queue_free`。挂死的探测发不再让 `probe_capability` 永阻、不再裸 await 挂死信号。llm 探测路也补了 `http.timeout`。
- 验证：桌面真模型 e2e（下）中 `_probe_once` 正确处理**真实** `response_finished`（p50=166–340ms，不误超时、正确释放）。

### ③ Overlay 可观测（`Main.gd`）— 已落地
- perf overlay 后端行显式标 `🔴熔断→logic(reason)`（已熔断）/ `连败 N/5`（逼近阈值）。真机就是靠此 overlay 诊断的——别让"后端 logic"看起来像用户主动选的。

### ④ 根因二分（桌面复现，结论：**设备/模型专属，非集成回归**）
| 场景 | 结果 |
|---|---|
| `slm_smoke`（隔离 NobodyWho，绕开整个游戏）· Win x86_64 · **CPU** · 本地 1.5B | ✅ **1251ms** 返回 `{"i":1}` |
| `slm_smoke` · Win x86_64 · **GPU/Vulkan（AMD Radeon 8060S）** · 1.5B | ✅ **1150ms** 返回 |
| **全 AIBackend 路径** e2e（探测+decide+熔断）· CPU · 1.5B | ✅ **landed 5/6**，熔断未触发，consec_fail=0 |
| 同上 · **GPU** · 1.5B | ✅ **landed 5/6**（p50=166ms），熔断未触发 |

**结论**：当前构建的 NobodyWho（v9.4.0）+ 一个能跑的 gguf，在桌面 Win CPU **和** AMD Vulkan 上**都不挂**、AIBackend 的 SLM 集成能真落地决策 → 真机的"0 成功 + 挂死"**不是普适的集成回归、也不是我们 AIBackend 用法的 bug**，而是下列之一（三者桌面均无法复现）：①设备侧 `model.gguf`（2026-06-28，MTP 拷入）本身与当前 llama.cpp 不合/损坏；②**Android arm64** NobodyWho 库（与 Win 库不同二进制）；③**Adreno** Vulkan 驱动挂（≠桌面 AMD）。

### 仍需设备侧一轮（治本收尾，需真机 adb loop）
- **验熔断确实封顶内存**：真机 `--backend slm` 跑，`dumpsys meminfo` 看 Native Heap 在熔断后**停涨**（预期涨到 ~2-3GB 触发熔断即平），而非涨到 16GB OOM。
- **定位设备 model.gguf**：把设备上那份 `model.gguf` 换成桌面已验证能跑的 gguf（如本仓 1.5B / 3B），或对齐 Android NobodyWho 库版本，二分是"这份模型文件"还是"arm64 库/Adreno"。桌面已排除前两类通用因素，重点查这份文件与 arm64 组合。

## 影响评级

**高 → 已降级为"可控"**：熔断器 + 探测硬化落地后，即便设备 SLM 仍挂，也只是**回退 logic 地板（无 LLM 增强）而非 OOM 崩溃**，泄漏封顶 ~2GB。治本（真机恢复 SLM 生效）仍待设备侧一轮。logic 地板全程不受影响（红线：无模型也能玩；本轮改动经 Harness S0 det 3/3 + 硬不变量 3/3 验证，与 pristine main 逐字节一致）。
