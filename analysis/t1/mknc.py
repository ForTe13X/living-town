#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1 负对照：在【隔离副本】里造两个变异体（出货树不动）。用法：mknc.py <scratch_dir>
  nc1 = 出货档 + 面点师申报批量归零（产者被掐断）  -> #40 必须红
  nc2 = 出货档 + hi=300/lo=100（只抬不压、抬到过冲）-> 上限臂必须红
"""
import io, json, os, re, sys

SC = sys.argv[1]


def setkey(path, hi, lo, den):
    s = io.open(path, encoding="utf-8", newline="").read()
    s = re.sub(r'\n  "stock_pull": \{.*?\n  \},', "", s, flags=re.S)
    s = re.sub(r'\n  "stock_pull": \{[^{}]*\},', "", s)
    blk = '\n  "stock_pull": {"hi": %d, "lo": %d, "den": %d},' % (hi, lo, den)
    i = s.index('\n  "work_pull":')
    out = s[:i] + blk + s[i:]
    json.loads(out)
    io.open(path, "w", encoding="utf-8", newline="").write(out)
    return json.loads(out)


# nc1：出货档 + 面点师 amount 0
p = os.path.join(SC, "g_nc1", "data", "production.json")
d = setkey(p, 110, 90, 100)
s = io.open(p, encoding="utf-8", newline="").read()
s2 = s.replace('"面点师": {\n      "good": "口粮",\n      "amount": 90\n    }',
               '"面点师": {\n      "good": "口粮",\n      "amount": 0\n    }')
if s2 == s:
    # 排版可能不同，退回按 json 结构写
    d = json.loads(s)
    d["produce"]["面点师"]["amount"] = 0
    s2 = json.dumps(d, ensure_ascii=False, indent=2)
io.open(p, "w", encoding="utf-8", newline="").write(s2)
print("nc1 面点师.amount =", json.loads(io.open(p, encoding="utf-8").read())["produce"]["面点师"]["amount"],
      " stock_pull =", json.loads(io.open(p, encoding="utf-8").read())["stock_pull"])

# nc2：只抬不压、抬到过冲
p = os.path.join(SC, "g_nc2", "data", "production.json")
d = setkey(p, 300, 100, 100)
print("nc2 stock_pull =", d["stock_pull"])
