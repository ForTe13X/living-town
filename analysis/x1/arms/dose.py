import json, io, glob, os, sys

D = {}
for f in sorted(glob.glob("out/k*_n40_s1-12.txt")):
    arm = os.path.basename(f).split("_")[0]
    for ln in io.open(f, encoding="utf-8"):
        if ln.startswith("[X1M] "):
            r = json.loads(ln[6:])
            D.setdefault(arm, {})[r["seed"]] = r

# baseline (worktree, unmodified) — Harness [S0] rows
base = {}
bp = "E:/Documents/Dev/June/26th/.claude/worktrees/agent-a486f8a5c704ec955/analysis/x1/base_n40_s1-12.txt"
if os.path.exists(bp):
    for ln in io.open(bp, encoding="utf-8"):
        if ln.startswith("[S0] "):
            r = json.loads(ln[5:])
            base[r["seed"]] = r

arms = sorted(D)
print("剂量臂:", arms, " 基线 seed 数:", len(base))
print()
hdr = "seed | base_digest | " + " | ".join("%-34s" % a for a in arms)
print(hdr)
for s in sorted(set().union(*[set(D[a]) for a in arms])):
    row = []
    for a in arms:
        r = D[a].get(s)
        if not r:
            row.append("-".ljust(34))
        else:
            same = "=" if base.get(s, {}).get("digest") == r["digest"] else "≠"
            row.append(("%s%s lock=%-4d hard=%-4s soc=%.1f" % (
                same, r["digest"][:6], r["max_soclock_run"],
                str(r["hard_fails"]), r["floors"]["social"])).ljust(34))
    print("%4d | %-11s | " % (s, base.get(s, {}).get("digest", "?")) + " | ".join(row))

print()
for a in arms:
    rows = list(D[a].values())
    hard = [r["seed"] for r in rows if r["hard_fails"]]
    same = sum(1 for r in rows if base.get(r["seed"], {}).get("digest") == r["digest"])
    locks = sorted(r["max_soclock_run"] for r in rows)
    fl = sorted(r["floors"]["social"] for r in rows)
    acc = sum(r["social_acc"].get("gossip_rep", 0) for r in rows)
    ref = sum(r["social_ref"].get("gossip_rep", 0) for r in rows)
    print("%s: n=%2d  与基线 digest 相同 %2d/%d  硬#01红 %s  最长锁段 %d..%d(中位%d)  social地板 %.2f..%.2f(中位%.2f)  gossip_rep 接/拒 %d/%d (%.1f%%)" % (
        a, len(rows), same, len(rows), hard or "无",
        locks[0], locks[-1], locks[len(locks) // 2],
        fl[0], fl[-1], fl[len(fl) // 2], acc, ref, 100.0 * acc / max(1, acc + ref)))
