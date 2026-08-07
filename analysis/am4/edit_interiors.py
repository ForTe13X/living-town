#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AM4: give home / home2 / library / wash 非模板身份分区 — CHAIN-SAFE (真·零金标).

★ 继承 AM1/AM2 (analysis/am{1,2}/edit_interiors.py) 实测教训：纯装饰家具【不是】自动零金标。
   Sim._build_interior_grids(:3995) 把非-WALKABLE_SLOTS(stairs/rug/window 之外) 的家具格【挡进导航网】。
   零金标的充要条件 = 【导航挡格集逐字节不变】。据此三条纪律（照 AM1/AM2）：
     · 每个原有家具格【位置不动、walkable 属性不变】，只换 slot（换画法/身份，不是几何）；
     · 新增装饰只用 WALKABLE slot(rug) 落在【原先空】的内格（walkable ⇒ 不挡格）；
     · 本片四栋不加挂墙件（picture/window）——home/home2/library/wash 全在 INT_SPACES 里，
       都被 INTSHELL 采样左右墙列(col0/col w-1)，挂墙件会移墙众数 ⇒ 改走【纯内格 re-slot + walkable rug】。

★ advertises 家具 = Sim 对象（Sim._compile_interiors :674 用 space+floor+slot 造 id、按 authored 顺序去重）：
   home 有 bed[1,1]+bed[6,1]+table[1,3] 三件、home2 有 bed[1,1]+table[1,3] 两件、library/wash 零件。
   ⇒ 这五件【位置+slot+label+advertises+authored 相对顺序】逐字节从原 dict 复制、一格没动
     （两张床的 _1 去重后缀依赖数组顺序 ⇒ 必须保序）。library/wash 无 advertises ⇒ 路①零候选对象。

★ role 分类器耦合（WorldView._furniture_role，纯 View、不动 digest，但 FURNROLE/INTSHELL 门吃它）：
   · wash → "bath" 由【有 bath slot】触发 ⇒ 保 bath[1,1]（另把 plant[1,3] 也换成第二个 bath 池）。
   · library → "study" 需 shelf≥2 AND desk AND 无 bed ⇒ 保 3 个 shelf（书架墙）+ desk（阅读桌）、绝不引入 bed。
   · home/home2 → "living"（兜底）⇒ 不引入 counter/coffee/bath/crate（否则会掉进 cafe/store/bath 档）。
   · FURNROLE 只采 shelf 格：home2 与 library 都保 shelf(书架/books) 撑「书架」类的 B 臂（同类必须相同）；
     home 的 shelf→dresser ⇒ home 不再进 FURNROLE（它 EXPECT 书架，但门对无 shelf 的栋 continue，合法）。

写回：json.dumps(indent=1, ensure_ascii=False) 后把 \\n→\\r\\n（原文件 CRLF，AM2 已验证 CRLF-redump
逐字节等于原文件）⇒ 除 home/home2/library/wash 四栋外，其余 4 栋(cafe/shop/work)+_note 全部逐字节不变。"""
import json

P = "game/data/interiors.json"
raw = open(P, "rb").read()
data = json.loads(raw.decode("utf-8"))

orig = {sid: data[sid]["1f"]["furniture"] for sid in ("home", "home2", "library", "wash")}


def f(slot, x, y, **extra):
    d = {"slot": slot, "pos": [x, y]}
    d.update(extra)
    return d


def pick(furn, slot, pos):
    """从原数组按 slot+pos 取【原 dict 引用】——保 label/advertises 载荷与键序逐字节。"""
    for it in furn:
        if it.get("slot") == slot and it.get("pos") == pos:
            return it
    raise KeyError("%s@%s not found" % (slot, pos))


# ── home · 民居（温馨/两床的家）(bounds 9x7, 内格 x∈1..7 y∈1..5) ──
#   原挡格集(非 walkable 内格)：bed[1,1]🔒 bed[6,1]🔒 shelf[4,1] table[1,3]🔒 chair[2,3] plant[5,3]
#   walkable：rug[3,3]。★两床+桌 advertises=Sim 对象逐字复制、保序；shelf→dresser、plant→stove（原地换 slot）；
#   加 walkable rug[5,4](炉前地毯) + rug[2,2](床前小毯)。身份：两床 + 五斗柜(带相框) + 柴炉 = 有生活感的暖家。
home_new = [
    pick(orig["home"], "bed", [1, 1]),   # 🔒 睡觉（advertises，authored 第 1 件 → home1f_bed）
    pick(orig["home"], "bed", [6, 1]),   # 🔒 睡觉（authored 第 2 件 → home1f_bed_1；顺序不能换）
    f("dresser", 4, 1),                  # ← shelf[4,1] 原挡格 → 五斗柜（同格同 walkable，纯换画法）
    pick(orig["home"], "table", [1, 3]), # 🔒 歇着（advertises）
    f("chair", 2, 3),                    # 原椅（不动）
    f("rug", 3, 3),                      # 原 walkable 地毯（不动）
    f("stove", 5, 3),                    # ← plant[5,3] 原挡格 → 柴炉
    f("rug", 5, 4),                      # NEW walkable 炉前地毯（空格，不挡格 ⇒ 零金标）
    f("rug", 2, 2),                      # NEW walkable 床前小毯
]

# ── home2 · 民居（简朴/单人书斋）(bounds 6x5, 内格 x∈1..4 y∈1..3) ──
#   原挡格集：bed[1,1]🔒 shelf[4,1] table[1,3]🔒 chair[2,3]；walkable：rug[3,3]。
#   ★保 bed+table(advertises)；保 shelf(书架/FURNROLE B 臂)；chair→stool（简朴的独凳，与 home 的椅分开）；
#   加 walkable rug[2,2]。身份：一床 + 一整墙书 + 书桌独凳 = 素净的读书人单间（与 home 的暖家明显不同）。
home2_new = [
    pick(orig["home2"], "bed", [1, 1]),   # 🔒 睡觉（advertises）
    f("shelf", 4, 1),                     # 书架（role=living→books，FURNROLE「书架」类 B 臂，保 slot 名）
    pick(orig["home2"], "table", [1, 3]), # 🔒 歇着（advertises）
    f("stool", 2, 3),                     # ← chair[2,3] 原挡格 → 独凳（简朴）
    f("rug", 3, 3),                       # 原 walkable 地毯（不动）
    f("rug", 2, 2),                       # NEW walkable 素色小毯
]

# ── wash · 澡堂（沐浴）(bounds 9x7, 内格 x∈1..7 y∈1..5) ──
#   原挡格集：bath[1,1] bench[3,1] shelf[5,1] plant[1,3] bench[5,3]；walkable：rug[3,3]。
#   ★保 bath(池+role=bath 触发器)、保 shelf(毛巾架/FURNROLE)；bench[3,1]→basin(洗漱台)、plant[1,3]→bath(第二池)；
#   bench[5,3] 留更衣凳；加 walkable rug[3,2]/rug[1,2](浴垫)。身份：双池 + 洗漱台 + 毛巾架 + 更衣凳 = 沐浴堂。
wash_new = [
    f("bath", 1, 1),      # 浴池（role=bath 触发器 + 强身份，不动）
    f("basin", 3, 1),     # ← bench[3,1] 原挡格 → 洗漱台（洗漱位）
    f("shelf", 5, 1),     # 毛巾架（role=bath→_shelf_towel，FURNROLE 采样，保 slot 名）
    f("bath", 1, 3),      # ← plant[1,3] 原挡格 → 第二个浴池（去掉重复盆栽）
    f("rug", 3, 3),       # 原 walkable 地毯（不动）
    f("bench", 5, 3),     # 更衣凳（不动）
    f("rug", 3, 2),       # NEW walkable 浴垫（池/台之间）
    f("rug", 1, 2),       # NEW walkable 浴垫（两池之间）
]

# ── library · 图书馆（书香）(bounds 7x6, 内格 x∈1..5 y∈1..4) ──
#   原挡格集：shelf[1,1] shelf[2,1] shelf[5,1] desk[3,3] stool[4,3] plant[1,3]；walkable：无。
#   ★保 3 个 shelf(书架墙/role=study→books/FURNROLE C 臂逐像素一致) + desk(role=study→阅读桌) + stool(阅读凳)、无 bed；
#   plant[1,3]→lamp(落地阅读灯/台灯)；加 walkable rug[3,2](阅读区地毯)。身份：整墙书架 + 阅读桌灯 = 书香。
library_new = [
    f("shelf", 1, 1),     # 书架墙（role=study→books）
    f("shelf", 2, 1),     # 书架墙（与 [1,1] 逐像素同 = FURNROLE C 臂）
    f("shelf", 5, 1),     # 书架墙
    f("desk", 3, 3),      # 阅读桌（原挡格；role=study 触发 AM4 的阅读桌画法，cafe 2F 私宅书桌走 else 逐字节不变）
    f("stool", 4, 3),     # 阅读凳（原挡格，不动）
    f("lamp", 1, 3),      # ← plant[1,3] 原挡格 → 落地阅读灯（去掉重复盆栽）
    f("rug", 3, 2),       # NEW walkable 阅读区地毯（桌前，空格，不挡格 ⇒ 零金标）
]

data["home"]["1f"]["furniture"] = home_new
data["home2"]["1f"]["furniture"] = home2_new
data["wash"]["1f"]["furniture"] = wash_new
data["library"]["1f"]["furniture"] = library_new

# 写回：CRLF（原文件 CRLF；redump-then-CRLF 逐字节等于原文件，AM2 已在 host 验证）——其余 4 栋+_note 逐字节不变。
out = json.dumps(data, ensure_ascii=False, indent=1).replace("\n", "\r\n").encode("utf-8")
open(P, "wb").write(out)
print("wrote", P, "bytes", len(out),
      " home:", len(home_new), " home2:", len(home2_new), " wash:", len(wash_new), " library:", len(library_new))

# ── 不变式自证 1：导航挡格集（内格非-walkable 家具格）逐格不变，按【每栋各自 bounds】算 ──
WALK = {"stairs", "rug", "window"}


def blocked_interior(furn, w, h):
    s = set()
    for it in furn:
        x, y = it["pos"]
        if 0 < x < w - 1 and 0 < y < h - 1 and it["slot"] not in WALK:
            s.add((x, y))
    return s


spaces = json.load(open("game/data/spaces.json", encoding="utf-8"))["spaces"]
allok = True
for sid in ("home", "home2", "library", "wash"):
    b = spaces[sid]["bounds"]
    w, h = int(b[2]), int(b[3])
    a = blocked_interior(orig[sid], w, h)
    n = blocked_interior(data[sid]["1f"]["furniture"], w, h)
    ok = (a == n)
    allok = allok and ok
    print("  %-8s bounds %dx%d  内格挡格集 identical: %s | old %s new %s"
          % (sid, w, h, ok, sorted(a), sorted(n)))
print("ALL 挡格集 byte-identical:", allok)

# ── 不变式自证 2：advertises 家具（=world 候选对象）逐字节不变（位置/slot/label/advertises/authored 顺序）──
def adv_sig(furn):
    return [(it.get("slot"), tuple(it.get("pos")), it.get("label"),
             json.dumps(it.get("advertises"), ensure_ascii=False, sort_keys=True))
            for it in furn if it.get("advertises")]


advok = True
for sid in ("home", "home2", "library", "wash"):
    a = adv_sig(orig[sid]); n = adv_sig(data[sid]["1f"]["furniture"])
    ok = (a == n)
    advok = advok and ok
    print("  %-8s advertises 对象序列 identical: %s (%d 件)" % (sid, ok, len(a)))
print("ALL advertises byte-identical:", advok)
