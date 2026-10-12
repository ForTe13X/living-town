"""Deterministic, footprint-safe offline street plan for Living Town.

No bpy dependency. No game files are written. Source cell = 1.8 metres.
Execute directly to regenerate art/living_town/street_plan.json.
"""
from __future__ import annotations

import hashlib
import heapq
import json
import math
from pathlib import Path

S = 1.8
WIDTH = 1.4
CLEARANCE = 0.72
ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


def xy(cx, cy):
    return ((cx - 32) * S, (24 - cy) * S)


def cell_point(cell):
    return xy(cell[0] + 0.5, cell[1] + 0.5)


def source_rect(ident, ax, ay, w, h, **meta):
    x0, y1 = xy(ax, ay)
    x1, y0 = xy(ax + w, ay + h)
    return {"id": ident, "bounds_m": [x0, y0, x1, y1], **meta}


def footprints(data):
    out = []
    for name, area in data["areas"].items():
        if area["type"] != "plaza":
            out.append(source_rect("Main_" + name, *area["rect"], source="map.areas." + name))
    for lot in data["solid_lots"]:
        out.append(source_rect(lot["id"], *lot["pos"], *lot["footprint"],
                               source="map.solid_lots." + lot["id"]))
    # Root's separately declared exterior-only harbor proposal. Its source
    # 9x6 interior is NOT claimed to fit this small 2.8x3.0m boathouse.
    x, y = xy(57.1, 8.2)
    out.append({"id": "Harbor_Warehouse", "bounds_m": [x - 1.4, y - 1.5, x + 1.4, y + 1.5],
                "source": "offline_proposed.port_warehouse_exterior", "proposed": True})
    return out


def expanded(rect, margin=CLEARANCE):
    x0, y0, x1, y1 = rect["bounds_m"]
    return x0 - margin, y0 - margin, x1 + margin, y1 + margin


def point_in_rect(p, rect, margin=CLEARANCE):
    x0, y0, x1, y1 = expanded(rect, margin)
    return x0 - 1e-8 < p[0] < x1 + 1e-8 and y0 - 1e-8 < p[1] < y1 + 1e-8


def segment_intersects(p0, p1, rect, margin=CLEARANCE):
    """True for a positive-length crossing through the expanded rectangle."""
    bounds = expanded(rect, margin)
    lo, hi = 0.0, 1.0
    for axis in (0, 1):
        low, high = bounds[axis], bounds[axis + 2]
        delta = p1[axis] - p0[axis]
        if abs(delta) < 1e-12:
            if p0[axis] <= low + 1e-8 or p0[axis] >= high - 1e-8:
                return False
        else:
            t0, t1 = (low - p0[axis]) / delta, (high - p0[axis]) / delta
            if t0 > t1:
                t0, t1 = t1, t0
            lo, hi = max(lo, t0), min(hi, t1)
            if hi - lo <= 1e-9:
                return False
    return hi - lo > 1e-9


def endpoints(data):
    """Real source doors plus one explicitly proposed harbor model approach."""
    out = []
    for door in data["doors"]:
        name = door["name"]
        ax, ay, w, h = data["areas"][name]["rect"]
        dx, dy = door["pos"]
        north = door["face"] == "N"
        out.append({"id": "Main_" + name,
                    "outside_cell": [dx, ay - 1 if north else ay + h],
                    "boundary_m": list(xy(dx + 0.5, ay if north else ay + h)),
                    "source_door_cell": [dx, dy], "face": door["face"]})
    for lot in data["solid_lots"]:
        if "door" not in lot:
            continue
        ax, ay = lot["pos"]
        w, h = lot["footprint"]
        dx, dy = lot["door"]
        face = lot.get("face", "S")
        north = face == "N"
        out.append({"id": lot["id"],
                    "outside_cell": [dx, ay - 1 if north else ay + h],
                    "boundary_m": list(xy(dx + 0.5, ay if north else ay + h)),
                    "source_door_cell": [dx, dy], "face": face})
    x, y = xy(57.1, 8.2)
    out.append({"id": "Harbor_Warehouse", "outside_cell": [57, 9],
                "boundary_m": [x, y - 1.5], "source_door_cell": [57, 8],
                "face": "S", "proposed_exterior_only": True})
    return sorted(out, key=lambda a: a["id"])


def edge_key(a, b):
    return tuple(sorted((tuple(a), tuple(b))))


def astar(start, goal, free, network):
    if start not in free or goal not in free:
        raise ValueError(f"Street endpoint is not free: {start} -> {goal}")
    directions = ((1, 0), (0, 1), (-1, 0), (0, -1))
    initial = (start[0], start[1], -1)
    costs, parents = {initial: 0.0}, {}
    serial = 0
    heuristic = lambda c: (abs(c[0] - goal[0]) + abs(c[1] - goal[1])) * 0.42
    queue = [(heuristic(start), 0.0, serial, initial)]
    while queue:
        _, score, _, current = heapq.heappop(queue)
        if score > costs.get(current, math.inf) + 1e-9:
            continue
        at = current[:2]
        if at == goal:
            path = [at]
            while current in parents:
                current = parents[current]
                path.append(current[:2])
            return list(reversed(path))
        for heading, (dx, dy) in enumerate(directions):
            nxt = (at[0] + dx, at[1] + dy)
            if nxt not in free:
                continue
            state = (nxt[0], nxt[1], heading)
            step = 0.42 if edge_key(at, nxt) in network else 1.0
            turn = 0.10 if current[2] not in (-1, heading) else 0.0
            candidate = score + step + turn
            if candidate + 1e-9 < costs.get(state, math.inf):
                costs[state], parents[state] = candidate, current
                serial += 1
                heapq.heappush(queue, (candidate + heuristic(nxt), candidate, serial, state))
    raise ValueError(f"No street route: {start} -> {goal}")


def straight_network_segments(network):
    """Merge only collinear edges. Never smooth across an occupied corner."""
    horizontal, vertical = {}, {}
    for a, b in network:
        if a[1] == b[1]:
            horizontal.setdefault(a[1], []).append(min(a[0], b[0]))
        else:
            vertical.setdefault(a[0], []).append(min(a[1], b[1]))
    out = []
    for axis, rows in ((0, horizontal), (1, vertical)):
        for fixed, positions in sorted(rows.items()):
            positions = sorted(set(positions))
            first = last = positions[0]
            for pos in positions[1:] + [None]:
                if pos is not None and pos == last + 1:
                    last = pos
                    continue
                a, b = ((first, fixed), (last + 1, fixed)) if axis == 0 else ((fixed, first), (fixed, last + 1))
                out.append({"points": [list(cell_point(a)), list(cell_point(b))], "width": WIDTH,
                            "kind": "street", "grid_endpoints": [list(a), list(b)]})
                if pos is not None:
                    first = last = pos
    return out


def build_plan(data):
    rects = footprints(data)
    water = {tuple(a) for a in data.get("water", [])}
    free = {(x, y) for x in range(data["width"]) for y in range(data["height"])
            if (x, y) not in water and not any(point_in_rect(cell_point((x, y)), r) for r in rects)}
    start = (32, 24)
    network, routes = set(), []
    doors = endpoints(data)
    for target in doors:
        goal = tuple(target["outside_cell"])
        path = astar(start, goal, free, network)
        network.update(edge_key(a, b) for a, b in zip(path, path[1:]))
        routes.append({"id": target["id"], "cell_count": len(path), "cells": [list(a) for a in path]})
    # Connect the principal district edges. These are offline public composition
    # routes on dry, unobstructed cells; they do not change runtime navigation.
    branches = [("west", (1, 24)), ("north", (31, 1)), ("south", (37, 46)),
                ("harbor_quay", (58, 9)), ("seafront_north", (58, 3)),
                ("seafront_center", (58, 24)), ("seafront_south", (58, 46))]
    for ident, goal in branches:
        path = astar(start, goal, free, network)
        network.update(edge_key(a, b) for a, b in zip(path, path[1:]))
        routes.append({"id": "branch_" + ident, "cell_count": len(path), "cells": [list(a) for a in path]})
    plans = straight_network_segments(network)
    for door in doors:
        plans.append({"points": [list(cell_point(door["outside_cell"])), door["boundary_m"]],
                      "width": WIDTH, "kind": "threshold", "threshold_owner": door["id"],
                      "source_door_cell": door["source_door_cell"], "face": door["face"]})
    collisions = []
    for i, route in enumerate(plans):
        for p0, p1 in zip(route["points"], route["points"][1:]):
            for rect in rects:
                # Only the short final approach may enter its own facade's
                # clearance strip. No other building receives this exception.
                if route.get("threshold_owner") == rect["id"]:
                    continue
                if segment_intersects(p0, p1, rect):
                    collisions.append({"segment": i, "building": rect["id"], "points": [p0, p1]})
    report = {"source_buildings": len(rects) - 1, "proposed_extra_obstacles": 1,
              "building_clearance_m": CLEARANCE, "street_width_m": WIDTH,
              "street_edges": len(network), "street_segments": len(plans),
              "true_source_doors": len(doors) - 1, "proposed_exterior_thresholds": 1,
              "route_targets": len(routes), "collision_count": len(collisions), "collisions": collisions,
              "all_targets_reachable": True, "smoothing": "collinear merge only; no diagonal corner cutting",
              "threshold_exception": "Final connector may enter only its own owner's 0.72m facade clearance strip."}
    if collisions:
        raise ValueError("Unsafe street segments: " + json.dumps(collisions))
    return {"format": "living_town.offline_street_plan.v1", "source_head": "f204276",
            "coordinate_transform": "world=((source_x-32)*1.8,(24-source_y)*1.8); grid points use cell centers",
            "source_map_canonical_sha256": hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest(),
            "note": "Offline architectural presentation only. Proposed warehouse exterior does not prove interior fit.",
            "paths": plans, "routes": routes, "thresholds": doors, "footprints": rects, "validation": report}


def plan_streets(data):
    """Return lists of world-space points and widths; raise on unsafe geometry."""
    return build_plan(data)["paths"]


if __name__ == "__main__":
    data = json.loads((REPO / "game/data/map.json").read_text(encoding="utf-8"))
    document = build_plan(data)
    (ROOT / "street_plan.json").write_text(json.dumps(document, indent=2), encoding="utf-8")
    print(json.dumps(document["validation"], indent=2))
