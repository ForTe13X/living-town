#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""art_gate.py — 美术资产门（Wave G · G1；docs/49 §一）。

## 为什么这道门必须存在

Wave F 收尾时 grep 过 `tools/ci.sh`：里面**没有任何一处**提到 assets / art / palette / coif / deprop
（唯一的字面命中是 `fresh-rest**art**` 里的三个字母）。
⇒ `game/assets/art/pro/` 那十张出货角色表是**这个仓库唯一一类"改了没有任何门会响"的资产**，
而它同时是玩家**唯一直接看得见**的东西。删一张、覆盖一张、手改一个像素——CI 从头到尾全绿。

## 它守的性质（只有一条）

**出货的 `pro/*.png` 必须等于 `coif_characters.py` 现在能重建出来的东西。**

刻意**不是**"有个校验和清单对得上"：那种门可以靠更新清单文件通过，而更新清单正是**任何**
偷改像素的人下一步会做的事。这里是**当场从 `library/` 重新生成、再逐字节比对**——
想让它变绿只有两条路：把 `pro/` 改回来，或者把生成脚本改成真的会生成那个东西。

## 三条"这道门自己会不会是假的"的自证（每次跑都做，不是注释里的承诺）

1. **重建来源自证**：重建期间把 `PIL.Image.open` 换成探针，记录**实际打开了哪些文件**。
   要求：命中 `library/` ≥ 1 个，命中 `pro/` **恰好 0 个**。
   这一条不是洁癖——`coif_characters.py` :444 亲口记过它翻过的车：第一版基线是**读 `pro/` 里的文件**算的，
   于是写完文件再跑，整张对照表静默退化成 `x → x`。**读了出货目录的"重建"不是重建，是抄答案。**
2. **判别力自检（teeth）**：拿重建结果自己复制一份、翻**一个**像素，喂给**同一个**比对函数，
   要求它报出"恰好 1 px 不同"且**指名是哪一张表**。比对器一旦退化成 `return True`，这一条立刻红。
3. **扫过量自证**：打印**实际比对了几张表 / 几个像素 / 几个字节**，且这三个数为 0 时**一律判红**。
   "数字是 0 却打 ✅"是本仓库反复出现的病（docs/41 §2 第三个盲区）。

## 硬判据 vs 软判据（为什么 PNG 容器字节只是 WARN）

- **硬**：解码后的 RGBA 像素字节必须逐字节相同。这是**真正会进 Godot 纹理、真正上屏**的那份数据，
  且 PNG 解码是确定的 ⇒ 换机器不会自己变色。
- **软**：把重建结果用**本机 Pillow** 重新编码出来的 **PNG 容器字节**。实测（Pillow 11.3.0 / Python 3.12）
  十张全部逐字节相同，所以这里照样打印结论；但它取决于 zlib/Pillow 版本，
  **不作为失败条件**——`tools/visual_gate.sh` 抬头写过的那条：
  「一道在别人机器上因环境变红的门比没有门更坏，它训练所有人忽略红色」。
  容器变了而像素没变 = 屏幕上什么都没变 ⇒ 不该红，但该说出来。

## 明确不做

**不查描边规则**（"新加的像素必须自带描边"那 132 个裸边像素）——那是 G2 的活，
它属于 `coif_characters.py` 的断言 C。本门只守"出货 == 可重建"，两边同时改会撞。

用法：
    python tools/art_gate.py            # 门：PASS ⇒ exit 0，FAIL ⇒ exit 1
    python tools/art_gate.py -v         # 附每张表的逐张明细
"""
import io
import os
import sys

try:
    import PIL
    from PIL import Image
except ImportError:
    sys.exit("❌ art gate: 需要 Pillow（pip install pillow）—— 重建管线依赖它，装不上就没有这道门")

try:                                    # Windows 控制台默认 GBK，直接 print 中文/✅ 会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coif_characters as cc            # 重建管线本体（G2 的行；本门只读它，绝不改它）
import deprop_characters as dp

ROOT = dp.ROOT
SRC = dp.SRC                            # game/assets/art/library/puny-characters/Puny-Characters
DST = dp.DST                            # game/assets/art/pro
BASE = dp.BASE


def _rel(p):
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:
        return p


def _under(parent, p):
    """p 是否在 parent 目录之内。用 normcase + sep 前缀，跨盘符不抛异常（commonpath 会抛）。"""
    parent = os.path.normcase(os.path.abspath(parent)).rstrip("\\/") + os.sep
    return os.path.normcase(os.path.abspath(p)).startswith(parent)


def compare(name, shipped, rebuilt, limit=3):
    """出货图 vs 重建图。返回 (差异像素数, 其中落在可达帧的像素数, [人话描述, ...], 比对的像素数)。

    ⚠️ 这个函数是本门唯一的"是不是一样"判据，因此它每次运行都会被 teeth 自检拿已知不同的一对喂一遍。

    例子**优先取可达帧**（`ROWS_USED × COLS_USED` 那 12 帧）。原因是实测出来的：
    第一版按行序取前三个差异，负对照①报出来的头三行全在 `col=12` 这种**渲染器到不了**的帧上，
    读者第一眼会以为"这不要紧"。整张表都出货，所以整张表都判；但**例子必须先给人看得见的那一半**。
    """
    if shipped.size != rebuilt.size:
        return -1, -1, ["%s：尺寸 %s ≠ 重建 %s" % (name, shipped.size, rebuilt.size)], 0
    W, H = shipped.size
    sp, rp = shipped.load(), rebuilt.load()
    ndiff = nreach = 0
    hot, cold = [], []                      # 可达帧的例子 / 不可达帧的例子
    for y in range(H):
        row = y // cc.FRAME
        row_used = row in cc.ROWS_USED
        for x in range(W):
            a, b = sp[x, y], rp[x, y]
            if a == b:
                continue
            ndiff += 1
            col = x // cc.FRAME
            used = row_used and col in cc.COLS_USED
            if used:
                nreach += 1
            bucket = hot if used else cold
            if len(bucket) < limit:
                bucket.append("%s：表内(%d,%d) = frame(col=%d,row=%d %s) 帧内(%d,%d)  出货 %s ≠ 重建 %s"
                              % (name, x, y, col, row, "可达帧" if used else "不可达帧",
                                 x % cc.FRAME, y % cc.FRAME, a, b))
    return ndiff, nreach, (hot + cold)[:limit], W * H


def rebuild_all():
    """当场从 library/ 重建十张表，并**同时**记录重建期间打开过哪些文件（自证①）。"""
    opened = []
    orig_open = Image.open

    def spy(fp, *a, **k):
        try:
            opened.append(os.path.abspath(os.fspath(fp)))
        except Exception:
            pass
        return orig_open(fp, *a, **k)

    Image.open = spy
    try:
        base_img = dp.load(BASE)
        out = {}
        for s in sorted(cc.STYLES):
            out[s] = cc.build(s, base_img)[0]
    finally:
        Image.open = orig_open
    return out, opened


def main():
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    fail = 0

    def ok(m):
        print("  ✅ %s" % m)

    def bad(m):
        nonlocal fail
        print("  ❌ FAIL: %s" % m)
        fail = 1

    print("### art gate：出货 pro/ 必须等于 coif_characters.py 当场重建的结果（docs/49 §一）")
    print("  源   %s" % _rel(SRC))
    print("  出货 %s" % _rel(DST))

    # ── 0. 文件集合 ─────────────────────────────────────────────────────────
    want = set(cc.STYLES)
    if not os.path.isdir(DST):
        bad("出货目录不存在：%s" % _rel(DST))
        print("\n=== ART GATE FAIL ❌ ===")
        return 1
    have = {f[:-4] for f in os.listdir(DST) if f.lower().endswith(".png")}
    missing, extra = sorted(want - have), sorted(have - want)
    if missing:
        bad("出货目录缺 %d 张：%s" % (len(missing), ", ".join(missing)))
    if extra:
        bad("出货目录多出 %d 张【重建管线生成不出来】的表：%s"
            % (len(extra), ", ".join(extra)))
    if not missing and not extra:
        ok("文件集合：%d 张 png，与 coif_characters.STYLES 逐名相同（0 缺失 / 0 多余）" % len(have))

    # ── 1. 当场重建 + 来源自证 ──────────────────────────────────────────────
    rebuilt, opened = rebuild_all()
    from_src = [p for p in opened if _under(SRC, p)]
    from_dst = [p for p in opened if _under(DST, p)]
    if not from_src:
        bad("重建期间一个 library/ 文件都没读 —— 这不是重建")
    elif from_dst:
        bad("重建期间读了 %d 个出货文件（%s）—— 那是抄答案不是重建，判据会退化成 x→x"
            % (len(from_dst), ", ".join(sorted({_rel(p) for p in from_dst}))))
    else:
        ok("重建来源自证：读了 %d 个 library/ 文件、%d 个 pro/ 文件 ⇒ 重建独立于出货目录"
           % (len(from_src), len(from_dst)))

    # ── 2. 判别力自检（teeth）：已知不同的一对，比对器必须报得出来 ──────────
    probe_sheet = sorted(rebuilt)[0]
    tampered = rebuilt[probe_sheet].copy()
    tp = tampered.load()
    # 落点选在**可达帧**的头顶（12 帧里的第一帧）：扰动必须落在玩家看得见的那一半，
    # 否则这条自检只证明"比对器能看见不可达帧"。RGB 取反 ⇒ 不论该点是实心还是全透明，
    # 元组必然改变 ⇒ 差异恒为 1 px，与 G2 以后怎么改模板无关。
    tx, ty = cc.COLS_USED[0] * cc.FRAME + 13, cc.ROWS_USED[0] * cc.FRAME + 10
    old = tp[tx, ty]
    tp[tx, ty] = (old[0] ^ 0xFF, old[1] ^ 0xFF, old[2] ^ 0xFF, old[3])
    tn, tnr, tnotes, _ = compare(probe_sheet, tampered, rebuilt[probe_sheet])
    if tn == 1 and tnr == 1 and tnotes and probe_sheet in tnotes[0]:
        ok("判别力自检：向 %s 的可达帧注入 1 px 扰动 ⇒ 比对器报「1 px 不同（可达帧 1）」且指名该表（比对器有牙）"
           % probe_sheet)
    else:
        bad("判别力自检失败：注入 1 px 扰动，比对器报 %d px（可达 %d）/ notes=%s ⇒ 这道门本身是坏的"
            % (tn, tnr, tnotes))

    # ── 3. 逐字节比对 ───────────────────────────────────────────────────────
    sheets_cmp = px_cmp = bytes_cmp = 0
    same = 0
    reenc_same = reenc_cmp = 0
    details = []
    for s in sorted(want & have):
        path = os.path.join(DST, s + ".png")
        with Image.open(path) as raw:          # with：Windows 上不留悬挂句柄（NC 脚本要覆写这些文件）
            mode = raw.mode
            shipped = raw.convert("RGBA")
        n, nreach, notes, npx = compare(s, shipped, rebuilt[s])
        sheets_cmp += 1
        px_cmp += npx
        bytes_cmp += npx * 4
        if n == 0:
            same += 1
        else:
            bad("%s：%d px 与重建不同（其中 %d px 落在 12 个可达帧上 = 玩家真的会看见）"
                % (s, max(n, 0), max(nreach, 0)))
            for ln in notes:
                print("        · %s" % ln)
        if mode != "RGBA":
            print("     ⚠  %s：PNG 模式是 %s（已按 RGBA 解码后比对）" % (s, mode))
        # 软判据：容器字节
        buf = io.BytesIO()
        rebuilt[s].save(buf, format="PNG")
        with open(path, "rb") as f:
            disk = f.read()
        reenc_cmp += 1
        if buf.getvalue() == disk:
            reenc_same += 1
        details.append((s, n, nreach, npx, len(disk), buf.getvalue() == disk))

    # ── 4. 扫过量自证：三个数为 0 一律判红 ─────────────────────────────────
    if sheets_cmp == 0 or px_cmp == 0 or bytes_cmp == 0:
        bad("扫过量为 0（表 %d / 像素 %d / 字节 %d）—— 一张都没比就打绿是假门"
            % (sheets_cmp, px_cmp, bytes_cmp))
    elif same == sheets_cmp:
        ok("逐字节比对：%d/%d 张与当场重建**逐像素相同**；共比对 %s 像素 / %s 字节（每张 %dx%d x RGBA）"
           % (same, sheets_cmp, format(px_cmp, ","), format(bytes_cmp, ","),
              rebuilt[sorted(rebuilt)[0]].size[0], rebuilt[sorted(rebuilt)[0]].size[1]))
    else:
        print("     （已比对 %s 像素 / %s 字节，%d/%d 张一致）"
              % (format(px_cmp, ","), format(bytes_cmp, ","), same, sheets_cmp))

    # 软判据回执（不参与判定，理由见模块 docstring）
    if reenc_cmp:
        tag = "✅" if reenc_same == reenc_cmp else "⚠ "
        print("  %s PNG 容器字节（软判据，不判红）：%d/%d 张与本机 Pillow %s 重编码逐字节相同"
              % (tag, reenc_same, reenc_cmp, PIL.__version__))

    if verbose:
        print("\n  ── 逐张明细 ──")
        print("  %-16s %8s %10s %10s %10s  %s"
              % ("表", "差异px", "其中可达", "比对px", "磁盘字节", "容器字节相同"))
        for s, n, nreach, npx, nb, rs in details:
            print("  %-16s %8d %10d %10s %10s  %s"
                  % (s, max(n, 0), max(nreach, 0), format(npx, ","), format(nb, ","), rs))

    print()
    if fail == 0:
        print("=== ART GATE PASS ✅ ===")
    else:
        print("=== ART GATE FAIL ❌ ===")
        print("修法：`python tools/coif_characters.py` 重新生成出货表；"
              "若你**蓄意**改了美术，请把改动做进 coif_characters.py 的模板里，而不是直接改 png。")
    return fail


if __name__ == "__main__":
    sys.exit(main())
