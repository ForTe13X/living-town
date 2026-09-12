#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""U1: write/remove production.stock_pull in an arbitrary game dir (text-level, one key only).
usage: setkey.py <gamedir> off | setkey.py <gamedir> <hi> <lo> <den>"""
import io, json, os, re, sys

P = os.path.join(sys.argv[1], "data", "production.json")
s = io.open(P, encoding="utf-8", newline="").read()
s2 = re.sub(r'\n  "stock_pull": \{[^{}]*\},', "", s)
if sys.argv[2] == "off":
    out = s2
else:
    hi, lo, den = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    blk = '\n  "stock_pull": {"_u1": "U1 sweep", "hi": %d, "lo": %d, "den": %d},' % (hi, lo, den)
    i = s2.index('\n  "work_pull":')
    out = s2[:i] + blk + s2[i:]
json.loads(out)
io.open(P, "w", encoding="utf-8", newline="").write(out)
print(P, "stock_pull =", json.loads(out).get("stock_pull", "(none)"))
