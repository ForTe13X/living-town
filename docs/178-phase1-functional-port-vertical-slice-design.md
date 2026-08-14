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

## 四-bis、用户已定（2026-08-10）+ affiliate 岗设计细化

**用户拍板**：①岗位＝**stevedore affiliate 卸货 JOB**（选 A，接「affiliate 运营」愿景）；②首刀＝**全纵切 a+b+c**；③carrier 可见度、④相位序＝按设计默认（简单船精灵起步、物理先行）。

**stevedore「码头工」affiliate 岗设计（P1-a 核心新机制，复用 jobs.json holder 机制）**：
- **岗位**：`jobs.json` 加 holder「码头工」title、action=`卸货`、shift 相位、worksite=port_dock。复用既有职业/工位机器（extra_advertises 注入、job-gated 决策槽），不新造决策原语。
- **做什么**：carrier 在港日（P1-b，`day%every==0`），码头工上班把 manifest 货**从港/仓搬进 town_stock**——把现在「日界账本瞬间到货」显形成「工人在码头卸货」。到货量仍＝import_lane.batch（不改经济量、只改**显形路径**：账本注入 → 工人动作驱动的同量注入，off 门须逐字节等价或走移金标重烘）。
- **affiliate 种子（接 big-Other 愿景）＝establish 角色，不动钱路**：
  - ⚠️**实测结论（2026-08-10，读 Invariants.gd:1090-1092 + Sim.gd:271/1595）**：external 账户被硬 #34 recon【锁死】——每笔 target=external 必 actor==town/reason==import、每笔 actor=external 必 target==town/reason==export（recon ③）；「凭空 transfer 到/自 external（没 import/export 货撑的款）⇒ external ≠ 应值 ⇒ 红」（recon ①）。⇒ **码头工工资若从 external 付＝违反 recon ③ 直接判红**。原设想（external 付薪＝affiliate 种子）**不成立**，不可做。
  - ✅**安全解**：P1-a 码头工工资走 **town_coin**（＝所有既有职业的同一条发薪路：Sim.gd:1595「做活工资镇库流出、镇库空则跳过」，#34 总量守恒/#35 非负天然保）或**干脆无薪**。affiliate 身份用**数据标记**(job 加 `affiliate:true` + 外来 persona)establish，**不引入任何新钱流** ⇒ #34/#35 守恒集**一字不动**、P1-a 移金标只源于「新 job 改决策/社交分布 + port_dock 改 nav」，比原设想【风险低得多】。
  - **诚实边界**：完整 affiliate 财政（external 付 affiliate / big-Other 收税 / 居民账单）＝**相位3**，那时才【慎重扩】#34 recon 加 affiliate 项（走完整 §0.8 + 四方对账扩展）。P1-a 只 establish「外来实体运营一个 dock 岗 + 卸货显形」，钱路留 P3。

**warehouse 位（P1-c）**：滩头 dock 区 [30,7,4,2] 内、AP-port 已画的「船屋」旁设一个仓库位；WorldView 读 town_stock 画货堆高度指示（纯 View）。具体格位在 P1-c 实现时据 AP-port 结构定（不撞栈桥/渔船/port_dock[33,8]）。

## 七、本片状态 → 实现就绪

**设计 only、未 build、未移金标。** 用户已定全纵切+affiliate 岗 ⇒ 据 §六棒表分派实现：
1. **P1-c（纯 View 仓库库存）先/并行**——零金标、最安全、即时可见增量、文件面只 WorldView draw 区。
2. **P1-a（港口成真对象 + 码头工 affiliate 岗）**——移金标；焦点＝external 付薪对 #34/#35 守恒的影响，必过 §0.8。
3. **P1-b（到货来船 carrier，复用 festival）**——移金标；依赖 P1-a 港口位。
每移金标棒＝committed-树三锚重烘 + off 门自证 + held-out 13-30 + N 路 refute；协调者在 committed 树 finalize。子 agent 必 base=integration/batons。

## 八、P1-a 实现就绪 spec（workflow wlb5b5uyd 6-agent 设计+对抗 verify；关键锚协调者已复核）

**核心机制（对抗 verify CONFIRMED-SAFE；我复核 Sim.gd :872/:875/:990/:1023/:2049/:3094）**：
- **池排除＝append-after-pool**（全部金标安全的地基）：affiliate 在 Sim.gd:875（定池 `_pool_rescale`/`_work_pull_mult`）**之后**才 append 进 `agents` ⇒ 定池时 `agents.size()==12` ⇒ `prod_pool_num==den==12`（:3365 短路）⇒ **export 不惰性**（豆子照出）、work_pull_mult==1.0。verify 枚举全 7 处 `agents.size()` 确认无隐藏 size 敏感池读，命门成立非侥幸。
- **工资走 town_coin**（非 external——#34 recon :1090-1092 锁死）；spawn 时 `econ_total0+=coin`（守 #34/#35，照 add_player:1026）。
- **卸货＝Option 1**：stock 注入仍留 `_logi_import` 日界账本、卸货动作 stock_delta=0（只发工资+社会痕迹，照 #41 形状；`_draw_dock` 读 `_stock_of("柴薪")` 显形）⇒ #38/#44/#45/#46 算术一字不动、**HARD_IDS 不动**。
- **port_dock 渲染**＝过程化 `dock` 槽（`OBJ_SLOT_PROCEDURAL`，不占别名棘轮，H3 绿，纯 View 零金标）。

**⚠️ 2 处 MUST-FIX（对抗 verify 逮出、协调者已核验锚，落地前必补）**：
1. **needs 冻结在【满】非 72**：`_make_agent` 置 needs=**72**（:990），只 `_decay_needs` 跳过＝冻在 72 ⇒ urgency=100−72=28 > 阈值 5（:2049）⇒ affiliate **照吃口粮**（#40 三紧货）⇒ 破「#40 分母不变/floor=36 原样」两句、尾风险边际逼红 **#01(HARD)**。**修＝spawn 后覆写所有 needs=100（照 add_player:1023）** ⇒ urgency≡0 永不成消费候选。
2. **affiliate agent id == jobs.json 键**：`_job_of(id)` 按 **agent id** 取 job（:3094）。jobs 键必须 == affiliate 的 id（且 == 广告位 `job` title 持有人），否则工资退化零工价、job 门永不开 ⇒ 卸货/工资链**静默失效**。

**5 disjoint 棒**（派发拓扑 **{B1∥B2}→{B3,B4}→B5**）：
- **B1** `Sim.gd`（移金标核心）：`_is_core` 谓词 + affiliate spawn（append-after-pool,:875 后 :910 前,`scenario==""` 守卫,persona=`tao`,needs=100）+ `_decay_needs` 跳 `_is_core` + `_tally_election` 排除 + `_town_image_stats` 口径收口(:3996/:4005) + `_compile_ports()`（镜像 worksite）。
- **B2** `agents.json`+`jobs.json`+`logistics.json`：`affiliates` 独立 key（id==jobs 键） + port_dock advertises 卸货 + jobs `<id>`:{码头工,wage} 走 town_coin。
- **B3** `Invariants.gd`（口径，**不新增硬门**）：:240 small_n 数核心 + :252 #03 跳 `_is_core` + :640 #37 eligible 对称排除。
- **B4** `WorldView.gd`（纯 View 零金标）：过程化 dock 槽 + `_draw_dock`。
- **B5** finalize 三锚重烘（committed 树）。
- **★#37 硬耦合陷阱**：B1 的「on-gate」验收**不得含 #37**（须待 B3 对称排除，否则 voters≠eligible 自红）。

**诚实标注（非阻塞，须如实记）**：① #03 排除 affiliate＝**真语义削弱**（真孤立的外籍工不再被抓），非纯口径；② 冻结-needs + town_coin 工资 affiliate＝**单向 town_coin 汇**（挣不花，60 天抽干，加重结构性赤字 seed18 的跳薪）——是【产品决策】非纯数值；③ N≥20 克隆扩容会与 `tao` 人设撞（未来棒）。

**finalize（committed 树，Option 1 下 HARD_IDS 不动）**：off-gate 三键删=pre-P1-a 逐字节 → commit game/ → 重烘 golden（seeds+scenarios **两段**）/modelpath/ledger（全 exe 路径，~12min，`dead_at_bake=[]`）→ 四锚各补 rebake_history → committed 树全 CI（尤 2f 互补性）→ held-out 13-30（硬 18/18、#40 逐 seed 前后不变、饿穿 0）→ 独立 AI refute。

## 九、用户拍板（2026-08-10）：**fully-integrated affiliate**（吃喝-参与，最faithful最重）——spec §八 frozen-needs 默认【被推翻】，须重设计

用户选【吃喝-参与】而非 spec 默认的冻结-needs。⇒ **§八 的"needs 冻结在满"MUST-FIX 与"不进 #40 分母"论证全部作废**，改按下述重设计（append-after-pool 池排除 / town_coin 工资 / Option 1 卸货 / 过程化 dock 槽【仍成立】，只 needs+消费一支翻盘）：

- **affiliate 有真 needs（decay+eat+spend），不冻结**：`_decay_needs` **不**跳过 affiliate（它会衰减、会去吃、会付钱）⇒ 工资在镇里循环（挣→买饭→钱回镇库）⇒ **无单向汇**（解 §八对抗 verify 的经济畸变）。
- **⚠️ 新张力（重设计核心）**：affiliate 吃 **口粮**（核心生存货）⇒ 与 12 居民**抢食**，但 append-after-pool 使**产能仍按 12 定池**（保 export 不惰性）⇒ 13 张嘴抢 12 份产能 ⇒ 撞 **#40 食物满足率 + #01 饿穿**。必须解。
- **★优雅解（接 big-Other 愿景）＝affiliate 自带外部口粮，经港口进**：outsider 的补给随船来（import lane 加一条"码头工口粮"external 供给，或 affiliate 有独立 supply 不吃镇产口粮）⇒ **既消除抢食、又直接兑现"big Other 外部供养"**。这是 fully-integrated 的推荐落法（待重设计 workflow 定确切机制）。
- **#01/#40 scoping 决策**：若走"自带外部口粮"则 affiliate 不抢镇产、#40 分母仍可按核心算；若走"吃镇产口粮"则须 export floor 36→? held-out 重标 + 决定 affiliate 是否进 #01 scope（进则须保证可喂饱，否则饿穿红）。
- **wage/amount/duration/floor** 皆决策稀释+食物敏感 ⇒ held-out 经济探针标定。

**⇒ P1-a 需一次【重设计 pass】**（fully-integrated + 自带外部口粮机制 + #40 held-out 重标），再派实现棒。§八 的池/工资/卸货/渲染骨架复用，needs/消费/食物供给重做。

### 九-bis、用户再扩（2026-08-10）：outsider＝经济+信息+心理三维图（非机械工）

用户："they also consume, which also generates revenue and tax, could also exchange ideas/info flow, provide lacanian jouissance and a desire/aspiration for local residents, a dream"。⇒ 重设计的关键 **reframe**：
- **消费是【想要的】非要避的**（纠正先前"自带外部口粮以避消费"的误读）：affiliate **消费驱动经济**——买服务/货 ⇒ 生 revenue(商户) + tax(big Other)。∴食物张力正解不是"别消费"，而是【**生存口粮外部供给经港口(不抢12居民紧货⇒保#40/#01)，但自由消费镇里 discretionary 服务/货(cafe/娱乐/商品)⇒驱动本地经济+纳税**】。既解 #40/#01、又兑现"consume→revenue+tax"。
- **相位映射**：P1-a(现)＝消费行为+revenue 种子路(付 town_coin/给商户)；**Phase 3 财政**＝完整 revenue+tax+账单闭环；信息流+Lacanian＝更深社会-叙事机制。
- **信息流/exchange ideas**（社会-叙事，非 P1-a 首落）：outsider＝外部世界 conduit，带新话题/观点/消息 ⇒ 影响居民 beliefs/attitudes/topics（接社交 sim + codex/narrative）。
- **★Lacanian jouissance / desire / aspiration / dream**（心理-社会，愿景层）：outsider＝objet petit a（欲望-成因）——居民对其代表的"外面世界/另一种活法"生**渴望/aspiration**成一个 dream。可落：居民新增"向往"维度 / 围绕 outsider 的 storylet（憧憬外面） / outsider 作 status-欲望焦点。是 town 的社会心理深度，攒进后续叙事/社会相位。

**⇒ P1-a 重设计 workflow 须纳入**：消费→revenue 种子路（不只自带口粮）、#01/#40 scoping 在"外部生存口粮 + 镇内 discretionary 消费"框架下重算。info-flow/Lacanian 维度记愿景、Phase 2-3 展开。

**terrain 决策：用户选 LA 东海（East Ocean）**（见 docs/179 §五）。

## 十、Codex takeover 重设计 + P1-a 首片（2026-08-10，`codex/p1a-takeover`，已 checkpoint/未重烘）

本节**取代 §七「design only」与 §八 frozen-needs 实现 spec**；§九/九-bis 的 fully-integrated 用户决定是现行产品语义。当前首片已在隔离分支实现，但在 golden/held-out/全 CI 完成前仍不算 landed。

### 10.1 重设计结论

- `agents.json.affiliates[]` 独立声明阿涛；默认场景且 logistics 开启时，在 `_pool_rescale` / `_work_pull_mult` **之后**追加。因此生产/出口继续用 12 位核心居民定标，affiliate 本人仍是完整 agent。
- **不设 `_is_core` 行为豁免**：阿涛的 needs 正常衰减，正常吃饭/赶集/喝咖啡、付钱、社交并参加选举；#01/#03/#37 都真实覆盖他。唯一口径变量 `core_population` 只用于 #15/#20 的小镇/大 N 分档，修掉“第 13 人令既有门静默豁免”的风险。
- `port_dock` 的 `advertises=卸货` 由新 `_compile_ports()` 编译成真实、阻挡、可导航 world 对象；type=`码头` 走 `dock` 程序化槽，不占别名预算。岗位复用 jobs holder / shift / wage / skill 原语，工资从 town_coin 支出。
- **暂不加外部口粮 lane**。先验“13 张嘴必撞 #01/#40”被实测否掉：在 12 人产能不放大的条件下，shipping/default 的 hard 门与跨 seed 软门仍过。held-out 唯一 #40 反转缺的是 **糕点**（discretionary demand），不是生存口粮；给免费口粮是错因调参。N=24 的口粮边界另记 scale/composition 诊断，不能借 P1-a 预防性补丁偷偷重标。
- P1-a checkpoint 的“卸货”是 Option 1：岗位/可见动作/工资/社会存在落地，贸易货量仍由日界 import ledger 注入。该状态已被 §10.9 的 manifest-gated kernel 取代；可见 carrier 与物理 East Ocean 港仍未完成。

### 10.2 当前证据

- 静态：`lint_data` PASS（13 agents / 24 personas）；`audit_map` PASS（10 个 activity sites，含功能港口；13 agents 全可达）；`lint_links` PASS；`git diff --check` PASS。
- 先验探针：固定 12 人生产与 work-pull、跑 13 个普通 agent，seeds 1-3 × 60 天均 hard/soft 空、#40 绿、饿穿 0；所以没有先塞免费口粮。
- 真实实现：seeds 1-12 × 60 天，逐 seed `n_agents=13`，**hard_fails=[] / soft_fails=[] / #40=12/12 / starved=0**。口粮满足率范围约 0.655-0.990，周期性短缺没有被灌没。
- 活性：seed 1 × 60 天，码头工工资 `wage:卸货` 19 笔、被接受社交 52 次；新 `p1a_affiliate_test` 的 20 天硬门还断言了 4 次卸货工资、12 笔镇内消费、53 次社交、needs 真变化、选民=13。
- 确定性：Harness seed 1 × 60 天、det=1，46 条不变量全绿，批量 digest + event digest + 逐 tick chain 两跑一致。`player_touch_test` PASS，H3 未报未映射槽。
- P1-a off-gate：临时摘掉 `agents.affiliates` 与 `port_dock.advertises`（既有 import/export 保留），seed 1 × 60 天重新与 committed golden 的 digest/event_digest/chain **三项逐字节一致**。
- **held-out（2026-08-11）**：默认 12 core + 1 affiliate，seeds 13-30 × 60 天，**hard 18/18、软门过（阈值 17/18）、det 3/3、活性过**。#40=17/18；仅 seed 27 的糕点满足率 0.48（95/197、断供 36/60 天）触发下限臂。committed `d46cbb1` 的 seed 27 为 #40 绿，故这是 fully-integrated affiliate 带来的真实 discretionary demand，不是旧债；但它仍在成文跨 seed 容差内。
- **规模参数口径抓虫（2026-08-11）**：P1-a 在 `spawn_count` 冻结 pool/work-pull **之后**追加 affiliate，所以 Harness `--agents N` 现在实际是 **N core + 1 affiliate**。旧写法 `--agents 16/24/60` 实得总人口 17/25/61；前两格全门过，最后一格虽 hard 12/12、det 1/1，却 #40=9/12（seeds 2/6/9 上限臂）且已越过“≤60”红线，**不得冒充 N=60 证据**。
- **精确总人口矩阵（2026-08-11）**：改用 `--agents 15/23/59` 得到 15/23/59 core + 1 affiliate：N=16 **PASS（#40 12/12）**；N=24 **soft FAIL（hard 12/12、det 1/1、#40 10/12，seeds 1/7 下限臂；seed 1 口粮 0.47、断供 33/60 天）**；N=60 **PASS（hard 12/12、det 1/1、#40 11/12；仅 seed 9 上限臂）**。三格活性均过。这个非单调形状要求下一棒先把 core/total 契约显式化，再对 N=24 做因果诊断，不能凭 N=60 或单一 seed 外推。
- **base 反证**：隔离 `git archive d46cbb1` 上，默认 seed 27、N=24 seeds 1/7、N=60 seeds 2/6/9 的 hard/soft 均空、#40 均绿；临时 archive/展开目录验证位于 `%TEMP%` 后已精确删除，日志保留在 `%TEMP%/p1a_base_*_godot.log`。因此上列边界来自 P1-a 的人口组成/需求变化，而非这些 seed 的 committed 基线失败。
- **scale-count contract（2026-08-11；checkpoint `ad1cc08`）**：Harness 保留 `--agents N` 为 **legacy core**（大量历史 fixture 不静默换义），新增互斥的 `--core-agents N` 与 `--total-agents N`；后者调用 `Sim.scale_population_plan()` 按当前场景、logistics、affiliate id 冲突规则反算 core，并在每次主跑/det 复跑启动后同时断言 `core_population` 与 `agents.size()`。带人口参数的 `[S0]` JSONL 新增 `{mode,requested,core,total}` 证据；冲突参数、非正整数、无法缩小的 total 均 exit 2。1 天真 tick 对拍中，`--total-agents 16/24/60` 分别得到 core 15/23/59、total 16/24/60，与 legacy `--agents 15/23/59` 的 digest/event_digest/chain/events 四项逐字相同；三条 total 路均 det 1/1。以后报告 N=60 不再依赖人工减一。

### 10.3 尚未完成（不可省略）

1. **N=24 #40 下限臂因果诊断**：先把 seeds 1/7 缩成 affiliate ON/OFF、同 total/同 core 的可比臂，判定是规模供给还是 affiliate composition；再决定成文处理，禁止直接拍数值。
2. logistics off-gate 的逐字节对拍；golden seeds/scenarios、modelpath、ledger 三锚只能在行为与 review 收敛后重烘。
3. 全 CI（含 complement fixtures、save/load、视觉/Xvfb）与人眼港口可读性验收。
4. P1-b 的 CargoManifest kernel 见 §10.9；尚缺可见 carrier 与物理 East Ocean 港。Phase 3 tax、outsider 信息流与 Lacanian aspiration 均未实现，继续按 §九-bis 排期。

### 10.4 Baton / hygiene ledger（2026-08-11）

- 本棒范围：只补 held-out + scale + committed-base 反证；主 agent 唯一写入本文件，三个 mini-session 只写互不重叠的 `%TEMP%/p1a_*_godot.log`，仓库未产生测试生成物。
- 验证环境：Godot 4.6.2 stable；各完整格均检查 hard/soft/liveness/det；日志仅有退出期 `ObjectDB instances leaked` warning，无 signal 11 / fatal / out-of-bounds/native crash 命中。warning 记 `stale-candidate`，不在本棒顺手修。
- Git hygiene preflight：共享仓库当前 164 个 worktree（161 个绑定分支、3 detached、0 标记 prunable），184 个本地分支，其中 150 个 `worktree-agent-*`。因全都缺 owner/完成态证据且多数仍被 worktree 占用，统一记 `unknown-owner / stale-candidate`，**本棒零 archive、零 clean、零 branch mutation**。
- scale-count contract 棒：独占写入 `game/bench/Harness.gd`、`game/scripts/Sim.gd` 与本 ledger；测试日志只写 `%TEMP%/p1a_contract_*.log`。未改金标/modelpath/ledger 锚；实现已随 P1-a WIP checkpoint `ad1cc08` 入 Git、尚未 push，参数错配现在可在仿真 tick 前恢复性失败，不再产出误标 N 证据。
- 本棒验证：Godot 4.6.2 解析/运行通过；default / legacy core 12 / explicit core 12 / total 13 四路都得 core 12、total 13 且四项摘要全等。total 16/24/60 均跑 1 天真 tick、各 det 1/1；三组 total↔legacy-core 对拍的 digest/event_digest/chain/events 也全等。非法 flag 冲突、core 11 与 total 12 均 exit 2、零 `[S0]`。`lint_data`、`audit_map`、`lint_links`、`git diff --check` 全过；仓库根与 `game/` 均未生成 `.godot`。
- mini-session：`p1a_base_compare` 全程只读，贡献 strict parse/互斥、det 双断言与“plan/append 共用 selector”审阅；后者已吸收为 `Sim._eligible_affiliate_defs()`。它另 flag `tools/lint_data.py` 尚未拒绝空/重复 affiliate id 与 `npc_N` 保留命名，记 `stale-candidate`，不在本棒跨文件扩张。
- link hygiene flags（只 flag、不整理）：`lint_links` 仍报 `docs/52@worktree-agent-a0c76a3f96ae5dbcf` 12 处为“分支在、文档不在”，`docs/45@claude/objective-lumiere-e6f125` 3 处已可由 HEAD canonical 文档替代，`docs/54@worktree-agent-a31b222a4dfd444a7` 2 处对应内容已并入 HEAD。owner/source task 未确认，统一 `stale-candidate`；后续 hygiene 棒先定位消费者再修引用，未 archive/clean。
- 下一可调度 baton：P1-a N=24 seeds 1/7 因果最小复现；用新 `--total-agents 24` 固定总人口，再做 affiliate composition 对照。它与 logistics off-gate、golden 重烘、全 CI 分离。

### 10.5 Review delivery gate + 贸易活性补集棒（2026-08-11；checkpoint `221456e`）

- **Review sync**：Living Town `review` task 的 09:00 CST scheduled brief 仍是 `REQUEST CHANGES`。draft PR #5 的 synthetic-merge CI 后来于 09:50 CST 变绿，但 PR base 固定在 `d18cc43`，比当时 live `integration/batons@d46cbb1` 落后 **178 commits**；live exact product tip 查询为 0 check-runs / 0 Actions runs。因此这次 green 只说明其冻结 review merge 可跑，**不是 exact-tip delivery proof**，不解除合入门。
- **采纳的反例**：旧 `SPEC[44]/SPEC[46]` 在 logistics 开启时恒给 provider=1；所以 zero-trade、import-only 等没有对应事件的格子也会被补集表记成“有牙”。本棒把 `[X3LIVE]` 扩为小型可复用贸易活性接口：`import_events`（真实 import 条数）、`export_related`（#46 扫描的 pay/export-stock 相关事件数）、`export_pairs`（相邻 pay,stock 候选对，仅诊断）。#44/#46 provider 分别消费前两项，字段缺失故意 fail-closed，旧探针输出不能冒充新证据。
- **边界收口**：#46 不直接用 `export_pairs` 当 provider——孤儿 pay/stock 可令 #46 变红，但完整 pair 仍为 0；只有 `export_related==0` 才能诚实称“判据没有事件可判”。probe 不复判 qty、actor、target 或货物合法性，判决仍由 `Invariants.gd` 独立负责，避免量具和门互相喂答案。
- **负控制**：`tools/gate_fixture_audit.py --self-test` 现经完整 `[X3LIVE] → parse_dir → SPEC` 链覆盖 logistics-on 的 zero / import-only / export-only / both，以及 orphan-only；前四格分别只激活真实存在的方向，orphan 格证明 `pairs=0` 时 #46 provider 仍可非零。旧 constant-one、constant-zero、只数 import 三类错误实现均会被矩阵击穿。
- **实跑证据**：Godot 4.6.2 在 `git archive HEAD:game` 隔离树上跑 S0 seeds 1-12 × 60 天，探针子进程 `rc=0`、12/12 条 `[X3LIVE]` 可解析；#44 `import_events=19..20`，#46 `export_related=8..16`、诊断 `export_pairs=4..8`，且 12/12 均满足 `related == 2*pairs`。随后 `python tools/gate_fixture_audit.py --from %TEMP%/lt_trade_provider_out_v2 --only S0` exit 0，HARD_IDS/DIAG_IDS/ci.sh defaults 对账均通过。这里只跑单格，工具明确警告**不能**据此下全 CI provider 结论。
- **review 点名控制**：同一 committed-tree 隔离副本的 probe 新增量具专用 `--trade-control`（不进入游戏运行时）。seed 1 × 60 天：`zero-import` 得 `import=0 / export_related=0`；`zero-export` 得 `import=20 / export_related=0`，两格 #44/#46 本体仍因空集真而绿，但 provider 均按真实事件归零，证明不再读取“logistics 存在”。由于 external 初始无钱、出口收入依赖进口付款，zero-import 实跑会连带令出口也为 0；export-only 的方向解耦由上面的合成解析格覆盖，不把经济依赖伪装成独立运行时流。未知 control exit 2 且零 `[X3LIVE]`。
- **POOL16 反例已复现并收口于量具**：POOL16 seeds 1-12 × 60 天子进程 `rc=0`，`import_events=20`（12/12），而 `export_related=export_pairs=0`（12/12）；新表把 #46 明确列为整格空洞，不再叫 live provider。当前 baked ledger 仍是旧锚（`Kind46=G`，providers 仍含 `POOL16`），所以 delivery blocker **尚未关闭**；本棒遵守禁令不重烘，等 committed tree + 完整 fixture 网格时才允许刷新。
- **诚实 delivery 状态**：`tools/gate_complement_ledger.json` **未重烘**；必须等代码提交、完整 fixture 网格和 exact game-tree 来源闭环同时成立才可更新。review 对现 P1-a “ghost-unloading”的判断也采纳：静态卸货广告/工资没有 carrier、manifest、cargo decrement 或 atomic stock commit，且旧 north-pond 锚与用户已选 East Ocean 冲突，故本片仍不可合入。后续顺序保持：补集门证据进入 committed tree → exact-tip CI → East Ocean 的最小 `CargoManifest` 纵切（manifest arrival → gated unload → cargo/stock 原子提交；无 cargo 必须零 unloading）。
- **Hygiene**：本棒只写 `tools/gate_fixture_probe.gd`、`tools/gate_fixture_audit.py` 与本 ledger；测试派生物仅在 `%TEMP%/lt_trade_provider_*`，标 `generated/rebuildable`。实现已 checkpoint 为 `221456e`、尚未 push；未改 branch/worktree/ref、未 archive/clean，README 受保护首屏未触碰。

### 10.6 Exact-tip CI 触发合同棒（2026-08-11；checkpoint `e7cf14c`）

- **Review/live cutoff**：Living Town `review` task 最新 completed scheduled brief 仍是 09:00 CST / `REQUEST CHANGES`，没有更新轮次。11:21 CST heartbeat 再查 GitHub：live `integration/batons=d46cbb1` 仍为 **0 check-runs / 0 Actions runs**；draft PR #5 的 `ci=SUCCESS` 仍只对应 review head `4bcdc81` + 旧 base `d18cc43`，不是 live product tip。故本棒只建立“下一次 integration push 能产生 exact-tip run”的前置合同，不宣称已有交付回执。
- **目标/独占范围**：只改 `.github/workflows/ci.yml` 与本 ledger。保留 `pull_request` synthetic-merge CI，同时把 `integration/batons` 加入既有 `push.branches`（`master` 不移除）；在 `actions/checkout@v4` 后逐位核对 `git rev-parse HEAD == GITHUB_SHA`，不等则 exit 1，成功打印 `CI_SOURCE event/ref/sha` 单行回执。它不碰游戏、金标、modelpath、complement ledger 或 branch protection。
- **官方语义研究卡**（访问 2026-08-11；只适配原理，未复制第三方代码）：
  - GitHub Docs `Workflow syntax`：`on.push.branches` 按被推 ref 的 branch name 过滤；多事件带配置时各自保留冒号。来源：https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - GitHub Docs `Events that trigger workflows`：push 的 `GITHUB_SHA` 是推到 ref 的 tip；`pull_request` 的 `GITHUB_SHA/GITHUB_REF` 是 merge ref 的 merge commit，默认 checkout 因而验证 merged result。来源：https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
  - upstream `actions/checkout`（MIT；当前 workflow 仍固定 major `v4`）：默认只取触发该 workflow 的单个 ref/SHA，足够做 HEAD 对账，不需要为本合同放大到 `fetch-depth:0`。来源：https://github.com/actions/checkout
- **本地验收与限制**：PyYAML `BaseLoader` 解析通过，并断言 push branch 恰含 `master`、`integration/batons`，`pull_request` 仍在，SHA verification step 同时含 `git rev-parse HEAD` 与 `GITHUB_SHA`；`git diff --check` 通过。当前 Windows 的裸 `bash` 实际指向无 `/bin/bash` 的 WSL relay，无法诚实复现 ubuntu runner；shell 片段仅用 runner 保证存在的 bash 基元，最终证据必须等该 workflow 进入 committed integration tip 后由 GitHub run 给出。
- **剩余 blocker / 恢复触发器**：本棒不配置 branch protection/ruleset，也不 push，所以 exact-tip delivery blocker 仍是 open。恢复触发器是：workflow 与 P1-a 候选经正常 review 落入 `integration/batons` 并 push；随后必须核对 run 的 `head_sha == live integration tip`、`event=push`、`CI_SOURCE` 相同 SHA、完整 `ci` terminal success。任何 PR merge-ref green 仍只算 synthetic compatibility，不能替代这张 receipt。
- **mini-session**：`exact_tip_review` 全程只读，确认 slash branch pattern、push/PR 两类 `GITHUB_SHA`、默认 checkout、depth=1 与现有 concurrency 均符合合同；特别否决把 checkout 改成 PR head SHA（会破坏 synthetic-merge gate）。它建议的 `permissions: contents: read` 属安全强化、branch protection/merge queue 属另一交付棒，本轮均不顺手扩入。
- **Hygiene**：workflow 已独立 checkpoint 为 `e7cf14c`、尚未 push；未改 refs/worktrees、未 archive/clean，其余文件原样保护。README 受保护首屏未触碰。

### 10.7 Complement ledger hard-ID 身份合同棒（2026-08-11；checkpoint `221456e`）

- **Review/live cutoff**：12:22 CST 恢复时，Living Town `review` task 最新 completed scheduled brief 仍是 09:00 CST / `REQUEST CHANGES`；live `integration/batons=d46cbb1` 仍无 exact-tip check/run，PR #5 的绿灯仍是旧 base 的 synthetic merge，故 CargoManifest 继续暂停。本棒只关闭 review 点名的 complement ledger 盲区：旧 M8 把 baked hard 判据删掉只会 warning，不能借此声称 P1-a 可交付。
- **目标/独占范围**：只改 `tools/gate_fixture_audit.py`、`tools/gate_complement_guard.py` 与本 ledger。未来完整 bake 会在 `_meta.hard_ids_at_bake` 写入升序精确 hard-ID 集合；guard 要求该字段是无重复正整数数组，严格解析 live 唯一 `const HARD_IDS := [...]`，比较集合全等，并确认每个 baked hard ID 仍有真实 `_chk(id)` 调用。新增 hard、删除/降级 hard、删除判据、缺字段、非法表达式、只在注释保留 `_chk` 均 fail-closed；未知新软门仍只 warning。
- **mini-session / 吸收项**：`exact_tip_review` 全程只读，指出两条原计划绕过：旧 `_check_hard_ids()` 在声明缺失时只输出“无法核对”，CLI 可能继续 bake；raw `_chk(` 搜索会命中文档/注释。已吸收为结构化 strict parser、明确 boolean 拒烘，以及只接受 bare / `R.append` / `return` 实际调用行。它建议的 metadata 类型门也已落地（`type(i) is int`，拒绝 bool、非正数与重复）。未复制外部代码，无许可证输入。
- **验证证据**：`python tools/gate_fixture_audit.py --self-test` PASS（21 项，含新锚精确写入 `hard_ids_at_bake`、live 副本对账、非法表达式与重复 id 拒绝）；`python tools/gate_complement_guard.py --self-test` PASS（19 项，M8/M8b/M8c/M8d/M8e 分别击穿判据删除、hard 降级、旧 schema、非法 live 表达式与注释伪装）；`python -m py_compile tools/gate_fixture_audit.py tools/gate_complement_guard.py` 与 `git diff --check` 通过。
- **诚实迁移状态 / 停止条件**：`tools/gate_complement_ledger.json` 按协议**未重烘、未手填**，现有锚为 2026-08-10 / commit `0fe0814`，缺 `hard_ids_at_bake`；正式 `python tools/gate_complement_guard.py` 因而按设计 rc=1，并明确要求完整重烘。这是 fail-closed migration blocker，不是回归假红。本棒到“producer/consumer 合同和负对照均通过、旧锚必红”即停止。
- **恢复触发器**：先让 probe/audit/guard 与 exact-tip workflow 经 review 进入同一 committed product tree；再从该 exact game tree 跑完整 fixture 网格并获准执行一次 full `--run --bake-ledger`，随后要求 guard rc=0、ledger 的 `baked_commit/baked_game_tree/hard_ids_at_bake` 与 live tip 全部对账，最后才可取 exact-tip CI receipt。不得单独手改 metadata 或用局部网格重烘。
- **Hygiene**：没有改现有 ledger、golden/modelpath、README、branch/ref/worktree；实现已 checkpoint 为 `221456e`、尚未 push，未 archive/clean。只 flag `tools/gate_complement_ledger.json` 为 `active + stale-schema/blocking`，恢复点仍是 Git 中既有 `0fe0814` 锚及未来一次可复现 full bake。

### 10.8 Git takeover checkpoint（2026-08-11 13:20 CST）

- 用户明确授权主 agent 接管 Git 管理。当前 dirty tree 经只读分组审阅后，17 个路径全部可追溯至 §10.1–10.7，无明显无关用户文件；没有使用 `git add -A`，每次均以显式路径 stage、核对 cached 清单并先跑 `git diff --cached --check`。
- 已建立三个可恢复主题提交：`e7cf14c`（exact-tip workflow）、`ad1cc08`（P1-a affiliate dock + scale-count WIP checkpoint）、`221456e`（#44/#46 event-backed provider + hard-ID fail-closed）。本文件作为第四个独立 ledger commit；提交不等于评审通过。
- checkpoint 前复验：`p1a_affiliate_test` PASS（20 天：wage=4、spending=12、social=13、voters=13）；`lint_data.py` 与 `audit_map.py` PASS；fixture audit 21/21、complement guard 19/19；workflow YAML 合同与 `git diff --check` PASS。正式 complement guard 仍因旧 ledger 缺 `hard_ids_at_bake` 按设计 rc=1。
- **Delivery gate 不变**：P1-a 仍是 review 所称 ghost-unloading，且港口锚未迁至 East Ocean；旧 ledger 未重烘，exact-tip 远端 receipt 尚不存在。Git checkpoint 只保存、分层和公开证据，不授权向 `integration/batons`/`master` 合并。远端发布必须保持 draft/WIP，并在正文列出这三个 blocker。

### 10.9 P1-b CargoManifest kernel 棒（2026-08-11 14:00 CST）

- **目标 / 边界**：关闭 review 的 ghost-unloading 反例，并落一条最小正向链；只改 manifest 权威态、物流数据、候选/完成双门、chain 投影、focused scene 与 CI 接线。不改地图、WorldView、carrier 动画、golden/modelpath/complement ledger。`route_id=east_ocean` 只声明逻辑货源；现有 `port_dock@[33,8]` 仍是旧地图 dock，绝不冒充 East Ocean 地形已落地。
- **实现合同**：到期日 `_logi_import` 只按 `route × day × lane-index` 生成整单 `{node,good,initial_qty,remaining_qty,price,state}` CargoManifest 和一条 `world:cargo_arrive` receipt，不碰库存或钱；manifest order 是显式 Array，存档只含 String/int/Dictionary/Array。卸货广告仅在最早整单同时有货位、余额时出现，travel→use 与完成点再次核验；外部强制 option / 旧存档缺 manifest 字段时从 world advert 恢复合同，不能绕过。
- **同步提交**：`_commit_manifest_unload` 要求在班码头工，固定执行 `town→external pay(import*4)` → `_stock_move(import*4)` → `cargo remaining 4→0/status complete` → `world:cargo_unload`；之后旧完成管线才允许记忆、技能和 `wage:卸货`。本片只整单卸：现价 `3/4` 若拆成四笔 1 件会被整数地板成四次 0 钱，整单 4 件恰付 3 钱，避免免费货。
- **focused negative/positive/save/det**：新 `p1b_cargo_manifest_test` 先证明空港广告关闭；即使强塞一个 `phase=use/remaining=1` 的旧 option，needs/stock/coins/event/option/完成记忆/技能/wage 全零。正例证明 arrival 只增 cargo；真实完成后 `cargo_delta == stock_delta == import.qty == 4`，事件严格为 import pay → import stock → unload receipt → wage，既有 #34/#38/#44/#45/#46 全绿。另命中 pending manifest save→load、use 期间货位/余额/cargo 被抢/跨出班次四种竞态及原单恢复，并拒绝整单价格地板为零的 paid lane；chain 对 option 的 `manifest_id/node` 和 cargo 的 `price_per/den` 均有单字段 mutation 牙，同时用 logistics-off 普通 option 证明旧 6 字段 chain 逐字节不漂；同 seed 完整状态/事件/event_digest 两跑逐字对拍。
- **验证**：Godot 4.6.2 focused scene PASS（0 fail）；既有 `p1a_affiliate_test` PASS（20 天真实 manifest-gated wage=5、消费=15、社交=56、选民=13）；Harness seed1×6d hard 全绿、det 1/1；最终 seed1×60d hard/soft 全绿、#40 绿、det 1/1，真实 import commit=19、export=5。`lint_data`、`audit_map`、`git diff --check` PASS。只跑单 seed，不能替代完整 12+held-out/scale 网格，也没有授权重烘。
- **旧证据 hygiene**：`logistics.json` 中“每 3 天直接注入 / 60 天约 80 件 / 当晚 import 自动贷足 export”的表述已标为 legacy 或改写；旧 AS1/AS4/N16/24/60 结论测的是日界直接注入路径，不能套到 manifest 吞吐。README 未触碰；没有 archive/clean；测试存档位于 `user://`，scene 结束时按精确路径删除；日志只在 `%TEMP%`，标 generated/rebuildable。
- **mini-session**：`p1a_base_compare` 与 `exact_tip_review` 全程只读、无仓库所有权；共同否决“只停工资、让 Tao 静默失活”，建议同棒提供正向 commit seam。吸收了候选+完成双检、整单防价格地板、world receipt 不污染 #38/#44、manifest 进入 save/chain；物理东海锚和 carrier 留作独立后续棒。
- **Review / PR sync**：最新 completed review brief 仍为 09:00 CST / `REQUEST CHANGES`，没有新 turn。PR #6 旧 head `5fb2686` 的 synthetic-merge run `31461417688` 已终态 **FAIL**：SHA verification 成功；首个真实失败是预期中的 complement ledger `baked_game_tree` stale + 缺 `hard_ids_at_bake`，随后还有 golden/modelpath/VoiceGate/player_agency 红。该 run 不含本棒，不能归因于 CargoManifest，也不是 exact integration-tip receipt。draft 必须保持不可合并。
- **剩余 blocker / 下一恢复触发器**：① 提交/push 本棒后核对新 PR head CI，分开记录行为锚预期漂移与非锚真实失败；② 完整 seeds 1-12 + held-out + total-N scale 重新量 manifest 吞吐，未过不得重烘；③ 以 East Ocean terrain 的结构锚迁移物理港口并接可见 carrier；④ exact-tip 仍须 workflow 真进入并 push `integration/batons` 后取得 `event=push/head_sha==tip` receipt；⑤ completed manifest 暂保留在 arrival order，查询成本随历史线性增长，当前 60 天规模可接受，后续应以保持回放顺序的 compact/index 独立棒处理。

### 10.10 P1-b 标准网格证据棒（2026-08-11 14:40 CST）

- **阻塞换道**：本轮首先尝试把已验证 commit `fbbf6f0` normal-push 到 `codex/p1a-takeover`，但 `github.com:443` 再次 `Recv failure: Connection was reset`，远端没有变化。没有用 REST 改 ref 绕过 normal-push 边界；按防锁协议把本轮唯一实现 baton 切为 committed-tree 标准网格。
- **验收**：在 `fbbf6f0` 上跑 seeds 1–12 × 60 天、det 3，exit 0 / S0 PASS；hard 全 `12/12`，#44/#46 各 `12/12`；#40=`11/12`，唯一 seed 6 糕点满足率 0.46、断供 42/60 天；17 个门控事件类全活，aid 覆盖 12/12，det `3/3`。canonical 资源卡见 `analysis/p1b/n12-standard-grid.md`。
- **mini-session / ownership**：`p1a_total60_compare` 只读运行精确 Harness 命令，只写 `%TEMP%/p1b_n12_seeds1_12_60d.log`；主 agent 核对 HEAD、状态、结果与 crash pattern 后只写本 ledger 和资源卡。没有并行写同一文件。
- **Review / PR sync**：review task 最新 completed brief 仍是 09:00 CST / REQUEST CHANGES；PR #6 仍为 draft、head `5fb2686`，旧 synthetic-merge CI 仍 FAIL。本网格来自本地 committed `fbbf6f0`，不是 PR check 或 exact-tip receipt；CargoManifest 已关闭静态 ghost-unloading 的逻辑内核，但物理 East Ocean/carrier 与 delivery receipt 继续阻断合入。
- **Hygiene**：工作树在测试前后 clean；原始日志为 `generated/rebuildable`，未复制进 repo；未 archive/clean worktree、branch、unknown-owner 文件，未重烘或改动 golden/modelpath/complement ledger。下一棒优先重试这两个本地 commit 的 fast-forward push；若网络仍阻塞，再跑 held-out 13–30，不能重复本标准格。

### 10.11 P1-b 码头工 VoiceGate 补集棒（2026-08-11 15:35 CST）

- **CI / review sync**：Living Town `review` task 最新 completed brief 仍为 09:00 CST / `REQUEST CHANGES`，其 product cutoff 早于当前分支。draft PR #6 exact head `1b07a43` 的 synthetic-merge run `31466041072` 已终态 FAIL；SHA verification、S0 hard 12/12、#44/#46 12/12、CargoManifest focused scene 与 state projection 都通过。首个红是按设计 fail-closed 的 stale complement ledger；另有 golden/modelpath 行为锚漂移、player agency，以及一个与锚无关的真实失败：`tao|卸货` 被 offer 427 次但冻结 voicebank 没有同名动作。
- **本棒边界**：只给 `voicebank.tao.卸货` 增加三句符合既有“码头扛包、直来直去、收工喝酒”人设的显示层台词，并记录回执；不重跑 `scriptwriter --voicebank`，不覆盖其他人格资产，不改 Sim、CargoManifest、地图、agency 或三类锚。该资源输入是人格 `tao` + 动作 `卸货`，输出是 `_canned_say` 可确定性选择的非空短句；来源为仓库内 `personas.json` / `jobs.json` 的既有原创设定，无外部代码或许可证输入。
- **验收 / 限制**：CI 同口径 `VoiceGate seeds 1-3 × 60 days` exit 0 / PASS：326 个 `(人格,动作)` 对、37 个动作、13/13 人格全枚举、0 对为空；`voicebank.json` 解析与 `lint_data.py` 也 PASS（24 JSON、16 required、13 agents、24 personas）。原始日志在 `%TEMP%/p1b_voicegate_tao_unload_receipt.log`，标 `generated/rebuildable`；仅有既知退出期 ObjectDB leak warning。voicebank 只进入 UI 气泡/记忆视图，不进入 Sim digest，所以本棒不重跑、不重烘 golden/modelpath/complement ledger。通过 VoiceGate 只关闭这一个非锚红，不能把 PR 写成整体 green 或解除 East Ocean 物理港、可见 carrier、stale anchors、player agency 与 exact integration-tip receipt 等 blocker。
- **Hygiene / ownership**：主 agent 独占 `game/data/voicebank.json` 与本 ledger；没有 mini-session 写入、没有生成仓库内缓存、没有 archive/clean/ref mutation，README 受保护首屏未触碰。下一恢复触发器是本提交 normal-push 后的新 PR-head CI；若 VoiceGate 仍红，停止并记录新的首个空 pair，不跨入其他失败域。

### 10.12 Player-agency 人口合同去常量棒（2026-08-11 16:35 CST）

- **Review / exact-head CI sync**：review task 最新 completed brief 仍为 09:00 CST / `REQUEST CHANGES`，没有更新窗口；远端 `integration/batons` 与 PR #6 base 仍是 `d46cbb1`。PR exact head `4021f4d` 的 synthetic-merge run `31470442420` 已 terminal FAIL，但 event SHA 对账成功；VoiceGate 已转绿，S0 hard 12/12、#44/#46、CargoManifest focused scene 与 state projection 均绿。预期红仍是 stale complement/golden/modelpath 三锚；唯一无关锚的真实红为 `player_agency_test` 1 项。
- **根因 / 边界**：本地 exact scene 复现显示其余 27 项全绿，唯一失败是入镇人数断言写死 `12-cast + player = 13`。P1-a 合法追加一名 affiliate 后，启动态已有 13 residents，`add_player()` 正确得到 14 agents；测试把旧阵容组成误当成玩家接口合同。本棒只把断言改为“调用前 resident count + 1”，并继续要求 `is_player=true` 与 `get_agent("player")` 同一对象；不改 Sim、人口规模、社交阈值、地图或锚。
- **资源池 / 验收合同**：该断言现在可被默认 12 core、带 affiliate、以及未来合法阵容复用，测的是 `add_player()` 的增量与身份语义，不再和居民数量耦合。实跑 Godot 4.6.2：`player_agency_test.tscn` PASS（0 fail；14 agents = 13 residents + player，挂机社交 69 次、8/8 seeds、12 actors）；`p1a_affiliate_test.tscn` PASS（0 fail）；`p1b_cargo_manifest_test.tscn` PASS（0 fail）。三份日志在 `%TEMP%/p1b_*_postfix.log`，仅有既知退出期 ObjectDB warning；三者任一红即停止，不扩入锚或物理 East Ocean。
- **Hygiene / ownership**：主 agent 独占 `game/scripts/player_agency_test.gd` 与本 ledger；无 mini-session、无外部研究或许可证输入，不修改 README、golden/modelpath/complement ledger，不 archive/clean。测试日志只写 `%TEMP%`，标 `generated/rebuildable`。

### 10.13 P1-b manifest 授权续班 + delivery grid big batch（2026-08-11 18:35 CST）

- **单一目标 / 内部 DAG**：把 CargoManifest 从“逻辑正确但吞吐回归”收敛成可验证纵切：先跑 standard/held-out/total-N16/24/60 与 pre-P1b 隔离 A/B，再定位单码头工 `offer→pick→commit` 漏斗，最后实现 engine-signed exact manifest option、跨班完成、stale-intent 防护、save/chain 回归，并复跑分层网格。实现 commit 为 `cfca74a`；canonical 资源卡为 `analysis/p1b/manifest-overtime-delivery-grid.md`。
- **根因 / 修复**：旧 28-tick 卸货在 travel/use/commit 每 tick 重验 dawn/day，临近 dusk 的已认领单被清空并下班重试；seed 15/30 的真实提交漏斗分别仅 `132→29→13`、`182→20→2`，且钱/终局容量反证不支持余额或货位是主因。现在只要求开工时在班；`_apply_object` 逐字段匹配当前 authored candidate 后签发 exact manifest 授权，途中继续核岗位、node/id、最早 cargo、货位/余额，成功仍严格 pay→stock→receipt→wage。外部 intent 篡 action/target/need/amount/dur_total、stale A→B 重绑、未授权旧档均在任何 gameplay effect 前拒绝。
- **验收**：focused scene `0 fail`，含 mid-use authorized save/load 与跨 dusk 同单完成；standard N12 PASS（hard 12/12、#40 11/12、真实 import/export 227/40、det3/3）；held-out 13–30 PASS（hard/#40/#44/#46 18/18、import/export 346/78、det3/3）；total-N16 PASS，total-N60 PASS（#40 11/12）。total-N24 仍因 #40 10/12 FAIL；N>12 的 export 按现有成文 scale gate 为零，#46 都是条件式空过，已在资源卡显式列红线。
- **Review / CI sync**：最新 completed scheduled review 仍是 09:00 CST / REQUEST CHANGES，cutoff 早于本实现。PR #6 `ac18e29` run `31478588905` 已终态 FAIL；SHA/S0/CargoManifest/player-agency/state projection 绿，红项是 stale complement ledger、golden/DetGate 与 ModelPath anchor。本棒不重烘。logistics-off 仍 hard/det 绿但 #40 9/12、三类 golden 共 36 处漂移；物理 East Ocean/carrier、N24 标定、三锚与 exact integration-tip push receipt 继续阻断合入。
- **mini-session / hygiene**：`p1a_base_compare`、`p1a_total60_compare` 只读跑互斥 `%TEMP%` 日志；`exact_tip_review` 只读对抗审阅并抓到 external intent 篡字段、stale cargo key 与 mid-use save/load 覆盖缺口，均已吸收。未改 README/地图/WorldView/三锚/protected branches，未 archive/clean；日志标 `generated/rebuildable`。下一 coherent batch 应优先在物理 East Ocean carrier 纵切与 N24 scale 标定中择一，不得用本次局部 green 冒充 delivery-ready。

### 10.14 P1-c East Ocean 可见货船 big batch（2026-08-11 19:00 CST；未重烘）

- **单一目标 / 决策**：关闭 review 的“港口锚与用户选定 East Ocean 冲突”和“货物到港玩家不可见”两项 blocker。对抗评审比较了 festival-style 动态 world object 与纯 View projection；本棒采用后者：`CargoManifest` 继续是唯一权威，货船按 `carriers[] × cargo_manifest_order` 投影最早 ready 单，多单只加有界计数，不复制 carrier lifecycle，不写 spawn/despawn、不进 nav/save/chain，也不扰乱严格 `pay→import→cargo_unload→wage` seam。
- **物理锚 / 地图成本**：East Ocean=`x60..63 × y0..47`，货港 dock=`[56,7,4,2] facing=east`，Tao home+spawn/port/berth=`[58,8]/[59,8]/[60,8]`（陆/陆/水）；渔业工位独立为 `north_pier=[30,7,4,2] / bench_pier=[31,7]`。water/tree/blocker=`272/130/569`，相对旧图净增 166 blocker。隔离矩阵先证明 home 非因果、旧 spawn32 只修复最初四红却在完整 held-out 新增 seeds16/24/26 三红；最终 K 臂把渔台合法分离回北塘、保留 Tao home+spawn58，七个目标 seed 的 #40 全部转绿。`population_anchor` 让 north_pier 复用旧 dock 的著者序/矩形/质心，同时排除 East freight dock，N>12 克隆仍精确消费旧 9 个锚。`audit_map.py` 已把地类、坐标、route/node、区域不重叠、渔业/物流隔离、扩容锚、全连通与双路门写成同一跨文件合同。
- **可见交付 / 负控制**：east-facing renderer 蓄意不画旧北池永久渔船；ready cargo 才画程序化货船。focused scene 覆盖 zero cargo、arrival-only、duplicate arrival、3 单 backlog 单船、FIFO rebind、save/load 与删 carrier config 的 off 门；删 carrier 只隐藏 View，manifest/event/chain 逐字不变。真实 framebuffer 同 seed/tick ON/OFF 差异 443 px、bbox `(948,199)-(979,221)`，全部落在 berth crop；同图负例 rc=1。该量具已接 `visual_gate.sh`，不新增 PNG golden。
- **当前验证 / exact code commit `c56f31e`**：`lint_data` PASS（24 JSON / 13 agents），`audit_map` PASS（walkable 2485 / blockers 569）；P1-c focused（含 exact 9-anchor tuple、非法 flag、N24 restart/save-load）、P1-a affiliate、P1-b CargoManifest、space、save/load 均 PASS。Harness：standard N13 `#40/#44/#46=12/12`、held-out `#40=17/18` 且真实双向贸易 18/18；total N16 `#40=12/12`、N24 `11/12`、N60 `11/12`，五格均 S0 PASS，det 分别 3/3、3/3、1/1、1/1、1/1。N>12 export 仍按成文 scale gate 为零，故 #46 只作 vacuous 结构门。完整回执在 `analysis/p1b/east-ocean-visible-carrier.md`；所有 Harness 未传 golden，只证明 hard/soft/liveness/determinism，不冒充 anchor receipt。
- **Review / GitHub delivery gate**：latest completed review brief 仍为 09:00 CST / REQUEST CHANGES，cutoff 早于本树。PR #6 旧 head `d34895c` run `31483079165` 已 terminal FAIL；exact checkout 绿，首红是 complement ledger stale/缺 `hard_ids_at_bake`，随后 golden/DetGate/modelpath 也因未重烘红，非锚 scenes 全绿。P1-c 进一步改变 nav 与 game tree，本棒按协议仍不重烘三锚，PR 保持 draft/不可合并。
- **Hygiene**：`_draw_port_legacy_north` 记 `legacy-supported`，不删除；旧“北池货港/次日退船”文字记 `stale-candidate`，canonical 指向本节与 docs/179 §六。`tools/gen_town.py` dry-run 已覆盖 north_pier/dock/Tao 双锚；其 `--write` 仍会重放历史 interiors 模板，故 generator/template reconciliation 继续记 `stale-candidate`，本棒不执行写出。README 首屏未触碰，零 archive/clean/protected-ref mutation。

### 10.15 P1-e schema-2 存档迁移 + 玩家视角产品参照 big batch（2026-08-12；未重烘）

- **单一交付目标 / DAG**：先关闭 P1-b/P1-c 新权威态仍沿用 schema 1 的混档风险，再把用户要求的玩法/UI/UX/美术参照纳入同一产品集成闭环。内部顺序为：冻结 `d46cbb1` 真实旧档 → 原子 schema 1→2 迁移 → transitional P1-b/畸形档负牙 → 玩家固定坐标真实 framebuffer → focused 回归、资源卡与 Git/PR 收口。canonical 资源卡为 `analysis/p1e/save-migration-player-visual.md`。
- **迁移合同**：`SAVE_SCHEMA=2`，只接收 1/2；header/blob schema 与 magic 必须一致，未知/派生键、类型、人口身份、CargoManifest order/record/授权 option 全部先在深拷贝上验证，成功后才 apply。pre-P1 档显式清空 cargo/order 并从 saved agents 推导 core；P1-a-only 卸货广告补 `manifest_node` 且清旧 option，未来三天仍零 cargo/零卸货工资；transitional P1-b schema 1 的已授权 mid-use 单保留并可严格完成。`backend/ext/decision_sink` 永不写档、永不覆盖接收实例连接。
- **exact fixture / provenance**：fixture 来自 `d46cbb132595185c3420bb4eb8fd7f28512baa85` + Godot 4.6.2 + seed `20260626` + tick 0；raw 271000 bytes，SHA-256 `84A9353F7C85A8BA191FEB45AFB644982DE273EB7380475930E509B4D68892B4`，以 deterministic gzip/base64 四片与 JSON sidecar 入池。迁移保留旧 north world/route-less logistics/12-agent cast，不凭历史 import 伪造 manifest，也不谎称自动升级到 East Ocean；承诺是安全确定续跑，不是旧引擎逐字节轨迹等价。
- **玩家视角 visual gate**：`Main --player-pos X Y` 成为可复用 presentation seam，默认出生点不变。visual gate 固定 seed 3 / tick 600，把 player 放 `[58,8]` 并选中；`vg_player_east_ocean.png` 同框玩家、ready 货船、栈桥/货箱、观察面板、时间轴和真实七动词操作栏。后续玩法纵切默认都要回答“玩家站在哪里、看见什么 affordance、如何操作、反馈是否清楚、UI 是否遮挡、美术是否讲清状态”，并至少留一张可复现截图；涉及动作节奏时再补短录屏。PNG 仍为 generated/rebuildable，不新增 pixel golden。
- **验证**：`save_migration_test` 覆盖 exact old fixture 的 clean/warm 同态、300 tick replay、schema-2 round-trip、runtime handle 保留与 7 类原子拒绝；`save_load`、`p1b_cargo_manifest`、`player_touch`、`p1c_east_ocean_carrier`、`p1d_scale_export` 全部 PASS，native-crash pattern 为 0。固定 `gamecraft-runner:4.6.2` + Xvfb 的玩家帧采集成功并完成目视玩法/UI/UX/美术检查。
- **Review / CI / hygiene**：最新 completed review 为 2026-08-11 21:00 CST / `REQUEST CHANGES`，冻结 `d0c8cba` 并把 schema 1 缺迁移列为 P0；本棒已用 exact `d46cbb1` fixture 与 schema-2 原子门直接关闭该项，但 09:00 下一轮 review 因模型容量失败，尚无对 `bcf2c04` 的新对抗回执。PR #6 上一 synthetic-merge run `31495043653` 无新代码红，首红仍是 stale complement ledger，随后是 golden/DetGate/modelpath 旧锚；visual 在 GHA 仍明确 SKIP。故本棒不重烘、不把 focused green 写成交付完成，PR 保持 draft。README 首屏、protected branches、未知文件均未触碰，零 archive/clean。

### 10.16 P1-f 本地 Godot 监督执行 + 玩家连续帧回执（2026-08-12；未重烘）

- **单一目标 / 根因**：关闭 21:00 review 的 P0 runner 污染项。CIM 预检精确确认四组旧 P1-b/P1-c/P1-e console→GUI 子树在测试返回后仍存活；命令行逐组含本项目 scene、`--path game` 与独立 `%TEMP%` 日志。经 parent/child/scene/log 三重复核，只终止八个精确 PID，四份日志保留；之后项目 Godot 进程为零，未碰其他 worktree、终端或文件。
- **可复用合同**：新增 `tools/run-godot-supervised.ps1`。每次本地运行独占 checkout lock，注入绝对 game path 与 GUID log，钉住 branch/source HEAD/`HEAD:game`，记录 stdout/stderr/Godot log 的 SHA-256；正常、非零、fatal、超时都在 `finally` 按 parent 链+唯一 log token 叶到根回收并复核零残留。退出码 `78` 表示并发/遗留进程 fail-closed，`124` 表示超时但清理成功；receipt 默认为 `%TEMP%/living-town-godot-runs/<run-id>/receipt.json`，可由下一会话直接复核。
- **负控 / 验收（P1-k 纠偏）**：`tools/test-run-godot-supervised.ps1` 真跑 P1-d focused scene（exit0）、故意让主循环超时（exit124）并在 owner 运行时启动第二实例（exit78）。历史 v1 receipt `176d96d…` / `f51c256…` / `697c13c…` 记录了 source `0cfc495`、game tree `1d16ae5`，但其 dirty `status_before` 意味着它们只证明 candidate-tree 进程监管，不能称 commit-exact。P1-k v2 默认拒 dirty；显式 candidate 绑定工作区指纹，运行中来源漂移 exit79。完整接口、纠偏与恢复证据见 `analysis/p1f/supervised-godot-runner.md`、`analysis/p1k/supervised-source-identity.md`。
- **玩家视角视觉验收**：按 Godot pipeline 的真实 framebuffer 纪律，用监督器在 seed3、tick580/600/620 把玩家放在 `[58,8]` 并选中；三帧均为 1280×768、哈希互异，同框可读玩家、ready 货船、泊位货箱、事件日志、需求/钱、时间轴与七项交互条，且每帧运行后零 Godot 残留。产物在 `%TEMP%/p1f-player-east-ocean-frames`，标 `generated/rebuildable`、非 pixel golden。UX 留债是 manifest id / 可否卸货尚未显式告诉玩家；这是下一产品纵切，不在进程治理棒中顺手改 UI。

### 13.5 P1-g：可回滚进口事务 + 玩家港口状态（2026-08-12）

- **事务闭环**：每次成功卸货以 `cargo_unload/<manifest_id>` 作为确定 txid，把 `pay(import*N) → import stock → cargo_unload receipt` 三条相邻回执绑定到同一 manifest/node/good/qty。付款后、入库后、货单完成后或回执后任一注入故障，都会把钱、库存、货单、event_log、next event id 与滚动 digest 精确恢复；工资仍是 cargo 成功后的独立 best-effort 事务。硬 #44 已升级为 txid/顺序/数量/manifest 完成态的对抗门。
- **玩家可读状态**：玩家站在 `port_dock` 三格内时，顶栏显示最早 ready manifest 的货名、数量、状态（待卸/卸货中/仓位不足/镇库不足）和负责码头工；它是 Sim 权威货单的只读投影，不新增玩家假按钮。seed3 tick580/600 显示「柴薪×4 待卸·阿涛负责」，tick620 显示「卸货中」，船、货箱、玩家、七项动作、事件日志与时间轴同框可读。
- **证据/边界**：focused 四故障点与 mutation 牙全绿；标准 `12/12`、held-out `18/18`、total N24 `12/12` 硬 #44/#45/#46 全绿，三格 import/export provider 全 seed 非真空，det3/3/1。三张真实 Windows/OpenGL 帧由监督器生成在 `%TEMP%/p1g-player-east-ocean-frames`，非 pixel golden。完整合同、receipt、失败记录与恢复命令见 `analysis/p1g/manifest-transaction-player-ux.md`。append-only manifest 压缩与 golden/modelpath/complement finalize 仍是后续交付项。
- **Review / Git / hygiene**：最新成功 completed review 仍为 2026-08-11 21:00 CST / REQUEST CHANGES；其后的 09:00 review 因模型容量失败，不构成新产品判决。本棒直接关闭其“遗留 Godot 污染后续证据”P0，但 txid/rollback、manifest compaction、scale authority、affiliate membership、East Ocean warehouse/portal/nav/culling 与三锚/exact-tip 仍未关闭。PR #6 保持 draft；不重烘 golden/modelpath/complement，不改 README/受保护分支，不 archive/clean unknown-owner worktree。旧 raw local Godot 脚本记 `legacy-supported`，后续按脚本逐个迁移并补退出码牙，不做无验证批量改写。

### 13.6 P1-h：完成货单退休 + event-only 审计 + backlog UX（2026-08-12；未重烘）

- **单一目标 / 权威边界**：关闭 §10.9 留下的 `cargo_manifest_order` 随存档年龄线性增长。成功卸货仍先完成 P1-g 的相邻 `pay → import stock → cargo_unload` 回执，再把 `complete/remaining=0` 记录从 manifest dictionary/order 同时退休；live queue 只保留会驱动未来候选、货船和 HUD 的正数 ready 单。`after_retire` 成为第五个注入故障点，可把钱、库存、事件、digest、manifest 和原序位全部恢复；order 悬空时 fail-closed，不静默擦货。
- **硬门 / 存档**：#44 改为由唯一 `cargo_arrive`、authored route/lane/batch 与 exact tx receipt 反向证明完成历史，不再依赖永久 live tombstone；arrival 必须属于 live pending 或已完成 tx，重复 order、错误 route、不可溯源单据均红。旧 P1-g schema-2 档中的 complete record 只在 prepared copy 内、凭 canonical id + authored lane + 唯一 arrival + 相邻 tx 证明后退休；缺证据/篡 id 均在 apply 前原子拒绝。schema 仍为 2。
- **有界证据 / 行为 no-op**：focused 33 天连续完成 11 单，每次 live queue 都回到空，11 单仍全部由 event history 审计。与 P1-g 标准格逐 seed 对拍，12/12 的 `digest/event_digest/events/pass` 精确不变，只有纳入未来驱动态的 `chain` 按预期变化。候选树 standard、held-out、total-N24 均 S0 PASS；三格真实 import/export 分别 `156/57`、`252/59`、`167/82`，#44/#45/#46 全绿且非真空。这里约束的是 manifest 权威面；全局 append-only event log 的历史增长仍是既有独立保留策略，不在本棒伪称解决。
- **玩家 / UI / UX / 美术参照**：港口状态与货船共用 ordered live queue；多单时顶栏在最早货物后补 `共N单M件`，单单路径逐字保持简洁。carrier focused 证明三单时一艘船 + HUD/船同为 `3单/12件`，首单完成后 FIFO 重绑，退休 tombstone 不改变投影。真实 Windows/OpenGL 玩家帧固定 seed3/tick600/[58,8]，同框保留船、货箱、玩家、责任提示、事件、需求/钱、七动作与时间轴；没有为好看伪造 backlog。PNG 在 `%TEMP%/p1h-player-east-ocean-frames`，`generated/rebuildable`、非 pixel golden。完整合同见 `analysis/p1h/manifest-live-queue-compaction.md`。
- **停止条件 / delivery gate**：focused 与三组网格通过后才允许主题提交；提交后还须在 committed exact tree 重跑并 normal-push 当前接管分支。golden/modelpath/complement 仍 stale，review 尚未给新 completed 判决，PR #6 继续 draft/不可合并。本棒不改 README、protected branch、anchor 文件，不 archive/clean unknown-owner 内容。

### 13.7 P1-i：可进入的东海货仓 + 玩家连续视觉回执（2026-08-12/13；未重烘）

- **可玩纵切**：东海码头 `[57,8]` 的货仓门现在双向连接 `port_warehouse/1f`（9×6）。玩家站在门边点击即可用真实 player agent 进仓、受室内导航网和家具碰撞约束，再由右侧木门返回东海；远处点击仍保持 Probe 观察语义。室内不新增 advert/job/production/RNG/economy 权威。
- **状态可读**：墙上「东港到货簿」直接投影 `town_stock` 的柴薪/豆子/口粮与 `cargo_status_for_node("port_dock")`，显示货名、数量和待卸/卸货中/仓位不足/镇库不足；无缓存、无复制货单。东向码头同时修正 deck 与 carrier 独立裁剪，并恢复豆子货袋，让船、仓门、货箱和库存反馈组成同一玩家 affordance。
- **验收**：`audit_map` 锁定门、地类、室内材料与 display-only 家具；`space_test` 锁定真实进出、墙体碰撞、可走地毯与返回；玩家 UI/save/P1-a/P1-b/P1-c/P1-g focused scenes 均绿。标准 seeds 1–12 ×60d 为 S0 PASS，hard/soft 12/12、#40/#44/#45/#46 12/12、真实 import/export `156/57` 覆盖全 seed、det3/3；未传 golden。
- **视觉负控 / presentation pool**：固定 Godot 4.6.2、seed3、tick600、player `[57,8]` 的 ON/OFF 对拍为 56,048 变化像素，bbox `(512,156)-(778,367)` 全落在状态板 crop `(505,147)-(784,371)`。两张 1280×768 玩家帧已入 `docs/media/p1i_east_ocean_{player,warehouse}.png`；它们是可重建 presentation receipt，不是 pixel golden。完整命令、SHA-256、来源/许可证与边界见 `analysis/p1i/east-ocean-warehouse.md`。
- **delivery gate**：P1-i 不改变贸易权威，但 `game/`/空间/View 变化仍令 complement freshness 与旧 visual assumptions 漂移。本棒不重烘 golden/modelpath/complement，不把本地 pinned GL green 冒充 GHA visual receipt；PR #6 继续 draft，等待 committed exact-tip CI、三锚 finalize 与新 review 判决。

### 13.8 P1-l：schema-2 完整权威字段合同（2026-08-13；未重烘）

- **根因 / 红测**：P1-e 的 current-schema 校验只手列 17 个 required state key；从真实 schema-2 档删除另一个权威字段 `festival_active` 后仍可加载，并保留 quickload 接收实例的污染值。envelope 的 `active_commit_ids` 缺失也会默认为空，使同一档依赖 receiver/工作集历史。
- **合同**：`_current_save_state_keys()` 复用保存器同一套 script-var 反射与 `SAVE_LOAD_DENY` 排除策略；schema 2 的 state 必须与保存器实际字段集合逐项精确相等，current envelope 也必须精确含九个协议键。缺/多任一字段均在触碰 live Sim 前 fail-closed。schema 1 仍走显式迁移，不被强迫伪装当前 shape。
- **牙齿 / 资源池**：focused test 对真实 current save 的每个 state key 做逐字段 deletion mutation，并用完整 envelope 证明缺 `festival_active`、缺 `active_commit_ids` 都原子拒绝；污染 receiver 的 cargo/order/core/festival/digest 均保持不变。exact d46 fixture、P1-a ghost gate、schema-2 roundtrip/续跑、runtime handles 与 cargo/population 负控继续保留。完整接口与边界见 `analysis/p1l/schema2-complete-state-contract.md`。
- **产品与视觉边界**：本棒只收紧存读档 codec，不改变玩法/UI/UX/美术/地图/帧输出；P1-i 的玩家/仓库实帧继续是 visual reference，无 changed presentation property 可由新截图验证。本棒不重烘 golden/modelpath/complement，也不解除 PR Draft 与 review delivery gate。

### 13.9 P1-m：writer/fixture 对齐 + 本地判决 fail-closed + 玩家三帧回执（2026-08-13；未重烘）

- **CI 根因与修复**：PR #6 的 `31653814665` 首个新代码红是 P1-g fixture 要求严格 schema-2 writer 写出被篡改的 complete manifest id；writer 拒绝本来正确。fixture 现在先断言 live writer fail-closed 且不留半文件，再只对一份合法 store-var envelope 做离线单字段 mutation，loader 仍须原子拒绝；`Sim.gd` 不降级。
- **监督器 v3**：Windows Godot 曾在打印 `p1g_manifest_transaction_test: FAIL (1 fail)` 后返回 OS exit0，使 v2 本地假绿。canonical supervisor 现识别标准 `*_test: FAIL` / `... GATE: FAIL` 终态并转成 `logic_failure_pattern/72`；永久零退出红控、正常 focused、timeout、并发 owner、dirty 拒绝和 source-drift/79 牙齿全部通过，v2 的 source fingerprint/cleanup 合同完整保留。
- **分层验收**：save/load/state projection、P1-b/c/d/g、space/player/static gates 全绿；标准 12-seed hard/soft 12/12、held-out hard 18/18（#40 17/18 达门）、total-N24 hard 12/12（#40 11/12 达门），三格 #44/#45/#46 与 determinism 全绿，N24 import/export `167/82` 覆盖 12/12，均为同一稳定 candidate 指纹且未传 golden。
- **玩家位置 / presentation**：固定 Godot 4.6.2、seed3、tick600、player `[57,8]` 真走“东海外景→货仓1F→返回”；返回帧与出发帧逐字节相等、内景相对外景变化 98.59%。ON/OFF 56,048 像素差全部落在仓库状态板 crop，肉眼同框可读玩家、船/货箱、仓门、到货簿、三类库存、HUD、需求/钱、时间与交互。帧 hash 与已跟踪 P1-i presentation pool 精确一致，故复用、不复制；完整命令、receipt、SHA-256、许可、边界和恢复见 `analysis/p1m/schema-writer-supervisor-player-proof.md`。
- **delivery/hygiene**：本棒不重烘 stale golden/modelpath/complement，不把本地 pinned-GL 冒充 GHA visual receipt；PR 继续 draft，等待 committed exact-tip CI 与独立 finalize。README/首屏 demo、protected branches、unknown-owner worktree 均未触碰；无 archive/clean。

### 13.10 P1-n：预期拒绝也必须成为受约束日志（2026-08-13；未重烘）

- **问题**：PR #6 run `31659112066` 中 P1-g 行为断言最终 PASS，但三个 arrival tombstone 负控与一个 writer 负控各自正确 `push_error`，通用 runtime sentinel 因没有 owning-scene 合同而把四条全部当成未解释错误。它不是产品 guard 红，也不能靠忽略 stderr 或把 `push_error` 降级成 warning 修。
- **合同**：`scan_exact_once_set` 要求每个声明的错误 family **各恰好一次**，过滤后任何第五条 `ERROR` / `SCRIPT ERROR` 仍红；缺一、同族重复替代另一族、额外错误三类负控全部自测。P1-g 与 state projection 是两个既有消费者，故抽取边界成立；`Sim.gd`/数据/不变量零改动。
- **候选证据**：canonical supervisor 下 P1-g、state projection、save migration 均 PASS 且 source stable/cleanup verified；前两者的四族拒绝逐项 exact-once、未声明 runtime error 为零。P1-m 的标准/held-out/total-N24 无 golden 网格继续适用，因为本棒不改仿真权威面。玩家位置再次从 exact HEAD 重建东海外景→货仓→返回三帧及 8 秒 H.264 短片，tracked P1-i 图 hash 不变；同时诚实记录 dossier 压返程门、无 NPC 时仍显示社交动作等后续 UX 债。
- **边界**：本棒不重烘 golden/modelpath/complement；Draft PR 在 committed exact-tip CI 和独立重烘协议完成前仍不可合入。完整根因、失败路线、命令、receipt、视觉/许可/恢复见 `analysis/p1n/expected-runtime-error-contract.md`。

### 13.11 P1-o：pending manifest authored-lane 权威 + 玩家异常态（2026-08-13；未重烘）

- **单一合同**：pending/complete manifest 不再只证明自身字段自洽；唯一纯 validator 严格绑定存档/运行时自己的 import lane、canonical route×day×lane id、whole batch、价格与 cadence/future-day。arrival、schema-1/2 load、complete compaction、卸货候选、atomic commit、硬 #44、HUD/仓库与 carrier 共用它；任何坏单都在钱/库/事件前 fail-closed。
- **玩家语义**：坏单不伪装成 empty/ready，也不泄露不可信 good/qty/cost/worker；外景零货船，HUD/仓内统一显示“货单异常·暂停卸货”。valid→corrupt 玩家对拍固定 seed3/tick600/[57,8]：外景变化 26,931 px（船+提示）、仓内只改状态板行 3,046 px；两臂都真实进仓返回且 town 前后逐像素相同。判据已接入 visual gate，不把本地 pinned GL 冒充 GHA receipt。
- **牙与回归**：P1-g 覆盖 12 个单字段/类型负臂、offline schema-2 原子拒绝、future/cadence、arrival accepted/target/note；每臂要求零候选/commit/副作用、#44 红与恢复。P1-b/P1-c/save migration/state projection 均绿；标准 12×60d det3 hard/#40/#44/#45/#46 全 12/12，import/export `156/57` 覆盖全 seed，det3/3。
- **边界**：这是存档内部合同而非密码学签名；同时篡 lane 与 manifest 的 provenance 另议。完整接口、receipt、presentation 来源/许可/恢复见 `analysis/p1o/manifest-authored-lane-authority.md`。golden/modelpath/complement 不重烘，PR #6 继续 draft。

### 13.12 P1-p：统一传送门权限事务 + 玩家拒绝实帧（2026-08-13；未重烘）

- **单一交付**：移除接受任意 portal 字典的原始传送面，把 Main 玩家点击和 NPC journey 统一到 `Sim._try_traverse_portal`。边界从 actor 当前 plane/位置重新解析 authored edge，自行派生玩家相邻/NPC 端点规则，验证 access、owner、方向与两端导航后，才原子提交地址、路径缓存和一次 transition signal。
- **真实反例已关闭**：schema-2 中伪造 player home、伪造当前 cafe/2f plane、或只把保存的 owner portal 改为 public，过去都能经真实 UI 越权；现在保存的 spaces/portals/homes/agent address 必须精确满足 authored graph 与可授权可达域，`peek/load` 在触碰 receiver 前拒绝。静态数据门同步拒绝未知 access、错类型、越界/重复端点和无效 owner。
- **至少十二步闭环**：上下文/review 对账、四条反例、事务设计、authored graph、双调用方、原子提交、current-schema 验证、负控矩阵、正向/Probe 纠偏、分层回归、exact 玩家实帧、Lore/Git/PR 收口全部属于同一权限纵切；不把无关 UI 重构拼入本批。
- **玩家呈现**：seed3/tick600/player `[57,8]` 的真实点击正向仍复用 P1-i 两帧；新增 `docs/media/p1p_portal_denied.png`。拒绝臂保持 player/Probe/camera/cargo 精确不变，画面明确显示“东海货仓：私人区域，未获通行许可”，7,191 个变化像素全部位于反馈区。反馈仍只在左下 feed、室内返程门受 HUD 挤压，诚实登记为后续 player-shell polish 债，不在本批用假 toast/离线合成掩盖。
- **验证/边界**：portal/save/projection/cargo/player focused 与 standard 1-12×60d det3 no-golden 均绿；exact committed-product-tree framebuffer 绑定 `a48ee58`。最新 completed review 冻结 tip 落后且仍为 REQUEST CHANGES，托管 exact-tip CI 需在 push 后重新取证；golden/modelpath/complement 未重烘，PR #6 继续 draft/不可合并。完整合同、SHA、runner digest、receipt、来源/许可、限制与恢复见 `analysis/p1p/portal-traversal-authority.md`。
### 13.13 P1-q：portal JSON 数值跨平台一致性（2026-08-13；未重烘）
- **根因/修复**：P1-p exact tip 的 GHA run `31690429941` 唯一新产品红为 Linux `space_test: 1 fail`；隔离复现证明 canonical JSON 的整数文本在 Linux Godot 被解析成精确 integral-float，P1-p runtime validator 却硬要求 `TYPE_INT`，于是十一条 portal 的 cost/pos 被整批误拒。SpaceGraph 现按数学值接受 int 或 finite integral-float，仍拒 string、fraction、NaN/inf 与非正 cost，不靠有损 `int()` 放行。
- **牙/验证**：cost/pos 两条 integral-float 正臂，fraction/string/zero 五条负臂与 canonical restore 全绿；Windows exact supervisor、pinned Linux archive、P1-g/save migration/state projection、lint/map、standard 1-12×60d det3 no-golden 均绿。玩家 seed3/tick600/[57,8] 真实往返继续 town 前后 0 px、室内差 98.59%，两张 canonical 图 hash 不变。
- **边界**：不改 portal access/owner/atomic commit 语义，不改 README/美术/数据/锚；最新 completed review 仍冻结在 P1-p 前，PR #6 必须保持 draft，push 后等待新 exact-tip hosted receipt，stale golden/modelpath/complement 仍独立阻断。完整 provenance、命令、receipt、限制与恢复见 `analysis/p1q/cross-platform-portal-number-contract.md`。

### 13.14 P1-r：exact-tip 非锚点闭环 + anchor-finalize readiness（2026-08-13；未重烘）

- **hosted 终态**：PR #6 run `31694970713` 精确绑定 head `b0a501b` 与 synthetic merge `233f82c`（parents=`d46cbb1+b0a501b`）。Linux `space_test` 与其余 15 个 focused scenes 全绿；全日志恰好四个 `FAIL:`，仅为 complement stale、S0 golden、DetGate golden、ModelPath anchor。P1-q 的跨平台 blocker 因此关闭；GHA visual 仍为未 pin Mesa 的显式 SKIP，不能冒充 hosted 图证。
- **post-tree 网格**：exact game-tree `d366811` 的 held-out `13-30×60d×det1` PASS（hard `18/18`、#40 `17/18`、#44/#45/#46 `18/18`、import/export `252/59`）；正确 total-N24 使用 `--total-agents 24` 并逐行钉住 `{core:23,total:24}`，PASS（hard `12/12`、#40 `11/12`、#44/#45/#46 `12/12`）。旧 `--agents 24` 实际是 core24/total25，只保留为兼容诊断，禁止再称 N24。
- **ON/OFF 牙齿**：新增可复用只读 probe `analysis/p1r/logistics_arm_probe.gd`，只复制进隔离 archive。total24 ON 臂逐 seed 要求 arrival/import/export/unload 全非零，12 seed 合计 `240/167/82/167`，四族覆盖均 `12/12`；OFF 臂只在验证绝对路径位于 `%TEMP%` 后移除该副本 `logistics.json`，3 seed×两跑的四族/manifest/order 全为零、摘要确定、#44/#45/#46 条件式绿。
- **R12 pre/post 与停止条件**：complement 锚旧 game-tree `eabcb07` 可达 `366e37f`；同口径 held-out 旧树 PASS（hard/#40/#44/#45/#46 `18/18`、import/export `357/87`，完整 log SHA `c3877795...cb172`）。37 个 game path、约 `+5908/-771` 行把直注入贸易迁为 P1-a–q 的真实 manifest/卸货/保存/权限纵切，故锚漂移可解释；但最新 completed review cutoff 仍落在 P1-o/p/q 前且为 REQUEST CHANGES。依 R12，本批不写 Harness/DetGate/ModelPath/complement 任一锚，PR 保持 draft。恢复触发器是覆盖本 committed tree 的 fresh review，再用单一 committed exact tree 做四锚 finalize + hosted CI。完整矩阵、receipt、限制与恢复见 `analysis/p1r/anchor-finalize-readiness.md`。

### 13.15 P1-s：hosted exact-tip receipt + fresh-review handoff（2026-08-14；未重烘）

- **不可变身份**：PR #6 run `31701895953` 自身冻结 head `614ec14`；synthetic merge `a688b1c` 的 ordered parents 正是 base `d46cbb1` / head，且 head 与 merge 的 `game/` tree 均为 `d366811`。可复用 `analysis/p1s/verify-exact-tip-delivery.ps1` 默认验证 run-head、PR 号、merge parents 与 terminal jobs；`-RequireLivePr` 另加 mutable live-head/base 牙。GitHub run API 的 `pull_requests[].head/base` 实测会随 live PR 漂移，故不充当 immutable snapshot。
- **hosted 终态分类**：run/job 均 terminal `failure`；270,836-byte 完整日志 SHA-256=`1871dd21...9061`，恰好四个 `FAIL:`：complement stale、S0 golden、DetGate golden、ModelPath anchor。其余 16 个 focused scenes、BackendGate、runtime exact-set scanner 及 state-projection 十二族 writer 拒绝均绿；没有第五个 product/infrastructure failure。GHA visual 仍因 Mesa 未 pin 而显式 SKIP。
- **review sync / stop**：21:10 review 已冻结 `614ec14` 并确认 P1-m/o/p/q 旧阻断关闭；其尚未完成的对抗判定把“机械具备受控重烘条件”与“产品语义已冻结”分开，当前指出 East Ocean draw↔nav、仓库观测室/活仓库里程碑选择与跨 plane 社交边界仍需裁决。进行中意见不是批准，因此本批不写 Harness/DetGate/ModelPath/complement 任一锚，PR 继续 draft/不可合并。
- **恢复与 hygiene**：完整 hosted 分类、正/负 verifier 牙、fresh-review 输入与限制见 `analysis/p1s/exact-tip-delivery-handoff.md`。恢复触发器是覆盖 `d366811` 的 completed 独立 review；若仍要求产品修正，先闭合新 blocker，再重新取 exact-tip CI。README/首屏 demo、protected branches、unknown-owner worktree、golden/modelpath/complement 均未触碰，无 archive/clean。

### 13.16 P1-t：社交事务 plane authority（2026-08-14；未重烘）

- **真实缺口**：玩家在同一平面跨 area 边界贴身时，`player_act` 的“同区或距离≤2”先放行，`_apply_social` 又只按 area 拒绝，形成假放行；反向的对抗臂里，只要不同 space/floor 的缓存 area 碰撞，apply/advance/commit/mediate 又会把 plane-local 坐标当成同一地点并改写关系、记忆、冲突与事件账本。
- **单一合同**：复用既有 `_same_plane`，新增 `_socially_reachable` 统一“先同 plane，再同非空 area 或距离≤2”。玩家入口、外部 intent apply、计时推进、最终 commit 共用它；调解要求玩家与两名当事人同 plane 且仍保留原本同一非空 area 的更严范围。NPC 候选仍走已经 plane-aware 的 `_nearby_agents`，默认无玩家轨迹不变。
- **牙与 exact 证据**：P1-t focused scene 覆盖 cross-space/floor cache collision、入口/apply/advance/commit/mediate 原子拒绝、跨 area 贴身正臂、距离负臂与恢复正臂，修前 9 fail、exact commit `6f6c5e1` 后 16/16 PASS。标准 `1-12×60d×det3` no-golden exact receipt hard/soft/#40/#44/#45/#46 全绿、17 类活性存在、det3/3；其 stdout 与候选网格 SHA-256 完全相同。完整矩阵、receipt、SHA、失败教训、来源/限制/恢复见 `analysis/p1t/social-plane-authority.md`。
- **review / stop / hygiene**：本批只关闭 21:10 进行中 review 指出的跨 plane 社交边界，不把未完成评审当批准；其余 draw↔nav 与仓库里程碑选择仍开放。README/首屏 demo、protected branches、golden/modelpath/complement、unknown-owner worktree 均未触碰，无 archive/clean；PR #6 继续 draft，等待 completed review 与本 tip hosted 分类。
