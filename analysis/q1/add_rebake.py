# -*- coding: utf-8 -*-
"""在 golden_digests.json 的 _meta.rebake_history 末尾追加一条（保留文件其余部分逐字节不动）。"""
import io, json, sys

P = "game/bench/golden_digests.json"
ENTRY = (
    "2026-08-01 · Q1 派系接触门：意见不再瞬移 ⇒ 世界轨迹蓄意移动"
    "（docs/65 / docs/64 §一 / docs/47 R12）。"
    "改的是什么：`_recompute_factions()` 的归堆判据从「对齐」"
    "改成「对齐 **且** 打过交道」（`_aligned(...) and _acquainted(id, m)`）。"
    "判据取 `familiarity >= faction_fam_th`（1.0）：它全仓只在两处自增"
    "（`_commit_social` 被接受的社交 / `_resolve_commitments` 守约赴会）、从不衰减 "
    "⇒ `>=1` 恰好等于「至少完整打过一次交道」（`_impt` 早就用 `<=1.0` 表示「首次接触」）。"
    "为什么必须动：旧树上只改**一个人的私有 `attitudes`**（零事件、零信念、"
    "`event_log` 一个字都没多），别人的 `faction` 在**下一个日界**就跟着变，"
    "而 `faction` 直接进候选生成（endorse / rally_oust / 同派系亲和）与接受判定（`_faction_term` ±8.0）。"
    "★ 本棒把这一步从【时序推论】换成【构造隔离】：把被改动者从 tick 0 起钉在自造平面 `q:cell` "
    "（`_same_plane` 比 space+floor）⇒ 他从头到尾不可能进任何人的 `_nearby_agents`；"
    "隔离自证逐格打印：同区 tick=0、familiarity=0，**25/25 格全为 0**。"
    "改前：该隔离臂在 5×5 网格（N∈{12,16,20,24,60} × seed∈{1,5,7,13,21}，10 天，t0=1200）上"
    "**9-10 个格有别人当夜换派系（4-16 人）、5 个格世界 chain 真的分叉**；"
    "改后 **25/25 格 chain 逐字节相同**（`chain同=true`）。"
    "★ 可 ablate：`faction_fam_th <= 0` ⇒ `_acquainted` 恒真 ⇒ **逐字节回到重烘前**"
    "（实测：seeds 1-12 × 60 天 + `--golden` ⇒ 金标一致 12/12、含 12 条逐 tick 前缀链，S0 GATE PASS）。"
    "同一次改动里还有两处，两处都在门关时整段跳过："
    "① `_seed_scenario()` 的 `faction` 定向场景补种【组内 familiarity】"
    "（照同一函数里 `freerider` 分支已有的做法）——不种的话这条场景第 1 天一个派系都没有，"
    "等于把它自己要测的机制关掉；"
    "② 新增只观测的累计计数 `Sim.fac_unmet_placements`（决策路零引用，与 `endorse_events` 同一档）。"
    "★ `#25` 跟着收紧成合取式（docs/41 §2 第四个盲区：名字是合取而实现只查一半，#39 就这么漏的）："
    "现名为「S3派系派生一致(对齐且相识)」，三个计数分开报。"
    "⚠ 最值得写进锚里的一条：**只查终态的那版 `#25` 在 CI 自己的配置上没有牙**。"
    "负对照（隔离副本，只删 `and _acquainted(id, m)` 一处）："
    "N=12 × 20 天 ⇒ **3/3 全绿**（终态未谋面同派系=0）——因为 12 人的镇跑完之后人人都认识人人；"
    "而 N=60 × 20 天 ⇒ 红 0/3（未谋面同派系=15）、N=12 × 1 天 ⇒ 红 0/3（=3）。"
    "⇒ 加上累计计数之后，**同一个变异体在 N=12 × 20 天上红 0/3**"
    "（终态未谋面同派系=0、**全程未谋面归堆=32**），未变异的树在三个 fixture 上均无假红。"
    "★ 通道没有静默消失（docs/64 验收 3），seeds 1-12 × 60 天、同一条命令只差 `faction_fam_th`："
    "endorse 257 → **198**（⋅23%，覆盖 seed 12/12 → 12/12）、"
    "rally_oust 325 → **244**（⋅25%，12/12 → 12/12）、discuss 970 → **1053**（+8.6%）；"
    "门控事件类 16 种全部仍在发生；#16 声誉传播 12/12、#20 谣言变冷 12/12、#26 同派系亲和 12/12。"
    "代价明写：派系参与度（faction_size>=QUORUM 的 agent-tick）探针里 20641 → 15369（N=12 s1 对照臂，−26%）；"
    "`pact_dissolved` 3（3/12 seed）→ 0——它**不在**门控类里、硬 #33 是条件式判据所以两边都绿，"
    "基数又只有 3，按 docs/41 §5 只报告不下结论。"
    "⚠ **修好的只是一半，另一半按构造修不掉**：接触门把【从没见过面】那一半打成逐字节零影响"
    "（= 多镇/多 domain 那一格），但【见过面】那一半仍然存在："
    "`lin` 改主意 ⇒ 不再与 `tie` 对齐 ⇒ `tie` 掍回单人、跌破 QUORUM，而 `tie` 没经历任何事件。"
    "原因：`_aligned` 比的是对方**当前真实的** attitudes，任何建立在真实 attitudes 上的全局划分都有这个性质；"
    "真正的局部化要 per-agent 的「我以为他怎么想」模型 = 架构改动 ⇒ 按 docs/41 §0.8 先过外部对抗评审，本棒只留建议。"
    "留出种子 13-30 × 60 天：硬不变量 改前 18/18 → 改后 18/18（两侧均 S0 GATE PASS），"
    "软失败 改前 1（#40 @ seed 22，柴薪 0.48）→ 改后 1（#40 @ seed 18，口粮 0.42），"
    "逐 seed 饿穿两侧恒 0，endorse 365 → 304（17/18 → 18/18 覆盖）、rally_oust 358 → 312（18/18），"
    "事件数 3227-3542 → 3219-3592。"
    "三份提交锚同 commit 重烘：Harness seeds 段、DetGate scenarios 段（重烘后复跑 PASS 16/16）、ModelPathGate 锚。"
)

s = io.open(P, encoding="utf-8").read()
marker = '\n    ],\n    "scenarios_baked_by"'
assert s.count(marker) == 1, "marker not unique"
ins = json.dumps(ENTRY, ensure_ascii=False)
s = s.replace(marker, ",\n      " + ins + marker, 1)
io.open(P, "w", encoding="utf-8", newline="").write(s)

d = json.load(io.open(P, encoding="utf-8"))
h = d["_meta"]["rebake_history"]
print("entries:", len(h))
print("last starts:", h[-1][:60])
print("json OK, top keys:", list(d.keys()))
