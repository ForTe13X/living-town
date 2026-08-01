"""Y1 — arbitrary paired arm-vs-arm sign tests + digest-equality census."""
import sys, io, os, json
from math import comb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agg import load, F_SOC, F_LOCK, F_AREA, sign_test, med


def cmp(a, b):
    da, db = load(a), load(b)
    ks = sorted(set(da) & set(db))
    same = sum(1 for k in ks if da[k]["digest"] == db[k]["digest"])
    r1 = sign_test(da, db, F_SOC)
    r2 = sign_test(da, db, F_LOCK, higher_is_better=False)
    r3 = sign_test(da, db, F_AREA, higher_is_better=False)
    print("%-9s vs %-9s n=%2d 同摘=%2d | 地板 %2d/%2d/%2d p=%.4f | 锁段 %2d/%2d/%2d p=%.4f | 面积 %2d/%2d/%2d p=%.4f"
          % (a, b, len(ks), same, r1[0], r1[1], r1[2], r1[3],
             r2[0], r2[1], r2[2], r2[3], r3[0], r3[1], r3[2], r3[3]))


if __name__ == "__main__":
    pairs = [
        ("bsoc_10", "ball_10"), ("bnon_10", "base"), ("bnon_10", "null"),
        ("bsoc_10", "bnon_10"), ("ball_10", "bnon_10"),
        ("bmin_10", "bsoc_10"), ("bmin_30", "bsoc_30"),
        ("bmin_05", "bsoc_05"), ("bmin_20", "bsoc_20"),
        ("bmin_10", "null"), ("bmin_20", "null"), ("bmin_30", "null"),
        ("bmin_10", "base"), ("bmin_20", "base"), ("bmin_30", "base"),
        ("bmin_20", "bmin_10"), ("bmin_30", "bmin_20"),
    ]
    if len(sys.argv) > 2:
        pairs = [(sys.argv[1], sys.argv[2])]
    for a, b in pairs:
        try:
            cmp(a, b)
        except Exception as e:
            print("%-9s vs %-9s  --  %s" % (a, b, e))
