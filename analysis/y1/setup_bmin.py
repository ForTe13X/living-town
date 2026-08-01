"""Y1 — variant `bmin`: the pull fires only when `social` IS the argmin need.

This is the exact mirror of X1's diagnosis: `_social_candidates` returns [] whenever
`_min_need < SURVIVAL_GATE`, and the lock happens precisely when that argmin is
`social` itself.  So open the object route in exactly that case, and in no other.
Structural consequence: the pull can never outbid a need that is MORE urgent than
social, because it is switched off whenever one exists.
"""
import io, json, os, shutil, sys

SRC = "E:/Documents/Dev/June/26th/.claude/worktrees/agent-a69d11c522a1efb5b/game"
DST = os.path.dirname(os.path.abspath(__file__)) + "/arms"

MODS_OLD = '\tvar mods_ok := _min_need(ag) >= SURVIVAL_GATE '
MODS_NEW = ('\tvar min_need := _min_need(ag)\n'
            '\tvar mods_ok := min_need >= SURVIVAL_GATE ')
CALL_OLD = '\t\t\tvar score := benefit - float(dist) * _w("obj_dist_penalty", 0.4)'
CALL_NEW = CALL_OLD + ' + _survival_pull(need_id, cur, min_need)'
ANCHOR = 'func _object_candidates('

HELPER = (
    '## Y1 intervention B-min: below SURVIVAL_GATE, push toward the OBJECT route --\n'
    '## but ONLY for `social`, and ONLY while social is the argmin need.\n'
    '## Missing key / 0 => returns 0.0 => `score + 0.0` => byte-identical trajectory.\n'
    'func _survival_pull(need_id: String, cur: float, min_need: float) -> float:\n'
    '\tvar k := _w("obj_survival_pull", 0.0)\n'
    '\tif k == 0.0 or need_id != "social" or cur > min_need:\n'
    '\t\treturn 0.0\n'
    '\treturn maxf(0.0, SURVIVAL_GATE - cur) * k\n\n')


def build(name, k):
    d = DST + "/" + name
    if os.path.isdir(d):
        shutil.rmtree(d)
    shutil.copytree(SRC, d, ignore=shutil.ignore_patterns(".godot", "*.import", "*.uid"))
    p = d + "/scripts/Sim.gd"
    s = io.open(p, encoding="utf-8").read()
    assert s.count(MODS_OLD) == 1, (name, "mods anchor", s.count(MODS_OLD))
    s = s.replace(MODS_OLD, MODS_NEW)
    assert s.count(CALL_OLD) == 1, (name, "call anchor")
    s = s.replace(CALL_OLD, CALL_NEW)
    assert s.count(ANCHOR) == 1
    s = s.replace(ANCHOR, HELPER + ANCHOR, 1)
    io.open(p, "w", encoding="utf-8", newline="").write(s)

    up = d + "/data/utility.json"
    j = json.load(io.open(up, encoding="utf-8"))
    if k is None:
        j.pop("obj_survival_pull", None)
    else:
        j["obj_survival_pull"] = k
    io.open(up, "w", encoding="utf-8", newline="").write(
        json.dumps(j, ensure_ascii=False, indent=2) + "\n")
    print("built", name, "k=", k)


if __name__ == "__main__":
    build("bmin_00", None)     # zero-perturbation control for THIS code shape
    build("bmin_10", 1.0)
    build("bmin_30", 3.0)
