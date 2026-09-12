# -*- coding: utf-8 -*-
"""AA3 · 改后（出货配置 standing=0.0）与改前的逐 seed 对照。"""
import io, json, os

HERE = os.path.dirname(os.path.abspath(__file__))


def L(name):
    return [json.loads(l) for l in io.open(os.path.join(HERE, name), encoding="utf-8") if l.strip()]


def main():
    b = L("g1_n12_s1_12_d60.jsonl")
    a = L("after_g1_n12_s1_12_d60.jsonl")
    v = L("v1census_before.jsonl")
    o = io.open(os.path.join(HERE, "after_summary.txt"), "w", encoding="utf-8")
    o.write("v1census_before seed1 digest = %s   (docs/101 记的 Z2 出货基线是 3480519386)\n\n" % v[0]["digest"])
    o.write("seed | 成交 改前/改后 | D1 | D5 | pay带目击 | TR:商贩 信念(改后) | mei standing非零\n")
    for x, y in zip(b, a):
        tr = {k: n for k, n in y["vendor_CR_via"].items() if k.startswith("TR")}
        o.write("%4d | %3d/%3d | %3d/%3d | %3d/%3d | %d/%d | %s | %d/%d\n" % (
            x["seed"], x["deals"], y["deals"], x["D1_buyer"], y["D1_buyer"],
            x["D5_paid_bystander"], y["D5_paid_bystander"],
            x["pay_events_witnessed"], y["pay_events_witnessed"],
            json.dumps(tr, ensure_ascii=False),
            x["vendor_standing_nonzero"], y["vendor_standing_nonzero"]))
    o.write("\n改后合计: 成交=%d D1=%d D5=%d pay带目击=%d\n" % (
        sum(y["deals"] for y in a), sum(y["D1_buyer"] for y in a),
        sum(y["D5_paid_bystander"] for y in a), sum(y["pay_events_witnessed"] for y in a)))
    o.write("改前合计: 成交=%d D1=%d D5=%d pay带目击=%d\n" % (
        sum(y["deals"] for y in b), sum(y["D1_buyer"] for y in b),
        sum(y["D5_paid_bystander"] for y in b), sum(y["pay_events_witnessed"] for y in b)))
    o.write("改后 digest: %s\n" % " ".join(y["digest"] for y in a))
    o.write("改前 digest: %s\n" % " ".join(y["digest"] for y in b))
    same = [x["seed"] for x, y in zip(b, a) if x["events_total"] == y["events_total"]]
    o.write("events_total 与改前相同的 seed: %s\n" % same)
    o.close()


if __name__ == "__main__":
    main()
