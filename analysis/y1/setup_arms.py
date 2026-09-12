"""Y1 — build isolated game/ copies for the obj_survival_pull dose + isolation arms.

Every arm shares ONE call-site edit (`+ _survival_pull(need_id, cur)` on the object
score) and differs only in the helper body + the utility.json key.  The `bsoc`
helper body is byte-identical to the one intended for shipping.

arms:
  base   bsoc body, key absent          -> pull is identity  => zero-perturbation control
  null   bsoc body, key absent, obj_dist_penalty 0.400->0.401 (semantically empty perturbation)
  bsoc_K need_id == "social" only
  ball_K every need (X1's original arm B)
  bnon_K every need EXCEPT social       -> negative control for the isolation claim
"""
import io, json, os, shutil, sys

SRC = "E:/Documents/Dev/June/26th/.claude/worktrees/agent-a69d11c522a1efb5b/game"
DST = os.path.dirname(os.path.abspath(__file__)) + "/arms"

CALL_OLD = '\t\t\tvar score := benefit - float(dist) * _w("obj_dist_penalty", 0.4)'
CALL_NEW = CALL_OLD + ' + _survival_pull(need_id, cur)'
ANCHOR = 'func _object_candidates('

BODIES = {
    # (guard line)  -> helper body
    "soc": '\tif k == 0.0 or need_id != "social":\n',
    "all": '\tif k == 0.0:\n',
    "non": '\tif k == 0.0 or need_id == "social":\n',
}


def helper(kind):
    return (
        '## Y1 intervention B: below SURVIVAL_GATE, push toward the OBJECT route.\n'
        '## Missing key / 0 => returns 0.0 => `score + 0.0` => byte-identical trajectory.\n'
        'func _survival_pull(need_id: String, cur: float) -> float:\n'
        '\tvar k := _w("obj_survival_pull", 0.0)\n'
        + BODIES[kind] +
        '\t\treturn 0.0\n'
        '\treturn maxf(0.0, SURVIVAL_GATE - cur) * k\n\n')


def build(name, kind, k, dist_pen=None):
    d = DST + "/" + name
    if os.path.isdir(d):
        shutil.rmtree(d)
    shutil.copytree(SRC, d, ignore=shutil.ignore_patterns(".godot", "*.import", "*.uid"))
    p = d + "/scripts/Sim.gd"
    s = io.open(p, encoding="utf-8").read()
    assert s.count(CALL_OLD) == 1, (name, "call anchor", s.count(CALL_OLD))
    s = s.replace(CALL_OLD, CALL_NEW)
    assert s.count(ANCHOR) == 1, (name, "func anchor")
    s = s.replace(ANCHOR, helper(kind) + ANCHOR, 1)
    io.open(p, "w", encoding="utf-8", newline="").write(s)

    up = d + "/data/utility.json"
    j = json.load(io.open(up, encoding="utf-8"))
    if k is None:
        j.pop("obj_survival_pull", None)
    else:
        j["obj_survival_pull"] = k
    if dist_pen is not None:
        j["obj_dist_penalty"] = dist_pen
    io.open(up, "w", encoding="utf-8", newline="").write(
        json.dumps(j, ensure_ascii=False, indent=2) + "\n")
    print("built %-10s kind=%-4s k=%-5s dist_pen=%s" % (name, kind, k, dist_pen))


if __name__ == "__main__":
    os.makedirs(DST, exist_ok=True)
    build("base", "soc", None)
    build("null", "soc", None, dist_pen=0.401)
    for k in (0.5, 1.0, 1.5, 2.0, 3.0):
        build("bsoc_%s" % str(k).replace(".", ""), "soc", k)
    build("ball_10", "all", 1.0)
    build("bnon_10", "non", 1.0)
