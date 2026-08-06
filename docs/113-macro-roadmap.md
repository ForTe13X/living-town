# 113 · 宏观路线图——**架构与功能层面，不拘小节**

> 维护者：主集成会话（worktree `main-integration`，分支 `integration/batons`）。
> 本文是**活文档**：只写架构/功能层面的大局与相位，不列具体门。门与实测在各波回执里。
> 前置：外部评审（Codex，2026-08-02 与 2026-08-06 两轮）、docs/62（GPT-5 Pro 多镇裁决）、docs/41 合同。
> **数字与分支状态实测于 2026-08-06；它们会随代码前进而旧——权威永远是 `git` 与 CI，不是本文。**

## 〇、分支现实（今天实测，这是"检查各 branch"的答案）

| 分支 | HEAD | 状态 | 定位 |
|---|---|---|---|
| **`integration/batons`** | `ce75142` | 远端=本地，289 ahead of master | **唯一集成候选（trunk）**。Wave A→AA 全部 + 真机回执 |
| **`codex/narrative`** | `c107296` | **今天刚补推到远端**（此前只在本地，9 commits / 8193 行有丢失风险） | **叙事子系统**：NarrativeGlyphs / ViewContract / WebMazeGraph / S16 合成器。真进度，但**与 trunk 从共同基点分叉，未合、无 PR** |
| `wip/ac1-state-projection` | `d14de07` | 断电存档，**未验证、未过 CI** | AC1 的只读覆盖探针 + 草稿。**结论按未验证读** |
| `wip/ac2-story-ratchet` | `5407941` | 断电存档，**未验证、无回执** | AC2 的 story_test 棘轮改动。docs/108 §二验收一条未兑现 |
| `claude/competent-noether-…` | `42bdfa1` | 有 worktree | **APK 导出跑通了**（`build/out/*.apk` 实测存在）⇒ Codex "无候选构建"在**管线层**已破，缺的是**当前 HEAD 的构建** |
| `master` | `38ba4a7` (07-26) | 289 behind，**全程未动** | 红线守住：master 不动 |

**⇒ 分支层的两条大局判断**：
1. **trunk 是清晰的**（`integration/batons`），而**叙事是一条真实的平行子系统**，尚未并入。合并面：两者都改 `docs/README.md` 与 `docs/05` ⇒ **有冲突，需要一次显式的 reconcile，不是自动 ff**。
2. **"分散证据"是真的**（Codex Phase 0 的核心）：全绿散落在多个分支/worktree，**没有一个 exact-head 的 CI 收据**。这是运营债，不是代码债。

## 一、架构脊柱——**一切多镇的先决条件只有一条**

外部评审两轮都指向同一处，而 AC1 已经**量到了它的形状**（虽然回执未验证）：

> **权威状态投影（authoritative state projection）不存在。**
> `Inv.digest` 只折 `event_log`；`chain_step` 折 tick + 逐 agent 的 id/pos/needs/talking/option。
> **两者都不覆盖** beliefs / attitudes / factions / affinity / pacts / standing / stock / **space·floor** / money / memory。

**含义（这是本项目最贵的一句话）**：本 session 反复说的"逐字节一致"，真实含义是
**"事件日志 + 一个很窄的活状态投影没有分叉"**——它是强性质，但**不足以承载存档正确性、换页、冷热镇等价、回滚**。
两个世界里某人都在 (10,10)、一个在室内一个在室外 ⇒ 当前哈希给出相同值。

⇒ **架构第一刀（Codex 定，我复核认同）：`state_projection_v1`**，与旧 digest **并行新增、不重写**：
- 用于存档/读档/checkpoint/换页/LOD 边界的**权威投影**；
- 对高维状态（关系/信念）用**确定性增量子摘要**，避免每 tick 全量扫描；
- 判据不能用"一天前后变没变"代替"未来读不读"——**要覆盖静态、晚触发、中途恢复**，以及 0–1784 tick 的盲窗。

**这一刀落地之前，多镇/旅行/贸易/异步一律不立项。** 这不是保守，是 docs/62 早写过的"任一系统失败会被其余掩盖"。

> ⚠️ **【2026-08-06 AF1 设计（编号 121）更新——它把这条从"多镇先决条件"升级成"现在就有的 bug"】**
> AF1 验证了 AC1 的形状（29 个演化字段既不进 digest 也不进 chain）**并干预实证**：beliefs/stock/space·floor/
> attitudes/standing 全部 digest+chain SAME 而独立全态指纹 DIFF，且"驱动未来"延迟**无界且随 seed 抖**
> （belief 行为分叉 s1@1508、s3@never）⇒ "chain 迟早抓到"这个论证被杀死。
> **最要紧：现行存档硬门 `save_load_test.gd` 放过了一次"悄悄丢一条 belief"的 load**（两侧 digest 相等、零漂移、
> 2460 tick 从不浮现）⇒ **state_projection 不只是多镇的门票，它的第一个消费者是【今天的存档正确性】。**
> AF1 推荐**路 (b) 并行新增 `state_projection`**（零金标，新函数不是 S0 对比量）。⚠️ 这仍是 §0.8 设计，实现待用户拍板。

## 二、正确性欠账——**在做新内容之前先清零**

| 欠账 | 现状 | 处置 |
|---|---|---|
| **#43 商贩自证** | `_nearby_agents` 不排除商贩 ⇒ 一笔只被卖家看见的成交也算"被看见"。**修复 workflow 在跑**（measure→fix→双反驳，走 R12） | 编号 112（在飞行中，尚未落盘）。零售豁免线只量不收紧（改判据要用户拍板） |
| **被拒行为叙述成成功** | AA2 实测 3565 条引用里 **976 条（27.4%）**把 rejected event 写成已发生；真机 docs/111 又肉眼看到一次。⚠️ **AD2 设计（编号 116）把它重新框定了**：`accepted` 字段【已在】，社交路已正确区分被拒，屏幕真出错的是表现层 `Main._event_prose` 对社交类型【不读 accepted】——**是"读侧漏字段"，不是"缺 schema"** | **分三档（AD2 编号 116）**：✅**档0 已落地（AE1 编号 118）**：_event_prose 十类社交加 if ok else，实测被拒讲成成功 496→0、零金标、带回归门（已接进 ci.sh 第5步）；档1 加 `effect_applied`/`rejection_reason`【不折金标】=零金标（用户拍 schema）；档2 经济族失败可观测=移金标走 R12（用户拍板）。原提的"四字段统一模型"被 AD2 证明捆错了——修 27.4% 不需要它 |
| ~~**fixture/scale 门可能 fail-open**~~ ✅**已收（AE2 编号 119）** | 普查约18个量具：真 fail-open【集中在1个】(烘锚流水线)，其余早已 fail-closed、ci.sh 自身干净 | 已堵+负对照：子进程非零立即失败、iso 内容寻址到 HEAD:game、bake 绑 tree_sha 拒空 commit；顺带重烘过期 ledger |
| **AC2 `vanished` 只 warning** | 删一个具名病例 + 别处强化 ⇒ aggregate 不降而过门 | 具名槽消失应**直接红**；合法删除走**显式 rebaseline**（照抄 R12 的 rebake_history 文化） |
| **半宏观生产** | 池按人口扩容，但产出触发仍绑少数具名工人 ⇒ N=60 口粮左尾的结构性来源 | 引入镇级 `IndustryState`（labor capacity / backlog）解耦到达过程；具名 NPC 仍供归因。**用干预证，别推断**（U1 已证零假设扰动能消红） |

## 三、功能轨道——**可并行，彼此不冲突**（用户点名的那些）

这些是"好玩"的一半，**多数与架构脊柱正交**，可以在 §一/§二推进的同时并行，但**owns 必须错开**避免 branch conflict：

- **叙事 / storylets**（`game/scripts/narrative/**` + `game/narrative_lab/**`）：已有一条真实子系统在 `codex/narrative`。下一步是**并入 trunk**（先 reconcile docs 冲突），然后在其上做 storylets（预置的多幕小剧本）。
- **美术 / visual**（`WorldView.gd` + `game/assets/**`）：室内分色（R2）、家具语义（S3）、树丛（V3）、HUD（T3）已落 trunk；✅**AF2（编号 122）落了季节视觉**——实测夏↔春本来只 ΔE00 2.71（卡 JND、眼验糊成一块），已拉到 ΔE00≈7，零金标（只动夏季帧、CI 春帧逐字节不变）；并更正了一处过期注释（P_NIGHT 从来不是夜间暗面罩，夜色是 Main._daylight 乘子+加色光）。⚠️**遗留**：四季可分门 `assert_season.py` 写好了（改前红/改后绿）但**未接线**（需 visual_gate.sh 多拍 8 张四季昼夜帧，非平凡）⇒ 跟进项。**但全部只在桌面验过**——真机待当前 HEAD 构建（§四）。下一块空地：**室外建筑立面、天气视觉、其余三季夜间光照**。
- **NPC / 社会产出**：手艺痕迹（V1/Z2 四门）、商贩消费侧痕迹（AA3）已落。下一步是**把社会产出接到叙事**（手艺弧、买卖弧进 storylet），以及 §二那个事件结果模型让"尝试/被拒/成功"在 NPC 记忆与故事里区分。
- **wiki**：全新绿地。**镇民百科**——每个 NPC 的职业/关系/信念/大事记，从 `event_log` 与 `beliefs` 生成（只读投影，不进金标）。低风险、高展示价值。
- **map / interior**：`map.json` 权威可走性 + 室内模板已成熟。下一块：**第二类室内布局**、可交互家具的语义扩展。

⚠️ **并行纪律**：每根棒的 `owns` 必须是**文件级不相交**的（本 session 反复验证有效）；docs 编号提前占；`README.md`/`docs/05`/`docs/README.md` 是**高冲突面**，同一时刻最多一根棒碰。

## 四、交付与运营——**把分散证据收敛成一个候选**

Codex Phase 0，我复核认同并补一条实测：

1. **单一集成候选**：`integration/batons` 就是它。叙事、AC1/AC2 wip 各自走**可审查的分支/PR**并入，不停在工作树。
2. **exact-head CI**：⚠️ **GHA 超时 15 分钟，而本地全量 CI 已 ~20-26 分钟**（实测跟机器负载浮动）⇒ **CI 必须拆**：
   - PR 快速硬门（10-12 分钟内：红线#4、lint、数据、S0 硬不变量、金标）；
   - nightly/release 全量门（软门网格、视觉门、场景、跨进程锚）。
3. **每份收据绑定**：repo + commit/tree + 数据版本 + Godot/Python/FFmpeg 版本 + 完整命令。（本 session 的收据大多绑了 commit，但没绑工具版本——这是真实缺口。）
4. **真机门（当前 HEAD）**：APK 管线已通（competent-noether）⇒ **重建当前 HEAD 的 APK**，把 docs/111 的触摸/暂停/HUD/音频逐条**在新构建上复验**（旧 APK 是 07-30 的，早于 T3 的 HUD 修复）。
5. **阶段产出**：录屏（`tools/record-godot.sh`，只走整数倍缩放）、真机截图、给非技术读者的 `docs/56`、README。**GIF 与 README 的 Codex 打磨那一环**：Codex desktop 的 computer-use 授权被拒过，README 由本会话自己打磨并在回执里注明这一环没走。

## 五、相位（Codex 的，经分支实测更正）

```
Phase 0  收敛工作面：叙事已备份到远端 ✅；AC1/AC2 存为 wip ✅；
         剩下——单一候选 + 拆分的 exact-head CI + 收据绑工具版本。
Phase 1  清正确性欠账（§二）：#43（在飞行中）· 事件结果模型 · fixture fail-closed · AC2 vanished 红门。
Phase 2  架构第一刀：state_projection_v1（§一），与旧 digest 并行。
Phase 3  修好 Round 3 执行合同再跑 S21-S28（S28 必须独立审阅者；S24 依赖 Phase 2 的新投影）。
Phase 4  真机门：重建当前 HEAD APK，复验触摸/暂停/HUD/音频。
Phase 5  才恢复多镇：生产 capacity 与具名 NPC 解耦 → N=24/40/60 held-out 供需校准 →
         旅途 social liveness → 两镇纯 headless spike。这些没做完之前，不实现贸易/货运/换页。
并行     功能轨道（§三）在 Phase 1-2 期间同时推进，owns 文件级错开。
```

## 六、共同约束（合同，照抄不重述理由）

- docs/41 红线四条 + §0.5；**改契约 / 改金标口径 / 改判据是用户的决定**。
- **红数不是判据**（X1/Y1/Z2/AA3 四证：语义为零的 0.400→0.401 扰动能消硬红/压穿余量）⇒ 对零假设臂用**连续余量**判。
- **"金标 N/N 不变" ≠ "该 N 不变"**（Y1）；**"某臂让金标动了"同样是抽样**（AA1：九臂只动 seed 8）。
- **可比性 ⟺ 两棵树在 `game/scripts/` 与 `game/data/` 上逐字节相同**（Y1 更正），一条 `git diff` 可查。
- **一个检查若"打印了却不阻止"就不是检查**；**一次 push 可以退出码 0、报"已同步"、而什么都没推**（分支没动）——**"成功了"≠"做了事"**。
- **先确认你量的是哪个对象**（H1/S3/V3/W3 四次量错；Z2："平均在场"≠"每 seed 至少一次"；AA3："在班"≠"在摊位"）。
- **写下一个数会改变这个数**（U3 的 xref、Z3 的悬空引用计数、索引的"某号不存在"预告）——报计数时当心量具污染。
- **别在 CI 跑时改它正在读的文件**；**tee|tail 吃退出码** ⇒ 写文件再读。
- **别在别的 session 的分支/checkout 上写**；主 checkout 现在是 `codex/narrative`，集成在独立 worktree `main-integration` 做。
- 编号三位数（`lint_links` 已修）；**107 属 codex/narrative、109/110 属 AC wip、112 留给 #43 修复**。

## 七、本轮（≈25 strides 周期）刻意不做什么

- **不启动新叙事内容**、不正式跑 S22+、不开多镇功能——三条外部评审都说了先决条件未满足。
- **不在 #43 修复落地前**开新的经济/社会波次（它动 `Sim.gd` 与金标，会与新棒撞车）。
- **不一次派满**：同仓库有 ≥4 个别的 session 在写 + 刚从每周 API 限额恢复 ⇒ 少派、错开 owns、每波先 review 分支再动手。

## 八、下一步（本文提议，随 #43 workflow 落地推进）

1. #43 修复 workflow 收尾 → 合入 trunk → 全量 CI 收据（Phase 1 首块）。
2. **一根只读棒**：把 §四·2 的 CI 拆分方案写成可执行的 `ci-pr.sh` / `ci-full.sh` 提案（不改 `ci.sh`，先出提案）。
3. **一根 reconcile 棒**：把 `codex/narrative` 与 trunk 的 docs 冲突面摸清，给出合并方案（只读，不合）。
4. 功能轨道择一并行（wiki 最绿、最低冲突）。
