#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1 扫描用：往 game/data/production.json 写/删 stock_pull 键。
用法：setpull.py off | setpull.py <hi> <lo> <den>
★只动这一个键，其余逐字节不动（json.load/dump 会重排格式 ⇒ 用文本级替换，别整份重写）。"""
import io, json, re, sys

P = "game/data/production.json"
s = io.open(P, encoding="utf-8", newline="").read()

# 先把已有的 stock_pull 块整段删掉（含尾随逗号与换行）
s2 = re.sub(r'\n  "stock_pull": \{[^{}]*\},', "", s)

if sys.argv[1] == "off":
    out = s2
else:
    hi, lo, den = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    blk = ('\n  "stock_pull": {"_t1": "T1 sweep", "hi": %d, "lo": %d, "den": %d},' % (hi, lo, den))
    # 插在 "work_pull" 块之前（位置不影响语义；固定位置便于 diff）
    i = s2.index('\n  "work_pull":')
    out = s2[:i] + blk + s2[i:]

json.loads(out)  # 语法自检：写坏了当场炸，而不是让 godot 静默降级到"缺文件即零扰动"
io.open(P, "w", encoding="utf-8", newline="").write(out)
d = json.loads(out)
print("stock_pull =", d.get("stock_pull", "(none)"))
