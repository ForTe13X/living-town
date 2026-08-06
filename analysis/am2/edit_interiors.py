#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AM2: give shop(杂货铺) + work(工坊) 非模板身份分区 — CHAIN-SAFE (真·零金标).

★ 继承 AM1 (analysis/am1/edit_interiors.py) 实测教训：纯装饰家具【不是】自动零金标。
   Sim._build_interior_grids(:3995) 把非-WALKABLE_SLOTS(stairs/rug/window 之外) 的家具格【挡进导航网】。
   零金标的充要条件 = 【导航挡格集逐字节不变】。据此三条纪律（照 AM1）：
     · 每个原有家具格【位置不动、walkable 属性不变】，只换 slot（换画法/身份，不是几何）；
     · 新增装饰只用 WALKABLE slot(rug) 落在【原先空】的内格（walkable ⇒ 不挡格）；
     · 挂墙装饰只落边界格（本就被外墙挡，幂等）——本片 shop/work 不加挂墙件。

★ AM2 实读订正协调者/AM1 的两条断言（先量后动）：
   ① 「shop/work 带 advertises 的货架/工位一个字节别动」——实读 interiors.json：shop 与 work
      **一件 advertises 都没有**（全部 advertises 只在 cafe/home/home2）。∴ 这两栋对 _compile_interiors
      路①【零候选对象】；唯一绑定约束是路②的挡格集。
   ② bounds 不是 cafe 的 8x6：shop=[0,0,7,6](w7 h6)、work=[0,0,9,7](w9 h7)。∴ 本自证按【每栋各自 bounds】
      算内格，AM1 硬编码的 8x6 不能照抄。portal 端点 shop[3,5]/work[4,0] 均落边界、非内格，不影响挡格集。

★ role 分类器耦合（WorldView._furniture_role，纯 View、不动 digest，但 FURNROLE 门吃它）：
   · shop → "store" 需 slots.has("counter") AND slots.has("crate") ⇒ 本片【保留】counter[1,1] 与 crate[2,3]
     两个 slot 名不改（只把它们的【画法】按 role 派发成杂货铺款），否则 shop 掉回 "living"、货架变书架、FURNROLE 红。
   · work → "workshop" 由 areas.type 决定（与 slot 无关）⇒ work 的 desk/crate/stool 可自由改名。
   · shop/work 各【保留】shelf slot（FURNROLE 只采 shelf 格：shop 货架 store / work 工具架 workshop）。

写回：json.dumps(indent=1, ensure_ascii=False) 后把 \\n→\\r\\n（原文件是 CRLF，已验证 CRLF-redump
逐字节等于原文件）⇒ 除 shop/work 两栋外，其余 6 栋 + _note 全部逐字节不变（cafe/home 一个字节没碰）。"""
import json

P = "game/data/interiors.json"
raw = open(P, "rb").read()
data = json.loads(raw.decode("utf-8"))
old_shop = data["shop"]["1f"]["furniture"]
old_work = data["work"]["1f"]["furniture"]


def f(slot, x, y, **extra):
    d = {"slot": slot, "pos": [x, y]}
    d.update(extra)
    return d


# ── shop · 杂货铺 (bounds 7x6, 内格 x∈1..5 y∈1..4) ──
#   原挡格集(非 walkable 内格)：counter[1,1] shelf[3,1] shelf[4,1] crate[1,3] crate[2,3]
#   walkable：rug[4,3]。★保 counter[1,1]+crate[2,3] 两个 slot 名（role=store 触发器）+ 两个 shelf（货架/FURNROLE）；
#   crate[1,3]→sacks（谷袋，仍非 walkable、同格 ⇒ 挡格不变）；加 walkable rug[3,4]（店门迎宾垫，门在[3,5]）。
shop_1f = [
    f("counter", 1, 1),      # 保 slot（role=store 触发器）→ 画法按 role 派发成杂货铺前柜（收银机+挂秤+果篮）
    f("shelf", 3, 1),        # 货架（role=store→_shelf_goods，FURNROLE 采样，逐像素与 [4,1] 同）
    f("shelf", 4, 1),        # 货架（同上）
    f("sacks", 1, 3),        # ← crate[1,3] 原挡格 → 谷袋堆（同格同 walkable，纯换画法）
    f("crate", 2, 3),        # 保 slot（role=store 触发器）→ 画法派发成敞口果蔬箱
    f("rug", 4, 3),          # 原 walkable 地毯（不动）
    f("rug", 3, 4),          # NEW walkable 店门迎宾垫（空格，不挡格 ⇒ 零金标）
]

# ── work · 工坊 (bounds 9x7, 内格 x∈1..7 y∈1..5) ──
#   原挡格集：desk[1,1] crate[3,1] shelf[5,1] stool[1,3] crate[2,3]；walkable：rug[4,3]。
#   ★role=workshop 由 areas.type 定、与 slot 无关 ⇒ 除保 shelf[5,1]（工具架/FURNROLE）外，其余按工坊身份改名；
#   全部原地换 slot（位置+walkable 不变 ⇒ 挡格集不变）；加 walkable rug[4,1]（工坊门垫，门在[4,0]）。
work_1f = [
    f("workbench", 1, 1),    # ← desk[1,1] 原挡格 → 工作台（台钳+刨）
    f("lumber", 3, 1),       # ← crate[3,1] 原挡格 → 木料堆
    f("shelf", 5, 1),        # 工具架（role=workshop→_shelf_tools，FURNROLE 采样，保 slot 名）
    f("anvil", 1, 3),        # ← stool[1,3] 原挡格 → 铁砧
    f("materials", 2, 3),    # ← crate[2,3] 原挡格 → 材料箱
    f("rug", 4, 3),          # 原 walkable 地毯（不动）
    f("rug", 4, 1),          # NEW walkable 工坊门垫（空格，不挡格 ⇒ 零金标）
]

data["shop"]["1f"]["furniture"] = shop_1f
data["work"]["1f"]["furniture"] = work_1f

# 写回：CRLF（原文件 CRLF；redump-then-CRLF 逐字节等于原文件，已在 host 验证）——其余 6 栋+_note 逐字节不变。
out = json.dumps(data, ensure_ascii=False, indent=1).replace("\n", "\r\n").encode("utf-8")
open(P, "wb").write(out)
print("wrote", P, "bytes", len(out), " shop:", len(shop_1f), " work:", len(work_1f))

# ── 不变式自证：导航挡格集（内格非-walkable 家具格）逐格不变，按【每栋各自 bounds】算 ──
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
for sid, old in (("shop", old_shop), ("work", old_work)):
    b = spaces[sid]["bounds"]
    w, h = int(b[2]), int(b[3])
    a = blocked_interior(old, w, h)
    n = blocked_interior(data[sid]["1f"]["furniture"], w, h)
    ok = (a == n)
    allok = allok and ok
    print("  %-5s bounds %dx%d  内格挡格集 identical: %s | old %s new %s"
          % (sid, w, h, ok, sorted(a), sorted(n)))
print("ALL 挡格集 byte-identical:", allok)
