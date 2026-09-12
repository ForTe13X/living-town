# 151 · E2 设计提案：钱跨镇边界（import 付费 / export 收钱）· 只读探索

> 用户 2026-08-08 拍板"E2 先 explore"。**只读设计探索、未实现未改码**。行号实读于当前树、会腐烂、以 git 为准。所有"逐字节/#34 恒等/移金标"是**结构推断，须落地实测**。⚠️**E2 改 #34（核心不变量）= 架构改动，须 docs/41 §0.8 双路外审 + 用户拍板后才实现。**

## 〇、实读复核（当前树）
- 唯一钱通道 `transfer(from,to,amt,…)`（`Sim.gd:3230`）：`amt<=0`/`from<amt` 返 false（#35 非负结构保证），`_set_coin(from,-)`+`_set_coin(to,+)`+写 `pay` 事件。
- `_coin_of`/`_set_coin`（`:3242/3248`）：**只特判 `"town"→town_coin`**，未知 id（如 "external"）现在读 0、写 no-op ⇒ 现 `transfer("town","external",c)` 会**扣 town、钱进虚空、#34 红**（正是要改的点）。
- `money_total()`（`:3257`）= `town_coin + Σ agents.coin`；`econ_total0`（`:838`）= 开局 `money_total()` 快照；#34（`Invariants.gd:606`）= `money_total()==econ_total0`（econ_on 出货在场，活门）。
- **判例**：`Sim.gd:996` 玩家带钱入镇时 `econ_total0 += 玩家coin`，注释"钱不凭空出现"——**external 账户是同一哲学的常驻化**。
- money_total/econ_total0 的读者只有 #34 + 一处 soak 诊断 ⇒ 加 external 不牵动别的判据。

## 一、方案 (a) external_coin（推荐，唯一保住 #34 判别力的选项）
1. **数据**：world 级整数 `var external_coin := 0`（`town_coin` 紧邻，同族）。
2. **transfer 路由**：`_coin_of`/`_set_coin` 各加一条 `"external"` 分支（照抄 `"town"`）；**transfer 本体一字不改**。
3. **money_total**：`+ external_coin`（一行）⇒ `econ_total0` 自动含其初值 0。
4. **import 付费** = `transfer("town","external",cost)`；**export 收钱** = `transfer("external","town",revenue)`。
5. **#34 恒等证明（算术）**：守恒集 = `town_coin+external_coin+Σagents.coin`；transfer 每次只做集内 `from-=amt;to+=amt` ⇒ 集合总和是 transfer 的不变量 ⇒ `money_total()≡econ_total0` 结构恒真。**判据形状不变、集合 +1 项**。〔须 held-out 实测背书〕
- ⚠️**为何非 (a) 不可**：docs/144 §四.1 的 (b)/(c) 把 external 当**集外**无限源/汇 ⇒ 钱真漏、#34 **抓不到**、门变空。(a) 把 external 收进守恒集是保住 #34 判别力的**唯一**选项。

## 二、确定性
cost/revenue 纯整数 `f(good,batch)`（`economy/logistics.json` 声明 `price_per`，`cost=price_per*applied_batch`，撞 cap 少收同步少付）；无 randi/Time/浮点；挂日界（紧贴 `_logi_import` `Sim.gd:1608`，`day%every_days==0`，一天一次非 per-tick）。

## 三、第一片 = **import 付费**（判决，非 export）
只碰 **#34**（钱），货侧走 E1 已有 import lane、**#38 一字不改**；external 从 0 只增、**无需预注资**；"付不起"有房租先例（`transfer` 返 false 自动跳）。**export 收钱**须加 `export` 事件（#38 负号臂 + 社交排除集）+ external 须先有钱 ⇒ 留到 import 付费喂出 external 正余额之后（P4）。
- **town 破产处置（须外审/用户拍板的行为分叉）**：选项 A **先付后到**（守恒忠实、town_coin 可回放、蓄意 self-contain 压力"穷镇进不起口"，推荐）vs 选项 B **先到后付、付不起免费到**（E1 超集，弱化经济语义）。两者都守 #34、都确定性。

## 四、风险
1. **#34 负对照仍成立**（前提 external 在集内）：`town_coin-=cost` 漏贷 external ⇒ money_total 掉 ⇒ #34 红 ✅。**E2 须加此负对照**（对称 E1 的 #38 直写负对照）。
2. **通胀？** 货币供给被 #34 钉死（只搬不造）无经典通胀；真风险=**分布**：town_coin 单调涨 → 工资永不 skip → 抹掉"镇库空"压力；#35 对 town_coin 无上限 ⇒ 建议**钱上限/export 阈值**（留 E4）。
3. **town 净现金流向未量**（吃饭+2/做活−3，60 天净额未知）：若净负 → 选项 A 下进口自动断供（可能是特性、也可能让 #40 悄回归）⇒ **须 held-out 13-30 展布 town_coin + 柴薪 rate**。

## 五、移金标 + 外审门（落地时，非本片）
- **须 docs/41 §0.8 双路外审**（Codex desktop repo session + 多棒并行带 does_not_detect）+ 用户拍板，才动手。
- 落地须**重烘三锚**（golden+modelpath+ledger，docs/147 教训别漏 modelpath）+ 若加硬不变量（候选 #45 进口付费溯源）**同步两份 HARD_IDS**（`Invariants.gd:1390` + `tools/gate_fixture_audit.py:71`，E1 教训）；off 门=缺 economy/logistics 逐字节回退。

## 六、诚实边界
纯静态读码、未跑 CI/bench/真机；town 净现金流向、external 在 goto_tick 重演一致性、price_per 标定、方案(a)守 #34、export 的 #38 负号臂——均**未验证**，落地实测。**本探索不实现不改码不提交。**
