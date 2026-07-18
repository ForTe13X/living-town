# 25 · Theory Engine 四类 opportunity 合成 — 从「蒸馏教师决策」到「离线发现规则、确定性执行」

> 承接 docs/22（NPU 决策路径）、docs/24（Theory Engine 设计规格）、docs/13（实验札记）。
> 本篇是**合成**：把 conflict / secret / faction 三条线、四类 opportunity 的完整弧线收成一个可复述的方法与结论。
> 一句话：**镇上"有后果的社交决策"的 in-character 政策，可以被【离线盲评发现 → 蒸馏成确定性 typed 规则 → 运行时零推理】地吃下；前沿模型的价值收敛到"配音"。**

---

## 0. 起点与反转

**原问题（bake-off）**：前沿教师（Nemotron-120B）能不能给出比 logic 地板更好的**决策 policy**、值得蒸馏进端上 SLM？

**Phase C 的反转**：不能——教师**没有**更优的稳定 policy。
- 富态 packet、batch=30：single-vs-batch 一致率仅 **29.5%**、候选置换稳定 37.2%——batch 标签不可训练。
- 但根因诊断出**三层混淆**：①样本几乎全是"无所谓时刻"（logic 地板把需求稳在高位、全 2516 决策 min_need 从不 <44.7）；②**batching 单调下毒**（single-vs-single 决定性案例 **97.6%**、batch=5→36/10→37/30→34%）；③旧 packet 缺"冲突显著性"→教师根本不知道有心结。
- **补上显著性后教师主动处理冲突 7%→88%、回归 logic**——所谓"教师=现实、logic=戏剧"其实是 observation 差、不是 policy 差。
- ceiling（单案例、K=5）分岗：**冒犯方该道歉 recall@5=90%（logic 已对）**、**委屈方小怨气 confront 仅 55%**；且 LLM 排序**非序不变**（置换后 top-5 set-overlap 0.46）。

**结论转向**：不去"蒸馏教师的 argmax 决策"，而是**用离线盲评把每类社交机会的 in-character 政策找出来、写成确定性 typed 规则**。这既躲开了"教师无稳定 policy / 端上小模型更不稳"的坑，又把决策做成**零运行时推理**。

---

## 1. 可复述的方法（同一套 playbook 跑了四遍）

```
TheorySnapshot（typed，非展示串）
  → 富态 packet + 显著性（心结/秘密托付/风评）
  → 单案例 teacher 标注（batch=1，97.6% 自洽；永不 batch）
  → ceiling（valid@K / recall@K / 候选置换 set-overlap）
  → 10 路独立盲评（Claude，非自评；镜像翻转消位置偏、A=A 控制测判平、按种子 cluster-bootstrap、per-persona 劈开）
  → 特征探针（什么人设/信号翻到"做" ）→ held-out 冻结规则复验
  → wire 成 CHARACTER（默认克制 + 人设例外）+ DRAMA（罕见节拍）
  → CI 门（确定性逐字节 + 37 不变量）→ 真引擎眼验（record-on-stage-change）
```
关键纪律：**永不让教师自评**（judge=Claude≠教师）；**in-character 与 dramatic 分开评**；显著性只喂 typed 事实、展示串不作输入；数据坏了（salience_probe_v0）就隔离、不进 judge/训练。

---

## 2. 四类 opportunity 的结果

| opportunity | 攻击形态 | logic 过度做 | 盲评 p_eff(做) | CHARACTER 默认 | 人设例外 | DRAMA 节拍 | 真引擎眼验 |
|---|---|---|---|---|---|---|---|
| **confront** | 一对一当面 | always confront | 0.08–0.12 CI[0.03,0.15] | defer（让它过去） | **1**：耿直老海 | 憋久的要紧心结爆发 | 场次 logic 802/char 59/+drama 271 |
| **leak** | 背后泄密 | revenge-leak | ~0.06 | guard（守信） | **1**：爱八卦阿丽 | 话痨憋久抖漏 | 阿本信任 76→40、怨 0→13 |
| **endorse** | 背后串谋贬损 | 49%(占决策 13%)…实为 29% | 0.043、但阿丽 0.43 | abstain（弃权） | **1**：爱八卦阿丽 | —（gossip 轴无需独立节拍） | 阿丽=全镇八卦枢纽 |
| **rally_oust** | 公开群体羞辱 | 49%（占决策 13%） | **0.014 CI[0,0.028]** | abstain（弃权） | **0** | 众人合围真·过街老鼠 | 候选 10756→388、picked 5300→267 |

held-out 复验（confront）：冻结自 judge#1 的规则（默认 defer + 耿直 confront）套到 disjoint 的 judge#2（67 例新案）：**char 98% / default-defer 94% / logic 6%**——真泛化、非过拟合。

---

## 3. 涌现的结构：人设-例外谱 = 1/1/1/0，两条攻击轴

四类连起来看，例外数 **1 / 1 / 1 / 0** 不是"越激烈例外越少"的单调，而是**两条轴**：
- **当面**（confront）：直性子老海破例——敢当面把话说开。
- **背后八卦**（leak + endorse）：**同一个话痨阿丽**在两处都破例——泄密与串谋贬损本是同一件事（嚼舌根）。
- **公开群体羞辱**（rally_oust）：**零人破例**——煽动围攻是所有人都不会主动挑的。

同一人设在**同一条轴**上一致（阿丽 leak+endorse 双破例；老海只在当面轴破例）；攻击越"公开/群体化"，in-character 的空间越窄，到公开围攻已是全员克制。**这条谱是四场独立盲评各自涌现、事前没设计**——是这镇人设结构的真实投影，也是"per-persona 劈开"才看得见的东西（整体 p_eff 会把阿丽的 0.43 淹没成 0.043）。

---

## 4. 架构：CHARACTER 默认克制 + 人设例外 + DRAMA 罕见节拍

- **两轴分开、绝不加权混合**：CHARACTER 判"像不像这人此刻会做"、DRAMA 判"要不要为剧情开一场"。`#15 涌现放逐`就是"混了会怎样"的实证护栏——v1 让所有憋久的怨都爆→抹平了放逐→改成只爆 escalated/高severity 才回绿。
- **纯 f(TheorySnapshot)**：无 RNG / 无 Time → 与红线兼容，S0 逐字节确定；改的是 logic 地板行为、digest 数值变，但门校验的是"同 seed 两跑一致 + 不变量"，不是钉死某个金数字。
- **零运行时推理**：政策蒸馏进 typed 规则、不是蒸馏进权重——运行时不需要 NPU/model 做这个决策。DRAMA 用"憋够久/够严重/名声极差"作确定性 pacing、可回放。
- **need-floor 鲁棒性升级（顺带）**：endorse 抑制曾蝴蝶到 seed-4 的 `#01 无饿穿`（阿本社交需求赶不上）——修法不是缩抑制、而是 `SURVIVAL_GATE 20→24` 给 need-floor 更足赶路缓冲，把 #01 从"对当前决策集成立"升级为"对任意决策扰动鲁棒"。

---

## 5. 对 NPU 旗舰的落点（收敛而非放弃）

- **决策**：这镇"有后果的社交决策"的 in-character 政策 = 确定性 typed 规则，运行时零推理——**旗舰的"NPU 快决策"诚实收敛为：决策交给确定性 Theory 引擎、不需要模型**。
- **模型的真正增值 = 配音**：入戏 ~4.0/5（bake-off + player-interaction 双证），且被"引擎定事实/秘密"的护栏夹住（泄密 35%→0%）。NPU 服务于**动态入戏配音的 prefill**、常见话走冻结 voicebank（零推理）。
- 一句话：**引擎决策（快、安全、可回放、零推理），模型配音（入戏、它真正强处）**——四类 opportunity 从决策侧把这句话钉死了。

---

## 6. 方法层的教训（护栏也适用于我的实验方法）

1. **别让模型自评**——自评 4.6 被三路独立评审判 inflated→真 3.4、还漏掉 35% 秘密泄露。judge 永远独立、且非同一模型。
2. **改 floor 决策后，软不变量务必用 CI 满天数（60）验**——30 天太短、软涌现（谣言/承诺/放逐）本就 flaky，短跑给假红。
3. **撞硬不变量先"眼见为实"定位根因再动手**——`find_starve` 打出"阿本 social=0.40 正做闲聊"一眼看出是社交吞吐+赶路时序、非饥饿，于是修缓冲不是抑制逻辑。
4. **per-persona 劈开**才看得见人设例外——整体 p_eff 会把单人设的 in-character 信号淹没。
5. **真引擎眼验**（record-on-stage-change）：betray 的信任崩、endorse 的八卦枢纽、confront 的戏剧节拍——headless 门 + 真机定格双证，`--warmup-tick`/`--select` 是为此加的精确定格挂点。

---

## 7. 现状与下一步

**现状（全部 master、full CI 绿：37 不变量、det 3/3、六场景）**：
- 四类 opportunity 全部盲评验证 + wired + 真机眼验；endorse 经 SURVIVAL_GATE 24 做到 #01-safe、四类全 ON。
- commit 链：`f67e590` CHARACTER · `1adc88c` DRAMA · `10eb754`+`9bbf882` secret · `d7ac1ea` rally_oust · `cc53df3`+`3c7a70d` endorse · `05b990c` endorse 眼验。

**下一步（docs/24 的剩余）**：
- `aid`（亲社会互助）：0 案例需 pact 富数据（S3b 场景）才能采样、判定——logic 大概已 in-character。
- **DSL/MAP 泛化**：目前四类是"手写门 + 人设例外 + DRAMA 常量"；docs/24 的完整形态是 Typed Datalog/Horn + 局部对数线性软权重 + 确定性 MAP，把这些门收进统一规则层、把常量（petty 阈、DRAMA horizon、人设例外集）变成**可校准参数**。
- **LLM_PRIOR 接入**：ceiling 说 LLM 排序非序不变（0.46）→ 作先验必须权重压低 + 固定候选序；只在"小怨气 confront-vs-defer"这条窄缝上可能加分，其余 logic/规则已够好。
