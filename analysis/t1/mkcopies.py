#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1 扫描：往【隔离副本】里各写一份 stock_pull（出货树本身保持 off）。用法：mkcopies.py <scratch_dir>"""
import io, json, os, re, sys

SC = sys.argv[1]
CFG = {"g_120": (120, 80, 100), "g_130": (130, 70, 100), "g_110": (110, 90, 100)}
for d, (hi, lo, den) in CFG.items():
    P = os.path.join(SC, d, "data", "production.json")
    s = io.open(P, encoding="utf-8", newline="").read()
    s = re.sub(r'\n  "stock_pull": \{[^{}]*\},', "", s)
    blk = '\n  "stock_pull": {"_t1": "T1 sweep", "hi": %d, "lo": %d, "den": %d},' % (hi, lo, den)
    i = s.index('\n  "work_pull":')
    out = s[:i] + blk + s[i:]
    json.loads(out)
    io.open(P, "w", encoding="utf-8", newline="").write(out)
    print(d, json.loads(out)["stock_pull"])
P = os.path.join(SC, "g_off", "data", "production.json")
print("g_off", json.load(io.open(P, encoding="utf-8")).get("stock_pull", "(none)"))
