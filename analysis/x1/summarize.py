"""X1: 把 ScaleSupply / x1_margin 的 JSONL 汇总成回执里那几张表。

纪律（docs/41 §5）：**逐 seed，不给均值**；极值连并列一起报；
不重写判据——红绿一律读记录里 `hard_fails` / `soft_fails`（它们由 Inv.check_all 现算），
本脚本只做分组与排序。
"""
import json, sys, glob, os


def load(paths):
    rows = []
    seen = {}
    for p in paths:
        # ⚠ 半行 / 半个 UTF-8 序列 = 那一片**还在跑**。W2 记过这一条：静默跳过会把
        #   "红 1/60" 悄悄变成 "红 1/59"，而没有人会发现 ⇒ 这里点名文件并退出，不容错。
        try:
            raw = open(p, encoding="utf-8").read()
        except UnicodeDecodeError:
            sys.exit("%s 读到半个 UTF-8 序列 ⇒ 这一片还在写。等它跑完再汇总。" % p)
        for i, line in enumerate(raw.splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                sys.exit("半行 JSON（那一片可能还在跑）：%s:%d" % (p, i))
            k = (r.get("n_agents"), r["seed"])
            if k in seen:
                sys.exit("重复 (N,seed)=%s：%s 与 %s" % (k, seen[k], p))
            seen[k] = p
            rows.append(r)
    rows.sort(key=lambda r: (r.get("n_agents", 0), r["seed"]))
    return rows


def kouliang_rate(r):
    g = r.get("final", {}).get("goods", {})
    kl = g.get("口粮")
    if not kl:
        return None, None
    return kl.get("rate"), kl.get("shortage_days")


def worst_rate(r):
    g = r.get("final", {}).get("goods", {})
    w, wg = None, None
    for name, gg in g.items():
        if not gg.get("gated"):
            continue
        if w is None or gg["rate"] < w:
            w, wg = gg["rate"], name
    return w, wg


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit("用法: summarize.py <jsonl...>")
    files = []
    for p in paths:
        files.extend(sorted(glob.glob(p)))
    rows = load(files)
    print("局数 = %d   文件 = %d" % (len(rows), len(files)))
    hard, soft = [], []
    print("\nseed | #01硬 | by_need | 触底者 | #40软 | 口粮满足率(断供天) | 最差货")
    for r in rows:
        h = r.get("hard_fails", [])
        s = r.get("soft_fails", [])
        kr, kd = kouliang_rate(r)
        wr, wg = worst_rate(r)
        if h:
            hard.append(r)
        # ⚠ 这里第一版写的是 `if s:`（**任何**软不变量红就算），于是 seed 26 的 `#26` 被我
        #   读成了"第 12 个 #40 红"，直接跟 W2 的 11 个对不上。判据要点名，不能"非空即算"。
        if 40 in s:
            soft.append(r)
        print("%4d | %-6s | %-22s | %-12s | %-6s | %s | %s" % (
            r["seed"], ",".join(map(str, h)) or "-",
            json.dumps(r.get("starve_by_need", r.get("by_need", {})), ensure_ascii=False),
            ",".join(r.get("starve_by_agent", {}).keys() if isinstance(r.get("starve_by_agent"), dict) else r.get("starve_agents", [])) or "-",
            ",".join(map(str, s)) or "-",
            ("%.3f(%s天)" % (kr, kd)) if kr is not None else "-",
            ("%.3f %s" % (wr, wg)) if wr is not None else "-"))

    print("\n=== 汇总 ===")
    print("硬 #01 红的 seed: %s" % ([r["seed"] for r in hard] or "无"))
    print("软 #40 红的 seed: %s" % ([r["seed"] for r in soft] or "无"))
    # 交集：#01 与 #40 是不是同一件事
    hs = {r["seed"] for r in hard}
    ss = {r["seed"] for r in soft if 40 in r.get("soft_fails", [])}
    print("两者【同时】红的 seed: %s" % (sorted(hs & ss) or "无"))
    rates = [(kouliang_rate(r)[0], r["seed"]) for r in rows if kouliang_rate(r)[0] is not None]
    rates.sort()
    if rates:
        lo = [x for x in rates if x[0] == rates[0][0]]
        hi = [x for x in rates if x[0] == rates[-1][0]]
        print("口粮满足率 min=%.3f (seed %s) · max=%.3f (seed %s) · 中位=%.3f" % (
            rates[0][0], ",".join(str(s) for _, s in lo),
            rates[-1][0], ",".join(str(s) for _, s in hi),
            rates[len(rates) // 2][0]))
        for r in hard:
            kr, kd = kouliang_rate(r)
            rank = 1 + sum(1 for x in rates if x[0] < kr)
            print("  硬红 seed %d 的口粮满足率 = %.3f（本格排名第 %d / %d）" % (
                r["seed"], kr, rank, len(rates)))


if __name__ == "__main__":
    main()
