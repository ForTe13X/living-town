"""Audited compact-footprint interiors for the generated territorial extension.

The canonical interior module remains the geometry and gate authority. This
adapter prepares local plans and supplies explicit, physical fixture programs;
it never lowers essential fixture counts, pedestrian diameter, door clearances,
privacy, furniture-facing or density requirements.
"""
from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
from pathlib import Path


KIND_MAPPING = {"workshop": "work", "souvenir": "shop", "convenience": "shop",
                "farmhouse": "longere", "residence": "home", "guesthouse": "hotel",
                "restaurant": "creperie"}


def load_authority(baseline_root):
    root = Path(baseline_root).resolve()
    if (root / "art/living_town").is_dir():
        root = root / "art/living_town"
    path = root / "tools/interior_design.py"
    spec = importlib.util.spec_from_file_location("territory_interior_authority", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def planning_record(plans):
    inputs = list(plans.values()) if isinstance(plans, dict) else list(plans)
    buildings = [{**b, "floors": b["floors"] if isinstance(b["floors"], int)
                  else b.get("floor_count", len(b["levels"]))} for b in inputs]
    return {"buildings": buildings,
            "floor_count": sum(b["floors"] for b in buildings),
            "room_count": sum(len(f["rooms"]) for b in buildings for f in b["levels"])}


def audit_prepared_plans(plans, baseline_root=None, *, authority=None):
    """Run every canonical gate plus checks for actual nonrectangular rooms.

    Accept either pure cached plans or build_interior's returned records; the
    latter use floors=list and floor_count=int, while the canonical audit uses
    floors=int and levels=list. The source records are not modified.
    """
    authority = authority or load_authority(baseline_root)
    record = planning_record(plans)
    audit = authority.audit_plan(record)
    added = []
    l_rooms = []
    for building in record["buildings"]:
        if building["floors"] != len(building["levels"]):
            added.append({"building": building["id"], "reason": "declared floor count differs from actual furnished levels"})
        for floor in building["levels"]:
            expected_z = .38 + floor["level"] * authority.FLOOR_HEIGHT
            if abs(floor["finished_floor_local_z_m"]-expected_z) > 1e-6:
                added.append({"building": building["id"], "reason": "finished floor differs from geometry authority"})
            for room in floor["rooms"]:
                exclusions = room.get("nonrectangular_exclusions_m", [])
                if not exclusions:
                    continue
                a, b, c, e = room["bounds_m"]
                # The current adapter authors one stair notch, so subtraction
                # is exact and cannot double-count overlapping exclusions.
                if len(exclusions) != 1:
                    added.append({"room": room["id"], "reason": "unsupported overlapping room exclusions"})
                    continue
                x, y, xx, yy = exclusions[0]
                excluded = max(0, min(c, xx)-max(a, x))*max(0, min(e, yy)-max(b, y))
                area = (c-a)*(e-b)-excluded
                covered = sum((q["footprint_m"][2]-q["footprint_m"][0]) *
                              (q["footprint_m"][3]-q["footprint_m"][1]) for q in room["assets"])
                limit = .58 if any(k in room["purpose"] for k in ("store", "archive", "stacks", "storage", "cafe dining")) else .48
                ratio = covered/area if area > 0 else float("inf")
                hits = [q["id"] for q in room["assets"] if authority.intersects(q["footprint_m"], exclusions[0])]
                passed = ratio <= limit and not hits
                l_rooms.append({"room": room["id"], "actual_floor_area_m2": round(area, 6),
                                "fixture_coverage_ratio": round(ratio, 6), "maximum_ratio": limit,
                                "assets_intersecting_protected_core": hits, "pass": passed})
                if not passed:
                    added.append({"room": room["id"], "reason": "nonrectangular room density or protected-core clearance failed"})
    audit["nonrectangular_room_checks"] = l_rooms
    audit["failures"].extend(added)
    audit["status"] = "FAIL" if audit["failures"] else "PASS"
    return audit


def _inventory(authority, room, kind, count, dimensions):
    """Specify a real compact assembly; never scale below its mesh footprint."""
    assets = [a for a in room["assets"] if a["kind"] == kind]
    while len(assets) < count:
        index = len(room["assets"])
        asset = {"id": room["id"] + f"_Adapted{index:02d}_{kind}", "kind": kind,
                 "center_m": [(room["bounds_m"][0] + room["bounds_m"][2]) / 2,
                              (room["bounds_m"][1] + room["bounds_m"][3]) / 2],
                 "rotation_degrees": 0, "dimensions_m": list(dimensions),
                 "accent": "Sage", "collision_proxy": True}
        if kind == "dining_table":
            asset["integrated_seating"] = 2
        if kind == "kitchen_run":
            asset["integrated_fixtures"] = ["recessed_sink", "tap", "hob", "undercounter_fridge"]
        room["assets"].append(asset)
        assets.append(asset)
    for asset in assets:
        asset["dimensions_m"] = list(dimensions)
        asset["footprint_m"] = authority.asset_footprint(asset)


def compact_inventory(authority, original, *, counter_width=1.8, banquette_width=1.4,
                      kitchen_width=1.4, focus=False):
    plan = deepcopy(original)
    for floor in plan["levels"]:
        for room in floor["rooms"]:
            if room["purpose"] == "cafe dining":
                _inventory(authority, room, "cafe_counter", 1, [counter_width, .60, 1.50])
                _inventory(authority, room, "banquette", 1, [banquette_width, .68, .95])
                # The actual two-chair geometry is 1.27 x .68m. Keep its existing
                # conservative 1.35 x .90m assembly footprint and all four sets.
                _inventory(authority, room, "cafe_table_set", 4, [1.35, .90, .95])
                if focus:
                    counter = next(a for a in room["assets"] if a["kind"] == "cafe_counter")
                    counter["dimensions_m"] = [3.0, .73901, 1.52615]
                    counter["detail_source"] = "hero_counter"
                    table = next(a for a in room["assets"] if a["kind"] == "cafe_table_set")
                    table["dimensions_m"] = [.69128, 1.77778, .8761]
                    table["detail_source"] = "hero_bistro"
            elif room["purpose"] == "private owner kitchenette":
                _inventory(authority, room, "kitchen_run", 1, [kitchen_width, .58, 1.12])
                _inventory(authority, room, "dining_table", 1, [1.0, 1.15, .84])
                _inventory(authority, room, "cupboard", 1, [.55, .32, 1.75])
    for floor in plan["levels"]:
        for room in floor["rooms"]:
            if room["purpose"] in ("cafe dining", "private owner kitchenette"):
                arrange_room(authority, plan, floor, room)
    return plan


def _door_gaps(floor):
    for room in floor["rooms"]:
        room["door_gaps"] = []
        a, b, c, e = room["bounds_m"]
        for wall in floor["partitions"]:
            co = wall["coordinate_m"]
            touches = (abs(co-a) < .001 or abs(co-c) < .001) if wall["axis"] == "x" else (abs(co-b) < .001 or abs(co-e) < .001)
            lo, hi = (b, e) if wall["axis"] == "x" else (a, c)
            if touches:
                for opening in wall["openings"]:
                    if opening["kind"] == "door" and lo < opening["center_m"] < hi:
                        room["door_gaps"].append({"axis": wall["axis"], "coordinate_m": co, **opening})


def open_cafe_lobby(original):
    """Open the front stair landing as a dining bay; keep the core protected.

    The public room is L shaped around the actual protected stair rectangle.
    Its bounding box supports the existing mesh API; the explicit exclusion is
    added to furniture reserves and independently checked by the adapter.
    No sleeping, sanitary, service-room or upper-floor boundary is opened.
    """
    plan = deepcopy(original)
    floor = plan["levels"][0]
    public = next((r for r in floor["rooms"] if r["purpose"] == "cafe dining"), None)
    if public is None or not plan["core"]:
        return plan
    xmin, ymin, xmax, ymax = plan["clear_bounds_m"]
    old_right, split = public["bounds_m"][2:]
    core = plan["core"]["bounds"]
    public["bounds_m"][2] = xmax
    public["access_edge"] = None
    public["circulation_keepouts"] = []
    public["nonrectangular_exclusions_m"] = [list(core)]
    public["layout_method"] = "L-shaped open cafe and front stair lobby; protected core excluded"
    # A 1.20m entry aisle turns into the 1.10m front landing aisle. The old
    # full-depth central rectangle was tied to the now-removed enclosed hall.
    # Keep explicit contiguous reserves and retain the independent entrance
    # sweep and whole-floor 0.50m pedestrian flood-fill gates unchanged.
    landing_y = (ymin + core[1]) / 2
    floor["access_keepouts"] = [
        [-.60, ymin, .60, landing_y+.55],
        [-.60, landing_y-.55, core[2], landing_y+.55],
        [core[0]-.10, core[1]-.10, core[2]+.10, core[3]+.10],
    ]
    floor["rooms"] = [r for r in floor["rooms"] if r["name"] != "Lower_Landing"]
    hall = next(r for r in floor["rooms"] if r["name"] == "Hall")
    hall["bounds_m"][1] = split
    # Open only the ground-floor public/hall divider. Preserve its rear portion
    # so the coffee preparation room remains physically separated.
    for wall in floor["partitions"]:
        if wall["axis"] == "x" and abs(wall["coordinate_m"]-old_right) < .001:
            wall["span_m"][0] = split
            wall["openings"] = [o for o in wall["openings"] if o["center_m"] > split]
    # Close the rear lobby edge while retaining a genuine 0.92m doorway.
    floor["partitions"].append({"axis": "y", "coordinate_m": split,
        "span_m": [old_right, core[0]], "thickness_m": .12,
        "height_m": 2.70 if plan["floors"] > 1 else 2.43,
        "openings": [{"kind": "door", "center_m": (old_right+core[0])/2,
                      "width_m": .92, "bottom_m": 0., "height_m": 2.08}]})
    _door_gaps(floor)
    return plan


def arrange_room(authority, plan, floor, room):
    """Bounded constraint-first packing using unchanged physical gate rules.

    Fixed service counters and wall-supported activity groups are placed before
    loose cafe tables. This avoids spending the old solver's search budget on
    table permutations that would later collide with the single fixed counter.
    """
    a, b, c, e = room["bounds_m"]
    intersects = authority.intersects
    blockers = [list(r) for r in room["circulation_keepouts"]]
    for reserve in floor["access_keepouts"]:
        if intersects(reserve, room["bounds_m"]) and reserve not in blockers:
            blockers.append(list(reserve))
    for door in room["door_gaps"]:
        co, mid, half = door["coordinate_m"], door["center_m"], door["width_m"]/2
        if door["axis"] == "x":
            blockers.append([co if abs(co-a)<.001 else co-.90, mid-half,
                             co+.90 if abs(co-a)<.001 else co, mid+half])
        else:
            blockers.append([mid-half, co if abs(co-b)<.001 else co-.90,
                             mid+half, co+.90 if abs(co-b)<.001 else co])
    blockers = [[round(value, 6) for value in rect] for rect in blockers]
    groups, relations = authority.furniture_groups(room)

    def inside(rect, margin=.035):
        return rect[0] >= a+margin-1e-7 and rect[1] >= b+margin-1e-7 and rect[2] <= c-margin+1e-7 and rect[3] <= e-margin+1e-7

    def candidates(group):
        choices = []
        for rotation in (0, 90, 180, 270):
            members = []
            for asset, x, y, rot in group["members"]:
                xx, yy = authority.rotated_xy(x, y, rotation)
                member = {**asset, "center_m": [xx, yy], "rotation_degrees": (rot+rotation)%360}
                member["footprint_m"] = authority.asset_footprint(member)
                members.append(member)
            lo = min(q["footprint_m"][0] for q in members)
            hi = max(q["footprint_m"][2] for q in members)
            bottom = min(q["footprint_m"][1] for q in members)
            top = max(q["footprint_m"][3] for q in members)
            xs = [a+.07-lo, c-.07-hi, (a+c-lo-hi)/2]
            ys = [b+.07-bottom, e-.07-top, (b+e-bottom-top)/2]
            xs += [a+.07-lo+i*.14 for i in range(max(0, int((c-a-hi+lo-.14)/.14))+1)]
            ys += [b+.07-bottom+i*.14 for i in range(max(0, int((e-b-top+bottom-.14)/.14))+1)]
            if group["wall"]:
                anchor = members[0]
                bx, by = authority.rotated_xy(0, anchor["dimensions_m"][1]/2, rotation)
                if rotation == 0: offsets = [(x, e-.07-by-anchor["center_m"][1]) for x in xs]
                elif rotation == 180: offsets = [(x, b+.07-by-anchor["center_m"][1]) for x in xs]
                elif rotation == 90: offsets = [(a+.07-bx-anchor["center_m"][0], y) for y in ys]
                else: offsets = [(c-.07-bx-anchor["center_m"][0], y) for y in ys]
            else:
                offsets = [(x, y) for y in ys for x in xs]
            if members[0]["kind"] == "cafe_counter":
                if rotation != 0:
                    continue
                original = group["members"][0][0]
                # Remain under the real service hatch, with a true wall gap.
                target_x = max(a+.07+original["dimensions_m"][0]/2,
                               min(c-.07-original["dimensions_m"][0]/2, original["center_m"][0]))
                offsets = [(target_x, e-.07-original["dimensions_m"][1]/2)]
            seen = set()
            for dx, dy in offsets:
                if (round(dx, 6), round(dy, 6)) in seen:
                    continue
                seen.add((round(dx, 6), round(dy, 6)))
                placed = []
                for member in members:
                    q = {**member, "center_m": [round(member["center_m"][0]+dx, 6), round(member["center_m"][1]+dy, 6)]}
                    q["footprint_m"] = [round(v, 6) for v in authority.asset_footprint(q)]
                    placed.append(q)
                rects = [q["footprint_m"] for q in placed]
                if any(not inside(r) or any(intersects(r, z, 1e-6) for z in blockers) for r in rects):
                    continue
                for clear in authority.furniture_clearance_sets(placed):
                    if any(not inside(z, .015) or any(intersects(z, r, 1e-6) for r in rects) for z in clear):
                        continue
                    score = sum(min((q["center_m"][0]-a)**2, (q["center_m"][0]-c)**2) +
                                min((q["center_m"][1]-b)**2, (q["center_m"][1]-e)**2) for q in placed)
                    choices.append((score, placed, clear))
        return sorted(choices, key=lambda q: (q[0], q[1][0]["rotation_degrees"], q[1][0]["center_m"]))

    choices = [(group, candidates(group)) for group in groups]
    choices.sort(key=lambda q: (len(q[1]), -len(q[0]["members"]), q[0]["label"]))
    visits = 0
    answer = None

    def solve(index, placed, clear):
        nonlocal visits, answer
        visits += 1
        if visits > 100000:
            return False
        if index == len(choices):
            answer = placed, clear
            return True
        for _, group_assets, reserves in choices[index][1]:
            rects = [q["footprint_m"] for q in group_assets]
            if any(intersects([r[0]-.065, r[1]-.065, r[2]+.065, r[3]+.065], p["footprint_m"], 1e-6)
                   for r in rects for p in placed):
                continue
            if any(intersects(r, z, 1e-6) for r in rects for z in clear):
                continue
            if any(intersects(z, p["footprint_m"], 1e-6) for z in reserves for p in placed):
                continue
            if solve(index+1, placed+group_assets, clear+reserves):
                return True
        return False

    if solve(0, [], []):
        mapped = {q["id"]: q for q in answer[0]}
        room["assets"] = [mapped[q["id"]] for q in room["assets"]]
        room["furniture_clearances_m"] = answer[1]
        room["circulation_keepouts"] = blockers
        status = "PASS"
    else:
        status = "UNRESOLVED"
    room["furnishing_count"] = len(room["assets"])
    room["furniture_composition"] = {"status": status, "search_nodes": visits,
        "candidate_counts": [len(q[1]) for q in choices], "relationships": relations,
        "policy": "Fixed counter first; physical wall backs, unchanged activity/clearance gates"}


def prepare_plans(territory, baseline_root):
    authority = load_authority(baseline_root)
    plans = {}
    adaptations = []
    for building in territory["buildings"]:
        ident = building["id"]
        mapped_kind = KIND_MAPPING.get(building["kind"], building["kind"])
        original = authority.plan_for_building(ident, building["width"], building["depth"],
                                              building["floors"], mapped_kind, 0)
        original_audit = audit_prepared_plans([original], authority=authority)
        selected = original
        focus = ident in territory.get("detailed_focus_ids", []) and mapped_kind == "cafe"
        if original_audit["status"] != "PASS" or focus:
            attempts = []
            for counter, banquette, kitchen in ((1.8, 1.4, 1.4), (1.5, 1.4, 1.1), (1.5, 1.25, 1.1)):
                candidate = compact_inventory(authority, open_cafe_lobby(original), counter_width=counter,
                                              banquette_width=banquette, kitchen_width=kitchen, focus=focus)
                audit = audit_prepared_plans([candidate], authority=authority)
                attempts.append({"counter_width_m": counter, "banquette_width_m": banquette,
                                 "kitchen_run_width_m": kitchen, "status": audit["status"],
                                 "failures": audit["failures"]})
                if audit["status"] == "PASS":
                    selected = candidate
                    break
            adaptations.append({"building_id": ident, "before_failures": original_audit["failures"],
                                "attempts": attempts, "status": attempts[-1]["status"]})
        plans[ident] = selected
    record = planning_record(plans)
    audit = audit_prepared_plans(plans, authority=authority)
    report = {"schema": "living_town.expansion_interior_adapter.v1", "status": audit["status"],
              "authority_sha256": hashlib.sha256(Path(authority.__file__).read_bytes()).hexdigest(),
              "adapter_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "adaptations": adaptations, "audit": audit}
    return plans, report
