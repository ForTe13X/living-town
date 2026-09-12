# -*- coding: utf-8 -*-
"""W1：把 aid 漏斗逐级、逐 seed 打出来。展布不给均值（docs/41 §5）。
用法：python funnel_table.py <tag1> <tag2> ...   （tag 对应 analysis/w1/log_<tag>.txt）"""
import json, io, os, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))

def load(tag):
    p = os.path.join(HERE, "log_%s.txt" % tag)
    out = []
    for line in io.open(p, encoding="utf-8", errors="replace"):
        if line.startswith("[W1FUNNEL] "):
            out.append(json.loads(line[len("[W1FUNNEL] "):]))
    return out

tags = sys.argv[1:]
arms = {t: load(t) for t in tags}
seeds = [r["seed"] for r in arms[tags[0]]]

def col(t, f):
    return [f(r) for r in arms[t]]

ROWS = [
    ("digest",              lambda r: r["digest"]),
    ("① 盟约 tick 和",       lambda r: r["funnel"]["pact_ticksum"]),
    ("  盟约成立/解体",      lambda r: "%d/%d" % (r["funnel"]["pact_formed"], r["funnel"]["pact_dissolved"])),
    ("② 决策点·有盟约",      lambda r: r["funnel"]["dp_haspact"]),
    ("③ 决策点·盟友同区",    lambda r: r["funnel"]["dp_pactnear"]),
    ("  同区人次",           lambda r: r["funnel"]["pair_pactnear"]),
    ("  其中在讲话(被跳过)", lambda r: r["funnel"]["pair_talking"]),
    ("  其中 need 低",       lambda r: r["funnel"]["pair_lowneed"]),
    ("④ aid 候选决策点",     lambda r: r["funnel"]["dp_aidcand"]),
    ("⑤ aid 被选中",         lambda r: r["funnel"]["dp_aidpick"]),
    ("⑥ aid 事件(落地)",     lambda r: r["ev_aid"]),
    ("  aid 被拒",           lambda r: r["ev_aid"] - r["ev_aid_accepted"]),
    ("社交段·被生存门关",     lambda r: r["funnel"]["dp_soc_shut_surv"]),
    ("社交段·被 social 饱和关", lambda r: r["funnel"]["dp_soc_shut_full"]),
    ("决策点总数",           lambda r: r["funnel"]["dp"]),
]

print("seed                      ", " ".join("%8s" % s for s in seeds))
for tag in tags:
    print("\n===== 臂 %s =====" % tag)
    for name, f in ROWS:
        print("%-26s" % name, " ".join("%8s" % v for v in col(tag, f)))
    lt = {}
    for r in arms[tag]:
        for k, v in r["funnel"]["lost_to"].items():
            lt[k] = lt.get(k, 0) + v
    print("%-26s" % "aid 输给了谁(12 seed 合计)", sorted(lt.items(), key=lambda kv: -kv[1]))

print("\n\n===== 逐级合计与级差比（12 seed 求和）=====")
STAGES = [
    ("① 盟约 tick 和",      lambda r: r["funnel"]["pact_ticksum"]),
    ("② 有盟约决策点",      lambda r: r["funnel"]["dp_haspact"]),
    ("③ 盟友同区决策点",    lambda r: r["funnel"]["dp_pactnear"]),
    ("④ aid 候选决策点",    lambda r: r["funnel"]["dp_aidcand"]),
    ("⑤ aid 被选中",        lambda r: r["funnel"]["dp_aidpick"]),
    ("⑥ aid 事件",          lambda r: r["ev_aid"]),
]
base = tags[0]
hdr = "%-22s" % "" + "".join("%14s" % t for t in tags)
print(hdr)
for name, f in STAGES:
    vals = [sum(col(t, f)) for t in tags]
    print("%-22s" % name + "".join("%14s" % v for v in vals))
print("%-22s" % "—— 相对 %s ——" % base)
for name, f in STAGES:
    b = sum(col(base, f))
    vals = [(sum(col(t, f)) / b if b else 0) for t in tags]
    print("%-22s" % name + "".join("%14s" % ("%.3f" % v) for v in vals))
print("%-22s" % "级间转化率:")
prev = None
for name, f in STAGES:
    if prev is None:
        prev = (name, f); continue
    row = []
    for t in tags:
        a = sum(col(t, prev[1])); b = sum(col(t, f))
        row.append("%.4f" % (b / a) if a else "-")
    print("%-22s" % (prev[0][0] + "→" + name[0]) + "".join("%14s" % v for v in row))
    prev = (name, f)

print("\n\n===== 配对符号检验（vs %s，逐 seed）=====" % base)
for name, f in [("aid 事件", lambda r: r["ev_aid"]),
                ("aid 候选点", lambda r: r["funnel"]["dp_aidcand"]),
                ("盟约 tick 和", lambda r: r["funnel"]["pact_ticksum"])]:
    print("  %s" % name)
    a = col(base, f)
    print("    %-10s %s   和=%d" % (base, a, sum(a)))
    for t in tags[1:]:
        b = col(t, f)
        lo = sum(1 for x, y in zip(a, b) if y < x)
        hi = sum(1 for x, y in zip(a, b) if y > x)
        print("    %-10s %s   和=%d   低%2d/高%2d/平%2d" % (t, b, sum(b), lo, hi, len(a) - lo - hi))
