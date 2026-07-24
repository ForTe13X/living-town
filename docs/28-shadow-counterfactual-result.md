# Shadow 反事实：把"2 个 lever 失败"量化成"各自翻错了哪些决策"

分支 `shadow-instrumentation`。docs/27 路线①落地：`_acceptance_margin` 暴露每次接受决策的数值 margin，`--shadow-dump`
导出 14926 条决策（12 seed × 60 天），`tools/shadow_analyze.py` 在【同一批提议 + 同一状态】上直接算某假想 lever
会翻哪些决策——**绕过确定性仿真的轨迹搅动**（正是这条混淆让 exile-hardening 的两个 lever 无法解释）。

**红线**：整套探针纯观测——`branch@shadow-off vs master` 0 digest 差异、`shadow-on vs shadow-off` 0 差异、gate 全绿(det 3/3)。

## 病灶定位
"本应放逐"的决策 = 共识型 outcast（零填充镇内声誉<=-0.8、负向占比>=2/3、覆盖率>=0.5）的 greet/invite
被【中立/弱关系】者（|standing|<=0.5、非好友）接受。全 trace 仅 **13 个这样的"被接受的本应放逐"决策**——
这就是 #15 残余的病灶。理想 lever：翻掉这 13 个，别碰别的。

## 反事实精准率（on the same decisions, no sim rerun）
| lever | applies | flips | on_target | collateral | 精准率 |
|---|---|---|---|---|---|
| A `EXILE_NEED_DAMP=1.0` | 1545 | 76 | **0** | 76 | **0%** |
| B `IMAGE_SCORE_K=8`（原实现口径） | 9263 | 359 | 7 | 352 | **2%** |
| B `IMAGE_SCORE_K=8`（零填充口径） | 9263 | 359 | 7 | 352 | 2% |
| targeted `P=12`（GPT-5 Pro 定向版） | 14 | 8 | **8** | **0** | **100%** |

**读数**（把双评审的口头判断变成硬数字）：
- **Lever A 精准率 0%**：翻了 76 个决策，无一命中病灶——它只作用于 standing<0 的 responder，恰恰放过了"中立/友好者过度接受"这条致因链。GPT-5 Pro"A 从没碰到被诊断的 responder"得证。
- **Lever B 精准率 2%**：翻 359 个、352 个是附带伤害（全动作、误伤好友/非 outcast）。且原实现口径与零填充口径在本 trace 上翻转集相同（这两个 seed 段里负 img 的 actor 覆盖率都高）——量级差没改变 flip 集，但两者都"翻错一大片"。
- **targeted 精准率 100%**：只作用 14 个决策、翻 8 个、全在病灶上、0 附带。P=12 只覆盖 margin<=12 的 8/13（另 5 个被大幅度接受）；调大 P 提升 recall 但要盯 collateral——**现在可在同一批决策上调 P，无需重跑仿真、无搅动**。

## 意义
这正是 shadow 探针要给的：把"某 lever 改了哪些【目标】决策"与"世界后续演化好不好"彻底分开。exile-hardening
当初栽在后者（轨迹搅动让 flip 集无法归因）；现在前者可直接、确定地测。**下一步**：以 targeted lever 为骨架，
在此 harness 上调 P / 门限 → 定 #15v2（日级事前快照 + 三态 + 遭遇代表性）→ 全新 seed 43-126 确认 → 再谈上机制。
