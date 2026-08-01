# -*- coding: utf-8 -*-
"""同 seed 配对符号检验：ON 与 OFF 在每一类事件上的方向一致性。
零假设参照就在同一张表里——绝大多数通道会在 5..7 / 12 附近摆（=轨迹重排的噪声），
只有真正被机制推动的那一条会贴到 11-12/12。"""
import json, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
off = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
on = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
n = len(off)
keys = set()
for r in off + on:
    keys |= set(r["by_type"].keys())
rows = []
for k in sorted(keys):
    a = [r["by_type"].get(k, {}).get("n", 0) for r in off]
    b = [r["by_type"].get(k, {}).get("n", 0) for r in on]
    lo = sum(1 for x, y in zip(a, b) if y < x)
    hi = sum(1 for x, y in zip(a, b) if y > x)
    rows.append((max(lo, hi), k, sum(a), sum(b), lo, hi, n - lo - hi))
print("配对符号检验（n=%d seed）" % n)
for m, k, sa, sb, lo, hi, eq in sorted(rows, reverse=True):
    flag = "  <== 方向一致" if m >= n - 1 else ""
    print("  %-14s OFF和=%-6d ON和=%-6d  ON更低 %2d / ON更高 %2d / 平 %2d%s"
          % (k, sa, sb, lo, hi, eq, flag))
