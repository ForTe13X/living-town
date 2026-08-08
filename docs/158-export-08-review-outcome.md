# 158 · export §0.8 评审结论（货出→钱进 / #45 双向口径变更）

> docs/41 §0.8 要求核心不变量口径变更前**两路独立评审收敛**才实现。export 改 #45（硬货币溯源）口径 = 核心变更（docs/157 §七 §0.8=YES）。① 内审=7-critic refute workflow（本文 §一，**已完成**）；② 外审=GPT-5 Pro（chrome，被要求 REFUTE，冷独立）——**进行中**。**export 实现门控在两路收敛之后**；本文先落内审结论 + required fixes，外审收敛后补 §三。

## 〇、内审判决：**SOUND_WITH_FIXES**
7-critic 逐条 refute（grounded in 落地后的 E2a 码）。核心设计成立、绑定 6 条 fixes 后可实现：
- **#34 守恒**（HOLDS/high）：`transfer("external","town",revenue)` 两端都在 `money_total()` 守恒集（Sim.gd:3273-3274）⇒ Δ=0，镜像 import。**必要非充分**——守恒的 money_total 会**盖住"货没动/少动"的假成功**，故 #38/#45 必须独立守。
- **external 闭环有界非负**（HOLDS/medium）：`transfer` 的 `from<amt:return false`（:3245）+ external 只被 import 贷/export 借（grep 证）⇒ `external = Σimport − Σexport ≥ 0` ⇒ 累计 export 收入 ≤ 累计 import 支出、镇对外净头寸 ≤0、**不能被泵富**。⚠ 三条诚实边界：(a) #35 external≥0 臂（Invariants.gd:611）是**门/bench 检测**、非运行时强制；运行时唯一强制是 transfer 的 from<amt 守卫。(b) "抑通胀"只保证在**净头寸**上；高 export price×cadence 仍能标定级抹平赤字镇压力。(c) 成立**条件于忠实实现**（走 transfer + `_export_fit` 镜像 `_import_fit` + `_stock_move` 非 `_stock_take` + 先收后出 A′）。
- **#38 export 减号臂**（HOLDS/high）：`_stock_move(good,−N,"export")` + 白名单加 "export"（自动落减号臂）是**唯一且正确**的最小改动；`_stock_take` 错（污染 #40）。

## 一、6 条 required fixes（实现棒必带）
- **F1（命门 · 符号）**：`_stock_move` 的 −delta 臂返回**负** applied（`applied = -mini(-delta,cur)`, Sim.gd:3376/3381）。docs/157 §二字面 `revenue = applied×price/den` 会得**负值** ⇒ `transfer(amt<=0:return false, :3242)` **静默 no-op 每一次 export**、external 虚高于 ext_expected。⇒ **必须用幅值**：`revenue = abs(applied)×price_per/price_den`，且 export 事件 `_amt_of` 与 revenue transfer 用**同一幅值**，镜像 import 的 `applied>0` 守卫（:3724）。
- **F2（#45 判别力）**：docs/157 §四负对照矩阵只测**单边**注入。补一条**跨边抵消**负对照：同时注入 phantom import(+X, 良构) 与 phantom export(−X, 良构) 净为 0、且 **export lane 激活**（非关）下复跑 import NEG_45 ⇒ 证 #45（或 #35+transfer+#38）仍抓得住。
- **F3（社交排除集 · 理由订正）**：加 "export" 到 Invariants.gd:225 **动作正确**；但 docs/157 §五 line63 的理由 "#2/#3 会被喂饱" **错**——export 事件 actor=port_dock（非居民）、target=town ⇒ 只可能虚增 **#2「社交发生」accepted 计数**、**动不了 #3「无永久孤立」**（#3 遍历 S.agents 居民）。订正为 **"#2 only"**，与 E1 import 理由（:230-231, 亦 #2-only）一致。
- **F4（标定诚实 + 反馈耦合货危险）**：删"结构上不饿镇"的"结构"字样——防饿来自**选货红线（未验）+ 标定 floor**，非结构保证。(a) floor 须按 held-out 13-30（尤 seed 18/30）最坏多日净消耗**逐货标定**、非拍一个 a-priori 整数；(b) 选 export 货前跑 docs/157 §一.3 自己要求的**物理库存 surplus 探针**（现存 stock > floor 有余量，拒 coverage 指标假象候选）；(c) **★把 `整洁` 的 `_clean_mult=stock/cap` 反馈耦合（Sim.gd:1909-1921）列入选货红线**——整洁是 §一.3 的 a-priori 候选，但它的库存反馈驱动广场吸引力，export 抽它会**退化清洁反馈**。⇒ **排除反馈耦合货**，或 floor 设得相对 cap 很高使 `_clean_mult` 退化有界，并在 held-out 量化广场吸引力 delta。
- **F5（人口缩放）**：export `floor`/`batch` 须进 K1 人口换尺度（start_new 处 rescale，镜像 production Sim.gd:853/3335-3355），**或**显式把 export 限定 N=12、把 §一.4"结构不饿镇"降级为**仅 N=12 标定**主张、held-out 对 #40（Invariants.gd:992-994）实测。
- **F6（货侧合法性 + #45 空 import 守卫 + 回放）**：import 有 #44 守"进的货/港合法"，export **货侧无对称硬门**。⇒ 加 **#44-analog for export**（export 事件 actor∈export_nodes、good∈export_lane、reason=export，镜像 :1019-1035），**或**在完备性声明里**显式认领这条不对称缺口**（非列为可选）。另：#45 的 export 项须在 import lane_price 字典为空时**也计算**（Invariants.gd:1062 附近 guard 重构）；重验 goto_tick **先收后出**回放确定性（external reset :847 在 econ_total0 :849 前，正确；export ordering 须同样 replay-safe）。

## 二、内审侧结论
核心设计（external 闭环 / #34 守恒 / #38 减号臂 / #45 双向原则）**成立**。F1（符号命门）与 F4（反馈耦合选货）是最实质的两条——F1 不修则 export 全程静默失效、F4 不修则 export 整洁反噬清洁系统。实现棒必带 F1-F6。

## 三、外审收敛（GPT-5 Pro，冷独立）
**〔待补〕** 外审冷读 docs/157 + 码、被要求 REFUTE，独立成结论后回填；两路收敛判决（是否发现内审漏项 / 是否同意 SOUND_WITH_FIXES）落此。**export 实现门控在本节收敛之后。**

## 四、实现计划（外审收敛后）
export 首片：export_lane（surplus 货、A′ 先收后出）+ external 闭环 + #38 白名单 +"export" + #45 双向泛化（F1 幅值 + F2 跨边负对照 + F6 空守卫）+ 社交排除集 +"export"（F3 理由 #2-only）+ floor 标定（F4 逐货 held-out + 排反馈耦合货）+ 人口缩放（F5）+ 货侧合法（F6 #44-analog 或认领缺口）→ 重烘三锚（committed 树，docs/155 §九纪律）。P4 deferred：多镇域 / #38-trade 原子性 / 完整 #36 / 分布通胀阈值 / 口岸落图。
