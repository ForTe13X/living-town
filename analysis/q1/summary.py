# -*- coding: utf-8 -*-
"""隔离臂/出货臂逐格汇总：派系是否被改变、chain 是否分叉、判决。"""
import re, glob, os, io

d = os.path.dirname(os.path.abspath(__file__))


def cells(tag):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, tag + "_n*_s*.txt"))):
        m = re.search(r"_n(\d+)_s(\d+)\.txt$", f)
        N, S = int(m.group(1)), int(m.group(2))
        txt = io.open(f, encoding="utf-8", errors="replace").read()
        rec = {}
        for b in re.split(r"\[Q1\] === ", txt)[1:]:
            arm = b.split(" ")[0]
            def g(p, dflt=""):
                mm = re.search(p, b)
                return mm.group(1) if mm else dflt
            who = g(r"faction 变的人: \[(.*?)\]")
            rec[arm] = dict(
                fac=g(r"faction@(\S+?)\s"),
                nwho=len(re.findall(r'"[^"]+"', who)) if who else 0,
                chain=g(r"chain同=(\w+)"),
                co=g(r"同区 tick=(\d+)"),
                fam=g(r"familiarity总和=([\d.]+)"),
                verdict=g(r"判决: (\S+?)\s"),
            )
        out[(N, S)] = rec
    return out


pre, post = cells("pre"), cells("post")
print("%-4s %-5s | %-34s | %-34s" % ("N", "seed", "隔离臂 修复前", "隔离臂 修复后"))
print("%-4s %-5s | %-8s %-6s %-6s %-10s | %-8s %-6s %-6s %-10s" % (
    "", "", "co/fam", "fac@", "变人数", "chain同", "co/fam", "fac@", "变人数", "chain同"))
stat = dict(pre_fac=0, pre_div=0, post_fac=0, post_div=0, n=0, iso_ok=0)
for k in sorted(set(pre) | set(post)):
    a = pre.get(k, {}).get("QATT1", {})
    b = post.get(k, {}).get("QATT1", {})
    print("%-4d %-5d | %-8s %-6s %-6s %-10s | %-8s %-6s %-6s %-10s" % (
        k[0], k[1],
        "%s/%s" % (a.get("co", "?"), a.get("fam", "?")), a.get("fac", "?"), a.get("nwho", 0), a.get("chain", "?"),
        "%s/%s" % (b.get("co", "?"), b.get("fam", "?")), b.get("fac", "?"), b.get("nwho", 0), b.get("chain", "?")))
    stat["n"] += 1
    if a.get("co") == "0" and float(a.get("fam", 1) or 1) == 0.0 and b.get("co") == "0" and float(b.get("fam", 1) or 1) == 0.0:
        stat["iso_ok"] += 1
    if a.get("fac", "从未") != "从未": stat["pre_fac"] += 1
    if a.get("chain") == "false": stat["pre_div"] += 1
    if b.get("fac", "从未") != "从未": stat["post_fac"] += 1
    if b.get("chain") == "false": stat["post_div"] += 1
print()
print("格数 %d ｜ 隔离自证(co=0 且 fam=0，两侧) %d/%d" % (stat["n"], stat["iso_ok"], stat["n"]))
print("隔离臂 修复前：别人 faction 被改 %d 格 · 世界 chain 分叉 %d 格" % (stat["pre_fac"], stat["pre_div"]))
print("隔离臂 修复后：别人 faction 被改 %d 格 · 世界 chain 分叉 %d 格" % (stat["post_fac"], stat["post_div"]))
print()
print("— 出货臂（⚠ 修复前后是两个不同的世界，不是受控对照）—")
print("%-4s %-5s | %-22s | %-22s" % ("N", "seed", "修复前 fac@ / 变人数 / 判决", "修复后 fac@ / 变人数 / 判决"))
n_pre_clean = n_pre_fire = n_post_clean = n_post_fire = 0
for k in sorted(set(pre) | set(post)):
    a = pre.get(k, {}).get("ATT1", {})
    b = post.get(k, {}).get("ATT1", {})
    print("%-4d %-5d | %-6s %-3s %-14s | %-6s %-3s %-14s" % (
        k[0], k[1], a.get("fac", "?"), a.get("nwho", 0), a.get("verdict", "?"),
        b.get("fac", "?"), b.get("nwho", 0), b.get("verdict", "?")))
    if a.get("fac", "从未") != "从未":
        n_pre_fire += 1
        if a.get("verdict", "").startswith("★"): n_pre_clean += 1
    if b.get("fac", "从未") != "从未":
        n_post_fire += 1
        if b.get("verdict", "").startswith("★"): n_post_clean += 1
print()
print("出货臂 修复前：触发 %d/%d 格，其中时序干净(★) %d" % (n_pre_fire, stat["n"], n_pre_clean))
print("出货臂 修复后：触发 %d/%d 格，其中时序干净(★) %d" % (n_post_fire, stat["n"], n_post_clean))
