"""接缝量具 —— 沿地图矩形边界法向取剖线，报【最大相邻像素亮度跃变】的三把尺子。

## 来历（F3 把它从 scratchpad 搬进仓库）

原作是 C7（docs/43 §1.2g），此前只存在于
`<会话临时目录>/scratchpad/wave_c/C7/seam.py` —— 那是一条**带会话 UUID 的 %TEMP% 路径**，
会随会话消失。而 docs/43 §1.2g、docs/46、docs/48 §二·一/§三-F3 **三处**都把它当作"唯一正确的量具"
指名引用（docs/43 原话就写着「建议 C4 或 Wave D 收进 CI」，没人做）。
F3 奉命"用 C7 自己写的 seam.py"时它还在，下一棒就不一定了 ⇒ 搬进 tools/。

**测量数学与 C7 原版逐行相同**，只改了入口：原版在模块末尾裸调 `main()`，
`import` 它就会拿 `sys.argv` 跑一遍（F3 实测踩到，只能靠 `redirect_stdout` 绕）。
这里换成 `if __name__ == "__main__"`，并加了一个目录模式，读数不受影响
（F3 已逐帧对拍：同一批 PNG，本文件与 C7 原版**每一个统计量都逐位相同**）。

## 三把尺子，不是一把（C7 实测：派棒者只给了 win16，而它量的是【界内的花】）

  cross  : 恰好跨过地图边界那一步（最后一个界外像素 → 第一个界内像素）——真正的"剪刀口"
  outband: 只在【界外】第一层整带内的最大跃变——守"我有没有在外面新造硬边"（石墙就在这里）
  win16  : 16px 窗口最大值。保留以忠实于原始 brief，但它有一个【由界内像素美术设定的地板】：
           窗口有 8px 落在界内，花丛/树干/路缘本来就自带 ~130 的相邻跃变，接缝修到 0 也压不下去。

## ⚠️ F3 追加的两条使用纪律（2026-07-30，都是实测出来的）

**① 读 `cross` 要读 `p90`/`median`，不要读 `max` —— 下雨天 `max` 会被【一颗雨滴】顶穿。**
`WorldView._draw_rain()` 的雨丝画在 `_vis` 全域上，**不按地图矩形裁剪**，所以它合法地跨界。
剖线一旦正好扫到某根雨丝压在"第一个界内像素"那一行，`cross` 就报一个 ~22 的孤立尖峰，
而同一帧的 `p90` 与 `median` 是 1.14。判别法（F3 用过的负对照）：雨丝相位 = `Sim.tick_no % 6`，
把 tick 加 1 再拍，尖峰会**换一个 x 出现或整个消失**（实测 6 个相位：x636 / x708 / 无 / x692 / x452 / x328）。
算术复核：草地 (123,157,123) 与雨色 `Color(0.80,0.89,1.00,0.30)` 混合 = (147.3,178.0,162.6)，
实测那颗尖峰像素正是 (147,178,163)。
> ⇒ **凡是拿本量具写门的，判据必须落在 `cross.p90`（或 median）上。**
> 写 `cross.max <= 5` 的门会在【下雨天】变红 —— 这与 docs/41 §6「写死 0 的重画门其实是在守你的机器别太快」
> 是同一个病的另一次发作：**判据没问题，出问题的是【喂给它的那个世界】。**

**② `win16` 的最大值【从来不在边界上】。** F3 在 15 帧上逐帧定位过 win16 的 argmax：
15/15 都落在 `left@y336` 的 (292,336)→(293,336) —— 那是**界内 4px 处的一朵黄花**（C7 记过同一朵）。
逐剖线统计 argmax 的落点是 `{界外 ~204, 边界 0, 界内 ~47}`：**边界那一档恒为 0**。
所以 win16 的量级（本仓库当前 32-130）**读不出接缝好坏**，只能当保真度参考。

## ★地图矩形公式（docs/41 §6-⑥ / scratchpad/wave_c/C1/diff.py）

`--resolution` 不改变相机取景。`stretch/mode=canvas_items` 下 `Main.gd` 的 `_vpsz` 恒为基准
1280x768，画布随后整体拉伸 W/1280。按窗口尺寸直接套公式会把矩形算大 15%，
量到的就不是接缝而是镇子内部。**本量具吃的是 `--shot-fit` 的整镇入画帧**；
拿跟随相机（1.8× 特写）那种帧来喂它，矩形根本不在画面里。

## ★HUD 遮挡必须排除

右侧居民面板、底部聊天条/时间轴、顶栏、左下播报 scrim 都压在世界之上，
剖线穿过它们量到的是【面板边缘】不是【地图接缝】。所以只取每条边上未被 HUD 覆盖的区段，
且用「改前/改后同一组坐标」保证可比。
（左下那块 scrim 就是 docs/48 §二·一-② 说的"西南角更暗的区域"——它是 HUD，不是地图，见 F3 回执。）

用法:
    python tools/seam.py <png> [--json out.json]
    python tools/seam.py before.png after.png      # 两张一起报，带 Δ
    python tools/seam.py --dir <目录>              # 目录里每张 PNG 一行汇总表
"""
import sys, os, json
from PIL import Image

MAP_W, MAP_H, T = 64, 48, 48
BASE_VP = (1280, 768)
PAD = (120, 240)          # Main.gd _pad
HALF = 8                  # 剖线半长 → 全长 16px


def map_rect(size):
    W, H = size
    mapsz = (MAP_W * T, MAP_H * T)
    fit = min((BASE_VP[0] - PAD[0]) / mapsz[0], (BASE_VP[1] - PAD[1]) / mapsz[1])
    stretch = min(W / BASE_VP[0], H / BASE_VP[1])
    w = mapsz[0] * fit * stretch
    h = mapsz[1] * fit * stretch
    return ((W - w) / 2.0, (H - h) / 2.0, (W + w) / 2.0, (H + h) / 2.0)


def lum(p):
    # Rec.709 相对亮度，0..255 尺度（与"亮度跃变"读数同尺度）
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def profiles(size, band):
    """产出 [(name, pts)]，每条剖线【由外向内】穿过边界：界外 band 个 + 界内 HALF 个，且避开 HUD。

    HUD 覆盖区（1280x768 基准，按 stretch 缩放）：顶栏 y<40、右面板 x>968、
    底部聊天+时间轴 y>650、左下播报 scrim x<600 且 y>462。
    右/下两条边整条压在 HUD 下面 ⇒ 本量具只用【上】【左】两条边，改前改后同一组坐标。
    """
    W, H = size
    s = min(W / BASE_VP[0], H / BASE_VP[1])
    x0, y0, x1, y1 = map_rect(size)
    hud_top, hud_right, hud_bottom = 40 * s, 968 * s, 650 * s
    log_x, log_y = 600 * s, 462 * s
    out = []
    step = max(2, int(round(4 * s)))
    for x in range(int(x0) + 12, int(x1) - 12, step):
        if x > hud_right or (y0 - band) < hud_top:
            continue
        out.append(("top@x%d" % x, [(x, int(y0) - band + i) for i in range(band + HALF)]))
    for y in range(int(y0) + 12, int(y1) - 12, step):
        if y > hud_bottom or ((x0 - band) < log_x and y > log_y):
            continue
        out.append(("left@y%d" % y, [(int(x0) - band + i, y) for i in range(band + HALF)]))
    return out


METRICS = ("cross", "outband", "win16")


def measure(path, band_tiles=3.0):
    im = Image.open(path).convert('RGB')
    px = im.load()
    W, H = im.size
    s = min(W / BASE_VP[0], H / BASE_VP[1])
    fit = min((BASE_VP[0] - PAD[0]) / (MAP_W * T), (BASE_VP[1] - PAD[1]) / (MAP_H * T))
    tile_px = T * fit * s                       # 一格在屏幕上的像素数
    band = max(2, int(round(band_tiles * tile_px)))
    res = {"path": path, "size": [W, H], "map_rect": [round(v, 1) for v in map_rect(im.size)],
           "tile_px": round(tile_px, 2), "band_px": band}
    per_edge = {}
    for name, pts in profiles(im.size, band):
        ls = [lum(px[x, y]) if (0 <= x < W and 0 <= y < H) else None for (x, y) in pts]
        if any(v is None for v in ls):
            continue
        # pts 布局: [0 .. band-1] 界外(由远及近), [band .. band+HALF-1] 界内
        outside = ls[:band + 1]                 # 含第一个界内像素之前的全部界外
        cross = abs(ls[band] - ls[band - 1])
        outb = max(abs(outside[i + 1] - outside[i]) for i in range(len(outside) - 2)) \
            if len(outside) > 2 else 0.0
        w16 = ls[band - HALF: band + HALF]
        win = max(abs(w16[i + 1] - w16[i]) for i in range(len(w16) - 1))
        edge = name.split('@')[0]
        per_edge.setdefault(edge, []).append({"cross": cross, "outband": outb, "win16": win, "at": name})

    def agg(vals, key):
        v = sorted(x[key] for x in vals)
        n = len(v)
        return {"n": n, "max": round(v[-1], 2), "p90": round(v[int(0.9 * (n - 1))], 2),
                "median": round(v[n // 2], 2), "mean": round(sum(v) / n, 2),
                "worst_at": max(vals, key=lambda x: x[key])["at"]}
    for edge, vals in per_edge.items():
        res[edge] = {m: agg(vals, m) for m in METRICS}
    allv = [x for vals in per_edge.values() for x in vals]
    res["ALL"] = {m: agg(allv, m) for m in METRICS}
    return res


def show(r):
    print("%s  size=%s  map_rect=%s  tile=%spx  band=%spx"
          % (r['path'], tuple(r['size']), r['map_rect'], r['tile_px'], r['band_px']))
    for k in ("top", "left", "ALL"):
        if k not in r:
            continue
        for m in METRICS:
            d = r[k][m]
            print("   %-5s %-8s n=%4d  max=%7.2f  p90=%7.2f  median=%7.2f  mean=%7.2f  worst@%s"
                  % (k, m, d['n'], d['max'], d['p90'], d['median'], d['mean'], d['worst_at']))


def show_table(paths):
    """目录/多图模式：一行一帧。**头条数字是 cross 的 p90，不是 max**（见抬头纪律①）。"""
    print("%-28s %9s %9s %9s | %8s %8s | %9s"
          % ("frame", "cross_p90", "cross_med", "cross_max", "outb_max", "outb_p90", "win16_max"))
    for p in paths:
        a = measure(p)["ALL"]
        print("%-28s %9.2f %9.2f %9.2f | %8.2f %8.2f | %9.2f  worst_cross@%s"
              % (os.path.basename(p)[:-4], a["cross"]["p90"], a["cross"]["median"], a["cross"]["max"],
                 a["outband"]["max"], a["outband"]["p90"], a["win16"]["max"], a["cross"]["worst_at"]))


def main():
    argv = sys.argv[1:]
    if "--dir" in argv:
        d = argv[argv.index("--dir") + 1]
        show_table([os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".png")])
        return
    args = [a for a in argv if not a.startswith('--')]
    if not args:
        print(__doc__)
        return
    rs = [measure(a) for a in args]
    for r in rs:
        show(r)
    if len(rs) == 2:
        b, a = rs
        print("\n  === delta (after - before) ===")
        for k in ("ALL",):
            for m in METRICS:
                for stat in ("max", "p90", "median"):
                    bv, av = b[k][m][stat], a[k][m][stat]
                    d = av - bv
                    pct = 100.0 * d / bv if bv else float('nan')
                    print("   %-4s %-8s %-6s: %7.2f -> %7.2f   d=%+7.2f (%+6.1f%%)"
                          % (k, m, stat, bv, av, d, pct))
    if '--json' in argv:
        p = argv[argv.index('--json') + 1]
        with open(p, 'w', encoding='utf-8') as fh:
            json.dump(rs, fh, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
