# 154 · E2 §0.8 双路对抗评审结论（钱跨镇边界 / external_coin / #34）

> docs/41 §0.8 要求核心不变量口径变更前**两路独立评审收敛**。① 外审=GPT-5 Pro（chrome，思考 2m51s，被要求 REFUTE）；② 内审=5-critic refute workflow + 综合。**两路已收敛**。用户 2026-08-08 指示"finish §0.8 review and E2 first"。

## 〇、收敛判决：**SOUND_WITH_FIXES —— E2 import-付费首片可实现，绑定下列 fixes**
两路一致：**external_coin 收进 #34 守恒集在忠实实现下算术恒真**（`Δmoney_total=−amt+amt=0`），#34 对 E2 引入的裸 sink / 漏贷 bug 保留判别力（内审 3 条 #34-refute 全失败、code-verify；外审独立给同一归纳证明）。⇒ **方案对，但绑定 blocker + fixes 先落。**

## 一、★两路独立命中的同一关键缺口（最有价值的产出）
**#34 的"总和守恒"证不出"transfer 是唯一钱通道 + 可逐字节回放"。** 直写 `a.coin-=10;b.coin+=10`（或把钱转给**错的**买卖方）⇒ #34+#35 全绿、无事件、账本不完整。
- 内审叫 **#45（付费溯源）**：这笔 town→external 须对应一次合法 import 且 cost=price_per×applied。
- 外审叫 **#36（账本完备性，更 principled）**：`live_balance(account) == fold(opening_snapshot, all_money_events)` **逐账户**（非仅总和——正常转账总和本就恒定、零判别力）。抓：直写钱 / 漏写事件 / 金额不符 / 收付款方写反 / 事件双应用 / reducer 与运行时逻辑分叉。**这正是 #38 给 stock 的完备性，而 money 现在缺。**
⇒ **收敛结论**：钱系统缺一条完备性不变量。#36（逐账户事件折叠）是理想终态。

## 二、Blockers（落地前必修，两路 code-confirmed）
1. **external_coin per-run 重置（硬红线#1，2 critic 独立命中）**：`town_coin` 回放安全来自 `Sim.gd:836` start_new 每局重赋值、**非 :271 声明默认**。goto_tick(:1158) 反复调 start_new，import 付费让 external_coin 局末非零 ⇒ 第二遍残留污染 `econ_total0`(:838) 快照 ⇒ 整局 money_total 位移、非逐字节，且 #34 因两侧同带残值可能**反把 bug 盖绿**。**必须在 :838 前镜像 :836 加 `external_coin = 0`。** docs/151 §六 自认未验证——现文实现=坏的。
2. **完备性不变量决策**：加 **#45**（import 付费溯源，守新流，invariants 35→36、同步两份 HARD_IDS、ledger 按 36 重烘）**或**显式**deferred 到具名 E2b**（以 §二 applied 回喂 + §四.1 负对照为过渡守护）。**不能停在 candidate。**

## 三、Required fixes（落地同棒）
- `money_total()` 真正 `+external_coin`（Sim.gd:3257）+ `_coin_of`/`_set_coin` external 臂**三处同棒**（任一漏接 ⇒ "正确 import" 与 "§四.1 漏贷负对照" 产生同一个红、不可区分）。
- **#35 补 external 非负臂**（`and external_coin>=0`，Invariants.gd:609，对称 town）——首片单调增暂不可达，零成本、防 export/选项B 时凭空铸币。
- **off 门 2 轴矩阵**：付费挂点显式 `_econ_on()`+price_per 存在守卫 ⇒ logistics ON+economy OFF 回到 E1【免费到货】逐字节；拍定 price_per 落 economy.json 还是 logistics.json。
- **price_per 标定 + import 到货活性**：logistics.json 现无 price_per；盈亏平衡≈0.8（town_start=60 定值不随人口缩放），price_per≥1 使 town_coin 单调→0、后 1/3 局 import **静默断供**而无门断言"进口必须到货"（#40 供给底 0.609/0.650>0.5 不会红——**静默死于无门比红门更危险**）⇒ 标不饿死 N=12 金标的 price_per + 加 import 到货/wages_skipped 活性监测。
- **读 `_stock_move` 返回 applied 件数算 cost**（当前 3691 丢弃返回值），避免撞 cap 少收时多付/买空气。
- **重烘三锚**（golden+modelpath+ledger，pay 事件进 event_digest ⇒ modelpath 必移；加 #45 则 ledger 按 36 重烘+同步 HARD_IDS）。

## 四、GPT-5 Pro 额外（前瞻，多 export/多镇才需，记档不阻塞 import 首片）
- **守恒域=全经济区（多镇），非单镇**：遍历**账本账户注册表**（`Σ ledger.accounts[id].balance`）而非场景"镇+居民"（居民迁镇会双算/漏算/随实体销毁丢余额）。external_sector 是"外部世界"这一档的正解（=external_coin）。
- **coin 别当居民实体自由可写字段**：集中进 MoneyLedger + 源码门禁 `.coin=`/`+=`/`-=`（一棒一棒 workflow 易在未来某棒重引直写）。
- **event-first 单 reducer**：append 事件 → 运行时与回放调**同一** `_apply_money_event`（避免两套逻辑漂移）。
- **transfer 契约补边界**：拒 amt<=0 / from==to / 账户不存在 / from<amt / 整数溢出；成功=恰一事件+恰两账户变。
- **账户 create/delete/migrate 规则**：新账户零余额、初始资金经 transfer（禁隐式铸币）；销户须零余额或先转出；迁镇只改归属不改 account_id。
- **贸易原子性（#38-trade）**：钱守恒但货没动=假成功 ⇒ TradeExecuted 事件原子应用钱+货，或显式 escrow/在途态（escrow 也进 money_total）。
- 外审建议终态不变量集：#34(全域守恒)/#35(全账户非负)/#36(账本完备逐账户)/#37(转账原子性)/#38(贸易原子性或显式在途)。

## 五、E2 实现计划（本次落地）
E2a import-付费首片：② blockers（external reset + #45 决策）+ ③ required fixes 全落 → 重烘三锚。**#45 决策**：首片加**最小 #45**（import 付费溯源：actor 须声明 node、cost=price_per×applied）守新流；**#36（全 money 逐账户完备性）作 E2b 具名后续**（GPT-5 Pro principled 终态，含 event-first reducer + MoneyLedger 重构，是更大一片）。export 侧全部（社交排除集/分布通胀/#38-trade/多镇域）= P4 deferred，别带进 import 首片。
