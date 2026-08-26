# 144 · 经济/物流系统设计提案（车道 E · item②③④）· 只读 scoping

> 用户 2026-08-07 拍板扩展：运输→外部供给(设无限)→多元产业→居民 consume/produce/create→自给自足→进出口→self-contain。**只读读码提案，未跑 CI/真机**；行号实读于当前 HEAD、以 git 为准。

## 〇、核心纠偏：经济基础设施**已存在且成熟**——车道 E 是"给已有账本接外部边界 + 加厚产业链"，不是造经济
- **镇级物资池已在**：`town_stock`（`Sim.gd:305`，整数件数），唯一通道 `_stock_move`/`_stock_take`（`Sim.gd:3325/3438`），硬不变量 **#38**（`Invariants.gd:671`）能从 event_log 独立重算它。⚠️#38 有"账外货"臂——不在 `production.goods` 表里的 town_stock 键立刻判红。
- **钱通道已在**：`transfer`（`Sim.gd:3204`，唯一通道）+ **#34** 金钱守恒（`money_total()==econ_total0`）。
- **产业链已在**：`produce[职位]={good,amount,inputs?}` + `_produce_for`（`Sim.gd:3363`）支持多原料 + 按最紧原料整数缩水；现有一环=柴薪→(泥瓦匠)→屋瓦。
- **消费已在**：`consume[动作]={good,amount}` + `_consume_for`（`Sim.gd:3418`），缺货不阻断、落社会后果 `_shortage_fallout`。
- **≤60 缩放已在**：K1 池 `_pool_rescale`（整数有理数）；供需感知 `_stock_pull_mult`/`_work_pull_mult`。
- **人→人买卖已在**：vendor 分支（货 `_stock_take` 出、钱 `transfer` 进个人）。
⇒ **reuse-first：worksite/money/stock/consume/池化/缺货后果一根不重造。** 真正新东西只两样：① **跨镇边界**(import/export) 的货+钱通道；② 更多 goods/产业链环。

## 一、数据模型（新增最小）
- **新货 = `production.goods` 加一条**（自动继承 #38 账本/#40 供给/缺货后果/K1 池；必须先声明、只经 `_stock_move` 动）。
- **多元产业 = 多加 produce 环 + goods + worksite + job**（照抄泥瓦匠形状，`_produce_for` 一行不改）。例：小麦→(磨坊)→面粉→(面点)→口粮；原木→(锯木)→木板→(木工)→家具。
- **运输节点 = outdoor 对象（worksite 家族）；货物流 = 抽象整数注入，不做空间搬运**（逐车空间搬运违背 K1 宏观池哲学 + 撞 60 人/tick 预算）。新文件 `logistics.json`（off-gate：缺文件⇒逐字节回到今天）声明 import/export lane + node。
- **"外部无限供给"的确定性定义**：import lane 每到期日 `day % every_days==0`（纯 `f(day)`）`_stock_move(good,+batch,"import",node,reason)` 注入镇库，撞 cap 少收（同 spoil）。**无 RNG/Time/浮点 ⇒ 逐字节可回放。**
- **居民 create（个人手作/送礼）= 需个人 goods inventory**（现在只有 `inventory.coin`）——新守恒臂（个人货+镇库货=闭合），**最大的一片、放最后**（E5）。

## 二、移金标 & 重烘（用户已放行）
所有写 town_stock/town_coin 轨迹的改动移 digest/chain。重烘按 **docs/41 §3**：`Harness --bake-golden`（seeds）+ `DetGate --bake-golden`（scenarios）**都跑**、`_meta.rebake_history` 补条、**跑留出种子 13-30 改前/改后**证非过拟合。⚠️**docs/124 §〇.3 警告**：N=12 金标"没动"是**盲**不是验证（CI 恒 N=12，N=60 无门）——真验证靠 **N>12 离线干预 + 逐 seed 展布**。

## 三、增量顺序
- **E1（第一根，见 §五）**：一条 import lane，确定性到货一种已有货（建议柴薪）进镇库。**不碰钱（#34 全程不动）**，风险最低。
- **E2**：export lane（余量换钱）。**首次让钱跨边界 → 触发 #34 架构决策（§四.1），E2 前必须拍板 + §0.8 外审。**
- **E3**：第一条新产业链（磨坊环），验证多层链在池化下成立。
- **E4**：import 从"无限"改成"随本地产出替代而节流"（self-contain 弧引擎化）。
- **E5+**：个人 goods inventory → 居民 create/送礼（新守恒臂，最后做）。

## 四、风险 & 红线
1. **★钱跨边界 vs #34（E2 前必拍板，属架构改动须 §0.8 外审）**：进口付钱=钱流向"外部"=money_total 减少=#34 红。**推荐方案(a)**：加兄弟余额 `external_coin` 进守恒集，`transfer("town","external",cost)` 仍唯一通道，#34 结构不破（守恒集+1项）。**E1 完全不碰钱**、把 #34 改动单列为 E2 前置片。
2. **别把进口做成"永不变红的门"**：#40 是软门判满足率；无脑补齐所有缺货 → #40 灌绿失去判别力（docs/41 §0.5 点名的空门）。import 必须是**有限声明通道**（batch/every_days 上限），本地产能仍是满足率主因；加进口重跑 #40 探测包络。
3. **≤60 缩放**：新货必须进 `scale.pool` 字段列否则大 N 塌供；import batch 是否随人口缩放**未验证**。⚠️`_holder_of_title` 只返单个持有人——一个工种加第二人打中 #41 反向臂，多产业多人须先解。
4. **determinism**：调度纯 `f(day)`；禁 randi/randf/Time；随机只从 `_rng_at(salt,身份)`；缩放整数有理数禁 log/sqrt/pow。
5. **性能**：结算放**日界**（`_nightly`/`_stock_nightly`，一天一次），不放 per-tick。
6. **唯一通道**：import/export 必须经 `_stock_move`/`transfer` 写事件，让 #38/#34 能重算（否则判红=机检兜底，是好事）。

## 五、self-contain 弧（P1→P4）
| 阶段 | 引擎 | 可见目标 |
|---|---|---|
| P1 外部无限供给 | import 管够(E1)、本地产业稀薄 | 码头/车站到货动画 + HUD"今日进港" |
| P2 内部产业替代 | 加产业链(E3)、本地产出升 | 玩家建/招工新产业、本地产出占比爬升 |
| P3 自给自足 | import 对核心货节流到 0(E4，判据=本地某货连续 N 天不缺) | "本镇已自给"里程碑事件（喂 voice grounding）|
| P4 出口余量 | export 把 surplus 换镇库钱(E2) | 出港 + 镇库财富涨；余量成收入而非丢弃(今天满仓 spoil) |
每阶段转换=一条 storylet 种子（衔接车道 N）；**转换判据只由已提交仿真态(town_stock 历史)得出、纯 `f(仿真态)`**。

## 六、E1 第一根经济棒 brief 底稿
- **owns**：新增 `game/data/logistics.json`；`Sim.gd`（import 原语+日界钩子+off-gate+node 编译）；`Invariants.gd`（**#38 认 import 事件**——把 "import" 加进 +delta 集；建议加 **#44 进口溯源**：actor 须声明过的 node、good 须声明过的 lane 货，对称 #39）；重烘 `golden_digests.json` 两段。**不碰钱/economy.json/#34。**
- **做什么**：`logistics.json` 一条 import lane（柴薪，澡堂唯一燃料+屋瓦原料、供给紧），日界 `_nightly` 里 `day%every_days==0` `_stock_move("柴薪",batch,"import","port_dock","import")`；node 经 `_compile_worksites` 同族进 world.objects（区域 dock）。
- **测**：① off-gate（无文件→12/12 逐字节同现 golden 含链）；② 两跑一致；③ #38 绿 + 负对照（绕过 import 事件直写 town_stock→#38 红）写进探测包络；④ S0 重烘后 PASS（两段 bake + rebake_history）；⑤ 留出 13-30 改前/改后逐 seed 展布（柴薪/屋瓦满足率、洗澡缺货——进口柴薪松动这两条=蓄意行为变更，要说清）；⑥ N=16/24/60 各 ≥12 seed 报 #40（进口不该灌绿 #40）。
- **预期移金标**（town_stock 柴薪轨迹变，用户放行）。**若 digest 动了但解释不了→停下报别重烘。**

## 附：未验证/可能错（诚实）
纯静态读码、未跑 CI/bench/真机——所有"逐字节/移金标"是结构推断，E1 落地必实测证。import 是否随人口缩放、方案(a)是否真守 #34、create 对 #34/#38 耦合成本、节点做对象 vs Space（多镇通勤才需 Space/Portal，本提案故意不含）——均**未验证**。行号会随代码腐烂（docs/124 实测 brief 坐标漂过 85 行），以 git 为准。
