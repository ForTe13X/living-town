# 113 · 宏观路线图——**架构与功能层面，不拘小节**

> 维护者：主集成会话（worktree `main-integration`，分支 `integration/batons`）。
> 本文是**活文档**：只写架构/功能层面的大局与相位，不列具体门。门与实测在各波回执里。
> 前置：外部评审（Codex，2026-08-02 与 2026-08-06 两轮）、docs/62（GPT-5 Pro 多镇裁决）、docs/41 合同。
> **数字与分支状态实测于 2026-08-06；它们会随代码前进而旧——权威永远是 `git` 与 CI，不是本文。**

## 〇、分支现实（今天实测，这是"检查各 branch"的答案）

| 分支 | HEAD | 状态 | 定位 |
|---|---|---|---|
| **`integration/batons`** | `091411c` | 远端=本地，**319 ahead of master** | **唯一集成候选（trunk）**。Wave A→AG 全部 + #43 已合 + 真机回执 |
| **`codex/narrative`** | `c107296` | 已备份到远端（主 checkout 停在它上面） | **叙事子系统**：NarrativeGlyphs / ViewContract / WebMazeGraph / S16 合成器。真进度，但**与 trunk 从共同基点分叉，未合、无 PR** |
| `codex/main-repo-review` | `6102134` | 外审文档分支（今天新增，纯 docs） | Codex 周期复核（2026-08-06 两轮）。**本文 §〇–§八 已吸收其更正** |
| `wip/ac1-state-projection` | `d14de07` | 断电存档，**未验证、未过 CI** | AC1 的只读覆盖探针 + 草稿。**结论按未验证读** |
| `wip/ac2-story-ratchet` | `5407941` | 断电存档，**未验证、无回执** | AC2 的 story_test 棘轮改动。docs/108 §二验收一条未兑现 |
| `master` | `38ba4a7` (07-26) | 319 behind，**全程未动** | 红线守住：master 不动 |

**⇒ 分支层的两条大局判断**：
1. **trunk 是候选、但"清晰"只是约定不是保护**（Codex §三.1 更正）：`integration/batons` 没有 branch protection，PR 运行期间 base 还会前进 ⇒ 真正的"单一候选"要**冻结候选 SHA + required checks + 合并策略**，不是靠命名。**叙事是一条真实的平行子系统**，尚未并入——⚠️**更正（Codex §三.8，本会话已实测）**：以共同基点 `dae2fbe` 算，trunk 改 79 path、narrative 改 60 path，**交集为 0**；当前树**没有已证实的文本 merge conflict**。仍需一次**语义** reconcile（两边都动 `docs/README.md`/`docs/05` 的语义），但不能把预期冲突写成既成事实。
2. **"分散证据"是真的**（Codex Phase 0 的核心）：全绿散落在多个分支/worktree，**没有一个 exact-head 的 CI 收据**。⚠️**更正（Codex §三.2）**：这不止是运营债——fail-open runner、过窄 digest、缺 state projection 是**测试/代码架构债**，只整理分支修不好它们。

## 一、架构脊柱——**多镇有两条先决条件**（不是一条）

⚠️**更正（Codex §三.10）**：本文原写"先决条件只有一条（state_projection）"是漏了 docs/62 的既有裁决——
**知识权限（epistemic locality + domain-scoped `KnowledgeState` 三臂）是并列的第一刀**：
哈希能证明冷/热态等价，却**挡不住 B 镇直接读到 A 镇尚未传播的事实**。两条都要做、作用不同：
投影管"状态一致性"，KnowledgeState 管"信息可见性"。KnowledgeState 可在**单镇/抽象域**上先跑三臂证伪（即时全局知识 / 匿名延迟传播 / 具名 carrier 传播），**不依赖完整多镇地图**。

下面是第一条（状态投影）。外部评审两轮都指向它，而 AC1 已经**量到了它的形状**（虽然回执未验证）：

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
>
> ⚠️**再更正（Codex §三.11，实现波要吸收）**：仓库**并非完全没有权威快照**——`Sim.save_game` 已有**反射式全量 snapshot/schema + load 恢复**。
> 真正缺的是从**该 codec 抽取**出的 canonical / versioned / hashable 等价性 oracle + 能咬住遗漏字段的 mutation/round-trip 门。
> ⇒ 实现时**优先"从现有 save codec 抽取单一 oracle"，而不是另造第二套 projection**（否则制造第二个 source of truth）；
> "增量子摘要"在未审计所有 mutation path 前是**过早承诺**。这把 AF1 的路 (b) 从"新写一套"收紧成"给 save codec 加 canonical 投影 + round-trip 门"。

## 二、正确性欠账——**在做新内容之前先清零**

| 欠账 | 现状 | 处置 |
|---|---|---|
| **#43 商贩自证** | ✅**运行时修复已合入 trunk**（`a3b2e0f`→`53213f9`→收据 `3b639d9`，编号 112）：采集侧滤掉收款商贩、观察侧 `wn_other` 只数商贩以外目击者。⚠️**遗留抗回归缺口（Codex §六.1，已实测属实）**：观察侧只排 vendor（`witness!=v_id`）**没排 buyer**；census 只有 `vendoronly`/`keepone`、缺 `buyeronly`/`partiesonly` 负控；docs/112 §九.1"交易双方之外"这句**过强**（代码只排一端） | **AG2 棒在跑**：观察侧改成排除 `actor`+`target` 双端点、补两条 `hard=[43]` 负控、订正 docs/112。自然轨迹本就不含双方 ⇒ 预期零金标（须三锚证）。零售豁免线只量不收紧（改判据要用户拍板） |
| **被拒行为叙述成成功** | AA2 实测 3565 条引用里 **976 条（27.4%）**把 rejected event 写成已发生；真机 docs/111 又肉眼看到一次。⚠️ **AD2 设计（编号 116）把它重新框定了**：`accepted` 字段【已在】，社交路已正确区分被拒，屏幕真出错的是表现层 `Main._event_prose` 对社交类型【不读 accepted】——**是"读侧漏字段"，不是"缺 schema"** | **分三档（AD2 编号 116）**：✅**档0 已落地（AE1 编号 118）**：_event_prose 十类社交加 if ok else，实测被拒讲成成功 496→0、零金标、带回归门（已接进 ci.sh 第5步）；档1 加 `effect_applied`/`rejection_reason`【不折金标】=零金标（用户拍 schema）；档2 经济族失败可观测=移金标走 R12（用户拍板）。原提的"四字段统一模型"被 AD2 证明捆错了——修 27.4% 不需要它 |
| ~~**fixture/scale 门可能 fail-open**~~ ✅**已收（AE2 编号 119）** | 普查约18个量具：真 fail-open【集中在1个】(烘锚流水线)，其余早已 fail-closed、ci.sh 自身干净 | 已堵+负对照：子进程非零立即失败、iso 内容寻址到 HEAD:game、bake 绑 tree_sha 拒空 commit；顺带重烘过期 ledger |
| **AC2 `vanished` 只 warning** | 删一个具名病例 + 别处强化 ⇒ aggregate 不降而过门 | 具名槽消失应**直接红**；合法删除走**显式 rebaseline**（照抄 R12 的 rebake_history 文化） |
| **半宏观生产** | 池按人口扩容，但产出触发仍绑少数具名工人（`_produce_for` 守卫三段合取 `job空∨动作不符∨不在班` ⇒ 产出是**一次具名 NPC 的离散事件**；克隆 spawn 只发 `{id,persona,spawn,home}` 不入岗位表 ⇒ `_job_of` 返 `{}` ⇒ 恒被守卫挡下，岗位恒 9）。⚠️**更正（AG1 编号 124 + Codex §三.12，已实测）**："具名工人→左尾"**只是相关**——源码 `Invariants.gd:755` 自己写的是 **Spearman ρ=0.618**（非因果）；不能当结论 | ✅**AG1 设计已落地（编号 124）**：现状盘点(给行号) + 三路代价 + **证伪优先的干预设计**。**推荐路 (c) 镇级 `IndustryState`（唯一真正解耦到达的连续率、subsume 池不撞双重计数），但以证伪闸为立项前置**：NULL/T1(产能匹配去方差)/T2(产能匹配留方差安慰剂) 三臂 ×≥48 seed，连续余量判左尾（T1 右移须 > T2 且 > 零假设臂 `obj_dist_penalty 0.400→0.401`），阳才建模、阴则"到达非根因"照实写。社会痕迹靠"只改 RATE、ATTRIBUTION 留在班具名持有人"保住（produce/pay 的 actor+witnesses+信念 subject 逐字段照旧）。⚠️路 (a)(b) 会撞池双重计数 + 逼 `_holder_of_title` 复数化(打中 #41 反向臂)，非干净三选一。**实现待用户 §0.8 拍板** |

## 三、功能轨道——**可并行，彼此不冲突**（用户点名的那些）

这些是"好玩"的一半，**多数与架构脊柱正交**，可以在 §一/§二推进的同时并行，但**owns 必须错开**避免 branch conflict：

- **叙事 / storylets**（`game/scripts/narrative/**` + `game/narrative_lab/**`）：已有一条真实子系统在 `codex/narrative`。下一步是**并入 trunk**（先 reconcile docs 冲突），然后在其上做 storylets（预置的多幕小剧本）。
- **美术 / visual**（`WorldView.gd` + `game/assets/**`）：室内分色（R2）、家具语义（S3）、树丛（V3）、HUD（T3）已落 trunk；✅**AF2（编号 122）落了季节视觉**——实测夏↔春本来只 ΔE00 2.71（卡 JND、眼验糊成一块），已拉到 ΔE00≈7，零金标（只动夏季帧、CI 春帧逐字节不变）；并更正了一处过期注释（P_NIGHT 从来不是夜间暗面罩，夜色是 Main._daylight 乘子+加色光）。⚠️**遗留**：四季可分门 `assert_season.py` 写好了（改前红/改后绿）但**未接线**（需 visual_gate.sh 多拍 8 张四季昼夜帧，非平凡）⇒ 跟进项。**但全部只在桌面验过**——真机待当前 HEAD 构建（§四）。下一块空地：**室外建筑立面、天气视觉、其余三季夜间光照**。
- **NPC / 社会产出**：手艺痕迹（V1/Z2 四门）、商贩消费侧痕迹（AA3）已落。下一步是**把社会产出接到叙事**（手艺弧、买卖弧进 storylet），以及 §二那个事件结果模型让"尝试/被拒/成功"在 NPC 记忆与故事里区分。
- **map / interior（⬆ 现在的最高产品价值轨——Codex §三.7/§四.P2B 把它抬到 wiki 之上）**：⚠️**AG3 设计（编号 126）把这一轨的框架整个证伪了**：纵切六段（外立面 `WorldView:1014-1050` / 室内布局 `:1310-1359` / 多楼层 portal `spaces.json`+`SpaceGraph:71-83` / 拖拽探查 `ProbeController:245-292` / 返回世界坐标 `go_home:2456` / 视觉回归 `SpaceShot`+`space_roundtrip.sh`）**在 trunk 全部已跑**，**cafe（阿丽的咖啡馆，commercial [37,13,9,7]，1F 公共区+2F 阿丽居所）就是已精修的两层样板**（同 AF2 季节：H1/S3"有 X≠X 做好了"的反向发作，已复核属实）。⇒ 这一轨的真活是**收口+立证+补门+纠腐烂**，不是绿地重建。**三处已量到的缺口（收口目标）**：① `_portal_click`（`Main:2439-2467`）**缺 `queue_redraw`** ⇒ 暂停点门世界层不刷新（疑似真 bug，须 chain-dump 复现，非当场断言）；② **cafe 2F 从没被任何门看过**（`visual_gate.sh:161` 写死 `--probe-floor 1f`）；③ `spaces.json:35` cafe `_note` 还写"Tier-A：居民不进、digest 逐字节不变"——**与实况自相矛盾**（已复核 aria `spatial_address={cafe,2f}` 真住那，Sim `:896`/`:1618` journey 跨平面）⇒ **这是又一处数据注释腐烂**。⚠️改 `_note`/`spaces.json` 会动 `game/data` tree sha、可能牵动 provenance 锚 ⇒ 走小心的收口棒、别当零成本。**该轨不碰社会决策 schema** ⇒ 能与 §一/§二 波并行。
- **wiki（⬇ 延后）**：**镇民百科**（NPC 职业/关系/信念/大事记，从 `event_log`+`beliefs` 生成的只读投影，不进金标）。AD1 已落地过基座（town_wiki/v1）。⚠️ Codex §三.7：wiki 冲突少但**不是当前最高产品价值**——选它是在优化"容易绿"而非产品目标。**延到事件结果 schema 与 state projection 稳定之后**再做增强。

⚠️ **并行纪律**：每根棒的 `owns` 必须是**文件级不相交**的（本 session 反复验证有效）；docs 编号提前占；`README.md`/`docs/05`/`docs/README.md` 是**高冲突面**，同一时刻最多一根棒碰。

## 四、交付与运营——**把分散证据收敛成一个候选**

Codex Phase 0，我复核认同并补一条实测：

1. **单一集成候选**：`integration/batons` 就是它。叙事、AC1/AC2 wip 各自走**可审查的分支/PR**并入，不停在工作树。
2. **exact-head CI**：⚠️ **GHA 超时 15 分钟，而本地全量 CI ~17-26 分钟**⇒ PR #5 每次都在 `story_test` 处被平台取消（Codex 实测两次 run 都 `cancelled@15m`，唯一红因是预算不是断言）。
   ⚠️**更正拆分策略（Codex §三.4）**：**别把视觉/场景/跨进程锚降级到 non-required nightly**——耗时构成显示问题是**串行化**不是覆盖过多（最慢 `story_test`≈491s，其余大门各 2-4 分钟）。正确做法：
   - **短期**：把总 `timeout-minutes` 从 15 提到 **30-35**，先取得 current-merge-tree 的一次全跑基线（✅ 本会话已把 `.github/workflows/ci.yml` 的 timeout 提到 35，作为解锁"候选 PR 拿到 exact-head 收据"的最小改动）；
   - **正式**：拆成**全部 required 的并行 jobs**（static/provenance · core-sim · deterministic-backends · scenes · rendered/device），每 job **独立 clean checkout 不共享可变工作目录**，由**同一 phase manifest** 驱动本地全量与 GHA matrix（避免维护两份门列表）。扩展 seed 网格才留给 nightly。
   ⚠️**收据口径（Codex §二/§五）**：`pull_request` 事件下 checkout 默认是 **synthetic merge**（head 合入 base），不是 head 自身；且 base 在 checkout 后还会前进。收据必须**同时记 `head_sha`/`base_sha`/`checkout_sha`**，并保留 `head-static`（显式检出 PR head）与 `merge-gates`（synthetic merge）两个口径，二者都不得冒称对方。
3. **每份收据绑定**：repo + commit/tree + 数据版本 + **Godot 下载校验和 / Pillow / Python / FFmpeg / runner 固定版本** + 完整命令 + 进程 exit code。（本 session 的收据大多绑了 commit，但**没绑工具链版本**——这是真实缺口；且 `3b639d9` 那份因加了 `.txt` 使 tree=2102 而运行对象是父树 2101，准确名是"`53213f9` post-merge code-tree 本地全量输出"，不是字面 exact-head。）
4. **真机门（当前 HEAD）**：⚠️**更正（Codex §三.9，已实测）**：`competent-noether` worktree **没有** `build/out/*.apk`；历史 APK 只在主 checkout 的 ignored `build/out`（07-30），**只证明导出管线曾跑通、不是任何 branch 或当前 HEAD 的 commit-bound 构建**。⇒ 要从**唯一候选 HEAD** 实际 export/install APK，记 **APK SHA256 + versionCode + 内嵌 git SHA**，再逐条复验 docs/111 的触摸/暂停/HUD/音频；旧包截图不进当前 release 门。
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
- **可比性：`game/scripts/`+`game/data/` 逐字节相同是【必要】不是【充分】**（Y1 给了必要条件；⚠️ Codex §三.5 更正它过强）——Godot 版本 / addons / scenes / `game/bench`·gate 代码 / 命令行 / 环境都能改变结果或改变量具。判可比要把这些一并写进 provenance，不能只看那两个目录的 `git diff`。
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

## 八、下一步（Wave AG 在飞行；本文随其落地推进）

**已落地（本波 AG）**：
- ✅**AG1（编号 124）**：半宏观生产设计已合入 trunk。四处载重坐标经协调者复核逐条属实（`_produce_for` 守卫、克隆不入岗位、ρ=0.618、N=60 无门），与 Codex §三.12 独立收敛。**推荐路 (c) 但以证伪闸为前置；实现待用户 §0.8。**
- ✅**AG3（编号 126）**：town-completeness 纵切设计已合入 trunk。四处载重坐标经复核逐条属实（cafe 两层样板已跑、aria 真住 cafe/2f、`_portal_click` 缺 `queue_redraw`、cafe 2F 无门）。**框架被证伪**：纵切已存在，真活是收口三缺口（见 §三 map/interior 行）。R1 边界立准：agent space/floor=金标 Tier-B、Probe active_space/floor=view-only。
- ✅**协调者本人**：`.github/workflows/ci.yml` timeout 15→35（解锁候选 PR 的 exact-head 收据）；本文吸收 Codex 2026-08-06 两轮更正。

**正在跑（本波 AG）**：
- **AG2（编号 125 + 改 `game/bench` + 订正 112）**：#43 观察侧买家防线——排除 actor+target 双端点、补 `buyeronly`/`partiesonly` 负控。Phase-1 抗回归。

**AG 落地后的候选队列（按 Codex 更新后的顺序）**：
1. **P0 收敛**：给 `integration/batons` 配 required PR/check + 冻结候选 SHA；把 CI 拆成并行 required jobs（§四·2 的"正式"方案）。
2. **Phase 1 续**：AC2 `vanished` 红门 + `1/19` 负控 + docs/110@wip/ac2-story-ratchet + 全量 CI（未验证 wip → 收口）；事件结果 schema 档1/档2（用户拍 schema）。
3. **Phase 2 双先决**：state_projection（从 save codec 抽 canonical oracle，§一）**并行** KnowledgeState 三臂证伪（单镇/抽象域，§一更正）——两者都待用户 §0.8 拍板。
4. **功能并行**：AG3 纵切转实现波（若用户认同设计）；`codex/narrative` 只读 reconcile 棒（语义面，不合）。
