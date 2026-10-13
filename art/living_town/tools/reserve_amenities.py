"""Measured reserve visitor amenities, independent of the frozen town kit.

``build(globals(), reserve_plan)`` is called by the owning Blender builder.
Importing this module, planning, and clearance checks need no Blender runtime.
All meshes/collections use Reserve_ names; the existing BUILDINGS and
INTERIOR_RECORDS inventories are deliberately not extended here. The returned
report is the integration contract for additional export/profile ownership.

Local frontage is south (-Y), dimensions are metres, and yaw is counterclockwise
in Blender XY. Pad level is the ground datum, not the finished floor. Collection
and object extras retain room, furnishing, and removable-cover ownership.
"""
from __future__ import annotations

import hashlib
import json
import math
from collections import Counter, deque

SCHEMA = "living_town.reserve_amenities.v1"
WALL = .12
KINDS = {
    "trailer": "trailer", "camping_trailer": "trailer", "mobile_home": "trailer",
    "convenience": "convenience_store", "convenience_store": "convenience_store",
    "souvenir": "souvenir_store", "souvenir_store": "souvenir_store",
    "visitor_reception": "reception", "reception": "reception",
    "public_bathhouse": "bathhouse", "bathhouse": "bathhouse",
    "public_toilets": "toilets", "toilets": "toilets", "food_truck": "food_truck",
    "laundry": "laundry", "laundry_utility": "laundry",
    "maintenance": "maintenance", "utility_service": "maintenance",
    "refuse_service": "refuse", "refuse": "refuse",
}
LABELS = {"convenience_store": "EPICERIE", "souvenir_store": "SOUVENIRS",
          "reception": "ACCUEIL", "bathhouse": "DOUCHES", "toilets": "TOILETTES",
          "food_truck": "SANDWICHS  /  HOT DOGS", "laundry": "LAVERIE",
          "maintenance": "SERVICE", "refuse": "TRI  /  RECYCLAGE"}


def _rect(cx, cy, w, d, angle=0):
    a = math.radians(angle)
    hx = abs(math.cos(a))*w/2 + abs(math.sin(a))*d/2
    hy = abs(math.sin(a))*w/2 + abs(math.cos(a))*d/2
    return [cx-hx, cy-hy, cx+hx, cy+hy]


def _inside(p, bounds, margin=0):
    return bounds[0]+margin <= p[0] <= bounds[2]-margin and bounds[1]+margin <= p[1] <= bounds[3]-margin


def _overlap(a, b, tolerance=.002):
    return min(a[2], b[2])-max(a[0], b[0]) > tolerance and min(a[3], b[3])-max(a[1], b[1]) > tolerance


def _ident(source):
    value = str(source)
    if not value or not all(c.isalnum() or c == "_" for c in value):
        raise ValueError("Reserve amenity ID must contain only letters, numbers and underscores: " + value)
    return value if value.startswith("Reserve_") else "Reserve_" + value


def _pad_level(record, reserve_plan):
    if "pad_level_m" in record:
        return float(record["pad_level_m"])
    pads = reserve_plan.get("pads", [])
    if isinstance(pads, dict):
        pads = [{"id": k, **v} for k, v in pads.items()]
    matches = [p for p in pads if p["id"] == record.get("pad_id")]
    if len(matches) != 1:
        raise ValueError("Missing unique pad for " + str(record["id"]))
    return float(matches[0]["level_m"])


def plan_amenity(record, reserve_plan):
    """Return explicit local zoning, physical door holes, and asset approaches."""
    ident = _ident(record["id"])
    if record["kind"] not in KINDS:
        raise ValueError("Unsupported reserve amenity kind: " + record["kind"])
    kind = KINDS[record["kind"]]
    w, d = float(record["width"]), float(record["depth"])
    if int(record.get("floors", 1)) != 1:
        raise ValueError("Reserve amenity kit supports exactly one storey: " + ident)
    x0, y0, x1, y1 = -w/2+.16, -d/2+.16, w/2-.16, d/2-.16
    entry = list(record["entry_local"])
    if len(entry) != 2 or abs(entry[1]+d/2) > .01:
        raise ValueError("Entry must be on the authored south frontage: " + ident)
    pad = _pad_level(record, reserve_plan)
    offset = .45 if kind in ("trailer", "food_truck") else .18
    ff = float(record.get("finished_floor_z_m", pad+offset))-pad
    plan = {"id": ident, "source_id": record["id"], "kind": kind,
            "center": list(record["center"]), "yaw_degrees": float(record.get("yaw_degrees", 0)),
            "width": w, "depth": d, "pad_id": record.get("pad_id"), "pad_level_m": pad,
            "finished_floor_local_z_m": ff, "finished_floor_z_m": pad+ff,
            "entry_local": entry, "entry_width_m": .80 if kind == "trailer" else .70 if kind == "food_truck" else 1.10,
            "wall_height_m": 2.23 if kind == "trailer" else 2.40 if kind == "food_truck" else 2.80,
            "clear_bounds_m": [x0, y0, x1, y1], "rooms": [], "partitions": [],
            "assets": [], "circulation_keepouts": [], "variant": record.get("variant", 0)}

    def room(name, purpose, bounds, finish="Oak"):
        r = {"id": ident+"_L00_"+name, "name": name, "purpose": purpose,
             "bounds_m": list(bounds), "floor_index": 0, "finish": finish}
        plan["rooms"].append(r)
        return r

    def wall(axis, coordinate, lo, hi, doors=(), height=None):
        plan["partitions"].append({"axis": axis, "coordinate_m": coordinate,
            "span_m": [lo, hi], "thickness_m": WALL,
            "height_m": height or plan["wall_height_m"]-.08,
            "openings": [{"center_m": c, "width_m": s, "bottom_m": 0., "height_m": 1.96 if kind == "trailer" else 2.10,
                          "kind": "door"} for c, s in doors]})

    def asset(r, name, typ, xy, dims, rot=0, approach=None, accent="Sage", **extras):
        a = {"id": r["id"]+"_"+name, "kind": typ, "room_id": r["id"],
             "center_m": list(xy), "dimensions_m": list(dims), "rotation_degrees": rot,
             "accent": accent, "footprint_m": _rect(*xy, *dims[:2], rot),
             "approach_local_m": list(approach) if approach is not None else [xy[0], xy[1]-dims[1]/2-.35], **extras}
        if typ == "kitchen":
            a["integrated_fixtures"] = ["recessed_sink", "tap", "two_ring_hob", "undercounter_fridge"]
        if typ in ("booth", "lounge_dining", "picnic"):
            a["integrated_seating"] = 4 if typ != "lounge_dining" else 2
        plan["assets"].append(a)
        return a

    if kind == "trailer":
        if w < 3.2 or d < 8.2:
            raise ValueError("Detailed trailer layout requires at least3.2x8.2m: " + ident)
        n = int(record.get("variant", record.get("lot_number", 0)))
        family, mirror = n % 4, bool((n//4) % 2)
        accent = ("Sage", "BluePaint", "Burgundy", "TealCloth")[n % 4]
        plan["lot_number"] = n+1
        plan["variant"] = {"family": ("double_booth", "twin_booth", "family_bunks", "double_lounge")[family],
                           "mirrored": mirror, "accent": accent}
        living = room("Living_Dining", "entry, shared dining and lounge", [x0, y0, x1, -1.45])
        room("Lounge_Transition", "open dry transition beside bathroom", [x0, -1.45, -.15, .15])
        bath = room("Private_Bathroom", "private wet shower, toilet and handwash", [x0, .15, -.15, 1.95], "Tile")
        hall = room("Galley_Aisle", "continuous kitchen and bedroom circulation", [-.15, -1.45, x1, 1.95], "Tile")
        bedroom = room("Sleeping", "private sleeping berths with exterior windows", [x0, 1.95, x1, y1])
        wall("y", .15, x0, -.15)
        wall("x", -.15, .15, 1.95, [(1.00, .72)])
        wall("y", 1.95, x0, x1, [(.36 if family == 1 else .90, .78)])
        if family in (0, 1):
            asset(living, "Booth", "booth", (-.88, -2.45), (1.16, 1.98, .85), approach=(.36, -2.45), accent=accent)
        else:
            asset(living, "Lounge_Dining", "lounge_dining", (-.70, -2.45), (1.56, 1.98, .85), approach=(.38, -2.45), accent=accent)
        asset(living, "Entry_Storage", "cabinet", (1.18, -3.12), (.80, .52, 1.55), -90, (.51, -3.12), accent)
        asset(hall, "Galley", "kitchen", (1.18, .15), (2.60, .56, .92), -90, (.55, .15), accent)
        asset(bath, "Wet_Shower", "shower", (-1.06, 1.49), (.70, .70, 1.95), approach=(-1.06, 1.49), walkable_surface=True)
        asset(bath, "WC", "toilet", (-1.07, .65), (.46, .62, .72), 90, (-.49, .65))
        asset(bath, "Handwash", "basin", (-.40, 1.67), (.43, .28, .85), approach=(-.40, 1.16))
        if family == 1:
            for side, sx in (("Left", -.98), ("Right", .98)):
                asset(bedroom, "Twin_"+side, "bed", (sx, 3.04), (.72, 1.94, .75), approach=(0, 2.85), accent=accent)
        elif family == 2:
            asset(bedroom, "Bunks", "bunk", (-.97, 3.03), (.82, 1.94, 1.84), approach=(.05, 2.9), accent=accent)
            asset(bedroom, "Family_Cupboard", "cabinet", (1.16, 3.46), (.92, .52, 1.62), -90, (.52, 3.46), accent)
        else:
            asset(bedroom, "Double_Bed", "bed", (-.56, 3.03), (1.34 if family == 0 else 1.22, 1.94, .78), approach=(.65, 3.00), accent=accent)
        plan["circulation_keepouts"] = [[-.25, y0, .32, -3.45], [.20, -3.45, .80, 1.55]]
        if mirror:
            for r in plan["rooms"]:
                a, b, c, e = r["bounds_m"];r["bounds_m"] = [-c, b, -a, e]
            for a in plan["assets"]:
                a["center_m"][0] *= -1;a["approach_local_m"][0] *= -1;a["rotation_degrees"] *= -1
                a["footprint_m"] = _rect(*a["center_m"], *a["dimensions_m"][:2], a["rotation_degrees"])
            for p in plan["partitions"]:
                if p["axis"] == "x":p["coordinate_m"] *= -1
                else:
                    p["span_m"] = [-p["span_m"][1], -p["span_m"][0]]
                    for o in p["openings"]:o["center_m"] *= -1
            plan["circulation_keepouts"] = [[-c, b, -a, e] for a, b, c, e in plan["circulation_keepouts"]]
    elif kind in ("convenience_store", "souvenir_store", "reception"):
        public = room("Visitor_Retail", "visitor information" if kind == "reception" else "public retail browsing", [x0, y0, x1, 1.5], "Tile")
        staff = room("Staff", "staff desk, coats and rest", [x0, 1.5, -.25, y1])
        stock = room("Stock", "separate stock and cleaning storage", [-.25, 1.5, x1, y1])
        wall("y", 1.5, x0, x1, [(-1.65, .92), (2.15, .92)])
        wall("x", -.25, 1.5, y1)
        side = -1 if kind == "souvenir_store" else 1
        asset(public, "Service_Counter", "counter", (side*(w/2-1.55), -2.12), (2.25, .65, 1.03), approach=(side*(w/2-1.55), -2.86), accent="BluePaint" if kind == "souvenir_store" else "Sage")
        if kind == "convenience_store":
            for j, x in enumerate((-1.70, 1.70)):
                asset(public, "Gondola_%d" % j, "grocery_gondola", (x, -.10), (2.0, .65, 1.45),
                      90 if x<0 else -90, approach=(x+(.75 if x < 0 else -.75), -.10))
            asset(public, "Wall_Groceries", "grocery_shelf", (x0+.23, -.15), (2.60, .40, 1.90), 90, (x0+1.0, -.15))
        elif kind == "souvenir_store":
            asset(public, "Postcards_Books", "souvenir_shelf", (x1-.23, -.10), (2.50, .40, 1.85), -90, (x1-1.0, -.10), "BluePaint")
            asset(public, "Ceramic_Island", "display", (1.70, -.20), (1.25, 1.25, .86), approach=(.72, -.20), accent="Sage")
            asset(public, "Folded_Linen", "souvenir_shelf", (-1.55, .45), (1.45, .40, 1.60), approach=(-1.55, -.20), accent="Burgundy")
        else:
            asset(public, "Map_Desk", "display", (-2.30, -.65), (1.65, .90, .88), approach=(-2.30, -1.45), accent="BluePaint", map_display=True)
            asset(public, "Waiting_Bench", "bench", (x0+.35, -1.35), (1.80, .55, .85), 90, (x0+1.1, -1.35))
            asset(public, "Leaflet_Rack", "souvenir_shelf", (1.60, .45), (1.45, .40, 1.65), approach=(1.60, -.20))
        asset(staff, "Staff_Desk", "desk", (-2.65, y1-.65), (1.55, 1.05, 1.0), approach=(-2.65, 1.80))
        asset(stock, "Stock_Rack", "stock_shelf", (2.10, y1-.27), (2.90, .46, 1.90), approach=(2.10, y1-1.0))
        plan["circulation_keepouts"] = [[-.60, y0, .60, 1.5]]
    elif kind == "bathhouse":
        if w < 13.8 or d < 8.8:raise ValueError("Bathhouse program requires14x9m: " + ident)
        hall = room("Entry_Hall", "clear central entry and through circulation", [-.8, y0, .8, y1], "Tile")
        west = room("Changing_West", "dry changing, lockers and benches", [x0, y0, -.8, -.4], "Tile")
        east = room("Changing_East", "dry changing and family lockers", [.8, y0, x1, -.4], "Tile")
        washw = room("Wash_West", "handwash and shower approach", [x0, -.4, -.8, 1.5], "Tile")
        washe = room("Wash_East", "handwash and private compartment approach", [.8, -.4, x1, 1.5], "Tile")
        for co in (-.8, .8):wall("x", co, y0, y1, [(-2.15, 1.0), (.55, 1.0)])
        for a, b in ((x0, -.8), (.8, x1)):wall("y", -.4, a, b, [((a+b)/2, 1.0)])
        step = (-.8-x0)/4
        for i in range(4):
            lo, hi = x0+i*step, x0+(i+1)*step;cx=(lo+hi)/2
            shower = room("Private_Shower_%d" % (i+1), "private shower and dry changing cubicle", [lo, 1.5, hi, y1], "Tile")
            wall("y", 1.5, lo, hi, [(cx, .82)])
            if i:wall("x", lo, 1.5, y1)
            asset(shower, "Shower", "shower", (cx, y1-.60), (1.0, 1.0, 2.1), approach=(cx, y1-.60), walkable_surface=True)
            asset(shower, "Dry_Bench", "bench", (lo+.20, 2.45), (.70, .30, .55), 90, (cx, 2.45))
        family = room("Family_Shower", "larger private shower and seat", [.8, 1.5, 3.5, y1], "Tile")
        wc = room("Bathhouse_WC", "private toilet compartment", [3.5, 1.5, 5.0, y1], "Tile")
        cleaner = room("Linen_Cleaner", "clean towels and utility sink", [5.0, 1.5, x1, y1], "Tile")
        for lo, hi, doorw in ((.8, 3.5, 1.), (3.5, 5.0, .82), (5.0, x1, .82)):
            wall("y", 1.5, lo, hi, [((lo+hi)/2, doorw)])
        for xx in (3.5, 5.0):wall("x", xx, 1.5, y1)
        asset(family, "Family_Shower", "shower", (2.20, y1-.70), (1.35, 1.15, 2.1), approach=(2.20, y1-.70), walkable_surface=True, grab_rails=True)
        asset(family, "Changing_Seat", "bench", (1.15, 2.45), (.85, .40, .65), 90, (1.85, 2.45))
        asset(wc, "WC", "toilet", (4.25, y1-.55), (.52, .72, .8), approach=(4.25, y1-1.30))
        asset(cleaner, "Linen", "cabinet", (5.95, y1-.28), (1.25, .45, 1.85), approach=(5.95, y1-1.0))
        asset(cleaner, "Utility_Sink", "basin", (x1-.28, 2.35), (.60, .45, .85), -90, (x1-1.0, 2.35))
        for r, side in ((west, -1), (east, 1)):
            asset(r, "Lockers", "lockers", (side*3.85, y0+.30), (4.10, .50, 1.9), 180, (side*3.85, y0+1.05))
            asset(r, "Changing_Bench", "bench", (side*3.85, -1.80), (2.60, .55, .58), approach=(side*3.85, -1.10))
        for i in range(2):asset(washw, "Washbasin_%d" % i, "basin", (x0+.30, .05+i*.85), (.55, .45, .85), 90, (x0+1.0, .05+i*.85))
        for i in range(2):asset(washe, "Washbasin_%d" % i, "basin", (4.5+i*.9, -.10), (.55, .45, .85), 180, (4.5+i*.9, .65))
        plan["circulation_keepouts"] = [[-.70, y0, .70, y1]]
    elif kind == "toilets":
        wash = room("Wash_Entry", "shared entrance and handwash", [x0, y0, x1, -.20], "Tile")
        cells = [("Larger_WC", x0, -.6, 1.05), ("WC_2", -.6, 1.3, .82), ("WC_3", 1.3, x1, .82)]
        for name, lo, hi, doorw in cells:
            r = room(name, "private toilet compartment with grab rails" if name == "Larger_WC" else "private toilet compartment", [lo, -.20, hi, y1], "Tile")
            cx=(lo+hi)/2;wall("y", -.20, lo, hi, [(cx, doorw)])
            if lo != x0:wall("x", lo, -.20, y1)
            asset(r, "WC", "toilet", (lo+.50 if name == "Larger_WC" else cx, y1-.58), (.52, .72, .8), approach=(lo+1.15 if name == "Larger_WC" else cx, y1-1.35), grab_rails=name == "Larger_WC")
        for side in (-1, 1):asset(wash, "Basin_"+str(side), "basin", (side*2.25, y0+.28), (.70, .45, .85), 180, (side*2.25, y0+1.0))
        asset(wash, "Baby_Change", "changing_table", (x1-.28, -1.0), (.90, .45, .95), -90, (x1-1.0, -1.0))
        plan["circulation_keepouts"] = [[-.65, y0, .65, -.35]]
    elif kind == "food_truck":
        if entry[0] < 2.4:raise ValueError("Food truck staff entry must clear the service hatch: " + ident)
        cab = room("Cab", "driver cab separated from food preparation", [x0, y0, -2.0, y1], "Iron")
        kitchen = room("Prep_Service", "food preparation, serving hatch and clear staff aisle", [-2.0, y0, x1, y1], "Tile")
        wall("x", -2.0, y0, y1, height=2.1)
        asset(cab, "Driver_Seat", "driver_seat", (-2.65, .25), (.62, .65, 1.05), 90, (-2.65, -.45), nonpublic=True)
        asset(kitchen, "Rear_Prep", "kitchen", (-.15, .90), (3.40, .48, .95), approach=(-.15, .20), accent="White")
        asset(kitchen, "Serving_Counter", "food_counter", (-.25, -.91), (3.40, .44, 1.05), 180, (-.25, -.20), accent="BluePaint")
        asset(kitchen, "Cold_Storage", "fridge", (2.73, .82), (.70, .58, 1.85), approach=(2.73, .10))
        plan["service_hatch"] = {"center_m": -.25, "width_m": 3.40, "bottom_m": 1.05, "height_m": 1.06}
        plan["circulation_keepouts"] = [[-1.85, -.48, 3.15, .43]]
    elif kind == "laundry":
        public = room("Laundry", "washing, drying, folding and waiting", [x0, y0, x1, 1.4], "Tile")
        utility = room("Laundry_Utility", "water heater, cleaning sink and supplies", [x0, 1.4, x1, y1], "Tile")
        wall("y", 1.4, x0, x1, [(2.6, .92)])
        for i in range(3):asset(public, "Washer_%d" % i, "washer", (x0+.43, -1.6+i), (.78, .72, .90), 90, (x0+1.25, -1.6+i))
        for i in range(2):asset(public, "Dryer_%d" % i, "washer", (-2.2+i*1.1, 1.0), (.82, .72, .90), approach=(-2.2+i*1.1, .15), dryer=True)
        asset(public, "Folding_Table", "workbench", (1.8, -.45), (2.0, .85, .88), approach=(1.8, -1.30))
        asset(public, "Waiting_Bench", "bench", (-1.8, y0+.30), (1.50, .45, .62), 180, (-1.8, y0+1.0))
        asset(utility, "Utility_Sink", "basin", (-2.50, y1-.27), (.80, .45, .85), approach=(-2.5, y1-1.0))
        asset(utility, "Water_Heater", "heater", (-.70, y1-.32), (.65, .55, 1.85), approach=(-.7, y1-1.0))
        asset(utility, "Supplies", "cabinet", (1.0, y1-.25), (1.4, .42, 1.85), approach=(1.0, y1-.95))
    elif kind == "maintenance":
        workshop = room("Maintenance", "repair bench and shared utility circulation", [x0, y0, x1, .8], "Tile")
        depot = room("Service_Store", "locked tools, water and electrical equipment", [x0, .8, x1, y1], "Tile")
        wall("y", .8, x0, x1, [(1.8, .92)])
        asset(workshop, "Repair_Bench", "workbench", (x1-.42, -.55), (2.05, .70, .93), -90, (x1-1.20, -.55), tools=True)
        asset(workshop, "Tool_Rack", "stock_shelf", (x0+.25, -.25), (1.90, .40, 1.85), 90, (x0+1.05, -.25))
        asset(depot, "Service_Heater", "heater", (-2.20, y1-.30), (.68, .50, 1.85), approach=(-2.20, y1-1.0))
        asset(depot, "Parts", "stock_shelf", (.0, y1-.25), (2.0, .42, 1.85), approach=(.0, y1-1.0))
    else:
        r = room("Recycling_Service", "covered sorting, refuse and utility access", [x0, y0, x1, y1], "Paving")
        for i, x in enumerate((-2.0, -.90, 1.0, 2.0)):
            asset(r, "Sorting_Bin_%d" % i, "bin", (x, y1-.43), (.72, .68, 1.1), approach=(x, y1-1.25), accent=("Sage", "BluePaint", "Ochre", "Ink")[i])
        asset(r, "Service_Locker", "cabinet", (x1-.32, -.70), (.85, .52, 1.65), -90, (x1-1.05, -.70))
    plan["open_door_leaves"] = _interior_door_leaves(plan)
    return plan


def _interior_door_leaves(plan):
    """Park actual hinged/bifold leaves beside their clear door apertures.

    Compact cubicles use a folded stack; larger staff-room doors use one leaf.
    The chosen jamb and wall face must fit inside the shell and avoid furniture.
    These exact footprints also participate in the clearance audit below.
    """
    result=[]
    protected=[a["approach_local_m"] for a in plan["assets"] if not a.get("nonpublic")]
    for partition in plan["partitions"]:
        for opening in partition["openings"]:
            protected.extend([(partition["coordinate_m"]+delta,opening["center_m"]) if partition["axis"]=="x" else(opening["center_m"],partition["coordinate_m"]+delta) for delta in(-.25,0,.25)])
    for pi,p in enumerate(plan["partitions"]):
        lo,hi=p["span_m"]
        for oi,o in enumerate(p["openings"]):
            width=o["width_m"];c=o["center_m"];chosen=None
            for folds in (1,2,4,8):
                length=(width-.08)/folds
                for side in (1,-1):
                    edge=c+side*width/2;u=edge+side*(length/2+.035)
                    if u-length/2<lo+.01 or u+length/2>hi-.01:continue
                    for normal in (-1,1):
                        panels=[]
                        for j in range(folds):
                            co=p["coordinate_m"]+normal*(WALL/2+.035+j*.034)
                            xy=(co,u) if p["axis"]=="x" else(u,co)
                            dims=(.027,length) if p["axis"]=="x" else(length,.027)
                            panels.append({"center_m":list(xy),"dimensions_m":[*dims,o["height_m"]-.05],
                                           "footprint_m":_rect(*xy,*dims)})
                        if any(not _inside((v[0],v[1]),plan["clear_bounds_m"],-.01) or not _inside((v[2],v[3]),plan["clear_bounds_m"],-.01) for v in [q["footprint_m"] for q in panels]):continue
                        if any(_overlap(q["footprint_m"],a["footprint_m"],.001) for q in panels for a in plan["assets"]):continue
                        if any((x-max(a,min(x,c)))**2+(y-max(b,min(y,e)))**2<.23**2 for x,y in protected for a,b,c,e in [q["footprint_m"] for q in panels]):continue
                        if any(_overlap(q["footprint_m"],s["footprint_m"],.001) for q in panels for old in result for s in old["panels"]):continue
                        chosen={"id":plan["id"]+"_Door_%02d_%02d"%(pi,oi),"partition_index":pi,
                                "opening_index":oi,"folded_panels":folds,"jamb_side":side,"wall_face":normal,
                                "state":"open alongside partition","clear_aperture_width_m":width,"panels":panels}
                        break
                    if chosen:break
                if chosen:break
            if chosen is None:raise ValueError("No furniture-clear parked door leaf for "+plan["id"]+" partition "+str(pi))
            result.append(chosen)
    return result


def validate_plan(plan, cell=.10, radius=.20):
    """Actual entrance seed and reachable furnishing fronts; never snap to free space.

    Low shower trays are walkable surfaces. A non-public truck cab is explicitly
    excluded from staff aisle reachability, not magically connected to it.
    This is a dimensional occupancy check, not a building-code certification.
    """
    errors=[];bounds=plan["clear_bounds_m"]
    rooms={r["id"]:r for r in plan["rooms"]}
    solids=[]
    for i,r in enumerate(plan["rooms"]):
        for other in plan["rooms"][i+1:]:
            if _overlap(r["bounds_m"],other["bounds_m"]):errors.append(r["id"]+" overlaps room "+other["id"])
    for a in plan["assets"]:
        f=a["footprint_m"];r=rooms[a["room_id"]]["bounds_m"]
        if not all(_inside(p,r,-.015) for p in ((f[0],f[1]),(f[2],f[3]))):errors.append(a["id"]+": footprint outside own room")
        if not a.get("walkable_surface"):solids.append((a["id"],f))
    for i,a in enumerate(plan["assets"]):
        for b in plan["assets"][i+1:]:
            if _overlap(a["footprint_m"],b["footprint_m"]):errors.append(a["id"]+" overlaps "+b["id"])
    for p in plan["partitions"]:
        lo,hi=p["span_m"];cuts=sorted([lo,hi]+[o["center_m"]+s*o["width_m"]/2 for o in p["openings"] for s in(-1,1)])
        for o in p["openings"]:
            if o["center_m"]-o["width_m"]/2<lo or o["center_m"]+o["width_m"]/2>hi:errors.append("Door outside partition "+str(p))
        for a,b in zip(cuts,cuts[1:]):
            if any(abs((a+b)/2-o["center_m"])<o["width_m"]/2 for o in p["openings"]):continue
            co=p["coordinate_m"];half=p["thickness_m"]/2
            solids.append(("partition",[co-half,a,co+half,b] if p["axis"]=="x" else[a,co-half,b,co+half]))
    for leaf in plan["open_door_leaves"]:
        solids.extend((leaf["id"],panel["footprint_m"]) for panel in leaf["panels"])
    def free(point):
        if not _inside(point,bounds,radius-.015):return False
        x,y=point
        for _,(a,b,c,e) in solids:
            # Disc-vs-AABB clearance avoids diagonal false blockages.
            if (x-max(a,min(x,c)))**2+(y-max(b,min(y,e)))**2 < (radius-.005)**2:return False
        return True
    seed=(plan["entry_local"][0],bounds[1]+radius)
    if not free(seed):errors.append("Actual exterior threshold seed is obstructed")
    nx=int((bounds[2]-bounds[0])/cell)+1;ny=int((bounds[3]-bounds[1])/cell)+1
    def pos(n):return(bounds[0]+n[0]*cell,bounds[1]+n[1]*cell)
    def exact_node(p):
        if not free(p):return None
        n=(round((p[0]-bounds[0])/cell),round((p[1]-bounds[1])/cell))
        return n if 0<=n[0]<nx and 0<=n[1]<ny and free(pos(n)) else None
    start=exact_node(seed);seen={start} if start else set();queue=deque(seen)
    while queue:
        i,j=queue.popleft()
        for nxt in ((i-1,j),(i+1,j),(i,j-1),(i,j+1)):
            if 0<=nxt[0]<nx and 0<=nxt[1]<ny and nxt not in seen and free(pos(nxt)):
                seen.add(nxt);queue.append(nxt)
    for a in plan["assets"]:
        if a.get("nonpublic"):continue
        p=a["approach_local_m"];n=exact_node(p)
        if n not in seen:errors.append(a["id"]+": exact approach obstructed or disconnected")
    for r in plan["rooms"]:
        if r["name"]=="Cab":continue
        if not any(_inside(pos(n),r["bounds_m"],.05) for n in seen):errors.append(r["id"]+": room unreachable")
    threshold_samples=[]
    for side in(-1,0,1):
        point=(seed[0]+side*(plan["entry_width_m"]/2-radius-.025),seed[1])
        threshold_samples.append(list(point))
        if exact_node(point) not in seen:errors.append("Exterior threshold sweep obstructed: "+str(point))
    interior_door_samples=[]
    for p in plan["partitions"]:
        for o in p["openings"]:
            for delta in(-.25,0,.25):
                point=(p["coordinate_m"]+delta,o["center_m"]) if p["axis"]=="x" else(o["center_m"],p["coordinate_m"]+delta)
                interior_door_samples.append(list(point))
                if exact_node(point) not in seen:errors.append("Interior door crossing obstructed: "+str(point))
    return {"status":"PASS" if not errors else "FAIL","id":plan["id"],"errors":errors,
            "cell_m":cell,"body_radius_m":radius,"exact_entry_seed_m":list(seed),
            "reachable_cells":len(seen),"room_count":len(rooms),"asset_count":len(plan["assets"]),
            "threshold_sweep_samples_m":threshold_samples,"interior_door_crossing_samples_m":interior_door_samples,
            "open_door_count":len(plan["open_door_leaves"]),"no_nearest_free_seed":True,"rendered_qa":False}


def plan_reserve(reserve_plan):
    plans=[];trailer_index=0
    for record in reserve_plan["buildings"]:
        r=dict(record)
        if KINDS.get(r["kind"])=="trailer":
            r.setdefault("variant",trailer_index);trailer_index+=1
        plans.append(plan_amenity(r,reserve_plan))
    ids=[p["id"] for p in plans]
    if len(set(ids))!=len(ids):raise ValueError("Duplicate Reserve_ amenity ID")
    return plans


def _wall(batch, axis, coordinate, span, height, holes, material, bottom, thickness=WALL):
    lo,hi=span
    cuts=sorted(set([lo,hi]+[o["center_m"]+s*o["width_m"]/2 for o in holes for s in(-1,1)]))
    zs=sorted(set([0.,height]+[o["bottom_m"]+v for o in holes for v in(0,o["height_m"])]))
    for a,b in zip(cuts,cuts[1:]):
        for z0,z1 in zip(zs,zs[1:]):
            if b-a<1e-5 or z1-z0<1e-5:continue
            if any(abs((a+b)/2-o["center_m"])<o["width_m"]/2-1e-6 and o["bottom_m"]<(z0+z1)/2<o["bottom_m"]+o["height_m"] for o in holes):continue
            batch.box((coordinate,(a+b)/2,bottom+(z0+z1)/2) if axis=="x" else((a+b)/2,coordinate,bottom+(z0+z1)/2),
                      (thickness,b-a,z1-z0) if axis=="x" else(b-a,thickness,z1-z0),material)


def _asset_geometry(b, a):
    """Local reusable furnishing geometry. Its -Y face is the working front."""
    w,d,h=a["dimensions_m"];kind=a["kind"];paint=a["accent"]
    def box(x,y,z,ww,dd,hh,mat):b.box((x,y,z),(ww,dd,hh),mat)
    def legs(ww=w,dd=d,top=.73):
        for x in(-ww/2+.07,ww/2-.07):
            for y in(-dd/2+.07,dd/2-.07):b.rod((x,y,.02),(x,y,top),.025,"Iron",n=6)
    def sink(cx,cy,sw,sd,z):
        box(cx,cy,z-.12,sw,sd,.06,"White")
        for x in(cx-sw/2,cx+sw/2):box(x,cy,z-.045,.035,sd,.13,"White")
        for y in(cy-sd/2,cy+sd/2):box(cx,y,z-.045,sw,.035,.13,"White")
        b.rod((cx,cy+sd/2+.045,z),(cx,cy+sd/2+.045,z+.21),.014,"Zinc",n=8)
        b.rod((cx,cy+sd/2+.045,z+.21),(cx,cy,z+.21),.014,"Zinc",n=8)
        b.rod((cx,cy,z+.21),(cx,cy,z+.16),.014,"Zinc",n=8)
        b.rod((cx,cy,z-.085),(cx,cy,z-.080),.022,"Zinc",n=10)
    if kind in("bed","bunk"):
        levels=(.25,1.25) if kind=="bunk" else(.25,)
        for z in levels:
            box(0,0,z,w,d,.20,"Oak");box(0,0,z+.17,w-.045,d-.05,.16,"Linen")
            box(0,-.13,z+.27,w-.06,d*.70,.065,paint);box(0,d*.31,z+.29,w*.80,.35,.11,"White")
        if kind=="bed":box(0,d/2-.04,.54,w,.07,.85,"Oak")
        else:
            for x in(-w/2+.035,w/2-.035):
                for y in(-d/2+.035,d/2-.035):b.rod((x,y,.03),(x,y,1.82),.03,"Oak",n=6)
            for y in(-d/2+.07,d/2-.07):b.rod((-w/2,y,1.65),(w/2,y,1.65),.018,"Oak",n=6)
            for j in range(6):b.rod((w/2-.05,-d*.25,.20+j*.25),(w/2-.05,-d*.25+.38,.20+j*.25),.017,"Iron",n=6)
    elif kind in("booth","lounge_dining"):
        if kind=="booth":
            for side in(-1,1):
                y=side*(d/2-.27);box(0,y,.25,w,.48,.36,"Oak");box(0,y,.47,w-.06,.45,.13,paint)
                box(0,side*(d/2-.045),.67,w,.09,.53,paint)
            box(0,0,.76,w*.86,.68,.07,"Oak");b.rod((0,0,.04),(0,0,.72),.05,"Iron",n=8)
        else:
            box(-w*.27,0,.26,w*.40,d,.36,"Oak");box(-w*.27,0,.49,w*.40-.04,d-.05,.13,paint)
            box(-w*.46,0,.72,.10,d,.50,paint);box(w*.17,0,.70,w*.43,d*.45,.07,"Oak")
            for y in(-d*.15,d*.15):b.rod((w*.17,y,.02),(w*.17,y,.67),.025,"Iron",n=6)
        box(0,0,.81,.14,.20,.025,"Linen");b.rod((.12,0,.80),(.12,0,.88),.045,"White",n=10)
    elif kind in("kitchen","counter","food_counter"):
        box(0,0,.43,w,d,.84,paint)
        if kind=="kitchen":
            sx=-w*.30;sw=min(.52,w*.23);sd=d*.58
            for xa,xb,ya,yb in((-w/2,sx-sw/2,-d/2,d/2),(sx+sw/2,w/2,-d/2,d/2),(sx-sw/2,sx+sw/2,-d/2,-sd/2),(sx-sw/2,sx+sw/2,sd/2,d/2)):
                box((xa+xb)/2,(ya+yb)/2,.90,xb-xa,yb-ya,.06,"Granite")
            sink(sx,0,sw,sd,.92)
            for xx in(-.07,.20):b.rod((xx,0,.94),(xx,0,.949),.075,"Iron",n=14)
            fx=w*.32;fw=w*.25;box(fx,-d/2-.005,.45,fw,.028,.76,"White")
            box(fx,-d/2-.025,.70,.10,.016,.025,"BluePaint")
            b.rod((fx+fw*.32,-d/2-.03,.36),(fx+fw*.32,-d/2-.03,.61),.012,"Zinc",n=6)
            for x in(-w*.29,0):box(x,-d/2-.01,.42,w*.27,.025,.70,paint)
        else:
            box(0,0,h-.04,w+.035,d+.035,.07,"Oak" if kind=="counter" else "Zinc")
            for x in(-w*.30,0,w*.30):box(x,-d/2-.012,.47,w*.28,.028,.72,paint)
            if kind=="food_counter":
                # Sandwich triangles, buns, sausage and separate condiment bottles.
                for i in range(3):
                    x=-w*.28+i*.20
                    b.poly([(x-.06,-.09,h),(x+.06,-.09,h),(x-.06,.09,h),(x-.06,-.09,h+.08),(x+.06,-.09,h+.08),(x-.06,.09,h+.08)],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],"Linen")
                for i in range(2):
                    x=w*.14+i*.28;b.ellipsoid((x,0,h+.04),(.12,.07,.045),"Oak",n=10,rings=4)
                    b.rod((x-.10,0,h+.075),(x+.10,0,h+.075),.027,"Burgundy",n=8)
                for x,mat in((w*.37,"Ochre"),(w*.43,"Burgundy")):
                    b.rod((x,.08,h),(x,.08,h+.20),.035,mat,n=8);b.rod((x,.08,h+.20),(x,.08,h+.24),.012,"White",n=6)
            else:
                box(w*.30,0,h+.07,.32,.24,.10,"Ink");box(w*.30,.06,h+.19,.25,.06,.20,"Iron")
    elif kind=="grocery_gondola":
        # A shop island is shallow and double sided, with its long axis
        # parallel to the aisle. Its back is a central spine, not an end wall.
        box(0,0,h/2,w,.035,h,"Sage")
        for x in(-w/2+.025,w/2-.025):box(x,0,h/2,.05,d,h,"Oak")
        shelves=4
        for j in range(shelves+1):
            z=.06+j*(h-.10)/shelves
            box(0,0,z,w,d,.035,"Oak")
            for side in(-1,1):box(0,side*(d/2-.012),z+.02,w,.018,.045,"Linen")
        for side in(-1,1):
            for j in range(shelves):
                for i in range(8):
                    x=-w/2+(i+.5)*w/8;y=side*d*.28;z=.10+j*(h-.10)/shelves
                    color=("Sage","Ochre","Burgundy","BluePaint")[(i+j)%4]
                    if (i+j)%3:
                        b.rod((x,y,z),(x,y,z+.17),.046,color,n=8)
                        box(x,y+side*.043,z+.09,.06,.008,.07,"Linen")
                    else:box(x,y,z+.09,.13,d*.27,.18,color)
    elif kind in("grocery_shelf","souvenir_shelf","stock_shelf","cabinet","lockers"):
        box(0,d/2-.02,h/2,w,.04,h,"Oak")
        for x in(-w/2+.025,w/2-.025):box(x,0,h/2,.05,d,h,"Oak")
        shelves=max(3,round(h/.40))
        for j in range(shelves+1):box(0,0,.06+j*(h-.10)/shelves,w,d,.035,"Oak")
        if kind in("cabinet","lockers"):
            count=max(2,round(w/.42)) if kind=="lockers" else 2
            for i in range(count):
                x=-w/2+(i+.5)*w/count;box(x,-d/2-.008,h/2,w/count-.025,.025,h-.05,paint)
                b.rod((x+w/count*.27,-d/2-.035,h*.48),(x+w/count*.27,-d/2-.035,h*.57),.011,"Brass",n=6)
        else:
            count=max(3,int(w/.22))
            for j in range(shelves):
                for i in range(count):
                    x=-w/2+(i+.5)*w/count;z=.10+j*(h-.10)/shelves
                    if kind=="grocery_shelf":
                        b.rod((x,-.02,z),(x,-.02,z+.15),.045,("Sage","Ochre","Burgundy")[i%3],n=8)
                    elif kind=="souvenir_shelf" and (i+j)%2:
                        b.ellipsoid((x,-.02,z+.07),(.06,.06,.08),"White",n=8,rings=4)
                    else:box(x,-.015,z+.095,.12,d*.70,.18,("Linen","BluePaint","Sage","Burgundy")[i%4])
    elif kind in("bench","desk","workbench","display","changing_table"):
        top=.47 if kind=="bench" else .80 if kind=="desk" else h-.06
        if kind=="desk":
            # The recorded footprint contains the desk and its chair. Reserve
            # its rear .60m for the desktop, leaving the chair back in front
            # rather than cutting through a full-depth tabletop.
            desktop_d=.60;desktop_y=(d-desktop_d)/2
            box(0,desktop_y,top,w,desktop_d,.065,"Oak")
            for x in(-w/2+.07,w/2-.07):
                for y in(desktop_y-desktop_d/2+.07,desktop_y+desktop_d/2-.07):
                    b.rod((x,y,.02),(x,y,top-.0325),.025,"Iron",n=6)
        else:
            box(0,0,top,w,d,.065,"Oak");legs(top=top)
        if kind=="bench":
            box(0,d*.40,.70,w,.065,.40,"Oak")
        elif kind=="desk":
            box(0,desktop_y,top+.045,.35,.28,.025,"Linen")
            box(w*.28,desktop_y+.10,top+.1125,.22,.19,.16,"BluePaint")
            # The chair is an integrated part of the recorded desk footprint.
            seat_y=-d*.32;seat_d=d*.28
            box(0,seat_y,.46,.40,seat_d,.10,"Oak");box(0,-d*.44,.68,.40,.06,.42,"Oak")
            for x in(-.14,.14):
                for y in(seat_y-seat_d/2+.045,seat_y+seat_d/2-.045):
                    b.rod((x,y,.02),(x,y,.41),.018,"Iron",n=6)
        elif kind=="display":
            if a.get("map_display"):
                box(0,0,top+.045,w*.84,d*.80,.015,"Linen")
                for i in range(5):box(-w*.33+i*w*.16,0,top+.056,.012,d*.70,.007,"BluePaint")
            else:
                for i in range(4):b.ellipsoid((-w*.30+i*w*.20,0,top+.12),(.09,.09,.12),"White",n=8,rings=4)
        elif kind=="changing_table":box(0,0,top+.06,w-.08,d-.06,.08,"Linen")
        elif a.get("tools"):
            for x in(-.45,.20):b.rod((x,0,top+.05),(x+.18,0,top+.05),.025,"Zinc",n=6)
    elif kind=="basin":
        box(0,0,.45,w*.88,d*.85,.75,"White");sink(0,0,w*.78,d*.70,.86)
        box(0,d/2+.018,1.35,w*.86,.025,.55,"Glass")
        for x in(-w*.44,w*.44):box(x,d/2+.005,1.35,.025,.04,.57,"Zinc")
    elif kind=="toilet":
        b.ellipsoid((0,-d*.10,.35),(w*.43,d*.35,.30),"White",n=12,rings=6)
        box(0,d*.32,.56,w*.80,d*.22,.43,"White")
        b.rod((0,-d*.10,.62),(0,-d*.10,.635),w*.35,"Ink",n=14)
        b.rod((0,-d*.10,.636),(0,-d*.10,.653),w*.42,"White",n=14)
        box(0,d*.31,.79,.06,.04,.012,"Zinc")
        if a.get("grab_rails"):
            b.rod((w*.65,-d*.3,.72),(w*.65,d*.35,.72),.018,"Zinc",n=8)
    elif kind=="shower":
        box(0,0,.025,w,d,.05,"White")
        b.rod((0,0,.052),(0,0,.058),.04,"Zinc",n=10)
        y=d/2-.035;b.rod((w*.28,y,.85),(w*.28,y,1.85),.017,"Zinc",n=8)
        b.rod((w*.28,y,1.85),(w*.28,y-.22,1.91),.017,"Zinc",n=8)
        b.rod((w*.28,y-.22,1.89),(w*.28,y-.22,1.92),.075,"Zinc",n=12)
        box(w*.28,y-.02,1.05,.14,.07,.06,"Zinc")
        b.rod((-w/2+.03,-d/2+.02,1.98),(w/2-.03,-d/2+.02,1.98),.015,"Zinc",n=8)
        # Curtain is drawn aside; the actual entry and shower standing area stay clear.
        box(-w*.41,-d/2+.015,1.18,w*.13,.025,1.55,"Canvas")
    elif kind=="washer":
        box(0,0,h/2,w,d,h,"White");box(0,-d/2-.008,h*.83,w*.92,.022,.18,"Zinc")
        b.rod((0,-d/2-.03,h*.43),(0,-d/2-.06,h*.43),w*.30,"Iron",n=18)
        b.rod((0,-d/2-.062,h*.43),(0,-d/2-.067,h*.43),w*.23,"Glass",n=18)
        b.rod((w*.28,-d/2-.025,h*.83),(w*.28,-d/2-.045,h*.83),.045,"Ink",n=10)
    elif kind=="heater":
        b.rod((0,0,.10),(0,0,h),min(w,d)*.43,"White",n=14)
        for x in(-.12,.12):b.rod((x,0,.02),(x,0,h+.08),.015,"Zinc",n=8)
        box(0,-d*.45,h*.60,.16,.035,.20,"Ink")
    elif kind=="fridge":
        box(0,0,h/2,w,d,h,"White")
        for z in(h*.30,h*.77):box(0,-d/2-.008,z,w-.035,.025,h*.43,"White")
        b.rod((w*.32,-d/2-.035,h*.55),(w*.32,-d/2-.035,h*.85),.016,"Zinc",n=8)
    elif kind=="bin":
        box(0,0,h*.45,w,d,h*.85,paint);box(0,0,h*.90,w+.025,d+.025,.08,"Ink")
        for x in(-w*.30,w*.30):b.rod((x,d*.35,.06),(x,d*.35,.13),.07,"Iron",n=8)
        box(0,-d/2-.012,h*.57,.18,.018,.15,"White")
    elif kind=="driver_seat":
        box(0,0,.40,w,d*.75,.14,"Ink");box(0,d*.35,.70,w,.12,.65,"Ink")
        b.rod((0,0,.05),(0,0,.36),.08,"Iron",n=8)
    elif kind=="picnic":
        box(0,0,.75,w,d*.40,.08,"Oak")
        for side in(-1,1):
            box(0,side*d*.38,.46,w,d*.23,.07,"Oak")
            for x in(-w*.35,w*.35):b.rod((x,side*d*.46,.02),(x,0,.73),.035,"Oak",n=6)
    else:raise ValueError("Missing reserve furnishing geometry: "+kind)


def build(api, reserve_plan):
    """Create only Reserve_ geometry and return a separate portable report.

    Required root kit API: Batch, coll, MATS.
    Optional: text, SCENE. No files, scenes, cameras or original inventories are
    changed. Repeated local furnishing meshes are linked via Object.copy().
    """
    plans=plan_reserve(reserve_plan);audits=[validate_plan(p) for p in plans]
    failures=[a for a in audits if a["status"]!="PASS"]
    if failures:raise ValueError("Reserve layout clearance failed before geometry creation: "+json.dumps(failures))
    Batch,coll=api["Batch"],api["coll"]
    reserve_root=coll("07_Reserve_Amenities")
    reserve_root["namespace"]="Reserve_";reserve_root["schema"]=SCHEMA
    objects=[];cache={};linked=0;records=[]
    for p in plans:
        ident=p["id"];w,d=p["width"],p["depth"];ff=p["finished_floor_local_z_m"];h=p["wall_height_m"]
        angle=math.radians(p["yaw_degrees"]);origin=(*p["center"][:2],p["pad_level_m"])
        def world(x,y,z):return(origin[0]+x*math.cos(angle)-y*math.sin(angle),origin[1]+x*math.sin(angle)+y*math.cos(angle),origin[2]+z)
        rootc=coll(ident,reserve_root)
        for k,v in {"reserve_building_id":ident,"reserve_kind":p["kind"],"reserve_floor_count":1,"footprint_m":[w,d],"yaw_degrees":p["yaw_degrees"]}.items():rootc[k]=v
        shellc=coll(ident+"_Structure",rootc);roofc=coll(ident+"_Roof",rootc);frontc=coll(ident+"_FrontCover",rootc)
        interiorc=coll(ident+"_Interior",rootc);floorc=coll(ident+"_Interior_L00",interiorc);outsidec=coll(ident+"_Site_Utilities",rootc)
        roofc["reserve_cover_role"]="roof";frontc["reserve_cover_role"]="front_wall"
        floorc["reserve_floor_index"]=0;floorc["finished_floor_local_z_m"]=ff;floorc["finished_floor_z_m"]=origin[2]+ff
        def flush(b, role, rc=None, asset_id=None):
            out=b.flush(.003)
            for ob in out:
                ob["reserve_building_id"]=ident;ob["reserve_role"]=role;ob["visual_only"]=True
                if rc:ob["reserve_room_id"]=rc["id"]
                if asset_id:ob["reserve_asset_id"]=asset_id
                objects.append(ob.name)
            return out
        structure=Batch(ident+"_Shell",shellc,origin,angle);front=Batch(ident+"_Front",frontc,origin,angle)
        trailer=p["kind"]=="trailer";truck=p["kind"]=="food_truck"
        skin="White" if trailer else "BluePaint" if truck else "Plaster"
        structure.box((0,0,ff-.094),(w,d,.14),"Oak" if trailer else "Zinc" if truck else "Granite")
        # Supported mobile chassis or a solid shallow, level plinth.
        if trailer or truck:
            for x in(-w*.36,w*.36):structure.box((x,0,ff-.28),(.13,d*.92,.13),"Iron")
            for x in(-w*.34,w*.34):
                for y in(-d*.33,d*.33):structure.rod((x,y,.03),(x,y,ff-.08),.045,"Zinc",n=8)
            if trailer:
                for y in(-d*.15,d*.15):
                    for side in(-1,1):
                        x=side*(w/2-.05);structure.rod((x-side*.07,y,.26),(x+side*.07,y,.26),.24,"Ink",n=16)
                        structure.rod((x+side*.075,y,.26),(x+side*.085,y,.26),.12,"Zinc",n=12)
            else:
                for x in(-w*.31,w*.31):
                    for side in(-1,1):
                        y=side*(d/2-.05);structure.rod((x,y-side*.07,.26),(x,y+side*.07,.26),.24,"Ink",n=16)
                        structure.rod((x,y+side*.075,.26),(x,y+side*.085,.26),.12,"Zinc",n=12)
        else:structure.box((0,0,(ff-.024)/2),(w+.08,d+.08,ff-.024),"Granite")
        door={"center_m":p["entry_local"][0],"width_m":p["entry_width_m"],"bottom_m":0.,"height_m":1.98 if trailer else 2.12,"kind":"door"}
        front_holes=[door]
        if truck:front_holes.append({**p["service_hatch"],"kind":"service_hatch"})
        else:
            candidates=(-w*.28,w*.28) if w>5 else(-w*.32,w*.32)
            for x in candidates:
                ww=min(1.65,w*.22)
                if abs(x-door["center_m"])>ww/2+door["width_m"]/2+.17:
                    front_holes.append({"center_m":x,"width_m":ww,"bottom_m":1.0 if trailer else .85,"height_m":.85 if trailer else 1.30,"kind":"window"})
        _wall(front,"y",-d/2,(-w/2,w/2),h,front_holes,skin,ff)
        for side in(-1,1):
            ops=[]
            for y in(-d*.30,d*.30):ops.append({"center_m":y,"width_m":min(1.15,d*.18),"bottom_m":1.05 if trailer else 1.45 if p["kind"] in("bathhouse","toilets") else .85,"height_m":.75 if trailer else .70 if p["kind"] in("bathhouse","toilets") else 1.30,"kind":"window"})
            _wall(structure,"x",side*w/2,(-d/2,d/2),h,ops,skin,ff)
            for o in ops:_window_frame(structure,"x",side*w/2,o,ff)
        rear_holes=[{"center_m":0.,"width_m":min(1.1,w*.30),"bottom_m":1.1 if trailer else 1.6,"height_m":.75,"kind":"window"}]
        _wall(structure,"y",d/2,(-w/2,w/2),h,rear_holes,skin,ff)
        for o in rear_holes:_window_frame(structure,"y",d/2,o,ff)
        for o in front_holes:
            if o["kind"]=="window":_window_frame(front,"y",-d/2,o,ff)
        # Door leaf folded against adjacent facade, not across its aperture.
        dx=door["center_m"];dw=door["width_m"]
        leafside=-1 if dx>0 else 1
        leafx=dx+leafside*(dw+.05)
        front.box((leafx,-d/2-.10,ff+door["height_m"]/2),(dw-.06,.055,door["height_m"]-.04),"Sage" if not truck else "BluePaint")
        front.box((leafx,-d/2-.135,ff+1.35),(dw-.20,.015,.65),"Glass")
        for xx in(dx-dw/2-.035,dx+dw/2+.035):front.box((xx,-d/2-.025,ff+door["height_m"]/2),(.065,.18,door["height_m"]+.06),"White")
        front.box((dx,-d/2-.025,ff+door["height_m"]+.035),(dw+.14,.18,.07),"White")
        for ob in flush(front,"front_cover"):
            ob["door_state"]="open folded against facade";ob["door_aperture_width_m"]=dw
        flush(structure,"exterior_shell_and_supports")
        roof=Batch(ident+"_RoofParts",roofc,origin,angle)
        if trailer or truck:
            count=12;vs=[]
            for y in(-d/2-.10,d/2+.10):
                for i in range(count+1):
                    x=-w/2-.08+(w+.16)*i/count;z=ff+h+.18*(1-(2*x/(w+.16))**2);vs.append((x,y,z))
            roof.poly(vs,[(i,i+1,count+2+i,count+1+i) for i in range(count)],"White" if trailer else "Zinc")
            roof.box((0,0,ff+h-.025),(w-.05,d-.05,.05),"Linen")
            for y in(-d*.20,d*.28):
                roof.box((0,y,ff+h+.17),(.48,.56,.10),"Zinc");roof.box((0,y,ff+h+.23),(.35,.42,.025),"Glass")
        else:
            rise=.60;z=ff+h
            roof.poly([(-w/2-.16,-d/2-.16,z),(-w/2-.16,d/2+.16,z),(0,-d/2-.16,z+rise),(0,d/2+.16,z+rise),(w/2+.16,-d/2-.16,z),(w/2+.16,d/2+.16,z)],[(0,2,3,1),(2,4,5,3)],"Slate")
            roof.rod((0,-d/2-.16,z+rise+.025),(0,d/2+.16,z+rise+.025),.055,"Zinc",n=8)
            roof.box((0,0,z-.04),(w-.05,d-.05,.08),"Linen")
            for side in(-1,1):
                roof.rod((side*(w/2+.10),-d/2-.12,z),(side*(w/2+.10),d/2+.12,z),.045,"Zinc",n=8)
                roof.rod((side*(w/2+.10),d/2-.12,z),(side*(w/2+.10),d/2-.12,.03),.035,"Zinc",n=8)
            # The top side gable infill belongs to the removable cover.
            for y in(-d/2,d/2):roof.poly([(-w/2,y,z),(w/2,y,z),(0,y,z+rise)],[(0,1,2)],skin)
        flush(roof,"roof_cover")
        room_collections={}
        for r in p["rooms"]:
            rc=coll(r["id"],floorc);room_collections[r["id"]]=rc
            for k,v in {"reserve_room_id":r["id"],"purpose":r["purpose"],"bounds_local_m":r["bounds_m"],"reserve_floor_index":0}.items():rc[k]=v
            a,b,c,e=r["bounds_m"];floor=Batch(r["id"]+"_FloorFinish",rc,origin,angle)
            floor.box(((a+c)/2,(b+e)/2,ff-.012),(c-a-.015,e-b-.015,.024),r["finish"]);flush(floor,"room_floor_finish",r)
        partitions=Batch(ident+"_Partitions",floorc,origin,angle)
        for wall in p["partitions"]:
            _wall(partitions,wall["axis"],wall["coordinate_m"],wall["span_m"],wall["height_m"],wall["openings"],"Plaster",ff)
            for o in wall["openings"]:
                for side in(-1,1):
                    co=o["center_m"]+side*(o["width_m"]/2+.025)
                    partitions.box((wall["coordinate_m"],co,ff+o["height_m"]/2) if wall["axis"]=="x" else(co,wall["coordinate_m"],ff+o["height_m"]/2),(.15,.045,o["height_m"]) if wall["axis"]=="x" else(.045,.15,o["height_m"]),"White")
        flush(partitions,"interior_partitions_with_real_door_holes")
        for leaf in p["open_door_leaves"]:
            leaves=Batch(leaf["id"],floorc,origin,angle)
            for panel in leaf["panels"]:
                x,y=panel["center_m"];ww,dd,hh=panel["dimensions_m"]
                leaves.box((x,y,ff+hh/2+.025),(ww,dd,hh),"Sage" if trailer else "White")
            for ob in flush(leaves,"open_interior_door"):
                ob["door_state"]=leaf["state"];ob["door_aperture_width_m"]=leaf["clear_aperture_width_m"]
                ob["folded_panel_count"]=leaf["folded_panels"]
        for a in p["assets"]:
            rc=room_collections[a["room_id"]]
            key=json.dumps({k:a[k] for k in("kind","dimensions_m","accent")},sort_keys=True)+json.dumps({k:a[k] for k in("map_display","tools","grab_rails","dryer") if k in a},sort_keys=True)
            if key in cache and all(hasattr(ob,"copy") for ob in cache[key]):
                obs=[]
                for j,source in enumerate(cache[key]):
                    ob=source.copy();ob.name=a["id"]+"_Mesh_%02d"%j;rc.objects.link(ob);obs.append(ob);linked+=1
            else:
                b=Batch(a["id"],rc,(0,0,0),0);_asset_geometry(b,a);obs=b.flush(.003);cache[key]=obs
            for ob in obs:
                ob.location=world(*a["center_m"],ff);ob.rotation_euler.z=angle+math.radians(a["rotation_degrees"])
                for k,v in {"reserve_building_id":ident,"reserve_room_id":a["room_id"],"reserve_asset_id":a["id"],"reserve_floor_index":0,"reserve_role":"furnishing","reusable_asset":True,"visual_only":True,"collision_proxy_local_xy":a["footprint_m"],"approach_local_m":a["approach_local_m"]}.items():ob[k]=v
                if "integrated_fixtures" in a:ob["integrated_fixtures"]=json.dumps(a["integrated_fixtures"])
                if "integrated_seating" in a:ob["integrated_seating"]=a["integrated_seating"]
                objects.append(ob.name)
        _site_geometry(api,p,outsidec,origin,angle,flush,frontc)
        if api.get("text"):
            label=("EMPLACEMENT %02d"%p["lot_number"]) if trailer else LABELS[p["kind"]]
            ob=api["text"](ident+"_SignText",label,world(0,-d/2-.16,ff+h-(.10 if trailer or truck else .20)),.085 if trailer else .13 if truck else .21,"White",frontc,(math.pi/2,0,angle))
            ob["reserve_building_id"]=ident;ob["reserve_role"]="visitor_sign";objects.append(ob.name)
        records.append({**p,"root_collection":rootc.name,"roof_collection":roofc.name,"front_cover_collection":frontc.name,"interior_collection":interiorc.name,"room_count":len(p["rooms"]),"furnishing_count":len(p["assets"])})
    report={"schema":SCHEMA,"status":"BUILT_REQUIRES_NATIVE_AND_RENDER_QA","buildings":records,"building_count":len(records),"room_count":sum(r["room_count"] for r in records),"furnishing_count":sum(r["furnishing_count"] for r in records),"kinds":dict(Counter(p["kind"] for p in plans)),"object_names":objects,"linked_furnishing_mesh_instances":linked,"layout_audits":audits,"root_collection":reserve_root.name,"original_core_inventories_unchanged":True,"rendered_qa":False,"units":"metres","reserve_plan_semantic_sha256":hashlib.sha256(json.dumps(reserve_plan,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()}
    if api.get("SCENE") is not None:api["SCENE"]["reserve_amenities_report"]=json.dumps(report,separators=(",",":"))
    return report


def _window_frame(b,axis,coordinate,o,ff):
    c=o["center_m"];w=o["width_m"];h=o["height_m"];z=ff+o["bottom_m"]+h/2
    def box(u,zz,ww,hh,depth,material):
        b.box((coordinate,u,zz) if axis=="x" else(u,coordinate,zz),(depth,ww,hh) if axis=="x" else(ww,depth,hh),material)
    box(c,z,w,h,.025,"Glass")
    for u in(c-w/2,c+w/2):box(u,z,.055,h+.07,.14,"White")
    for zz in(z-h/2,z+h/2):box(c,zz,w+.10,.055,.14,"White")
    box(c,z,.035,h,.08,"White")


def _site_geometry(api,p,collection,origin,angle,flush,front_collection):
    """Building-local visitor utilities only; no reserve terrain/trail ownership."""
    b=api["Batch"](p["id"]+"_Visitor_Utilities",collection,origin,angle)
    facade=api["Batch"](p["id"]+"_Facade_Attachments",front_collection,origin,angle)
    w,d=p["width"],p["depth"];ff=p["finished_floor_local_z_m"];dx=p["entry_local"][0]
    # Two or more equal risers terminate on the exact finished floor.
    steps=max(2,math.ceil(ff/.15));tread=.27
    for j in range(steps):
        top=ff*(j+1)/steps;y=-d/2-.27*(steps-j)+.135
        b.box((dx,y,top/2),(p["entry_width_m"]+.25,tread,top),"Oak" if p["kind"]=="trailer" else "Granite")
    if p["kind"]=="trailer":
        # Side deck leaves the centered end-entry and its approach unobstructed.
        x=-w/2-1.0;b.box((x,-d*.17,.15),(1.75,3.1,.14),"Oak")
        for xx in(x-.70,x+.70):
            for yy in(-d*.17-1.3,-d*.17+1.3):b.rod((xx,yy,.02),(xx,yy,.13),.045,"Zinc",n=6)
        picnic={"kind":"picnic","dimensions_m":[1.35,1.45,.85],"accent":"Oak"}
        # Furniture is centered on the supported deck, separate from entry steps.
        deck=api["Batch"](p["id"]+"_Picnic",collection,(0,0,0),0);_asset_geometry(deck,picnic)
        obs=flush(deck,"picnic_table_with_seats")
        for ob in obs:
            ob.location=(origin[0]+x*math.cos(angle)+d*.17*math.sin(angle),origin[1]+x*math.sin(angle)-d*.17*math.cos(angle),origin[2]+.22)
            ob.rotation_euler.z=angle;ob["reserve_building_id"]=p["id"];ob["reserve_asset_id"]=p["id"]+"_Outdoor_Picnic"
        # Power/water standpipe + service connection, all on the opposite side.
        xx=w/2+.42;yy=d*.25
        b.box((xx,yy,.60),(.24,.18,1.05),"White");b.box((xx,yy-.105,.78),(.18,.035,.25),"BluePaint")
        b.rod((xx+.20,yy,.02),(xx+.20,yy,.65),.018,"Zinc",n=8)
        b.rod((xx+.20,yy,.65),(xx+.10,yy,.65),.018,"Zinc",n=8)
        b.rod((xx,yy,.20),(w/2-.05,yy,.20),.014,"Ink",n=6)
        b.box((0,d/2+.08,ff+.15),(.70,.22,.30),"White")
    elif p["kind"]=="food_truck":
        z=ff+2.12
        facade.box((-.25,-d/2-1.0,z),(3.60,1.85,.055),"Canvas")
        for xx in(-1.98,1.48):facade.rod((xx,-d/2-.05,z-.70),(xx,-d/2-1.86,z-.05),.018,"Zinc",n=6)
        facade.box((-.25,-d/2-.22,ff+1.04),(3.55,.48,.06),"Oak")
        for side in(-1,1):
            x=side*(w*.40);b.rod((x,-d/2-.18,.02),(x,-d/2-.18,.54),.025,"Iron",n=6)
        b.box((w/2+.30,.65,.30),(.45,.45,.55),"Zinc")
    else:
        # Notice board, welcome mat and segregated visitor litter bin.
        x=-w/2-.45;b.box((x,-d/2+.45,.55),(.45,.45,1.0),"Sage");b.box((x,-d/2+.45,1.09),(.49,.49,.08),"Ink")
        b.box((dx,-d/2-.10,ff-.012),(p["entry_width_m"]+.15,.18,.024),"Ink")
        facade.box((-w*.28,-d/2-.11,ff+1.40),(.55,.045,.65),"Oak");facade.box((-w*.28,-d/2-.14,ff+1.40),(.48,.018,.58),"Linen")
    # A restrained sign backing and porch lamp give tertiary scale without clutter.
    compact=p["kind"] in("trailer","food_truck")
    # The elevated fascia belongs to the facade cutaway, alongside its text.
    facade.box((0,-d/2-.12,ff+p["wall_height_m"]-(.10 if compact else .20)),(min(w-.25,4.9),.08,.16 if compact else .35),"BluePaint" if p["kind"] in("food_truck","souvenir_store") else "Sage")
    facade.rod((dx,-d/2-.13,ff+2.10),(dx,-d/2-.28,ff+2.10),.018,"Iron",n=6)
    facade.rod((dx,-d/2-.28,ff+2.06),(dx,-d/2-.28,ff+2.12),.055,"Lamp",n=10)
    flush(facade,"front_cover")
    # Low flowering planters frame the facade without crowding the entrance.
    for side in (-1,1):
        px=side*w*.34;py=-d/2-.48
        if p['kind']=='trailer':px=side*(w/2+.65);py=-d/2+.8
        b.box((px,py,.17),(.55,.34,.34),'Terracotta')
        b.ellipsoid((px,py,.39),(.34,.25,.22),'Leaf',n=7,rings=3)
        for j in range(4):
            b.ellipsoid((px-.19+j*.12,py-.08,.56),(.07,.07,.08),'BloomPink' if side>0 else 'BloomCream',n=6,rings=3)
    flush(b,"visitor_entry_steps_signs_and_site_utilities")
