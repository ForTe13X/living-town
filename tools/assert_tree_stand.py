#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LT-04 forest sampling gate.

This host-side gate partitions every authored tree cell into a stable grove ID,
uses periodicity only for sufficiently large regions, and uses paired full/tree-free
screenshots to measure visible coverage for narrow groves. Tree-free captures must
share the same seed, tick, viewport, and camera as their full-scene partner.

The paired ledger explicitly records cells with low visibility due to frame clipping,
overlap, or later-rendered art/UI. Grove-level visibility floors and a calibrated
ceiling on partially visible cells reject missing groves and camera shifts without
pretending overlapping sprites can be attributed independently. See
`analysis/af2/forest_sample_policy.json` and the LT-04 release candidate receipt.

The legacy one-frame CLI remains available for older fixtures; CI uses the paired
mode described above.
"""
import argparse, hashlib, json, os, statistics, sys as _sys
# Windows 控制台默认 GBK，编不出 ✅ 会直接抛 UnicodeEncodeError——**判据全部算完之后**才炸，
# 于是门"通过了"却以 rc=1 收场。实测过：本门第一次接进 visual_gate.sh 就是这么红的
# （P 27.59/26.03 正午、13.90/13.12 夜间，全部远超 8.0，地色 8.4%/9.4% 远低于 22%，然后炸在打印那一行）。
# 与 tools/assert_no_weights.py 抬头同源。V3 明写过"本门从没在 visual_gate.sh 里跑过"——
# 这就是那句话的代价。
try:
    _sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass
import json
import sys
from collections import Counter
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw
except ImportError:
    print("[TREESTAND] 需要 Pillow（与另外两道视觉门同一个依赖）", file=sys.stderr)
    sys.exit(1)


# ── --shot-fit 的取景几何 ────────────────────────────────────────────────────
# docs/41 §6 盲区⑥：**不许按窗口尺寸算地图矩形**。canvas_items 拉伸下基准视口恒为 1280x768，
# zoom = min((1280,768) - HOME_PAD(120,240)) / (W*48, H*48)；本地图 64x48 => 528/2304
# => 1 格 = 11 基准像素、原点 (288,120)。实拍的帧再乘 实际宽/1280。
# 这两个数与 docs/69 §二 实测的室内 bbox 起点 (288,120) 逐字相符 —— 那是一次独立的交叉验证。
BASE_W, BASE_H = 1280.0, 768.0
PAD_X, PAD_Y = 120.0, 240.0
TILE_WORLD = 48.0


def geometry(im, map_w, map_h):
    zoom = min((BASE_W - PAD_X) / (map_w * TILE_WORLD), (BASE_H - PAD_Y) / (map_h * TILE_WORLD))
    tile = TILE_WORLD * zoom
    ox = BASE_W * 0.5 - map_w * TILE_WORLD * 0.5 * zoom
    oy = BASE_H * 0.5 - map_h * TILE_WORLD * 0.5 * zoom
    s = im.width / BASE_W
    return tile * s, ox * s, oy * s, s


def crop_tiles(im, g, tx, ty, tw, th):
    tile, ox, oy, _ = g
    return im.crop((int(round(ox + tx * tile)), int(round(oy + ty * tile)),
                    int(round(ox + (tx + tw) * tile)), int(round(oy + (ty + th) * tile))))


def periodicity(im, g, tx, ty, tw, th):
    """一格周期性残差：区域与它自己【平移恰好一格】的平均 |Δ|（RGB 再平均）。"""
    out = []
    for dx, dy in ((0, 1), (1, 0)):
        a = crop_tiles(im, g, tx, ty, tw - dx, th - dy)
        b = crop_tiles(im, g, tx + dx, ty + dy, tw - dx, th - dy)
        d = list(ImageChops.difference(a, b).getdata())
        out.append(sum(sum(t) for t in d) / (3.0 * len(d)))
    return out


def stands(trees):
    """Preserve the legacy x-run regions, but use their true authored y extent."""
    return [region["bounds"] for region in tree_regions(trees)]


def tree_regions(trees):
    """Partition every tree cell into stable x-contiguous regions and true bounds."""
    xs = sorted(set(x for x, _ in trees))
    ys = sorted(set(y for _, y in trees))
    blocks, cur = [], [xs[0]]
    for p, q in zip(xs, xs[1:]):
        if q == p + 1:
            cur.append(q)
        else:
            blocks.append(cur); cur = [q]
    blocks.append(cur)
    out = []
    for bx in blocks:
        cells = sorted((x, y) for x, y in trees if x in bx)
        by = [y for _, y in cells]
        x0, x1, y0, y1 = bx[0], bx[-1], min(by), max(by)
        out.append({"id": "grove_x%02d_%02d" % (x0, x1),
                    "bounds": (x0, y0, x1 - x0 + 1, y1 - y0 + 1),
                    "cells": cells, "row_count": len(set(by))})
    return out


def tree_cell_digest(trees):
    cells = sorted([[int(x), int(y)] for x, y in trees], key=lambda p: (p[1], p[0]))
    raw = json.dumps(cells, separators=(",", ":")).encode("ascii")
    return hashlib.sha256(raw).hexdigest()


def sprite_screen_geometry(im, g, policy, source_path):
    source = Image.open(source_path).convert("RGBA")
    alpha = source.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("tree sprite has no opaque source pixels")
    alpha = alpha.crop(bbox)
    src_w, src_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    fit = min(float(policy["sprite_world_width"]) / src_w,
              float(policy["sprite_max_height"]) / src_h)
    world_w, world_h = src_w * fit, src_h * fit
    tile, ox, oy, scale = g
    screen_w = world_w * tile / float(policy["tile_world"])
    screen_h = world_h * tile / float(policy["tile_world"])
    width, height = max(1, int(round(screen_w))), max(1, int(round(screen_h)))
    resized = alpha.resize((width, height), Image.Resampling.NEAREST)
    return {"alpha": resized, "width": width, "height": height,
            "source_bbox": list(bbox), "screen_size": [screen_w, screen_h],
            "scale": scale, "tile_px": tile, "origin_px": [ox, oy]}


def sprite_rect(cell, sprite):
    x, y = cell
    tile, (ox, oy) = sprite["tile_px"], sprite["origin_px"]
    # CoastalPlan.draw_landscape anchors each tree at ((x+.5), (y+1))*TILE
    # and sprite() aligns the opaque texture region to that foot point.
    foot_x, foot_y = ox + (x + 0.5) * tile, oy + (y + 1.0) * tile
    left = int(round(foot_x - sprite["width"] * 0.5))
    top = int(round(foot_y - sprite["height"]))
    return left, top, left + sprite["width"], top + sprite["height"]


def _sample_sprite_coverage(cell, sprite, changed):
    rect = sprite_rect(cell, sprite)
    x0, y0, x1, y1 = rect
    fw, fh = changed.size
    cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(fw, x1), min(fh, y1)
    if cx1 <= cx0 or cy1 <= cy0:
        return {"rect": list(rect), "expected_pixels": 0, "changed_pixels": 0,
                "coverage_fraction": 0.0, "frame_clipped": True}
    expected = sprite["alpha"].crop((cx0 - x0, cy0 - y0, cx1 - x0, cy1 - y0))
    observed = changed.crop((cx0, cy0, cx1, cy1))
    alpha_values = expected.get_flattened_data() if hasattr(expected, "get_flattened_data") else expected.getdata()
    diff_values = observed.get_flattened_data() if hasattr(observed, "get_flattened_data") else observed.getdata()
    expected_n = sum(1 for value in alpha_values if value > 0)
    changed_n = sum(1 for alpha_value, diff_value in zip(alpha_values, diff_values)
                    if alpha_value > 0 and diff_value > 0)
    return {"rect": list(rect), "expected_pixels": expected_n, "changed_pixels": changed_n,
            "coverage_fraction": changed_n / float(expected_n) if expected_n else 0.0,
            "frame_clipped": x0 < 0 or y0 < 0 or x1 > fw or y1 > fh}


def paired_grove_gate(frame_path, tree_free_path, map_path, policy_path, overlay_dir=None, report_path=None):
    m = json.load(open(map_path, encoding="utf-8"))
    policy = json.load(open(policy_path, encoding="utf-8"))
    trees = [tuple(map(int, c[:2])) for c in m.get("trees", []) if isinstance(c, list) and len(c) >= 2]
    if not trees:
        raise ValueError("map.json contains no authored tree cells")
    fw, fh = int(m["width"]), int(m["height"])
    full = Image.open(frame_path).convert("RGB")
    tree_free = Image.open(tree_free_path).convert("RGB")
    if full.size != tree_free.size:
        raise ValueError("full and --draw-skip trees frames have different dimensions")
    if policy.get("schema") != "living-town.forest-sample-policy/1":
        raise ValueError("forest policy schema mismatch")
    if policy.get("projection") != "main_shot_fit" or policy.get("design_viewport") != [int(BASE_W), int(BASE_H)]:
        raise ValueError("forest policy projection/viewport mismatch")
    if len(trees) != int(policy.get("expected_tree_cells", -1)) or tree_cell_digest(trees) != policy.get("expected_tree_cells_sha256"):
        raise ValueError("authored tree inventory differs from the approved grove fixture (count/digest mismatch)")
    g = geometry(full, fw, fh)
    sprite = sprite_screen_geometry(full, g, policy, policy["tree_sprite"])
    diff = ImageChops.difference(full, tree_free)
    channels = diff.split()
    max_diff = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    changed = max_diff.point(lambda value: 255 if value >= int(policy.get("diff_channel_threshold", 3)) else 0)
    regions = tree_regions(trees)
    fails, ledger_rows = [], []
    overlay = Image.new("RGBA", full.size, (0, 0, 0, 0)) if overlay_dir else None
    draw = ImageDraw.Draw(overlay) if overlay is not None else None
    if overlay is not None:
        highlight = Image.new("RGBA", full.size, (230, 35, 75, 0))
        highlight.putalpha(changed.point(lambda value: 95 if value else 0))
        overlay = Image.alpha_composite(overlay, highlight)
        draw = ImageDraw.Draw(overlay)
    min_tree_pixels = int(policy["per_tree_min_diff_pixels"])
    min_tree_fraction = float(policy["per_tree_min_diff_fraction"])
    min_small_pixels = int(policy["small_grove_min_visible_pixels"])
    min_grove_pixels = int(policy["grove_min_visible_pixels"])
    for region in regions:
        rid = region["id"]
        bx, by, bw, bh = region["bounds"]
        tx, ty, tw, th = bx + 1, by + 1, bw - 2, bh - 2
        reg = crop_tiles(full, g, tx, ty, max(0, tw), max(0, th)) if tw > 0 and th > 0 else Image.new("RGB", (0, 0))
        sample_pixels = reg.width * reg.height
        periodic_applicable = (len(region["cells"]) >= int(policy["periodicity_min_tree_cells"])
                               and tw >= 2 and th >= 2
                               and sample_pixels >= int(policy["periodicity_min_samples"]))
        cell_rows = []
        for cell in region["cells"]:
            sample = _sample_sprite_coverage(cell, sprite, changed)
            sample.update({"cell": [cell[0], cell[1]]})
            observed = (sample["changed_pixels"] >= min_tree_pixels and
                        sample["coverage_fraction"] >= min_tree_fraction)
            sample["status"] = "visible" if observed else "partially_obscured_or_clipped"
            sample["occlusion_note"] = ("frame edge clips authored sprite" if sample["frame_clipped"] else
                "sprite pixels overlap later-rendered art or UI; cell-level attribution is inconclusive")
            cell_rows.append(sample)
            if draw is not None:
                x0, y0, x1, y1 = sample["rect"]
                color = (68, 235, 123, 230) if observed else (255, 190, 55, 245)
                draw.rectangle((x0, y0, x1 - 1, y1 - 1), outline=color, width=1)
        x0, y0, x1, y1 = (round(g[1] + bx * g[0]), round(g[2] + by * g[0]),
                          round(g[1] + (bx + bw) * g[0]), round(g[2] + (by + bh) * g[0]))
        region_diff = changed.crop((max(0, x0), max(0, y0), min(full.width, x1), min(full.height, y1))) if x1 > x0 and y1 > y0 else Image.new("L", (0, 0))
        visible_pixels = sum(1 for value in (region_diff.get_flattened_data() if hasattr(region_diff, "get_flattened_data") else region_diff.getdata()) if value > 0)
        if periodic_applicable:
            pv, ph = periodicity(full, g, tx, ty, tw, th)
            periodicity_ok = pv >= float(policy["periodicity_min_p"]) and ph >= float(policy["periodicity_min_p"])
            grove_pixels_ok = visible_pixels >= min_grove_pixels
            ground = ground_color(full, g, m, set(trees))
            gf = 0.0
            if ground is not None and sample_pixels:
                gf = sum(1 for px in reg.getdata() if px == ground[1]) / float(sample_pixels)
            if not periodicity_ok:
                fails.append("%s periodicity P=(%.3f,%.3f) below %.2f" % (rid, pv, ph, policy["periodicity_min_p"]))
            if gf > float(policy["max_ground_fraction"]):
                fails.append("%s tree-region ground fraction %.3f exceeds %.3f" % (rid, gf, policy["max_ground_fraction"]))
            if not grove_pixels_ok:
                fails.append("%s visible tree pixels %d < %d" % (rid, visible_pixels, min_grove_pixels))
            status = "periodicity_pass" if periodicity_ok and gf <= float(policy["max_ground_fraction"]) and grove_pixels_ok else "periodicity_fail"
            result = {"test": "large_region_periodicity", "sample_pixels": sample_pixels,
                      "p_vertical": pv, "p_horizontal": ph, "ground_fraction": gf,
                      "visible_tree_pixels": visible_pixels, "minimum_visible_tree_pixels": min_grove_pixels,
                      "partially_obscured_tree_cells": sum(1 for row in cell_rows if row["status"] != "visible"),
                      "status": status}
            print("[TREESTAND] %s periodicity bounds=(%d,%d %dx%d) pixels=%d P=(%.3f,%.3f) ground=%.3f %s" %
                  (rid, bx, by, bw, bh, sample_pixels, pv, ph, gf, status))
        else:
            required_pixels = max(min_small_pixels, min_grove_pixels)
            status = "small_grove_coverage_pass" if visible_pixels >= required_pixels else "unresolved_small_grove_coverage"
            if visible_pixels < required_pixels:
                fails.append("%s small-grove visible tree pixels %d < %d" % (rid, visible_pixels, required_pixels))
            result = {"test": "small_grove_shape_coverage", "sample_pixels": sample_pixels,
                      "visible_tree_pixels": visible_pixels, "minimum_visible_tree_pixels": required_pixels,
                      "partially_obscured_tree_cells": sum(1 for row in cell_rows if row["status"] != "visible"),
                      "status": status}
            print("[TREESTAND] %s small-grove bounds=(%d,%d %dx%d) anchors=%d visible_pixels=%d minimum=%d %s" %
                  (rid, bx, by, bw, bh, len(region["cells"]), visible_pixels, required_pixels, status))
        if draw is not None:
            draw.rectangle((x0, y0, x1, y1), outline=(70, 220, 250, 210), width=1)
            draw.text((x0 + 2, max(0, y0 - 11)), rid + (" *" if status.endswith("fail") or status.startswith("unresolved") else ""), fill=(255, 255, 255, 255))
        ledger_rows.append({"grove_id": rid, "bounds_cells": [bx, by, bw, bh],
                            "row_count": region["row_count"], "tree_cells": len(region["cells"]),
                            "test": result, "tree_cells_evidence": cell_rows})
    if overlay is not None:
        Path(overlay_dir).mkdir(parents=True, exist_ok=True)
        out = Image.alpha_composite(full.convert("RGBA"), overlay)
        out.save(os.path.join(overlay_dir, "grove-coverage.png"))
    report = {"schema": "living-town.grove-coverage-ledger/1", "projection": policy["projection"],
              "frame": str(frame_path), "tree_free_frame": str(tree_free_path),
              "map": str(map_path), "policy": str(policy_path), "map_size": [fw, fh],
              "frame_size": list(full.size), "geometry": {"tile_px": g[0], "origin_px": [g[1], g[2]],
              "scale": g[3], "tree_sprite_screen_px": [sprite["width"], sprite["height"]]},
              "tree_count": len(trees), "tree_sha256": tree_cell_digest(trees),
              "tree_pass_changed_pixels": sum(1 for value in (changed.get_flattened_data() if hasattr(changed, "get_flattened_data") else changed.getdata()) if value > 0),
              "regions": ledger_rows, "failures": fails, "verdict": "PASS" if not fails else "FAIL"}
    occluded_cells = sum(1 for region in ledger_rows for row in region["tree_cells_evidence"] if row["status"] != "visible")
    max_occluded_cells = int(policy["max_occluded_tree_cells"])
    if occluded_cells > max_occluded_cells:
        fails.append("camera/occlusion coverage has %d partially visible tree cells > policy maximum %d" %
                     (occluded_cells, max_occluded_cells))
        report["verdict"] = "FAIL"
        report["failures"] = fails
    report["visibility_accounting"] = {
        "occluded_or_clipped_tree_cells": occluded_cells,
        "maximum_occluded_tree_cells": max_occluded_cells,
        "note": "Per-cell low coverage is recorded; grove-level coverage is used where sprites overlap or later layers/UI obscure pixels. Frame clipping is flagged per cell."
    }
    if report_path:
        Path(report_path).parent.mkdir(parents=True, exist_ok=True)
        Path(report_path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("=== TREESTAND PAIRED GROVE GATE: %s (%d findings; %d cells partially obscured/clipped) ===" %
          (report["verdict"], len(report["failures"]), report["visibility_accounting"]["occluded_or_clipped_tree_cells"]))
    for failure in fails[:20]:
        print("[TREESTAND] ❌ " + failure)
    return 0 if not fails else 1


def self_test(policy_path):
    policy = json.load(open(policy_path, encoding="utf-8"))
    cells = [tuple(map(int, c)) for c in json.load(open("game/data/map.json", encoding="utf-8"))["trees"]]
    regions = tree_regions(cells)
    flattened = [cell for region in regions for cell in region["cells"]]
    if len(flattened) != len(set(flattened)) or set(flattened) != set(cells):
        print("[TREESTAND-SELFTEST] FAIL: grove inventory does not partition every authored tree exactly once")
        return 1
    region10 = next((r for r in regions if r["id"] == "grove_x51_53"), None)
    if region10 is None or region10["bounds"] != (51, 4, 3, 33) or region10["row_count"] != 9:
        print("[TREESTAND-SELFTEST] FAIL: sparse-row bounds did not preserve the 847-pixel source case")
        return 1
    if tree_cell_digest(cells) != policy.get("expected_tree_cells_sha256"):
        print("[TREESTAND-SELFTEST] FAIL: removed-grove tree inventory mutant was not rejected")
        return 1
    missing = [cell for cell in cells if cell not in regions[-1]["cells"]]
    if tree_cell_digest(missing) == policy.get("expected_tree_cells_sha256"):
        print("[TREESTAND-SELFTEST] FAIL: grove-removal mutant preserved the inventory digest")
        return 1
    rows = ["".join("#" if (x % 11) < 4 else "." for x in range(96)) for _ in range(88)]
    tiled = Image.new("RGB", (96, 88))
    px = tiled.load()
    for y in range(88):
        for x in range(96):
            v = 255 if (x % 11) < 4 else 0
            px[x, y] = (v, v, v)
    p = periodicity(tiled, (11.0, 0.0, 0.0, 1.0), 1, 1, 7, 6)
    if max(p) > 0.01:
        print("[TREESTAND-SELFTEST] FAIL: repeated one-cell stamp mutant was not detected")
        return 1
    left, top, _, _ = sprite_rect((51, 36), {"tile_px": 11.0, "origin_px": [288.0, 120.0], "width": 29, "height": 27})
    moved_left, moved_top, _, _ = sprite_rect((51, 36), {"tile_px": 11.0, "origin_px": [266.0, 98.0], "width": 29, "height": 27})
    if (moved_left, moved_top) != (left - 22, top - 22):
        print("[TREESTAND-SELFTEST] FAIL: camera-origin shift did not translate grove samples")
        return 1
    clipped = _sample_sprite_coverage((0, 0), {"tile_px": 10.0, "origin_px": [-10.0, -10.0],
        "width": 8, "height": 8, "alpha": Image.new("L", (8, 8), 255)}, Image.new("L", (10, 10), 255))
    if not clipped["frame_clipped"] or clipped["expected_pixels"] >= 64:
        print("[TREESTAND-SELFTEST] FAIL: clipped grove evidence was not explicitly bounded")
        return 1
    print("[TREESTAND-SELFTEST] PASS: exact grove partition, sparse 847-pixel bounds, removed-grove digest, repeated-stamp, camera-shift, and clipped-frame controls")
    return 0


def ground_color(im, g, m, occupied):
    """从同一帧里现取「地面色」：在 authored 空地上找**最均匀**的一块，取它的众数色。

    不写死颜色的理由与 R2/S3 一样：色值的真源在 `WorldView.gd`，抄进判据文件等于立第二个副本。
    这里更进一步 —— 四季/昼夜/天气都会乘这个色，写死的任何值都活不过一次换季。
    """
    best = None
    K = 3
    for ty in range(0, int(m["height"]) - K):
        for tx in range(0, int(m["width"]) - K):
            if any((tx + i, ty + j) in occupied for i in range(K) for j in range(K)):
                continue
            c = crop_tiles(im, g, tx, ty, K, K)
            cnt = Counter(c.getdata())
            top, n = cnt.most_common(1)[0]
            frac = n / float(c.width * c.height)
            if best is None or frac > best[0]:
                best = (frac, top, (tx, ty))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frame")
    ap.add_argument("--map", default="game/data/map.json")
    ap.add_argument("--tree-free-frame", help="same capture with --draw-skip trees; isolates visible tree pixels")
    ap.add_argument("--policy", default="analysis/af2/forest_sample_policy.json")
    ap.add_argument("--overlay-dir")
    ap.add_argument("--report-json")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--min-p", type=float, default=8.0)
    ap.add_argument("--max-ground", type=float, default=0.22)
    ap.add_argument("--min-samples", type=int, default=2000)
    a = ap.parse_args()

    if a.self_test:
        return self_test(a.policy)
    if not a.frame:
        ap.error("--frame is required unless --self-test is used")
    if a.tree_free_frame:
        try:
            return paired_grove_gate(a.frame, a.tree_free_frame, a.map, a.policy, a.overlay_dir, a.report_json)
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
            print("[TREESTAND] ❌ paired grove sample invalid/inconclusive: %s" % exc)
            return 1

    m = json.load(open(a.map, encoding="utf-8"))
    trees = [tuple(c) for c in m.get("trees", [])]
    im = Image.open(a.frame).convert("RGB")
    g = geometry(im, int(m["width"]), int(m["height"]))
    errs, notes = [], []

    # ── C 臂：采样自检（先跑；几何算错时另外两条臂的数字没有意义）─────────────
    # 防的是最难看的那种失效：取景公式错 => 采样点全落在别处 => 门照常全绿。
    # R2 的自证④是同一件事，只是它量的是"墙面采样点有几个"。
    if im.width % int(BASE_W) != 0 or im.height % int(BASE_H) != 0:
        errs.append("帧尺寸 %dx%d 不是基准 1280x768 的整数倍 —— 取景公式不适用，拒绝给判决"
                    % (im.width, im.height))
    if not trees:
        errs.append("map.json 里一棵 authored 树都没有 —— 本门的输入没了，这【不是】通过")
    if errs:
        for e in errs:
            print("[TREESTAND] ❌ " + e)
        return 1

    occupied = set(trees)
    for aid, ar in m.get("areas", {}).items():
        r = ar.get("rect", [0, 0, 0, 0])
        for i in range(int(r[2])):
            for j in range(int(r[3])):
                occupied.add((int(r[0]) + i, int(r[1]) + j))
    for key in ("water", "walls", "blockers"):
        for c in m.get(key, []):
            occupied.add((int(c[0]), int(c[1])))

    gc = ground_color(im, g, m, occupied)
    if gc is None:
        errs.append("找不到任何一块 3x3 的 authored 空地 —— B 臂无从标定")
    else:
        print("[TREESTAND] 地面参考色 = #%02x%02x%02x（取自空地格 %s，块内占比 %.1f%%）"
              % (gc[1][0], gc[1][1], gc[1][2], gc[2], 100 * gc[0]))

    for bi, (bx, by, bw, bh) in enumerate(stands(trees), 1):
        if bw < 4 or bh < 4:
            errs.append("林块%d 只有 %dx%d 格，没有双向内部样本；small-grove coverage 未提供" % (bi, bw, bh))
            continue
        tx, ty, tw, th = bx + 1, by + 1, bw - 2, bh - 2
        if tw < 2 or th < 2:
            errs.append("林块%d 内部只有 %dx%d 格，不能判双向周期；small-grove coverage 未提供" % (bi, tw, th))
            continue
        reg = crop_tiles(im, g, tx, ty, tw, th)
        npx = reg.width * reg.height
        if npx < a.min_samples:
            errs.append("林块%d 内部采样点只有 %d（< %d）—— 取景可能算错" % (bi, npx, a.min_samples))
            continue
        pv, ph = periodicity(im, g, tx, ty, tw, th)
        gf = 0.0
        if gc is not None:
            gf = sum(1 for p in reg.getdata() if p == gc[1]) / float(npx)
        print("[TREESTAND] 林块%d 格(%d,%d %dx%d) 内部(%dx%d, %d px)  P竖=%6.3f P横=%6.3f  地面色占比=%.1f%%"
              % (bi, bx, by, bw, bh, tw, th, npx, pv, ph, 100 * gf))
        if pv < a.min_p:
            errs.append("林块%d 竖向周期残差 P=%.3f < %.2f —— 这片林子是【逐格盖章】的" % (bi, pv, a.min_p))
        if ph < a.min_p:
            errs.append("林块%d 横向周期残差 P=%.3f < %.2f —— 这片林子是【逐格盖章】的" % (bi, ph, a.min_p))
        if gc is not None and gf > a.max_ground:
            errs.append("林块%d 露出的地面色占 %.1f%% > %.1f%% —— 点阵是拆了，树也拆没了"
                        % (bi, 100 * gf, 100 * a.max_ground))

    for n in notes:
        print("[TREESTAND] ⚠️  " + n)
    if errs:
        for e in errs:
            print("[TREESTAND] ❌ " + e)
        print("[TREESTAND] ❌ 林相点阵门 FAIL（%d 条）" % len(errs))
        return 1
    print("[TREESTAND] ✅ 林相点阵门 PASS（P >= %.2f 且 地面色 <= %.0f%%）" % (a.min_p, 100 * a.max_ground))
    return 0


if __name__ == "__main__":
    sys.exit(main())
