# 112 · AA3-FIX 回执——修掉商贩自证：`witnesses` 滤掉收款方，#43 只数商贩以外的目击者

> **一句话**：一笔只被商贩自己"看见"的成交（改前实测 40/715 笔、逐 seed 1-6）从此不再算"被看见"。
> 采集侧（`Sim.gd`）与观察侧（`Invariants.gd` #43）各挡一道；纯观测变更、零行为变更
> （event_digest/chain 逐 seed 一位不动），但动了 witnesses 采集 ⇒ 走完整 R12。

## ★ 交付状态

- 分支 `fix/aa3-vendor-witness`（基线 `ce75142` = origin/integration/batons），不 push 不 merge。
- 改动：`game/scripts/Sim.gd`（①采集侧过滤）、`game/bench/Invariants.gd`（②#43 观察侧判据 + 注释）、
  三份锚重烘（`golden_digests.json` seeds+scenarios 段、`modelpath_anchor.json`）、
  探针 `game/bench/aa3fix_census.gd`（新增，含两种合成变异）、本回执、原始数据 `analysis/aa3fix/`。
- **豁免线（`TRADE_MIN_SALES=5`）一个字节没动**——那是 Z2 立的口径，改判据要用户拍板（§六只报余量与建议）。

### 原始数据清单（`analysis/aa3fix/`）

| 文件 | 是什么 |
|---|---|
| `golden_red_before_bake.txt` | 改后·重烘前的 `Harness --golden`（金标先自己红） |
| `detgate_prebake.txt` / `modelpath_prebake.txt` | 另两份锚的"先红" |
| `bake_harness.txt` / `bake_detgate.txt` / `bake_modelpath.txt` | 三份锚的重烘 |
| `detgate_postbake.txt` / `modelpath_postbake.txt` / `golden_verify_after_history.txt` | 烘后 + 补 `rebake_history` 后的复核 |
| `censusA.txt` / `censusFIX.txt` / `censusR.txt` / `censusN.txt` | 基线 / 修后 / 撤过滤 / 零假设臂 的普查（12 seed × 60 天） |
| `censusAkd.txt` / `censusFkd.txt` | 负对照 a：两棵树各自摘掉 `trade_credit` 键（`aa3_vendor_census`） |
| `tooth_old.txt` / `tooth_new.txt` / `keepone.txt` | ② 的牙齿与盲区（合成变异，跑出来的） |
| `heldout_base.txt` / `heldout_fix.txt` | 留出种子 13-30，改前/改后两侧 |
| `ci_full.txt` | `bash tools/ci.sh` 全量输出 |

## 〇、这份 brief 哪里是错的（[docs/41 §4](41-baton-contract.md)）

1. **派单写 `Invariants.gd #43（约 :1100-1140）`——过期**。`ce75142` 上 #43 全块是 **:1079-1156**
   （M2 已更正，我复核）。`Sim.gd:1499-1507` / `_nearby_agents(:3879)` / `_trade_fallout(:3599-3609)` 三处行号都对。
2. **"商贩与买家同区的成交占 19-24%"引用时丢了分母**。那是 [docs/106 §一](106-wave-aa-aa3-vendor-consumption-trace.md)
   的 D2 口径（分母=全部成交，含付不起的）。在"带目击者的 `pay` 事件"这个分母上（M1 的口径），
   witnesses 含商贩的是 **232/715 ≈ 32%**（我复测逐 seed 与 M1 逐位同）。两个数都真，分母不同。
3. **M1 那句"展布 min 58（seed12，11.6×线）"把两列贴混了**：逐 seed **余量**（成交−5）是
   `79/59/66/58/66/58/76/60/61/66/70/53`，最小 **53**（seed12）；**58** 是 seed12 的**成交数**（58 = 11.6×5）。
   数全对，标签错列。本回执 §六 按两列分开报。

## 一、改了什么（两处，语义各一句）

**① `Sim.gd` 采集侧**——赶集付款处的 `twits` 从 `_nearby_agents(买家)` 改为**再滤掉 payee（商贩本人）**：

```gdscript
var twits: Array = []
if not tc.is_empty():
    for tw in _nearby_agents(ag):
        if String(tw["id"]) != payee:
            twits.append(tw)
```

语义：**"被看见" = 交易双方之外的人看见**。买家已被 `_nearby_agents` 排除（它跳过 `ag` 自己），
商贩由本过滤排除；信念/standing 层 `_trade_fallout` 本就跳过商贩（seers 循环里的 `continue`，未动）。
`tc` 为空时连 `_nearby_agents` 都不调——AA3 的零扰动性质原样保留（负对照 a）。

**② `Invariants.gd` 观察侧（防御纵深）**——#43 正向臂的 `sales_w` 从"`witnesses` 非空"改为
"**`witnesses` 去掉商贩后非空**"（`wn_other`）。即使将来采集侧被改回，自证也喂不绿这道门（负对照 b 的牙齿）。

## 二、金标先自己红（改后·重烘前，三份锚各自跑）

**Harness**（`--seeds 1-12 --days 60 --det 3 --golden …`，`golden_red_before_bake.txt`）：**exit 1**，

```
❌ 金标不符（12 处）——12 处全部是 digest 行（seed 1-12 逐个），event_digest 0 处、chain 0 处
=== S0 GATE: FAIL ❌  (硬不变量 seed 12/12 全绿, 软通过率门 ≥11/12(90%) 过, 活性 过, 金标 破, det 3/3) ===
```

与 M1 的预测逐字吻合（M1 原文）：
> "12/12 —— Inv.digest 全部 12 个 seed 都变了……event_digest 0/12、chain 0/12 未动，逐 seed 事件总数相同。
> ……witnesses 只折进 Inv.digest 的 wstr，event_digest/chain_step 不折，且 _trade_fallout(Sim.gd:3602)
> 本就跳过商贩 ⇒ 过滤是纯观测变更、零行为变更；但只要动采集就必须 R12 重烘金标。"

**DetGate**（`detgate_prebake.txt`）：**exit 1**，金标 15/16 行不符、**全部只有 digest 位不同**
（每行的 event_digest 与 chain 期望/实得逐位相同）；**freerider seed 3 金标=✅**——那一格 20 天里
没有一笔商贩同区带证成交，digest 就不动，这本身是"纯观测变更"的又一枚旁证。硬 16/16、两跑一致 16/16。

**ModelPathGate**（`modelpath_prebake.txt`）：**exit 1**，`失败 4`：4/4 seed 只差 digest；
`landed`（681/664/664/646）与候选规模行（max|C|=40，88/2655）**逐位对上锚**——
模型路上也只动观测不动行为。

## 三、R12（[docs/47 §〇](47-wave-e-plan.md)）——整套走完

1. **蓄意吗**：是——§二先红、红的形状与 M1 预测逐字节一致，然后才烘。
2. **三份锚全烘**：`Harness --bake-golden`（12 seed，烘后自跑 PASS）→ `DetGate --bake-golden`
   （🔨 已烘 4 track × 4 seed；**烘的那一跑照旧打 FAIL「金标 1/16 可比」**——它在写入前拿旧 scenarios 比，
   docs/106 §六② 记过的同一条坑）→ 重跑不带 bake 的 DetGate ⇒ **PASS（硬 16/16、两跑 16/16、金标 16/16 可比）**
   → `ModelPathGate --bake-anchor` → 重跑 ⇒ **PASS（失败 0）**。
3. **`rebake_history`**：两份 json 各补一条（日期 + 原因 + "只有 digest 动"的证据形状），
   补完再各复核一遍三道门仍绿（`golden_verify_after_history.txt`）。
4. **留出种子 13-30，两侧都跑**（`heldout_base.txt` / `heldout_fix.txt`）：
   改前（隔离副本 `ce75142`）与改后**都是** `S0 GATE: PASS ✅ 硬 18/18 全绿`；
   软/诊断失败**两侧逐 seed 相同**（软 #40 seed26、#26 seed29；诊断 #15 seed18）；
   逐 seed 事件数相同；**digest 动 18/18，event_digest 0/18、chain 0/18**——观测变更、行为不变，在留出格上同样成立。
5. **没有为让门变绿放松任何判据**：`Invariants.gd` 唯一的判据改动是 #43 ① 臂**收紧**（自证不再计入）；
   `TRADE_MIN_SALES`、豁免结构、其余臂原样。

## 四、负对照（三条都真跑了，不是推断）

### 4.1 a）摘 `production.vendor.trade_credit` 键 ⇒ 12/12 逐字节回到 AA3 之前

两棵树各自摘键（注释键留着）、各跑 `aa3_vendor_census --agents 12 --seeds 1-12 --days 60`：

```
基线(ce75142)摘键   3480519386 3917739032 2996591874 432712946 1944181176 1650616061
                    2131126506 1742410486 2120349616 3407576096 211456419 29724740
修后(本分支)摘键    ——12/12 逐位相同，events_total 逐 seed 相同——
docs/106 §四.1 预AA3行 ——12/12 逐位相同——
```

⇒ 本修复在键关着时**一条指令都不多跑**；AA3 的零扰动对照原样成立，回滚成本仍是删一个键。

### 4.2 b）撤掉①的过滤（隔离副本 copyR，②的新判据留着）

- **自证计数回到非零**：`buy_vendor_only` 逐 seed `2/5/2/1/3/3/3/5/3/3/4/6`（合计 40/715）——
  与 M1 的基线**逐位相同**（极值 min 1=seed4、max 6=seed12，无并列）；copyR 的 12 个 digest
  与基线逐位同（Invariants 改动不碰行为，尺子自证）。
- **②抓住每一笔自证**：#43 note 的"被看见"逐 seed = 带证成交 − 自证
  （71=73−2、43=48−5、59=61−2、51=52−1、62=65−3、51=54−3、66=69−3、54=59−5、55=58−3、55=58−3、61=65−4、47=53−6，12/12 精确）。
- **牙齿（合成极端）**：把全部 buy 事件的 witnesses 改成 `[商贩]`（seeds 1-4 × 60 天）：
  **旧判据（基线 copyA）4/4 绿、"被看见"=成交**（被自证喂饱）；
  **新判据 4/4 红 `hard=[43]`**：`成交84笔但【一笔都没被看见】(pay 的 witnesses 通道断了)`。
  同一份账本，旧门瞎、新门咬——这就是②存在的理由。

### 4.3 c）零假设臂 `obj_dist_penalty` 0.400→0.401（语义无关扰动，基线树）

| 臂 | `buy_vendor_only` 逐 seed | 合计 | 极值 |
|---|---|---|---|
| 基线 0.400 | `2/5/2/1/3/3/3/5/3/3/4/6` | **40**/715 | min 1=seed4、max 6=seed12（无并列） |
| 零假设 0.401 | `2/3/2/3/2/2/1/3/3/3/6/6` | **36**/697 | min 1=seed7、max 6=**seed11 与 seed12 并列** |
| **修后（本分支）** | `0/0/0/0/0/0/0/0/0/0/0/0` | **0**/(带证 675) | 12/12 全 0 |

读法（连续余量，不数红格）：轨迹重排把自证计数挪了 ±10%（40→36），**挪不到 0**——
零假设臂 12 个 seed 里**没有一个**降到 0（最小 1）；修后 12/12 恒 0，且 `buy_vendor_in` 也 12/12 恒 0
（不是"恰好没有只剩他一个"，是他**根本不再出现在 witnesses 里**——结构性归零，不在零假设带内）。

## 五、探测包络（[docs/41 §2.5](41-baton-contract.md)）——#43 ① 臂的新判据

```
detects:（实测变红）
  · 全部成交只被商贩自己"看见"（witnesses=[商贩] 合成，seeds 1-4×60 天）⇒ 4/4 红「被看见0」；
    同一账本喂旧判据 ⇒ 4/4 绿「被看见=成交」（tooth_old/tooth_new.txt）。
  · witnesses 通道整体断裂（docs/106 m1 那类，sales_w=0）⇒ 照旧红——它与上一条走的是**同一条**
    `sales_w<=0` 判定（tooth_new 实际打红过的那条）；m1 那个变体本身未另跑。
does_not_detect:（跑出来的，不是想出来的）
  · 99% 通道损失：只留 1 条带非商贩目击的成交、其余全清空（--mutate keepone，seeds 1-4×60 天）
    ⇒ 4/4 绿「被看见1」（keepone.txt）——这条臂只在恰好 0 时红，本棒继承、未收紧。
  · 目击者是否真在场 / standing 是否真动 / 文案 / meals_free 那一半 / 日名额——
    docs/106 §五 m5-m8 的盲区原样继承（本棒只改了 sales_w 的计数口径，那些臂没动，m5-m8 未重跑）。
confidence: N=3 组合成变异（vendoronly×新旧判据 各 4 seed、keepone 4 seed）；
  正确性侧：出货 12/12 绿、留出 13-30 两侧各 18/18、DetGate 16/16、金标三锚重烘后全绿、CI 全量绿。
```

## 六、豁免线余量（只报数 + 建议；**本棒不收紧**——Z2 的口径，改判据要用户拍板）

M1 原文：

> "#43 豁免线余量：sales 距 TRADE_MIN_SALES=5 逐 seed 余量 79/59/66/58/66/58/76/60/61/66/70/53，
> 展布 min 58（seed12，11.6×线）max 84（seed1）无并列——liveness 静默豁免离触发很远（最坏 seed 需跌掉 >91% 成交）。"

（列标签更正见 §〇-3：余量最小 **53**、成交最小 **58**，两列都在上面。）我复测逐位相同，且两条旁证：

- **豁免线的证据基础本来就是"滤掉商贩后的世界"**（M2 查明）：`TRADE_MIN_SALES` 的余量证据
  （`Invariants.gd` 该常量抬头注释引的九格最小 13——引符号不引行号，本棒的编辑已把行号推了十来行）
  量的是 `aa3_vendor_census` 的 D5，其 `others` 列**已排除商贩** ⇒ 本修复没有动摇豁免线的标定依据。
- 修后带证成交每 seed 仍有 **43..71** 笔（min 43=seed2、max 71=seed1，无并列）⇒ `sales_w<=0` 臂余量 ≥43。

**建议**（仅供拍板，不落地）：维持 5 不动。若将来想让豁免线与①臂同口径（按"非商贩带证成交"计），
今天的最小值是 43，8× 余量下限在 5 上仍然成立；收紧买不到新的判别力（M1：单 seed 的 PASS 不含信息）。

## 七、`bash tools/ci.sh` 全量（读输出，判决行照抄，`ci_full.txt`）

`bash tools/ci.sh` 在本分支（三锚已重烘、rebake_history 已补）上跑完：**`=== CI PASS ✅ ===`，exit 0，全程 919s**
（"全程"是脚本现算现印的，别把单次读成基准）。逐步判决行照抄：

```
0.  ✅ no tracked weights/binaries · ✅ 红线#4 负对照
1.  ✅ lint_data   1b. ✅ audit_map   2. ✅ lint_links（126 markdown / 107 numbered docs）
2b. === ART GATE PASS ✅ ===   2c. === TERRAIN GATE PASS ✅ ===   2d. === ASSET GATE PASS ✅ ===
2e. ✅ 可重算门（负对照四臂 + 注册表逐条）——两条 gate:false 的样本行照旧打印 ❌ 但不判红
    （palette-gpl-de00-6p3 / lint-links-md-count，与 docs/106 §7.1 的同两条）
2f. ✅ 互补性守卫（负对照五臂 + 现读现比）
3.  ✅ import/parse clean
4.  === S0 GATE: PASS ✅ (硬不变量 seed 12/12 全绿, 软通过率门 ≥11/12(90%) 过, 活性 过, 金标 过, det 3/3) ===
      其中 ✅ #43 [硬]买卖的社会痕迹(被看见·被知道·不外溢) 12/12   ← 新判据在出货网格全绿
4a. ✅ 宏观池尺度门 (N=16，×16/12)：S0 GATE: PASS（含 #43 12/12）
4b. === LOD-VERIFY GATE: ✅ PASS (V2+V3abc 全绿) ===
4c. === DetGate: PASS ✅ (硬 16/16, 两跑一致 16/16, 数据指纹一致 16/16[1412772156], 金标 16/16 可比) ===   ← 锚是本棒重烘的
4d. === BackendGate: PASS ✅ (硬 8/8, 两跑一致 8/8, 闭集封闭 8/8, 自检臂必红 4/4, 伪造落地 4/4) ===
4e. === ModelPathGate: PASS ✅ (失败 0)                                                        ← 锚是本棒重烘的
4f. === VoiceGate: PASS ✅ ===
5.  9 个场景全绿（m2/reqlife/player_agency/player_touch/s4_replay/space/save_load 1-9s；goals_test 71s；story_test 192s）
6.  ✅ 视觉门（昼夜 / 界外层重画 / 空间往返 / 岸线 / 室内外壳 / 家具语义 / 树丛点阵）
=== CI PASS ✅ ===
```

## 八、没能测到什么（"没测"明写）

- **docs/106 §五 的 m5-m8 四个盲区变异没有重跑**——本棒没动那些臂；引用的是 AA3 的实测，不是新证据。
- **BackendGate / ModelPathGate 两格里商贩成交的绝对频次**没有单独量（继承 docs/106 §五 结尾同一条）；
  只知道 ModelPathGate 的 4/4 digest 在 8 天 random 臂上都动了 ⇒ 那两格里商贩同区成交发生过，频次不明。
- **留出 31-60 没有跑**（派单只要 13-30 两侧；31-60 的改前数据在 docs/106 §四.2，改后没有）。
- **N≠12 的网格没有跑**（4a 的 N=16 由 CI 覆盖，census 类测量全部 N=12）。

## 九、给下一棒的三句话

1. **witnesses 的观察侧语义：本回执只排了商贩一端，买家端由 AG2 补全（docs/125，Codex §六.1 的 P2 抗回归缺口）。**
   ⚠ 订正（这句原写"witnesses 的语义从此是『交易双方之外』"——过强、与本回执 §一② 的代码不符）：
   本回执 §一② 的 `#43 ①臂` 只把 `wn_other` 从"witnesses 非空"改成"去掉【商贩=target=v_id】后非空"，
   **观察侧当初只排了交易的一端**；采集侧 §一① 两端都排，两侧口径其实不一致。
   AG2（docs/125）把 `wn_other` 收紧成同时排掉【买家=actor】与【商贩=target】⇒ 观察侧这才真正做到"交易双方之外"。
   自此：谁往 buy `pay` 的 witnesses 里塞【买家或商贩】，#43 ①臂都会把那笔当"没被看见"数；别把这当 bug 报。
   （负对照见 docs/125：`--mutate buyeronly` / `partiesonly` 收紧后各 6/6 红 `hard=[43]`；同一账本喂旧判据 buyeronly 是绿的。）
2. **#43 ① 臂仍然只在 sales_w 恰好为 0 时红**（keepone 4/4 绿是跑出来的）——想守"通道变细"，
   要么给它配比例地板，要么别声称它守了。
3. **豁免线（TRADE_MIN_SALES=5）这次刻意没动**，余量两列（成交 min 58 / 余量 min 53）都在 §六，
   要收紧是用户的决定。
