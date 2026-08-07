# analysis/as1 — E1 柴薪进口 lane 的实测支撑数据

配套 `docs/147`。全部 backend=null、无 LOD、60 天，量具 = `game/bench/ScaleSupply.gd`（逐 good 满足率的算法逐字对齐 Invariants #40）。

| 文件 | 内容 |
|---|---|
| `n12_supply_before_after.txt` | N=12 seeds 1-30 改前(OFF)/改后(batch=4 ON) 逐 seed：柴薪/屋瓦满足率、缺货天数、洗澡 attempts、never_short/gated、arm_high、#40ok |
| `largeN_40_before_after.txt` | N=16/24/60 各 seeds 1-12 OFF/ON 的 #40 红数、两条臂、最差货 rate、arm_high margin |
| `largeN_40_ON.txt` | 上表 ON 侧的单独汇总 |
| `raw_scalesupply_n12_OFF.jsonl` | N=12 seeds 1-30 OFF 的原始 ScaleSupply 记录（每行一 seed） |
| `raw_scalesupply_n12_ON_batch4.jsonl` | N=12 seeds 1-30 ON(batch=4) 的原始记录 |

## batch 定量（为什么是 4/every_days=3）
逐档实测（N=12 seeds 1-30），判据是【松动看得见】∧【柴薪不进 never_short（否则撞 #40 上限臂）】∧【#40 无新红】：

| batch (件/seed) | 柴薪 rate min/med | 柴薪 0缺货 seed 数 | arm_high 触发 | #40 新红 | 结论 |
|---|---|---|---|---|---|
| 8 (~160) | seed 13 → **1.0** | 多 | 逼近(seed13 never_short=2,余量2) | — | **过头**：柴薪被推成全年零缺货，逼上限臂 |
| 4 (~80) | 0.77/0.94 | **0/30** | 0/30 | 0/30 | **选它**：松动可见、柴薪仍缺、无新红 |
| 2 (~40) | 0.76/0.91 | 0/30 | 0/30 | **1/30**(seed26 arm_low) | 松动更弱，反而撞了一个 butterfly 下限红 |

★关键结构事实（`raw_scalesupply_n12_OFF.jsonl` 可复核）：**基线里柴薪 0/30 seed 全年零缺货**（rate 0.61-0.98、缺货 2-27 天），而 **seeds 29/30 基线已有 never_short=3（整洁/话本/豆子）、arm_high 余量=0** ⇒ 只要进口把柴薪推成全年零缺货、且落在这类 seed 上，#40 上限臂当场红。batch=4 保证柴薪【仍缺】⇒ 余量不被吃。
