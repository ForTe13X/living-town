#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""asset_gate.py —— emote / decor / obj / building 资产门（Wave H · H2；docs/50 §二）。

## 为什么是【第三个文件】而不是往 art_gate.py 里加

形状**照抄** `art_gate.py`（G1）与 `terrain_gate.py`（G5）：当场从 CC0 库重建 → 解码后逐像素比对
→ 三条"这道门自己会不会是假的"自证。docs/50 §二 的原话是「已经有两份同形的了，别发明第三种」
——本文件是**同一个形状的第三个实例**，不是第三种形状。分开成新文件的理由有四条，都可复核：

1. `art_gate.py` 在模块层 `import coif_characters as cc`，而它的 `compare()` 深度依赖
   `cc.FRAME / cc.ROWS_USED / cc.COLS_USED`（角色表的"可达帧"几何）。emote/decor/obj **没有帧**
   ⇒ 塞进去要么把 G1 刻意做的"例子优先取可达帧"挖掉，要么给它加一条恒真分支。两者都更差。
2. G5 已经立过先例：terrain 那 13 张也没有并进 `art_gate.py`，而是开了 `terrain_gate.py`。
3. 爆炸半径：`art_gate.py` 是 G1/G2 的行，本波仍可能有别的棒动它；新文件零冲突。
4. CI 里是独立一步（2d）⇒ 红的时候它自报家门，而不是让人去 2b 的输出里找是哪一类资产。

## 它守的性质（**Wave J·J2 之后是三条**）

1. **出货 == 配方**：眼验过的出货 png 必须等于配方现在能重建出来的东西。
2. **（I1 新增）表情之间必须分得开**：上门的 10 张 emote 两两差必须过一个**量出余量之后才定**的地板。
   理由见下面「为什么 emote 从 9 张不上门变成 10 张上门」。
3. **（J2 新增）切图配方不许从连着的美术中间切过去**：一条 crop 如果把图集里**连通的**一块
   美术拦腰截断，切出来的就是**碎片**不是精灵。判据 = `bleed()`，见下面 `CUT_FRAC_FLOOR` 一节。
   这一条**只判配方的几何**，不判画得好不好 —— 所以它可以（也必须）覆盖**没人眼验过**的图。

另外 1 张**仍然故意不上门**（性质 1 与 2 的意义上），这不是偷懒，是 H2 那一棒的全部要点
（docs/50 §〇·2 / docs/51 §三·4）：

> **给没有人眼验过（或已知画错、或根本上不了屏）的美术上门 = 把当前状态钉成"正确"。**
> 池塘那个 bug 正是这样活了一个月。

## 为什么 emote 从「9 张不上门」变成「10 张全上门」（Wave I · I1，docs/53 §一）

H2 当时写的理由是对的：**那 9 张当时是坏的，钉住 = 把坏钉成正确**。现在它们被重画了，
理由的前提没了，所以结论跟着变——**不是把规矩放松了，是被守的对象换了**：

```
                        旧（白气泡×9）      新（自绘×9）
两两差 min /400              6                  109
两两差 median /400          24                  191
轮廓差(alpha only) min       0（10 对并列）      11
28 设备px 渲染后 min       9.94                47.23
最近邻模板分类 top-1       37.4%               99.2%
```

⇒ 9 张 emote 从 `NOT_GATED` 挪进 `GATED`，并且**同时给它们加了第 2 条性质**（两两可分地板）
——只补第 1 条的话，一次"把 9 张又改回同一个图"的改动能全绿通过。

- **~~obj/bath + obj/arcade + decor/tree_big（3 张）~~ —— J2 2026-07-30 已重画，三张都进了 GATED。**
  它们的配方从 ffmpeg crop 换成了 `slice_all.SPRITES` 的字符画（同 I1 给 9 张 emote 做的那条路）。
  **三张的病不是同一种，这一点值得写下来**：`tree_big` 真的是**切错了**（右边界 27/32、下边界 29/32
  个不透明像素，从别的树冠中间横切过去）；`bath`/`arcade` **一个像素都没切错**（四边各 0，正落在格线上）
  ——它们错在**题材**：那两格画的是一口井和一根告示柱，而 `WorldView._draw_landmarks()` 里
  **已经有**程序化的 `well` 与 `board`，`board` 就在 `arcade_1` 正下方 2 格。
  "重切"这条路三张都走不通，理由见 `tools/slice_all.py` 抬头（整张表 45 个自足单格道具里 0 浴池 0 街机；
  32×32 窗口全扫一遍也没有 2 格高的独立树）。
- **decor/tree_small（1 张）**：H1 判「从不出现」——**不在 `WorldView.DECOR_POOL` 里**。
  本文件每次运行都**重新核**这一条（见下面自证④），不是抄 docs/51 的结论。
  给不上屏的素材上门 = 把一份死资产钉成"正确"，而它的正确处置是**接线或删掉**，两条路都会动到文件本身。
- **~~building/{house,hut,shop}（3 张）~~ —— I2 2026-07-30 已按上面那句执行了「删掉」。**
  它们不再属于"不上门"，改由 `DELETED` + `check_deleted()` 守着**不许回来**（那一节写清了为什么
  "删完就不用管了"是错的：原来的棘轮查 `building_tex` 调用点，而**输入随函数一起没了**）。

## 硬判据 vs 软判据（**这一条与 art_gate.py 不一样，别照抄错**）

`art_gate.py` 第 3 节的**小标题**写着"逐字节比对"，但它的代码从来就是**解码后 RGBA 逐像素**
（`compare()` 比的是 `Image.load()` 出来的元组），容器字节只 print。**照抄它的代码是对的，
照抄它的标题会害死人**——docs/50 §二 坑①：H1 在隔离目录重切全部 26 张，实测
**逐像素相同 26/26、逐字节相同 0/26**。真拿字节判红 ⇒ 换一台机器就全假红。

> ⚠️ **J2 更正了那个 0/26 的【机制】（结论不变，理由是错的）**。docs/51 §三·2 把它解释成
> "出货那批当年被**重新编码/压缩过**，不是 ffmpeg 的原始输出"。**不成立**：
> 我把两份配方原样放进 `gamecraft-runner:4.6.2` 容器里跑了一遍（ffmpeg 在容器里才有），
> 与出货逐个比对 ⇒ **28/28 逐像素相同，而且 28/28 逐【字节】也相同**。
> 差别只是 **ffmpeg 版本**：容器里是 **4.4.2**（Ubuntu 22.04），H1 当时用的是**宿主机的 8.1.2**。
> ⇒ 出货文件没有被谁重新压缩过，它们就是容器 ffmpeg 的原始输出。
> **判据必须是逐像素这一条照旧成立**，理由换成更结实的那个：**字节取决于编码器版本，
> 而这道门要在任何人的机器上跑。**（本门的软判据比的又是第三个编码器：Pillow。）

- **硬**：解码后的 RGBA 逐像素。这是真正进 Godot 纹理、真正上屏的那份数据。
- **软**：本机 Pillow 重编码出来的 PNG 容器字节。**只打印，永不判红**（实测 0/19 相同）。

## 四条自证（每次跑都做，不是注释里的承诺）

1. **重建来源自证**：重建期间把 `PIL.Image.open` 换成探针。要求命中 `library/` ≥1、命中出货目录**恰好 0**。
2. **判别力自检（teeth）**：**逐张**——对**每一张**上门的图各注入 1 个像素，要求比对器报"恰好 1 px"
   且**指名是这一张**。打印 `detected X/X`。
   （art_gate/terrain_gate 只探 1 张 ⇒ 那测的是 recall 不是 coverage，docs/41 §2.5 外审的原话。）
3. **扫过量自证**：打印实际比对了几张 / 几个像素 / 几个字节，三个数为 0 一律判红。
4. **本门特有：范围自证（scoping）**。这道门最容易出的错不是判错，是**守错东西**，所以范围本身要机检：
   - 配方产出的每一张都必须落进**三张表之一**（`GATED` / `NOT_GATED` / `ELSEWHERE`），
     少一张就红。新资产必须有人**显式**决定守不守 —— 默认放行正是本波要拦的那个病。
   - **这条自证是双向的，I2 实测踩了另一个方向**：把 `slice_visual.py` 的三行建筑配方删掉、
     而 `NOT_GATED` 还写着它们 ⇒ `phantom` 臂当场红（「三张表里有 3 张配方根本产不出的图」，rc=1）。
     ⇒ **删资产必须连表一起删**，否则表和配方漂开。这不是障碍，是这道门本来就该说的话。
   - `ELSEWHERE`（terrain 那 5 张归 `terrain_gate.py`）不是写死的转告：本门去核
     `slice_shore.LEGACY|SHORE` 里**真的还有它们**，没有就红。
   - **上门的每一张都必须在代码里可达**（decor 在 `DECOR_POOL`／obj 在 `OBJ_SLOT_BY_TYPE`／
     emote 在 `_emote_key` 的 return 行），从 `game/scripts/*.gd` 源码解析，解析到 0 条即判红。
   - **"从不出现"的 `tree_small` 必须仍然不可达**（代码里零命中，注释不算）。
     哪天有人把它接上线，这条会红——**那正是该重新眼验、重新决定守不守的时刻**（棘轮，同 H3 的别名预算）。
   - **已删除的三张必须留在删除态**（`check_deleted()`：出货目录 / 切图配方 / `.gd` 非注释引用，三处都不许有）。
5. **（J2 新增）切图配方不许拦腰截断连通的美术**（`bleed()` + `CUT_FRAC_FLOOR`）。
   它与上面四条的关键差别：**它判的是配方，不是出货像素**，所以它对
   **还没有人眼验过的图**照样有话说 —— 而那正是 `house` / `shop` / `tree_big` 三次都缺的那道门。

## 明确不做

- **不查画得好不好、不查"读出来是不是那个情绪"**。门能判"这两张不一样"，判不了"这张是道歉"
  ——后者只有人眼能判（I1 的眼验图见回执）。两两地板拦得住"又变回一个样"，拦不住"十张都很丑但互不相同"。
- **不给 obj 立两两可分地板**（J2 量过之后放弃的，理由要写下来，别让下一棒再想一遍）：
  9 张 obj/decor 的两两源像素差里，`obj/counter` vs `obj/desk` 只有 **17/256**（H1 早就报过），
  而其余最近的一对是 **86/256**。任何能拦住"两件家具画成同一张"的地板都会**在干净树上判红**，
  而修法是重画 counter/desk —— 那是另一棒的活。**先量再定地板**的结论有时候是"今天定不了"。
- **不查别名**（一张 bench.png 服务五种物件）——那是 H3 的 `OBJ_SLOT_ALIAS_BUDGET`。
- **不对 7 张未上门的图判红**（缺失/多余只 WARN），理由见上。

## 探测包络（docs/41 §2.5；J2 2026-07-30 复跑，隔离副本，逐条读 rc 与判决行）

```
detects（11 个变异体里 8 个变红，rc 均为 1）：
  A2 把 decor/tree_big 单独退回 HEAD 的切图路线 ⇒ 断口臂红并点名「56/128 = 0.438」
     ★ 这一条是在【未改动的树】上跑的（docs/41 §6 ★），不是只在我造的变异体上
  A  整棵树退回 HEAD（三张图 + 两份配方）⇒ 红两处（断口 + SPRITES 空）
  E  把旧 crop 加回 slice_visual（配方与自绘表同产一张）⇒ 断口红 + 逐像素 768 px 不同
  B/C/D  obj/bath · obj/arcade · decor/tree_big 各翻 1 px ⇒ 各自红并点名那一张
  G  清空 slice_all.SPRITES ⇒ 红两处（配方没了 + 三张表里 3 张幽灵）
  H  把 render_drawn() 改成读出货 png ⇒ 红「抄答案不是重建」，点名 3 个文件
  F  把 tree_small 塞进 WorldView.DECOR_POOL ⇒ 红（I2 那条自检④的臂**仍然有牙**）

does_not_detect（3 个变异体实测**全绿 rc=0**，不是推断）：
  I  把 tree_big 改成一块 32×32 纯色方块，**配方与出货一起改** ⇒ PASS。
     ⇒ 性质①只说「出货 == 配方」，它对「美术变差了」结构上失明。
  J  把 arcade 换回切图，落在另一个**自足但题材错**的格子 (8,30) ⇒ 断口 0.000 ⇒ PASS。
     ⇒ 断口臂只看「crop 有没有切断连着的美术」，看不见「切得很干净但画的是别的东西」
        —— 而 bath/arcade 得的正是后面这个病（旧 crop 四边断口各 0）。**这一栏是本棒最该被读到的一行。**
  K  把 obj/counter 与 obj/desk 做成同一张 ⇒ PASS（obj 没有两两可分地板，理由见上「明确不做」）。
  另外三处结构性盲区（不需要变异体就能说清）：
   · **自绘的 12 张对断口臂天然免疫**——它们没有「框外」。今天 23 张里 12 张不在这条臂的射程内。
   · **terrain 那 5 张被排除在断口臂之外**（满铺瓦按设计就是无缝的：grass_a 0.500 / dirt 1.000 / water 1.000）。
   · **断口臂对 `building/hut` 会判阳（0.297 ≥ 0.10），而 H1 说它是「唯一一张完整可用的 1×1 小屋」。**
     两边都对：它确实是一整块房屋图集左上角的那一格，只是那一格看起来像小屋。
     ⇒ 这条臂说的是「这条 crop 切断了连通的美术」，不是「切出来的东西不好看」。（hut 已被 I2 删除，今天不误伤在架资产。）

confidence：N=11（8 红 / 3 绿）。断口臂的地板 0.10 标定在 4 个阳性 + 12 个阴性上：
  阳性 building/shop 0.474 · decor/tree_big(旧) 0.438 · building/hut 0.297 · building/house 0.188
  阴性 11 条并列 **0.000**，最高的是 decor/tree_small **0.031**
  ⇒ 阴性最高值到地板 3.2x，地板到最低阳性 1.9x。**两侧都有余量**，不是贴着边定的。
```

用法:
    python tools/asset_gate.py            # 门：PASS ⇒ exit 0，FAIL ⇒ exit 1
    python tools/asset_gate.py -v         # 附逐张明细 + 未上门清单
"""
import io
import os
import re
import subprocess
import sys

try:
    import PIL
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("❌ asset gate: 需要 Pillow（pip install pillow）—— 重建管线依赖它，装不上就没有这道门")

try:                                    # Windows 控制台默认 GBK，直接 print 中文/✅ 会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
ART = os.path.join(ROOT, "game", "assets", "art")
GD_DIR = os.path.join(ROOT, "game")
SLICERS = (os.path.join(TOOLS, "slice_all.py"), os.path.join(TOOLS, "slice_visual.py"))
# "building" 留在表里**是刻意的**，尽管 I2 删空了那个目录（目录已不存在，下面每处都 isdir 守着）：
# 留着，出货目录里再冒出**任何**一张 building/*.png 都会被 stray 那条报出来（DELETED 只点名那 3 个）。
SHIPPED_DIRS = ("emote", "decor", "obj", "building")

# ── 上门的 22 张（decor6+obj3 来自 docs/51 §三·4 的 H1 真机眼验；emote10 见上，I1 重画+眼验；
#    obj/bath + obj/arcade + decor/tree_big 是 J2 重画+眼验）────────────────────────────────
GATED = {
    "decor/bush", "decor/flower_red", "decor/flower_yellow",
    "decor/rock", "decor/stump", "decor/mushroom",
    "obj/bench", "obj/counter", "obj/desk",
    # J2 自绘的 3 张：配方在 tools/slice_all.py 的 SPRITES 里（字符画 → render_drawn() 纯函数重建）。
    "obj/bath", "obj/arcade", "decor/tree_big",
    # emote 10 张：confront 是 CC0 切片（H1 眼验判 OK，像素未动）；其余 9 张是 I1 自绘，
    # 配方在 tools/slice_all.py 的 GLYPHS 里（字符画 → render_glyph() 纯函数重建）。
    "emote/confront",
    "emote/greet", "emote/give", "emote/gossip", "emote/invite",
    "emote/meet_fulfilled", "emote/meet_broken", "emote/conflict",
    "emote/apologize_ok", "emote/apologize_no",
}

# 上门 emote 里哪些必须两两分得开（= 全部 10 张，因为 10 张都会画在同一个位置表达不同的事）
DISTINCT_SET = sorted(k for k in GATED if k.startswith("emote/"))

# ── 不上门的 1 张，写明理由。**这张表和上面那张必须并起来盖住整份配方**（自证④）──────────
NOT_GATED = {
    "decor/tree_small": "从不出现：不在 WorldView.DECOR_POOL 里（本门自证④每次重核）—— 该接线或删掉，不是该钉住",
    # building/{house,hut,shop} 曾经在这里，理由是「从不出现：Art.building_tex() 全仓零调用点」。
    # I2（2026-07-30）执行了这条注释自己开的第二条药方——**删掉**。它们现在归下面的 DELETED 管。
    #
    # obj/bath、obj/arcade、decor/tree_big 也曾经在这里（H1 判「读不出」/「需要重切」）。
    # J2（2026-07-30）执行了「先重画再守」——三张已重画并进 GATED。
    # ⚠️ **这张表现在只剩一条，而它正是自证④「死资产必须仍然是死的」那条臂唯一的活输入**
    #    （I2 特意留下 tree_small 的第二个理由）。J2 没有消费它：`tree_big` 是**自绘**的，
    #    不是从 tree_small 重切的 ⇒ 这条臂的输入原封不动，仍然会红（J2 复跑了 I2 的负对照：
    #    把 "tree_small" 塞进 WorldView.DECOR_POOL ⇒ rc=1）。
    #    **它同时也是本门"不上门也要盖住"这条范围纪律的最后一个实例**：这张表空了的那天，
    #    `unclassified` 那条臂就再没有"故意不守"的对照面了。
}

# ── 配方里还有 5 张 terrain —— 它们**已经有门了**（G5 的 tools/terrain_gate.py）────────────
# `slice_visual.py` 同时产 terrain + decor + building，所以采配方一定会采到这 5 条。
# 它们既不属于本门的 GATED，也不是"没人管"，第三个桶必须存在，否则范围自证会假红（实测：第一次跑就红了）。
# **并且本门会去核 terrain_gate 真的还在守它们**（下面 `check_elsewhere`）——
# 「存在」与「被使用」是两件必须分开问的事（docs/50 §八），对门本身同样成立。
ELSEWHERE = {
    "terrain/grass_a": "terrain_gate.py（G5）",
    "terrain/grass_b": "terrain_gate.py（G5）",
    "terrain/grass_flowers": "terrain_gate.py（G5）",
    "terrain/dirt": "terrain_gate.py（G5）",
    "terrain/water": "terrain_gate.py（G5）",
}

# ── 第四张表：**已删除**（I2 2026-07-30）───────────────────────────────────────────────────
#
# ## 为什么删掉之后还需要一张表——这一条是本次改动的全部要点
#
# 原来自证④靠 **`building_tex` 全仓零调用点** 守着 building 那 3 张「从不出现」的图。
# I2 把 `Art.building_tex()` 连同 3 张 png 一起删了 ⇒ **那条判据的输入没有了**。
# 它不会变红——它会**永远绿**，而这正是 docs/41 §2.5 第三个盲区的原话：
#
#   > 一道门可以【已经在 CI 里、已经是绿的】，却跑在一个它永远不可能变红的配置上。
#
# 精确一点（这一栏不许含糊，见下面 does_not_detect）：删掉之后那条 grep **不是全空真**——
# 谁要是把 `func building_tex` 原样加回来再调用它，字符串还是会命中。
# 但**最自然的复活写法**（直接 `Art.tex("res://assets/art/building/hut.png")`，因为 helper 已经没了）
# 它一个字都看不见。⇒ 它守得住"照原样抄回来"，守不住"换个写法接上"。**这不叫棘轮，叫运气。**
#
# 所以换一条**还有输入**的判据：输入从"代码里有没有人调它"变成"**这三个名字有没有回来**"。
# 三处任何一处出现即红：
#   ① 出货目录里又有这个 png；
#   ② 切图配方（slice_visual.py）又产得出它；
#   ③ 任何 `.gd` 的**非注释**行引用 `building_tex` 或 `assets/art/building`。
# 方向与原来的棘轮一致（悄悄复活会被拦下），守的东西换成了「删干净了」。
#
# ⚠️ ③ 为什么必须跳过注释：旧的 `bt_calls` **不跳**，于是 I2 在 `Art.gd` 里写下"为什么删掉它"的
#    那段说明本身就把门弄红了（实测：`❌ building_tex 调用点 ['game/scripts/Art.gd:97']`，
#    而 :97 是一行 `##`）。**一道门不该把解释它自己的文字判成违规。**
DELETED = {
    "building/house": "I2 2026-07-30 删除（16x64 图集竖条带，四边断口）—— docs/09 §1.1",
    "building/hut": "I2 2026-07-30 删除（消费者早在 841d4c4 就被当作「比例失调」头号成因拆掉）—— docs/09 §1.1",
    "building/shop": "I2 2026-07-30 删除（32x64 图集区域，内含六个橙顶石屋残片）—— docs/09 §1.1",
}
_DELETED_CODE_TOKENS = ("building_tex", "assets/art/building")


def _rel(p):
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:
        return p


def _under(parent, p):
    """p 是否在 parent 目录之内（normcase + sep 前缀；跨盘符不抛异常）。"""
    parent = os.path.normcase(os.path.abspath(parent)).rstrip("\\/") + os.sep
    return os.path.normcase(os.path.abspath(p)).startswith(parent)


def _local(container_path):
    """把切图脚本里的容器路径 `/game/...` 映射到本仓库路径。别的前缀返回 None。"""
    p = str(container_path).replace("\\", "/")
    if not p.startswith("/game/"):
        return None
    return os.path.normpath(os.path.join(ROOT, p[1:]))


# ── 配方采集：**执行**切图脚本、把 ffmpeg 拦下来，而不是抄第二份坐标表 ───────────────────
_CROP_RE = re.compile(r"^crop=(\d+):(\d+):(\d+):(\d+)$")


def harvest_recipes():
    """跑 tools/slice_all.py + slice_visual.py，把它们**打算**喂给 ffmpeg 的每一条 crop 记下来。

    docs/50 §二「别在门里抄第二份坐标表——从源码解析，解析到 0 行就判红」。
    这里比"解析"更进一步：**直接执行配方本体**，只把 `subprocess.run` 与 `os.makedirs` 换成探针
    ⇒ 多格瓦的 `wt*T / ht*T` 算术也是配方自己算的，本文件一个坐标都不复制。
    （同一个手法 art_gate.py 已经用在 `Image.open` 上了。）

    返回 {key: {"sheet":本地路径, "box":(l,t,r,b)}}，key = "<dir>/<name>"。
    抓到 0 条 ⇒ 调用方判红（配方换了写法，不能静默放行）。
    """
    recs = {}
    bad = []

    # ① 自绘配方：**import** slice_all（不是 exec）拿 GLYPHS / SPRITES —— 它有 main 守卫，import 零副作用。
    #    这里刻意不抄一份字形表：门里出现第二份坐标/像素，两份就会各自漂（docs/50 §二 原话）。
    try:
        import slice_all as _sa
        if not getattr(_sa, "GLYPHS", None):
            bad.append("slice_all.GLYPHS 是空的 —— 自绘表情的配方没了，不能静默放行")
        if not getattr(_sa, "SPRITES", None):
            bad.append("slice_all.SPRITES 是空的 —— 自绘世界精灵的配方没了，不能静默放行")
        for _name in getattr(_sa, "GLYPHS", {}):
            recs["emote/%s" % _name] = {"drawn": "emote/%s" % _name}
        for _key in getattr(_sa, "SPRITES", {}):
            recs[_key] = {"drawn": _key}
    except Exception as e:                          # noqa: BLE001 —— 任何 import 失败都必须判红
        bad.append("import slice_all 失败（%s）—— 拿不到自绘资产的配方" % e)

    orig_run, orig_makedirs = subprocess.run, os.makedirs

    def spy_run(cmd, *a, **k):
        try:
            cmd = list(cmd)
            inp = cmd[cmd.index("-i") + 1]
            vf = cmd[cmd.index("-vf") + 1]
            out = cmd[-1]
            m = _CROP_RE.match(str(vf))
            sheet, dst = _local(inp), _local(out)
            if not m or sheet is None or dst is None:
                bad.append(" ".join(str(c) for c in cmd))
                return None
            w, h, x, y = (int(g) for g in m.groups())
            key = "%s/%s" % (os.path.basename(os.path.dirname(dst)),
                             os.path.splitext(os.path.basename(dst))[0])
            recs[key] = {"sheet": sheet, "box": (x, y, x + w, y + h)}
        except Exception as e:                      # 配方换了 argv 形状 ⇒ 记下来，让调用方判红
            bad.append("%r (%s)" % (cmd, e))
        return None

    os.makedirs = lambda *a, **k: None               # 配方会往 /game/... 建目录：拦住，别在盘根上乱建
    subprocess.run = spy_run
    hold, sys.stdout = sys.stdout, io.StringIO()     # 配方自己会 print("sliced ...")：别混进门的输出
    try:
        for path in SLICERS:
            if not os.path.isfile(path):
                bad.append("找不到切图配方 %s" % _rel(path))
                continue
            with open(path, encoding="utf-8") as f:
                src = f.read()
            # `__name__ = "__main__"`：两份配方今天都是**裸的模块级代码**（没有 main 守卫），
            # 但哪天有人给它们加上 `if __name__ == "__main__":`，用 "_slicer" 会让采集悄悄变成 0 条。
            # 那时门确实会红（"一条 crop 都没采到"），但那是一次**假红**——配方并没有坏。
            # `ASSET_GATE_HARVEST`：告诉配方"只走切图这一半，别写盘"。没有它的话，
            # 采配方这一步会把本门正要判的 9 个出货 png 覆盖掉 —— 判据当场退化成 x→x。
            # （下面 `main()` 里还有一条 mtime 自证，去实测门确实没碰过出货目录。）
            try:
                exec(compile(src, path, "exec"),
                     {"__name__": "__main__", "__file__": path, "ASSET_GATE_HARVEST": True})
            except SystemExit:
                pass
    finally:
        sys.stdout = hold
        subprocess.run, os.makedirs = orig_run, orig_makedirs
    return recs, bad


def rebuild(recs, keys):
    """按配方当场重建，并记录重建期间打开过哪些文件（自证①）。返回 ({key: RGBA Image}, opened)。

    两种配方走两条路：
    - `{"sheet","box"}` ⇒ 从 CC0 源表 crop（老路，读文件）。
    - `{"drawn"}`       ⇒ 调 `slice_all.render_drawn()`（**一个文件都不读**：它是纯函数，
                          字符画写在配方源码里）。所以自绘那 12 张的"重建独立于出货目录"
                          比切片那批还强 —— 它压根没有可抄的答案。
    """
    import slice_all as sa

    opened = []
    orig_open = Image.open

    def spy(fp, *a, **k):
        try:
            opened.append(os.path.abspath(os.fspath(fp)))
        except Exception:
            pass
        return orig_open(fp, *a, **k)

    Image.open = spy
    sheets, out = {}, {}
    try:
        for key in sorted(keys):
            r = recs[key]
            if "drawn" in r:
                w, h, px = sa.render_drawn(r["drawn"])
                im = Image.new("RGBA", (w, h))
                im.putdata(px)
                out[key] = im
                continue
            sp = r["sheet"]
            if sp not in sheets:
                with Image.open(sp) as im:
                    sheets[sp] = im.convert("RGBA")
            out[key] = sheets[sp].crop(r["box"])
    finally:
        Image.open = orig_open
    return out, opened


def compare(key, shipped, rebuilt, limit=3):
    """出货图 vs 重建图 → (差异像素数, [人话描述...], 比对的像素数)。

    ⚠ 本函数是这道门唯一的"是不是一样"判据 ⇒ 每次运行都被 teeth 自检拿**每一张**已知不同的
    图各喂一遍（不是只喂一张，理由见模块 docstring 自证②）。
    比的是 `load()` 出来的 RGBA 元组 —— **不是** `getbbox()`（docs/41 §6：它在 RGBA 上默认
    只看 alpha，翻一个不透明像素的 RGB 会被判成"完全相同"）。
    """
    if shipped.size != rebuilt.size:
        return -1, ["%s：尺寸 %s ≠ 重建 %s" % (key, shipped.size, rebuilt.size)], 0
    W, H = shipped.size
    sp, rp = shipped.load(), rebuilt.load()
    ndiff = 0
    notes = []
    for y in range(H):
        for x in range(W):
            a, b = sp[x, y], rp[x, y]
            if a == b:
                continue
            ndiff += 1
            if len(notes) < limit:
                notes.append("%s：(%d,%d)  出货 %s ≠ 重建 %s" % (key, x, y, a, b))
    return ndiff, notes, W * H


# ── 可达性：从 game/scripts/*.gd 源码解析，不抄 docs/51 的结论 ───────────────────────────
def _gd_sources():
    out = {}
    for base, _dirs, files in os.walk(GD_DIR):
        if ".godot" in base.replace("\\", "/").split("/"):
            continue
        for f in files:
            if f.endswith(".gd"):
                p = os.path.join(base, f)
                try:
                    out[p] = open(p, encoding="utf-8").read()
                except Exception:
                    pass
    return out


def reachability(srcs):
    """返回 (facts, errs)。facts 里每一项都是**从代码里读出来的**，errs 非空 ⇒ 判红。"""
    errs = []
    joined = {p: s for p, s in srcs.items()}
    wv = next((s for p, s in joined.items() if os.path.basename(p) == "WorldView.gd"), None)
    if wv is None:
        errs.append("找不到 game/scripts/WorldView.gd —— 无法核可达性")
        return {}, errs

    # DECOR_POOL 是**单行**数组字面量 ⇒ 只能配到同一对方括号里，别用 `(.*?)\n]`
    # （第一版就是那么写的，一路吞到几百行之外的另一个 `]`，解析出 523 个"装饰名"——
    #   而它**照样打绿**，因为 6 个真名恰好在那 523 个里。假绿就是这么来的。）
    pm = re.search(r"const\s+DECOR_POOL\s*:=\s*\[([^\]]*)\]", wv)
    decor_live = set(re.findall(r'"([^"]+)"', pm.group(1) if pm else ""))
    # 池子之外还有直接点名的（如 _draw 里的 tree_big 回退路）
    for s in joined.values():
        decor_live |= set(re.findall(r'decor_tex\(\s*"([^"]+)"\s*\)', s))
    if not decor_live:
        errs.append("从 WorldView.gd 里一个装饰名都没解析到（DECOR_POOL 格式变了？）—— 不能静默放行")

    sm = re.search(r"const\s+OBJ_SLOT_BY_TYPE\s*:=\s*\{(.*?)\n\}", wv, re.S)
    obj_live = set(re.findall(r'"[^"]+"\s*:\s*"([^"]+)"', sm.group(1) if sm else ""))
    pre_m = re.search(r"const\s+OBJ_SLOT_BY_ID_PREFIX\s*:=\s*\{([^}]*)\}", wv)
    obj_live |= set(re.findall(r'"[^"]+"\s*:\s*"([^"]+)"', pre_m.group(1) if pre_m else ""))
    if not obj_live:
        errs.append("从 WorldView.gd 里一个物件槽都没解析到（OBJ_SLOT_BY_TYPE 格式变了？）—— 不能静默放行")

    # 只认 `_emote_key()` 里 **return 行**上的字面量。刻意不认函数里别的字符串
    # （`e["type"]` / `e["accepted"]` 是字段名，不是 emote 键；第一版把它们也算进去了）。
    ek = re.search(r"func\s+_emote_key\(.*?\n(.*?)(?=\n(?:func |## ))", wv, re.S)
    ek_body = ek.group(1) if ek else ""
    emote_live = set()
    for ln in ek_body.splitlines():
        if "return" in ln:
            emote_live |= set(re.findall(r'"([^"]+)"', ln))
    if not emote_live:
        errs.append("从 WorldView.gd 的 _emote_key() 里一个 emote 键都没解析到 —— 不能静默放行")

    # ── I1 补上 H2 点名欠的那条解析 ─────────────────────────────────────────────────
    # H2 的原注释：「⚠ 这样解析**漏掉**透传分支 `_: return t` 能到达的 greet/give/gossip/invite
    #  ——将来要给那四张上门，**得先给这里补一条"从 Sim 的事件类型取"的解析，不能直接塞进 GATED**。」
    # 本波正是要给那四张上门，所以先补解析。**口径是代码给的，不是猜的**：
    #   `Sim.gd:2066` `if not (action in KNOWN_SOCIAL_ACTIONS): ...` 挡在
    #   `Sim.gd:2077/2210` 的 `_log_event(action, ...)` 之前
    #   ⇒ 能透传到 `_emote_key` 的 `t` 恰好就是 `KNOWN_SOCIAL_ACTIONS` 这张表。
    # （注意：**不是** `_log_event("...")` 的字面量集合 —— 那里面根本没有 greet/give/gossip/invite，
    #   它们是靠变量 `action` 进去的。照字面量解析会得出"这四张不可达"的假红。）
    if re.search(r"^\s*_:\s*return\s+t\b", ek_body, re.M):
        sim = next((s for p, s in joined.items() if os.path.basename(p) == "Sim.gd"), None)
        km = re.search(r"const\s+KNOWN_SOCIAL_ACTIONS\s*:=\s*\[([^\]]*)\]", sim or "")
        acts = set(re.findall(r'"([^"]+)"', km.group(1) if km else ""))
        if not acts:
            errs.append("_emote_key 有透传分支，但从 Sim.gd 的 KNOWN_SOCIAL_ACTIONS 一个动作都没解析到"
                        " —— 那四张 emote 的可达性无从核实，不能静默放行")
        emote_live |= acts

    # 「从不出现」这一栏今天只剩 decor/tree_small 一张——building 那 3 张已由 I2 删除，
    # 改由 DELETED + check_deleted() 守着「不许回来」（见本文件 :454）。
    # 原来那条扫 building_tex 调用点的臂**连同它的被扫对象一起没了**，故删除，不是遗漏：
    # 留着它会变成一条永远扫不到东西的空臂。剩下的 tree_small 这条**输入仍然活着**
    # （它仍出货、仍不在 DECOR_POOL 里）⇒ 自证④没有因为 building 那半边被删而变空。
    ts_hits = []
    for p, s in joined.items():
        for i, ln in enumerate(s.splitlines(), 1):
            if "tree_small" in ln and not ln.lstrip().startswith("#"):
                ts_hits.append("%s:%d" % (_rel(p), i))

    return {"decor": decor_live, "obj": obj_live, "emote": emote_live,
            "tree_small_code_hits": ts_hits}, errs


def check_deleted(recs, srcs):
    """DELETED 里的三个名字必须【三处都不在】。返回人话错误串列表（空 = 过）。

    见上面 DELETED 的抬头：这是 building 那条棘轮**换了输入**之后的形态，不是补丁。
    ③ 跳过注释行——否则"为什么删掉它"的说明会把门自己弄红（实测踩过一次）。
    """
    errs = []
    for key in sorted(DELETED):
        d, n = key.split("/", 1)
        path = os.path.join(ART, d, n + ".png")
        if os.path.isfile(path):
            errs.append("出货目录里又出现了已删除的 %s" % _rel(path))
        if key in recs:
            errs.append("切图配方又产得出已删除的 %s（tools/slice_visual.py 里那三行被加回来了？）" % key)
    hits = []
    for p, s in sorted(srcs.items()):
        for i, ln in enumerate(s.splitlines(), 1):
            if ln.lstrip().startswith("#"):
                continue                      # 注释不算引用（旧的 bt_calls 不跳注释，实测会假红）
            if any(tok in ln for tok in _DELETED_CODE_TOKENS):
                hits.append("%s:%d" % (_rel(p), i))
    if hits:
        errs.append("`.gd` 里又引用了已删除的 building 素材：%s" % ", ".join(hits))
    return errs


# ── I1 新增的第 2 条性质：上门的 emote 必须两两分得开 ──────────────────────────────────
#
# **地板是量出余量之后定的，不是拍的**（docs/53 §一·2 / docs/44 §一·六）：
#
#   指标                     旧出货(白气泡)   新出货(自绘)   本门地板   新出货的余量
#   M1 源 RGBA 逐像素 /400        6            109          60        1.82x
#   M4 28设备px 渲染后灰度        5.74         15.73        10        1.57x
#
# 两条都要过，因为它们守的是不同的失效：
#   M1 抓"两张图几乎一样"；M4 抓"两张图在**上屏尺寸 + 颜色被压掉**之后几乎一样"
#   —— 后者是旧那批真正死掉的地方，而 M1 单独看不见它（M1 把颜色也算进去，
#      于是"只换个颜色、形状照抄"能靠 M1 拿高分而在 M4 上原形毕露）。
# 旧那批在两条上分别 6 和 5.74 ⇒ **这道门在未改动的树上会红**，不是装饰。
DISTINCT_SRC_FLOOR = 60
DISTINCT_GREY_FLOOR = 10.0
# 40(EMOTE_PX) × 0.45(LABEL_MIN_ZOOM) × 1.583(真机缩放) ≈ 28：玩家能看到的**最小**尺寸。
# 比这更小的时候 WorldView 整块不画，所以这就是最坏情况，不是随手挑的一个数。
DISTINCT_RENDER_PX = 28
GRASS = (133, 166, 67)


def _render_min_zoom(img, size=DISTINCT_RENDER_PX, bg=GRASS):
    """按 WorldView 的真实路径把 20×20 源图放到最小可见尺寸：NEAREST 放大 + 压在草地上。

    NEAREST 不是选来的，是 `WorldView.gd:525` 写死的（`texture_filter = TEXTURE_FILTER_NEAREST`）。
    用 PIL 的 BILINEAR 会把结论做漂：那会平滑掉正是 NEAREST 保住的锯齿结构。
    """
    up = img.resize((size, size), Image.NEAREST)
    plate = Image.new("RGBA", (size, size), bg + (255,))
    return Image.alpha_composite(plate, up).convert("L")


def distinctness(shipped):
    """返回 [(key_a, key_b, src_diff, grey_diff)]，逐对。shipped: {key: RGBA Image}。"""
    keys = sorted(shipped)
    grey = {k: list(_render_min_zoom(shipped[k]).getdata()) for k in keys}
    src = {k: list(shipped[k].getdata()) for k in keys}
    out = []
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if shipped[a].size != shipped[b].size:
                out.append((a, b, -1, -1.0))
                continue
            sd = sum(1 for x, y in zip(src[a], src[b]) if x != y)
            ga, gb = grey[a], grey[b]
            gd = sum(abs(x - y) for x, y in zip(ga, gb)) / float(len(ga))
            out.append((a, b, sd, gd))
    return out


# ── J2 新增的第 3 条性质：切图配方不许从连着的美术中间切过去 ────────────────────────────
#
# ## 病历：同一种病，三张图，三次都是人眼在事后发现的
#
#   `building/house`(16×64)、`building/shop`(32×64)、`decor/tree_big`(32×32) —— H1 与 I2 都
#   逐字写过"这是从图集里竖着/横着切下来的多格条带，四边都是断口"。三次都没有门。
#
# ## 判据：**bleed** —— 框外紧贴着框边的那一圈里，有多少个不透明像素**连着框内的不透明像素**
#
#   连着 ⇒ 那块美术在框外还在继续 ⇒ 这条 crop 从它中间切过去了。
#   `bleed/perimeter` 就是"周长里有多大比例是断口"。**注意它判的是【配方】不是【出货 png】**：
#   自绘的图没有"框外"，所以结构上不适用（见 does_not_detect）。
#
# ## 地板是量出来的，而且第一版判据被自己的量具否掉了（这一段值得留着）
#
#   我先写的是"出货 png 的左/右/上边界不许有不透明像素"（更简单，也更直觉）。
#   拿历史上四个已知实例一量，它**判反了**：
#     building/house 0.156、building/shop 0.203 —— 两张公认的碎片，**分数比** building/hut 0.688 低，
#     而 hut 是 H1 亲口说的"唯一一张完整可用的 1×1 小屋"。
#   ⇒ 那个判据只在我造它时用的那一个例子上成立。换成 bleed 之后（同样四个实例 + 12 张阴性）：
#
#     阳性（已知碎片）：shop 0.474 · tree_big(旧) 0.438 · hut 0.297 · house 0.188
#     阴性（decor/obj/emote 的其余 crop）：11 张**并列 0.000**，最高的是 decor/tree_small 0.031
#
#   floor = 0.10：阴性最高值到地板 3.2x，地板到最低阳性 1.9x。**两侧都有余量。**
#
# ## 两个必须写明的边界
#
#   ① **terrain 那 5 张按设计就是满铺的**（grass_a 0.500 / dirt 1.000 / water 1.000）——
#      它们本来就该无缝平铺。所以本臂**只覆盖 emote/decor/obj**（= GATED ∪ NOT_GATED），
#      terrain 归 terrain_gate。这不是给判据开后门，是"满铺瓦"和"精灵"本来就是两类东西。
#   ② **`hut` 会被判成碎片，而 H1 说它完整**。两边都对：它确实是一整块房屋图集的左上角那一格，
#      只是那一格**看起来**像一间小屋。⇒ 本臂说的是"这条 crop 切断了连通的美术"，
#      **不是**"切出来的东西不好看"。它今天不误伤任何在架资产（hut 已被 I2 删除）。
CUT_FRAC_FLOOR = 0.10


def bleed(sheet_img, box):
    """(断口像素数, 周长)。断口 = 框外紧贴框边、且与框内不透明像素 4-邻接的不透明像素。"""
    l, t, r, b = box
    W, H = sheet_img.size
    px = sheet_img.load()

    def op(x, y):
        return 0 <= x < W and 0 <= y < H and px[x, y][3] > 0

    n = 0
    for x in range(l, r):
        if op(x, t - 1) and op(x, t):
            n += 1
        if op(x, b) and op(x, b - 1):
            n += 1
    for y in range(t, b):
        if op(l - 1, y) and op(l, y):
            n += 1
        if op(r, y) and op(r - 1, y):
            n += 1
    return n, 2 * ((r - l) + (b - t))


def check_cut_edges(recs, keys):
    """返回 [(key, frac, n, perim)]，按 frac 降序。调用方拿 CUT_FRAC_FLOOR 判红。"""
    out = []
    sheets = {}
    for key in sorted(keys):
        r = recs.get(key) or {}
        if "sheet" not in r:                 # 自绘：没有"框外"，结构上不适用
            continue
        sp = r["sheet"]
        if sp not in sheets:
            with Image.open(sp) as im:
                sheets[sp] = im.convert("RGBA")
        n, perim = bleed(sheets[sp], r["box"])
        out.append((key, n / float(perim) if perim else 0.0, n, perim))
    out.sort(key=lambda t: -t[1])
    return out


def check_elsewhere():
    """ELSEWHERE 里的每一张，另一道门是否**真的**还在守？返回 (漏网的 key 列表, 错误串或 None)。

    理由：`slice_visual.py` 一份配方同时产 terrain + decor + building。把 terrain 那 5 张
    记成"归 terrain_gate 管"是**转告**，而转告会漂——只要有人把它们从 `slice_shore.LEGACY`
    里删掉，terrain_gate 就不再守，而本门这张表还写着"有人管"。所以去问代码，不问注释。
    """
    try:
        import slice_shore as ss
    except Exception as e:
        return [], "import slice_shore 失败（%s）—— 无法核 terrain 那 5 张是否真有门" % e
    covered = set(ss.LEGACY) | set(ss.SHORE)
    if not covered:
        return [], "slice_shore 的 LEGACY+SHORE 是空的 —— 无法核，不能静默放行"
    return [k for k in sorted(ELSEWHERE) if k.split("/", 1)[1] not in covered], None


def main():
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    fail = 0

    def ok(m):
        print("  ✅ %s" % m)

    def warn(m):
        print("  ⚠  %s" % m)

    def bad(m):
        nonlocal fail
        print("  ❌ FAIL: %s" % m)
        fail = 1

    print("### asset gate：①上门的 %d 张出货 png == 切图/自绘配方当场重建；②上门的 %d 张 emote 两两分得开；"
          "③配方里没有一条 crop 从连着的美术中间切过去"
          % (len(GATED), len(DISTINCT_SET)))
    print("  配方 %s + %s" % (_rel(SLICERS[0]), _rel(SLICERS[1])))
    print("  出货 %s/{%s}" % (_rel(ART), ",".join(SHIPPED_DIRS)))

    # ── 0. 采集配方 ─────────────────────────────────────────────────────────
    # 采配方要 exec 配方本体，而配方本体的另一半是"往出货目录写 png"。所以先记下出货文件的
    # (mtime, size)，采完再核一遍：**门不能修改它正要判的东西**（否则判据退化成 x→x，
    # 而且会是那种"永远绿"的假绿）。这条是 I1 把自绘配方接进来之后新出现的风险。
    def _snapshot():
        snap = {}
        for d in SHIPPED_DIRS:
            dd = os.path.join(ART, d)
            if not os.path.isdir(dd):
                continue
            for f in sorted(os.listdir(dd)):
                if f.lower().endswith(".png"):
                    p = os.path.join(dd, f)
                    st = os.stat(p)
                    snap["%s/%s" % (d, f[:-4])] = (st.st_mtime_ns, st.st_size)
        return snap

    before = _snapshot()
    recs, harvest_bad = harvest_recipes()
    touched = sorted(k for k, v in _snapshot().items() if before.get(k) != v)
    if touched:
        bad("采集配方的过程**改写了出货文件**：%s\n"
            "        门不能修改它正要判的东西 —— 那样比对就退化成 x→x，而且会永远绿。\n"
            "        修法：tools/slice_all.py 的写盘分支必须受 `ASSET_GATE_HARVEST` 守住。"
            % ", ".join(touched))
    else:
        ok("门自身无副作用：采集配方前后 %d 个出货 png 的 (mtime, size) 逐个未变" % len(before))
    for b in harvest_bad:
        bad("切图配方里有一条读不懂的命令：%s" % b)
    if not recs:
        bad("从两份切图配方里一条 crop 都没采到 —— 配方换了写法，不能静默放行")
        print("\n=== ASSET GATE FAIL ❌ ===")
        return 1
    ok("配方采集：从 2 份切图脚本里拦下 %d 条 crop（未真的调用 ffmpeg；坐标全部来自配方自己算的）" % len(recs))

    # ── 1. 范围自证（本门特有，自证④）────────────────────────────────────────
    known = GATED | set(NOT_GATED) | set(ELSEWHERE)
    unclassified = sorted(set(recs) - known)
    phantom = sorted(known - set(recs))
    if unclassified:
        bad("配方里有 %d 张【没人决定守不守】的图：%s\n"
            "        新资产必须显式进 asset_gate.GATED / NOT_GATED / ELSEWHERE —— 默认放行正是"
            "「一张没人看过的贴图躺了一个月」的成因（docs/50 §〇·2）"
            % (len(unclassified), ", ".join(unclassified)))
    if phantom:
        bad("上门/不上门/别人管 三张表里有 %d 张配方根本产不出的图：%s（表和配方漂开了）"
            % (len(phantom), ", ".join(phantom)))
    if not unclassified and not phantom:
        ok("范围自证：配方 %d 张 = 上门 %d + 不上门 %d + 别的门管 %d，逐名对齐（0 未分类 / 0 幽灵）"
           % (len(recs), len(GATED), len(NOT_GATED), len(ELSEWHERE)))

    # ── 1a. 第 3 条性质：配方里没有一条 crop 从连着的美术中间切过去（J2）─────────────
    #     范围是 GATED ∪ NOT_GATED（= emote/decor/obj），**刻意包含没上门的那一张**：
    #     这一条判的是配方几何，不是"art 好不好"，所以它对没人眼验过的图恰恰最该开口
    #     —— house / shop / tree_big 三次都是缺这道门。terrain 不在范围里（满铺瓦按设计就该无缝）。
    cut_scope = (GATED | set(NOT_GATED)) & set(recs)
    cuts = check_cut_edges(recs, cut_scope)
    if not cuts:
        warn("没有一条 crop 落在本臂范围内（%d 张全是自绘）—— 断口判据这次没有可判的对象" % len(cut_scope))
    else:
        over = [c for c in cuts if c[1] >= CUT_FRAC_FLOOR]
        if over:
            bad("有 %d 条 crop 从图集里**连通的**美术中间切过去（断口占周长 ≥ %.0f%%）：\n%s\n"
                "        切出来的是【碎片】不是【精灵】—— building/house·shop 与 decor/tree_big 都是这么来的。\n"
                "        修法：把 crop 挪到自足的格子上；如果表里根本没有这个东西，就改自绘"
                "（tools/slice_all.py 的 SPRITES）。"
                % (len(over), CUT_FRAC_FLOOR * 100,
                   "\n".join("        · %s  断口 %d/%d = %.3f" % (k, n, p, f) for k, f, n, p in over)))
        else:
            worst = cuts[0]
            tied = [k for k, f, n, p in cuts if abs(f - worst[1]) < 1e-9]
            ok("断口自证：%d 条 crop 逐条自足（最大断口 %s = %.3f < %.2f，余量 %s；自绘 %d 张不适用）"
               % (len(cuts), worst[0], worst[1], CUT_FRAC_FLOOR,
                  ("%.1fx" % (CUT_FRAC_FLOOR / worst[1])) if worst[1] > 0 else "∞（断口为 0）",
                  len(cut_scope) - len(cuts)))
            print("     ℹ  并列在最大值 %.3f 上的 crop：%s" % (worst[1], ", ".join(tied)))

    orphan, ew_err = check_elsewhere()
    if ew_err:
        bad(ew_err)
    elif orphan:
        bad("记成「别的门管」的 %d 张其实没人管了：%s —— slice_shore 不再产它们 ⇒ terrain_gate 也不再守。\n"
            "        「存在」与「被使用」是两件事（docs/50 §八），对门本身一样。"
            % (len(orphan), ", ".join(orphan)))
    else:
        ok("交接自证：记成「terrain_gate.py 管」的 %d 张，逐个仍在 slice_shore 的 LEGACY+SHORE 里（去问代码，不问注释）"
           % len(ELSEWHERE))

    gd_srcs = _gd_sources()                  # 走一次树，两条判据共用（reachability + check_deleted）
    facts, rerrs = reachability(gd_srcs)
    for e in rerrs:
        bad(e)
    if facts:
        unreach = []
        for key in sorted(GATED):
            d, n = key.split("/", 1)
            live = facts.get({"decor": "decor", "obj": "obj", "emote": "emote"}.get(d, ""), set())
            if n not in live:
                unreach.append(key)
        if unreach:
            bad("上门表里有 %d 张【代码里到不了屏幕】的图：%s\n"
                "        给上不了屏的素材上门 = 把死资产钉成「正确」（docs/50 §八）。"
                "要么接线，要么把它挪进 NOT_GATED。" % (len(unreach), ", ".join(unreach)))
        else:
            ok("可达性：上门的 %d 张逐个在代码里可达" % len(GATED) +
               "（decor∈DECOR_POOL %d 项 / obj∈OBJ_SLOT_BY_TYPE %d 槽 / emote∈_emote_key %d 键）"
               % (len(facts["decor"]), len(facts["obj"]), len(facts["emote"])))

        ts = facts["tree_small_code_hits"]
        if ts:
            bad("「从不出现」的 decor/tree_small 不再是死的了：代码命中 %s\n"
                "        这不是坏事，是**该重新眼验、重新决定守不守**的时刻（docs/50 §八：正确处置是接线或删掉）。\n"
                "        处置：眼验后把它从 NOT_GATED 挪进 GATED，或像 I2 对 building 那样明确删掉 png 与配方行。" % ts)
        else:
            ok("死资产仍然是死的：`tree_small` 代码里**零命中**（非注释行）⇒ decor/tree_small 继续不上门"
               "（本门每次重核，不是抄结论）")

    # ── 1b. 已删除的三张必须留在删除态（I2；见 DELETED 抬头：这条替换了原来那条输入已消失的棘轮）──
    del_errs = check_deleted(recs, gd_srcs)
    for e in del_errs:
        bad("%s\n"
            "        这三个名字是 2026-07-30 **蓄意删掉**的（docs/09 §1.1：消费者早在 841d4c4 就被当作\n"
            "        「比例失调」的头号成因拆掉，剩下两张还是图集断口条带）。要复活得先解决尺度问题，\n"
            "        再走「新素材必须显式进 GATED」那条路 —— 不是把配方行悄悄加回来。" % e)
    if not del_errs:
        ok("删除态自证：building/{house,hut,shop} 三处皆无 —— 出货目录 0 张 / 切图配方 0 条 / `.gd` 非注释引用 0 处"
           "（棘轮换了输入，不是没了：原来那条查 `building_tex` 调用点，而它的输入已随函数一起删除）")

    # ── 2. 当场重建 + 来源自证（自证①）──────────────────────────────────────
    buildable = sorted(GATED & set(recs))
    if not buildable:
        bad("上门表与配方交集为空 —— 一张都重建不出来")
        print("\n=== ASSET GATE FAIL ❌ ===")
        return 1
    rebuilt, opened = rebuild(recs, buildable)
    lib = os.path.join(ART, "library")
    from_lib = [p for p in opened if _under(lib, p)]
    from_dst = [p for p in opened
                if any(_under(os.path.join(ART, d), p) for d in SHIPPED_DIRS)]
    if not from_lib:
        bad("重建期间一个 library/ 文件都没读 —— 这不是重建")
    elif from_dst:
        bad("重建期间读了 %d 个出货文件（%s）—— 那是抄答案不是重建，判据会退化成 x→x"
            % (len(from_dst), ", ".join(sorted({_rel(p) for p in from_dst}))))
    else:
        ok("重建来源自证：读了 %d 个 library/ CC0 源表、%d 个出货文件 ⇒ 重建独立于出货目录"
           % (len(from_lib), len(from_dst)))

    # ── 3. 判别力自检：**逐张**注入 1 px（自证②）─────────────────────────────
    teeth_ok, teeth_bad = 0, []
    for key in buildable:
        t = rebuilt[key].copy()
        tp = t.load()
        W, H = t.size
        x, y = W // 2, H // 2                # 图心：不论该点实心还是全透明，RGB 取反必然改变元组
        old = tp[x, y]
        tp[x, y] = (old[0] ^ 0xFF, old[1] ^ 0xFF, old[2] ^ 0xFF, old[3])
        n, notes, _ = compare(key, t, rebuilt[key])
        if n == 1 and notes and notes[0].startswith(key + "："):
            teeth_ok += 1
        else:
            teeth_bad.append("%s→%d px/%s" % (key, n, notes[:1]))
    if teeth_ok == len(buildable):
        ok("判别力自检（逐张）：%d 张各注入 1 px 扰动 ⇒ 比对器逐张报「1 px 不同」且**指名那一张**"
           "  detected %d/%d" % (len(buildable), teeth_ok, len(buildable)))
    else:
        bad("判别力自检失败 detected %d/%d：%s ⇒ 这道门本身是坏的"
            % (teeth_ok, len(buildable), "; ".join(teeth_bad)))

    # 顺带把 docs/41 §6 的 getbbox 陷阱**量出来**（只打印，绝不判红：
    # `alpha_only` 的默认值随 Pillow 版本走，拿它判红等于让门在别人机器上变红）。
    probe = buildable[0]
    t = rebuilt[probe].copy()
    tp = t.load()
    W, H = t.size
    px, py = W // 2, H // 2
    o = tp[px, py]
    tp[px, py] = (o[0] ^ 0xFF, o[1] ^ 0xFF, o[2] ^ 0xFF, o[3])
    naive = ImageChops.difference(t, rebuilt[probe]).getbbox()
    right = ImageChops.difference(t.convert("RGB"), rebuilt[probe].convert("RGB")).getbbox()
    print("  ℹ  getbbox 陷阱量具（docs/41 §6，只打印不判红）：%s 翻 1 个像素的 RGB ⇒ "
          "getbbox()=%s  /  convert(\"RGB\") 后 =%s  （Pillow %s）"
          % (probe, naive, right, PIL.__version__))
    if naive is None:
        print("     ⚠  本机 getbbox() 把它判成「完全相同」—— **本门没有用 getbbox()**，"
              "比的是 load() 出来的 RGBA 元组")

    # ── 4. 逐像素比对（硬判据）+ 容器字节（软判据）───────────────────────────
    files_cmp = px_cmp = bytes_cmp = 0
    same = 0
    reenc_same = reenc_cmp = 0
    details = []
    shipped_imgs = {}
    for key in buildable:
        d, n = key.split("/", 1)
        path = os.path.join(ART, d, n + ".png")
        if not os.path.isfile(path):
            bad("上门的出货文件缺失：%s" % _rel(path))
            continue
        with Image.open(path) as raw:      # with：Windows 上不留悬挂句柄
            mode = raw.mode
            shipped = raw.convert("RGBA")
        shipped_imgs[key] = shipped
        ndiff, notes, npx = compare(key, shipped, rebuilt[key])
        files_cmp += 1
        px_cmp += npx
        bytes_cmp += npx * 4
        if ndiff == 0:
            same += 1
        else:
            bad("%s：%d px 与当场重建不同" % (key, max(ndiff, 0)))
            for ln in notes:
                print("        · %s" % ln)
        if mode != "RGBA":
            print("     ⚠  %s：PNG 模式是 %s（已按 RGBA 解码后比对）" % (key, mode))
        buf = io.BytesIO()                 # 软判据：容器字节（只打印，理由见模块 docstring）
        rebuilt[key].save(buf, format="PNG")
        with open(path, "rb") as f:
            disk = f.read()
        reenc_cmp += 1
        if buf.getvalue() == disk:
            reenc_same += 1
        details.append((key, ndiff, npx, len(disk), buf.getvalue() == disk))

    # ── 5. 扫过量自证（自证③）──────────────────────────────────────────────
    if files_cmp == 0 or px_cmp == 0 or bytes_cmp == 0:
        bad("扫过量为 0（图 %d / 像素 %d / 字节 %d）—— 一张都没比就打绿是假门"
            % (files_cmp, px_cmp, bytes_cmp))
    elif same == files_cmp:
        ok("逐像素比对：%d/%d 张与当场重建**解码后 RGBA 逐像素相同**；共比对 %s 像素 / %s 字节"
           % (same, files_cmp, format(px_cmp, ","), format(bytes_cmp, ",")))
    else:
        print("     （已比对 %s 像素 / %s 字节，%d/%d 张一致）"
              % (format(px_cmp, ","), format(bytes_cmp, ","), same, files_cmp))

    if reenc_cmp:
        print("  ℹ  PNG 容器字节（软判据，**不判红**）：%d/%d 张与本机 Pillow %s 重编码逐字节相同"
              % (reenc_same, reenc_cmp, PIL.__version__))
        if reenc_same != reenc_cmp:
            print("     （预期如此，**理由不是「出货被重新压缩过」**：这一行比的是 Pillow 编出来的字节，"
                  "而出货是容器 ffmpeg 4.4.2 / 本仓自绘编码器写的 —— 三个编码器，字节当然不同。\n"
                  "      J2 实测：把两份配方原样放回容器跑一遍，28/28 逐【字节】相同。"
                  "字节随编码器版本走 ⇒ 拿它判红 = 换台机器就全假红。逐像素 %d/%d 同、逐字节 %d/%d 同。）"
                  % (same, files_cmp, reenc_same, reenc_cmp))

    # ── 5b. 第 2 条性质：上门的 emote 两两必须分得开（I1 新增）────────────────────
    dset = {k: shipped_imgs[k] for k in DISTINCT_SET if k in shipped_imgs}
    if len(dset) < 2:
        bad("两两可分判据拿到 %d 张 emote（<2）—— 一对都没比就打绿是假门" % len(dset))
    else:
        pairs = distinctness(dset)
        src_min = min(p[2] for p in pairs)
        grey_min = min(p[3] for p in pairs)
        under = [p for p in pairs if p[2] < DISTINCT_SRC_FLOOR or p[3] < DISTINCT_GREY_FLOOR]
        # 报最小值时把**并列在最小值上的所有对**一起报（docs/44 §一·六 的教训）
        src_tied = ["%s|%s" % (a.split("/")[1], b.split("/")[1])
                    for a, b, s, g in pairs if s == src_min]
        grey_tied = ["%s|%s" % (a.split("/")[1], b.split("/")[1])
                     for a, b, s, g in pairs if abs(g - grey_min) < 1e-9]
        if under:
            bad("有 %d 对 emote 分不开（地板 源≥%d / 28px灰度≥%.1f）：\n%s"
                % (len(under), DISTINCT_SRC_FLOOR, DISTINCT_GREY_FLOOR,
                   "\n".join("        · %s vs %s  源=%d  28px灰度=%.2f"
                             % (a, b, s, g) for a, b, s, g in under[:8])))
        else:
            ok("两两可分：%d 张 emote 的 %d 对全部过地板"
               "（源 min=%d ≥ %d，余量 %.2fx；28px 灰度 min=%.2f ≥ %.1f，余量 %.2fx）"
               % (len(dset), len(pairs), src_min, DISTINCT_SRC_FLOOR,
                  src_min / float(DISTINCT_SRC_FLOOR), grey_min, DISTINCT_GREY_FLOOR,
                  grey_min / DISTINCT_GREY_FLOOR))
            print("     ℹ  并列在最小值上的对 —— 源: %s ／ 28px灰度: %s"
                  % (", ".join(src_tied), ", ".join(grey_tied)))

    # ── 6. 未上门的 7 张：只清点、只 WARN，绝不判红 ───────────────────────────
    miss_ng = [k for k in sorted(NOT_GATED)
               if not os.path.isfile(os.path.join(ART, k.split("/")[0], k.split("/")[1] + ".png"))]
    if miss_ng:
        warn("未上门的 %d 张里有 %d 张出货文件不在了：%s（只报不红 —— 它们不在本门的范围里）"
             % (len(NOT_GATED), len(miss_ng), ", ".join(miss_ng)))
    else:
        print("  ℹ  未上门 %d 张：文件都在，**一个像素都没查**（刻意的，理由逐条见 -v）" % len(NOT_GATED))

    stray = []
    for d in SHIPPED_DIRS:
        dd = os.path.join(ART, d)
        if not os.path.isdir(dd):
            continue
        for f in sorted(os.listdir(dd)):
            if f.lower().endswith(".png") and "%s/%s" % (d, f[:-4]) not in recs:
                stray.append("%s/%s" % (d, f[:-4]))
    if stray:
        warn("出货目录里有 %d 张【任何切图配方都产不出】的 png：%s\n"
             "        只报不红：手绘新素材本来就没有 ffmpeg 配方（H1 判「读不出」的那 11 张就该被重画）。"
             "但它没有来源可查 —— 想让它被守住，得给它一条可重建的配方。" % (len(stray), ", ".join(stray)))

    if verbose:
        print("\n  ── 上门明细（%d 张）──" % len(details))
        print("  %-24s %8s %10s %10s  %s" % ("图", "差异px", "比对px", "磁盘字节", "容器字节相同"))
        for key, ndiff, npx, nb, rs in details:
            print("  %-24s %8d %10s %10s  %s"
                  % (key, max(ndiff, 0), format(npx, ","), format(nb, ","), rs))
        print("\n  ── 不上门明细（%d 张，逐条理由）──" % len(NOT_GATED))
        for k in sorted(NOT_GATED):
            print("  %-24s %s" % (k, NOT_GATED[k]))

    print()
    if fail == 0:
        print("=== ASSET GATE PASS ✅ ===")
    else:
        print("=== ASSET GATE FAIL ❌ ===")
        print("修法：出货图与配方不符 ⇒ 按 tools/slice_all.py / tools/slice_visual.py 的坐标重切；"
              "若你**蓄意**改了美术，请把改动做进切图配方（或换成一份可重建的新配方），而不是直接改 png。")
    return fail


if __name__ == "__main__":
    sys.exit(main())
