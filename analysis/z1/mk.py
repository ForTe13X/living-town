# -*- coding: utf-8 -*-
"""Z1 负对照：在隔离副本里造变异体。只在 .z1iso/ 下写，绝不碰工作树的 game/。"""
import io, json, os, shutil, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ISO = os.path.join(ROOT, ".z1iso")

# 变异体：都建在【装了 Z1 这道门的树】上（= 工作树当前状态），
# 因为要证明的是"这道门抓得住"，不是"改前抓不住"。
MUTANTS = {
    # Y1 的四个变异体里【必须由本门抓住】的两个：
    "M1_relax_all":  "去掉 `need_id != \"social\"` 这道门（= X1 臂 B 原样，对五条 need 全生效）",
    "M2_dose2":      "剂量翻倍 k=1.0 → 2.0",
    # 额外两个（第三道收窄 + ablation 路，后者【必须仍然绿】）：
    "M3_no_argmin":  "去掉 `cur > min_need` 这道 argmin 门",
    "M4_ablate":     "整项 ablate：utility.obj_survival_pull 删键（缺键即零扰动）",
    # 变体：只放宽给【一条】别的 need —— 探 A 臂是不是只认"全放宽"
    "M5_relax_one":  "只额外放宽给 hunger（need_id 不是 social 也不是 hunger 才拦）",
    # 门自己的余量点：k 恰好卡在门下方一档
    "M6_dose_18":    "k=1.8（比值 0.972 < 1.0 ⇒ 本门【抓不到】，用来把门咬的位置量出来）",
    "M7_dose_186":   "k=1.86（比值 1.004 ≥ 1.0 ⇒ 本门抓得到）",
    # 本门自己的两个已知洞，从"推的"变成"跑的"：
    "M8_short0":     "把 _survival_pull 短路成恒返回 0.0（k 仍是 1.0）—— 三臂平凡成立，本门抓不到",
    "M9_weak_ad":    "给长椅加一条 amount=5 的 social 广告 —— 最弱基准收益掉到 8.33，本门会红（正当改动的假红风险）",
}

PULL_ORIG = '''func _survival_pull(need_id: String, cur: float, min_need: float) -> float:
	var k := _w("obj_survival_pull", 0.0)
	if k == 0.0 or need_id != "social" or cur > min_need:
		return 0.0
	return maxf(0.0, SURVIVAL_GATE - cur) * k'''

PATCH_SIM = {
    "M1_relax_all": PULL_ORIG.replace('or need_id != "social" ', ''),
    "M3_no_argmin": PULL_ORIG.replace(' or cur > min_need', ''),
    "M5_relax_one": PULL_ORIG.replace('need_id != "social"',
                                      '(need_id != "social" and need_id != "hunger")'),
    "M8_short0": PULL_ORIG.replace('	return maxf(0.0, SURVIVAL_GATE - cur) * k',
                                   '	return 0.0 * maxf(0.0, SURVIVAL_GATE - cur) * k'),
}
PATCH_K = {"M2_dose2": 2.0, "M6_dose_18": 1.8, "M7_dose_186": 1.86}


def build(name):
    dst = os.path.join(ISO, name)
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    shutil.copytree(os.path.join(ROOT, "game"), os.path.join(dst, "game"))
    simp = os.path.join(dst, "game", "scripts", "Sim.gd")
    utp = os.path.join(dst, "game", "data", "utility.json")
    if name in PATCH_SIM:
        s = io.open(simp, encoding="utf-8").read()
        assert s.count(PULL_ORIG) == 1, "锚点没命中 —— Sim._survival_pull 变了，先看代码"
        s = s.replace(PULL_ORIG, PATCH_SIM[name])
        io.open(simp, "w", encoding="utf-8", newline="\n").write(s)
    if name in PATCH_K:
        d = json.load(io.open(utp, encoding="utf-8"))
        assert d["obj_survival_pull"] == 1.0
        d["obj_survival_pull"] = PATCH_K[name]
        io.open(utp, "w", encoding="utf-8", newline="\n").write(
            json.dumps(d, ensure_ascii=False, indent=2) + "\n")
    if name == "M9_weak_ad":
        mp = os.path.join(dst, "game", "data", "map.json")
        d = json.load(io.open(mp, encoding="utf-8"))
        hit = 0
        for o in d["objects"]:
            if o.get("id") == "bench_1":
                o["advertises"].append({"action": "闲坐", "need": "social",
                                        "amount": 5, "duration": 8})
                hit += 1
        assert hit == 1, "map.json 里没找到 bench_1"
        io.open(mp, "w", encoding="utf-8", newline="\n").write(
            json.dumps(d, ensure_ascii=False, indent=1) + "\n")
    if name == "M4_ablate":
        d = json.load(io.open(utp, encoding="utf-8"))
        del d["obj_survival_pull"]
        io.open(utp, "w", encoding="utf-8", newline="\n").write(
            json.dumps(d, ensure_ascii=False, indent=2) + "\n")
    print("built %-14s  %s" % (name, MUTANTS[name]))


if __name__ == "__main__":
    for n in (sys.argv[1:] or list(MUTANTS)):
        build(n)
