# 107 · Wave AB 计划——**先让 web maze 可结算、可回放，再把它接到镇上**

> 外部实验室：`E:/Documents/Dev/living-town-narrative-lab`
>
> Lab 共同契约：`CONTRACT.md`；20 棒依赖图：`ROADMAP.md`
>
> 主仓共同契约：[41](41-baton-contract.md)，任何会移动既有 digest 的接入仍走 [47](47-wave-e-plan.md) R12。
>
> 开工基线：`9bad1f411982a4c3c52268ca08b80412b7265699`（AA1+AA2+AA3 union）。

## 〇、当前裁决

**独立 Narrative Lab 可以继续；生产接入维持 NO-GO。**

这不是因为《第十三张空椅》没有内容骨架。它已有 6 个 role、12 个 node、三类 edge、13 片材料、
竞争解释、8 个 beat 与 5 个 ending portrait。问题在于这些数字里有几项只证明“字段非空”或“无条件图连通”，
还没有证明动作能被结算、时间窗内能走通、切角不泄漏、存档与回放能复现。

Round-0 三路对抗审查得到同一个 P0：

1. Lab 的 v1 validator 没有真正执行完整 JSON Schema；未知 action/gate/effect 与错误类型可漏过。
2. gate、beat choice、fallback、ending requirement/effect 是 opaque token，没有 predicate/cost/delta registry。
3. 三条核心 claim 的所谓双路径共享单片或含无关片；当前门只检查 tuple 不同，不检查 provenance 独立。
4. `knows` 不能区分知道、相信、怀疑与误信，也没有 seed receipt/source chain。
5. 当前 BFS 忽略 window/gate/cost/access；“六人均可达 12 点”不是 runtime 可达性。
6. 主仓 `goto_tick()` 不回放玩家动作；现有 digest/chain 不含 fragment、receipt、custody 与 edge overlay。
7. `SimExtensions` 的逐 agent 即时执行也不等于“所有离屏 intent 从同一 pre-state 规划后原子结算”。

所以本波 high-leverage 顺序不是先画一张完整 UI，而是：**可执行 contract → reducer/receipt/hash → 四路线 →
save/replay/tamper → promotion audit → 只读投影 → UI/录制 → integration RFC 最终裁决。**

## 一、共同停止线

S12 promotion audit 通过前，所有棒共同禁止：

- 改 `Sim.gd`、`Main.gd`、`WorldView.gd`、`game/data/map.json`；
- 把 fixture 复制进 `game/data/scenarios/`；
- 用 player notebook 解锁 role 动作；
- 用 `Story.gd`、UI 或模型写回事实；
- 用 `SpaceGraph.portals_from()` 代替 Sim 的角色移动授权；
- 用 prose token、截图或“测试全绿”冒充 canonical state/replay 已成立。

主仓现有 `analysis/phase_d/` 与 `analysis/town-world-probe/` 是开工前就存在的未跟踪目录，本波不得触碰或纳入提交。

## 二、20 棒路线

完整 owner、forbidden、acceptance、evidence 与 handoff 在 lab `ROADMAP.md`；这里保留主仓权威摘要。

| 棒 | P | 交付 | 进入下一阶段的硬门 |
|---|---|---|---|
| S01 | P0 | Git/source freeze、共同契约、Round-0 review | clean checkout 可复算；tamper 必红 |
| S02 | P0 | 真 Draft 2020-12 schema + typed registries | extra/type/unknown token/伪 production 均拒绝 |
| S03 | P0 | evidence closure | 单片/整批损失、共享单点、无关片 mutation 有牙 |
| S04 | P0 | maze/transaction/ledger reducer | gate/window/access/cost 真结算；同输入逐字节一致 |
| S05 | P0 | epistemics/handoff/offscreen | false belief 分离；notebook 不解锁；原子回滚；intent 乱序稳定 |
| S06 | P0 | 主仓全新只读 snapshot contract | 两 role 不同视图；隐藏文本零泄漏；不读写 Sim |
| S07 | P0 | 四条固定 12-watch trace | watch 8 前 edge/receipt/custody 已结构分叉 |
| S08 | P0 | save/load/replay/tamper | split-run 等于 uninterrupted；单字节篡改必红 |
| S09 | P1 | cafe/library 8–12 storylets | token 全登记；每 choice 有 cost/effect/fallback |
| S10 | P1 | wash/work/home 8–12 storylets | ≥3 跨 role 碰撞；≥2 退出 fallback |
| S11 | P1 | square/night/rumor 8–12 storylets | ≥4 可证伪转折；≥2 错路恢复地板 |
| S12 | P0 | 独立 runner promotion audit | structure/routes/save/replay/LLM-off 逐项判 proved/contradicted/weak/missing |
| S13 | P1 | WebMazeGraph / RolePOVCard / glyph | POV 差异可见；隐藏文本不进节点树；0.5× 可辨 |
| S14 | P1 | 真实 actor/space/portal 只读 projection | fail closed；投影前后主 digest 相同 |
| S15 | P1 | coverage + ending oracle | ≥32 storylets；每 role ≥4 主动入口；≥4 结构结局；无全优解 |
| S16 | P1 | 唯一 UI compositor | 键鼠/触屏同函数；切角/穿行/交接/回看完整 |
| S17 | P1 | 三分辨率截图、录屏、manifest | 1280×768 / 1024×768 / 2688×1216；trace 双跑一致 |
| S18 | P1 | integration RFC 最终版 | clock/movement/receipt/save/replay/hash/迁移逐项拍板，不直接接写侧 |
| S19 | P2 | 技术报告、journal、wiki、非技术汇报 | 功能/困难/方案/错前提/未测项/commit/命令/媒体齐全 |
| S20 | P0 | 第二轮红队 + 安全修复 + 下一轮 roadmap | source→artifact completion audit；不以全绿代替逐项核验 |

并行只发生在 ownership 不相交时：S03/S04/S05/S06；S09/S10/S11；S08/S13/S15；S14 与视觉准备。
共享 schema、compositor、索引与最终审计各自保持单 owner。

## 三、接入 RFC 的预冻结边界

这些是独立 runner 必须对齐的边界，不是批准接入：

1. **时间**：候选口径是一天 12 watch、每 watch 20 tick（由现有 240 tick/day 派生）；S07 用节奏实测后才能冻结。
2. **玩家动作**：另建 canonical narrative action trace。不能假设主仓 `goto_tick` 会替它回放。
3. **离屏事务**：同一 watch 的 intent 全部从同一 pre-state 产生，以稳定 ID 仲裁，再原子提交。
4. **移动**：physical traversal 最终必须请求 Sim 现有 journey/portal 授权；lab 不复制一份角色移动真相。
5. **认识**：receipt/source chain 旁挂现有 beliefs；`MemoryStream` 只接派生文本，因为它会遗忘且不是证据仓。
6. **存档**：权威 narrative state 必须是纯 Dictionary/Array 或有显式 snapshot/restore；不能放进会被反射存档跳过的 Object。
7. **digest**：narrative-on 用 `sim digest + narrative hash`；custody、receipt source、edge state 任一变化必须改 narrative hash，prose/UI 不改。
8. **呈现**：沿用 Story 的只读折叠原则；incremental view 必须等于从 canonical ledger 全量重建。
9. **模型**：只选合法候选 ID 或润色已结算事件；关闭模型仍可完整跑四路线。

S18 必须把以上每项改成 `accepted/rejected/replaced` 并附 runner 证据。未经 S18 与新一轮 R12 brief，不开唯一的 Sim 写侧棒。

## 四、主仓现有可复用底座

- 64×48 地图、9 area、7 室内空间/8 floor、10 portal 足以承载首个 maze；视觉棒不改世界数据。
- 右侧观察台已有角色、关系、冲突、秘密与信念呈现；新组件只消费 role-filtered snapshot，不造第二套人物事实。
- 现有 sprite 正面帧、姓名色、职业短标签与代码绘制符号足够做第一轮；不先画整套立绘。
- `tools/record-godot.sh` 的声音混流、deterministic demo camera 与 trace 可复用；新增 narrative gate，不改旧视觉门。
- 默认全镇视角会隐藏名字、表情与气泡，因此 maze 的信息层级必须独立于世界名牌。

## 五、开工基线与尚未外推的东西

在 `9bad1f4` 实跑的 targeted gates：

- `save_load_test`：PASS；
- `s4_replay_test`：PASS，drift 0；
- `space_test`：PASS，0 fail；
- `story_test --seeds 1-2 --days 40`：PASS。

但 AA1/AA2/AA3 合并后的 HEAD 尚无一次 union full-CI 回执；三棒各自 CI 绿不能自动外推为合并树全绿。
因此 S01 另跑当前 HEAD 全 CI，完整日志与退出码归档后才能说本波开工基线绿色。

## 六、阶段产出

- Lab `reports/ROUND_0_ADVERSARIAL_REVIEW.md`：本轮反例与停止线；
- Lab `journal/2026-08-02-stride-00.md`：为何撤回“结构 PASS ⇒ 可执行”的误读；
- S07/S08：四路线 ledger、replay、state/hash 与 tamper evidence；
- S17：多分辨率截图、15–20 秒录屏、contact sheet、媒体 manifest；
- S19：技术回执 + 非技术进展汇报（功能、困难、方案、仍未完成）；
- S20：第二轮红队报告、当场修复与下一轮 roadmap。

## 七、Detection envelope

- **detects**：当前 v1 schema/证据/认识/replay/digest 的已知空洞；通过 20 棒把每类声明绑定到命令与 artifact。
- **does_not_detect**：今天尚未运行的真实 12-watch 节奏、人工 PT-001–006、手机触屏体验与生产写侧兼容；全部明确为 `NOT_RUN`。
- **confidence**：生产停止线 high；20 棒排序 high；具体 watch↔tick 比例和 UI 信息密度 medium，必须由后续实测决定。

## 八、这份 brief 哪里是错的

“参考 Rivette / Balzac，扩充 narrative 体量”本身没有错；错的是如果把体量理解成先写更多自由文本。
当前最稀缺的不是剧情点子，而是能证明每条线索由谁知道、经什么路径得到、失败后留下什么、回放时为何还是同一件事的结构。

另一个容易错的直觉是“地图已经有了，所以接一层 UI 就行”。现有地图足够复用，但 role-specific access 的权威在 Sim，
而玩家动作不在 canonical replay 中。先接 UI 会让系统在截图里成立、在存读档与回拨里失忆。本波因此先修可执行性，
并把 32–36 个 storylets 的内容扩张放在 schema 冻结之后并行进行。
