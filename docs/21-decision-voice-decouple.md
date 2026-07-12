# docs/21 · 决策↔语音解耦（闭集选号 + 冻结语音库）+ 严格对拍

> 源起：姊妹 lab `Dev/edge-npu-8elite` 的核心 reframe——**决策 = 从 N 个合法候选选 1 = 一次 prefill 前向 + 候选上 argmax = ≈0 decode 步**；开放生成（语音）是 decode 重活、该离开热路。小镇原本把两者揉进一次 slm 调用（JSON `{pick,speech,emotion,...}`，~80 decode token）——这正是端上 ~9.7s 的元凶。

## 1. 改动（`AIBackend.gd`，slm/llm-only）
- **决策 = 单字符编号**（0-9/A-Z，`_idx_label`/`_label_idx`）→ decode≈1 token；**台词永远从冻结·70B 语音库**（`Sim._canned_say`）取。pick=模型（快分类器）/ voice=冻结数据（确定、零推理，本会话早先建）。
- `_system_prompt` 缩到"只回编号"（prefill 也随之降）；`build_prompt` 候选用单字符标签；`parse_decision` **编号优先 + JSON 兜底**（单测/旧 llm 路仍过、含台词则留）；`decide()` 无 `say` 时补语音库；`DECIDE_MAX_TOKENS=8`（chat 仍 `MAX_TOKENS=128`）；`_mock_raw` 回编号。
- **红线**：`logic`/CI 从不构建 prompt → digest 逐字节不变（S0 seed12=`3858030099` 未动，12/12 全绿、det 3/3）。

## 2. 严格对拍（术语等级，仿 edge-npu-8elite 数字账本）
**术语**：`resident-warm`（模型常驻、取第 2 次暖推理，**单次探针**）· `cold`（冷启）· `thermal-hot`（热饱和，最高热区 79°C）。同 **Qwen2.5-1.5B-Q4_K_M**、同探针（`probe_capability` 2 暖发取 p50）、同 prompt 候选、同机。

| 条件 | OLD（JSON pick+speech, ~80 decode tok） | NEW（index-only, ~1 decode tok） | 加速 | 等级 |
|---|---|---|---|---|
| 桌面 Vulkan(Radeon 8060S) · resident-warm | 365 ms | **150 ms** | **2.4×** | ✅ 受控 |
| 桌面 CPU(Ryzen AI MAX 395) · resident-warm | 985 ms | **349 ms** | **2.8×** | ✅ 受控 |
| 手机 CPU(8 Elite) · **matched-cold**(CPU 起 35°C) | 14768 ms | **12667 ms** | **1.17×** | ✅ 受控实测 |

## 3. 读法
- **机制坐实**：省下的时间 ≈ 塌掉的 decode。Vulkan 省 **215 ms**、CPU 省 **636 ms**——**CPU decode 慢，故 decouple 在 CPU 上收益更大（2.8× > 2.4×）**。这正预示 CPU-only 的手机受益最大。
- **桌面 slm 由此激活**：NEW 150/349 ms 均 < 8s 降级门 → slm **真被启用**（tier=fast），不再一律降 logic。
- **★ 手机 matched-cold 实测（CPU 起 35°C 两跑）：OLD 14768ms → NEW 12667ms，只 1.17×（省 ~2.1s）**——与桌面 2.4-2.8× 天壤之别。**根因：手机是 prefill-bound，桌面是 decode-bound**。手机 CPU 上 12 居民候选 prompt 的 prefill(~327 tok) 就吃 ~12.7s（NEW 的绝大部分），80-token decode 只占 ~2.1s；decouple 砍的正是这 2.1s decode、prefill 一点没动。桌面 CPU 反过来（decode 占 65%）故 decouple 收益大。**两跑均 demoted(>8s)**——decouple 不足以让 1.5B 在手机跌破 8s 门。
- **热态诚实**：CPU 分区(cpu-*/cpuss-*)才是推理温度（我先前误读 `pmih010x_lite_tz` 这个 PMIC 分区 61-79°C→以为热；实际 CPU 一直 ~32°C）。且**探针本身即热源**：冷启 35°C→跑完 58°C，故"冷启"与前测"暖"(12526ms)几乎一致 → **单次探针的热态影响远小于长时段持续推理的深度节流**（那才是之前 18s 的来源）。工具坑：无线 adb 端口漂移(35259，mDNS 重发现)、Godot print 不进 logcat（改用探针写 `Documents/livingtown_probe.txt` 可靠 pull）、`am start` 不唤屏→tap 打空（需 keyevent 224 唤屏）。

## 4. 诚实边界（别外推）
- 桌面数是 **resident-warm 单次探针**，非 p50/p95 分布（edge-npu lab 那种 200×3 重启的生产严苛度未做）——足以证 decouple 的**相对收益 + 机制**，不外推为生产 p95。
- **跨设备别按比例外推延迟结构**：我先前外推"冷手机 NEW ≈ 3.4s、激活"是**错的**——它假设手机 decode 占比 ≈ 桌面(65%)，实测手机 prefill-bound、decode 占比只 ~14%，瓶颈翻转。matched-cold 实测才是真值(14768→12667)。
- decouple 只改**延迟结构**（在 decode-bound 机器上把 decode 那半砍掉），**不改决策"质量"评估**（仍待 living-town 真 trace 另评）。
- slm 的**选号仍非确定**（模型挑）；**台词已确定**（冻结库，`_rng_at` 挑）。logic 地板 + 红线不动。

## 5. 结论
把"决策"从"生成"里拆出来（edge-npu「决策≠生成」洞察）+ 台词走冻结库（[voicebank](../game/data/voicebank.json)，本会话早先建）→ 端上 slm 延迟结构从 **decode 主导** 变 **prefill 主导**：桌面（decode-bound）实测 **2.4–2.8× 提速、slm 激活**；**手机（prefill-bound）实测只 1.17×、仍 demoted**。

**decouple 是正确的第一刀（砍掉 decode 那半），但手机的真瓶颈是 prefill——下一刀得砍 prefill**：缩候选 prompt / 复用静态前缀 KV（`GENIE_DIALOG_SENTENCE_REWIND` 之类）/ 更小模型(0.5B) / 或上 **NPU**（edge-npu 的 Genie 路——**NPU 恰是 prefill-强、decode-弱，与手机 CPU 的强弱正好互补**，故决策打在 NPU 的 prefill 强项上才是 ~100ms 的正解）。两个 lab 殊途同归——**决策=快分类器（该上 NPU）、语音=冻结数据（零推理）、logic 地板兜底**；本决策已是闭集选号形态、上 NPU 天然前向兼容。**最诚实的一句**：想让端上 slm 真跑起来，方向不是"更聪明的 decouple"，是"把决策的 prefill 搬上 NPU"或"决策留 logic 地板 + 语音走冻结 70B 数据"（后者本会话已成、零推理、红线内）。
