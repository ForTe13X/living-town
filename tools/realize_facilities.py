#!/usr/bin/env python
# realize_facilities.py — docs/193 §六: the PixelLab "prop buildings" become real places.
#
# tools/place_houses.py --solid leaves a door cell in the first bakery / crêperie / chapel / covered market /
# grand hotel it places (lots.json "door"). This script gives each of those an interior Space, a street-door
# portal from that town cell, and a furnished floor whose pieces advertise real actions:
#   面包房/可丽饼店：小圆桌「吃点心」   礼拜堂：长椅「静坐」、祭台「祈祷」   市场：摊位「逛集」
#   大酒店：钢琴「弹琴」、沙发「歇着」   以及各处墙上的画「赏画」。
# Idempotent: previously generated facility spaces/portals (marked "_facility") are replaced.
# Usage: python tools/realize_facilities.py [--check]
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from furnish_interiors import f, ad, validate, ART, REST  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "game", "data")
LOTS = os.path.join(ROOT, "game", "assets", "art", "houses", "lots.json")

# 「吃点心」而不是「吃饭」：production.consume 里没有它 ⇒ 不从镇库口粮出账。第一版用「吃饭」，
# N=16 的 #40 口粮满足率掉到 0.31（想要 1435）——多两处吃饭的地方，口粮需求被放大，而产能一格没加。
EAT = ad("吃点心", "hunger", 30, 12)
PEW = ad("静坐", "fun", 22, 14)
PRAY = ad("祈祷", "fun", 20, 12)
STALL = ad("逛集", "fun", 20, 12)
PIANO = ad("弹琴", "fun", 32, 18)

# sid -> (label, floor, (w, h), furniture)   door is always the bottom-centre cell (w//2, h-1)
FACILITIES = {
    "bakery": ("面包房", "wood", (8, 6), [
        f("window", 1, 0), f("painting_parasol", 5, 0, label="风景画", adv=ART),
        f("counter", 2, 1, (2, 1)), f("plant", 6, 1),
        f("bistro", 2, 3, label="小圆桌", adv=EAT), f("bistro", 5, 3, label="小圆桌", adv=EAT),
        f("menu", 1, 4),
    ]),
    "creperie": ("可丽饼店", "wood", (8, 6), [
        f("painting_sea", 2, 0, label="海景画", adv=ART), f("window", 6, 0),
        f("plant", 1, 1), f("sink", 5, 1), f("stove", 6, 1),
        f("bistro", 2, 3, label="小圆桌", adv=EAT), f("bistro", 5, 3, label="小圆桌", adv=EAT),
        f("menu", 1, 4),
    ]),
    "chapel": ("礼拜堂", "stone", (7, 8), [
        f("stained_glass", 1, 0), f("stained_glass", 5, 0),
        f("plant", 1, 1), f("altar", 2, 1, (2, 1), "祭台", PRAY), f("plant", 5, 1),
        f("pew", 1, 3, (2, 1), "长椅", PEW), f("pew", 4, 3, (2, 1), "长椅", PEW),
        f("pew", 1, 5, (2, 1)), f("pew", 4, 5, (2, 1)),
    ]),
    "halles": ("室内市场", "stone", (10, 7), [
        f("window", 2, 0), f("window", 7, 0),
        f("grocery", 4, 1), f("grocery", 5, 1),
        f("market_stall", 1, 2, (2, 1), "摊位", STALL), f("market_stall", 7, 2, (2, 1), "摊位", STALL),
        f("market_stall", 1, 4, (2, 1)), f("market_stall", 7, 4, (2, 1)),
        f("sacks", 1, 5), f("crate", 8, 5),
    ]),
    "hotel": ("海滨大酒店", "wood", (10, 7), [
        f("window", 1, 0), f("painting_sea", 3, 0, label="海景画", adv=ART), f("window", 8, 0),
        f("plant", 4, 1), f("bookshelf", 5, 1), f("piano", 7, 1, (2, 1), "钢琴", PIANO),
        f("rug", 3, 3, (2, 1)),
        f("sofa", 1, 4, (2, 1), "沙发", REST), f("armchair", 4, 4), f("sofa", 6, 4, (2, 1), "沙发", REST),
        f("lamp", 8, 4), f("plant", 1, 5), f("plant", 8, 5),
    ]),
}


def main():
    check = "--check" in sys.argv
    lots = json.load(open(LOTS, encoding="utf-8"))["lots"]
    doors = {L["sprite"]: L["door"] for L in lots if "door" in L}
    ip, sp = os.path.join(D, "interiors.json"), os.path.join(D, "spaces.json")
    interiors = json.load(open(ip, encoding="utf-8"))
    spaces = json.load(open(sp, encoding="utf-8"))
    for sid in [k for k, v in spaces["spaces"].items() if isinstance(v, dict) and v.get("_facility")]:
        del spaces["spaces"][sid]
        interiors.pop(sid, None)
    spaces["portals"] = [p for p in spaces["portals"] if not p.get("_facility")]
    for sid, (label, floor, (w, h), furn) in FACILITIES.items():
        if sid not in doors:
            print(f"{sid:8s} not placed with a door — skipped")
            continue
        door_in = (w // 2, h - 1)
        n = validate(sid, (w, h), door_in, furn)
        spaces["spaces"][sid] = {"_facility": True, "public_venue": True, "kind": "interior", "label": label, "bounds": [0, 0, w, h],
                                 "floors": ["1f"], "default_floor": "1f"}
        spaces["portals"].append({"_facility": True, "id": f"p_{sid}_door", "kind": "door",
                                  "from": {"space": "town", "floor": "outdoor", "pos": doors[sid]},
                                  "to": {"space": sid, "floor": "1f", "pos": list(door_in)},
                                  "bidirectional": True, "access": "public", "traversal_cost": 1})
        interiors[sid] = {"1f": {"label": "一层", "floor": floor, "furniture": furn}}
        print(f"{sid:8s} {label} {w}x{h} street door {doors[sid]} pieces={len(furn)} walkable={n}")
    if check:
        return 0
    for path, d in ((ip, interiors), (sp, spaces)):
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(d, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
