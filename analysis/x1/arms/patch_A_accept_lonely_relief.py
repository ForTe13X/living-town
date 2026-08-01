import sys, io, json

def patch_sim(d):
    p = d + "/scripts/Sim.gd"
    s = io.open(p, encoding="utf-8").read()
    old = '\t\t\t\tsum = aff + reserved + st + fac + jitter + extra; thr = _w("accept_gossip", 0.0)'
    new = '\t\t\t\tsum = aff + reserved + st + fac + jitter + extra + _lonely_relief(need); thr = _w("accept_gossip", 0.0)'
    assert s.count(old) == 1, (d, "anchor count", s.count(old))
    s = s.replace(old, new)
    anchor = 'func _acceptance_margin('
    assert s.count(anchor) == 1, (d, "func count", s.count(anchor))
    helper = (
        '## X1: already below the social survival line -> extra willingness to accept being talked to.\n'
        '## Missing key / 0 => returns 0.0 => `sum + 0.0` (IEEE identity) => byte-identical to before.\n'
        'func _lonely_relief(need: float) -> float:\n'
        '\tvar k := _w("accept_lonely_relief", 0.0)\n'
        '\tif k == 0.0:\n'
        '\t\treturn 0.0\n'
        '\treturn maxf(0.0, SURVIVAL_GATE - need) * k\n\n')
    s = s.replace(anchor, helper + anchor, 1)
    io.open(p, "w", encoding="utf-8", newline="").write(s)

def set_key(d, k):
    p = d + "/data/utility.json"
    j = json.load(io.open(p, encoding="utf-8"))
    if k is None:
        j.pop("accept_lonely_relief", None)
    else:
        j["accept_lonely_relief"] = k
    io.open(p, "w", encoding="utf-8", newline="").write(
        json.dumps(j, ensure_ascii=False, indent=2) + "\n")

if __name__ == "__main__":
    for d, k in [("g_k00", None), ("g_k02", 0.2), ("g_k05", 0.5), ("g_k10", 1.0)]:
        patch_sim(d)
        set_key(d, k)
        print("patched", d, "k=", k)
