# 113 · 宏观路线图——**架构与功能层面，不拘小节**

> 维护者：主集成会话（worktree `main-integration`，分支 `integration/batons`）。
> 本文是**活文档**：只写架构/功能层面的大局与相位，不列具体门。门与实测在各波回执里。
> 前置：外部评审（Codex，2026-08-02 与 2026-08-06 两轮）、docs/62（GPT-5 Pro 多镇裁决）、docs/41 合同。
> **数字与分支状态实测于 2026-08-06；它们会随代码前进而旧——权威永远是 `git` 与 CI，不是本文。**

## ★★ 2026-08-07 用户扩展愿景——从"社交 sim 打磨"扩到"星露谷式活镇：视觉大改 + 物流/产业经济"

用户给了 5 件事（在 3→2→1[storylet/选角深度/默认镇规模] 之外的**扩展愿景**）。整成三条并行车道 + 现有社交/叙事车道：

- **车道 V（视觉大改 · item①）**：town map polish / total overhaul——terrain、building skin/appearances，**类星露谷**；工作流=实机图片 reference + **chrome session GPT img-gen 出草图/原型** → 一份 **reference 素材集** + 丰富 building 种类。✅**红线 R4 已由用户 2026-08-07 明示 waive**（"ignore red line R4"）：生成图**可**当出货资产、不再强制自绘/CC0、图二进制可入 git。实务注记（非阻塞）：生成图仍须适配像素分辨率/风格（通常作 game sprite 的底稿而非原样塞入）、二进制入 git 会涨库。**✅ 进度（docs/146）**：reference 素材集已起 2 张——① 11 栋建筑参考表（含新经济建筑车站/码头/仓库/磨坊/集市）② 7 类地砖参考表（草地/土路/石铺/农田/水岸/沙/木栈道，衔接 AP1/AP2 石街）。待续：building 变体/季节皮、经济建筑内部、props。**下一步**：据参考把某栋 building 皮或某片 terrain 重铺进 `WorldView.gd`（纯 View 零金标）。
- **车道 E（经济/物流 · item②③④）**：运输(railway/port/bus)→外部供给(**设无限**)→**多元产业**(goods flow)→居民 consume/produce/create→**自给自足→进出口→最终 self-contain**。**最大新子系统、移金标**（新 sim 机制改 digest/chain，用户已放行 docs/41 §3 重烘金标锚）。**须先设计再实现**——✅**经济设计 docs/144 已出**（核心纠偏：经济基础设施 town_stock/#38/produce链/consume/K1池 已成熟，车道 E=给已有账本接外部边界+加厚产业链，reuse-first）。✅**E1（编号147）已落地**——一条 import lane（柴薪确定性到港进镇库，off-gate，不碰钱#34）；移金标已重烘三锚（golden+modelpath+ledger）；协调者独立复核 off-gate=pre-E1 逐字节、#38/#44 双负对照、留出 13-30 柴薪↑/屋瓦↑=self-contain P1 且#40 未灌绿；committed CI PASS。**E3 磨坊链（AS2）试做未落地**：AS2 设计了小麦(农户)→面粉(磨坊)→口粮 三层链（`_e3_why` 论证充分），但**把核心口粮 gated 在 面粉 上=有 starve 风险**；AS2 反复卡在自身验证 run 上、口粮满足率没垮的证据只在其 context 未落盘、没重烘没提交。⇒ **协调者不擅自 land 这个重构核心食物的移金标片**（风险+未证+2am），设计已存档待用。**再approach 走更安全的 additive**：面粉→**糕点(新食/treat，不 gate 口粮)**，或让用户拍板要不要加深食物链。经济车道稳在 E1。⚠️**E2（export 收钱，钱跨边界）撞硬#34 守恒，须 external_coin 方案 + docs/41 §0.8 外审后做**（docs/144 §四.1）。E1 实测纠 docs/144 两处：port_dock 只声明不落图（落图撞 WorldView spriteless push_error）、modelpath 是第三锚（漏它 4e 红）。
- **车道 N/S（叙事+社交 · 3→2→1 + item⑤）**：storylet/叙事内容（`goals.json` 零金标先做）→选角行为深度（移金标）→默认镇规模（与车道 E 的"活镇"呼应：大镇需经济支撑）。item⑤ narrative 分支=stale 只读 compositor，已折进叙事 scoping 当参考。**✅ 进度**：叙事 scoping docs/143；**AR1（编号 145）已落地**——给 grudge/pact/craft 弧加「银钱往来」traded 幕（零金标，story_test+S0 金标 12/12 双证，committed CI PASS）。✅**AR2（编号 150）L3-b 已落地**：编年史散文多样化(单模板→逐 event type 生动措辞、被拒叙述"被拒",零金标 S0 12/12 含链+event_prose_test PASS)。**下一片**：L3-c（compositor 先并层,独立轨,docs/127 R-1）或 L3-d（移金标:解锁到场/mediate/gossip 褒贬,耦合选角行为深度,须重烘）。

**并行/排序**：V 与 E 与 N/S 三车道**文件面基本不相交**（V=WorldView/assets、E=新经济 data+Sim 机制、N/S=goals/Story/personas）⇒ 可并行推。**E 是重头且移金标**⇒ 设计提案先出、我(+用户)审过再增量实现，别盲上。**当前在跑**：叙事面 scoping、经济设计 scoping（两个只读）。**互联**：运输/产业/消费(E) + 大镇(3-2-1的1) + 更多 building 种类(V) + 经济事件成 storylet(N) 互相加强，是一个"活的星露谷式小镇"整体。

---

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
1. **trunk 是候选、但"清晰"只是约定不是保护**（Codex §三.1 更正）：`integration/batons` 没有 branch protection，PR 运行期间 base 还会前进 ⇒ 真正的"单一候选"要**冻结候选 SHA + required checks + 合并策略**，不是靠命名。**叙事是一条真实的平行子系统**，尚未并入——⚠️**更正（Codex §三.8 + AH1 编号 127，均已实测）**：以共同基点 `dae2fbe` 算，两侧文件**交集为 0**、**没有文本 merge conflict**。且 AH1 blob 哈希实测再纠一层：`docs/README.md`/`docs/05` **trunk 逐字节没碰**（两文件 trunk==merge-base），**只有 narrative 改了** ⇒ 是**单向漂移不是双向冲突**（trunk 已把路线图挪到 docs/113、冻结 docs/05）。⚠️ 还纠了两处规模高估：narrative 8193 行里**真生产代码只 5 个 .gd/1460 行**（其余是测试/fixture/评审媒体），**可执行叙事引擎(reducer/ledger/replay S01–S12)根本不在 codex/narrative，在外部 lab 仓 `living-town-narrative-lab`**；且**叙事今天不消费任何 Sim schema**（5 组件只吃自有合成态，全标 `NOT_SIM`/`production_gate:false`）。
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
> 2460 tick 从不浮现）⇒ **state_projection 不只是多镇的门票，它的第一个消费者是【今天的存档正确性门】。**
> ⚠️**外审 21:00 更正措辞**：AF1 证的是"**现有验证 oracle 会漏掉字段突变**"（手删 belief 后 digest/chain 仍同），**不是**"自然 round-trip 真的丢了 belief"。准确说法="**存档正确性门有盲区**"，非"已观测到产品数据丢失"。风险仍真实高优；实现从现有反射式 save codec 抽单一 oracle。
> AF1 推荐**路 (b) 并行新增 `state_projection`**（零金标，新函数不是 S0 对比量）。⚠️ 这仍是 §0.8 设计，实现待用户拍板。
>
> ⚠️**再更正（Codex §三.11，实现波要吸收）**：仓库**并非完全没有权威快照**——`Sim.save_game` 已有**反射式全量 snapshot/schema + load 恢复**。
> 真正缺的是从**该 codec 抽取**出的 canonical / versioned / hashable 等价性 oracle + 能咬住遗漏字段的 mutation/round-trip 门。
> ⇒ 实现时**优先"从现有 save codec 抽取单一 oracle"，而不是另造第二套 projection**（否则制造第二个 source of truth）；
> "增量子摘要"在未审计所有 mutation path 前是**过早承诺**。这把 AF1 的路 (b) 从"新写一套"收紧成"给 save codec 加 canonical 投影 + round-trip 门"。

## 二、正确性欠账——**在做新内容之前先清零**

| 欠账 | 现状 | 处置 |
|---|---|---|
| **#43 商贩自证** | ✅**运行时修复 + 抗回归缺口都已收（编号 112 + 125）**：采集侧滤掉收款商贩（`a3b2e0f`→`53213f9`）；观察侧 `wn_other` 从"只排 vendor"收紧成**排交易双方**（`743ebfa`，Codex §六.1） | ✅**AG2 已落地（编号 125）**：`ws43 != v_id AND != actor`（买家=transfer from_id）、补 `buyeronly`/`partiesonly` 两负控、订正 docs/112 §九.1。协调者独立复跑 census（seeds1-6）：natural 6/6 绿、两负控 6/6 红[43]、三臂 digest 逐位相同=零金标；全量 CI 895s PASS。未重烘锚（结构不动金标）。零售豁免线只量不收紧（改判据要用户拍板） |
| **被拒行为叙述成成功** | AA2 实测 3565 条引用里 **976 条（27.4%）**把 rejected event 写成已发生；真机 docs/111 又肉眼看到一次。⚠️ **AD2 设计（编号 116）把它重新框定了**：`accepted` 字段【已在】，社交路已正确区分被拒，屏幕真出错的是表现层 `Main._event_prose` 对社交类型【不读 accepted】——**是"读侧漏字段"，不是"缺 schema"** | **分三档（AD2 编号 116）**：✅**档0 已落地（AE1 编号 118）**：_event_prose 十类社交加 if ok else，实测被拒讲成成功 496→0、零金标、带回归门（已接进 ci.sh 第5步）；档1 加 `effect_applied`/`rejection_reason`【不折金标】=零金标（用户拍 schema）；档2 经济族失败可观测=移金标走 R12（用户拍板）。原提的"四字段统一模型"被 AD2 证明捆错了——修 27.4% 不需要它 |
| **fixture/scale 门 fail-open** 🔴**P0 重开（外审 2026-08-06 21:00 隔离复现，我"已收"标错了）** | AE2（编号119）堵了一部分，但 **`gate_fixture_audit.py --from OLD --bake-ledger` 不带 `--run` ⇒ `tree_sha=None` ⇒ 树比较被跳过（只在 `tree_sha is not None` 才跑），却用 `tree_sha or cur_tree` 盖章 ⇒ 旧/伪输出被盖上当前 HEAD**；且 consumer `gate_complement_guard.py` **只打印 metadata、不比当前依赖树**（入库 ledger 还写 `baked_game_tree=6c13be2` 而 HEAD:game=a176d68，守卫照返 0）。self-test 没覆盖这条路 | **按 Codex Phase 0**：禁 `--from`+`--bake-ledger` 同用；每 run 唯一目录+原子输出+run-id manifest；严格验 seed/invariant/live 全集拒 duplicate；consumer 比依赖树 hash 不匹配即红；再从 clean 重烘。⚠️**用户另一 session 在跑"re-bake stale ledger"——那修的是数据(旧锚)、非工具 fail-open；两者别撞** |
| **AC2 `vanished` 只 warning** | 删一个具名病例 + 别处强化 ⇒ aggregate 不降而过门 | 具名槽消失应**直接红**；合法删除走**显式 rebaseline**（照抄 R12 的 rebake_history 文化） |
| **半宏观生产** | 池按人口扩容，但产出触发仍绑少数具名工人（`_produce_for` 守卫三段合取 `job空∨动作不符∨不在班` ⇒ 产出是**一次具名 NPC 的离散事件**；克隆 spawn 只发 `{id,persona,spawn,home}` 不入岗位表 ⇒ `_job_of` 返 `{}` ⇒ 恒被守卫挡下，岗位恒 9）。⚠️**更正（AG1 编号 124 + Codex §三.12，已实测）**："具名工人→左尾"**只是相关**——源码 `Invariants.gd:755` 自己写的是 **Spearman ρ=0.618**（非因果）；不能当结论 | ✅**AG1 设计已落地（编号 124）**：现状盘点(给行号) + 三路代价 + **证伪优先的干预设计**。**推荐路 (c) 镇级 `IndustryState`（唯一真正解耦到达的连续率、subsume 池不撞双重计数），但以证伪闸为立项前置**：NULL/T1(产能匹配去方差)/T2(产能匹配留方差安慰剂) 三臂 ×≥48 seed，连续余量判左尾（T1 右移须 > T2 且 > 零假设臂 `obj_dist_penalty 0.400→0.401`），阳才建模、阴则"到达非根因"照实写。社会痕迹靠"只改 RATE、ATTRIBUTION 留在班具名持有人"保住（produce/pay 的 actor+witnesses+信念 subject 逐字段照旧）。⚠️路 (a)(b) 会撞池双重计数 + 逼 `_holder_of_title` 复数化(打中 #41 反向臂)，非干净三选一。<br>🔴**对抗评审证伪了这条推荐里最承重的一句（已复核源码，用户决策前必看）**：**"只改 RATE 就能保住社会痕迹" 是【假】的**。produce 的 witnesses = `_nearby_agents(worker)` 的**同区物理共在**（`Sim.gd:3891` 只收 `o.area==ag.area`），而这份共在**正是路(c)要解耦的到达过程产生的**（工人走到工位→完成才发 produce，`:1535`）。⇒ 两难：**要保 witnesses 就得把发货门在物理在场上 ⇒ 到达没解耦 ⇒ 左尾没修 ⇒ 路(c)白做**；**要解耦就在累加器时钟上发货 ⇒ `_nearby_agents(holder)` 抓到没人/错人 ⇒ #41(产出必须被看见,`Invariants.gd` 反红"产出N次但一次都没被看见")红、或"看见他在[他家]干活"语义为假**。AA3-FIX 已证在班≠在场(商贩 19-24%)、只能把 #43 锚移【off 持有人】到买家——而"谁做的"produce **没有这种可移的锚**。⇒ **路(c) 多一道硬子问题：解耦到达后 produce-witnesses/CR-信念怎么保**；证伪闸也得覆盖它。**实现待用户 §0.8 拍板** |

## 三、功能轨道——**可并行，彼此不冲突**（用户点名的那些）

这些是"好玩"的一半，**多数与架构脊柱正交**，可以在 §一/§二推进的同时并行，但**owns 必须错开**避免 branch conflict：

- **叙事 / storylets**（`game/scripts/narrative/**` + `game/narrative_lab/**`）：真实子系统在 `codex/narrative`。**AH1（编号 127）已给出分层 reconcile 方案**（实测 R1 佐证）：
  - **先并层（可开只读 PR、零金标）**：5 个只读视图 .gd（`NarrativeGlyphs`/`NarrativeViewContract`/`RolePOVCard`/`WebMazeGraph`/`S16Compositor`，全 fail-closed、grep 零 `randi/randf/Sim./save_game`、只吃自有合成态）+ 测试场景 + fixtures + docs 语义 reconcile。**触碰的既有 sim/金标文件=0**。⚠️ 但**当前零 CI 接线**（60-path 不含 `tools/`）⇒ 先并**必须先给 ci.sh 加一道 headless 叙事门**，否则并进去无人守。🔴**对抗评审修正（已复核）**：这道 headless 门**只能是 logic-only**（结构/隐私）——AH1 倚重的**像素牙**（glyph 塌缩负控、hidden-prose 不进像素）**在 `--headless` 下 dummy display 让 `get_texture().get_image()` 空 ⇒ 环境性变红**，跟 `visual_gate.sh` 在 GHA 上 SKIP(exit 77) 同因。⇒ 先并层的像素级验证得靠**非-headless 的 Xvfb runner**，headless CI 守不住它，**AH1 低估了这一步**。
  - **后置层（gated）**：S14 真 actor 只读投影、**S18 integration RFC（触发 §0.8 外审+用户拍板）**、唯一 Sim 写侧棒（走完整 R12）、storylets 内容。注意 AH1 校正：**S18 gate 的是写侧；只读组件的停止线其实是 S12，不 gated 在 S18**。
  - **schema 冻结面**：Tier-1（自有合成态，先并层消费）vs Tier-2（Sim 真面：事件结果 accepted/effect_applied、beliefs/attitudes、journey/portal、save codec/digest——**trunk 正在改这些**，是后置层真正等的）。
  - ⚠️**两个决策点留用户**：① 是否把先并层并入 trunk（AH1 判零风险但需先加 CI 门）；② 14 个评审媒体二进制(~1.45MB,无 LFS)进不进 trunk（AH1 建议默认不进、只留 manifest+contact sheet）。
- **美术 / visual**（`WorldView.gd` + `game/assets/**`）：室内分色（R2）、家具语义（S3）、树丛（V3）、HUD（T3）已落 trunk；✅**AF2（编号 122）落了季节视觉**——实测夏↔春本来只 ΔE00 2.71（卡 JND、眼验糊成一块），已拉到 ΔE00≈7，零金标（只动夏季帧、CI 春帧逐字节不变）；并更正了一处过期注释（P_NIGHT 从来不是夜间暗面罩，夜色是 Main._daylight 乘子+加色光）。⚠️**遗留**：四季可分门 `assert_season.py` 写好了（改前红/改后绿）但**未接线**（需 visual_gate.sh 多拍 8 张四季昼夜帧，非平凡）⇒ 跟进项。**但全部只在桌面验过**——真机待当前 HEAD 构建（§四）。✅**AI1（编号 129）落地天气/季节降水视觉**：新增 `_draw_snow()`（冬季两层视差飘雪，密度随天气）+ 强化 `_draw_rain()`（密度 36→52、两档景深、地面涟漪），确定性靠 `_hash`+`tick_no` 无 RNG。协调者独立复核：scope 只 WorldView（零 Sim/data/锚），digest 三证据（A/B + 金标 12/12 + 留出 seed 逐位同 + CI 帧 0px），**自跑全量 CI `=== CI PASS ✅ ===` 907s（S0 金标 12/12、DetGate 金标 ✅）**，眼验冬雪真帧=真程序化美术。⚠️**遗留（外审 21:00 更正我的判断）**：AI1 的 `assert_precip.py` + AF2 的 `assert_season.py` **都未接线，且"被 digest+既有视觉门覆盖"技术上不成立**——simulation digest 不含像素，现役视觉基准刻意拍**春季帧**且 AI1 又刻意保持该帧 0px ⇒ 季节/降水视觉**没有任何 CI 牙**。⇒ **必须接**（Codex Phase 0.5：season+precip 合成 Xvfb 视觉 matrix 进 required CI，runner 须查每个 Godot 子进程 rc 非只看图存在）。另：AI1 "冬季晴/阴/雨都下雪只改密度"是**产品语义选择**，应由用户拍板（不是自然天气规则）。<br>⚠️**外审 21:00 定性我近两波偏航**：AI1 天气 + AJ1 wiki 都是"继续写 wiki/天气而不碰 map/building/interior"=**偏离用户产品目标**。Codex：**下一根主功能棒必须是 AG3 可交付纵切的【实现】（cafe–plaza–shop–work 街区），不是第三份设计/wiki/天气**。
- **NPC / 社会产出**：手艺痕迹（V1/Z2 四门）、商贩消费侧痕迹（AA3）已落。下一步是**把社会产出接到叙事**（手艺弧、买卖弧进 storylet），以及 §二那个事件结果模型让"尝试/被拒/成功"在 NPC 记忆与故事里区分。
- **map / interior（⬆ 现在的最高产品价值轨——Codex §三.7/§四.P2B 把它抬到 wiki 之上）**：⚠️**AG3 设计（编号 126）把这一轨的框架整个证伪了**：纵切六段（外立面 `WorldView:1014-1050` / 室内布局 `:1310-1359` / 多楼层 portal `spaces.json`+`SpaceGraph:71-83` / 拖拽探查 `ProbeController:245-292` / 返回世界坐标 `go_home:2456` / 视觉回归 `SpaceShot`+`space_roundtrip.sh`）**在 trunk 全部已跑**，**cafe（阿丽的咖啡馆，commercial [37,13,9,7]，1F 公共区+2F 阿丽居所）就是已精修的两层样板**（同 AF2 季节：H1/S3"有 X≠X 做好了"的反向发作，已复核属实）。⇒ 这一轨的真活是**收口+立证+补门+纠腐烂**，不是绿地重建。**缺口（收口目标）**：~~① `_portal_click` 缺 `queue_redraw` ⇒ 暂停点门不刷新~~ ✅**AH2 查证=假警报（编号 128，不改代码）**：`_portal_click` 确实没 `queue_redraw`，但世界层照样刷新——由 `WorldView._process` 每帧窄键轮询兜底（`:2738-2753`，`_view_state_key` 含 `active_space/floor`；E5/E6 专为这个 bug 加的，`WorldView:601-605` 存着加之前的 `[PAUSEPORTAL] _draw() 0 次` 原始探针）。SceneTree 从不 paused（grep `get_tree().paused`=0）。**结构观察对一半、用户可见症状不成立**。② **cafe 2F 从没被任何门看过**（`visual_gate.sh:161` 写死 `--probe-floor 1f`）——真缺口，属 AG3 的 G1 多楼层门设计（编号 126），待实现波。③ `spaces.json:35` cafe `_note` 写"Tier-A：居民不进、digest 逐字节不变"——**与实况自相矛盾**（aria `spatial_address={cafe,2f}` 真住，Sim `:896`/`:1618` journey 跨平面）⇒ 数据注释腐烂。⚠️改 `_note`/`spaces.json` 会动 `game/data` tree sha、可能牵动 provenance 锚 ⇒ 走小心的收口棒。
  - ⚠️**新增·低置信观察（AH2 越界记录、未运行时证实，交 WorldView 属主判断）**：`WorldView:2753` 窄键命中只 `queue_redraw()`(self)、不像 tick 路 `_redraw_all()`(:631-635) 连 `_lights.queue_redraw()`。**理论上**夜间+暂停+进室内，`_lights`(夜灯层) 可能残留旧镇灯命令。**未证实是不是真缺陷**，别当 bug 追，先记着。**该轨不碰社会决策 schema** ⇒ 能与 §一/§二 波并行。
- **wiki（⬇ 延后）**：**镇民百科**（NPC 职业/关系/信念/大事记，从 `event_log`+`beliefs` 生成的只读投影，不进金标）。AD1 已落地过基座（town_wiki/v1）。⚠️ Codex §三.7：wiki 冲突少但**不是当前最高产品价值**——选它是在优化"容易绿"而非产品目标。**延到事件结果 schema 与 state projection 稳定之后**再做深度增强。⚠️但**架构轨全部 §0.8-gated 待用户拍板期间**，非门控功能轨里 visual 已成熟（AF2+AI1）、map/interior 是 gated 的最高价值轨 ⇒ ✅**AJ1（编号 130）落地镇级横切总览**——关系图谱(自包含 SVG,12 节点确定性圆布局,49 边友好23/敌对26) + 大事年表(88 条跨居民,每条可追溯 #id) + 派系/冲突概览(4 派+施压5目标+高怨气对)，**纯渲染器 `gen_town_wiki.py`(+548)从已有 town_wiki/v1 JSON 建、`wiki_dump.gd`/`town_wiki.json`/`game/` 一字节没碰=零金标 trivially**。协调者独立复核：scope 无 game/golden、眼验图谱渲染正确、**再跑可追溯 gate PASS(1961 大事记全可追溯 + 负对照注入 4 伪造项抓 4/4)**。这是"非门控可做的里挑非重复的"，不是"最高价值"（最高价值仍是 gated 的 §一/§二/map-interior）。

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
4. **真机门（当前 HEAD）—— ⏸️ PC-first defer（用户 2026-08-07，[[project-pc-first-defer-port]]）**：整门 defer 到桌面产品完成度达标后的移植波一次性做，**不再当每片的验收/退出条件**。已做的当前 HEAD cafe 真机基线（docs/128 §六，app 跑/触摸/存读档/cafe 室内+人流）留作【已知良好基线】，移植波在达标 HEAD 上重跑。下面是原始记录（历史）：⚠️**更正（Codex §三.9，已实测）**：`competent-noether` worktree **没有** `build/out/*.apk`；历史 APK 只在主 checkout 的 ignored `build/out`（07-30），**只证明导出管线曾跑通、不是任何 branch 或当前 HEAD 的 commit-bound 构建**。⇒ 要从**唯一候选 HEAD** 实际 export/install APK，记 **APK SHA256 + versionCode + 内嵌 git SHA**，再逐条复验 docs/111 的触摸/暂停/HUD/音频；旧包截图不进当前 release 门。**⇒ ✅ 已完成首个 current-HEAD 真机验证（docs/128，2026-08-06）**：用户重开无线调试后，走 **SDK-free 路**（临时 `use_gradle_build→false` 走预建模板 + `keytool` 自建 debug key，均未提交）构建成功（HEAD `9579294`，apk sha256 `f9748e5c…`）、装上 NX789J 实测通过——**app 跑起来、触摸可用（点详情→观察台）、音频 `mIsActive=true` 实播（强于 docs/111 仅 started）、AE1 被拒叙述修复真机活着（"对方没搭理/没接茬"）、4 游戏天社会动态正常**。⚠️遗留：出货门仍需**正式 gradle 构建**（装 `res://android/build/`+SDK，见 docs/128 §一）；音质/路由/并发 focus、其余触摸项未测（连接凭据时效）。docs/128 还**订正了 docs/111 触摸矩阵**（Codex 反证：触摸未测≠keyboard-only，8 个触摸等价入口实证）。
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
- ✅**AG2（编号 125）**：#43 观察侧买家防线已合入 trunk（`743ebfa`）——`wn_other` 排交易双方、补两负控。协调者独立复跑 census（natural 6/6 绿、buyeronly+partiesonly 6/6 红[43]、三臂 digest 逐位相同=零金标）+ 全量 CI 895s PASS。Phase-1 抗回归收口。
- ✅**协调者本人**：`.github/workflows/ci.yml` timeout 15→35（解锁候选 PR 的 exact-head 收据）；本文吸收 Codex 2026-08-06 两轮更正。

**⇒ Wave AG 全部落地**（AG1 半宏观设计 · AG2 #43 买家防线 · AG3 纵切设计 · CI 解锁 · 路线图吸收外审）。

**对抗评审轮（6 refuter × 3 设计结论，用户 §0.8 决策前的证伪，已把每条复核回源码）**：
- 🔴**AG1 推荐被证伪一处承重句**（已复核）："只改 RATE 保住社会痕迹"假——produce witnesses=物理共在、正是路(c)要解耦的到达产生的 ⇒ 解耦与保 witnesses 两难，路(c) 多一道硬子问题（详见 §二 半宏观行）。**推荐仍成立但风险画像变了，用户决策前必看。**
- 🟡**AG3 承重结论存活**（R1 边界 / 纵切已存在 / cafe·aria·_note 全被复核为真）；被证伪的 gap①(portal-redraw) **正是 AH2 已判的假警报**（本文已改）。附带发现：改 `spaces.json` **不动金标**（Inv.digest/chain/DetGate 都是行为态非静态配置哈希）——但仍会让 `gate_complement_ledger` 的 `baked_game_tree` 绑定变旧需重烘，故 §三 gap③"走小心收口棒"的口径不变（金标不动≠零成本）。
- 🟡**AH1 先并层零金标存活**（subtree-hash 顾虑文档已预答）；被证伪的是**"加 headless 叙事门"这一步被低估**——像素牙在 headless 下环境性变红，headless CI 只能 logic-only（详见 §三 叙事行）。
- **净判**：3 条推荐的**方向都存活**，但 AG1 和 AH1 各多一道之前没写清的硬约束，已折进 §二/§三。**这正是对抗评审的用处：在用户拍板前把承重句挑穿。**

### ⭐ 外审 2026-08-06 21:00 的 course-correction（覆盖下面旧队列，是当前权威顺序）

外审读了 AE1/AG2/AF2/AI1/AJ1 + 真机验证，裁决：**无仿真/RNG/金标回归**（那几笔代码干净、可留），但**产品偏航**（47 commit 里 34 是 docs/ci/chore、map/building/interior 零内容实现）。⇒ 明确顺序：

- ✅✅✅**P0 证据闭环短闸【全部收口】**（②③⑤①四条都已收 + worktree 审计）——外审 21:00 要的"假绿通道"堵完：视觉门有牙、#43 抗回归入 CI、AE2 真 fail-closed、ledger fresh 且 guard 强制。下面留详情：
- **P0（证据闭环短闸，非门控，现在做）**：✅**① 已收（AN1 编号 136，`c5883f2`）**：互补性锚工具真 fail-closed——禁 `--from`+`--bake-ledger` 后门（拒绝把旧输出盖成当前树）、consumer `gate_complement_guard` 加 `check_ledger_freshness`（`baked_game_tree` vs `HEAD:game` 不符即红+点名 stale+叫重烘）。协调者亲跑三负控：`--from` 后门→拒、synthetic stale→红 exit1、fresh→PASS；落地时全量 CI 跑绿（判决行=CI PASS/rc0）——⚠️该 run 的 stdout 未归档 `analysis/an1`，**精确墙钟秒数不作存证（审查 F4 纠：勿再引"1286s"）**。**⇒ 此后 guard 强制 fresh ledger：改 game/data 后必须重烘（正确纪律）**；✅**② 已收（AK1 编号 131，`62f21d0`）**：season+precip 视觉门接进 required CI（步6 加 8 季节+12 降水帧）+ 新 `vg_shoot.sh` 三判据硬化子进程 rc（关"图在盘但 rc≠0"fail-open）——本机全量 CI 真跑 SEASON PASS(昼8.06/夜4.30)、PRECIP PASS，双负对照证牙；✅**③ 已收（AL1 编号 132，`724fb8c`）**：`tools/aa3_regression_gate.sh` 接进 CI 步4g——natural 绿 / vendoronly·buyeronly·partiesonly 红[43]，任一不符即红（观察侧退回只排 vendor ⇒ buyeronly 红→绿 ⇒ 门红=牙）；判据看 census 的 hard_fails JSON、豁免线自证；只调既有 census 不改 game/、seed1×30天≈16s；协调者亲跑 4 例判决对 + 全量 CI 步4g PASS；④ 冻结候选 SHA + branch protection + 让 35min synthetic-merge workflow 真跑一次；✅**⑤ 已审计（无自动删除，遵 Codex）**：128 worktree——**115 是本 session 的 transient `agent-*`**（batons，产出已 cherry-pick 进 trunk，harness 对 unchanged 的会自清）；~13 具名。**dirty 的全是【具名/别 session/历史】worktree**（`competent-noether` 8、`compassionate-antonelli` 9、`brave-spence` 1、`objective-sinoussi` 2、`nlab-baseline` 1 + 主 checkout 的 session-start untracked 2）——**都不是我的、不动**。`git worktree prune` 跑过（0 stale）。建议：115 `agent-*` 可安全 `git worktree remove`（clean 的会删、dirty 的自拒），但留给用户/harness 自清，不自动批删。
- **Phase 1（下一根【主功能棒】= AG3 可交付纵切【实现】，不是第三份设计）**：cafe–plaza–shop–work 连续街区——`town→cafe1F→2F→1F→town` 的 **Probe 往返**（本 Phase 默认 omniscient research Probe，玩家穿门旅行另立知识/访问策略）、1F/2F 清晰用途/非模板 zoning、修腐烂 `_note`、加 2F 像素门 + portal round-trip 门 + Probe observer-independence 门。<br>⭐**方向（用户 2026-08-07）：PC-first——先把产品在桌面打磨到预期完成度，移植（Android）攒到最后一次性做，别双线分摊（见 [[project-pc-first-defer-port]]）**。⇒ **退出条件收窄成：观察者【桌面】走完整旅程**（`town→cafe1F→2F→1F→town`，已由 AM3 往返门机器守）；**Android 实测那半 defer**（已有的当前 HEAD cafe 真机基线留档，移植波在完成度达标 HEAD 上一次性重跑）。非"代码里有 portal"。<br>⭐**已启动（用户 2026-08-07 拍板"绕过卡住的 re-bake、协调者自己重烘"）**：✅**AM1（编号 133，`7f1ed4b`）第一片 cafe 室内分区打磨落地**——1F=咖啡馆身份（甜点柜/吧凳/菜单牌/迎宾地毯）、2F=阿丽私宅（衣柜/梳妆镜/床/照片墙），非模板 zoning；订正腐烂 `_note`（Tier-A→Tier-B）；加 cafe **2F 像素门**（非空+与1F可分+色数落差，负对照空2F→红=牙）。<br>🔴**AM1 纠正了我一处 scope 错**（已复核）：我说"纯装饰家具=零金标"**不全**——只覆盖 `_compile_interiors`(路①advertises→对象)，**漏了 `_build_interior_grids`(Sim.gd:3995) 路②**：家具格(slot∉{stairs,rug,window})进导航网挡格 ⇒ aria 住 2F 跨平面 journey，加挡格会改她的路 ⇒ **digest 不变但 chain 变→S0 金标红**。AM1 重构成"原格位置/walkable 不动、只换 slot 画法 + 新装饰只用 walkable(rug)/墙面(picture)"，实测**金标 12/12 含逐 tick 链逐字节不变**（协调者自跑 CI 复核）。**教训：`interiors.json` 家具几何进导航网；改室内内容须守【导航挡格集不变】才零金标。**<br>⚠️**complement ledger 重烘**：game/data 变了⇒ledger 更 stale。但 guard 当时是 fail-open（不比树，Codex P0.①；**后由 AN1 收口成 fail-closed**），stale 不破 CI ⇒ **重烘攒批**（做完几片内容一次性重烘）。✅**AM2（编号 134，`f27ba6e`）第二片 shop+work 室内身份落地**——杂货铺(货架/柜台/货箱/果篮)、工坊(工具/工作台/材料)各有辨识度；照 AM1 手法（挡格集 byte-identical=结构零金标），实测金标 12/12 含链 + INTSHELL(shop=commercial/work=workshop 可分)+FURNROLE 门 PASS。⇒ **cafe/shop/work 三栋室内身份已做**。**AM4（编号 138）在跑**：home/home2/library/wash 四栋室内身份（收尾"每栋有身份"，PC-first 桌面渲染验证，照 AM1/AM2 零金标挡格集手法）。✅**AM3（编号 135，`0548691`）cafe 全楼层往返门落地**——`town→cafe1F→(楼梯)2F→(楼梯)1F→(街门)town` 逐段断言落对 Floor（SpaceShot 加 `--rt-journey full`，纯 Probe view-only 零金标）+ 宿主侧核 meta 楼层双证；**往返 1F 帧逐像素=进店 1F（0/424692=0.000%）** ⇒ 旅程正确回程。双负对照红（目标层改错/2F=1F→红），probe_digest_test PASS(R1)，金标 12/12 含链。**⇒ cafe 纵切片完整**（1F/2F 内容 + 2F 像素门 + 全楼层往返门 = Codex Phase-1 退出条件"观察者走完整旅程"已机器门）。后续：outdoor plaza/street 街区内容、Android 实测。✅**ledger 攒批重烘已做（`1867e1a`）**：走正确 `--run` 路（非 Codex 标的 `--from` fail-open 后门）重烘到 `b19a8e6`，diff 只 _meta 树绑定 + rebake_history、**anchor 值零变化=独立证实 AM1/AM2/AM3 确零金标**。<br>✅ 注意（此段写于 AM3 落地时、AN1 之前，留档记录时序）：这里当时标"AE2 工具 fail-open 仍未修"——**后已由 AN1（P0.① 见上，`c5883f2`）收口**：`--from`+`--bake-ledger` 后门已禁、consumer 已比依赖树 fail-closed；外审 AE2 审计员 2026-08-07 独立复核**确认真 fail-closed、未找到第二条绕过路径**。⇒ AE2 待办**已闭**（审查 F4 纠：与上 P0.① 单一判决对齐，消除本 doc 内自相矛盾）。
- ✅**并行架构 lane 落地：state_projection_v1（AO1 编号 137，`2ddbe2f`+ledger 重烘 `54b1b89`）**——用户 2026-08-07 §0.8 拍板做。从 `Sim.save_game` blob 抽 canonical 投影（单一真相源、不另造第二套）+ 真咬门接进 `ci.sh` 4h：round-trip + 20 家族 A/B（digest SAME/chain SAME/proj DIFF）+ 全量扫（agent 35=agents[0] 键集·world 99，⚠️分母口径见下）+ **AF1 合成扰动（手工 erase 一条 belief）被投影抓住、Inv.digest 盲**——是门的**灵敏度自证**，非抓到真 load_game bug（审查 F8 纠措辞）。协调者自跑全量 CI：**金标 12/12 含链不变（零金标）**、新门 PASS、guard 在 fresh ledger 过；⚠️落地 run stdout 未归档（勿引"1377s"当存证，审查 F4）。<br>⚠️**审查 F1 收口（2026-08-07，`StateProjection.gd`/`state_projection_gate.gd`）**：backend/ext 原记 does_not_detect **是错的**——它俩是运行时注入的 Object 服务句柄，GDScript `null is Object==false` ⇒ headless 落 `backend:null` 进 blob、真机注入 Object 被 `save_game` 的 `v is Object` 跳键 ⇒ **键集随注入态漂移、投影跨机不等（违反红线#1）**。已在 `StateProjection.NONAUTH_STATE_KEYS` 把这两键**从投影 & 覆盖分母统一剥除**（单一真相源），world 分母 101→99；**新增门⑥【注入无关性】证 headless(键在/null)==真机(键不在) 投影同**（实跑 269495820==269495820），零金标（bench-only、不进 S0）。<br>⚠️**诚实边界（审查 F6/F7）**：agent 分母=`agents[0].keys()` 非全 agent 并集；world_count 耦合 save 落盘持久集（非独立权威枚举）——两条记为 v1 已知边界，**不谎称"全覆盖 0 洞"**。AO1 子棒卡死于 backend/ext 分类，协调者复核+收口+接线+写 docs/137。**边界（诚实）**：v1 只覆盖存读档【边界两点】的 save 权威面当前形；跨时窗（0–1784 盲窗/late/mid-recovery）、增量子摘要是 v2；KnowledgeState（多镇第二先决）另一条线未起。
- **明确暂停**（外审点名）：**wiki 增强、IndustryState、Narrative 合入、event schema 档1/2、更多天气扩张、多镇**。AC2 以后 fresh 小 PR 收口不抢 AG3。
- ⇒ **协调者本波动作**：先接 P0 里非冲突的一块（视觉门接线，game/data-free、避开 re-bake），并把 AG3 实现波planning 出来；AE2 工具修待用户 re-bake 收工再动（同区避撞）。

### ⭐ 内部对抗审查 2026-08-07（5 独立 critic + 综合，复刻外审视角；外部 Codex 不可达时的替代）

对最近一波（AN1/AO1/AM1-3 + 轨迹）跑了 5 面独立审计（零金标 / AE2 / state_projection / 漂移 / 证据膨胀）+ 综合。**判决：内容半是真进度（AM1/2/3 独立复核确零金标、on-goal），但 AN1/AO1 两波漂回纯基建/自证——尤其 AO1 为一个 PC-first 已 defer 的消费者（多镇）建 595 行门。** 已收口：

- ✅**F1（真 bug，已修+验）**：`state_projection` 的跨机等价被 `backend/ext` null-leak 破了——`null is Object==false` ⇒ headless 折 `backend:null`、真机注入 Object 被 save 跳键 ⇒ 同态两哈希（违反红线#1）。修：`StateProjection.NONAUTH_STATE_KEYS` 从投影&分母剥除（world 101→99）+ 新门⑥证注入无关性（`269495820==269495820`）。gate PASS。零金标（bench-only）。
- ✅**F4（我的记录在案失败模式，已收）**：多处"已收口/CI PASS"证据超出留档——docs/113 内 AE2 自相矛盾（已对齐单一判决）、"1286s/1596s/1377s" 无归档的精确秒数（已删/降级）、docs/134 "INTSHELL/FURNROLE 全过"但 log 只有采集行（已降级为结构论证 + 待整轮 CI 归档回填）、docs/133 引不存在的 `golden_*.log`（已改指真存在的 `digests_*.txt`）。**统一纪律：判决行以 2026-08-07 F1+AM4 整轮 CI 归档为准回填。** ✅**已回填**：`analysis/review-2026-08-07-ci/verdict.txt`（HEAD `1fcbfc8`/game `c244322`）= **`=== CI PASS ✅ ===`**——S0 12/12 含链、state_projection 4h PASS（world 99/洞0、⑥注入无关性绿）、INTSHELL 7栋4类 PASS、FURNROLE 6栋5类 PASS、CAFE2F/FLOOR ROUNDTRIP/SEASON/PRECIP PASS、complement guard 在 fresh ledger 过。docs/134/135/136 占位符已用此归档回填。**⚠️后续审查(2026-08-07 车道轮)发现 docs/138(AM4) 也犯同款**——引 4 个不存在的 `analysis/am4/{golden_*.log,visual_gate.log,ci.log}` + 假精度"1297s"；已一并纠：金标改指 `digests_*.txt`、CI/视觉判决改指 `analysis/review-2026-08-07-ci/`（AM4 树 c244322 的真归档）、删 1297s。⇒ F4 覆盖清单现含 133/134/135/136/**138**。**全 docs/ sweep（practice「修 recurring pattern 要扫全、别 whack-a-mole」）另发现更早波次的同款遗留债**（非近批引入）：docs/131 引不存在的 `analysis/ak1/ci_full.log`、docs/119 `<!-- CI_RESULT -->` + docs/132 `<!-- CI_VERDICT_PLACEHOLDER -->` 空占位、docs/113 本身早期条目的"895s/907s PASS"无归档精确秒数。**判定=已知历史债、暂不逐条重写**（大改历史回执属低杠杆、且易再触"非产品churn"偏航）——记此备将来一次性 hygiene 波清；新回执一律走 committed verdict.txt 纪律。docs/134 §四的 `golden_*.log` 经核**真存在**（am2 有该档）、非幻影，保留。
- ✅**F5/F6/F7/F8（措辞诚实化）**：backend/ext"实测确认"是空标签（已删）；`agents[0]` 分母非全 agent 并集、world_count 耦合 save 持久集（记 v1 边界，不谎称"0 洞全覆盖"）；AF1 是合成扰动的**灵敏度自证**非抓真 load bug（已改）。
- ❌**F2（审查旗舰）= 假阳性，已被源码复核驳回**（协调者 finalizer 核查，2026-08-07）：审查说"`WorldView` 只在 `space=='town'` 画 agent、进店空房"——**错**。`_draw_interior`（WorldView.gd:1443-1445，由 `_draw_interior_backdrop` 在 :1377 实调）**本就有一段室内住户层**：`for ag in Sim.agents: if ag.space==sid and ag.floor==fid: _draw_agent(ag)`；而 `_draw_agent`（:3267）用 `_rpos→_center=ag.pos*T`、**无 `_in_town` 内闸** ⇒ 室内居民按 floor-local 格真渲染。该功能是 `ae8cf4b`（"aria lives in the café — cross-plane life，#01 green"）早落的、**早于审查**。审查看的是**镇图 overlay** 的 `_in_town` 闸（派系环 :3162/盟约线 :3211/关系线 :3096——那些正确地不在镇图上画室内人），漏了 `_draw_interior` 自己的住户层。⇒ **不派 F2 实现棒（会加重复住户层）。** ✅**经验确认**：AM4 committed 渲染 `docs/media/am4_home_1f_after.png` **就有一个居民精灵站在住宅室内**（床边）——三条独立证据（源码路径 + `ae8cf4b` 出处 + 真渲染截图）坐实室内住户已渲染。**教训**：对抗审查的结论也要源码复核，不能 relay——它的旗舰建议正建立在一个假前提上（reviewer 看了镇图 overlay 的 `_in_town` 闸、漏了 `_draw_interior` 自己的住户层）。
- 🚦**F3 = 纪律（已内化）**：**冻结新造 bespoke per-slice 门 / oracle 扩张**，直到出现现役门抓不到的、玩家可达的产品 bug 才建门。切片验收=一次桌面眼验 + 现役视觉门。下一波投玩家可见的产品内容，不是新门。

**⇒ 下一批旗舰候选（本次 F1+AM4 landing push 后起）**：室内身份全做完（AM1-4 八栋）+ 室内住户已渲染（F2 驳回坐实）+ cafe 纵切完整（AM3）⇒ 最高杠杆玩家可见 = **outdoor「连续街区」内容**（cafe–plaza–shop–work 不是建筑孤岛，是连着的街）。⚠️这是**金标最险的一片**（全 60 居民每天在 outdoor 64×48 导航网上寻路，改错=大面积 chain 漂）。✅**只读金标面 scoping 已做（docs/139）**：outdoor 导航网=`f(map.json)` 纯函数（`_build_nav` Sim.gd:3975-3991，运行期零写 blocked——协调者已验）；两路移金标面（objects/worksites/`areas[*].rect`——含空区）vs 零金标面（`areas[*].type`/terrain·decor 绘制/wash，Sim 读不到）分清；安全 free cell 谓词直接复用 `_build_decor`(WorldView.gd:810-820)。**★第一片 ✅AP1（编号 140，`d37c5a0`+ledger `de66198`）已落地**：plaza + 门→plaza 现有 walkable 土路网**重铺石铺连街**（鹅卵石+路缘石+flagstone 广场）+ verge 落 84 件纯 View 街具（路灯/花坛/长椅/系缆柱，程序 draw 图元非 DECOR_POOL——AP1 实读纠：pool 项受 asset_gate 管、无灯凳贴图）。**零金标实证**：golden 12/12 含链逐字节不变、`golden_digests.json` sha256 零改动。权威 landing CI（committed 树+fresh ledger）= CI PASS（`analysis/ap1/ci_landed_verdict.txt`）。眼验：dirt→石街读感成立（`docs/media/ap1_{before,after}.png`；props 全镇 zoom 偏细，近看才显）。红旗全守（typed-layer 未碰/lod_verify PASS/未碰 weather-lifecycle/hash+tick/图尺寸不变）。<br>**⇒ ✅AP2（编号 141，`f11d689`+ledger `48bb381`）已落地**：plaza 做成【镇社交心脏】（同心石徽章 + well/board 重皮成村井/公告栏 + 座圈）+ 码头连街收尾（AP2 实读纠：AP1 已把 7 门全石街化、零残留土径；真孤岛只有无门的 dock，已 View-only 连缀）。零金标实证（golden 12/12 含链 + `golden_digests.json` sha256 零改动），权威 landing CI PASS（`analysis/ap2/ci_landed_verdict.txt`）。眼验：广场读成"大家聚的社交心脏"、居民环绕（`docs/media/ap2_plaza_after.png`）。
- ⭐**outdoor 连续街区（AP1+AP2）阶段性完成**：门→广场石街全连、广场有中心身份、街具落 verge。**外围建筑本就已连（AP2 纠 AP1 已做）。**
- ✅**车道杠杆对抗审查已跑（4 独立镜头 + 综合，2026-08-07）**：判决——**「更户外」OUT**（AM4→AP1→AP2 已 6 连片视觉、金标最险面、第7片=教科书单车道过投）；**下一车道 = NPC 选角深度**（不是"社交可读性"）。关键洞见：社交**渲染管线**基本做完（关系线**已绿=亲密/红=敌意** valence 分色——协调者实读 `WorldView.gd:3316` 复核，驳回"背叛≈问好"），最刺眼 placeholder 是**一个定位 ≤60 人的镇只有 12 张真脸**（拨大到 60 时 48 个复读机）。审查还抓到**我的 F4 失败模式复发**：docs/138(AM4) 引 4 幻影 `golden_*.log`+假精度 1297s（我在 133-136 修过却漏 138、还写"✅已回填"）——已纠 + 全 docs sweep（`c1d1b08`）。
  - **协调者对审查前提的实读纠正**（不 relay）：出货默认 **N=12**（distinct，非审查以为的 60）；克隆复读机只在**用户拨大 N**时现（设计意图拨大才"长满"，`player_touch_test.gd:283`）⇒ 选角深度**payoff 在拨大档**，出货默认镇规模(12 vs 拨大)是**产品身份决定、已备注用户**（非阻塞）。
  - ✅**AQ1（编号 142，`f017af4`+ledger `db99773`）已落地**：personas 12→24（追加 12 可辨识居民 + voicebank 台词），**零金标设计**=新人设 traits 镜像原人设+只用已枚举 token ⇒ 各 N digest/chain 逐字节不变、只显示层(name/color/sprite/气泡)变。**命门实证**：协调者独跑 S0 金标 = PASS 12/12 含链（AQ1 子棒卡自 CI 未提交、协调者接手 finalize）。权威整轮 CI PASS（含 VoiceGate、`analysis/aq1/ci_landed_verdict.txt`）。眼验：N=24 事件流出现六婶/阿涛/老槐等新名。
  - **⇒ AQ2 视觉辨识度经核= 低值**：新 12 人已有 **7 种 sprite 纹理 × 各异 color + L6 逐 id 色变**（非单一复用），拨大后不是脸盲。⇒ 不做 AQ2-sprite。

### ★ 产品状态盘点（2026-08-07，到达【自主打磨的收益递减 / 用户决定】边界）
连做 AM4→review→AP1→AP2→review→AQ1 一大批后，**视觉/空间/选角名册/社交渲染四层已实质打磨到位**：
- ✅ 室内八栋身份 + 居民室内渲染（AM1-4/F2）；✅ 户外石街 + 广场社交心脏（AP1-2）；✅ 选角名册 12→24（AQ1，拨大不复读）；✅ 社交渲染**本就齐全**（关系线 valence 绿/红、事件散文流、emote/气泡、冲突红标、盟约青线、小镇纪事目标）。
- **剩下的高价值车道都需用户拍板**（不擅自做）：
  1. **选角行为深度**（新人设给**不同 traits/行为**、非只镜像显示面）——**移金标**（新 token 入 Sim decision，须 docs/41 §3 重烘**金标锚**=改判据基线=用户决定）。
  2. **出货默认镇规模**（默认 N=12 distinct vs 拨大成活镇）——产品身份决定，决定选角/社交打磨的默认可见度。
  3. **storylet / 叙事内容**——§0.8 门控 + 外审 21:00 暂停 Narrative 合入，等用户放行。
- **纯自主零金标的剩余项都是边际**（更多环境装饰=会再触"视觉车道过投"、审查已叫停；室内活动姿态可读=需碰 Sim 态或收益小）——**不churn 投机小片**。
- ⇒ **当前动作**：盘点已写、决定点已 surface 用户；**放慢 loop 到边界节奏**，等用户就上面 1-3 任一拍板，即可精准起下一大车道；用户若明确"继续自主挑无悔小片"，再从边际项里挑。**这不是没进度，是诚实到达"高价值需输入"的边界、不用低对准忙碌冒充进展**（[[feedback-freeze-gates-drift-recurs]] 同源纪律）。

<details><summary>（旧队列，已被上面覆盖，留档）</summary>

1. P0 收敛：required PR/check + 冻结 SHA + 并行 CI。2. AC2 vanished 红门。3. state_projection+KnowledgeState（§0.8）。4. AH1 先并层（§0.8）。
</details>
