#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Z2 · 「镜像」这条取值规则的量级核对。

V1 给环卫工取 `standing = 0.25` 的理由是**抄**：它恰是整洁自己那条 `shortage_standing = -0.25`
的相反数。本棒把同一条规则铺到别的岗位（`standing = −该岗位产物的 shortage_standing`）之前，
先把**两侧真正投放出去的总量**量出来——per-event 对称不等于 per-run 对称：
  负向：每条 shortage 事件给 (当事人 + 在场者) 各记一笔 shortage_standing（`_shortage_fallout`）
  正向：每条被看见的 produce 给每个在场者记一笔 craft_credit.standing（`_craft_fallout`）
两侧的**次数**由完全不同的机制决定（缺货有每天每货一次的 dedup，产出没有）。

用法：python analysis/z2/mirror_scale.py <a.jsonl> ...
"""
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")

ORDER = ["面点师", "渔夫", "杂役", "木匠", "咖啡师", "教书先生", "环卫工", "泥瓦匠", "商贩"]
# game/data/production.json：goods[*].shortage_standing，缺则用顶层 shortage_standing
GOOD_OF = {"面点师": "口粮", "渔夫": "口粮", "杂役": "柴薪", "木匠": "柴薪",
           "咖啡师": "豆子", "教书先生": "话本", "环卫工": "整洁", "泥瓦匠": "屋瓦"}
SS = {"口粮": -0.5, "柴薪": -0.5, "豆子": -0.5, "话本": -0.5, "整洁": -0.25, "屋瓦": -0.35}


def load(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def main(path):
    rows = load(path)
    print("== %s  (n=%d seed) ==" % (path, len(rows)))
    print("%-7s %-4s %7s | %-38s | %-38s" % ("岗位", "货", "镜像值",
                                             "负向：Σ(被指责事件 + 其在场人次)×|ss|",
                                             "正向：Σ(产出在场人次)×镜像值"))
    for t in ORDER:
        g = GOOD_OF.get(t, "")
        if g == "":
            continue
        ss = SS[g]
        neg_ev, neg_slots, pos_slots = 0, 0, 0
        for r in rows:
            j = r["jobs"].get(t)
            if j is None:
                continue
            neg_ev += int(j["ev_blamed"])
            neg_slots += int(j["ev_blamed_witness_slots"])
            pos_slots += int(j["produce_bystanders"]["sum"])
        neg_units = neg_ev + neg_slots          # 当事人 1 + 在场者 n（近似：责任人自己被跳过）
        print("%-7s %-4s %7.2f | %5d 事件 + %5d 人次 = %5d 笔 × %.2f = %7.2f | %5d 人次 × %.2f = %7.2f"
              % (t, g, -ss, neg_ev, neg_slots, neg_units, -ss, neg_units * -ss,
                 pos_slots, -ss, pos_slots * -ss))
    print()


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
