# 174 · E7 判决性测量：缺货稀释 leak ＝ ④声誉挫伤（非 ③信念）· DP-A 授权

> ---
> ## ⚠️ 2026-08-10 SUPERSEDED —— 本片"判决性 / 授权 DP-A"已撤回
> **E7 建在【旧 standing 小数跨零翻号 bug】之上**（`x - signf(x)`：\|x\|<1 时 −0.2→+0.8，符号翻转）——④声誉挫伤的漂移语义在旧代码里是错的，故"leak 全在 ④、③零贡献"这一因果分离**不可信**。standing bug 已于 2026-08-10 修（`move_toward(x,0,1)`，三锚随行为重烘），世界已移动（golden 聚合 rally_oust **+26.4%**/gossip_rep **+14.3%**/discuss **−12.8%**/gossip **−12.1%**）⇒ **E7 须在新基线、提交态、预注册新 seeds(61-126) 上重做**，旧结论不 carry-over。
> **且 DP-A 本身已 un-land**（docs/176）：drama 指标误读全 topic `social_by_type.gossip`（非饼干专属）、grievance 是 write-only ghost。**本片不再授权任何 Phase 1 手术。** 权威＝docs/113 顶部 2026-08-10 节 + docs/176 横幅 + git/CI。
> ---

> 本片是 E7 机制图（docs/113 宏图 Phase 0）的【判决性离门测量】。用 per-good 数据门在【第二件工业货饼干】上【分开】ablate ③(SH 信念)与 ④(声誉挫伤)，量各自对核心口粮 held-out(13-30) 的贡献——docs/170 §六明写"③④ 未分离 ablate"，本片补上。**只测量、不 land 代码、不移金标。** 结论直接授权 Phase 1 的 DP-A 手术精确切点。

## 〇、一句话
**第二件被消费工业货缺货稀释核心的 leak【全在 ④ 声誉挫伤】(`_adjust_standing`@Sim.gd:3582 → `_acceptance_margin`@3913 的涌现放逐)；③信念/gossip【零贡献】。** 单切 ④ ⇒ 口粮 held-out −0.0001(16/18 平)、paired +0.0479 **SIG UP**。DP-B(非核心 blame→商贩)只 partial **n.s.** 恢复 + 柴薪 −0.030 collateral ＝【搬家非解耦】(E7 预测证实)。⇒ **授权 DP-A**（④ 改道自含字段、保 ③ 戏剧），**无需 DP-D**。

## 一、setup（held-out 13-30、backend=null headless、N=12、seed 1-30 各 60 天）
- **CLEAN**＝committed batons(无饼干)。**WITH**＝加饼干为第二被消费货、镜像糕点让它常缺(cap≈糕点、闲聊 consume-Array、糕点师 produce-Array)＝复现 E4d-B 稀释基座。
- **4 arm**＝WITH + per-good 数据门(默认关、缺键【逐字节 no-op】、照抄 no_shortage_gossip/craft_credit 形状；Sim.gd:3574-3592 加 `_abl_belief`/`_abl_standing` 两守卫)，**只在饼干上**切：arm1=④(ablate_standing)、arm2=③(ablate_sh_belief)、arm3=③④、arm4=DP-B(饼干 blame 糕点师→商贩 mei，纯数据)。糕点/生存货全程不动。

## 二、结果（口粮 held-out Δ vs CLEAN + paired recovery vs WITH）
| arm（只切饼干的通道） | 口粮 mean Δ vs CLEAN | median | dn/up/flat | paired(arm−WITH) | 判 |
|---|---|---|---|---|---|
| **WITH**（③④全开） | −0.0480 | −0.0457 | 14/2/2 | — | 复现 E4d-B ✓ |
| **arm1 ④切** | **−0.0001** | +0.0000 | 1/1/16 | **+0.0479 [+0.016,+0.080] SIG UP** | **④＝leak** |
| arm2 ③切 | −0.0523 | −0.0540 | 13/3/2 | −0.0043 n.s. | **③非 leak** |
| arm3 ③④切 | +0.0000 | +0.0000 | 0/0/18 | +0.0480 SIG UP | 字节平 |
| arm4 DP-B（blame→mei） | −0.0231 | −0.0115 | 11/7/0 | +0.0249 [−0.024,+0.074] **n.s.** | 搬家非解耦 |

旁证：DP-B 令**柴薪 −0.0298**(recover −0.0225)——mei 卖口粮、砸她声誉经赶集分销扰其他货 ⇒ collateral，坐实"搬家非解耦"。arm1/arm3 对柴薪/屋瓦/整洁亦全恢复(每货 recover≈+WITH 的伤)。

## 三、解读
1. **leak ＝ ④ 声誉挫伤**：④ 是 standing【唯一无阈值改行为的读点】(`_acceptance_margin`@3913 `st=standing*STANDING_K` 进每种社交接受和式→涌现放逐→churn 决策/RNG 织物→翻食物产者 argmax)。切它 ⇒ 核心逐字节恢复(16/18 平，残 2 seed 是 ③ 的转述抖动)。
2. **③信念【非 leak】**：单切 ③ 零恢复(−0.0523、paired n.s.)。∴ ③(SH 信念→gossip 传开)虽是缺货戏剧的一部分，对**核心零贡献**——可【放心保留】作戏剧。这【推翻】E7 "DP-A 须配 DP-D 闭合 ③残留"的担心：③本就不 leak，DP-D 非必需(切它只多拿 2 seed 字节平、代价是杀掉 gossip 传开那面戏剧)。
3. **DP-B 判决＝搬家非解耦**：换 blame(→mei) 只 partial n.s. 恢复 + collateral。坐实 E7 判断：churn 出口侧＝seer 集(在场者含食物产者)【与 blame 身份无关】，换被砸对象不动 churn 出口。**∴ 非核心 blame 数据路作废**(§0.8/E7 要求"先探便宜路再下手术结论"——已探、已证伪、手术不可避免的前提成立)。
4. **E5a vs arm3 和解**：E5a 切【既有糕点】的 ③④＝−0.0197 混沌 n.s.(扰动已烘进均衡的成分)；arm3 切【新加饼干】的 ③④＝+0.0000 字节平(干净返回"无第二货 churn")。**教训：别动既有货的通道、只给【新/工业货】的 ④ 改道。**

## 四、DP-A 精确 scope（本测量授权的手术）
- **写侧** `Sim.gd:3582`：按 good-typed 门，把【工业/comfort 货】缺货的 ④ standing 挫伤**改写进一个自含字段**（grievance / 或 Anno 消费者-satisfaction），该字段**不 `*STANDING_K`、不进 `_acceptance_margin` 和式(3913)、不进 bad_targets(2130)/gossip_rep 阈**——只被 Story/编年史/语音读。
- **读侧** `3913` 只取生存/人际 standing 分量(judge/pact/craft_credit 来源)——**继续承载全镇涌现放逐核心戏剧**(不整刀砍 STANDING_K，见 ruled_out)。
- **保 ①②③ 戏剧**：饼干仍缺货、shortage 事件照记(喂 #40)、SH 信念照写照传 gossip。丢的只有"产者因该货被涌现放逐"这一面——而它非本货设计戏剧。
- **默认关数据门**(缺键逐字节回改前)保 replay；committed 树重烘 + CI。
- **★这直接实现 [[docs/175]] 的 big-Other 分层 + Anno consequence-on-consumer**：缺货后果落自含层(消费者情绪/drama 声誉)、绝不 churn 生存产者决策。

## 五、未决 / Phase 1 下一步
- **DP-A 原型 + probe**：核心中性确认(应复现 arm1 的 −0.0001)、饼干【真缺货且玩家可感】(shortage 事件>0 + gossip + 新 grievance/satisfaction 读数)、determinism 默认关门自证、**#40 共存**(静音/改道货 shortage 是否仍进 never_short 分母、排除是否 replay-safe、Invariants ~929-949 复核)。→ 通过则 §0.8 双路 → move-golden land。
- **grievance/satisfaction 字段语义**待定(衰减/钳制；勿复用 _adjust_standing 的翻号漂移引新混沌)——见 [[docs/173]] open_q。
- 数据：analysis/e7/（6 arm .log/.jsonl + anchor.py/attribute.py + prod/ 配置）。所有数值 held-out 13-30 真跑、seed≤30、N=12、backend=null；未跑真机/N≥24。
