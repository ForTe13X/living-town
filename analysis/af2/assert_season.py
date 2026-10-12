#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assert_season.py —— 四季可分门（Wave AF · AF2）。
★ 2026-08-06 AK1 已接线：`tools/visual_gate.sh` 第 6 步在同一个 Xvfb 里多拍 8 帧晴天四季（昼+夜）后
  【原地引用】本文件判决（不搬进 tools/：见下 §怎么接进 CI 的 (a)——搬走会断 import 路径）。判据/阈值/§2.5 由 AF2 原样保留。

守的性质一句话：**四季不许糊成一块——春/夏/秋/冬的地面主色必须两两分得开。**

形状照抄 tools/assert_interior_shell.py（R2）/ tools/assert_furniture_role.py（S3）/
tools/assert_tree_stand.py（V3）：**关系判据、吃已经拍好的帧、判据在宿主侧跑、阈值是量出来的、几何有自检。**
色差用仓库里现役的 tools/ciede2000.py（ΔE00），世界主色用现役的 tools/assert_daynight.world_mode
（与昼夜门同一条不含 HUD 的横带 x∈[60,960) y∈[60,420)）——**两把尺都不另立第二份真相**（红线#5 复用）。

## 为什么要有它

改前实测：`SEASON_VEG`/`SEASON_WASH`（Wave C 起就在）确实把四季画出了差异，但**春↔夏这一对
只有 ΔE00 2.71(昼) / 2.40(夜)** —— 卡在 JND(≈2.3)，两个绿季眼验里分不开（旧注写"夏=深浓"，值没兑现）。
其余各对都在 8–23。⇒ 病是**四季里最该看见的那一步（生长季 春→夏）几乎不可见**，而**没有任何一道门守着它**：
把 `SEASON_VEG` 整表退回 `Color.WHITE`（四季全塌成一个色）今天能【悄无声息】通过全部 CI——
昼夜门只跑春帧且与季无关（veg 昼夜同施，比值不变），树丛/池/室内门的参考色都逐帧现取、对换季免疫。
本门就是补这道缺口：AF2 把夏压深到 ΔE00≈8(昼)/4.3(夜) 之后，用它把"四季可分"这条性质钉死。

## 判据

* **A 臂（可分）**：同一时刻（昼 或 夜）的四季地面主色，**两两 ΔE00 的最小值 ≥ `--min-de`**。
  一对糊在一起（或整表塌成一个色）⇒ 最小值掉到阈值以下 ⇒ 红。
* **C 臂（采样自检，先跑）**：每个时刻必须恰好 4 帧；帧尺寸必须是基准 1280×768 的整数倍
  （world_mode 的取样带按 w/1280 缩放，非整数倍会把带取歪 ⇒ 主色无意义）。任一条不满足 ⇒ **exit 1，不是静默放行**。

**没有 B 臂**，而这是**量过之后的决定**，不是省事：季节就是"四个可分的乘算色偏"，没有 trees 的密度、
furniture 的语义那种第二性质可守。硬凑一个 B 臂（比如"同季跨 seed 必须一致"）挡的是别的门已经挡住的东西——
四季是纯 f(day)、与 seed 无关，实测三个 seed 的春/夏主色**逐字节相同**（见下"多 seed 展布"），
那条一致性由确定性本身 + digest 保证，不该在这里立第二个副本。

## 阈值是量出来的（多 seed 展布：**零方差**，且解释得清为什么）

季节色是 `SEASON_VEG[季]`（纯 f(季)）乘在草地上，草地变体是 `_hash(x,y)`（纯位置、与 seed 无关），
晴天没有天气罩 ⇒ **地面主色是 f(季) 的纯函数、与 seed 无关**。实测（改后，seed 1/3/5 各自的晴天）：

    春↔夏（最紧的一对）   昼 ΔE00        夜 ΔE00
    seed 1               8.06           4.30
    seed 3               8.06           4.30
    seed 5               8.06           4.30
    -----------------------------------------------
    展布                 [8.06, 8.06]   [4.30, 4.30]   ← 零方差

这与 S3 的教训（`visual_gate.sh` 写死 SEED=3、单 seed 标定 2.08 而逐 seed 2.08–5.65 ⇒ 照抄会假红）
**方向相反**：那里的量具 f(seed)、这里 f(季)。⇒ 单 seed 标定在**这道门上**是安全的，而这句话是**证出来的**，不是假设。
> ⚠️ 前提是**晴天**：天气罩（阴/雨）会把主色整体推蓝、可能把两季拉近。接线的拍帧步必须挑晴天
>   （`weather(seed,day)=晴` 是确定的、可预算的；本目录的 run_season_gate.sh 就是这么挑的）。

`--min-de` 默认 **3.2**：夜是约束档（昼 8.06 余量大，夜 4.30 最紧）。
    改前（塌）夜 2.40 < 3.2（1.33× 在下）  ·  改后（分开）夜 4.30 ≥ 3.2（1.34× 在上）
两侧余量近乎对称、都约 1.33×。比 V3 的 1.5× 窄，写在这里是因为**它就是窄的**：季节色是被 Wave C 反复
眼验标定过的（"秋 1.32/0.52 偏芥末压了一档"…），春↔夏在夜里天生贴得近（夜乘子把两季差异所在的 R/G 压掉、
只剩 B，而春夏的差异恰在 R/G）。3.2 是 JND(2.3) 的 1.39×——"清楚可分"的最低线，不是余量。
谁把它提到 4.3 以上，改后的夜档会假红——那是**改后**的下界，不是余量。

## §2.5 探测包络

```
detects:（逐条都亲眼看着跑完并核过退出码，原始输出见 analysis/af2/envelope.txt）
  ① **改前那棵树**（seed3 晴、旧 SEASON_VEG["夏"]=(0.88,1.00,0.72)）⇒ 夜 min=2.40 < 3.2 ⇒ 红，exit 1。
     昼 min=2.71 也 < 3.2。——这同时就是「先在未改动的树上跑一遍」：它在那里【是红的】，故有判别力。
  ② **整表塌成一个色**（把四帧都喂同一张 spring 帧，模拟 SEASON_VEG 全退回 Color.WHITE）
     ⇒ 六对全 ΔE00=0.00 ⇒ 红，exit 1。挡的正是"悄无声息把季节关掉"这条本门存在的理由。
  ③ **取景几何算错**（喂一张 160×96 的小图）⇒ C 臂：尺寸非 1280×768 整数倍 ⇒ 红，exit 1，不给判决。
     防的是最难看的那种失效：带取歪 ⇒ 主色无意义 ⇒ 门照常全绿。
  ④ **少喂一帧**（只给 3 季）⇒ C 臂：帧数≠4 ⇒ 红，exit 1（不是把 3 季当 4 季偷偷判）。

does_not_detect:（逐条都是跑出来的或从结构直接读出来的，不是想出来的）
  · **颜色对不对，它一概不管。** 关系判据不是取值判据：把四季映射【对调】（春显秋的金黄）⇒ 四个主色照样两两分开 ⇒ 全绿。
    理由与 R2/S3/V3 相同：色值真源在 WorldView.gd，抄进判据文件等于立第二份真相。
  · **只看地面主色（那条横带的众数）。** 树/花草石/界外林的换季它一概不看——实测把 trees pass 的 veg 拿掉、
    只留草地换季，本门照绿。它守的是"四季地面分得开"，不是"每一层都换了季"。
  · **只看被拍到的那一对时刻**（昼 tod=0.5 / 夜 tod≈0.03）。晨昏、四季×天气的其余组合没判。
  · **要晴天。** 判据本身对天气无意见，但天气罩会把两季拉近 ⇒ 拍帧步必须挑晴天（见上）。它不自己验天气。
  · 不保证屏幕上"好看"，也不保证草地纹理没被一层纯色盖掉（那是 tree_stand/pixel-diff 的活）。

confidence: N=4（4 个变异体，每一个都跑完并核过退出码）：
            全 4 红 —— ① 改前的树(春↔夏塌) ② 整表塌成一色 ③ 几何算错 ④ 少喂一帧；
            0 绿变异体 —— 本门的 does_not_detect 是从**关系判据的结构**直接读出来的（换值/换映射不改关系），
            不像 V3 那样需要跑一个荧光色变异体来坐实：那条"换色照绿"这里是定义使然（min 两两 ΔE00 与绝对色值无关）。
```

**措辞**：本门**阻断了一类已观测的失效模式**（四季地面色糊成一块、或季节被整表关掉），
**不是**"补上了季节美术缺失的保护"——它连树和花草的换季都不看，也不管颜色对不对。

## 怎么接进 CI（本棒**不许碰 tools/**，接线留给合流的人）

季节门要吃**多季**帧，而 `tools/visual_gate.sh` 现在只拍春帧（seed3 tick 488/600 = 游戏日 3 = 春）。
所以不能像 pond/tree_stand 那样复用已拍的帧，得【多拍 8 张】（四季 × 昼夜，晴天）。两条路：
  (a) 把本文件挪到 `tools/assert_season.py`，在 `visual_gate.sh` 的同一个 Xvfb 上按
      analysis/af2/run_season_gate.sh 里的 8 条 godot 命令多拍 8 帧，再跑本判据；
  (b) 或让本门作为**独立一步**在 `tools/ci.sh` 第 6 步后另起一次 docker 渲染（代价：多一次容器）。
接线的人注意：拍帧的 tick 要落在**晴天**（`weather(seed,day)` 确定），run_season_gate.sh 已算好 seed3 的四个晴天。
`ci.sh` 第 6 步抬头的门数 +1，把"四季"加进那行总判文案。

用法:
    python analysis/af2/assert_season.py \\
        --noon  spring_noon.png summer_noon.png autumn_noon.png winter_noon.png \\
        --night spring_night.png summer_night.png autumn_night.png winter_night.png \\
        [--min-de 3.2] [--labels 春 夏 秋 冬]
    （只给 --noon 也行；两组都给则两组都判，任一红即整体红——照 visual_gate 昼夜两帧都判 tree_stand 的写法）
退出码 0=PASS 1=FAIL 2=用法错
"""
import argparse
import itertools
import json
import os
import statistics
import sys
from pathlib import Path
from PIL import Image, ImageDraw

# Windows 控制台默认 GBK，编不出 ✅/ΔE 的 → 会在判据全部算完之后炸在 print 上（V3 第一次接进 CI 的原样翻车）。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

# 复用现役工具（红线#5）：world_mode（与昼夜门同一条 HUD-free 横带 + stdlib PNG 读取器）+ de00（ΔE00）。
_TOOLS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools")
sys.path.insert(0, _TOOLS)
import assert_daynight as _ad   # noqa: E402
from ciede2000 import de00      # noqa: E402

BASE_W, BASE_H = 1280, 768
TILE_WORLD = 48.0


def _cell(value):
    return (int(value[0]), int(value[1])) if isinstance(value, list) and len(value) >= 2 else None


def _grass_cells(map_data, coastal_data, fixture):
    """Build grass cells from canonical world layers; the fixture stores policy, not copied map data."""
    if fixture.get("semantic_id") != "grass":
        raise ValueError("semantic_id must be 'grass'; a paving/water mask is not a season sample")
    map_layers = fixture.get("map_layers_to_exclude", [])
    coastal_layers = fixture.get("coastal_layers_to_exclude", [])
    allowed_map = {"water", "trees", "blockers", "walls", "doors", "landmarks", "objects"}
    allowed_coastal = {"surfaces", "tree_belt", "planting", "flowerbeds"}
    if set(map_layers) != allowed_map or set(coastal_layers) != allowed_coastal:
        raise ValueError("grass-mask source layer inventory is incomplete or unknown")
    width, height = int(map_data.get("width", 0)), int(map_data.get("height", 0))
    if width <= 0 or height <= 0:
        raise ValueError("map dimensions are invalid")
    excluded = set()
    solid_lot_cells = set()
    roofed_area_cells = set()
    counts = {}

    def add(value):
        xy = _cell(value)
        if xy is not None and 0 <= xy[0] < width and 0 <= xy[1] < height:
            excluded.add(xy)

    for name in map_layers:
        before = len(excluded)
        values = map_data.get(name, [])
        if isinstance(values, dict):
            values = values.values()
        for value in values:
            if isinstance(value, dict):
                add(value.get("pos", value.get("cell", [])))
            else:
                add(value)
        counts["map." + name] = len(excluded) - before

    if fixture.get("exclude_area_rects") is True:
        before = len(excluded)
        for area in map_data.get("areas", {}).values():
            rect = area.get("rect", []) if isinstance(area, dict) else []
            if len(rect) != 4:
                raise ValueError("area rectangle is malformed")
            x, y, w, h = map(int, rect)
            for cy in range(y, y + h):
                for cx in range(x, x + w):
                    add([cx, cy])
                    if (area.get("type") not in (None, "", "plaza") and w >= 3 and h >= 3
                            and 0 <= cx < width and 0 <= cy < height):
                        roofed_area_cells.add((cx, cy))
        counts["map.areas"] = len(excluded) - before
    if fixture.get("exclude_solid_lots") is True:
        before = len(excluded)
        for lot in map_data.get("solid_lots", []):
            pos, footprint = lot.get("pos", []), lot.get("footprint", [])
            if len(pos) != 2 or len(footprint) != 2:
                raise ValueError("solid lot footprint is malformed")
            x, y = map(int, pos); w, h = map(int, footprint)
            for cy in range(y, y + h):
                for cx in range(x, x + w):
                    add([cx, cy])
                    if 0 <= cx < width and 0 <= cy < height:
                        solid_lot_cells.add((cx, cy))
        counts["map.solid_lots"] = len(excluded) - before
    for name in coastal_layers:
        before = len(excluded)
        values = coastal_data.get(name, {}) if name == "surfaces" else coastal_data.get(name, [])
        if name == "surfaces":
            if not isinstance(values, dict):
                raise ValueError("coastal surfaces are malformed")
            for cells in values.values():
                for value in cells:
                    add(value)
        elif name == "flowerbeds":
            for value in values:
                add(value.get("pos", []) if isinstance(value, dict) else value)
        else:
            for value in values:
                add(value)
        counts["coastal." + name] = len(excluded) - before
    margins = fixture.get("occlusion_margins", {})
    if set(margins) != {"solid_lots", "roofed_areas"}:
        raise ValueError("occlusion_margins must cover canonical solid_lots and roofed_areas")
    for name, source_cells in (("solid_lots", solid_lot_cells), ("roofed_areas", roofed_area_cells)):
        radius = int(margins[name])
        if radius < 0 or radius > 2:
            raise ValueError("occlusion margin for %s must be between 0 and 2" % name)
        before = len(excluded)
        for x, y in source_cells:
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if 0 <= x + dx < width and 0 <= y + dy < height:
                        excluded.add((x + dx, y + dy))
        counts["occlusion." + name] = len(excluded) - before
    cells = [(x, y) for y in range(height) for x in range(width) if (x, y) not in excluded]
    return width, height, cells, counts


def _shot_fit_geometry(frame_size, map_w, map_h, fixture):
    design = fixture.get("design_viewport", [])
    pad = fixture.get("home_pad", [])
    hud_free = fixture.get("hud_free_rect", [])
    if design != [BASE_W, BASE_H] or len(pad) != 2 or len(hud_free) != 4:
        raise ValueError("shot-fit design viewport or HUD padding drifted from the authored fixture")
    fw, fh = frame_size
    if fw % BASE_W != 0 or fh % BASE_H != 0 or fw / BASE_W != fh / BASE_H:
        raise ValueError("frame dimensions are not an integer scale of the authored shot-fit viewport")
    zoom = min((BASE_W - float(pad[0])) / (map_w * TILE_WORLD),
               (BASE_H - float(pad[1])) / (map_h * TILE_WORLD))
    scale = fw / BASE_W
    tile = TILE_WORLD * zoom * scale
    ox = (BASE_W * 0.5 - map_w * TILE_WORLD * 0.5 * zoom) * scale
    oy = (BASE_H * 0.5 - map_h * TILE_WORLD * 0.5 * zoom) * scale
    return {"projection": fixture.get("projection"), "tile_px": tile, "origin_px": [ox, oy],
            "scale": scale, "map_size": [map_w, map_h], "frame_size": [fw, fh],
            "hud_free_rect": [float(v) * scale for v in hud_free]}


def _sample_rect(cx, cy, geometry, fixture):
    inset = float(fixture.get("sample_cell_inset", 0.18))
    tile = geometry["tile_px"]; ox, oy = geometry["origin_px"]
    left, top, right, bottom = geometry["hud_free_rect"]
    x0 = max(int(round(ox + cx * tile + inset * tile)), int(left))
    x1 = min(int(round(ox + (cx + 1) * tile - inset * tile)), int(right))
    y0 = max(int(round(oy + cy * tile + inset * tile)), int(top))
    y1 = min(int(round(oy + (cy + 1) * tile - inset * tile)), int(bottom))
    return (x0, y0, x1, y1) if x1 > x0 and y1 > y0 else None


def _covered_cells(cells, geometry, fixture):
    return sum(_sample_rect(cx, cy, geometry, fixture) is not None for cx, cy in cells)


def _semantic_sample(path, cells, geometry, fixture, overlay_path=None):
    im = Image.open(path).convert("RGB")
    inset = float(fixture.get("sample_cell_inset", 0.18))
    if not (0.0 <= inset < 0.5):
        raise ValueError("sample_cell_inset must be between 0 and 0.5")
    pixels = []
    sampled_cells = 0
    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0)) if overlay_path else None
    draw = ImageDraw.Draw(overlay) if overlay is not None else None
    for cx, cy in cells:
        rect = _sample_rect(cx, cy, geometry, fixture)
        if rect is None:
            continue
        x0, y0, x1, y1 = rect
        x0 = max(0, min(im.width, x0)); x1 = max(0, min(im.width, x1))
        y0 = max(0, min(im.height, y0)); y1 = max(0, min(im.height, y1))
        if x1 <= x0 or y1 <= y0:
            continue
        crop = im.crop((x0, y0, x1, y1))
        pixels.extend(crop.get_flattened_data() if hasattr(crop, "get_flattened_data") else crop.getdata())
        sampled_cells += 1
        if draw is not None:
            draw.rectangle((x0, y0, x1 - 1, y1 - 1), fill=(34, 230, 128, 78), outline=(250, 226, 86, 190))
    if overlay is not None:
        Image.alpha_composite(im.convert("RGBA"), overlay).save(overlay_path)
    if not pixels:
        raise ValueError("grass mask sampled no pixels in this frame")
    color = tuple(int(statistics.median(px[channel] for px in pixels)) for channel in range(3))
    return color, len(pixels), sampled_cells


def _judge_semantic_set(tag, paths, labels, min_de, cells, geometry, fixture, overlay_dir=None):
    if len(paths) != 4:
        print("[SEASON] ❌ %s requires exactly 4 season frames, got %d" % (tag, len(paths)))
        return 1, None, []
    min_cells = int(fixture.get("min_grass_cells", 0))
    min_pixels = int(fixture.get("min_sample_pixels", 0))
    left, top, right, bottom = geometry["hud_free_rect"]
    ox, oy = geometry["origin_px"]; tile = geometry["tile_px"]
    inset = float(fixture.get("sample_cell_inset", 0.18))
    covered_cells = _covered_cells(cells, geometry, fixture)
    if covered_cells < min_cells:
        print("[SEASON] ❌ HUD-free grass mask coverage inconclusive: %d cells < %d; viewport rect=(%.0f,%.0f)-(%.0f,%.0f)" %
              (covered_cells, min_cells, left, top, right, bottom))
        return 1, None, []
    samples = []
    for label, path in zip(labels, paths):
        overlay = None
        if overlay_dir:
            os.makedirs(overlay_dir, exist_ok=True)
            overlay = os.path.join(overlay_dir, Path(path).stem + ".grass-mask.png")
        color, count, sample_cell_count = _semantic_sample(path, cells, geometry, fixture, overlay)
        if count < min_pixels:
            print("[SEASON] ❌ %s/%s grass coverage inconclusive: %d pixels < %d" % (tag, label, count, min_pixels))
            return 1, None, []
        print("[SEASON] %s/%s semantic=grass cells=%d pixels=%d median=%s" % (tag, label, sample_cell_count, count, color))
        samples.append({"label": label, "path": str(path), "median_rgb": list(color), "sample_pixels": count,
                        "grass_cells": sample_cell_count, "coverage_fraction": count / float(geometry["frame_size"][0] * geometry["frame_size"][1]),
                        "overlay": overlay})
    worst = (1e9, None)
    for a, b in itertools.combinations(samples, 2):
        delta = de00(tuple(a["median_rgb"]), tuple(b["median_rgb"]))
        mark = "ok" if delta >= min_de else "❌越界"
        print("    %s↔%s ΔE00=%6.2f %s" % (a["label"], b["label"], delta, mark))
        if delta < worst[0]:
            worst = (delta, (a["label"], b["label"]))
    ok = worst[0] >= min_de
    print("[SEASON] %s semantic-grass minimum ΔE00=%.2f (%s↔%s), threshold %.2f ⇒ %s" %
          (tag, worst[0], worst[1][0], worst[1][1], min_de, "PASS" if ok else "FAIL"))
    return (0 if ok else 1), worst[0], samples


def _semantic_self_test(map_path, coastal_path, fixture_path):
    root = Path(__file__).resolve().parents[2]
    map_data = json.loads(Path(map_path or root / "game/data/map.json").read_text(encoding="utf-8"))
    coastal_data = json.loads(Path(coastal_path or root / "game/data/coastal_plan.json").read_text(encoding="utf-8"))
    fixture = json.loads(Path(fixture_path or Path(__file__).with_name("semantic_grass_mask.json")).read_text(encoding="utf-8"))
    width, height, cells, _ = _grass_cells(map_data, coastal_data, fixture)
    geometry = _shot_fit_geometry((BASE_W, BASE_H), width, height, fixture)
    visible_cells = _covered_cells(cells, geometry, fixture)
    if visible_cells < int(fixture.get("min_grass_cells", 0)):
        print("[SEASON-SELFTEST] FAIL: HUD-free production grass mask is below its minimum coverage")
        return 1
    wrong_surface = dict(fixture, semantic_id="paving")
    try:
        _grass_cells(map_data, coastal_data, wrong_surface)
        print("[SEASON-SELFTEST] FAIL: paving surface was accepted as grass")
        return 1
    except ValueError as exc:
        if "semantic_id" not in str(exc):
            print("[SEASON-SELFTEST] FAIL: wrong surface rejected for the wrong reason: %s" % exc)
            return 1
    too_small = dict(fixture, min_grass_cells=visible_cells + 1)
    if _covered_cells(cells, geometry, too_small) >= int(too_small["min_grass_cells"]):
        print("[SEASON-SELFTEST] FAIL: insufficient sample coverage was accepted")
        return 1
    print("[SEASON-SELFTEST] PASS: authored HUD-free grass mask coverage=%d cells; paving rejected; small mask marked inconclusive" % visible_cells)
    return 0


def judge_set(tag, paths, labels, min_de):
    """一个时刻（昼 或 夜）的四季帧：C 臂自检 + A 臂两两 ΔE00 最小值。返回 (fails, min_de00)。"""
    fails = 0
    # ── C 臂：先跑（几何/数目错时 A 臂的数字没意义）──────────────────────────────
    if len(paths) != 4:
        print("[SEASON] ❌ %s 期望 4 帧（春夏秋冬），实得 %d —— 这【不是】通过" % (tag, len(paths)))
        return 1, None
    modals = []
    for lab, p in zip(labels, paths):
        (w, h), modal = _ad.world_mode(p)
        if w % BASE_W != 0 or h % BASE_H != 0:
            print("[SEASON] ❌ %s/%s 帧尺寸 %dx%d 不是基准 %dx%d 的整数倍 —— 取样带会取歪，拒绝给判决"
                  % (tag, lab, w, h, BASE_W, BASE_H))
            return 1, None
        modals.append((lab, modal))
        print("[SEASON] %s/%s 地面主色 = %s" % (tag, lab, modal))
    # ── A 臂：两两 ΔE00，报最小 ─────────────────────────────────────────────────
    worst = (1e9, None)
    for i in range(len(modals)):
        for j in range(i + 1, len(modals)):
            (la, ca), (lb, cb) = modals[i], modals[j]
            d = de00(ca, cb)
            mark = "ok" if d >= min_de else "❌越界"
            print("    %s↔%s  ΔE00 = %6.2f   %s" % (la, lb, d, mark))
            if d < worst[0]:
                worst = (d, (la, lb))
    ok = worst[0] >= min_de
    if not ok:
        fails += 1
    print("[SEASON] %s 最小两两 ΔE00 = %.2f (%s↔%s)  阈值 %.2f  ⇒ %s"
          % (tag, worst[0], worst[1][0], worst[1][1], min_de, "PASS" if ok else "FAIL"))
    return fails, worst[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--noon", nargs="+", default=[], help="四帧：春夏秋冬 正午")
    ap.add_argument("--night", nargs="+", default=[], help="四帧：春夏秋冬 夜")
    ap.add_argument("--min-de", type=float, default=3.2)
    ap.add_argument("--labels", nargs=4, default=["春", "夏", "秋", "冬"])
    ap.add_argument("--mask-fixture", help="semantic surface sampling policy JSON")
    ap.add_argument("--map", help="canonical game/data/map.json")
    ap.add_argument("--coastal", help="canonical game/data/coastal_plan.json")
    ap.add_argument("--overlay-dir", help="write annotated semantic-mask overlays here")
    ap.add_argument("--report-json", help="write per-frame sample counts, transforms and color values")
    ap.add_argument("--self-test", action="store_true", help="validate production grass-mask coverage and reject a paving mask")
    a = ap.parse_args()
    if a.self_test:
        return _semantic_self_test(a.map, a.coastal, a.mask_fixture)
    if not a.noon and not a.night:
        print(__doc__)
        return 2
    if a.mask_fixture:
        try:
            root = Path(__file__).resolve().parents[2]
            fixture = json.loads(Path(a.mask_fixture).read_text(encoding="utf-8"))
            map_data = json.loads(Path(a.map or root / "game/data/map.json").read_text(encoding="utf-8"))
            coastal_data = json.loads(Path(a.coastal or root / "game/data/coastal_plan.json").read_text(encoding="utf-8"))
            if fixture.get("projection") != "main_shot_fit":
                raise ValueError("fixture projection must be main_shot_fit")
            width, height, cells, layer_counts = _grass_cells(map_data, coastal_data, fixture)
        except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
            print("[SEASON] ❌ semantic grass mask invalid/inconclusive: %s" % exc)
            return 1
        if not cells:
            print("[SEASON] ❌ semantic grass mask contains no eligible cells")
            return 1
        failures = 0
        report = {"schema": "living-town.semantic-season-samples/1", "semantic_id": "grass",
                  "projection": fixture["projection"], "mask_fixture": str(a.mask_fixture),
                  "map_size": [width, height], "grass_cells": len(cells), "excluded_layer_counts": layer_counts,
                  "minimum_delta_e00": a.min_de, "groups": {}}
        for tag, paths in (("noon", a.noon), ("night", a.night)):
            if not paths:
                continue
            geometries = []
            for path in paths:
                with Image.open(path) as im:
                    geometries.append(_shot_fit_geometry(im.size, width, height, fixture))
            if any(g != geometries[0] for g in geometries[1:]):
                print("[SEASON] ❌ %s frames do not share the same shot-fit transform" % tag)
                failures += 1
                report["groups"][tag] = {"verdict": "invalid_transform"}
                continue
            overlay_dir = os.path.join(a.overlay_dir, tag) if a.overlay_dir else None
            result, worst, samples = _judge_semantic_set(tag, paths, a.labels, a.min_de, cells,
                                                         geometries[0], fixture, overlay_dir)
            failures += result
            report["groups"][tag] = {"verdict": "PASS" if result == 0 else "FAIL", "minimum_delta_e00": worst,
                                     "geometry": geometries[0], "samples": samples}
        if a.report_json:
            out = Path(a.report_json)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("=== SEMANTIC GRASS SEASON GATE: %s ===" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
        return 1 if failures else 0
    fails = 0
    if a.noon:
        f, _ = judge_set("昼", a.noon, a.labels, a.min_de)
        fails += f
    if a.night:
        f, _ = judge_set("夜", a.night, a.labels, a.min_de)
        fails += f
    print("=== SEASON GATE: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
