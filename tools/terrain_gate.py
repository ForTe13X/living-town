#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""terrain_gate.py —— 地形资产门（Wave G · G5；AV2/Lane V 改为 **hybrid**）。

## 这道门原来守什么（G5，2026-07）

出货 `terrain/` 的 **13 张**瓦必须等于 `slice_shore.py` 当场从 CC0 总表重建的结果，
逐像素比对。刻意**不是**"校验和清单对得上"——那种门可以靠更新清单通过，而更新清单正是任何
偷改像素的人下一步会做的事。**当场重建 + 逐字节比**是这道门当时的骨架。

## 为什么 AV2 必须把它改成 hybrid（诚实地记下这次退让）

AV2（Lane V）把 5 张**原样裁切的** CC0 瓦（`slice_shore.LEGACY`：grass_a / grass_b /
grass_flowers / dirt / water）换成了从 `docs/media/references/ref_terrain_v1_stardew.png`
**降采样生成**的暖色瓦（`tools/slice_terrain_ref.py`）。R4（不许生成图出货）对本切片 **WAIVED**。
⇒ 这 5 张**再也无法从任何 CC0 总表重建** ⇒ 原来的"当场重建 + 逐像素比"对它们**结构上失效**。

**hybrid 的两半**：
  · **8 张 CC0 岸线自动贴图**（`slice_shore.SHORE`：water_{n,s,e,w,ne,nw,se,sw}）—— **一个字没改**，
    仍然当场从 CC0 总表重建 + 逐像素比（连同它的来源自证与 teeth），和 G5 完全一样。
  · **5 张生成瓦**（`slice_shore.LEGACY`）—— 改为 **hash-pin**：比对**解码后 RGBA 的 sha256**
    与一份眼验过的清单 `tools/terrain_hashes.json`。**用解码 RGBA 而不是容器字节**：容器字节随
    zlib/Pillow 版本漂，解码像素不漂（与 2b/2c/2d 的硬判据同源）。

## ⚠️ 诚实边界：hash-pin 就是 G5 当初点名要避开的那种"校验和清单"

G5 抬头原话：**校验和清单"可以靠更新清单通过，而更新清单正是偷改像素的人下一步会做的事"。**
把 5 张生成瓦换成 hash-pin，等于对这 5 张**主动接受了这条弱点**——没有 CC0 源可重建，
就没有第二份独立真相能当场比。**唯一诚实的缓解是【眼验棘轮】**（R4 waived 下的守法）：
  · 清单**只能由人**跑 `python tools/terrain_gate.py --rebless` 重烘，**CI 永不自动重烘**；
  · 且**必须**在（a）Read 眼验每张 16×16 瓦、(b) 录一帧真机整镇图之后才重烘
    （AV2 的证据：docs/media/av2/after_town_day.png + docker 视觉门 POND/SEASON/DAYNIGHT 全 PASS）；
  · 每次重烘往 `_meta.rebless_history` 追一条【为什么】。
这**不能**挡"重烘时把一张偷改的瓦一起钉进去"——那一层只有人眼在守。写在这里，不藏着。

## 自证（G5 三条照旧；本门把它们按两半各自保留，缺哪条都判红）

1. **重建来源自证（SHORE 半）**：重建期间探针记录打开过哪些文件。命中 CC0 总表 ≥1、命中出货 `terrain/` **恰好 0**。
2. **判别力自检 teeth（两半各一条）**：
   · SHORE：拿重建结果复制一份、翻 1 px，喂给**同一个 compare()**，要求报"恰好 1 px 不同"且指名。
   · LEGACY：拿一张出货生成瓦复制一份、翻 1 px，重算 sha256，要求它**不等于**该瓦钉子。
     （比对退化成 `return True` / 常量 hash 立刻红。）
3. **扫过量自证**：SHORE 半打印比对了几瓦/几像素/几字节；LEGACY 半打印 hash 了几瓦/几像素/几字节；
   任一半的三个数为 0 一律判红。
+ **文件集合**：出货目录恰好 = LEGACY ∪ SHORE（0 缺失 / 0 多余）。

## ★ 丢掉的那条自证（大声说明，别让它悄悄消失）

G5 有**第 4 条**：核 `slice_visual.py` 与 `slice_shore.LEGACY` 两份**切图坐标**逐个一致。
生成瓦**没有切图坐标**（它们来自 `slice_terrain_ref.py` 的 band + 降采样，不是 tileset 的 (col,row)）
⇒ 这条自证对 5 张生成瓦**结构上不再适用，本棒删掉了它**。代价：`slice_visual.py` 里那 5 行
terrain 切图坐标（现在只被 `slice_shore.build()` 用来取【岸线键控的草地调色板】）与 `LEGACY`
之间**不再有门核对一致性**。岸线半的重建-比对会间接兜住"草地调色板漂了"（岸瓦会比出不同），
但两份坐标表本身的漂移**不再有专门判据**。这是本棒真实的判别力损失。

用法:
    python tools/terrain_gate.py            # 门：PASS ⇒ exit 0，FAIL ⇒ exit 1
    python tools/terrain_gate.py -v         # 附每张瓦的逐张明细
    python tools/terrain_gate.py --rebless ["原因"]   # ⚠️人工：眼验+录真机帧后重烘 5 张生成瓦的清单
"""
import hashlib
import io
import json
import os
import sys
import time

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
import slice_shore as ss                # 岸线重建管线本体（build() 只读 CC0 总表）

ROOT = ss.ROOT
SHEET = ss.SHEET
DST = ss.DST
GEN = set(ss.LEGACY)                    # 5 张生成瓦（hash-pin）
CC0 = set(ss.SHORE)                     # 8 张 CC0 岸线瓦（重建-比对）
MANIFEST = os.path.join(ROOT, "tools", "terrain_hashes.json")
REF = os.path.join(ROOT, "docs", "media", "references", "ref_terrain_v1_stardew.png")


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

    ⚠ 本函数是 SHORE 半唯一的"是不是一样"判据 ⇒ 每次运行都被 teeth 自检拿已知不同的一对喂一遍。
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


def decoded_rgba(path):
    """出货 png → (RGBA bytes, (w,h))。**解码后**的像素，不是容器字节。"""
    with Image.open(path) as raw:
        img = raw.convert("RGBA")
    return img.tobytes(), img.size


def sha_rgba(path):
    b, size = decoded_rgba(path)
    return hashlib.sha256(b).hexdigest(), size, len(b)


def rebuild_all():
    """当场从 CC0 总表重建 13 张瓦，并**同时**记录重建期间打开过哪些文件（自证①）。

    只有 8 张 SHORE 会被拿去逐像素比；5 张 LEGACY 的重建结果本门不再使用（它们已不是出货来源）。
    仍整套重建，是因为 SHORE 的键控调色板取自本函数刚重建出的草地瓦（build() 内部逻辑，只读 CC0）。
    """
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


def load_manifest():
    if not os.path.isfile(MANIFEST):
        return None
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def rebless(reason):
    """⚠️人工专用：重算 5 张生成瓦的解码 RGBA sha256，写清单。CI 永不调用它。"""
    missing = sorted(n for n in GEN if not os.path.isfile(os.path.join(DST, n + ".png")))
    if missing:
        sys.exit("❌ rebless 中止：出货目录缺生成瓦 %s" % ", ".join(missing))
    tiles = {}
    for n in sorted(GEN):
        h, size, _ = sha_rgba(os.path.join(DST, n + ".png"))
        tiles[n] = {"sha256": h, "size": list(size)}
    ref_sha = ""
    if os.path.isfile(REF):
        ref_sha = hashlib.sha256(open(REF, "rb").read()).hexdigest()
    prev = load_manifest() or {}
    history = list(((prev.get("_meta") or {}).get("rebless_history")) or [])
    stamp = time.strftime("%Y-%m-%d")
    history.append("%s · %s · ref_sha=%s" % (stamp, reason or "(未给原因)", ref_sha[:12]))
    doc = {
        "_meta": {
            "note": "AV2 生成地形瓦（5 张）解码 RGBA 的 sha256 钉子。这 5 张来自 tools/slice_terrain_ref.py "
                    "对参考图降采样，无 CC0 源可重建 ⇒ 只能钉 hash。8 张 CC0 岸线瓦不在这里（它们仍走 "
                    "terrain_gate.py 的当场重建-比对）。",
            "ratchet": "只能由人跑 `python tools/terrain_gate.py --rebless \"原因\"` 重烘，且必须在【Read 眼验每张瓦 + "
                       "录一帧真机整镇图】之后。CI 永不自动重烘（这是 R4 waived 下唯一诚实的缓解，见 terrain_gate.py 抬头）。",
            "hash": "sha256(Image.open(png).convert('RGBA').tobytes())  —— 解码像素，非容器字节",
            "source": "tools/slice_terrain_ref.py ← docs/media/references/ref_terrain_v1_stardew.png",
            "ref_sha256": ref_sha,
            "reblessed_by": "python tools/terrain_gate.py --rebless",
            "reblessed_at": stamp,
            "rebless_history": history,
        },
        "tiles": tiles,
    }
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print("⚠️  已重烘 %s（%d 张生成瓦）。" % (_rel(MANIFEST), len(tiles)))
    print("    确认你已经：① Read 眼验每张 16×16 瓦；② 录了一帧真机整镇图。否则你刚把一张没人看过的瓦钉成了'正确'。")
    for n in sorted(tiles):
        print("      %-14s %s  size=%s" % (n, tiles[n]["sha256"][:16] + "…", tiles[n]["size"]))
    return 0


def main():
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    fail = 0

    def ok(m):
        print("  ✅ %s" % m)

    def bad(m):
        nonlocal fail
        print("  ❌ FAIL: %s" % m)
        fail = 1

    print("### terrain gate (hybrid)：8 张 CC0 岸线瓦=当场重建，5 张生成瓦=hash-pin（docs/49 §七 + AV2/docs/159）")
    print("  CC0 源 %s" % _rel(SHEET))
    print("  清单   %s" % _rel(MANIFEST))
    print("  出货   %s" % _rel(DST))

    # ── 0. 文件集合 ─────────────────────────────────────────────────────────
    want = GEN | CC0
    if not os.path.isdir(DST):
        bad("出货目录不存在：%s" % _rel(DST))
        print("\n=== TERRAIN GATE FAIL ❌ ===")
        return 1
    have = {f[:-4] for f in os.listdir(DST) if f.lower().endswith(".png")}
    missing, extra = sorted(want - have), sorted(have - want)
    if missing:
        bad("出货目录缺 %d 张：%s" % (len(missing), ", ".join(missing)))
    if extra:
        bad("出货目录多出 %d 张【本门不认识】的瓦：%s" % (len(extra), ", ".join(extra)))
    if not missing and not extra:
        ok("文件集合：%d 张 png = LEGACY(生成 %d) ∪ SHORE(CC0 %d)（0 缺失 / 0 多余）"
           % (len(have), len(GEN), len(CC0)))

    # ══ A 半：8 张 CC0 岸线瓦 —— 当场重建 + 逐像素比（G5 原样）══════════════════
    # ── A1. 当场重建 + 来源自证 ─────────────────────────────────────────────
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

    # ── A2. 判别力自检 teeth（SHORE）────────────────────────────────────────
    probe = sorted(CC0)[0]                      # 挑一张岸线瓦
    tampered = rebuilt[probe].copy()
    tp = tampered.load()
    tx, ty = 8, 8                               # 瓦心：不论该点实心还是透明，RGB 取反必然改变元组
    old = tp[tx, ty]
    tp[tx, ty] = (old[0] ^ 0xFF, old[1] ^ 0xFF, old[2] ^ 0xFF, old[3])
    tn, tnotes, _ = compare(probe, tampered, rebuilt[probe])
    if tn == 1 and tnotes and probe in tnotes[0]:
        ok("判别力自检(SHORE)：向 %s 注入 1 px ⇒ compare() 报「1 px 不同」且指名该瓦（比对器有牙）" % probe)
    else:
        bad("判别力自检(SHORE)失败：注入 1 px，compare() 报 %d px / notes=%s ⇒ 这道门本身是坏的" % (tn, tnotes))

    # ── A3. 逐像素比对（只比 8 张 CC0 SHORE）────────────────────────────────
    tiles_cmp = px_cmp = bytes_cmp = 0
    same = 0
    reenc_same = reenc_cmp = 0
    details = []
    for s in sorted(CC0 & have):
        path = os.path.join(DST, s + ".png")
        with Image.open(path) as raw:
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
        buf = io.BytesIO()                      # 软判据：容器字节（随 zlib/Pillow 版本走，只打印不判红）
        rebuilt[s].save(buf, format="PNG")
        with open(path, "rb") as f:
            disk = f.read()
        reenc_cmp += 1
        if buf.getvalue() == disk:
            reenc_same += 1
        details.append((s, n, npx, len(disk), buf.getvalue() == disk))

    if tiles_cmp == 0 or px_cmp == 0 or bytes_cmp == 0:
        bad("SHORE 扫过量为 0（瓦 %d / 像素 %d / 字节 %d）—— 一张都没比就打绿是假门"
            % (tiles_cmp, px_cmp, bytes_cmp))
    elif same == tiles_cmp:
        ok("CC0 岸线逐像素比对：%d/%d 张与当场重建**逐像素相同**；共比 %s 像素 / %s 字节"
           % (same, tiles_cmp, format(px_cmp, ","), format(bytes_cmp, ",")))
    else:
        print("     （CC0 已比对 %s 像素 / %s 字节，%d/%d 张一致）"
              % (format(px_cmp, ","), format(bytes_cmp, ","), same, tiles_cmp))

    # ══ B 半：5 张生成瓦 —— hash-pin（AV2）════════════════════════════════════
    man = load_manifest()
    gen_tiles = 0
    gen_px = gen_bytes = 0
    gen_same = 0
    gen_details = []
    if man is None:
        bad("找不到清单 %s —— 生成瓦没有钉子可比（跑 `--rebless` 重烘，但只能在眼验+录真机帧之后）"
            % _rel(MANIFEST))
    else:
        pins = man.get("tiles") or {}
        for g in sorted(GEN):
            if g not in have:
                continue                        # 缺失已在文件集合处判红
            path = os.path.join(DST, g + ".png")
            h, size, nb = sha_rgba(path)
            gen_tiles += 1
            gen_px += size[0] * size[1]
            gen_bytes += nb
            pin = pins.get(g)
            if pin is None:
                bad("%s 不在清单里 —— 有一张出货生成瓦没被钉（补钉只能 --rebless）" % g)
                gen_details.append((g, h, "无钉子"))
            elif pin.get("sha256") != h:
                bad("%s 解码 RGBA sha256 与清单不符：出货 %s… ≠ 钉子 %s…（有人改了这张瓦而没走 --rebless）"
                    % (g, h[:16], str(pin.get("sha256"))[:16]))
                gen_details.append((g, h, "≠钉子"))
            else:
                gen_same += 1
                gen_details.append((g, h, "==钉子"))

        # ── B-teeth：hash 判别力（翻 1 px ⇒ hash 必变，杀 return-True/常量 hash）────
        tprobe = sorted(GEN & have)[0] if (GEN & have) else None
        if tprobe is None:
            bad("判别力自检(生成瓦)：一张生成瓦都不在出货目录 —— 无法自检")
        else:
            with Image.open(os.path.join(DST, tprobe + ".png")) as raw:
                timg = raw.convert("RGBA")
            base_hash = hashlib.sha256(timg.tobytes()).hexdigest()
            tpx = timg.load()
            o = tpx[8, 8]
            tpx[8, 8] = (o[0] ^ 0xFF, o[1] ^ 0xFF, o[2] ^ 0xFF, o[3])
            flip_hash = hashlib.sha256(timg.tobytes()).hexdigest()
            pin_hash = (pins.get(tprobe) or {}).get("sha256")
            if flip_hash != base_hash and base_hash == pin_hash:
                ok("判别力自检(生成瓦)：向 %s 翻 1 px ⇒ sha256 改变且原图 hash==钉子（hash 有牙，非常量/非 return-True）" % tprobe)
            elif base_hash != pin_hash:
                bad("判别力自检(生成瓦)：%s 出货 hash 与钉子已不符，teeth 前提不成立（先修 B 半的 hash 比对）" % tprobe)
            else:
                bad("判别力自检(生成瓦)失败：翻 1 px 后 sha256 没变 ⇒ hash 判据是坏的")

        # ── B-扫过量自证 ────────────────────────────────────────────────────
        if gen_tiles == 0 or gen_px == 0 or gen_bytes == 0:
            bad("生成瓦扫过量为 0（瓦 %d / 像素 %d / 字节 %d）—— 一张都没 hash 就打绿是假门"
                % (gen_tiles, gen_px, gen_bytes))
        elif gen_same == gen_tiles:
            ok("生成瓦 hash-pin：%d/%d 张解码 RGBA sha256 与清单相同；共 hash %s 像素 / %s 字节"
               % (gen_same, gen_tiles, format(gen_px, ","), format(gen_bytes, ",")))

    # ── 软判据打印 + 丢掉的第 4 条自证的大声声明 ─────────────────────────────
    if reenc_cmp:
        tag = "✅" if reenc_same == reenc_cmp else "⚠ "
        print("  %s CC0 容器字节（软判据，不判红）：%d/%d 张与本机 Pillow %s 重编码逐字节相同"
              % (tag, reenc_same, reenc_cmp, PIL.__version__))
    print("  ℹ  已删自证④（slice_visual.py↔LEGACY 切图坐标一致）：生成瓦无切图坐标，此臂结构上不适用；"
          "代价见本文件抬头「丢掉的那条自证」。")

    if verbose:
        print("\n  ── CC0 岸线逐张明细 ──")
        print("  %-16s %8s %10s %10s  %s" % ("瓦", "差异px", "比对px", "磁盘字节", "容器字节相同"))
        for s, n, npx, nb, rs in details:
            print("  %-16s %8d %10s %10s  %s" % (s, max(n, 0), format(npx, ","), format(nb, ","), rs))
        print("\n  ── 生成瓦 hash 明细 ──")
        for g, h, st in gen_details:
            print("  %-16s %s…  %s" % (g, h[:24], st))

    print()
    if fail == 0:
        print("=== TERRAIN GATE PASS ✅ ===")
    else:
        print("=== TERRAIN GATE FAIL ❌ ===")
        print("修法：CC0 岸线不符 ⇒ `python tools/slice_shore.py` 重切；"
              "生成瓦不符 ⇒ 若是**蓄意**改美术，先 Read 眼验+录真机帧，再 `python tools/terrain_gate.py --rebless \"原因\"`。")
    return fail


if __name__ == "__main__":
    if "--rebless" in sys.argv:
        i = sys.argv.index("--rebless")
        reason = sys.argv[i + 1] if len(sys.argv) > i + 1 and not sys.argv[i + 1].startswith("-") else ""
        sys.exit(rebless(reason))
    sys.exit(main())
