"""Check the four Mill Court room plans without Blender or engine dependencies.

This is a bounded design validator: exact rectangular overlaps and hinged-door
sectors, clearance ribbons, pulled-chair envelopes, and 56cm disc routes on a
4cm grid. It does not certify real-world building regulations or game collision.
"""

from pathlib import Path
import argparse
import copy
import heapq
import json
import math

DEFAULT_PLAN = (
    Path(__file__).resolve().parents[1]
    / "art/planning_revision/mill_court/v1/floorplans.json"
)


def area(poly):
    return (
        abs(sum((a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))))
        / 2
    )


def overlap(a, b):
    return max(0.0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0.0, min(a[3], b[3]) - max(a[1], b[1])
    )


def inside(p, poly):
    hit = False
    for a, b in zip(poly, poly[1:] + poly[:1]):
        dx, dy = (b[0] - a[0], b[1] - a[1])
        ll = dx * dx + dy * dy
        t = (
            max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ll))
            if ll
            else 0.0
        )
        if math.dist(p, [a[0] + t * dx, a[1] + t * dy]) < 1e-08:
            return True
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < a[0] + (p[1] - a[1]) * dx / dy:
            hit = not hit
    return hit


def distrect(p, b):
    return math.hypot(
        max(b[0] - p[0], 0.0, p[0] - b[2]), max(b[1] - p[1], 0.0, p[1] - b[3])
    )


def segment_rect_distance(a, b, r):
    if (
        r[0] <= a[0] <= r[2]
        and r[1] <= a[1] <= r[3]
        or (r[0] <= b[0] <= r[2] and r[1] <= b[1] <= r[3])
    ):
        return 0.0
    corners = [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]
    dx, dy = (b[0] - a[0], b[1] - a[1])
    ll = dx * dx + dy * dy
    candidates = [distrect(a, r), distrect(b, r)]
    for q in corners:
        t = (
            max(0.0, min(1.0, ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / ll))
            if ll
            else 0.0
        )
        candidates.append(math.dist(q, (a[0] + t * dx, a[1] + t * dy)))
    for c, d in zip(corners, corners[1:] + corners[:1]):
        bx, by = (d[0] - c[0], d[1] - c[1])
        det = dx * by - dy * bx
        if abs(det) > 1e-10:
            cx, cy = (c[0] - a[0], c[1] - a[1])
            t = (cx * by - cy * bx) / det
            u = (cx * dy - cy * dx) / det
            if 0 <= t <= 1 and 0 <= u <= 1:
                return 0.0
    return min(candidates)


def walls_for(p):
    rows = []
    W = p["clear_width_m"]
    H = p["clear_depth_m"]
    ext = {"S": (0, W, -0.3, 0), "N": (0, W, H, H + 0.3)}
    for side in ("S", "N"):
        holes = []
        for d in p["doors"]:
            if d.get("external") and side == "S":
                holes.append(
                    (W / 2 - d["clear_width_m"] / 2, W / 2 + d["clear_width_m"] / 2)
                )
        start, end, y0, y1 = ext[side]
        cursor = start
        for a, b in sorted(holes):
            if a > cursor:
                rows.append(
                    dict(id="ext_" + side, bounds_m=[cursor, y0, a, y1], exterior=True)
                )
            cursor = b
        if cursor < end:
            rows.append(
                dict(id="ext_" + side, bounds_m=[cursor, y0, end, y1], exterior=True)
            )
    rows += [
        dict(id="ext_W", bounds_m=[-0.3, -0.3, 0, H + 0.3], exterior=True),
        dict(id="ext_E", bounds_m=[W, -0.3, W + 0.3, H + 0.3], exterior=True),
    ]
    for w in p["walls"]:
        cursor = w["start_m"]
        spans = []
        for d in sorted(w["openings"], key=lambda q: q["start_m"]):
            if d["start_m"] > cursor:
                spans.append((cursor, d["start_m"]))
            cursor = d["end_m"]
        if cursor < w["end_m"]:
            spans.append((cursor, w["end_m"]))
        for a, b in spans:
            q = (
                [a, w["at_m"], b, w["at_m"] + w["thickness_m"]]
                if w["axis"] == "horizontal"
                else [w["at_m"], a, w["at_m"] + w["thickness_m"], b]
            )
            rows.append(dict(id=w["id"], bounds_m=q, exterior=False))
    return rows


def swing_hit(d, b):
    h = d["hinge_xy_m"]
    u = d["closed_unit_vector"]
    v = d["open_unit_vector"]
    pts = [(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])]
    xs = [sum(((p[i] - h[i]) * u[i] for i in range(2))) for p in pts]
    ys = [sum(((p[i] - h[i]) * v[i] for i in range(2))) for p in pts]
    lo0 = max(0, min(xs))
    lo1 = max(0, min(ys))
    return (
        max(xs) > lo0 + 1e-08
        and max(ys) > lo1 + 1e-08
        and (lo0 * lo0 + lo1 * lo1 < d["clear_width_m"] ** 2 - 1e-08)
    )


def pathfind(start, target, W, H, obstacles, radius=0.28, step=0.04):
    grid = lambda p: (round(p[0] / step), round(p[1] / step))
    xy = lambda n: (n[0] * step, n[1] * step)
    s, t = (grid(start), grid(target))
    cache = {}

    def free(n):
        if n in cache:
            return cache[n]
        x, y = xy(n)
        ok = (
            radius - 1e-08 <= x <= W - radius + 1e-08
            and radius - 1e-08 <= y <= H - radius + 1e-08
            and all((distrect((x, y), b) >= radius - 1e-08 for b in obstacles))
        )
        cache[n] = ok
        return ok

    if not free(s) or not free(t):
        return None
    queue = [(math.dist(s, t), 0, s)]
    best = {s: 0}
    previous = {}
    visited = 0
    while queue:
        _, g, n = heapq.heappop(queue)
        if g != best[n]:
            continue
        visited += 1
        if n == t:
            out = []
            while n != s:
                out.append(xy(n))
                n = previous[n]
            out.append(xy(s))
            return dict(length_m=g * step, path_m=out[::-1], visited=visited)
        for dx, dy in (
            (1, 0),
            (-1, 0),
            (0, 1),
            (0, -1),
            (1, 1),
            (-1, 1),
            (1, -1),
            (-1, -1),
        ):
            m = (n[0] + dx, n[1] + dy)
            if not free(m) or (
                dx
                and dy
                and (not free((n[0] + dx, n[1])) or not free((n[0], n[1] + dy)))
            ):
                continue
            ng = g + math.hypot(dx, dy)
            if ng < best.get(m, 1000000000.0):
                best[m] = ng
                previous[m] = n
                heapq.heappush(queue, (ng + math.dist(m, t), ng, m))
    return None


TARGETS = {
    "A_Ground": {
        "stair": [0.5, 0.45],
        "kitchen": [3.3, 3.8],
        "dining": [3.55, 2.55],
        "sofa": [4.15, 1.35],
        "pantry": [0.85, 4.4],
    },
    "A_Upper": {
        "bath": [1.6, 1.7],
        "shower": [1.25, 0.45],
        "wc": [2.15, 0.925],
        "bed_w": [3.1, 1.3],
        "bed_e": [5.1, 1.3],
        "wardrobe": [3.3, 3.85],
        "desk": [4.55, 2.7],
    },
    "B_Ground": {
        "stair": [0.5, 0.45],
        "kitchen": [5.0, 3.8],
        "dining": [3.2, 2.9],
        "dining_chair1": [1.6, 1.0],
        "dining_chair2": [2.3, 1.0],
        "sofa": [6.18, 1.7],
        "wc": [1.25, 4.45],
        "basin": [1.95, 4.6],
        "washer": [2.2, 3.7],
    },
    "B_Upper": {
        "bath": [2.5, 3.1],
        "shower": [1.65, 3.05],
        "wc": [2.65, 3.0],
        "child_bed": [2.3, 1.35],
        "child_wardrobe": [3.55, 0.75],
        "primary_w": [4.95, 1.35],
        "primary_e": [7.05, 1.35],
        "wardrobe": [5.3, 3.85],
        "desk": [6.5, 2.7],
    },
}


def validate(floorplans):
    """Return the measured report; never modify the input plan."""
    D = copy.deepcopy(floorplans)
    fail = []
    reports = []
    stairs_by_owner = {}
    for shared in D["stairs"]:
        if shared["owner_id"] in stairs_by_owner:
            fail.append([shared["owner_id"], "duplicate_shared_stair", shared["id"]])
        stairs_by_owner[shared["owner_id"]] = {
            key: value for key, value in shared.items() if key != "owner_id"
        }
    for p in D["plans"]:
        id = p["id"]
        W, H = (p["clear_width_m"], p["clear_depth_m"])
        f = p["furniture"]
        solids = [x for x in f if not x.get("host_surface_id")]
        wallrows = walls_for(p)
        if p["wall_segments"] != wallrows:
            fail.append([id, "stale_serialized_wall_segments"])
        if p["stair"] != stairs_by_owner.get(p["owner_id"]):
            fail.append([id, "shared_stair_mismatch"])
        slab = p["floor_slab"]
        expected_void = p["stair"]["opening_bounds_m"] if p["level_index"] else None
        if (
            slab["opening_bounds_m"] != expected_void
            or p.get("stair_void_bounds_m") != expected_void
        ):
            fail.append([id, "slab_stair_opening_mismatch"])
        if (
            abs(slab["top_world_Z_m"] - p["FF_world_m"]) > 1e-9
            or abs(slab["top_world_Z_m"] - slab["bottom_world_Z_m"] - D["floor_slab_m"])
            > 1e-9
        ):
            fail.append([id, "slab_elevation_or_thickness"])
        for d in p["doors"]:
            if abs(d["rough_opening_width_m"] - d["clear_width_m"] - 0.1) > 1e-9:
                fail.append([id, "door_rough_opening_width", d["id"]])
            if d["leaf_thickness_m"] != 0.04:
                fail.append([id, "door_leaf_thickness", d["id"]])
        for x in solids:
            b = x["bounds_m"]
            corners = [(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])]
            if not any(
                (all((inside(q, r["polygon_m"]) for q in corners)) for r in p["rooms"])
            ):
                fail.append([id, "furniture_not_contained_in_room", x["id"]])
            for w in wallrows:
                if overlap(b, w["bounds_m"]) > 1e-08:
                    fail.append([id, "furniture_wall", x["id"], w["id"]])
        for i, a in enumerate(solids):
            for b in solids[i + 1 :]:
                if overlap(a["bounds_m"], b["bounds_m"]) > 1e-08:
                    fail.append([id, "solid_furniture_overlap", a["id"], b["id"]])
        for d in p["doors"]:
            if d["kind"] == "hinged":
                for x in solids:
                    if swing_hit(d, x["bounds_m"]):
                        fail.append([id, "door_swing_furniture", d["id"], x["id"]])
            elif d["kind"] == "pocket":
                # Test the full closed-to-retracted leaf sweep against junctions,
                # excluding only the host partition's explicitly hollow pocket.
                start = min(d["start_m"], *d["pocket_extent_m"])
                end = max(d["end_m"], *d["pocket_extent_m"])
                side_a = d["at_m"] - d["leaf_thickness_m"] / 2
                side_b = d["at_m"] + d["leaf_thickness_m"] / 2
                sweep = (
                    [side_a, start, side_b, end]
                    if d["opening_axis"] == "vertical"
                    else [start, side_a, end, side_b]
                )
                hosts = {
                    wall["id"]
                    for wall in p["walls"]
                    if any(
                        opening["door_id"] == d["id"] for opening in wall["openings"]
                    )
                }
                if (
                    len(hosts) != 1
                    or abs(d["pocket_extent_m"][1] - d["pocket_extent_m"][0])
                    < d["clear_width_m"]
                ):
                    fail.append([id, "pocket_host_or_travel", d["id"]])
                for wall in wallrows:
                    if (
                        wall["id"] not in hosts
                        and overlap(sweep, wall["bounds_m"]) > 1e-8
                    ):
                        fail.append([id, "pocket_sweep_wall", d["id"], wall["id"]])
                for furniture in solids:
                    if overlap(sweep, furniture["bounds_m"]) > 1e-8:
                        fail.append(
                            [id, "pocket_sweep_furniture", d["id"], furniture["id"]]
                        )
        for z in p["clearance_zones"]:
            b = z["bounds_m"]
            measured = b[2] - b[0] if z["clearance_axis"] == "x" else b[3] - b[1]
            if measured < z["minimum_clear_m"] - 1e-9:
                fail.append([id, "clearance_dimension", z["id"]])
            for x in solids:
                if overlap(z["bounds_m"], x["bounds_m"]) > 1e-08:
                    fail.append([id, "clearance_solid", z["id"], x["id"]])
            for w in wallrows:
                if overlap(z["bounds_m"], w["bounds_m"]) > 1e-08:
                    fail.append([id, "clearance_wall", z["id"], w["id"]])
        for x in solids:
            if "pullback_bounds_m" not in x:
                continue
            for y in solids:
                if (
                    x is not y
                    and overlap(x["pullback_bounds_m"], y["bounds_m"]) > 1e-08
                ):
                    fail.append([id, "chair_pullback_solid", x["id"], y["id"]])
        for route in p["circulation"]:
            radius = route["clear_width_m"] / 2
            obstacles = (
                [(x["id"], x["bounds_m"]) for x in solids]
                + [(w["id"], w["bounds_m"]) for w in wallrows if not w["exterior"]]
                + [
                    (
                        "stair_run_or_void",
                        p.get("stair_void_bounds_m", p["stair"]["run_bounds_m"]),
                    )
                ]
            )
            for a, b in zip(route["points_m"], route["points_m"][1:]):
                for name, box in obstacles:
                    if segment_rect_distance(a, b, box) < radius - 1e-07:
                        fail.append(
                            [id, "declared_circulation_ribbon", route["id"], name]
                        )
        stairs = p["stair"]
        if (
            abs(stairs["risers"] * stairs["riser_m"] - 2.7) >= 1e-12
            or abs(
                stairs["treads"] * stairs["tread_going_m"] - stairs["horizontal_run_m"]
            )
            >= 1e-12
        ):
            fail.append([id, "stair_rise_or_run"])
        if (
            min(
                stairs["top_landing_bounds_m"][3] - stairs["top_landing_bounds_m"][1],
                stairs["bottom_landing_bounds_m"][3]
                - stairs["bottom_landing_bounds_m"][1],
            )
            < 0.9 - 1e-10
        ):
            fail.append([id, "stair_landing_depth"])
        obs = (
            [w["bounds_m"] for w in wallrows if not w["exterior"]]
            + [x["bounds_m"] for x in solids]
            + [p.get("stair_void_bounds_m", stairs["run_bounds_m"])]
        )
        start = [W / 2, 1.3] if p["level_index"] == 0 else [0.5, 4.35]
        access = []
        for name, target in TARGETS[id].items():
            result = pathfind(start, target, W, H, obs)
            if result is None:
                fail.append([id, "access_unreachable", name, target])
            access.append(
                dict(
                    target=name,
                    xy_m=target,
                    reachable=result is not None,
                    length_m=result["length_m"] if result else None,
                )
            )
        triangle = None
        if "kitchen_triangle" in p:
            q = p["kitchen_triangle"]["points_m"]
            names = ["fridge", "sink", "hob"]
            lengths = [math.dist(q[names[i]], q[names[(i + 1) % 3]]) for i in range(3)]
            triangle = dict(edge_lengths_m=lengths, perimeter_m=sum(lengths))
            if min(lengths) < 1.2 or max(lengths) > 2.7:
                fail.append([id, "kitchen_triangle_length"])
        pulled = []
        for x in solids:
            b = list(x["bounds_m"])
            if "pullback_bounds_m" in x:
                pb = x["pullback_bounds_m"]
                v = x["facing"]
                distance = pb[2] - pb[0] if v[0] else pb[3] - pb[1]
                b = [
                    b[0] - v[0] * distance,
                    b[1] - v[1] * distance,
                    b[2] - v[0] * distance,
                    b[3] - v[1] * distance,
                ]
            pulled.append((x["id"], b))
        for route in p["circulation"]:
            for a, b in zip(route["points_m"], route["points_m"][1:]):
                for name, box in pulled:
                    if (
                        segment_rect_distance(a, b, box)
                        < route["clear_width_m"] / 2 - 1e-07
                    ):
                        fail.append(
                            [id, "pulled_chair_circulation_ribbon", route["id"], name]
                        )
        upper = next(
            q
            for q in D["plans"]
            if q["owner_id"] == p["owner_id"] and q["level_index"] == 1
        )
        ground = next(
            q
            for q in D["plans"]
            if q["owner_id"] == p["owner_id"] and q["level_index"] == 0
        )
        opening = upper["floor_slab"]["opening_bounds_m"]
        half_margin = (stairs["overall_width_m"] - stairs["clear_width_m"]) / 2
        left = stairs["run_bounds_m"][0] + half_margin
        right = left + stairs["clear_width_m"]
        headroom = []
        for i in range(stairs["treads"]):
            front = stairs["run_bounds_m"][1] + i * stairs["tread_going_m"]
            back = front + stairs["tread_going_m"]
            tread_z = ground["FF_world_m"] + (i + 1) * stairs["riser_m"]
            open_above = (
                opening is not None
                and opening[0] <= left + 1e-9
                and opening[2] >= right - 1e-9
                and opening[1] <= front + 1e-9
                and opening[3] >= back - 1e-9
            )
            overhead = (
                upper["FF_world_m"] + upper["clear_ceiling_height_m"]
                if open_above
                else upper["floor_slab"]["bottom_world_Z_m"]
            )
            headroom.append(overhead - tread_z)
        headroom.extend(
            [ground["clear_ceiling_height_m"], upper["clear_ceiling_height_m"]]
        )
        if min(headroom) < 2.5 - 1e-9:
            fail.append([id, "stair_headroom"])
        reports.append(
            dict(
                plan=id,
                minimum_computed_stair_headroom_m=min(headroom),
                all_declared_circulation_clear_with_chairs_pulled=not any(
                    row[0] == id and row[1] == "pulled_chair_circulation_ribbon"
                    for row in fail
                ),
                clear_floor_area_m2=W * H,
                room_areas_m2={r["id"]: area(r["polygon_m"]) for r in p["rooms"]},
                stair=stairs,
                kitchen_triangle=triangle,
                access_disc_diameter_m=0.56,
                access_step_m=0.04,
                access=access,
                explicit_clearance_zones=p["clearance_zones"],
            )
        )

    return {
        "status": "PASS" if not fail else "FAIL",
        "failures": fail,
        "plans": reports,
        "navigation_scope": "Design access only; doors traversable as needed. No native controller or legal certification.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional output JSON; plan input is never rewritten.",
    )
    args = parser.parse_args()
    report = validate(json.loads(args.plan.read_text(encoding="utf-8")))
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "status": report["status"],
                "plans": len(report["plans"]),
                "failures": report["failures"],
            }
        )
    )
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
