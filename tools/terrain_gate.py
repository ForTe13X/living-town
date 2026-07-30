#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""terrain_gate.py —— 地形资产门（Wave G · G5；docs/49 §七 硬要求 4）。

## 为什么

G1 建 `tools/art_gate.py` 时点了名：它只守 `pro/` 那 10 张角色表，
而仓库里另有 **31 张出货 png**（emote 10 / decor 8 / terrain 5 / obj 5 / building 3）
**一道门都没有** —— 改一个像素、删一张图，CI 从头到尾全绿。

本棒往 `terrain/` 里加了 8 张岸线瓦片（5 → 13 张），正好把这一类补上门。
**形状照抄 `art_gate.py`，不发明第二套**：当场从 `library/` 的 CC0 总表重建 → 逐像素比对。
刻意**不是**"校验和清单对得上"——那种门可以靠更新清单通过，而更新清单正是任何
偷改像素的人下一步会做的事。

## 覆盖到哪 / 没覆盖到哪（明写，别让读者自己猜）

- **守住**：`game/assets/art/terrain/` 全部 13 张。
- **没守**：emote 10 / decor 8 / obj 5 / building 3 —— **共 26 张仍然无门**。
  它们切自 `slice_all.py` / `slice_visual.py` 的另外两组坐标，形状与本文件完全一样，
  照着扩是机械劳动；本棒没做，因为没在真机帧上验过那 26 张，
  **给没眼验过的东西上门 = 把当前状态钉成"正确"**，而本棒的整个由来就是
  "一张从没被人看过一眼的贴图安安静静躺了一个月"。

  > **⚠️ 2026-07-30 更新（H2；`tools/terrain_gate.py` 不归 H2，本次改动只动这段注释，声明式越界）**：
  > 上面那句"共 26 张仍然无门"**已经过期**。H1 把 26 张在真机上逐张眼验（docs/51），
  > H2 据此给其中判为 OK 的 **10 张**上了 `tools/asset_gate.py`（CI 第 2d 步）。
  > 剩下 **16 张仍然无门，而且是刻意的**：11 张判「读不出」、1 张判「需要重切」——先修再守；
  > 另 4 张（`building/{house,hut,shop}` + `decor/tree_small`）判「从不出现」，
  > 给上不了屏的素材上门 = 把死资产钉成"正确"。上面那条理由**没有被推翻，只是终于有了眼验做前提**。

## 三条"这道门自己会不会是假的"的自证（照抄 art_gate.py 的三条，每次跑都做）

1. **重建来源自证**：重建期间把 `PIL.Image.open` 换成探针，记录实际打开了哪些文件。
   要求：命中 `library/` ≥ 1 个，命中出货 `terrain/` **恰好 0 个**。
2. **判别力自检（teeth）**：拿重建结果复制一份、翻 **1** 个像素，喂给**同一个**比对函数，
   要求它报出"恰好 1 px 不同"且指名是哪一张瓦。比对器退化成 `return True` 立刻红。
3. **扫过量自证**：打印实际比对了几张瓦 / 几个像素 / 几个字节，三个数为 0 一律判红。

## 第四条（本门特有）：**两份坐标表必须一致**

`tools/slice_visual.py` 第 12-16 行（ffmpeg 版，容器内跑）与 `tools/slice_shore.py`
的 `LEGACY` 表（Pillow 版）**各写了一份 terrain 切图坐标**。两份漂开的话，
"重建"重建的就不是出货文件真正的来源。所以本门**解析 slice_visual.py 的源码**
把那 5 行的 (col,row) 抠出来和 `LEGACY` 对，不靠注释里的君子协定。

用法:
    python tools/terrain_gate.py            # 门：PASS ⇒ exit 0，FAIL ⇒ exit 1
    python tools/terrain_gate.py -v         # 附每张瓦的逐张明细
"""
import io
import os
import re
import sys

try:
    import PIL
    from PIL import Image
except ImportError:
    sys.exit("❌ terrain gate: 需要 Pillow（pip install pillow）")

try:                                    # Windows 控制台默认 GBK，直接 print 中文/✅ 会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slice_shore as ss                # 重建管线本体

ROOT = ss.ROOT
SHEET = ss.SHEET
DST = ss.DST
SLICE_VISUAL = os.path.join(ROOT, "tools", "slice_visual.py")


def _rel(p):
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:
        return p


def _under(parent, p):
    """p 是否在 parent 目录之内（normcase + sep 前缀；跨盘符不抛异常）。"""
    parent = os.path.normcase(os.path.abspath(parent)).rstrip("\\/") + os.sep
    return os.path.normcase(os.path.abspath(p)).startswith(parent)


def compare(name, shipped, rebuilt, limit=3):
    """出货图 vs 重建图 → (差异像素数, [人话描述...], 比对的像素数)。

    ⚠ 本函数是这道门唯一的"是不是一样"判据 ⇒ 每次运行都被 teeth 自检拿已知不同的一对喂一遍。
    """
    if shipped.size != rebuilt.size:
        return -1, ["%s：尺寸 %s ≠ 重建 %s" % (name, shipped.size, rebuilt.size)], 0
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
                notes.append("%s：(%d,%d)  出货 %s ≠ 重建 %s" % (name, x, y, a, b))
    return ndiff, notes, W * H


def rebuild_all():
    """当场从 CC0 总表重建 13 张瓦，并**同时**记录重建期间打开过哪些文件（自证①）。"""
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
        out = ss.build()
    finally:
        Image.open = orig_open
    return out, opened


def slice_visual_coords():
    """从 slice_visual.py 源码里抠出 terrain 那几行的 (name -> (col,row))。

    只认形如  tile(f"{B}/terrain/<name>.png", <col>, <row>)  的行；多格瓦（带 wt/ht）
    不属于 terrain，出现即忽略。抠不到任何一行 ⇒ 调用方判红（说明格式变了，别静默放行）。
    """
    if not os.path.isfile(SLICE_VISUAL):
        return None
    src = open(SLICE_VISUAL, encoding="utf-8").read()
    pat = re.compile(r'tile\(f"\{B\}/terrain/(\w+)\.png",\s*(\d+),\s*(\d+)\s*\)')
    return {m.group(1): (int(m.group(2)), int(m.group(3))) for m in pat.finditer(src)}


def main():
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    fail = 0

    def ok(m):
        print("  ✅ %s" % m)

    def bad(m):
        nonlocal fail
        print("  ❌ FAIL: %s" % m)
        fail = 1

    print("### terrain gate：出货 terrain/ 必须等于 slice_shore.py 当场从 CC0 总表重建的结果（docs/49 §七）")
    print("  源   %s" % _rel(SHEET))
    print("  出货 %s" % _rel(DST))

    # ── 0. 文件集合 ─────────────────────────────────────────────────────────
    want = set(ss.LEGACY) | set(ss.SHORE)
    if not os.path.isdir(DST):
        bad("出货目录不存在：%s" % _rel(DST))
        print("\n=== TERRAIN GATE FAIL ❌ ===")
        return 1
    have = {f[:-4] for f in os.listdir(DST) if f.lower().endswith(".png")}
    missing, extra = sorted(want - have), sorted(have - want)
    if missing:
        bad("出货目录缺 %d 张：%s" % (len(missing), ", ".join(missing)))
    if extra:
        bad("出货目录多出 %d 张【重建管线生成不出来】的瓦：%s" % (len(extra), ", ".join(extra)))
    if not missing and not extra:
        ok("文件集合：%d 张 png，与 slice_shore 的 LEGACY+SHORE 逐名相同（0 缺失 / 0 多余）" % len(have))

    # ── 1. 当场重建 + 来源自证 ──────────────────────────────────────────────
    rebuilt, opened = rebuild_all()
    from_sheet = [p for p in opened if os.path.normcase(p) == os.path.normcase(os.path.abspath(SHEET))]
    from_dst = [p for p in opened if _under(DST, p)]
    if not from_sheet:
        bad("重建期间没读 CC0 总表 —— 这不是重建")
    elif from_dst:
        bad("重建期间读了 %d 个出货文件（%s）—— 那是抄答案不是重建，判据会退化成 x→x"
            % (len(from_dst), ", ".join(sorted({_rel(p) for p in from_dst}))))
    else:
        ok("重建来源自证：读了 %d 次 CC0 总表、%d 个出货文件 ⇒ 重建独立于出货目录"
           % (len(from_sheet), len(from_dst)))

    # ── 2. 判别力自检（teeth）──────────────────────────────────────────────
    probe = sorted(ss.SHORE)[0]                 # 挑一张岸线瓦（本棒新加的那一类）
    tampered = rebuilt[probe].copy()
    tp = tampered.load()
    tx, ty = 8, 8                               # 瓦心：不论该点实心还是透明，RGB 取反必然改变元组
    old = tp[tx, ty]
    tp[tx, ty] = (old[0] ^ 0xFF, old[1] ^ 0xFF, old[2] ^ 0xFF, old[3])
    tn, tnotes, _ = compare(probe, tampered, rebuilt[probe])
    if tn == 1 and tnotes and probe in tnotes[0]:
        ok("判别力自检：向 %s 注入 1 px 扰动 ⇒ 比对器报「1 px 不同」且指名该瓦（比对器有牙）" % probe)
    else:
        bad("判别力自检失败：注入 1 px 扰动，比对器报 %d px / notes=%s ⇒ 这道门本身是坏的" % (tn, tnotes))

    # ── 3. 两份坐标表一致（本门特有）────────────────────────────────────────
    sv = slice_visual_coords()
    if sv is None:
        bad("找不到 %s —— 无法核对两份切图坐标" % _rel(SLICE_VISUAL))
    elif not sv:
        bad("从 %s 里一行 terrain 切图都没解析到 —— 格式变了，不能静默放行" % _rel(SLICE_VISUAL))
    else:
        drift = {k: (ss.LEGACY.get(k), v) for k, v in sv.items() if ss.LEGACY.get(k) != v}
        miss = sorted(set(ss.LEGACY) - set(sv))
        if drift:
            bad("两份切图坐标漂开了：%s（slice_shore.LEGACY vs slice_visual.py）"
                % ", ".join("%s %s≠%s" % (k, a, b) for k, (a, b) in sorted(drift.items())))
        elif miss:
            bad("slice_visual.py 里没有这几张的切图行：%s" % ", ".join(miss))
        else:
            ok("坐标表一致：%d 张 legacy 瓦在 slice_shore.LEGACY 与 slice_visual.py 里逐个相同" % len(sv))

    # ── 4. 逐像素比对 ───────────────────────────────────────────────────────
    tiles_cmp = px_cmp = bytes_cmp = 0
    same = 0
    reenc_same = reenc_cmp = 0
    details = []
    for s in sorted(want & have):
        path = os.path.join(DST, s + ".png")
        with Image.open(path) as raw:           # with：Windows 上不留悬挂句柄
            mode = raw.mode
            shipped = raw.convert("RGBA")
        n, notes, npx = compare(s, shipped, rebuilt[s])
        tiles_cmp += 1
        px_cmp += npx
        bytes_cmp += npx * 4
        if n == 0:
            same += 1
        else:
            bad("%s：%d px 与重建不同" % (s, max(n, 0)))
            for ln in notes:
                print("        · %s" % ln)
        if mode != "RGBA":
            print("     ⚠  %s：PNG 模式是 %s（已按 RGBA 解码后比对）" % (s, mode))
        buf = io.BytesIO()                      # 软判据：容器字节（理由同 art_gate 模块 docstring）
        rebuilt[s].save(buf, format="PNG")
        with open(path, "rb") as f:
            disk = f.read()
        reenc_cmp += 1
        if buf.getvalue() == disk:
            reenc_same += 1
        details.append((s, n, npx, len(disk), buf.getvalue() == disk))

    # ── 5. 扫过量自证 ───────────────────────────────────────────────────────
    if tiles_cmp == 0 or px_cmp == 0 or bytes_cmp == 0:
        bad("扫过量为 0（瓦 %d / 像素 %d / 字节 %d）—— 一张都没比就打绿是假门"
            % (tiles_cmp, px_cmp, bytes_cmp))
    elif same == tiles_cmp:
        ok("逐字节比对：%d/%d 张与当场重建**逐像素相同**；共比对 %s 像素 / %s 字节"
           % (same, tiles_cmp, format(px_cmp, ","), format(bytes_cmp, ",")))
    else:
        print("     （已比对 %s 像素 / %s 字节，%d/%d 张一致）"
              % (format(px_cmp, ","), format(bytes_cmp, ","), same, tiles_cmp))

    if reenc_cmp:
        tag = "✅" if reenc_same == reenc_cmp else "⚠ "
        print("  %s PNG 容器字节（软判据，不判红）：%d/%d 张与本机 Pillow %s 重编码逐字节相同"
              % (tag, reenc_same, reenc_cmp, PIL.__version__))

    if verbose:
        print("\n  ── 逐张明细 ──")
        print("  %-16s %8s %10s %10s  %s" % ("瓦", "差异px", "比对px", "磁盘字节", "容器字节相同"))
        for s, n, npx, nb, rs in details:
            print("  %-16s %8d %10s %10s  %s" % (s, max(n, 0), format(npx, ","), format(nb, ","), rs))

    print()
    if fail == 0:
        print("=== TERRAIN GATE PASS ✅ ===")
    else:
        print("=== TERRAIN GATE FAIL ❌ ===")
        print("修法：`python tools/slice_shore.py` 重新生成岸线瓦；"
              "若你**蓄意**改了地形美术，请把改动做进切图坐标/键控规则里，而不是直接改 png。")
    return fail


if __name__ == "__main__":
    sys.exit(main())
