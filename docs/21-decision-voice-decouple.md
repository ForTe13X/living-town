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
| 手机 CPU(8 Elite) | 9680 ms（cold-ish，前测） | demoted >8s（**thermal-hot 79°C**） | — | ⚠ 热态不同·**不可作 A/B** |

## 3. 读法
- **机制坐实**：省下的时间 ≈ 塌掉的 decode。Vulkan 省 **215 ms**、CPU 省 **636 ms**——**CPU decode 慢，故 decouple 在 CPU 上收益更大（2.8× > 2.4×）**。这正预示 CPU-only 的手机受益最大。
- **桌面 slm 由此激活**：NEW 150/349 ms 均 < 8s 降级门 → slm **真被启用**（tier=fast），不再一律降 logic。
- **手机不可比**：NEW 在 79°C 热饱和下测（OLD 9680 在较凉时测），**热态不同 → 不作 A/B**。**外推（非实测）**：若手机 CPU 的 decode 占比 ≈ 桌面 CPU（985→349，省 ~65%），则冷手机 NEW ≈ 9680×(349/985) ≈ **3.4s** → 有望跌破 8s 门、激活。**待一次凉机冷测坐实**——现障碍三重：设备热饱和 + 无线 adb 端口漂移（36921→35259，mDNS 重发现）+ Godot `print()` 不进本机 logcat（p50 只能屏幕捕捉、又被社交事件刷掉）。

## 4. 诚实边界（别外推）
- 桌面数是 **resident-warm 单次探针**，非 p50/p95 分布（edge-npu lab 那种 200×3 重启的生产严苛度未做）——足以证 decouple 的**相对收益 + 机制**，不外推为生产 p95。
- **手机冷测未拿到**；3.4s 是外推、不是测量。
- decouple 只改**延迟结构**（decode 主导 → prefill 主导），**不改决策"质量"评估**（仍待 living-town 真 trace 另评）。
- slm 的**选号仍非确定**（模型挑）；**台词已确定**（冻结库，`_rng_at` 挑）。logic 地板 + 红线不动。

## 5. 结论
把"决策"从"生成"里拆出来（edge-npu「决策≠生成」洞察）+ 台词走冻结库（[voicebank](../game/data/voicebank.json)，本会话早先建）→ 端上 slm 的延迟结构从 **"80-token decode 主导"** 变成 **"prefill 主导"**：桌面实测 **2.4–2.8× 提速、slm 激活**；手机 CPU 冷测待补，但机制与外推都指向"**可用的 ~3s 决策节奏 + 即时冻结语音**"。两个 lab 殊途同归——**决策 = 快分类器（可上 NPU），语音 = 冻结数据（零推理），logic 地板兜底**。若日后上 NPU（edge-npu 的 Genie 路），本决策已是其消费的闭集选号形态、天然前向兼容。
