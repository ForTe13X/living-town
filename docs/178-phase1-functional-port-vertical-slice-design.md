# 178 · 相位1 · 功能港口纵切【设计】——把无形贸易接成玩家可见的一条纵切

> 触发：docs/113 相位0 收口后放行相位1；外审主诉「town/world 玩家可见增量本窗口=0，港口仍 pure-View draw、不读 logistics，import/export 仍是日界账本、无 carrier/manifest/warehouse」。
> 对齐用户愿景：big Other（中央权威）**持续供养**物资进镇——本片把那条供养链【显形】成港口来船卸货。
> **纪律＝先设计再实现（DP-A 教训）。本片只出设计、不 build、不移金标。** disjoint-by-file、可验收，呈用户定方向后再分棒实现。

## 〇、一句话

港口现在是【看着像、其实空】：视觉画了栈桥/货箱/渔船（AP-port，pure-View），但 `port_dock` **只声明不落图**（logistics.json _why 明写「落图交给 P1」）、import/export 只是日界账本数字。本片设计把它接成一条**功能纵切**：`port_dock` 成真·world 对象（可导航、有身份）→ 来船（carrier）按到货日**显形抵港卸货**（复用 festival 的 spawn/despawn 原语）→ 仓库库存**可见**。分 3 个 disjoint 子棒（P1-a/b/c），a/b 移金标、c 可纯 View。

## 一、grounded 当前态（file:line，实测非假设）

| 部件 | 现状 | 位置 |
|---|---|---|
| `port_dock` 节点 | **只声明**(id/type=码头/pos[33,8]/area=dock)，**不进 world.objects**；唯一作用＝硬#44 校验 import actor | `game/data/logistics.json:7-15` |
| 落图为何 defer | WorldView 契约「world.objects 只放 advertises 非空对象」+ type=码头 在 `OBJ_SLOT_BY_TYPE` **无槽** + 别名预算已满 ⇒ 现在落图＝品红占位 bug + CI 红(player_touch_test 撞过) ⇒ **明写交 P1** | `logistics.json:13` _why |
| import/export | **日界账本**，纯 f(day)(`day%every==0`)、整数、无 RNG/浮点、无可见载体 | `Sim.gd:3780 _logi_import` / `3835 _logi_export` |
| 港口视觉 | AP-port 已画栈桥/系缆桩/货箱/渔船/船屋 + 路牌——**pure-View 装饰**，「一块带凳子的铺装，没有任何码头/船/仓库功能」 | `WorldView.gd:3233,3503` / docs/163 |
| world.objects 契约 | advertises 非空 → 入 world.objects(可导航/供动作)；advertises 空 → 只渲染+挡格 | `Sim.gd:590-593` |
| 精灵槽解析 | `_obj_slot(type,id)` 走 `OBJ_SLOT_BY_TYPE`；H3 断言：任何 advertises 对象【必须】解析出可画槽，否则品红+CI 红 | `WorldView.gd:4322,4387,4405` |
| 别名预算棘轮 | `OBJ_SLOT_ALIAS_BUDGET={bench:5,counter:4,desk:2}`——别名增长被棘轮管住，不能随手借槽 | `WorldView.gd:4378` |
| spawn/despawn 原语 | `spawn_object(def)`/`despawn_object(id)`(WorldPatch 原语#4)；**festival 是现成先例**：日界 despawn 昨日→spawn 今日、确定 id、track 数组 | `Sim.gd:3156 _update_festival` |
| 导航挡格 | `_blocked`(idx→true) 由 world.blockers + 家具重建；新增 world 对象会改 nav ⇒ 改 agent 轨迹 ⇒ 移金标 | `Sim.gd:238,4242` |

**结论**：相位1 就是 logistics.json 明写「交给 P1」的那件事——把 port_dock 从逻辑节点升成功能对象 + 给贸易加可见载体。视觉外壳(AP-port)与 spawn/despawn 原语(festival)**已存在可复用**，是 reuse-first 的干净起点。

## 二、纵切分棒（disjoint-by-file，分阶段可各自验收）

### P1-a · port_dock 升为功能 world 对象【移金标】
- **做什么**：给 `port_dock` 一个非空 `advertises`（一个码头工作动作，见 §四 待定①）＝入 world.objects；同时给 type=`码头` 在 `OBJ_SLOT_BY_TYPE` 加一个**真槽**（新过程化 dock 精灵，非借别名 ⇒ 不动棘轮预算，见 §三）。
- **文件**：`logistics.json`(port_dock.advertises) · `WorldView.gd`(OBJ_SLOT_BY_TYPE 加码头槽 + 过程化 dock draw) · `Sim.gd`(仅确认 compile 路径，多半零改)。
- **确定性/移金标**：新静态 world 对象在 [33,8] ⇒ 改 nav/blockers ⇒ agent 轨迹位移 ⇒ **移金标**（digest 变）。走 §0.8 + committed-树三锚重烘 + held-out + refute。
- **验收**：port_dock 进 world.objects；H3 断言绿(码头槽解析得出、无品红)；player_touch_test 绿；off 门(删 logistics.json)逐字节回今天；金标重烘三锚 tree-fresh。

### P1-b · 到货来船 carrier 显形抵港【移金标·复用 festival】
- **做什么**：新 `_update_carrier()`（**镜像 `_update_festival` 结构**），挂 _nightly：到货日(`day%every==0`，与 _logi_import 同拍)`spawn_object` 一艘船在 port_dock 旁、次日 `despawn_object`。船带 manifest（本批到货货/量，读 import_lane.batch）。确定 id `carrier_<good>_<day>`、track `_carrier_objects`——与 festival 一字同构。
- **文件**：`Sim.gd`(`_update_carrier` + `_carrier_objects` 声明 + _nightly 挂点) · `WorldView.gd`(船精灵 + 可选 manifest 货堆) · `logistics.json`(carrier 视觉配置，可选)。
- **确定性/移金标**：spawn_object 入 world ⇒ 移金标（同 festival 已是金标内）。纯 f(day)、无 RNG/Time ⇒ 逐字节可回放。off 门：缺 logistics.json ⇒ 不调 ⇒ 逐字节回今天。
- **验收**：到货日港口有船、非到货日无船；同 seed 两跑逐字节相同；金标重烘；off 门回退。
- **★复用红利**：festival 已证明「日界 spawn/despawn 确定对象」在金标下稳（festival_spawn/despawn 在 liveness 里 80/80 稳），carrier 是它的直接实例化 ⇒ 低风险、低新代码。

### P1-c · 仓库库存可见【优先纯 View·零金标】
- **做什么**：WorldView 读 `town_stock`（已存在的镇库），在滩头仓库位画一个**库存指示**（货堆高度/数字随 stock 涨落）＝把「进来的货堆在哪」显形。**先做纯 View**（只读 sim 状态、不改 sim）⇒ 零金标。
- **文件**：`WorldView.gd` 唯一。
- **确定性**：纯 View 零金标（同 AV1/AV2/AP-port 纪律，POND/SEASON tol=0 风险自查）。
- **验收**：仓库货堆随 import/export 涨落、视觉门 tol=0 绿、S0 金标 12/12 不变（零金标证据）。

## 三、E1 落图 blocker 的解法（关键设计点）

E1 defer 的三条理由逐一拆：① type=码头无槽 → **P1-a 加一个过程化码头槽**（`OBJ_SLOT_PROCEDURAL` 加 `dock:true`，像 bed/stove/fest 那样**程序画**，不占别名预算、不动 `OBJ_SLOT_ALIAS_BUDGET` 棘轮）；② advertises 空进不了 world → P1-a 给它一个真 advertises（§四待定①）；③ WorldView 是 E1 绝不碰区 → 相位1【就是】碰 WorldView 的授权片，按 pure-View/移金标各自纪律走。⇒ 三条 blocker 在 P1 全可解，且**过程化槽避开别名棘轮**是最干净的路（新经济建筑车站/仓库同法可扩）。

## 四、待用户定的设计决策（呈方向再实现）

1. **port_dock 的 `advertises` 是什么？**——(A) 一个 **stevedore 卸货 JOB**（`jobs.json` 加「码头工」，班表 job-gated，产/搬运货）＝接用户「commercial/service 建筑由 outsider affiliate 运营」愿景的第一个 affiliate 岗；(B) 仅一个轻 idle「候船/看船」动作（不加经济角色，最小移金标）。**荐 A**（一岗接双愿景：功能港口 + affiliate 运营），但 A 是更大移金标（新 job 改决策/社交分布）。
2. **首刀范围**——(i) 只 P1-a（港口成真对象，最小可见增量）；(ii) P1-a+b（港口+来船，一眼「贸易在发生」）；(iii) a+b+c 全纵切（港口+来船+仓库库存，完整「货从外部来、堆进仓、镇里用」）。**荐 (ii)** 作首个可见里程碑，c 作纯 View 收尾。
3. **carrier 可见度**——一艘静态船精灵（最省）/ 抵港→停→离港的多 tick 动画（更生动，但要设计 carrier 的 tick 状态机，多一层移金标状态）。
4. **与相位2/3 的接续确认**——本片是**物理地基**：把 big Other 的供养【显形】。相位2(Anno goods-demand：居民要这些货)、相位3(big Other 财政：税/账单/affiliate)在此地基上加**经济意义**。请确认这个「先显形物理、再加经济意义」的相位序对不对你的 big-picture。

## 五、共同约束（contract，本片不破）

红线#1 逐字节可回放（carrier/港口对象皆纯 f(day)/静态、无 RNG-Time-浮点）· #2 零模型可玩 · #3 ≤60 人 · #4 已 waive(生成图可出货，港口/船精灵可用生成底稿)。移金标片(a/b)＝§0.8 双路评审 + off 门自证 + committed-树三锚重烘(golden/modelpath/ledger) + HARD_IDS 两份同步 + held-out 13-30 + N 路 refute；纯 View 片(c)＝零金标 + 视觉门 tol=0。godot 重烘必传全 exe 路径。**新贸易货/口岸落图若进硬不变量集 ⇒ 补 SPEC provider + 负夹具（复用相位0 #44-46 已建的贸易 complement 通道）。**

## 六、disjoint 棒表（呈用户定范围后据此派单，子 agent 必 base=integration/batons）

| 棒 | 文件面(disjoint) | 金标 | 依赖 | 验收锚 |
|---|---|---|---|---|
| P1-a | logistics.json + WorldView(OBJ_SLOT/dock draw) + Sim(compile 确认) | 移 | 无 | H3 绿/port_dock 入 world/off 门回退/三锚重烘 |
| P1-b | Sim(`_update_carrier`+_nightly) + WorldView(船精灵) | 移 | P1-a(港口位) | 到货日有船/逐字节/off 门/三锚重烘 |
| P1-c | WorldView(仓库库存 draw) 唯一 | 纯 View | 无(可先做) | 货堆随 stock/视觉门 tol=0/S0 12/12 |

**排序**：P1-c 可【即刻并行】（纯 View、不依赖 a/b、文件面只 WorldView draw 区，与 a 的 OBJ_SLOT 表不同段）；P1-a→P1-b 串（b 用 a 的港口位）。三棒与叙事(codex/narrative)、既有视觉(AV) 文件面不相交。

## 七、本片状态

**设计 only、未 build、未移金标。** 待用户答 §四（尤①岗位性质 + ②首刀范围 + ④相位序确认）→ 据 §六棒表分派实现。
