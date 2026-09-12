#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""U1 干预 H-free：把 话本/豆子 的申报批量压低，让这两种货【真的会缺】。
文本级替换，只动这两个数字，其余逐字节不动。用法：cut.py <gamedir>"""
import io, json, os, re, sys

P = os.path.join(sys.argv[1], "data", "production.json")
s = io.open(P, encoding="utf-8", newline="").read()
GOOD_BOOK = "话本"   # 话本
GOOD_BEAN = "豆子"   # 豆子
for good, old, new in [(GOOD_BOOK, 6, 3), (GOOD_BEAN, 36, 24)]:
    pat = re.compile(r'("good"\s*:\s*"%s"\s*,\s*"amount"\s*:\s*)%d\b' % (good, old))
    s, n = pat.subn(lambda m: m.group(1) + str(new), s)
    assert n == 1, (good, n)
json.loads(s)
io.open(P, "w", encoding="utf-8", newline="").write(s)
d = json.loads(s)["produce"]
print(P, "->", json.dumps({k: v for k, v in d.items() if v["good"] in (GOOD_BOOK, GOOD_BEAN)}, ensure_ascii=True))
