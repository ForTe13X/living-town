#!/usr/bin/env python3
# assert_precip.py — AI1（编号129）降水可见门：**冬天必须真有落雪、雨必须真有雨丝**，不许悄无声息退回"只有色调"。
# ★ 2026-08-06 AK1 已接线：tools/visual_gate.sh 第 6 步在同一个 Xvfb 里多拍 12 帧（冬雪 on/off + 非冬雨 on/off × 3 seed）
#   后【原地引用】本文件判决（out_dir = $OUT/precip）。判据/阈值/§2.5 由 AI1 原样保留。
#
# 判据形状照抄 R2/S3/V3/AF2 四道既有视觉门：
#   · 关系判据（on vs off，不锚死绝对色）：coverage = 同 tick「降水 pass 开 / 关」两帧的差异像素数。
#     "关"用 WorldView 的 `--draw-skip snow|rain`（AI1 加，见 WorldView.gd `_ready` 的 user-args 解析）。
#     ⇒ **off 帧本身就是负对照**：谁把 _draw_snow/_draw_rain 删空 ⇒ on≡off ⇒ coverage 0 ⇒ 红。
#   · 判据在【宿主侧】跑，吃已拍好的帧（拍帧步在 run_precip_gate.sh，与 visual_gate.sh 同构）。
#   · 阈值【量出来】、多 seed 展布逐 seed 报（见下 §阈值）。
#   · getbbox 陷阱安全写法：一律先 convert("RGB") 再逐通道比（Pillow≥11 的 alpha_only 默认对本项目全不透明美术恒空真，docs/41 §6）。
#   · 只数【max 通道差 > --min-delta】的像素 ⇒ 忽略光栅器 LSB 抖动，只认真正的降水笔画（雪=近白、雨丝=亮蓝，都远超 8）。
#
# ── §阈值（多 seed 展布 = 量出来的，不是拍脑袋）──────────────────────────────────
#   拍帧：冬用 tick 11160（游戏日47=冬，season 与 seed 无关 ⇒ 全 seed 都下雪，密度随该 seed 当日 weather 变）；
#         雨用各 seed 最早的【非冬】雨日的正午（seed1=t600 / seed3=t840 / seed5=t1560，都是春·雨）。
#   实测 coverage（delta>8，docker 软渲染 mesa pin，1280×768 --shot-fit）：
#     SNOW  seed1(阴)=1617  seed3(晴)=1154  seed5(雨)=3505   展布[1154,3505]，floor=1154（晴档=密度地板40）
#     RAIN  seed1=1458      seed3=1458      seed5=1458        展布[1458,1458]，零方差
#   · 雪的方差来自【weather 驱动的密度】（晴40/阴54/雨70）——season 本身与 seed 无关，故 floor 恒在"晴"档。
#   · 雨【零方差】且这是【证出来的】：雨丝画在居民【之上】（无遮挡）+ 铺设夹到 map∩vis（同图同 fit）+
#     正午 tick 的降水相位恒为 0（240k+120 恒 %6==0、%8==0）⇒ coverage = f(map,pattern)，与 seed 无关。
#     这与 AF2 季节门同形（f(季) 非 f(seed)）⇒ **单 seed 标定在这道门上安全，且这句话是证出来的**（S3 的反面）。
#   · 阈值：--min-snow 600（floor 1154 的 0.52×，且 >> 负对照的 0）；--min-rain 700（floor 1458 的 0.48×）。
#     谁把它们提到 floor 以上，"晴"档冬帧会假红——那是**改后**的地板，不是余量。
#
# ── §2.5 探测包络（完整原始输出见 analysis/ai1/envelope.txt）────────────────────
#   detects:        ① 雪层删空/关掉（on≡off，coverage 0 < 600）⇒ 红，exit 1（= off 帧作负对照，在"未画雪的树"上它是红的）
#                   ② 雨层删空/关掉（coverage 0 < 700）⇒ 红，exit 1
#                   ③ 几何错（喂 640×384 帧）⇒ C 臂拒判，exit 1   ④ 少喂一帧（缺 off）⇒ C 臂拒判，exit 1
#   does_not_detect: 降水【长什么样】一概不管（关系判据，只数"有没有画东西"，换颜色/换形状/换密度照过——色值真源在 WorldView.gd，不抄进判据）；
#                   降水【落在哪一层顺序】不管（只要 on/off 有差）；只看冬(season)与非冬雨(weather) 两类，晨昏/其余天气组合没判；
#                   不验降水是否【确定性】（那由 digest + 同 tick 重拍证，见 docs/129 §三，不在本门）；
#                   只看 map∩vis 带内（界外背板本就不下雨/雪，是设计）。
#   confidence:     N=4 变异体全按预期（①②③④，各核过退出码）；does_not_detect 逐条从关系判据结构直接读出，非臆测。
#
# 退出码：0 PASS / 1 FAIL（含拒判）。用法：python assert_precip.py <out_dir> [--min-snow N] [--min-rain N] [--min-delta N] [--w 1280] [--h 768]
import sys, os, glob, argparse
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # V3/AF2 教训：新门第一次接 CI 常红在 ✅ 的 GBK 编码上
except Exception:
    pass
from PIL import Image, ImageChops


def coverage(on_path, off_path, min_delta):
    a = Image.open(on_path).convert("RGB")
    b = Image.open(off_path).convert("RGB")
    if a.size != b.size:
        return None, a.size, b.size
    d = ImageChops.difference(a, b)
    if d.getbbox() is None:
        return 0, a.size, b.size
    r, g, bl = d.split()
    mx = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    nz = sum(mx.histogram()[min_delta + 1:])
    return nz, a.size, b.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--min-snow", type=int, default=600)
    ap.add_argument("--min-rain", type=int, default=700)
    ap.add_argument("--min-delta", type=int, default=8)
    ap.add_argument("--w", type=int, default=1280)
    ap.add_argument("--h", type=int, default=768)
    a = ap.parse_args()
    od = a.out_dir
    rc = 0

    def pairs(kind):
        out = []
        for on in sorted(glob.glob(os.path.join(od, "*_%s_on.png" % kind))):
            off = on[:-len("_on.png")] + "_off.png"
            out.append((on, off))
        return out

    # ── C 臂（几何自检，先跑）：每对两帧都在、尺寸相等且 == 期望 fit 尺寸 ──
    for kind in ("winter", "rain"):
        ps = pairs(kind)
        if not ps:
            print("  ❌ C: 没有找到任何 %s on/off 帧对（拍帧步是否跑了？）" % kind); rc = 1; continue
        for on, off in ps:
            if not os.path.exists(off):
                print("  ❌ C: 缺 off 帧 %s（少喂一帧 ⇒ 拒判）" % os.path.basename(off)); rc = 1; continue
            im = Image.open(on)
            if im.size != (a.w, a.h):
                print("  ❌ C: %s 尺寸 %s != 期望 (%d,%d)（几何错 ⇒ 取样带取歪，拒判）" % (
                    os.path.basename(on), im.size, a.w, a.h)); rc = 1
    if rc != 0:
        print("=== PRECIP GATE: FAIL（几何/缺帧 ⇒ 拒判）===")
        return 1

    # ── A1 臂：冬帧必须有雪（on vs off coverage ≥ min-snow）──
    for on, off in pairs("winter"):
        cov, sa, sb = coverage(on, off, a.min_delta)
        if cov is None:
            print("  ❌ A1: %s 与 off 尺寸不一致 %s/%s" % (os.path.basename(on), sa, sb)); rc = 1; continue
        ok = cov >= a.min_snow
        print("  %s A1 SNOW %-22s coverage=%5d  (min=%d)" % ("PASS" if ok else "FAIL", os.path.basename(on), cov, a.min_snow))
        if not ok:
            rc = 1

    # ── A2 臂：雨帧必须有雨丝（on vs off coverage ≥ min-rain）──
    for on, off in pairs("rain"):
        cov, sa, sb = coverage(on, off, a.min_delta)
        if cov is None:
            print("  ❌ A2: %s 与 off 尺寸不一致 %s/%s" % (os.path.basename(on), sa, sb)); rc = 1; continue
        ok = cov >= a.min_rain
        print("  %s A2 RAIN %-22s coverage=%5d  (min=%d)" % ("PASS" if ok else "FAIL", os.path.basename(on), cov, a.min_rain))
        if not ok:
            rc = 1

    print("=== PRECIP GATE: %s ===" % ("PASS" if rc == 0 else "FAIL"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
