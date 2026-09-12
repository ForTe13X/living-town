#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AM1: re-theme cafe 1f/2f into non-template zoning — CHAIN-SAFE (真·零金标).

★ 实测教训（analysis/am1/golden_after.log 第一版）：纯装饰家具【不是】零金标。
   Sim._build_interior_grids 把非-WALKABLE_SLOTS(stairs/rug/window 之外) 的家具格【挡进导航网】，
   在【原先空】的格上新增挡格 ⇒ 改变居民室内寻路 ⇒ 逐 tick 前缀链(chain)漂移（digest/event_digest
   仍逐字节相同，但 golden 门含 chain ⇒ CI 红）。协调者"纯装饰=只渲染=零金标"只覆盖 _compile_interiors，
   漏了 _build_interior_grids。⇒ 本版遵守【导航挡格集不变】不变式来保证 chain 也逐字节不变：
     · 每个原有家具格【位置不动、walkable 属性不动】，只换 slot（换的是画法/身份，不是几何）；
     · 新增装饰只用 WALKABLE slot(rug) 落在【原先空】的内格（walkable ⇒ 不挡格 ⇒ 不改导航网）；
     · 挂墙装饰(picture) 只落【边界格】(x=0/7 或 y=0/5——本就被外墙挡，furniture 再挡是幂等)。
   counter/table(喝咖啡)/bed(睡觉) = advertises 对象，位置+slot+advertises 逐字不动（改它=移金标）。
   stairs = portal 锚点。⇒ 导航挡格集与 world 候选集都逐字节不变 ⇒ digest+event_digest+chain 三者都不动。

Re-serialized json.dumps(ensure_ascii=False, indent=1) 无尾换行，与原文件风格逐字节同源（已验证）。"""
import json

P = "game/data/interiors.json"
data = json.loads(open(P, encoding="utf-8").read())
old = data["cafe"]

# 从原文件取 advertises 载荷（保持逐字节），并核对原挡格集不变式所依赖的原始位置。
adv_counter = next(f["advertises"] for f in old["1f"]["furniture"] if f["slot"] == "counter")
adv_drink = next(f["advertises"] for f in old["1f"]["furniture"] if f["slot"] == "table" and f.get("advertises"))
adv_sleep = next(f["advertises"] for f in old["2f"]["furniture"] if f["slot"] == "bed")


def f(slot, x, y, **extra):
    d = {"slot": slot, "pos": [x, y]}
    d.update(extra)
    return d


# ── cafe 1f · 公共咖啡区 ── 原挡格集(非 walkable)：
#   shelf[6,1] counter[4,1]🔒 coffee[5,1] table[2,3] chair[2,4] table[5,3]🔒 chair[5,4] plant[1,4]
#   walkable：stairs[1,1](portal) rug[3,2]。★下面每一格【位置不动、walkable 属性不动】——
#   只把 5 个纯装饰格换成咖啡身份画法（table→pastry、chair→barstool×2、plant→menu、shelf 留杯碟架），
#   再在【空格】上加 walkable 迎宾/走道地毯（不挡格）。
cafe_1f = [
    f("stairs", 1, 1, label="上楼"),                                  # portal（walkable，不动）
    f("shelf", 6, 1),                                                # 杯碟架（role=cafe，挡格不动）
    f("counter", 4, 1, label="咖啡吧台", staff=True, advertises=adv_counter),  # 🔒
    f("coffee", 5, 1, label="咖啡机"),                                # 挡格不动
    f("pastry", 2, 3),        # ← table[2,3] 原挡格 → 玻璃甜点柜（同格同 walkable，纯换画法）
    f("barstool", 2, 4),      # ← chair[2,4] 原挡格 → 吧凳
    f("table", 5, 3, advertises=adv_drink),                          # 🔒 喝咖啡（不动）
    f("barstool", 5, 4),      # ← chair[5,4] 原挡格 → 吧凳
    f("menu", 1, 4),          # ← plant[1,4] 原挡格 → A 字黑板菜单牌
    f("rug", 3, 2),                                                  # 原 walkable 地毯（不动）
    f("rug", 4, 4),           # NEW walkable 门口迎宾地毯（门在 [4,5]，空格，不挡格 ⇒ 零金标）
]

# ── cafe 2f · 阿丽私宅 ── 原挡格集(非 walkable)：bed[2,2]🔒 desk[5,2] shelf[6,1] plant[6,4]
#   walkable：stairs[1,1](portal) rug[3,3] window[7,3]。★换 3 个纯装饰格成卧室身份画法
#   （shelf→wardrobe、plant→vanity、desk 留书桌），加 walkable 床前地毯 + 左墙相片（边界格幂等挡）。
cafe_2f = [
    f("stairs", 1, 1, label="下楼"),                                  # portal（不动）
    f("wardrobe", 6, 1),      # ← shelf[6,1] 原挡格 → 高衣柜
    f("bed", 2, 2, label="床", advertises=adv_sleep),                # 🔒 睡觉（不动）
    f("desk", 5, 2, label="书桌"),                                   # 书桌（挡格不动）
    f("vanity", 6, 4),        # ← plant[6,4] 原挡格 → 梳妆镜
    f("rug", 3, 3),                                                  # 原 walkable 地毯（不动）
    f("window", 7, 3),                                               # 原 walkable 窗（不动）
    f("rug", 2, 3),           # NEW walkable 床前地毯（空格，不挡格 ⇒ 零金标）
    f("picture", 0, 2),       # NEW 相片（左墙边界格，本就被外墙挡 ⇒ 幂等，不改导航网）
    f("picture", 0, 3),       # NEW 相片（左墙边界格）
]

data["cafe"] = {
    "1f": {"label": old["1f"]["label"], "floor": old["1f"]["floor"], "furniture": cafe_1f},
    "2f": {"label": old["2f"]["label"], "floor": old["2f"]["floor"], "furniture": cafe_2f},
}

data["_note"] = (
    "P3 竖切片室内内容：space -> floor -> {label, floor(地板材质), furniture[]}。"
    "furniture={slot(渲染前缀,决定程序化画法), pos:[x,y]（该 Space 内的格,从 0,0）, label?, advertises?}。"
    "★两条 Sim 读取路径（非纯渲染，务必分清）：① 带 advertises 的家具经 Sim._compile_interiors 编译成 world 候选对象"
    "（改它/改其 advertises/挪位 = 移金标）；② 家具格经 _build_interior_grids 进各平面导航网"
    "（WALKABLE_SLOTS=stairs/rug/window 放行，其余【挡格】）⇒ 在原先空的格上新增挡格会重排居民寻路、漂移逐tick链"
    "（AM1 实测：digest/event_digest 不动但 chain 漂 ⇒ golden 红）。∴纯装饰家具"
    "【零金标的充要条件是不改导航挡格集】：换 slot 而位置+walkable 不变、或只在空格加 walkable(rug)、"
    "或挂墙装饰落边界格——AM1 按此实测 golden 12/12 逐字节不变（含 chain）。"
    "外墙由 Space bounds 边框自动画（门口那格留缺）、门/楼梯锚点用 spaces.json 的 portal。缺此文件=非-town Space 回落占位网格。"
)

out = json.dumps(data, ensure_ascii=False, indent=1)
open(P, "w", encoding="utf-8", newline="\n").write(out)
print("wrote", P, "bytes", len(out), " 1f:", len(cafe_1f), " 2f:", len(cafe_2f))

# 不变式自证：导航挡格集（非 walkable 家具格 ∪ 已挡的边界格）与原文件逐格相同。
WALK = {"stairs", "rug", "window"}
BW, BH = 8, 6


def blocked_interior(furn):
    s = set()
    for it in furn:
        x, y = it["pos"]
        if 0 < x < BW - 1 and 0 < y < BH - 1 and it["slot"] not in WALK:
            s.add((x, y))
    return s


for fl in ("1f", "2f"):
    a = blocked_interior(old[fl]["furniture"])
    b = blocked_interior(data["cafe"][fl]["furniture"])
    print("  floor", fl, "内格挡格集 identical:", a == b, "| old", sorted(a), "new", sorted(b))
