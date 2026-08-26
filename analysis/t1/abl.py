#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1 消融对照：带新代码但【没有 stock_pull 键】的树，digest 必须与 S1 在改动前那棵树逐字节相同。
用法：abl.py <off.log-or-jsonl> <s1_a.jsonl> [s1_b.jsonl ...]"""
import io, json, sys


def loadlog(p):
    out = {}
    for ln in io.open(p, encoding="utf-8", errors="replace"):
        i = ln.find("[SCALE] ")
        if i < 0:
            continue
        r = json.loads(ln[i + 8:])
        out[r["seed"]] = r
    if out:
        return out
    for ln in io.open(p, encoding="utf-8"):
        ln = ln.strip()
        if ln:
            r = json.loads(ln)
            out[r["seed"]] = r
    return out


def main():
    cur = loadlog(sys.argv[1])
    ref = {}
    for p in sys.argv[2:]:
        ref.update(loadlog(p))
    seeds = sorted(set(cur) & set(ref))
    same = 0
    diff = []
    for s in seeds:
        if cur[s]["digest"] == ref[s]["digest"]:
            same += 1
        else:
            diff.append((s, ref[s]["digest"], cur[s]["digest"]))
    print("消融对照（新代码 + 无 stock_pull 键  vs  S1 改动前的树）：digest 相同 %d/%d seed" % (same, len(seeds)))
    for s, a, b in diff:
        print("  ✗ seed %d: %s -> %s" % (s, a, b))
    if not diff and seeds:
        print("  ⇒ 逐字节可 ablate：摘掉 production.json 的 stock_pull 键 = 逐字节回到 T1 之前")


main()
