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

## 它守的性质（只有一条，而且【范围是刻意窄的】）

**H1 在真机上眼验过、判为 OK 的那 10 张出货 png，必须等于两份切图配方现在能重建出来的东西。**

另外 16 张**故意不上门**，这不是偷懒，是本棒的全部要点（docs/50 §〇·2 / docs/51 §三·4）：

> **给没有人眼验过（或已知画错、或根本上不了屏）的美术上门 = 把当前状态钉成"正确"。**
> 池塘那个 bug 正是这样活了一个月。

- **9 张 emote + obj/bath + obj/arcade（11 张）**：H1 判「读不出」——**先修再守**。
  现在钉住 = 把"九张一模一样的白气泡"钉成正确（最近的一对只差 6/400 像素，docs/51 §二·1）。
- **decor/tree_big（1 张）**：H1 判「需要重切」（它是树冠图集碎片，不是一棵树）。
- **building/{house,hut,shop} + decor/tree_small（4 张）**：H1 判「从不出现」。
  `Art.building_tex()` **全仓零调用点**、`tree_small` **不在 `WorldView.DECOR_POOL` 里** ——
  本文件每次运行都**重新核**这两条（见下面自证④），不是抄 docs/51 的结论。
  给不上屏的素材上门 = 把一份死资产钉成"正确"，而它的正确处置是**接线或删掉**，两条路都会动到文件本身。

## 硬判据 vs 软判据（**这一条与 art_gate.py 不一样，别照抄错**）

`art_gate.py` 第 3 节的**小标题**写着"逐字节比对"，但它的代码从来就是**解码后 RGBA 逐像素**
（`compare()` 比的是 `Image.load()` 出来的元组），容器字节只 print。**照抄它的代码是对的，
照抄它的标题会害死人**——docs/50 §二 坑①：H1 在隔离目录重切全部 26 张，实测
**逐像素相同 26/26、逐字节相同 0/26**（出货那批当年被重新编码压缩过）。真拿字节判红 ⇒ 干净树 26/26 假红。

- **硬**：解码后的 RGBA 逐像素。这是真正进 Godot 纹理、真正上屏的那份数据。
- **软**：本机 Pillow 重编码出来的 PNG 容器字节。**只打印，永不判红**（实测本门这 10 张 0/10 相同）。

## 四条自证（每次跑都做，不是注释里的承诺）

1. **重建来源自证**：重建期间把 `PIL.Image.open` 换成探针。要求命中 `library/` ≥1、命中出货目录**恰好 0**。
2. **判别力自检（teeth）**：**逐张**——对**每一张**上门的图各注入 1 个像素，要求比对器报"恰好 1 px"
   且**指名是这一张**。打印 `detected X/X`。
   （art_gate/terrain_gate 只探 1 张 ⇒ 那测的是 recall 不是 coverage，docs/41 §2.5 外审的原话。）
3. **扫过量自证**：打印实际比对了几张 / 几个像素 / 几个字节，三个数为 0 一律判红。
4. **本门特有：范围自证（scoping）**。这道门最容易出的错不是判错，是**守错东西**，所以范围本身要机检：
   - 配方产出的每一张都必须落进**三张表之一**（`GATED` / `NOT_GATED` / `ELSEWHERE`），
     少一张就红。新资产必须有人**显式**决定守不守 —— 默认放行正是本波要拦的那个病。
   - `ELSEWHERE`（terrain 那 5 张归 `terrain_gate.py`）不是写死的转告：本门去核
     `slice_shore.LEGACY|SHORE` 里**真的还有它们**，没有就红。
   - **上门的每一张都必须在代码里可达**（decor 在 `DECOR_POOL`／obj 在 `OBJ_SLOT_BY_TYPE`／
     emote 在 `_emote_key` 的 return 行），从 `game/scripts/*.gd` 源码解析，解析到 0 条即判红。
   - **"从不出现"那 4 张必须仍然不可达**（`building_tex` 零调用 + `tree_small` 代码里零命中）。
     哪天有人把它们接上线，这条会红——**那正是该重新眼验、重新决定守不守的时刻**（棘轮，同 H3 的别名预算）。

## 明确不做

- **不查这 10 张画得好不好**。门只守"出货 == 配方"，"配方对不对"只有人眼能判（H1 的活）。
- **不查别名**（一张 bench.png 服务五种物件）——那是 H3 的 `OBJ_SLOT_ALIAS_BUDGET`。
- **不对 16 张未上门的图判红**（缺失/多余只 WARN），理由见上。

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
SHIPPED_DIRS = ("emote", "decor", "obj", "building")

# ── 上门的 10 张（docs/51 §三·4 的表；判据是 H1 的真机眼验，不是本文件的推断）───────────
GATED = {
    "decor/bush", "decor/flower_red", "decor/flower_yellow",
    "decor/rock", "decor/stump", "decor/mushroom",
    "obj/bench", "obj/counter", "obj/desk",
    "emote/confront",
}

# ── 不上门的 16 张，逐条写明理由。**这张表和上面那张必须并起来盖住整份配方**（自证④）────
NOT_GATED = {
    "emote/greet": "读不出：与另外 8 张同为白气泡，最近一对差 6/400 px（docs/51 §二·1）—— 先重画再守",
    "emote/gossip": "读不出：同上",
    "emote/give": "读不出：同上",
    "emote/invite": "读不出：同上",
    "emote/meet_fulfilled": "读不出：同上",
    "emote/meet_broken": "读不出：同上",
    "emote/conflict": "读不出：同上",
    "emote/apologize_ok": "读不出：同上",
    "emote/apologize_no": "读不出：同上",
    "obj/bath": "读不出：真机读作「木箱压在石槽上」（docs/51 §一 obj 表）—— 先重画再守",
    "obj/arcade": "读不出：真机读作「木牌/告示柱」，而广场 3 格外就是真告示板 —— 先重画再守",
    "decor/tree_big": "需要重切：它是 2x2 树冠【图集碎片】不是一棵树，156 格平铺成壁纸（docs/51 §二·3）",
    "decor/tree_small": "从不出现：不在 WorldView.DECOR_POOL 里（本门自证④每次重核）—— 该接线或删掉，不是该钉住",
    "building/house": "从不出现：Art.building_tex() 全仓零调用点（本门自证④每次重核）",
    "building/hut": "从不出现：同上",
    "building/shop": "从不出现：同上",
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
            try:
                exec(compile(src, path, "exec"), {"__name__": "__main__", "__file__": path})
            except SystemExit:
                pass
    finally:
        sys.stdout = hold
        subprocess.run, os.makedirs = orig_run, orig_makedirs
    return recs, bad


def rebuild(recs, keys):
    """按配方当场重建，并记录重建期间打开过哪些文件（自证①）。返回 ({key: RGBA Image}, opened)。"""
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
    # ⚠ 这样解析**漏掉**透传分支 `_: return t` 能到达的 greet/give/gossip/invite ——
    #    它们的可达性来自 Sim 的事件类型，不是字面量。今天只有 confront 上门，不受影响；
    #    将来要给那四张上门，得先给这里补一条"从 Sim 的事件类型取"的解析，不能直接塞进 GATED。
    ek = re.search(r"func\s+_emote_key\(.*?\n(.*?)(?=\n(?:func |## ))", wv, re.S)
    emote_live = set()
    for ln in (ek.group(1) if ek else "").splitlines():
        if "return" in ln:
            emote_live |= set(re.findall(r'"([^"]+)"', ln))
    if not emote_live:
        errs.append("从 WorldView.gd 的 _emote_key() 里一个 emote 键都没解析到 —— 不能静默放行")

    # 「从不出现」的两条判据（H1 §一★ 的原话，这里每次重跑）
    bt_calls = []
    for p, s in joined.items():
        for i, ln in enumerate(s.splitlines(), 1):
            if "building_tex" in ln and not re.match(r"\s*func\s+building_tex", ln):
                bt_calls.append("%s:%d" % (_rel(p), i))
    ts_hits = []
    for p, s in joined.items():
        for i, ln in enumerate(s.splitlines(), 1):
            if "tree_small" in ln and not ln.lstrip().startswith("#"):
                ts_hits.append("%s:%d" % (_rel(p), i))

    return {"decor": decor_live, "obj": obj_live, "emote": emote_live,
            "building_tex_calls": bt_calls, "tree_small_code_hits": ts_hits}, errs


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

    print("### asset gate：H1 眼验判为 OK 的 10 张出货 png 必须等于切图配方当场重建的结果（docs/50 §二 / docs/51）")
    print("  配方 %s + %s" % (_rel(SLICERS[0]), _rel(SLICERS[1])))
    print("  出货 %s/{%s}" % (_rel(ART), ",".join(SHIPPED_DIRS)))

    # ── 0. 采集配方 ─────────────────────────────────────────────────────────
    recs, harvest_bad = harvest_recipes()
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

    facts, rerrs = reachability(_gd_sources())
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
            ok("可达性：上门的 10 张逐个在代码里可达"
               "（decor∈DECOR_POOL %d 项 / obj∈OBJ_SLOT_BY_TYPE %d 槽 / emote∈_emote_key %d 键）"
               % (len(facts["decor"]), len(facts["obj"]), len(facts["emote"])))

        bt, ts = facts["building_tex_calls"], facts["tree_small_code_hits"]
        if bt or ts:
            bad("「从不出现」那 4 张不再是死的了：building_tex 调用点 %s；tree_small 代码命中 %s\n"
                "        这不是坏事，是**该重新眼验、重新决定守不守**的时刻（docs/50 §八：正确处置是接线或删掉）。\n"
                "        处置：眼验后把它们从 NOT_GATED 挪进 GATED，或明确删掉这几张 png 与配方行。"
                % (bt or "0", ts or "0"))
        else:
            ok("死资产仍然是死的：`building_tex` 全仓 .gd **零调用点**、`tree_small` 代码里**零命中**"
               " ⇒ building/{house,hut,shop} + decor/tree_small 这 4 张继续不上门（本门每次重核，不是抄结论）")

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
    for key in buildable:
        d, n = key.split("/", 1)
        path = os.path.join(ART, d, n + ".png")
        if not os.path.isfile(path):
            bad("上门的出货文件缺失：%s" % _rel(path))
            continue
        with Image.open(path) as raw:      # with：Windows 上不留悬挂句柄
            mode = raw.mode
            shipped = raw.convert("RGBA")
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
            print("     （预期如此：出货这批当年被重新编码压缩过 —— 逐像素 %d/%d 同、逐字节 %d/%d 同。"
                  "拿字节判红 = 干净树全假红，docs/50 §二 坑①）" % (same, files_cmp, reenc_same, reenc_cmp))

    # ── 6. 未上门的 16 张：只清点、只 WARN，绝不判红 ──────────────────────────
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
