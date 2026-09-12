import json, io, os, sys


def load(arm, block):
    p = "out/%s_n40_%s.txt" % (arm, block)
    if not os.path.exists(p):
        return {}
    out = {}
    for l in io.open(p, encoding="utf-8"):
        if l.startswith("[X1M] "):
            r = json.loads(l[6:])
            out[r["seed"]] = r
    return out


def med(v):
    v = sorted(v)
    return v[len(v) // 2] if v else float("nan")


arms = sys.argv[1:] or ["k00", "k02", "k05", "k10", "null", "o05", "o10"]
blocks = ["s1-12", "s49-60"]
base = {}
for b in blocks:
    base.update({(b, s): r for s, r in load("k00", b).items()})

print("臂    | 局数 | 与k00 digest 同 | 硬#01红 | 最长锁段 min..max(中位) | social地板 min..max(中位) | 变好/变坏/不变")
for a in arms:
    rows = []
    same = 0
    better = worse = nochange = 0
    for b in blocks:
        d = load(a, b)
        for s, r in d.items():
            bb = base.get((b, s))
            if bb is None:
                continue
            rows.append(r)
            if bb["digest"] == r["digest"]:
                same += 1
                nochange += 1
            else:
                # 变好 = 地板抬高（同分看锁段变短）
                if r["floors"]["social"] > bb["floors"]["social"]:
                    better += 1
                elif r["floors"]["social"] < bb["floors"]["social"]:
                    worse += 1
                else:
                    nochange += 1
    if not rows:
        continue
    locks = sorted(r["max_soclock_run"] for r in rows)
    fl = sorted(r["floors"]["social"] for r in rows)
    hard = [r["seed"] for r in rows if r["hard_fails"]]
    print("%-5s | %4d | %14d | %-7s | %3d..%3d (%3d)          | %5.2f..%5.2f (%5.2f)      | %d/%d/%d" % (
        a, len(rows), same, str(hard) if hard else "无",
        locks[0], locks[-1], med(locks), fl[0], fl[-1], med(fl),
        better, worse, nochange))
