#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""逐条【实测】每个注入的最便宜证伪路径与耗时。

S2（docs/73 §一·2-2）断言五类注入的证伪成本"差两个数量级"，并把它当成"不许合并分层"的理由。
**那条断言本身从来没有被测过**——它是从"改行号 `sed -n` 一秒；改基线数字要重跑 60 天 × 12 seed"
推出来的。本脚本把它变成实测：对每一条注入，找出**一根棒实际可用的最便宜的那条路**并计时。

关键的一问：L4 那条"要重跑一次网格"的路，**是不是真的没有更便宜的替代**？
在这个仓库里，绝大多数基线数字都被某一份回执**原样又写了一遍**——
若真值能在树上被 grep 到，那么 L4 的真实成本就不是 `rerun`，是 `xref`。
"""
import json, os, subprocess, sys, time, glob

sys.stdout.reconfigure(encoding="utf-8")
REPO = sys.argv[1]
KEYDIR = sys.argv[2]


def t(fn):
    a = time.perf_counter()
    r = fn()
    return r, time.perf_counter() - a


def sh(*args):
    return subprocess.run(args, cwd=REPO, capture_output=True, text=True, errors="replace")


def route(k, brief_rel):
    """返回 (路径类别, 耗时秒, 证据一行)。"""
    s, tv, fv = k["stratum"], str(k["true_value"]), str(k["false_value"])

    if s == "L2_path":
        r, dt = t(lambda: os.path.exists(os.path.join(REPO, fv)))
        return "exists", dt, "os.path.exists(%s) = %s" % (fv, r)

    if s == "L3_symbol":
        r, dt = t(lambda: sh("git", "grep", "-c", "-F", "--", fv))
        return "grep", dt, "git grep -F %s → %d 行" % (fv, len(r.stdout.splitlines()))

    if s == "L1_lineno":
        f = k.get("file", "")
        r, dt = t(lambda: sh("sed", "-n", "%sp" % fv, f))
        return "sed", dt, "%s:%s = %s" % (f, fv, r.stdout.strip()[:60])

    if s == "L4_number":
        # 真值能不能在【别的已提交文本文件】里被 grep 到？能 ⇒ 成本是 xref，不是 rerun。
        # ⚠ 必须加数字边界并排掉二进制：第一版用裸 `git grep -F` 得到「`2.18` 在 24 个文件里」，
        #   而其中两个是 `docs/media/cover.png` 与一张 svg —— 正是本棒刚在对分器里修掉的
        #   那个"无边界子串"毛病，我自己的探针又犯了一遍。**同一个错，一天之内第三次。**
        pat = r"(^|[^0-9.])" + tv.replace(".", r"\.") + r"([^0-9.]|$)"
        r, dt = t(lambda: sh("git", "grep", "-nIE", "--", pat,
                             "--", "*.md", "*.gd", "*.py", "*.sh", "*.json", "*.txt"))
        hits = [l for l in r.stdout.splitlines() if l and not l.startswith(brief_rel + ":")]
        if hits:
            return "xref", dt, "真值 %s 命中 %d 行文本，例：%s" % (tv, len(hits), hits[0][:80])
        return "rerun", float("nan"), "真值 %s 在树上只出现在 brief 自己里 ⇒ 只能重跑" % tv

    if s in ("L5_gate", "L6_accept"):
        # 这条假断言在契约里有没有【已经写死的】反例？有 ⇒ 成本是 read，不是 rerun/judge。
        keys = {
            "lod_verify": "分辨率恰好是零", "视觉门": "§6", "金标": "§3",
            "BackendGate": "不守别的", "_ready()": "从不执行",
            "emote": "永远拍不到 emote", "letterbox": "拍不出 letterbox",
            "docker": "5.3-10.8", "getbbox": "alpha_only", "tick=0": "tick≈0",
            "backend=null": "根本不进",
        }
        for probe, _ in keys.items():
            if probe in fv:
                r, dt = t(lambda: sh("git", "grep", "-c", "-F", "--", probe, "docs/41-baton-contract.md"))
                n = r.stdout.strip().split(":")[-1] if ":" in r.stdout else r.stdout.strip()
                return "read-contract", dt, "docs/41 里 `%s` 出现 %s 次" % (probe, n or "0")
        return "judge", float("nan"), "契约里没有现成反例，只能靠判断"
    return "?", float("nan"), ""


print("%-4s %-4s %-10s %-14s %-9s %s" % ("臂", "id", "层", "标签成本", "实测路径", "秒 / 证据"))
rows = []
for kf in sorted(glob.glob(os.path.join(KEYDIR, "*.key.json"))):
    arm = os.path.basename(kf).split(".")[0]
    if arm in ("C1",):                      # C1 与 A2 逐字节同一份钥匙
        continue
    key = json.load(open(kf, encoding="utf-8"))
    for k in key["injections"]:
        cls, dt, ev = route(k, key["brief"])
        rows.append((arm, k["id"], k["stratum"], k["cost"], cls, dt, ev))
        print("%-4s %-4s %-10s %-14s %-9s %s  | %s"
              % (arm, k["id"], k["stratum"], k["cost"], cls,
                 "  n/a" if dt != dt else "%6.3f" % dt, ev[:88]))

print("\n── 按层汇总：标签成本 vs 实测最便宜路径 ──")
agg = {}
for arm, i, s, lab, cls, dt, ev in rows:
    agg.setdefault(s, {}).setdefault(cls, 0)
    agg[s][cls] += 1
for s in sorted(agg):
    print("  %-10s %s" % (s, "  ".join("%s×%d" % (c, n) for c, n in sorted(agg[s].items()))))
