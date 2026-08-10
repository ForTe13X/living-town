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
