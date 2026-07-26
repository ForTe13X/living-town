# 文档索引 · Living Town

本树上有编号文档 00-25、28-43（26 与 27 只存在于未并入的分支，见下）+ 若干附录。
文档以中文为主，**按写作时的真实过程记录**——包括被推翻的结论和负结果，
这些不会被事后删改（见 [13 实验札记](13-实验札记-experiment-journey.md) 与 [31 #15 结案](31-15-resolution.md)）。

> **哪些是"当前状态"，哪些是"历史记录"**：只有 [05 路线图](05-路线图与里程碑.md) 与 [13 实验札记](13-实验札记-experiment-journey.md)
> 承诺跟随当前进度。其余按主题文档记录的是**写作当时**的设计与实测；数字会随代码前进而变旧，
> 唯一权威的不变量清单是代码本身：[`game/bench/Invariants.gd`](../game/bench/Invariants.gd)。

---

## 先读这三篇

| 文档 | 内容 |
|---|---|
| [05 路线图与里程碑](05-路线图与里程碑.md) | **当前 now / next / later 路线图**；已交付里程碑 M0-M4 作为历史保留 |
| [08 测试与验证](08-测试与验证.md) | 不变量门的方法学、37 条不变量的硬/软划分、如何复现整条 CI |
| [13 实验札记](13-实验札记-experiment-journey.md) | 995 行的过程日志：发现、奇技、坑、**被推翻的结论**。仓库里最能看出工程判断的一篇 |

## 产品与玩法设计

| 文档 | 内容 |
|---|---|
| [01 产品愿景与玩法](01-产品愿景与玩法.md) | 游戏概念、核心循环、明确不做什么 |
| [16 建筑与室内](16-建筑与室内-设计.md) | 多层室内、房间语义、室内隐私的空间模型设计 |
| [17 私密相处动机](17-私密相处动机-调研与设计.md) | 为什么居民会想单独相处——调研 + 机制设计（含对任务前提的纠错） |
| [19 大地图 roadmap](19-大地图-roadmap.md) | 分区 / 流式加载 / 跨区社会传播，且不破确定性红线 |
| [20 richer-town roadmap](20-richer-town-roadmap.md) | 定调：**先把小镇做丰富，再把地图做大** |

## 架构与 LLM 集成

| 文档 | 内容 |
|---|---|
| [02 技术架构 · 混合仿真](02-技术架构-混合仿真.md) | 确定性引擎当肌肉、LLM 当声音，中间用"合法候选 + 引擎兜底"缝合 |
| [03 LLM 集成架构](03-LLM集成架构.md) | 三档后端、结构化输出、超时与降级链 |
| [07 技术文档 · 社交底座](07-技术文档-社交底座.md) | 社交事务、关系账本、信念/知识边界、承诺、冲突生命周期的实现细节 |
| [21 决策↔语音解耦](21-decision-voice-decouple.md) | 决策=选号(≈0 decode)、语音=生成——拆开后桌面快 2.4-2.8×；含"手机是 prefill-bound"的反直觉更正 |
| [22 端上决策加速](22-npu-decision-path.md) | 两层决策栈（蒸馏 ranker + NPU-LLM）的穷举式探索与红线对账 |
| [23 端上混合推理构想](23-hybrid-inference-vision.md) | CPU/GPU/NPU 混合推理——**vision only，未建** |
| [24 Theory Engine 设计](24-theory-engine-design.md) | structural micro-social model v1 规格。⚠️ **离线 Python 原型，尚未接入游戏循环** |
| [25 Theory Engine 四类 opportunity](25-theory-engine-four-opportunity-synthesis.md) | 从"蒸馏教师决策"转向"离线发现规则、确定性执行" |

## 测试 · 度量 · 负结果

| 文档 | 内容 |
|---|---|
| [08 测试与验证](08-测试与验证.md) | 不变量门与复现方式（同上） |
| [06 评审与风险册](06-评审与风险册.md) | 7 维 / 41 agent 对抗式架构评审留下的 25 条 confirmed 风险 |
| [28 shadow 反事实探针](28-shadow-counterfactual-result.md) | 在**不扰动轨迹**的前提下量"一个干预到底翻了哪些决策"——把机制有效性从轶事变成数字 |
| [29 #15v2 首个跨种子结果](29-exile-v2-result.md) | 修指标比加机制更诚实（也更准） |
| [30 #15v2 Metric Card](30-15v2-metric-card.md) | **预注册**指标卡，冻结于看 held-out 之前，用于防止"看着结果调指标" |
| [31 #15 结案](31-15-resolution.md) | 126/126 seed 全 INCONCLUSIVE：残余是**度量的时间泄漏**，不是机制缺陷 → **不加任何机制** |
| [`bench/bakeoff/README.md`](../bench/bakeoff/README.md) | 3 命令可复现的蒸馏 bake-off；含两个诚实负结果（ranker 赢是"机制赢不是质量赢"；LLM 自评法官不可靠） |
| [38 决策路值不值](38-does-the-decision-path-earn-it.md) | 把「均匀随机」做成可跑的臂：模型可与随机区分，但没有一条差异指向好的方向；并报出 CI 结构上查不到的硬不变量 #01 破损 |
| [39 Node 端口处置](39-node-port-disposition.md) | `tools/sim_social_port.mjs` **退役**为历史文物：根因二分到单个 commit，且它自己 33% 的 seed 就是红的 |
| [40 出货交叉点 N=60 × 端上 SLM](40-device-n60-slm-the-shipping-intersection.md) | 从未测过的那一格：真出货配置下模型只驱动全镇 **0.04%** 的决策 |
| [41 分棒契约](41-baton-contract.md) | **所有并行子任务的共同约束**——红线、验证契约、报告契约、统计纪律，以及视觉棒的五条工具链盲区 |
| [42 编码病理 vs 能力天花板](42-prompt-pathology-or-capability-ceiling.md) | 把出货那一份 prompt 原样喂给 31B：编码可读**且** 1.5B 有天花板，两者并存；顺带解释了「模型把人饿穿」的机理 |
| [43 Wave C 计划](43-wave-c-plan.md) | **当前这一波的权威计划**：从「研究仓库」转向「像个游戏」；路线图差量、共同规则 R1-R6、逐棒 brief 与验收 |
| [45 外部后端不变量门](45-external-backend-invariant-gate.md) | 每一道既有的门都跑在 `backend=null` 上 ⇒ #01 从没在模型路径上被验过。补一道**确定性**的 `random` 后端门 + 两条引擎边界；含两条走不通的路（提抢占线炸成 livelock、一个把作者骗了一轮的计数器 bug）<br>（原棒落盘为 40 号，与 HEAD 的 `40-device-n60-...` 撞号，合入时改为 45） |

> **`tools/sim_social_port.mjs` 的状态：已退役（2026-07-26），历史文物，不入 CI，不验证引擎。**
> 它的逻辑冻结在 2026-07-03，读的却是仍在演进的 `game/data/*.json`——自"阵容 6→12 人"
> （`251ab9f`, 07-05）起就已分叉，今天 12 个 seed 里 7 个红；且它没有 space/floor 模型，
> 对引擎不变量 #34-#37 零覆盖。**它的红不是引擎回归**（同 seed 下 Godot 全绿）。
> 处置理由与全部实测见 [39](39-node-port-disposition.md)；确定性红线的真正跨进程锚是
> `tools/ci.sh` 第 4 步的金标 + 逐 tick 前缀链，不是这个端口。

> #15 这条链的**起点**是 docs/27@exile-hardening（负结果原文，未并入 master）：
> `git show exile-hardening:docs/27-exile-hardening-negative-result.md`。
> 同理 docs/26@phase-d-contract-hardening 只存在于 `phase-d-contract-hardening` 分支。

## 移动端与端上 SLM

| 文档 | 内容 |
|---|---|
| [18 Android APK 构建](18-android-apk-build.md) | 骁龙 8 Elite / arm64 出带端上 SLM 的 APK |
| [34 真机 SLM 挂死与泄漏](34-slm-device-hang-leak.md) | 16GB 原生泄漏 → 根因是 worker 生命周期 use-after-free（**第一版根因"Adreno GPU"被自己证伪**）→ 池化治本 → 真机 GPU/CPU A/B → 端上默认 CPU |
| `35-slm-decision-share-and-lod-soft-gate.md` | *（并行撰写中，尚未落盘）* 端上 SLM 决策占比的**诚实分母**，以及 N=60 下 LOD 对软不变量的影响 |
| [11 LLM 部署实测对比与选型](11-LLM部署实测对比与选型.md) | 多机器 × 多模型尺寸的延迟实测与选型 |
| [15 手机可行性 · 算力上界](15-手机可行性-算力上界-世界扩展.md) | 手机端算力上界估算与世界扩展的三线深研 |

## 规模与性能

| 文档 | 内容 |
|---|---|
| [12 规模与美术 roadmap](12-规模与美术-roadmap.md) | 多 NPC 与美术的研究型规划（**只规划不实现**） |
| [14 可扩展性与规模 · 设计](14-可扩展性与规模-设计.md) | 策略空间可扩展化、时间同频、更大群体的上界估算 |
| [32 规模诊断](32-scale-diagnostic.md) | 镇子扩到 N 会怎样——含一次被作者自己抓到的过度解读 |
| [33 观察无关 aggregate LOD](33-viewer-independent-lod-delivery.md) | 设计→实现→双层对抗评审→修→验→**诚实定位为原型而非"已交付数百 NPC"**；"别推断瓶颈，埋计时器测"的方法论教训 |

## 素材、背景与参考

| 文档 | 内容 |
|---|---|
| [09 美术资产与版权](09-美术资产与版权.md) | CC0 素材来源、三级美术回退、版权红线 |
| [00 现有项目与流水线分析](00-现有项目与流水线分析.md) | 上游 `June/22nd` 流水线分析——本项目"复用而非重建"的出发点 |
| [04 参考项目](04-参考项目.md) | 已核实的对标项目；**学设计不抄代码/美术** |
| [10 社交深化 · 前沿研究](10-社交深化-前沿研究与roadmap.md) | 意见动力学 / 谣言传播 / 合作博弈等 6 路检索，按三约束筛选后的落地取舍 |
| [`_paper-notes.md`](_paper-notes.md) | 论文札记 |
| [`_gpt55-review-brief.md`](_gpt55-review-brief.md) | 送外部评审的 brief |

## 媒体

演示视频与截图在 [`media/`](media/)。README 只链当前构建的片子；更早的片子仍留在目录里作为历史。
