# P1-b CargoManifest · authorized overtime delivery grid

- **用途**：记录 `cfca74a` 对 CargoManifest 吞吐回归的因果诊断、修复合同、分层网格和仍未关闭的 delivery gate，供 review、CI 与后续 East Ocean/carrier 纵切复用。
- **实现来源**：`codex/p1a-takeover@cfca74a`。网格在提交前的同一工作树代码上运行；提交只冻结已测内容。最后一次 JSON 合同说明改写不参与仿真决策，focused scene 已在该最终内容上重跑。原始日志只在 `%TEMP%`，均为 `generated/rebuildable`。
- **环境**：Windows / Godot `4.6.2.stable.official.71f334935`；未传 `--golden`，没有重烘 golden、modelpath 或 complement ledger。

## 1. 回归与因果定位

P1-b `ac18e29` 把日界直接进口替换成真实 manifest 后，standard N=12 仍过门，但 held-out seeds 15/30 与 total-N60 的 #40 暴露了轨迹回归。隔离 `git archive 5fb2686` 的 A/B 中，seeds 15/30 在旧树均绿，在 `ac18e29` 分别因糕点满足率 `0.44 / 0.35` 变红。`ScaleSupply` 对拍显示 Coco 的糕点工作完成由 `22→15 / 32→15`；不是直接的柴薪原料短缺。

真正瓶颈是码头工 Tao 的“候选→认领→真实提交”漏斗：seed 15 为 `132→29→13`，seed 30 为 `182→20→2`。整单只需 3 钱，两个 seed 的 `town_coin_min=60`、无 skipped wage；60 天末柴薪 `59 / 55 < cap80`，余额和终局货位都不能解释持续 backlog。旧实现要求 28-tick 卸货在 dawn/day 的每一个 travel/use/commit tick 都重新满足班次；临近 dusk 开工会被清 option，下一班重复旅行，seed 30 有 90% 已认领卸货未提交。行为轨迹变化再外溢到糕点工作完成率。

## 2. 修复合同

1. `_apply_object` 只在码头工**在班**且当前 authored cargo candidate 仍存在时签发 `manifest_authorized=true`；action/target/need/amount/dur_total/node/id 必须逐字段与 canonical candidate 相同。
2. Sim 与 AIBackend 只给 cargo candidate key 追加 exact node/id（backend 另钉 `dur_total`），普通 candidate key 逐字保持；旧异步 intent 不能把 manifest A 重绑成 B，也不能把 28 tick 篡成 1 tick。
3. 已签发的同一单允许跨班次完成；travel/use/commit 每 tick 仍重验岗位、target/action→node、最早 exact manifest、货位和余额。未授权、stale、被抢、余额或容量变化均在 need/库存/钱/事件/记忆/技能/工资之前 fail-closed。
4. 成功顺序保持 `import pay → import stock → cargo receipt → wage`；跨班完成仍按本职工资结算。chain 仅对 cargo option 追加 authorization/node/id，logistics-off 的普通六字段 option 不漂。
5. save/load 覆盖已授权且 use 中途的 option：授权、remaining、exact manifest 与 chain 恢复后，跨 dusk 仍提交同一单。

## 3. 最终验证矩阵

| 格子 | 结果 | hard / #40 | 贸易与确定性 | 诚实限制 |
|---|---|---|---|---|
| focused CargoManifest | PASS | `0 fail` | 空港、篡改/stale intent、容量/余额/抢单、授权、跨班、mid-use save/load、原子顺序、chain mutation 全绿 | 只验证合同，不替代统计网格 |
| standard N=12, seeds 1–12, 60d, det3 | PASS | hard `12/12`；#40 `11/12`，仅 seed 5 糕点 `0.50`、断供 `33/60` | import `227`、export `40`，均覆盖 `12/12`；#44/#46 `12/12`；det `3/3` | 未传 golden |
| held-out N=12, seeds 13–30, 60d, det3 | PASS | hard `18/18`；#40 `18/18` | import `346`、export `78`，均覆盖 `18/18`；#44/#46 `18/18`；det `3/3` | aid 覆盖 `17/18`，仍高于门槛 9 |
| total-N16, seeds 1–12, 60d, det1 | PASS | hard `12/12`；#40 `12/12`；#26 `11/12` | import `218/12 seeds`；det `1/1` | export 按现有 scale gate 为 0，#46 条件式空过 |
| total-N24, seeds 1–12, 60d, det1 | **FAIL** | hard `12/12`；#40 `10/12`，seeds 7/12 红 | import `214/12 seeds`；det `1/1` | composition/scale 仍未标定；export 0，#46 空过 |
| total-N60, seeds 1–12, 60d, det1 | PASS | hard `12/12`；#40 `11/12`，仅 seed 4 口粮 `0.49`、断供 `36/60` | import `197/12 seeds`；det `1/1` | export 0，#46 空过；不能用本格覆盖 N24 红 |

标准格命令：

```powershell
C:\Users\yp\.local\bin\godot.cmd --headless --path game --log-file $env:TEMP\p1b_final_n12_exact_e393a889-20fe-41e5-9156-6c771c2ae809.log --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3
```

held-out 与 total-N60 的同口径日志分别为 `%TEMP%\p1b_heldout_canonical_cargo_b6a74352-a698-4566-99e2-23e839f9be6b.log`、`%TEMP%\p1b_dirty_canonical_cargo_total60.log`。所有正确运行均无 `signal 11` / `FATAL` / `out of bounds` / `SCRIPT ERROR`；部分仅有 Godot 退出期 `ObjectDB instances leaked` warning。

## 4. Delivery / review gate

- PR #6 的旧 exact head `ac18e29` synthetic-merge run `31478588905` 已终态 FAIL。SHA receipt、S0 hard、CargoManifest scene、player agency、state projection 都通过；真实红为 stale complement ledger schema/game tree、golden/DetGate 漂移与 ModelPath anchor 5 项漂移。按协议不在本棒重烘。
- logistics-off 隔离对拍虽然 hard `12/12`、det `3/3`，但 #40 仅 `9/12` 且 golden 的 digest/event_digest/chain 共 `36` 处不符；#44/#46 因零贸易而空过。这不是 parser/load 失败，必须保留为阻断证据。
- 物理 `port_dock@[33,8]` 仍是 legacy map anchor；`route_id=east_ocean` 只表示逻辑来源。可见 carrier、East Ocean 物理港与 exact `integration/batons` push receipt 尚未落地，review 的 REQUEST CHANGES 不能解除。
- scale export 仍明确限 N=12；N16/24/60 的 #46 均不可称为 live provider。N24 #40 红需下一独立规模标定棒，禁止用 N60 PASS 外推。
- `manifest_authorized` 属可信 in-process/save 状态；手改存档或内部扩展直接伪造 bool 不在当前产品合同。若未来承诺不可信 mod/save 抗篡改，应改用 engine-owned capability，而不是沿用本布尔边界。

## 5. 来源、复用与 hygiene

- 原理、实现和测试均来自本仓现有 CargoManifest、candidate replay、save/chain 与经济账本；未复制外部代码/资产，无新增第三方许可证义务。
- 复用接口：`_cargo_option_eligible` 是 travel/use 的统一副作用前门；`_cand_key` 的 cargo-only suffix 是异步回包绑定合同；本 focused scene 是 negative/race/save/determinism fixture。
- 无 README、地图、WorldView、golden/modelpath/complement ledger、protected branch 修改；无 archive/clean。原始日志可由上列 commit/命令重建，repo 不跟踪大日志。
