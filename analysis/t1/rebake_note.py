#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""R12 ③：往两个提交锚的 _meta.rebake_history 各补一条（日期 + 为什么）。
标准 note 字段每次烘都会被覆盖，rebake_history 不会（docs/41 §3-3）。"""
import io, json

NOTE = (
    "2026-08-01 Wave T · T1 镇库回拉（stock_pull）上线 ⇒ 世界轨迹【蓄意】移动（docs/75 §一 / docs/47 R12）。"
    "为什么：#40 的红在 60 个 seed 上是【基率】而不是特例（docs/72：13-60 这 48 个留出 seed 上 5 红），"
    "而根因是产出侧【开环】—— Sim._object_candidates 给工位广告打分时一项都不读 town_stock，"
    "于是空仓与满仓时『去上工』的分数逐位相同，一个岗位 60 天的产出次数成了一次没有反馈的 Binomial 抽样。"
    "改动：production.json 新增 stock_pull{hi:110, lo:90, den:100}，"
    "f = (hi·(cap−stock) + lo·stock)/(den·cap) 乘进带本职动作且在班的那条候选的 benefit。"
    "★摘掉该键 ⇒ 48/48 seed digest 逐字节回到改前（完全可 ablate）；hi==lo==den ⇒ f≡1.0 逐位（零假设对照，金标 12/12 不动）。"
    "验收（门自己的判决行，多 seed 网格、不受 Harness.gd:311 单 seed 恒过那条陷阱影响）："
    "--seeds 13-60 改前 S0 GATE FAIL ❌（#40 43/48，软门 ≥44/48 破）→ 改后 PASS ✅（#40 47/48）；"
    "--seeds 49-60 改前 FAIL ❌（docs/72 §1.3 逐字记录）→ 改后 PASS ✅（#40 12/12）；"
    "seeds 1-12 改前后皆 0/12 红、硬不变量 12/12、饿穿 0。"
    "剩余边界：seed 44 豆子 0.495（低于 SUPPLY_FLOOR 0.005），是本次改动重排出来的【新】边缘 seed，据实记在 docs/76 §6.2。"
    "判据一个字节没动（Invariants.gd 未改），SUPPLY_FLOOR/SUPPLY_MIN_DEMAND/SUPPLY_MIN_DAYS 与软通过率门均未放宽。"
)

for p in ["game/bench/golden_digests.json", "game/bench/modelpath_anchor.json"]:
    d = json.load(io.open(p, encoding="utf-8"))
    m = d.setdefault("_meta", {})
    h = m.setdefault("rebake_history", [])
    if not any(s.startswith("2026-08-01 Wave T · T1") for s in h):
        h.append(NOTE)
    # 格式与引擎自己写出来的一致（indent=2 + 键排序），免得 diff 里全是重排噪声
    io.open(p, "w", encoding="utf-8", newline="\n").write(
        json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print("%s  rebake_history 条数 = %d" % (p, len(h)))
