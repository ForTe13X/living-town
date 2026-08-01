import sys, io, json

# 干预 B：**推向物件那条出路**，而不是求别人接受。
# §1.3 量到：被锁住的人在 100%(s8) / 72%(s56) 的 tick 上枚举得到 need=social 的物件候选
# （长椅「社交」+40、吧台「闲聊」+42），却只在 11% / 12% 的 tick 上真的在做它。
# SURVIVAL_GATE 的设计意图原文是「先去吃/睡」——它**禁止**了社交那条路，
# 却从来没有**推向**物件那条路。这一项就是那个缺掉的推力，且只在生存线以下生效。
def patch_sim(d):
    p = d + "/scripts/Sim.gd"
    s = io.open(p, encoding="utf-8").read()
    old = '\t\t\tvar score := benefit - float(dist) * _w("obj_dist_penalty", 0.4)'
    new = ('\t\t\tvar score := benefit - float(dist) * _w("obj_dist_penalty", 0.4)'
           ' + _survival_pull(cur)')
    assert s.count(old) == 1, (d, "anchor", s.count(old))
    s = s.replace(old, new)
    anchor = 'func _object_candidates('
    assert s.count(anchor) == 1
    helper = (
        '## X1 intervention B: push toward the object route for a need already below\n'
        '## SURVIVAL_GATE. Missing key / 0 => returns 0.0 => `score + 0.0` => byte-identical.\n'
        'func _survival_pull(cur: float) -> float:\n'
        '\tvar k := _w("obj_survival_pull", 0.0)\n'
        '\tif k == 0.0:\n'
        '\t\treturn 0.0\n'
        '\treturn maxf(0.0, SURVIVAL_GATE - cur) * k\n\n')
    s = s.replace(anchor, helper + anchor, 1)
    io.open(p, "w", encoding="utf-8", newline="").write(s)


def set_key(d, k):
    p = d + "/data/utility.json"
    j = json.load(io.open(p, encoding="utf-8"))
    if k is None:
        j.pop("obj_survival_pull", None)
    else:
        j["obj_survival_pull"] = k
    io.open(p, "w", encoding="utf-8", newline="").write(
        json.dumps(j, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    for d, k in [("g_o00", None), ("g_o05", 0.5), ("g_o10", 1.0)]:
        patch_sim(d)
        set_key(d, k)
        print("patched", d, "obj_survival_pull=", k)
