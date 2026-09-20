# 226 · P4c-7 跨切片影响复核与 S5 因果监测修正

> 接 [225](225-p4c7-civic-notice-board.md)。镇务公示板按设计是只读 View 切片；本次不凭代码注释相信它，
> 而是用跨提交金标、留出 seed、历史压力病例和因果套件分别检查“有没有移动世界”与“监测器有没有说真话”。

## 一、P4c-7 没有移动仿真轨迹

- 默认 N=12、seeds 1-12、60 天：硬不变量 12/12，软门通过，20 类活性通过，确定性 1/1；
  `digest / event_digest / 逐日 chain` 与切片前金标 **12/12 逐字节一致**。
- 留出 N=12、seeds 13-30、60 天：46 条不变量全部 18/18；`civic_duty` 31 次、覆盖 18/18；
  `aid` 覆盖 14/18，均高于法定覆盖门；确定性 1/1。
- `life_test`、`governance_test`、`player_touch_test` 全绿。公示板新增的是无 `advertises` 的 authored marker；
  CausalHarness、Harness 与 NPC 决策都不调用公示投影。

因此，seed 4 的 #15 诊断项与 seed 5 的 #26 软项不是本切片回归：它们在新切片下的三份金标摘要仍与旧锚逐字节相同。

## 二、历史 N=40 病例今天已不复现，但不能外推

按当前显式人口口径 `--core-agents 40` 重跑 [89](89-wave-w-w2-n40-red.md) 点名的 seeds 8 与 56：

- 两个 seed 均跑满 60 天；#01 与其余 45 条不变量全部 2/2；
- seed 8 / 56 分别产生 10949 / 11347 条事件；
- `civic_duty` 两个 seed 都发生；同 seed 重放摘要 1/1 一致。

这说明路线图中“seed 8 与 56 今天仍红”已经过期。它**不**证明完整 N=40，更不证明 N=48/N=60；
两 seed 网格也小于 quorum 最小样本，Harness 会明确把 `aid/civic_duty` 覆盖率标成不入门。不能把这次绿写成规模承诺已完成。

## 三、真正发现的红：S5 把必要条件当成充分原因

原 S5 在当前树上输出：

```text
trust→投资  base=0.25  do(高)=0.25  do(低)=0.00  ACE=0.25  PN=1.00(2/2)
S5 GATE: FAIL（统一要求三条假设 ACE≥0.30）
```

逐 seed 回执显示，固定 pair 只有 seeds 4 与 7 自然获得同场、礼物或邀约机会；强制低 trust 会把两次投资全部阻断，
强制高 trust 却不能凭空创造相遇和资源。引擎里的 `INVEST_TRUST` 本来就是 give/invite 的**必要候选门**，不是机会生成器。
统一 ACE 门因此把“机会只有 2/8”误报成“trust 机制失效”。

监测器现按声明分开判：

- standing→放逐、开放度→观点迁移继续要求 `ACE ≥ 0.30`；
- trust→投资要求 control-positive 支持数至少 2，并且持续 `do(trust=low)` 必须阻断全部支持样本；
- PS 与 ACE 继续打印，但只作“高 trust 是否足以创造结果”的诊断量；
- 每条假设打印 `seed:control/high/low`，以后不再只剩一个无法定位的均值；
- `--only trust|standing|xi` 可单独复核一条假设，缩短异常定位回路；非法值 fail closed（非零退出）。

修正后的 trust 专项为 `blocked=2/2`、`PN=1.00`，且支持数正好为 2，因而通过但余量为零。
这不是“投资频率健康”的证明；base 2/8 相比早期文档的 5/8 明显更稀，下一片若要改善社交暖度，应该另立机会/频率量具，
而不是放松 trust 门或把相遇率偷塞进因果必要性断言。

完整 S5（seeds 1-8 × 40 天）随后复跑通过：standing `ACE=1.00`，开放度 `ACE=0.88`，trust
`blocked=2/2 / PN=1.00`。系统指标 control 为 PI `0.260`、cascade `12.875`、Gini `0.124`；
三条假设均附逐 seed control/high/low 回执。

## 四、边界

本片只改 `game/bench/CausalHarness.gd` 的监测语义和诊断输出，没有改 Sim、数据、金标或玩家 UI。
NobodyWho GDExtension 缺失仍是本机已知启动警告；所有 logic-only 测试随后正常执行。

The follow-up opportunity funnel and English receipt are in [227](227-investment-opportunity-receipt.md).
