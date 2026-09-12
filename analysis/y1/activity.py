"""Y1 — activity-cost table: the same thing M2 used to pick 36 over 40.
Parses Harness's own activity block ("  <flag> <type>  次数=N  覆盖 seed=a/b")."""
import io, re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
RE = re.compile(r"^\s*(?:🔒|✅|⚠|Q)*\s*([A-Za-z_]+)\s+次数=(\d+)\s+覆盖 seed=(\d+)/(\d+)")


def parse(p):
    out = {}
    for l in io.open(p, encoding="utf-8"):
        m = RE.match(l.replace("🔒Q", "").replace("🔒", ""))
        if m:
            out[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
    return out


def main():
    base_p = sys.argv[1]
    arms = sys.argv[2:]
    b = parse(HERE + "/out/" + base_p)
    tabs = {a: parse(HERE + "/out/" + a) for a in arms}
    keys = sorted(b)
    hdr = "%-20s %9s" % ("事件类", "改前")
    for a in arms:
        hdr += "%18s" % a.replace("reg_bmin_", "k=").replace("_n12.txt", "").replace("_n16.txt", "")
    print(hdr)
    for k in keys:
        line = "%-20s %9d" % (k, b[k][0])
        for a in arms:
            v = tabs[a].get(k)
            if not v:
                line += "%18s" % "—"
            else:
                d = (v[0] - b[k][0]) / float(b[k][0]) * 100.0 if b[k][0] else 0.0
                line += "%18s" % ("%d (%+.1f%%)" % (v[0], d))
        print(line)
    print()
    for a in arms:
        big = [(k, b[k][0], tabs[a][k][0]) for k in keys
               if k in tabs[a] and b[k][0] >= 20
               and abs(tabs[a][k][0] - b[k][0]) / float(b[k][0]) > 0.05]
        print("%-24s 变动 >5%% 且基数>=20 的事件类：%d 种  %s" % (
            a, len(big), ", ".join("%s %d→%d" % t for t in big) or "无"))
        miss = [k for k in keys if k in tabs[a] and tabs[a][k][2] < b[k][2]]
        print("%-24s seed 覆盖下降的事件类：%s" % (a, ", ".join(miss) or "无"))


if __name__ == "__main__":
    main()
