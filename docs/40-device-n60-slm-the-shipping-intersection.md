# 40 · 出货交叉点实测：N=60 × 端上 SLM（此前从未测过的那一格）

**2026-07-26，红魔 8 Elite / Android 15，无线 adb 实机。** 此前每一个真机数据点要么是 **N≈12 + SLM**、要么是 **N=200 + logic**——
**"最多 60 个居民 **同时** 开着端上推理"这个真正的出货配置，一次都没测过**（docs/33 的评审早就点名了这个空档）。本文补上。

## 读数（perf overlay + dumpsys）

| 项 | 实测 |
|---|---|
| 帧 | **FPS 41 · 24.4ms**（可玩；logic 同机 88-91） |
| 仿真 | NPC 60 · tick 2117 · **11.5 tick/s**（名义 12，**仿真没有掉队**） |
| Native Heap | **371 MB**（TOTAL PSS 1.67GB）——池化 worker 在 5 倍阵容下依旧封顶，**旧版 16GB 无界泄漏无复现** |
| 模型 | **发起 12 · 成功 2 · 超时 7 · 无效 2** |
| 小镇 | 事件 2297 · 冲突 107(活 101) · 编年史正常播报（含"道了歉，两人和解"） |

## 关键数：出货配置下模型的决策占比 ≈ **0.04%**

- 运行跨度：tick 2117 ÷ 240 ≈ **8.8 sim-日**（第 9 天暮）。
- 落地：**2** 次。
- 分母：N=60 时全镇 **约 534 决策/sim-日**（docs/35 §1.3 桌面确定性实测）→ 约 **4700** 次决策。
- ⇒ **占比 ≈ 2 / 4700 ≈ 0.04%**。

**与解析天花板互相印证**：发起 12 次 ÷ 8.8 日 = **1.4 次/sim-日**，正好落在串行 worker 的
`19.2s ÷ 解码时长` 窗口内（docs/35 §1.2）。机理不是猜的，是对上了。

**这比此前的外推低一个数量级**：docs/35 §1.5 按 N=12 的落地率外推 N=60 为 0.3-0.8%。实测低得多，因为
**落地率本身在 N=60 塌了**：12 发只成 2（16.7%），而 N=12 时约 60%——镇子变大 → 仿真更重、与推理抢同一颗 SoC →
解码越过 15s 截止线的比例大增（超时 7/12）。**两个因素同向叠加**：分子塌、分母涨 5 倍。

## 结论

配合 [docs/36](36-model-influence-delta-over-c.md)（模型的选择与随机不可区分）与
[docs/38](38-does-the-decision-path-earn-it.md)（可与随机区分，但没有一条差异指向好的方向、且 8/8 seed 违反硬不变量 #01）：

> **在真正的出货配置下，端上 SLM 决策路径以 FPS 88→41 的代价，驱动了全镇约 0.04% 的决策，
> 而这些决策在效用轴上与随机不可区分。**

这不否定端上模型本身——**对话/台词是另一条已经在工作的路**（截图里满屏的气泡就是），
也不否定"决策≠生成"的架构洞察。它否定的是**当前这条决策路（1.5B + 闭集选号）值得开着**。

## 诚实边界

- **单机单次**：一台设备、一次运行、8.8 sim-日。不是跨机型基准，也没有重复测量的方差。
- 分母 534/sim-日来自**桌面**确定性实测（同 N），未在真机上独立复测；真机 tick 11.5/s 略低于名义 12，
  故真实分母可能略小、占比略高——但不足以改变数量级。
- 未测：N=60 + CPU 推理的 A/B（本次走的是端上默认 CPU 档）、更长时程、热节流稳态。

## 复现

```
adb connect <ip:port>
printf '[backend]\n\nmode="slm"\n\n[sim]\n\nnpc_count=60\n' > s60.cfg
adb shell "run-as com.forte13x.livingtown sh -c 'cat > files/settings.cfg'" < s60.cfg
adb shell am force-stop com.forte13x.livingtown
adb shell am start -n com.forte13x.livingtown/com.godot.game.GodotAppLauncher
sleep 150; adb shell input keyevent 133   # F3 = perf overlay
adb exec-out screencap -p > n60.png
adb shell dumpsys meminfo com.forte13x.livingtown | grep 'Native Heap'
```
截图：[`docs/media/device_n60_slm.png`](media/device_n60_slm.png)。
同轮 logic 档整波眼验图：[`docs/media/device_wave_chronicle.png`](media/device_wave_chronicle.png)（编年史/区名/唤醒后的戏剧全部在真机成立）。
