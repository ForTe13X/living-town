#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""U1：把 stock_pull 键写进【出货】production.json（带 _why），文本级插入，其余逐字节不动。"""
import io, json, re

P = "game/data/production.json"
s = io.open(P, encoding="utf-8", newline="").read()
EOL = "\r\n" if "\r\n" in s else "\n"
s = re.sub(r'\r?\n  "stock_pull": \{[^{}]*\},', "", s)

WHY = (
    "T1（docs/76）做出机制、U1（docs/80）把它打开。"
    "★它修的是一条【结构】缺陷，不是某个数没调好：_object_candidates 给一条工位广告打分时，"
    "phase/weather/season/clean/work_pull/work_urgency/距离 七项里没有任何一项读 town_stock "
    "⇒ 镇上这种货【空仓】与【满仓】时，『去上工』这条候选的分数逐位相同——产出侧对短缺是开环的，两头都是："
    "空仓时没有任何东西把工人叫回工位，满仓时也没有任何东西让他歇一歇"
    "（T1 实测：面点师在【镇上一粒口粮都没有】的时刻被摆到台面上 449 次、接了 17 次；"
    "另一头有的 seed 一半以上的工时撞 cap 当场丢掉，口粮丢弃占比最高 61.3%）。"
    "★形状 f = (hi·(cap−stock) + lo·stock) / (den·cap)：空仓 f=hi/den、满仓 f=lo/den、线性插值。"
    "分子分母全整数、只做一次 IEEE 除法（正确舍入）⇒ 红线#1 逐位可复现；log/sqrt/pow 一概不用。"
    "★hi==lo==den ⇒ f≡1.0 逐位（自带零假设对照：代码路照跑、乘法照做，而世界不动）。"
    "★删掉本键 ⇒ stock_pull_den=0 ⇒ _stock_pull_mult 第一行返回 1.0、连乘法都不进 ⇒ 逐字节回到 T1 之前"
    "（缺数据即零扰动，同 work_pull / scale）。"
    "★为什么是 110/90：T1 §2.4 在看到 48-seed 结果【之前】写下的选档规则——"
    "①seeds 13-60 两条臂都要 0 红；②seeds 1-12 不许回归；③满足前两条里取【离 1.0 最近】的一档（最小干预）。"
    "扫过的四档全部报在 docs/76 §三（110/90 · 110/85 · 120/80 · 130/70），实测这族参数【非单调】"
    "（120/80 比 110/90 更强却更差）⇒ 不声称任何一档最优。"
    "★U1 补的那一半：本键第一次打开时把 ci.sh 4a（N=16）顶红，成因是 work_pull_mult(16)=1.125 "
    "把阻尼那一半整个抵消（合成区间 [1.0125,1.2375]）。U1 的修法不在这两个数上，在 Sim._object_candidates "
    "里【人口项与库存项不叠加】（见那一段 ★★★U1 注释）⇒ 合成区间恒为 [0.90,1.10]、与 N 无关。"
    "★U1 实测（判据一个字节没改）：N=16 seeds1-12 #40 红 3/12 → 0/12、零缺货货数 max 4 → 3（回到未改动树的余量）、"
    "最差货 min 0.661 → 0.627（未改动树 0.556）；N=12 seeds1-12 与 13-60 的 digest 与不加 U1 那一段【逐字节相同】"
    "（12/12 + 48/48），因为 N=12 上 work_pull_mult ≡ 1.0、那一段一条指令都不多跑。"
    "★没做到的那一格：seeds 13-60 上仍有 1 个红（seed 44 豆子 0.495，比 SUPPLY_FLOOR 低 0.005）——"
    "它不是原来那五个中的任何一个，是本改动重排出来的新边缘 seed，软门（≥44/48）过而 T1 自己写的『0/48』没达标。"
)

blk = (EOL + '  "stock_pull": {' + EOL
       + '    "_why": ' + json.dumps(WHY, ensure_ascii=False) + ',' + EOL
       + '    "hi": 110, "lo": 90, "den": 100' + EOL
       + '  },')
i = s.index(EOL + '  "work_pull":')
out = s[:i] + blk + s[i:]
json.loads(out)
io.open(P, "w", encoding="utf-8", newline="").write(out)
print("stock_pull =", {k: v for k, v in json.loads(out)["stock_pull"].items() if k != "_why"})
