# 175 · 经济宏架构：大他者供养 + Anno 需求-满足 + 财政环 + 服务外营

> 本片是【经济车道的宏观架构 / 共同 contract】，由用户在 2026-08-09 数条设计对话中articulate、协调者综合成型。它给后续多相位、多棒实现提供【共享契约 + 不变量约束 + 相位序】，防 memory rot / 各棒漂移。**是活文档、会随实现精化。** 具体机制根因见 [[docs/170]]（缺货-gossip 根因）、[[docs/173]]（E6a §0.8）、E7 机制图（docs/174 待落）。

## 〇、一句话
小镇＝固定确定性 ≤60 居民的社会模拟；其经济是**分层系统**：一个「大他者(big Other / 外部中央权威)」**无条件供养生存物资 + 收税 + 经外部 affiliate 运营服务设施**；居民**生产/贸易/消费、有按 class/分工分化的需求(Anno)在【保证 floor 之上】被满足、缴 bills、并可 peer 贸易**；整套**守恒货币、逐字节可回放**。

## 一、层（layers）
1. **大他者(external authority)**：① import 无条件供养生存物资(preserve order、供充足 resources)② 收 tax(town→external 返流)③ 经 affiliate 运营 commercial/service 建筑(外部staff、常开)。
2. **居民(residents)**：生产(核心+可贸易货)、缴 bills/tax、有分化需求、peer 贸易。
3. **财政环(fiscal loop)**：钱入(供养+工资)↔ 钱出(tax+bills) → town budget → 力争 **nx balance＝财政均衡/自给**。
4. **需求-满足(Anno needs)**：need 谱＝①生存(口粮/基本，big-Other floor 托住)②comfort goods(treat)③entertainment/leisure(活动+venue)④future services/culture；按 class/分工 demand、supply 货或 venue 访问(+优质分级)满足、**后果落消费者情绪(非产者声誉)**。
5. **服务/affiliate 层**：venue(茶馆/咖啡馆/摊)由外部 affiliate 运营 ⇒ **不抽居民劳动池** ⇒ 常开、居民访问+消费+缴费 ⇒ 满足经【access】升。venue＝地图功能建筑(接视觉车道/用户原#1)。
6. **个人/peer 贸易**：居民间贸易(守 #34+溯源)，满足给货差异化价值后自然涌现。
7. **nx balance**：镇长自产、少依赖大他者净流入，趋净/平衡贸易＝自给。

## 二、不变量约束（the contract，任何相位都不许破）
- **红线**：①确定性+逐字节回放（新增 money 流/满足 state/affiliate agent 都必须 replay 字节精确）②零模型可玩 ③**≤60 居民、无人口增长环**（∴ Anno 满足度映射到【情绪/语音/幸福读数】、**不**驱动生人/升 tier）④R4 豁免。
- **货币**：#34 守恒、#35 非负、#45/#46 溯源、**闭环储备 external=Σimport−Σexport≥0**（tax/bills/affiliate 收入都并入此账；**大他者净头寸有界 ⇒ tax 不能把镇抽通缩到崩、供养不能泵通胀**——财政环须【构造性平衡】，如现贸易储备）。
- **供给**：#40 生存供给 floor＝大他者无条件供养的守门（生存永不崩）。
- **★核心结构规则(E7 定)**：**满足度/grievance 绝不可反馈进【生存产者决策】**。缺货后果只能落【自含的消费者情绪 / 只进 Story-语音-编年史的 drama 字段】，绝不进 `_acceptance_margin@Sim.gd:3913`(共享 standing 读点)——否则重蹈 E3b→E6a 的核心稀释。

## 三、关键设计原则（为何这套能成立）
- **consequence-on-consumer**：不满落消费者自身(有界、自含)，非产者声誉 churn 生存底料。这是【Anno 撑 ~30 货、本镇曾封顶 1 货】的差别所在，也是 E7/DP-A 解耦的目标。
- **survival-floor-guaranteed → 满足层承载戏剧而无崩溃风险**：大他者托住生存 ⇒ comfort/娱乐层可尽情涨落、永不威胁生存。
- **affiliate 服务外营 → 绕开劳动耦合**：venue 不抽居民劳动 ⇒ 服务/娱乐可交付而不重开 E4c/E4d-B 的劳动纠缠。**居民跑生存+可贸易经济、大他者+affiliate 跑服务/amenity 层**。
- **fiscal loop 构造性平衡**：tax 出 ≤ 供养入(有界)，如贸易储备的 external≥0 结构保证，防财政螺旋。

## 四、相位序（phases，各相独立可验、MVP 优先、每相同 discipline 门控：核心中性 held-out probe + 逐字节确定性 + 财政平衡）
- **Phase 0【已完成】**：E7 机制图——缺货→口粮耦合＝共享 `_rel(*).standing`(写@Sim.gd:3582、读@3913)。见 docs/174(待落)。
- **Phase 1【测量中】**：**解耦 enabler**——ablate ③(belief)/④(standing)定 leak、DP-B(非核心 blame)判决性测量、然后 **DP-A(standing 字段分离：生存 standing 进 3913、工业缺货 grievance 走只读 Story 字段)**必要时配 DP-D。**解锁【带戏剧的多工业货】**（打破封顶 1）。
- **Phase 2**：**需求-满足条**——per resident/class 满足 state、后果落消费者情绪、语音抱怨 + UI 读数。
- **Phase 3**：**娱乐 + 服务 venue**——entertainment need + affiliate 运营 venue 落地图（＝视觉建筑车道）。
- **Phase 4**：**财政环**——tax、bills、town budget；构造性平衡；P4 硬化(txid/town_coin 上限/大 N)。
- **Phase 5**：**peer 贸易 + nx balance 自给**（接生产多样化）。

## 五、当前状态
- Phase 0 done。**Phase 1 测量棒运行中**（ablate ③/④ + DP-B + #40 共存，授权 DP-A 精确切点）。
- 已 land 基座：import(E2a)+export 贸易环闭合(external 闭环储备)、#45 二向/#46 原子；多货机器 E4a(consume-Array)/E4d-A(produce-Array) committed 可复用；糕点(E3b)＝当前唯一工业消费货。
- 关联：[[project-economy-trade-loop]]、[[project-finalize-baton-committed-tree]]（move-golden 纪律）、[[feedback-adversarial-external-review]]（§0.8）、[[feedback-freeze-gates-drift-recurs]]（别给 defer 消费者预建基建——∴ 各相位 land 前须有玩家可达价值）。
