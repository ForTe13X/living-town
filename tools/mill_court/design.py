"""Concrete Mill Court geometry specification. Pure Python; metres; no DCC imports."""

import math


def product(*seq):
    out = [()]
    for values in seq:
        out = [a + (b,) for a in out for b in values]
    return out


def grid_rect(outer, holes):
    """Rectangular cells whose interiors exclude every declared aperture."""
    x0, y0, x1, y1 = outer
    xs = sorted(
        {
            x0,
            x1,
            *[v for h in holes for v in (max(x0, h[0]), min(x1, h[2])) if x0 < v < x1],
        }
    )
    ys = sorted(
        {
            y0,
            y1,
            *[v for h in holes for v in (max(y0, h[1]), min(y1, h[3])) if y0 < v < y1],
        }
    )
    return [
        (a, c, b, d)
        for a, b in zip(xs, xs[1:])
        for c, d in zip(ys, ys[1:])
        if not any(
            h[0] < (a + b) / 2 < h[2] and h[1] < (c + d) / 2 < h[3] for h in holes
        )
    ]


class Design:
    def __init__(self, data, site):
        self.data = data
        self.site = site
        self.objects = []
        self.apertures = []
        self.furniture = []
        self.stairs = []
        self.owner = None
        self.plan = None
        self.room = ""
        self.asset = ""
        self.serial = 0

    def emit(self, name, kind, material, **kw):
        self.serial += 1
        row = dict(
            id=f'{self.owner or "Site"}/{self.plan["id"] if self.plan else "Site"}/{self.asset or name}/{name}_{self.serial:05}',
            label=name,
            kind=kind,
            material=material,
            owner=self.owner or "SITE_Study",
            plan=self.plan["id"] if self.plan else None,
            level=self.plan["level_index"] if self.plan else -1,
            asset=self.asset or name,
            room=self.room,
            category=kw.pop("category", "detail"),
            **kw,
        )
        self.objects.append(row)
        return row

    def point(self, p):
        if not self.plan:
            return list(p)
        x, y = self.plan["world_inner_southwest_xy_m"]
        return [p[0] + x, p[1] + y, p[2] + self.plan["FF_world_m"]]

    def box(self, name, b, mat, bevel=0.003, **kw):
        assert all(b[i + 3] > b[i] for i in range(3)), (name, b)
        return self.emit(
            name,
            "BOX",
            mat,
            low=self.point(b[:3]),
            high=self.point(b[3:]),
            bevel=bevel,
            **kw,
        )

    def sphere(self, name, c, s, mat, **kw):
        return self.emit(
            name, "ELLIPSOID", mat, center=self.point(c), scale=list(s), **kw
        )

    def beam(self, name, a, b, r, mat, **kw):
        return self.emit(
            name, "CYLINDER", mat, a=self.point(a), b=self.point(b), radius=r, **kw
        )

    def mesh(self, name, verts, faces, mat, **kw):
        return self.emit(
            name,
            "MESH",
            mat,
            vertices=[self.point(v) for v in verts],
            faces=faces,
            **kw,
        )

    def surface(self, name, outer, z0, z1, holes, mat, **kw):
        for i, b in enumerate(grid_rect(outer, holes)):
            self.box(f"{name}_{i}", [b[0], b[1], z0, b[2], b[3], z1], mat, **kw)

    def wall(self, name, axis, at, start, end, thickness, holes, mat, side=None):
        # One closed shared-vertex extrusion per cutaway height band. Adjacent
        # aperture cells contribute no internal side face and receive no bevel.
        for lo, hi in ((0.0, 1.0), (1.0, 2.5)):
            cells = grid_rect((start, lo, end, hi), holes)
            if not cells:
                continue
            verts = []
            faces = []
            lookup = {}
            edge_count = {}
            edge_direction = {}

            def vertex(u, z, back):
                key = (u, z, back)
                if key not in lookup:
                    lookup[key] = len(verts)
                    verts.append(
                        (u, at + thickness * back, z)
                        if axis == "horizontal"
                        else (at + thickness * back, u, z)
                    )
                return lookup[key]

            for a, b, c, e in cells:
                contour = [(a, b), (c, b), (c, e), (a, e)]
                if axis == "vertical":
                    contour.reverse()
                faces.append([vertex(u, z, 0) for u, z in contour])
                faces.append([vertex(u, z, 1) for u, z in reversed(contour)])
                for aa, bb in zip(contour, contour[1:] + contour[:1]):
                    key = tuple(sorted((aa, bb)))
                    edge_count[key] = edge_count.get(key, 0) + 1
                    edge_direction[key] = (aa, bb)
            for key, count in edge_count.items():
                if count == 1:
                    a, b = edge_direction[key]
                    faces.append(
                        [vertex(*a, 0), vertex(*a, 1), vertex(*b, 1), vertex(*b, 0)]
                    )
                else:
                    assert count == 2
            origin = self.plan["world_inner_southwest_xy_m"] + [self.plan["FF_world_m"]]
            self.mesh(
                name + ("_Lower" if lo == 0 else "_Upper"),
                verts,
                faces,
                mat,
                category="wall",
                side=side,
                cut_upper=lo >= 1.0,
                wall_cells=cells,
                wall_axis=axis,
                wall_at=at,
                wall_thickness=thickness,
                wall_origin=origin,
                merge_policy="Shared vertices; internal cell side faces removed; no bevel on construction grid or split height",
            )
        for h in holes:
            self.apertures.append(
                dict(
                    owner=self.owner,
                    plan=self.plan["id"],
                    wall=name,
                    axis=axis,
                    at=at,
                    thickness=thickness,
                    rect=h,
                )
            )


def pane(d, name, side, span, z0, z1, mat="glass", depth=0.014):
    p = d.plan
    W = p["clear_width_m"]
    D = p["clear_depth_m"]
    a, b = span
    at = {"S": -0.16, "N": D + 0.16, "W": -0.16, "E": W + 0.16}[side]
    if side in ("S", "N"):
        return d.box(
            name,
            [a, at - depth / 2, z0, b, at + depth / 2, z1],
            mat,
            0.001,
            category="window",
            side=side,
        )
    return d.box(
        name,
        [at - depth / 2, a, z0, at + depth / 2, b, z1],
        mat,
        0.001,
        category="window",
        side=side,
    )


def window(d, w):
    d.asset = w["id"]
    a = w["start_m"]
    b = w["end_m"]
    z = w["sill_above_FF_m"]
    h = w["height_m"]
    f = w["frame_width_m"]
    s = w["side"]
    # Masonry aperture is exact input window span; frame is fitted inside it.
    pane(
        d,
        "SashGlazing",
        s,
        (a + f, b - f),
        z + f,
        z + h - f,
        "frosted" if w.get("frosted") else "glass",
    )
    for label, span, lo, hi in [
        ("JambL", (a, a + f), z, z + h),
        ("JambR", (b - f, b), z, z + h),
        ("SashHead", (a, b), z + h - f, z + h),
        ("SashBottom", (a, b), z, z + f),
        ("Mullion", ((a + b) / 2 - 0.018, (a + b) / 2 + 0.018), z + f, z + h - f),
    ]:
        pane(
            d,
            label,
            s,
            span,
            lo,
            hi,
            "paint_sage" if d.plan["owner_label"] == "A" else "paint_blue",
            0.065,
        )
    # Stone sill and granite lintel span masonry, not floating painted panels.
    W = d.plan["clear_width_m"]
    D = d.plan["clear_depth_m"]
    at = {"S": -0.34, "N": D + 0.02, "W": -0.34, "E": W + 0.02}[s]

    def solid(label, start, end, lo, hi, depth, mat):
        if s in ("S", "N"):
            d.box(
                label,
                [start, at, lo, end, at + depth, hi],
                mat,
                0.008,
                category="window",
                side=s,
            )
        else:
            d.box(
                label,
                [at, start, lo, at + depth, end, hi],
                mat,
                0.008,
                category="window",
                side=s,
            )

    solid("GraniteSill", a - 0.07, b + 0.07, z - 0.065, z, 0.32, "granite")
    solid("Lintel", a - 0.10, b + 0.10, z + h, z + h + 0.10, 0.30, "granite")
    # Latch positioned inside the casement, hinges at outer edge.
    pane(
        d,
        "Latch",
        s,
        ((a + b) / 2 + 0.025, (a + b) / 2 + 0.05),
        z + 0.42 * h,
        z + 0.57 * h,
        "brass",
    )
    if not w.get("frosted") and any(
        k in w["id"] for k in ("living", "bed", "primary", "child")
    ):
        for lo, hi in ((a + 0.015, a + 0.10), (b - 0.10, b - 0.015)):
            at = {"S": 0.025, "N": D - 0.025, "W": 0.025, "E": W - 0.025}[s]
            verts = []
            faces = []
            bottom = max(0.15, z - 0.20)
            top = z + h + 0.04
            for j in range(17):
                t = j / 16
                zz = bottom + (top - bottom) * t
                for i in range(13):
                    u = i / 12
                    along = lo + (hi - lo) * u
                    fold = math.sin(u * math.tau * 3) * (0.010 + 0.007 * (1 - t))
                    depth = at + fold
                    verts.append(
                        (
                            along,
                            depth,
                            zz + 0.006 * math.sin(u * math.tau * 3) * (1 - t),
                        )
                        if s in ("S", "N")
                        else (
                            depth,
                            along,
                            zz + 0.006 * math.sin(u * math.tau * 3) * (1 - t),
                        )
                    )
            for j in range(16):
                for i in range(12):
                    n = j * 13 + i
                    faces.append([n, n + 1, n + 14, n + 13])
            d.mesh(
                "FoldedLinenCurtain",
                verts,
                faces,
                "linen_white",
                category="window",
                side=s,
                smooth=True,
                cloth_thickness=0.001,
            )


def door(d, door):
    d.asset = door["id"]
    w = door["clear_width_m"]
    h = door["height_m"]
    t = door["leaf_thickness_m"]
    j = door["jamb_width_m"]
    if door["kind"] == "hinged":
        hx, hy = door["hinge_xy_m"]
        vx, vy = door["closed_unit_vector"]
        vertical = bool(vy)
        # Leaves are stored OPEN at exact declared90deg swing; each leaf retains hinge metadata.
        ox, oy = door["open_unit_vector"]
        cx = hx + ox * w / 2
        cy = hy + oy * w / 2

        def leaf(label, u0, u1, z0, z1, dep, mat):
            ax = hx + ox * u0
            ay = hy + oy * u0
            bx = hx + ox * u1
            by = hy + oy * u1
            return d.box(
                label,
                [
                    min(ax, bx) - (dep / 2 if ox == 0 else 0),
                    min(ay, by) - (dep / 2 if oy == 0 else 0),
                    z0,
                    max(ax, bx) + (dep / 2 if ox == 0 else 0),
                    max(ay, by) + (dep / 2 if oy == 0 else 0),
                    z1,
                ],
                mat,
                0.006,
                category="door",
            )

        base = leaf("OpenLeaf", 0, w, 0.025, h, t, "paint_cream")
        base.update(
            hinge_local=[hx, hy],
            closed_unit=door["closed_unit_vector"],
            open_unit=door["open_unit_vector"],
            clear_width=w,
        )
        for z0, z1 in ((0.18, 0.80), (1.03, 1.88)):
            leaf(
                "RecessedPanel",
                0.10,
                w - 0.10,
                z0,
                min(z1, h - 0.10),
                t + 0.004,
                "paint_warm",
            )
        leaf("Lever", w - 0.19, w - 0.07, 0.99, 1.015, t + 0.035, "brass")
        for z in (0.24, 1.1, 1.90):
            d.beam(
                "Hinge",
                (hx, hy, z),
                (hx, hy, z + 0.055),
                0.012,
                "brass",
                category="door",
            )
        a = min(hy, hy + vy * w) if vertical else min(hx, hx + vx * w)
        b = a + w
        at = hx if vertical else hy
    else:
        vertical = door["opening_axis"] == "vertical"
        a = door["start_m"]
        b = door["end_m"]
        at = door["at_m"]
        pocket = door["pocket_extent_m"]
        lo = min(pocket) + 0.025
        hi = lo + w
        if vertical:
            bounds = [at - t / 2, lo, 0.02, at + t / 2, hi, h]
        else:
            bounds = [lo, at - t / 2, 0.02, hi, at + t / 2, h]
        r = d.box("PocketLeafStored", bounds, "paint_cream", 0.004, category="door")
        r.update(pocket_extent=pocket, clear_opening=[a, b], pocket_state="OPEN")
    # Three-sided visible jamb sits outside clear passage; no threshold obstruction inside.
    mat = "oak"
    half = 0.05 if not door.get("external") else 0.16
    if vertical:
        for u in (a - j, b):
            d.box(
                "Jamb",
                [at - half, u, 0, at + half, u + j, h + j],
                mat,
                0.003,
                category="door",
            )
        d.box(
            "HeadJamb",
            [at - half, a - j, h, at + half, b + j, h + j],
            mat,
            0.003,
            category="door",
        )
        d.box(
            "HeadPacking",
            [at - half, a - j, h + j, at + half, b + j, door["rough_opening_height_m"]],
            mat,
            0.002,
            category="door",
        )
    else:
        for u in (a - j, b):
            d.box(
                "Jamb",
                [u, at - half, 0, u + j, at + half, h + j],
                mat,
                0.003,
                category="door",
            )
        d.box(
            "HeadJamb",
            [a - j, at - half, h, b + j, at + half, h + j],
            mat,
            0.003,
            category="door",
        )
        d.box(
            "HeadPacking",
            [a - j, at - half, h + j, b + j, at + half, door["rough_opening_height_m"]],
            mat,
            0.002,
            category="door",
        )


def build_floor(d, p):
    d.plan = p
    d.owner = p["owner_id"]
    d.room = ""
    d.asset = "Structure"
    W = p["clear_width_m"]
    D = p["clear_depth_m"]
    voids = [p["stair_void_bounds_m"]] if p["level_index"] else []
    d.surface(
        "StructuralSlab",
        [-0.3, -0.3, W + 0.3, D + 0.3],
        -0.20,
        0,
        voids,
        "slab",
        category="slab",
    )
    # Room floors sit inside the exact room polygons, with wet rooms visibly tiled.
    for room in p["rooms"]:
        d.room = room["id"]
        poly = room["polygon_m"]
        d.asset = "RoomFloor_" + room["id"]
        d.mesh(
            "FloorFinish",
            [(x, y, 0.002) for x, y in poly],
            [list(range(len(poly)))],
            (
                "tile"
                if any(k in room["id"] for k in ("bath", "utility", "wc"))
                else "oak_floor"
            ),
            category="floor_finish",
        )
        d.emit(
            "RoomZone",
            "EMPTY",
            None,
            location=d.point(
                [
                    sum(x for x, y in poly) / len(poly),
                    sum(y for x, y in poly) / len(poly),
                    0,
                ]
            ),
            category="room_zone",
            polygon_world=[d.point([x, y, 0]) for x, y in poly],
            room_label=room["label"],
        )
    d.room = ""
    d.asset = "Ceiling"
    rooflight = [w["bounds_m"] for w in p["windows"] if w["side"] == "ROOF"]
    if p["level_index"] == 0:
        rooflight = [
            next(
                x
                for x in d.data["plans"]
                if x["owner_id"] == p["owner_id"] and x["level_index"] == 1
            )["stair_void_bounds_m"]
        ]
    d.surface(
        "Ceiling",
        [-0.3, -0.3, W + 0.3, D + 0.3],
        2.50,
        2.53,
        rooflight,
        "plaster_inside",
        category="ceiling",
    )
    d.asset = "Exterior"
    for side, axis, at, lo, hi in [
        ("S", "horizontal", -0.3, -0.3, W + 0.3),
        ("N", "horizontal", D, -0.3, W + 0.3),
        ("W", "vertical", -0.3, 0, D),
        ("E", "vertical", W, 0, D),
    ]:
        holes = []
        for w in p["windows"]:
            if w["side"] == side:
                holes.append(
                    [
                        w["start_m"],
                        w["sill_above_FF_m"],
                        w["end_m"],
                        w["sill_above_FF_m"] + w["height_m"],
                    ]
                )
        for dr in p["doors"]:
            if dr.get("external") and side == "S":
                h = dr["hinge_xy_m"]
                v = dr["closed_unit_vector"]
                end = h[0] + v[0] * dr["clear_width_m"]
                holes.append(
                    [
                        min(h[0], end) - 0.05,
                        0,
                        max(h[0], end) + 0.05,
                        dr["rough_opening_height_m"],
                    ]
                )
        d.wall(
            "Exterior_" + side,
            axis,
            at,
            lo,
            hi,
            0.3,
            holes,
            "plaster_A" if p["owner_label"] == "A" else "plaster_B",
            side,
        )
        if p["level_index"] == 1:
            bounds = (
                [lo, at, 2.5, hi, at + 0.3, 2.7]
                if axis == "horizontal"
                else [at, lo, 2.5, at + 0.3, hi, 2.7]
            )
            d.box(
                "WallPlateBand_" + side,
                bounds,
                "plaster_A" if p["owner_label"] == "A" else "plaster_B",
                0.002,
                category="roof",
                side=side,
            )
    for wall in p["walls"]:
        d.asset = wall["id"]
        holes = []
        pockets = []
        for op in wall["openings"]:
            dr = next(x for x in p["doors"] if x["id"] == op["door_id"])
            holes.append(
                [
                    op["start_m"] - 0.05,
                    0,
                    op["end_m"] + 0.05,
                    dr["rough_opening_height_m"],
                ]
            )
            if dr["kind"] == "pocket":
                pockets.append(dr)
        # A pocket wall contains a physical leaf cavity, not a leaf intersecting solid masonry.
        holes.extend(
            [
                [min(x["pocket_extent_m"]), 0, max(x["pocket_extent_m"]), 2.15]
                for x in pockets
            ]
        )
        d.wall(
            wall["id"],
            wall["axis"],
            wall["at_m"],
            wall["start_m"],
            wall["end_m"],
            wall["thickness_m"],
            holes,
            "plaster_inside",
        )
        for dr in pockets:
            for delta in (0, wall["thickness_m"] - 0.015):
                d.wall(
                    "PocketSkin",
                    wall["axis"],
                    wall["at_m"] + delta,
                    min(dr["pocket_extent_m"]),
                    max(dr["pocket_extent_m"]),
                    0.015,
                    [],
                    "plaster_inside",
                )
    for w in p["windows"]:
        if w["side"] != "ROOF":
            window(d, w)
    for dr in p["doors"]:
        door(d, dr)
    d.asset = "CornerQuoins"
    for row, z in enumerate((0.12, 0.46, 0.80, 1.14, 1.48, 1.82, 2.16)):
        for x, y, sx, sy in (
            (-0.3, -0.3, 1, 1),
            (W + 0.3, -0.3, -1, 1),
            (-0.3, D + 0.3, 1, -1),
            (W + 0.3, D + 0.3, -1, -1),
        ):
            x -= sx * 0.012
            y -= sy * 0.012
            dx = 0.34 if row % 2 else 0.27
            c = [x + sx * dx, y + sy * 0.016, z + 0.26]
            d.box(
                "CornerStoneX",
                [min(x, c[0]), min(y, c[1]), z, max(x, c[0]), max(y, c[1]), z + 0.26],
                "granite",
                0.005,
                category="exterior_detail",
            )
            c = [x + sx * 0.016, y + sy * dx, z + 0.26]
            d.box(
                "CornerStoneY",
                [min(x, c[0]), min(y, c[1]), z, max(x, c[0]), max(y, c[1]), z + 0.26],
                "granite",
                0.005,
                category="exterior_detail",
            )
    if not p["level_index"]:
        w = next(q for q in p["windows"] if q["id"] == "dining_s")
        a = w["start_m"] + 0.12
        b = w["end_m"] - 0.12
        sill = w["sill_above_FF_m"]
        d.asset = "DiningWindowFlowerbox"
        d.box(
            "TimberPlanter",
            [a, -0.55, sill - 0.28, b, -0.32, sill - 0.07],
            "paint_sage",
            0.005,
            category="exterior_detail",
        )
        d.box(
            "PlanterSoil",
            [a + 0.02, -0.53, sill - 0.071, b - 0.02, -0.34, sill - 0.065],
            "roof_dark",
            0.001,
            category="exterior_detail",
        )
        for i in range(7):
            x = a + 0.08 + (b - a - 0.16) * i / 6
            y = -0.435 + 0.035 * math.sin(i * 2)
            z = sill + 0.035 + 0.018 * math.sin(i)
            d.beam(
                "GeraniumStem",
                (x, y, sill - 0.065),
                (x, y, z),
                0.004,
                "leaf",
                category="exterior_detail",
            )
            d.sphere(
                "GeraniumLeaf",
                (x - 0.035, y, sill - 0.015),
                (0.055, 0.045, 0.012),
                "leaf",
                category="exterior_detail",
            )
            for j in range(5):
                angle = j * math.tau / 5
                d.sphere(
                    "GeraniumPetal",
                    (x + 0.024 * math.cos(angle), y + 0.024 * math.sin(angle), z),
                    (0.021, 0.021, 0.012),
                    "flower",
                    category="exterior_detail",
                )
    # Skirtings follow actual opaque wall segments rather than bridging door gaps.
    d.asset = "Skirting"
    for wall in p["wall_segments"]:
        b = wall["bounds_m"]
        x0, y0, x1, y1 = b
        if x1 - x0 > y1 - y0:
            y = (
                (y1 if wall["id"] == "ext_S" else y0 - 0.016)
                if wall.get("exterior")
                else y0 - 0.012
            )
            d.box(
                "Skirting",
                [x0, y, 0, x1, y + 0.016, 0.10],
                "paint_cream",
                0.002,
                category="trim",
            )
        else:
            x = (
                (x1 if wall["id"] == "ext_W" else x0 - 0.016)
                if wall.get("exterior")
                else x0 - 0.012
            )
            d.box(
                "Skirting",
                [x, y0, 0, x + 0.016, y1, 0.10],
                "paint_cream",
                0.002,
                category="trim",
            )


def build_stair(d, p):
    d.plan = p
    d.owner = p["owner_id"]
    d.asset = p["stair"]["id"]
    d.room = "stair"
    s = p["stair"]
    rise = s["riser_m"]
    going = s["tread_going_m"]
    y0 = 0.95
    # 13 independent horizontal treads plus14 real vertical risers, final riser meeting upper slab.
    for i in range(13):
        y = y0 + i * going
        z = (i + 1) * rise
        d.box(
            "Tread",
            [0.05, y, z - 0.04, 0.95, y + going, z],
            "oak",
            0.004,
            category="stair_tread",
            tread_index=i + 1,
        )
    for i in range(14):
        y = y0 + i * going
        z = i * rise
        d.box(
            "Riser",
            [0.05, y - 0.018, z, 0.95, y + 0.018, z + rise],
            "oak",
            0.002,
            category="stair_riser",
            riser_index=i + 1,
        )
    for x in (0.025, 0.975):
        d.beam(
            "Stringer",
            (x, y0, 0.07),
            (x, 3.875, 2.63),
            0.045,
            "oak",
            category="stair_rail",
        )
        d.beam(
            "Handrail",
            (x, y0, 1 + rise),
            (x, 3.875, 3.70),
            0.025,
            "oak",
            category="stair_rail",
        )
        for i in range(0, 14, 2):
            y = y0 + i * going
            z = (min(i + 1, 14)) * rise
            d.beam(
                "Baluster",
                (x, y, z),
                (x, y, z + 1.0),
                0.012,
                "iron",
                category="stair_rail",
            )
        # West is against wall; east turn onto the hall MUST remain open.
        if x < 0.5:
            d.beam(
                "LandingWallHandrail",
                (x, 3.875, 3.70),
                (x, 4.85, 3.70),
                0.025,
                "oak",
                category="stair_rail",
            )
    if not s["upper_floor_covered_over_bottom_landing"]:
        d.beam(
            "LowerVoidGuard",
            (1.0, 0.02, 3.70),
            (1.0, 0.94, 3.70),
            0.025,
            "oak",
            category="stair_rail",
        )
        for y in (0.04, 0.48, 0.92):
            d.beam(
                "VoidGuardPost",
                (1.0, y, 2.7),
                (1.0, y, 3.7),
                0.012,
                "iron",
                category="stair_rail",
            )
    d.stairs.append(
        dict(
            owner=d.owner,
            id=s["id"],
            treads=13,
            risers=14,
            top_z=d.point([0, 0, 2.7])[2],
            opening=s["opening_bounds_m"],
            clear_width=0.9,
        )
    )


def build_roof(d, p):
    d.plan = p
    d.owner = p["owner_id"]
    d.asset = "Roof"
    d.room = "Loft"
    W = p["clear_width_m"]
    D = 4.9
    ridge = D / 2
    slope = 2.3 / 2.75

    def roofz(y):
        return 5.0 - abs(y - ridge) * slope  # local upperFF; wallplate is2.7, ridge5.0

    holes = [(1.2, 1.7, 1.8, 2.3)] if p["owner_label"] == "B" else []
    for side, (lo, hi) in enumerate(((-0.55, ridge), (ridge, D + 0.55))):
        tiles = []
        faces = []
        matindices = []
        # Flat continuous deck with actual rooflight aperture.
        for cell in grid_rect((-0.55, lo, W + 0.55, hi), holes):
            a, b, c, e = cell
            d.mesh(
                "RoofDeck",
                [
                    (a, b, roofz(b)),
                    (c, b, roofz(b)),
                    (c, e, roofz(e)),
                    (a, e, roofz(e)),
                ],
                [[0, 1, 2, 3]],
                "roof_dark",
                category="roof",
            )
        # Individual visible slate rectangles, batched into two meshes/owner.
        rows = math.ceil((hi - lo) / 0.22)
        for row in range(rows):
            ya = lo + row * 0.22
            yb = min(hi, ya + 0.235)
            for col in range(math.ceil((W + 1.10) / 0.25) + 1):
                xa = -0.55 + col * 0.25 - (0.125 if row % 2 else 0)
                xb = min(W + 0.55, xa + 0.245)
                xa = max(-0.55, xa)
                if xb <= xa:
                    continue
                for a, b, c, e in grid_rect((xa, ya, xb, yb), holes):
                    n = len(tiles)
                    off = 0.015 + row * 0.00003
                    tiles.extend(
                        [
                            (a, b, roofz(b) + off),
                            (c, b, roofz(b) + off),
                            (c, e, roofz(e) + off),
                            (a, e, roofz(e) + off),
                        ]
                    )
                    faces.append([n, n + 1, n + 2, n + 3])
                    matindices.append((row * 17 + col * 7) % 5)
        d.mesh(
            "BatchedSlates_" + str(side),
            tiles,
            faces,
            "slate",
            category="roof",
            material_variants=5,
            face_material_indices=matindices,
        )
    for x in (-0.40, W + 0.40):
        d.beam(
            "Bargeboard",
            (x, -0.55, roofz(-0.55)),
            (x, ridge, 5.0),
            0.045,
            "paint_cream",
            category="roof",
        )
    for x in (-0.40, W + 0.40):
        d.beam(
            "Bargeboard",
            (x, ridge, 5.0),
            (x, D + 0.55, roofz(D + 0.55)),
            0.045,
            "paint_cream",
            category="roof",
        )
    d.beam(
        "RidgeCap",
        (-0.55, ridge, 5.04),
        (W + 0.55, ridge, 5.04),
        0.07,
        "slate",
        category="roof",
    )
    for y in (-0.53, D + 0.53):
        z = roofz(y) - 0.04
        d.beam("Gutter", (-0.5, y, z), (W + 0.5, y, z), 0.06, "iron", category="roof")
        d.beam(
            "Downpipe",
            (W + 0.42, y, z),
            (W + 0.42, y, -2.65),
            0.035,
            "iron",
            category="exterior_service",
        )
    for x in (-0.3, W):
        d.mesh(
            "Gable",
            [
                (x, -0.3, 2.7),
                (x, D + 0.3, 2.7),
                (x, ridge, 5.0),
                (x + 0.3, -0.3, 2.7),
                (x + 0.3, D + 0.3, 2.7),
                (x + 0.3, ridge, 5.0),
            ],
            [[0, 2, 1], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]],
            "plaster_A" if p["owner_label"] == "A" else "plaster_B",
            category="roof",
        )
    # Splayed shaft: exact ceiling opening, top shifted20cm south, clearofridge.
    if holes:
        d.asset = "bath_rooflight"
        bottom = [(1.2, 1.9, 2.5), (1.8, 1.9, 2.5), (1.8, 2.5, 2.5), (1.2, 2.5, 2.5)]
        top = [
            (1.2, 1.7, roofz(1.7)),
            (1.8, 1.7, roofz(1.7)),
            (1.8, 2.3, roofz(2.3)),
            (1.2, 2.3, roofz(2.3)),
        ]
        for i in range(4):
            d.mesh(
                "LightShaft",
                [bottom[i], bottom[(i + 1) % 4], top[(i + 1) % 4], top[i]],
                [[0, 1, 2, 3]],
                "plaster_inside",
                category="rooflight",
            )
        d.mesh(
            "RooflightGlazing",
            [(x, y, z + 0.025) for x, y, z in top],
            [[0, 1, 2, 3]],
            "frosted",
            category="roof",
        )
        for a, b in zip(top, top[1:] + top[:1]):
            d.beam("RooflightFlashing", a, b, 0.035, "iron", category="roof")
        d.box(
            "ExtractGrille",
            [2.55, 2.05, 2.475, 2.75, 2.25, 2.50],
            "paint_cream",
            0.003,
            category="ceiling",
        )


def furniture(d, p):
    """Each piece uses facing-local right/depth axes inside its exact source footprint."""
    d.plan = p
    d.owner = p["owner_id"]
    for f in p["furniture"]:
        d.asset = f["id"]
        b = f["bounds_m"]
        x0, y0, x1, y1 = b
        cx = (x0 + x1) / 2
        cy = (y0 + y1) / 2

        def contains(poly, x, y):
            inside = False
            for a, c in zip(poly, poly[1:] + poly[:1]):
                if (a[1] > y) != (c[1] > y) and x < (c[0] - a[0]) * (y - a[1]) / (
                    c[1] - a[1]
                ) + a[0]:
                    inside = not inside
            return inside

        d.room = next(
            (r["id"] for r in p["rooms"] if contains(r["polygon_m"], cx, cy)), "Shared"
        )
        fx, fy = f["facing"]
        right = (fy, -fx)
        width = (x1 - x0) if fx == 0 else (y1 - y0)
        depth = (x1 - x0) if fx else (y1 - y0)

        # depth v0 is back, v1 is front; front points along source facing.
        def pt(u, v, z):
            return [cx + right[0] * u + fx * v, cy + right[1] * u + fy * v, z]

        def box(n, u0, v0, z0, u1, v1, z1, m, bev=0.008):
            a = pt(u0, v0, z0)
            c = pt(u1, v1, z1)
            return d.box(
                n,
                [
                    min(a[0], c[0]),
                    min(a[1], c[1]),
                    z0,
                    max(a[0], c[0]),
                    max(a[1], c[1]),
                    z1,
                ],
                m,
                bev,
                category="furniture",
            )

        def ball(n, u, v, z, su, sv, sz, m):
            sx, sy = (su, sv) if fx == 0 else (sv, su)
            return d.sphere(n, pt(u, v, z), (sx, sy, sz), m, category="furniture")

        def beam(n, u, v, z, u2, v2, z2, r, m):
            return d.beam(n, pt(u, v, z), pt(u2, v2, z2), r, m, category="furniture")

        def cloth(n, ulo, uhi, vlo, vhi, height, throw=False):
            verts = []
            faces = []
            nx = 32
            ny = 42 if not throw else 16
            for j in range(ny + 1):
                v = vlo + (vhi - vlo) * j / ny
                for i in range(nx + 1):
                    u = ulo + (uhi - ulo) * i / nx
                    edge = max(0.0, min(1.0, (abs(u) - (w - 0.065)) / 0.06))
                    foot = (
                        max(0.0, min(1.0, (v - (q - 0.08)) / 0.065))
                        if not throw
                        else 0.0
                    )
                    drop = 0.12 * max(edge, foot)
                    wrinkle = (
                        (
                            0.006 * math.sin(u * 17 + v * 5)
                            + 0.004 * math.sin(v * 23 - u * 4)
                        )
                        if not throw
                        else (
                            0.007 * math.sin(v * 59) + 0.003 * math.sin(u * 19 + v * 8)
                        )
                    )
                    verts.append(pt(u, v, height - drop + wrinkle * (1 - 0.3 * edge)))
            for j in range(ny):
                for i in range(nx):
                    a = j * (nx + 1) + i
                    faces.append([a, a + 1, a + nx + 2, a + nx + 1])
            d.mesh(
                n,
                verts,
                faces,
                (
                    "linen_ochre"
                    if throw
                    else ("linen_blue" if p["owner_label"] == "B" else "linen_sage")
                ),
                category="furniture",
                smooth=True,
                cloth_thickness=0.003 if throw else 0.008,
            )

        def pillow(u, v, z, su, sv, sz):
            verts = [pt(u, v, z + sz)]
            faces = []
            segments = 32
            rings = 11
            for i in range(1, rings + 1):
                theta = math.pi * i / (rings + 1)
                radial = math.sin(theta) ** 0.55
                for j in range(segments):
                    phi = j * math.tau / segments
                    co = math.cos(phi)
                    si = math.sin(phi)
                    xx = su * math.copysign(abs(co) ** 0.5, co) * radial
                    yy = sv * math.copysign(abs(si) ** 0.5, si) * radial
                    zz = (
                        sz * math.cos(theta)
                        + 0.003 * math.cos(phi * 7) * math.sin(theta) ** 3
                    )
                    verts.append(pt(u + xx, v + yy, z + zz))
            bottom = len(verts)
            verts.append(pt(u, v, z - sz))
            for j in range(segments):
                faces.append([0, 1 + j, 1 + (j + 1) % segments])
                faces.append(
                    [
                        bottom,
                        1 + (rings - 1) * segments + (j + 1) % segments,
                        1 + (rings - 1) * segments + j,
                    ]
                )
            for i in range(rings - 1):
                for j in range(segments):
                    a = 1 + i * segments + j
                    b = 1 + i * segments + (j + 1) % segments
                    faces.append([a, a + segments, b + segments, b])
            d.mesh(
                "Pillow", verts, faces, "linen_white", category="furniture", smooth=True
            )

        w = width / 2
        q = depth / 2
        h = f["height_m"]
        k = f["kind"]
        start = len(d.objects)
        if k in ("chair", "sofa", "bench"):
            seat = 0.45
            pad = (
                "linen_sage"
                if k == "sofa" and p["owner_label"] == "A"
                else "linen_blue" if k == "sofa" else "linen_oat"
            )
            for u, v in product((-w + 0.055, w - 0.055), (-q + 0.055, q - 0.055)):
                beam("Leg", u, v, 0.025, u, v, 0.38, 0.021, "oak")
            box(
                "SeatFrame",
                -w + 0.015,
                -q + 0.015,
                0.32,
                w - 0.015,
                q - 0.015,
                0.39,
                "oak",
            )
            box(
                "Back",
                -w + 0.012,
                -q + 0.008,
                0.43,
                w - 0.012,
                -q + 0.085,
                h,
                pad if k == "sofa" else "oak",
                0.025,
            )
            seats = f.get("seats", 1)
            for i in range(seats):
                a = -w + 0.045 + i * (width - 0.09) / seats
                c = -w + 0.045 + (i + 1) * (width - 0.09) / seats - 0.012
                box("SeatCushion", a, -q + 0.09, 0.39, c, q - 0.025, seat, pad, 0.026)
                if k == "sofa":
                    box(
                        "BackCushion",
                        a,
                        -q + 0.08,
                        0.48,
                        c,
                        -q + 0.22,
                        h - 0.04,
                        pad,
                        0.045,
                    )
            if k == "sofa":
                for u in (-w + 0.02, w - 0.10):
                    box("Arm", u, -q + 0.02, 0.38, u + 0.08, q - 0.01, 0.65, pad, 0.028)
                ball(
                    "AccentPillow",
                    -w + 0.20,
                    -q + 0.30,
                    0.60,
                    0.13,
                    0.06,
                    0.14,
                    "linen_ochre",
                )
        elif k == "bed":
            box("Divan", -w, -q, 0.08, w, q, h - 0.17, "linen_oat", 0.035)
            box(
                "Mattress",
                -w + 0.015,
                -q + 0.015,
                h - 0.18,
                w - 0.015,
                q - 0.015,
                h - 0.025,
                "linen_white",
                0.045,
            )
            cloth("LinenCover", -w + 0.008, w - 0.008, -q + 0.46, q - 0.008, h + 0.008)
            cloth(
                "FoldedThrow",
                -w + 0.012,
                w - 0.012,
                q - 0.40,
                q - 0.08,
                h + 0.036,
                True,
            )
            box("Headboard", -w, -q, 0.12, w, -q + 0.045, 0.95, "oak", 0.014)
            n = 2 if width > 1.1 else 1
            for i in range(n):
                pillow(
                    -w + (i + 0.5) * width / n,
                    -q + 0.23,
                    h + 0.045,
                    min(0.27, width / n * 0.42),
                    0.16,
                    0.07,
                )
        elif k in ("table", "desk", "coffee_table", "side_table", "nightstand"):
            box("Top", -w, -q, h - 0.04, w, q, h, "oak", 0.012)
            for u, v in product((-w + 0.045, w - 0.045), (-q + 0.045, q - 0.045)):
                box(
                    "Leg",
                    u - 0.018,
                    v - 0.018,
                    0.02,
                    u + 0.018,
                    v + 0.018,
                    h - 0.04,
                    "oak",
                    0.003,
                )
            if k == "nightstand":
                box(
                    "Drawer",
                    -w + 0.02,
                    -q + 0.01,
                    0.23,
                    w - 0.02,
                    q - 0.01,
                    0.42,
                    "paint_cream",
                )
                box(
                    "Pull",
                    -0.045,
                    q - 0.01,
                    0.32,
                    0.045,
                    q + 0.001,
                    0.335,
                    "brass",
                    0.002,
                )
                beam("LampStem", 0, 0, h + 0.02, 0, 0, h + 0.20, 0.012, "brass")
                ball("LampShade", 0, 0, h + 0.23, 0.085, 0.085, 0.08, "linen_oat")
            elif k == "desk":
                box(
                    "Notebook",
                    -w * 0.70,
                    -q * 0.1,
                    h + 0.002,
                    w * 0.15,
                    q * 0.75,
                    h + 0.015,
                    "paper",
                    0.002,
                )
                beam(
                    "Pencil",
                    w * 0.25,
                    0,
                    h + 0.02,
                    w * 0.3,
                    q * 0.5,
                    h + 0.02,
                    0.003,
                    "paint_blue",
                )
            elif k in ("table", "coffee_table"):
                box(
                    "Book",
                    -0.12,
                    -0.10,
                    h + 0.002,
                    0.10,
                    0.08,
                    h + 0.026,
                    "paint_blue",
                    0.002,
                )
                for i in range(2):
                    beam(
                        "Cup",
                        w * 0.45,
                        -q * 0.25 + i * 0.17,
                        h + 0.004,
                        w * 0.45,
                        -q * 0.25 + i * 0.17,
                        h + 0.08,
                        0.032,
                        "ceramic",
                    )
                if k == "table":
                    beam("PendantCord", 0, 0, 2.5, 0, 0, 2.15, 0.003, "iron")
                    ball(
                        "PendantShade",
                        0,
                        0,
                        2.13,
                        min(0.19, w * 0.6),
                        min(0.19, q * 0.6),
                        0.065,
                        "linen_oat",
                    )
            elif k == "side_table":
                beam("Vase", 0, 0, h, 0, 0, h + 0.13, 0.045, "ceramic")
                for i in range(3):
                    beam(
                        "Stem",
                        0,
                        0,
                        h + 0.1,
                        0.04 * (i - 1),
                        0,
                        h + 0.30 + i * 0.02,
                        0.002,
                        "leaf",
                    )
                    ball(
                        "Flower",
                        0.04 * (i - 1),
                        0,
                        h + 0.30 + i * 0.02,
                        0.022,
                        0.022,
                        0.016,
                        "flower",
                    )
        elif k in (
            "kitchen_counter",
            "pantry",
            "wardrobe",
            "media_console",
            "fridge",
            "washing_machine",
        ):
            m = (
                "paint_sage"
                if k == "kitchen_counter" and p["owner_label"] == "A"
                else "paint_blue" if k == "kitchen_counter" else "paint_cream"
            )
            box(
                "Plinth",
                -w + 0.025,
                -q + 0.025,
                0.025,
                w - 0.025,
                q - 0.025,
                0.10,
                "roof_dark",
                0.002,
            )
            if k == "kitchen_counter":
                box(
                    "CaseSide", -w, -q, 0.10, -w + 0.018, q - 0.025, h - 0.035, m, 0.002
                )
                box("CaseSide", w - 0.018, -q, 0.10, w, q - 0.025, h - 0.035, m, 0.002)
                box(
                    "CaseBack",
                    -w + 0.018,
                    -q,
                    0.10,
                    w - 0.018,
                    -q + 0.018,
                    h - 0.035,
                    m,
                    0.002,
                )
                box(
                    "CaseBottom",
                    -w + 0.018,
                    -q + 0.018,
                    0.10,
                    w - 0.018,
                    q - 0.025,
                    0.12,
                    m,
                    0.002,
                )
            else:
                box("CabinetCase", -w, -q, 0.10, w, q - 0.025, h - 0.025, m)
            panels = max(1, round(width / 0.5))
            for i in range(panels):
                a = -w + i * width / panels + 0.007
                c = -w + (i + 1) * width / panels - 0.007
                box("DoorPanel", a, q - 0.024, 0.13, c, q, h - 0.06, m, 0.005)
                box(
                    "DoorInset",
                    a + 0.035,
                    q + 0.001,
                    0.21,
                    c - 0.035,
                    q + 0.006,
                    h - 0.14,
                    m,
                    0.003,
                )
                box(
                    "Handle",
                    c - 0.035,
                    q + 0.007,
                    h * 0.55,
                    c - 0.022,
                    q + 0.017,
                    h * 0.55 + 0.10,
                    "brass",
                    0.003,
                )
            if k == "kitchen_counter":
                # Worktop genuinely cut around the two hosted appliances, so the sink is not a dark decal.
                holes = [
                    x["bounds_m"]
                    for x in p["furniture"]
                    if x.get("host_surface_id") == f["id"]
                ]
                for i, a in enumerate(grid_rect(b, holes)):
                    d.box(
                        "Worktop" + str(i),
                        [a[0], a[1], h - 0.035, a[2], a[3], h],
                        "stone_worktop",
                        0.004,
                        category="furniture",
                    )
                # Short splashback stops below the window sill.
                box("Splashback", -w, -q, 0.91, w, -q + 0.018, 1.03, "tile", 0.001)
            elif k == "fridge":
                box(
                    "FreezerSeam",
                    -w,
                    q + 0.002,
                    1.30,
                    w,
                    q + 0.005,
                    1.31,
                    "iron",
                    0.001,
                )
                box(
                    "FridgeHandle",
                    w - 0.07,
                    q + 0.008,
                    0.7,
                    w - 0.045,
                    q + 0.020,
                    1.19,
                    "iron",
                    0.003,
                )
            elif k == "washing_machine":
                beam(
                    "RoundDoor",
                    0,
                    q + 0.002,
                    0.43,
                    0,
                    q + 0.018,
                    0.43,
                    min(width, depth) * 0.29,
                    "iron",
                )
                beam(
                    "DarkPorthole",
                    0,
                    q + 0.020,
                    0.43,
                    0,
                    q + 0.025,
                    0.43,
                    min(width, depth) * 0.22,
                    "glass_dark",
                )
                box(
                    "Controls",
                    -w + 0.04,
                    q + 0.002,
                    0.72,
                    w - 0.04,
                    q + 0.008,
                    0.80,
                    "paint_warm",
                    0.002,
                )
            elif k == "media_console":
                # Display faces sofa; screen kept within declared top/footprint, not a misplaced monolith.
                box(
                    "Radio",
                    -w * 0.60,
                    -q * 0.65,
                    h - 0.20,
                    w * 0.60,
                    q * 0.20,
                    h + 0.003,
                    "roof_dark",
                )
                for i in range(4):
                    box(
                        "BookSpine",
                        -w + 0.04 + i * 0.045,
                        q + 0.001,
                        0.20,
                        -w + 0.075 + i * 0.045,
                        q + 0.008,
                        0.40,
                        "paper",
                        0.001,
                    )
        elif k == "sink":
            # Basin bowl is assembled from bottom and four rims; real open cavity.
            z = 0.83
            box(
                "BowlBottom",
                -w + 0.035,
                -q + 0.035,
                z,
                w - 0.035,
                q - 0.035,
                z + 0.018,
                "metal",
                0.004,
            )
            for a, c in ((-w, -w + 0.035), (w - 0.035, w)):
                box("BowlSide", a, -q, z, c, q, 0.92, "metal", 0.002)
            for a, c in ((-q, -q + 0.035), (q - 0.035, q)):
                box("BowlEnd", -w + 0.035, a, z, w - 0.035, c, 0.92, "metal", 0.002)
            beam("TapStem", 0, -q + 0.045, 0.92, 0, -q + 0.045, 1.14, 0.014, "metal")
            beam("TapSpout", 0, -q + 0.045, 1.14, 0, 0.02, 1.14, 0.014, "metal")
            beam("TapNose", 0, 0.02, 1.14, 0, 0.02, 1.10, 0.014, "metal")
        elif k == "hob":
            box("HobGlass", -w, -q, 0.903, w, q, 0.919, "glass_dark", 0.003)
            for u, v in product((-w * 0.48, w * 0.48), (-q * 0.46, q * 0.46)):
                beam(
                    "Burner", u, v, 0.92, u, v, 0.921, min(width, depth) * 0.13, "iron"
                )
        elif k == "toilet":
            ball("Pedestal", 0, 0, 0.19, w * 0.62, q * 0.65, 0.18, "ceramic")
            ball("Bowl", 0, q * 0.18, 0.36, w * 0.96, q * 0.80, 0.12, "ceramic")
            ball(
                "SeatRing", 0, q * 0.20, 0.435, w * 0.88, q * 0.68, 0.025, "paint_cream"
            )
            ball(
                "BowlOpening",
                0,
                q * 0.20,
                0.451,
                w * 0.59,
                q * 0.45,
                0.006,
                "roof_dark",
            )
            box("Cistern", -w, -q, 0.38, w, -q + 0.13, 0.78, "ceramic", 0.035)
            box(
                "FlushButton",
                -0.027,
                -q + 0.04,
                0.78,
                0.027,
                -q + 0.09,
                0.785,
                "metal",
                0.002,
            )
        elif k == "basin":
            box(
                "Vanity",
                -w + 0.01,
                -q + 0.01,
                0.10,
                w - 0.01,
                q - 0.01,
                0.70,
                "oak",
                0.015,
            )
            box("BasinRimBack", -w, -q, 0.73, w, -q + 0.055, 0.85, "ceramic", 0.01)
            for a, c in ((-w, -w + 0.045), (w - 0.045, w)):
                box("BasinSide", a, -q + 0.055, 0.73, c, q, 0.85, "ceramic", 0.009)
            box(
                "BasinFront",
                -w + 0.045,
                q - 0.045,
                0.73,
                w - 0.045,
                q,
                0.85,
                "ceramic",
                0.008,
            )
            box(
                "BasinBottom",
                -w + 0.045,
                -q + 0.055,
                0.73,
                w - 0.045,
                q - 0.045,
                0.75,
                "ceramic",
                0.012,
            )
            beam("Tap", 0, -q + 0.025, 0.85, 0, -q + 0.025, 1.02, 0.012, "metal")
            beam("Spout", 0, -q + 0.025, 1.02, 0, 0, 1.02, 0.012, "metal")
            box(
                "Mirror",
                -w * 0.75,
                -q - 0.004,
                1.15,
                w * 0.75,
                -q + 0.006,
                1.85,
                "mirror",
                0.002,
            )
        elif k == "shower":
            box("Tray", -w, -q, 0, w, q, 0.035, "ceramic", 0.008)
            box("Drain", -0.035, -0.035, 0.035, 0.035, 0.035, 0.038, "metal", 0.001)
            # Backscreen and folded curtain leave the exact0.70m entry clear.
            box("BackTile", -w, -q, 0.035, w, -q + 0.012, 2.05, "tile", 0.001)
            beam(
                "CurtainRail",
                -w + 0.025,
                q - 0.025,
                2.02,
                w - 0.025,
                q - 0.025,
                2.02,
                0.012,
                "metal",
            )
            for i in range(6):
                box(
                    "FoldedCurtain",
                    -w + 0.015 + i * 0.018,
                    q - 0.05,
                    0.10,
                    -w + 0.028 + i * 0.018,
                    q - 0.015,
                    1.98,
                    "linen_white",
                    0.002,
                )
            beam("RiserPipe", 0, -q + 0.025, 0.85, 0, -q + 0.025, 1.87, 0.012, "metal")
            beam("ShowerArm", 0, -q + 0.025, 1.87, 0, -q + 0.18, 1.94, 0.012, "metal")
            beam("ShowerRose", 0, -q + 0.18, 1.93, 0, -q + 0.18, 1.95, 0.045, "metal")
        else:
            raise ValueError(("Unhandled furnishing", k))
        d.furniture.append(
            dict(
                owner=d.owner,
                plan=p["id"],
                id=f["id"],
                kind=k,
                source_bounds=b,
                source_facing=f["facing"],
                object_ids=[x["id"] for x in d.objects[start:]],
            )
        )


def build(data, site):
    d = Design(data, site)
    for p in data["plans"]:
        build_floor(d, p)
        furniture(d, p)
        if p["level_index"] == 0:
            build_stair(d, p)
        else:
            build_roof(d, p)
    # Site platform is restrained: actualFFs, independent foundation plinths, graded source site profile separate.
    d.plan = None
    d.owner = None
    d.asset = "StudySupport"
    d.room = ""
    for owner in site["new_owners"]:
        x, y = owner["center"]
        w = owner["width"]
        dep = owner["depth"]
        ff = owner["finished_floor_z_m"]
        d.box(
            "GraniteFoundation",
            [
                x - w / 2,
                y - dep / 2,
                owner["pad_level_m"] - 0.40,
                x + w / 2,
                y + dep / 2,
                ff - 0.20,
            ],
            "granite",
            0.01,
            category="site",
        )
    return dict(
        schema="MillCourtConcretePrototypeGeometry.v1",
        units="metres",
        objects=d.objects,
        apertures=d.apertures,
        furniture=d.furniture,
        stairs=d.stairs,
        rooflight_interpretation=dict(
            owner="PROPOSED_Core_MillCourt_B",
            ceiling_xy=[1.2, 1.9, 1.8, 2.5],
            roof_xy=[1.2, 1.7, 1.8, 2.3],
            reason="20cm south splay keeps glazing clearofridge; ceiling plan exact",
        ),
        partition_join_resolution=dict(
            plan="B_Upper",
            wall="child_n",
            reason="Uses coordinated input endpoint directly; generator doesnot override room wall endpoints",
        ),
        source_layout_unchanged=True,
        scope="Two new prototype houses only; art/export/performance review pending",
    )
