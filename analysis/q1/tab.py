import re, sys, glob, os
tag = sys.argv[1] if len(sys.argv) > 1 else "pre"
d = os.path.dirname(os.path.abspath(__file__))
rows = []
for f in sorted(glob.glob(os.path.join(d, tag + "_n*_s*.txt"))):
    m = re.search(r"_n(\d+)_s(\d+)\.txt$", f)
    N, S = int(m.group(1)), int(m.group(2))
    txt = open(f, encoding="utf-8", errors="replace").read()
    if "SCRIPT ERROR" in txt:
        rows.append((N, S, "SCRIPT_ERROR", "", "", "", "", "", "", ""))
        continue
    blocks = re.split(r"\[Q1\] === ", txt)[1:]
    rec = {}
    for b in blocks:
        arm = b.split(" ")[0]
        def g(pat, default=""):
            mm = re.search(pat, b)
            return mm.group(1) if mm else default
        rec[arm] = dict(
            att=g(r"attitudes@(\S+?)\s"), fac=g(r"faction@(\S+?)\s"),
            act=g(r"行为@(\S+?)\s"), rel=g(r"关系账本@(\S+)"),
            co=g(r"同区 tick=(\d+)"), fam=g(r"familiarity总和=([\d.]+)"),
            who=g(r"faction 变的人: (\[.*?\])"),
            verdict=g(r"判决: (\S+?)\s"),
            chan=g(r"通道活性 本臂/对照: (.*)"),
            hard=g(r"硬=(\[.*?\])"),
        )
    rows.append((N, S, rec))

print("N   seed | 出货臂 ATT1                                    | 隔离臂 QATT1")
print("         | fac@   att@    act@   判决        变的人数     | co_ticks fam  fac@   att@   act@   判决")
for N, S, rec in rows:
    if rec == "SCRIPT_ERROR":
        print("%-3d %-4d | SCRIPT ERROR" % (N, S)); continue
    a = rec.get("ATT1", {}); q = rec.get("QATT1", {})
    na = len(re.findall(r'"', a.get("who", ""))) // 2
    nq = len(re.findall(r'"', q.get("who", ""))) // 2
    print("%-3d %-4d | %-6s %-7s %-6s %-11s %-2d          | %-8s %-4s %-6s %-6s %-6s %-11s %d" % (
        N, S, a.get("fac", "?"), a.get("att", "?"), a.get("act", "?"), a.get("verdict", "?"), na,
        q.get("co", "?"), q.get("fam", "?"), q.get("fac", "?"), q.get("att", "?"), q.get("act", "?"),
        q.get("verdict", "?"), nq))
print()
print("— 通道活性（本臂/对照）—")
for N, S, rec in rows:
    if rec == "SCRIPT_ERROR": continue
    print("N=%-3d s=%-3d ATT1 : %s" % (N, S, rec.get("ATT1", {}).get("chan", "?")))
    print("           QATT1: %s   硬=%s" % (rec.get("QATT1", {}).get("chan", "?"), rec.get("QATT1", {}).get("hard", "?")))
print()
print("— 派系变动的人（出货臂）—")
for N, S, rec in rows:
    if rec == "SCRIPT_ERROR": continue
    print("N=%-3d s=%-3d %s" % (N, S, rec.get("ATT1", {}).get("who", "?")))
