# 152 · E3-additive 设计提案：单环 treat 链（糕点→fun）· 只读探索

> 用户 2026-08-08："additive 路线继续、E3 先 explore"。**只读设计探索、未实现未改码**。行号腐烂、以 git 为准；"逐字节/移金标/标定值"是结构推断、落地必实测。

## 〇、推荐（单环 additive treat 链）
一个 **spare 居民**（coco/fei/qin 之一，现做零工、无生产职位 ⇒ 天然单持有人、不触 #41）当 **糕点师**，直接产新货 **糕点**（**无 inputs**，形状照抄 `咖啡师→豆子`）；居民经一个**新的 town 平面消费动作 `吃点心`** 把糕点当 treat 满足 **`fun`** 需求。**核心口粮/柴薪/屋瓦/豆子/话本/整洁 一字节不改。**
- **把用户候选①(面粉→糕点 2-hop)收成 1-hop**：砍掉"面粉"中间货。多层"货由货做"**已被 `柴薪→屋瓦`(inputs) 证过**，面粉证不出新东西、只增标定/金标移动/落带风险。全 2-hop 留作可选 E3b。
- **拒候选②(原木→木板→家具)**：家具消费方=个人 inventory(=E5"最大一片、放最后")或抢整洁 need，两条都不干净。

## 一、现状（实读）：5 need × 6 货
5 need：hunger/energy/social/fun/hygiene。6 货产/消/need 见探索原文。**无空 need**（每个都有 ≥1 good-backed 消费），但 **fun 有空档**：豆子/话本只在**室内平面**、克隆居民出不了 town ⇒ 需求不随人口涨、大 N 必"缺货绝迹"。⇒ 加一条**接 fun、落 town 平面**的平行 treat 货干净（need 不空但可加平行货；town 平面 → 需求随人口涨 → 大 N 池化不塌）。

## 二、不 gate 核心供给的证明（diff 只加不改）
`production.json` 内 6 个**新增键**（无一 MODIFY core）：
```
+ goods.糕点 {cap,spoil_per_day,blame:"糕点师"}
+ produce.糕点师 {good:"糕点",amount:A}   ← 无 inputs（不吃任何 core 货）
+ consume.吃点心 {good:"糕点",amount:1}   ← 接 fun,不接 hunger/hygiene/energy
+ jobs.<coco|fei|qin> {title:"糕点师",...}
+ worksites[+1] {type:【复用已在 OBJ_SLOT 的现有 type,如摊位/counter】,area:"plaza",advertises:[做点心+吃点心]}
+ start_stock.糕点 N
```
证明：① 原料不碰 core（无 inputs，core 的 produce.inputs 全表未动）；② 消费接 **fun** 不接生存 need（**刻意不接 hunger**——treat 当饭会抢口粮决策=貌似 gate 核心,禁）；③ 单持有人（spare 居民，不触 #41、不动现有 9 职位）。

## 三、确定性/池/off/无需新不变量
- **determinism**：整数 `_stock_move`/`_stock_take`，无 inputs 连缩水都不算，无 RNG/Time/浮点。
- **池自动**：`scale.pool` 是字段名列表、对所有货生效 ⇒ 新货 cap/spoil/start_stock/amount 自动按人口换尺度，`scale` 块不改。
- **off-gate**：⚠️`production.json` 在 `lint_data.py` REQUIRED ⇒ **不能像 logistics.json 删文件测 off**；off = **删掉这 6 个新键**→糕点零引用→逐字节回今天（"删 JSON 键即回滚"纪律，是**多键移除非单文件删**，brief 要对 reviewer 说清）。
- **★无需新不变量（additive 相对 E1 最大红利）**：produce/consume/stock 都是已有 typed 通道，新货自动被 #38/#39/#40 覆盖 ⇒ **HARD_IDS 不动** ⇒ 不改 `gate_fixture_audit.py` 副本 ⇒ **绕开 E1 收尾被咬的 HARD_IDS 坑**。

## 四、★核心门约束：新货必须"周期性缺"（定量心脏）
实读 #40：**安全带 = 满足率约 (0.5, 0.9) 且有若干缺货天**：
- `SUPPLY_FLOOR=0.5` 下限臂：rate<0.5 红 ⇒ 别标太紧。
- 上限臂"缺货绝迹"（`never_short*2>gated_n`）：新货**全年零缺货**→加第7货某 seed 4/7(8>7)红 ⇒ **绝不能标成灌满/从不缺**。
- `dead_goods` 臂：有产者却零消费→红 ⇒ **禁堆仓**（用户"不只堆仓"的机检兜底：treat 从不被选,CI 当场红）。
- demand≥20 且≥60 天才进判决。
- 标定照抄 G3 屋瓦：扫 worksite 吸引力 W + batch A + 吃点心.amount，落糕点 rate 到 (0.5,0.9)、**无现有岗位掉出改前展布**。

## 五、移金标 + 重烘 + 验收锚
- additive 仍移金标（糕点 town_stock 轨迹）但**无 starve 风险**（缺货不阻断、接 fun 不动生存核心货）。重烘**三锚**（golden+modelpath+ledger，docs/147 别漏 modelpath；tree-fresh 提交上重烘，见 [[complement-ledger-drift-verdict]]）+ rebake_history；**HARD_IDS 不动**。
- **★核心验收锚（additive 的本质）**：**口粮/柴薪/屋瓦 满足率应基本不动**（新动作接 fun 不接这三 need）——**若这三条动了=没做成 additive,停下查**。会动的是 整洁/豆子/话本(同 fun)消费略降=蓄意可解释。**#40 不灌绿**（糕点周期性缺、放松上限臂、下限臂靠标定守）。
- golden diff 每处须归到【糕点产/消 + fun 决策重排下游】；归不到就停别重烘。

## 六、最小落地片 brief（E3a）
- **owns 仅 `production.json`**（6 新键）；**不碰** Sim.gd/Invariants.gd/WorldView.gd/economy.json/#34。worksite 复用**已在 `OBJ_SLOT_BY_TYPE` 的现有 type**（alias budget bench5/counter4/desk2 已满、加新 type 借槽撞预算+越 WorldView 禁区）⇒ 零 WorldView 改动。
- **免费消费**（不接 vendor、不收钱）⇒ **#34 全程不动**。
- **测**：①两跑逐字节；②删新键→12/12 逐字节回 pre-E3a golden(纯加法)；③#38 绿+负对照;④#40 糕点进判决、rate 落带、不灌绿、dead_goods 不红;⑤留出 13-30:糕点落带+fun↑+**口粮/柴薪/屋瓦基本不动(核心锚)**+整洁/豆子/话本微降(可解释);⑥重烘三锚+全绿。
- 预期移金标（糕点轨迹+fun 下游,用户放行）。**归不到糕点及下游→停别重烘。**

## 七、诚实边界
纯静态读码未跑 CI/bench/真机；标定值(W/A/吃点心.amount)全未量（安全带、demand≥20、大 N 落带都要扫）；fun 拥挤对整洁/豆子/话本的压降未量；一个更低扰动变体=把新货挂已有无货动作 `闲聊(social)`（不加决策选项、需求=既有闲聊频率保证被用，但改既有动作语义、严格 reviewer 可能不认作纯 additive）——首片走"纯加新动作"。production.json 单文件 off 不可 CI 测、面粉(E3b)、export/#34(E2)、个人 inventory(E5) 均本片外。
