#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把出货版的 stock_pull 块（带完整 _why）写进 game/data/production.json。
用法：ship.py <hi> <lo> <den>   —— 只动这一个键，其余文本逐字节不动。"""
import io, json, re, sys

HI, LO, DEN = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])

WHY = (
    "T1（docs/76）：工位广告的【镇库回拉】。"
    "★根因是结构性的，不是某个数没调好：Sim._object_candidates 给工位广告打分时，"
    "benefit 依次乘过 _phase_pref(时段) / _weather_mult(天气) / _season_mult(季节) / work_pull_mult(人口)，"
    "而 cl_mult 明写把带 job 的广告位排除在外 —— **这里面没有一项读 town_stock**。"
    "⇒ 镇上这种货空仓与满仓时，『去上工』这条候选的分数逐位相同，产出侧对短缺【开环】。"
    "后果：一个岗位 60 天的在班完成次数 ≈ Binomial(在班上台数, p)，而 p 是常数；"
    "实测 (t1_workfloor_probe, N=12 × 9 seed × 60 天, 走既有只读钩子 decision_sink, --selfcheck digest 逐字节不扰动) "
    "在班上台 76..257 次、p 的逐 seed 展布逐岗位是 泥瓦匠 25.8-40.0% · 环卫工 20.6-34.5% · 商贩 12.4-21.5% · "
    "渔夫 5.1-15.3% · 木匠 6.9-12.7% · 教书先生 4.2-8.5% · 杂役 2.7-7.6% · 面点师 2.0-13.9% · 咖啡师 1.3-10.1%（20 倍跨度）。"
    "低 p 的那几个 np≈4..20 ⇒ 相对标准差 22%..50% ⇒ 左尾是构造出来的。"
    "★开环的【另一头】此前没人量过：_stock_move 撞 cap 时 applied=min(delta, cap-cur)，满仓上工多出来的当场丢掉。"
    "拿 S1 的 60 个 seed 原始数据重算（申报批量×在班完成 vs event_log 真入账）丢弃占比："
    "口粮 5.1%(seed 50)..61.3%(seed 60) · 屋瓦 9.9%(seed 19)..55.6%(seed 30) · 柴薪 7.0%..51.3% · "
    "豆子 0.0%..80.7% · 话本 0.0%..54.3% · 整洁 0.0%..9.3% —— 有的 seed 一半以上的工时是白干的。"
)
WHY_FORM = (
    "形状 f = (hi·(cap − stock) + lo·stock) / (den · cap)：空仓 hi/den、满仓 lo/den，线性插值。"
    "★分子分母全整数、只做一次 IEEE 除法（除法是正确舍入的）⇒ 红线 #1 的逐位可复现；"
    "log/sqrt/pow 一概不用，理由与 K1 的池、L2 的 work_pull._form_why 逐字相同。"
    "★hi==lo==den ⇒ f ≡ 1.0【逐位】而不是『近似不动』—— 自带零假设对照：代码路照跑、乘法照做，而金标 12/12 逐字节不动（实测）。"
    "★为什么必须【两头都管】：#40 有两条臂，seeds 1-60 上各红过一次——下限臂 18/40/50/58（供不应求），"
    "上限臂 36（缺货绝迹 4/6）。只抬不压会把上限臂推得更红，实测 hi=180/lo=20 那一档正是这样："
    "下限臂全修好，却把 10 个 arm-critical seed 里的 4 个变成上限臂红。"
    "★三道门：① den<=0（缺本键/任一项非法）⇒ 恒 1.0，一条指令都不多跑；"
    "② mods_ok 生存门（含【抬】的一侧 ⇒ 这道门在这里承重，与 rhythm/weather/season/cleanliness/work_pull 共用）；"
    "③ _job_action(job)==action 且 _in_shift(job) —— 逐字就是 _produce_for 开头那道守卫。"
    "⚠ 门③ 【不是】照抄 L2 的 adv[\"job\"]!=\"\"：全镇九个岗位里恰好咖啡师那条广告没有 job 键"
    "（看摊来自 jobs.json.extra_advertises 与 interiors 的吧台），按 adv[\"job\"] 判会正好漏掉豆子那一族。"
    "用 _job_action（本仓库自己指定的『本职动作』单一真相源）则与 _produce_for 的范围在构造上重合。"
    "★不动 amount：amount/dur_total 是每 tick 回补的 need 量，改它就是改微观需求侧（docs/41 §0.5 写死微观不降级）；"
    "F1/F5/G3 三波手工标定出来的相对比例（34/20/46/46/46/32/46/38）一个字节没碰。"
)

BLK = (
    '\n  "stock_pull": {\n'
    '    "_why": %s,\n'
    '    "_form_why": %s,\n'
    '    "hi": %d,\n'
    '    "lo": %d,\n'
    '    "den": %d\n'
    '  },' % (json.dumps(WHY, ensure_ascii=False), json.dumps(WHY_FORM, ensure_ascii=False), HI, LO, DEN)
)

P = "game/data/production.json"
s = io.open(P, encoding="utf-8", newline="").read()
s = re.sub(r'\n  "stock_pull": \{.*?\n  \},', "", s, flags=re.S)
i = s.index('\n  "work_pull":')
out = s[:i] + BLK + s[i:]
json.loads(out)
io.open(P, "w", encoding="utf-8", newline="").write(out)
d = json.loads(out)["stock_pull"]
print("stock_pull hi=%d lo=%d den=%d  (_why %d 字, _form_why %d 字)" % (
    d["hi"], d["lo"], d["den"], len(d["_why"]), len(d["_form_why"])))
