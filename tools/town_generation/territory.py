"""Deterministic, bounded expansion of the existing Breton town.

This is a spatial planner, not an Infinigen adapter.  It reads the preserved
town/reserve and emits actual parcels, a connected street graph, elevations,
and local earthworks.  No source plans are changed and no engine is imported.
"""
from __future__ import annotations

import hashlib
import heapq
import importlib.util
import bisect
import json
import math
import random
from collections import defaultdict
from pathlib import Path

SCHEMA = "living_town.territory_expansion.v1"
GRADE = .08
CORE_RECT = (-61.5, -47.3, 56., 55.)
CORE_FADE = .6
ROUTE_FADE = .75
ROUTE_FADE_OVERRIDES = {"Reserve_Fern_Bridge_East": 1.8}
SOURCES = ("masterplan.json", "landscape_plan.json", "terrain_plan.json",
           "reserve_plan.json", "tools/reserve_plan.py", "tools/terrain_profile.py")


def _root(path):
    path = Path(path).resolve()
    if (path / "art/living_town/masterplan.json").is_file():
        path = path / "art/living_town"
    if not (path / "masterplan.json").is_file():
        raise ValueError("baseline_root must be the repository or art/living_town directory")
    return path


def _authority(root):
    path = _root(root) / "tools/reserve_plan.py"
    spec = importlib.util.spec_from_file_location("territory_preserved_reserve", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # Build only the pure planning data/index; this does not write anything.
    module._ensure_plan()
    return module


def _seed(seed, namespace, identity):
    return int.from_bytes(hashlib.sha256(f"{seed}\0{namespace}\0{identity}".encode()).digest()[:4], "big")


def _xy(p):
    return tuple(round(float(v), 6) for v in p[:2])


def _project(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    ll = dx*dx+dy*dy
    t = max(0., min(1., ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/ll)) if ll else 0.
    q = (a[0]+t*dx, a[1]+t*dy)
    return t, math.dist(p[:2], q)


def _crossing(a, b, c, d):
    ax, ay = b[0]-a[0], b[1]-a[1]
    bx, by = d[0]-c[0], d[1]-c[1]
    det = ax*by-ay*bx
    if abs(det) < 1e-10:
        return None
    cx, cy = c[0]-a[0], c[1]-a[1]
    t, u = (cx*by-cy*bx)/det, (cx*ay-cy*ax)/det
    if -1e-8 <= t <= 1+1e-8 and -1e-8 <= u <= 1+1e-8:
        return (max(0., min(1., t)), max(0., min(1., u)),
                _xy((a[0]+t*ax, a[1]+t*ay)))
    return None


def _inside(p, polygon):
    positive = negative = False
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        cross = (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        positive |= cross > 1e-8
        negative |= cross < -1e-8
    return not (positive and negative)


def _segment_distance(a, b, c, d):
    if _crossing(a, b, c, d):
        return 0.
    return min(_project(a, c, d)[1], _project(b, c, d)[1],
               _project(c, a, b)[1], _project(d, a, b)[1])


def _segment_polygon(a, b, poly):
    if _inside(a, poly) or _inside(b, poly):
        return 0.
    return min(_segment_distance(a, b, c, d) for c, d in zip(poly, poly[1:]+poly[:1]))


def _polygon_distance(a, b):
    if _inside(a[0], b) or _inside(b[0], a):
        return 0.
    return min(_segment_polygon(c, d, b) for c, d in zip(a, a[1:]+a[:1]))


def _polygon(center, width, depth, yaw):
    angle = math.radians(yaw)
    c, s = math.cos(angle), math.sin(angle)
    return [[round(center[0]+x*c-y*s, 6), round(center[1]+x*s+y*c, 6)]
            for x, y in ((-width/2, -depth/2), (width/2, -depth/2),
                         (width/2, depth/2), (-width/2, depth/2))]


def _hull(points):
    points = sorted(set(tuple(p[:2]) for p in points))
    def cross(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lower, upper = [], []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0: lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0: upper.pop()
        upper.append(p)
    return lower[:-1]+upper[:-1]


def _area(poly):
    return abs(sum(a[0]*b[1]-b[0]*a[1] for a, b in zip(poly, poly[1:]+poly[:1])))/2


def _baseline_routes(master, reserve, landscape):
    routes = []
    for row in master["streets"]:
        routes.append({"id": row["id"], "points": row["points"], "width": row["width"]})
    for row in reserve["paths"]:
        routes.append({"id": row["id"], "points": row["points_m"], "width": row["width_m"]})
    for row in landscape.get("paths", []):
        points = row.get("points", row.get("points_xy", []))
        if points:
            routes.append({"id": row["id"], "points": points,
                           "width": row.get("width", row.get("width_m", 1.6))})
    return routes


def _road_specs():
    # Authored topological skeleton: bends follow the coast/contours and each
    # loop joins a named node.  Buildings are subsequently parcelled along it.
    # This is deliberately not a perturbed grid.
    return [
        ("North_Harbor_Road", "D06", 4.2, [[31,54],[38,60],[38,63],[40,70],[38,78],[23,85],[8,108],[-15,118]]),
        ("Harbor_Back_Loop", "D06", 3.6, [[25,67],[2,65],[-24,76],[-31,97],[-15,118]]),
        ("Harbor_Cross_Mews", "D06", 2.6, [[23,85],[-2,85],[-31,97]]),
        ("Harbor_Upper_Loop", "D06", 3.2, [[8,108],[20,124],[10,143],[-16,148],[-39,135],[-48,114]]),
        ("Hillside_Contour_Road", "D08", 3.6, [[-15,118],[-48,114],[-80,105],[-111,97],[-135,86],[-157,66]]),
        ("Hillside_Lower_Loop", "D08", 3.2, [[-31,97],[-57,81],[-83,73],[-110,70],[-135,86]]),
        ("Hillside_Market_Link", "D08", 3.5, [[-83,73],[-97,49],[-110,30],[-118,12]]),
        ("West_Market_Street", "D07", 4.2, [[-56,11.5],[-73,9],[-95,5],[-118,12],[-145,15],[-175,10]]),
        ("Workshop_Court_Loop", "D07", 3.0, [[-73,9],[-80,-7],[-111,-8],[-136,-2],[-145,15]]),
        ("West_Workyard_Lane", "D07", 3.0, [[-175,10],[-200,-8],[-195,-30],[-170,-30],[-153,-5]]),
        ("Trailhead_Village_Loop", "D10", 3.1, [[-145,15],[-158,30],[-181,29],[-193,10],[-181,-7],[-153,-5],[-145,15]]),
        ("Forest_Edge_Link", "D10", 3.1, [[-157,66],[-183,57],[-217,55],[-222,25],[-193,10]]),
        ("Orchard_Gateway", "D09", 3.6, [[-58,-25],[-67,-40],[-71,-65]]),
        ("Orchard_Lane_Loop", "D09", 3.0, [[-71,-65],[-70,-91],[-54,-113],[-25,-121],[-7,-111],[-4,-86],[-23,-68],[-51,-66],[-71,-65]]),
        ("Orchard_Cross_Lane", "D09", 2.4, [[-70,-91],[-45,-91],[-20,-93],[-4,-86]]),
    ]


def _envelope(initial, graph):
    values = list(initial)
    heap = [(v, i) for i, v in enumerate(values)]
    heapq.heapify(heap)
    while heap:
        value, node = heapq.heappop(heap)
        if value != values[node]: continue
        for other, cost in graph[node]:
            candidate = value+cost
            if candidate < values[other]-1e-12:
                values[other] = candidate
                heapq.heappush(heap, (candidate, other))
    return values


def _route_guard(authority, routes, default_fade=ROUTE_FADE, overrides=None):
    """Exact old ribbons with a banked plane extension, never a natural bank.

    Outside the protected width, extrapolate the actual boundary height using
    the small crossfall measured inside its walkable centre. This avoids
    dragging the steep *old grass bank* across a newly intersecting road.
    """
    overrides=overrides or {};items=[];index=defaultdict(list);cell=20.
    for route in routes:
        fade=overrides.get(route["id"],default_fade)
        for a,b in zip(route["points"],route["points"][1:]):
            length=math.dist(a[:2],b[:2])
            if length<1e-8:continue
            nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            mx,my=(a[0]+b[0])/2,(a[1]+b[1])/2
            gradient=(authority.design_height(mx+.05*nx,my+.05*ny)-authority.design_height(mx-.05*nx,my-.05*ny))/.1
            gradient=max(-.12,min(.12,gradient))
            i=len(items);half=route["width"]/2+.12;radius=half+4.
            items.append((route,a,b,half,fade,nx,ny,gradient))
            for x in range(math.floor((min(a[0],b[0])-radius)/cell),math.floor((max(a[0],b[0])+radius)/cell)+1):
                for y in range(math.floor((min(a[1],b[1])-radius)/cell),math.floor((max(a[1],b[1])+radius)/cell)+1):index[x,y].append(i)
    def guard(x,y):
        pending=[];strength=0.;extension_strength=0.;nearest=math.inf
        for i in index.get((math.floor(x/cell),math.floor(y/cell)),()):
            route,a,b,half,fade,nx,ny,gradient=items[i]
            t,d=_project((x,y),a,b);distance=max(0.,d-half)
            if distance==0:return True,authority.design_height(x,y),1.,0.,1.
            if distance>=4.:continue
            qx,qy=a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])
            ux,uy=(x-qx)/d,(y-qy)/d
            edge=(qx+ux*half,qy+uy*half)
            target=authority.design_height(*edge)+gradient*(ux*nx+uy*ny)*distance
            u=min(1.,distance/fade);strength=max(strength,1-u*u*(3-2*u))
            u=distance/4.;kernel=1-u*u*(3-2*u)
            weight=kernel/distance**4;pending.append((weight,target));extension_strength=max(extension_strength,kernel);nearest=min(nearest,distance)
        total=sum(w for w,z in pending)
        return False,(sum(w*z for w,z in pending)/total if total else 0.),strength,nearest,extension_strength
    return guard


def _plan_roads(specs, existing_routes, authority):
    raw = []
    for identity, district, width, points in specs:
        for segment, (a,b) in enumerate(zip(points, points[1:])):
            raw.append({"road":identity,"a":a,"b":b,"segment":segment,"cuts":{0.:_xy(a),1.:_xy(b)}})
    fixed, crossings = {}, []
    anchors = {(-56.,11.5):"upperwest", (31.,54.):"northservice", (-58.,-25.):"main_west"}
    for p, source in anchors.items(): fixed[p] = authority.design_height(*p)
    for i, segment in enumerate(raw):
        a,b=segment["a"],segment["b"]
        for other in raw[i+1:]:
            hit = _crossing(a,b,other["a"],other["b"])
            if hit:
                t,u,p=hit;segment["cuts"][t]=p;other["cuts"][u]=p
        for route in existing_routes:
            for c,d in zip(route["points"],route["points"][1:]):
                hit = _crossing(a,b,c,d)
                if not hit: continue
                t,u,p=hit; segment["cuts"][t]=p
                # Exact baseline finished ground, including existing path cuts.
                fixed[p]=authority.design_height(*p)
                crossings.append({"road":segment["road"],"baseline_route":route["id"],
                                  "point_xy":list(p),"preserved_z_m":round(fixed[p],6)})
    owners=defaultdict(set)
    for segment in raw:
        for p in segment["cuts"].values():owners[p].add(segment["road"])
    # A shared centreline point alone leaves two sloping, finite-width ribbons
    # disagreeing beside it. Use a short common level apron before solving the
    # graph; preserved trail crossings instead remain genuinely banked.
    aprons=[];apron_requested={};widths={r[0]:r[2]/2+.78 for r in specs}
    for p,ids in sorted(owners.items()):
        if len(ids)<2:continue
        rays=[]
        for segment in raw:
            if p not in segment["cuts"].values():continue
            for endpoint in (segment["a"],segment["b"]):
                length=math.dist(p,endpoint)
                if length>1e-5:rays.append((segment["road"],[(endpoint[k]-p[k])/length for k in range(2)]))
        radius=2.
        for i,(first,u) in enumerate(rays):
            for second,v in rays[i+1:]:
                if first==second:continue
                sine=abs(u[0]*v[1]-u[1]*v[0]);cosine=abs(u[0]*v[0]+u[1]*v[1])
                if sine>.15:radius=max(radius,(widths[first]+widths[second]*cosine)/sine+.5)
        radius=min(12.,radius);apron_requested[p]=radius
        clearance=math.hypot(max(CORE_RECT[0]-p[0],0.,p[0]-CORE_RECT[2]),max(CORE_RECT[1]-p[1],0.,p[1]-CORE_RECT[3]))
        clearance=min(clearance,min(_project(p,a,b)[1]-r["width"]/2-.12-ROUTE_FADE_OVERRIDES.get(r["id"],ROUTE_FADE)
                                    for r in existing_routes for a,b in zip(r["points"],r["points"][1:])))
        radius=min(radius,clearance-.05)
        if radius>=2.:aprons.append((p,radius,sorted(ids)))
    for segment in raw:
        a,b=segment["a"],segment["b"];dx,dy=b[0]-a[0],b[1]-a[1];ll=dx*dx+dy*dy
        for p,radius,ids in aprons:
            if segment["road"] not in ids:continue
            t=((p[0]-a[0])*dx+(p[1]-a[1])*dy)/ll
            distance=_project(p,a,b)[1]
            if distance>radius:continue
            dt=math.sqrt(max(0.,radius*radius-((a[0]+t*dx-p[0])**2+(a[1]+t*dy-p[1])**2))/ll)
            for cut in (t-dt,t+dt):
                if 0<cut<1:segment["cuts"][cut]=_xy((a[0]+cut*dx,a[1]+cut*dy))
    nodes, indices, graph, road_nodes = [], {}, defaultdict(list), defaultdict(list)
    longitudinal_links=[]
    def node(p):
        p=_xy(p)
        if p not in indices: indices[p]=len(nodes);nodes.append(p)
        return indices[p]
    for segment in raw:
        cuts=sorted(segment["cuts"].items())
        ids=[]
        for (_,a),(_,b) in zip(cuts,cuts[1:]):
            count=max(1,math.ceil(math.dist(a,b)/.75))
            pts=[_xy((a[0]+(b[0]-a[0])*i/count,a[1]+(b[1]-a[1])*i/count)) for i in range(count+1)]
            ids.extend(node(p) for p in pts[:-1])
        ids.append(node(cuts[-1][1]))
        for a,b in zip(ids,ids[1:]):
            # Leave ten ppm for six-decimal XYZ serialization; otherwise a
            # very short segment can round microscopically over the target.
            cost=(GRADE-.00001)*math.dist(nodes[a],nodes[b])
            graph[a].append((b,cost));graph[b].append((a,cost))
            longitudinal_links.append((segment["road"],a,b))
        if road_nodes[segment["road"]]:ids=ids[1:]
        road_nodes[segment["road"]].extend(ids)
    natural=[authority.design_height(*p) for p in nodes]
    guard=_route_guard(authority,existing_routes,ROUTE_FADE,ROUTE_FADE_OVERRIDES)
    for p,z in zip(nodes,natural):
        if CORE_RECT[0]<=p[0]<=CORE_RECT[2] and CORE_RECT[1]<=p[1]<=CORE_RECT[3]:
            fixed[p]=z
        else:
            inside,target,strength,_,_=guard(*p)
            if strength:fixed[p]=target
    # Finite-width neighboring ribbons must agree in space, not just at their
    # shared centreline node. Constrain nearby branches before elevation solve.
    node_owners=defaultdict(set)
    for identity,ids in road_nodes.items():
        for i in ids:node_owners[i].add(identity)
    proximity=defaultdict(list);cell=8.
    for i,p in enumerate(nodes):
        key=(math.floor(p[0]/cell),math.floor(p[1]/cell))
        if p not in fixed:
            for dx in (-1,0,1):
                for dy in (-1,0,1):
                    for j in proximity.get((key[0]+dx,key[1]+dy),()):
                        if node_owners[i]&node_owners[j]:continue
                        distance=math.dist(p,nodes[j])
                        reach=max(widths[r] for r in node_owners[i])+max(widths[r] for r in node_owners[j])
                        if distance<=reach:
                            cost=(GRADE-.00001)*distance;graph[i].append((j,cost));graph[j].append((i,cost))
            proximity[key].append(i)
    low=[fixed.get(p,z-4.) for p,z in zip(nodes,natural)]
    high=[fixed.get(p,z+4.) for p,z in zip(nodes,natural)]
    def solve():
        hi=_envelope(high,graph);lo=[-v for v in _envelope([-v for v in low],graph)]
        return lo,hi
    accepted=[]
    for p,desired,owners in sorted(aprons,key=lambda row:(-row[1],row[0])):
        best=0.;added=[]
        # A large theoretical apron can consume too much ramp length between
        # fixed old-route levels. Keep only radii with an actually feasible
        # global 8% profile, and report the bounded reduction explicitly.
        lower_radius,upper_radius=0.,desired
        for attempt in range(6):
            radius=desired if attempt==0 else (lower_radius+upper_radius)/2
            links=[(a,b) for road,a,b in longitudinal_links if road in owners and
                   math.dist(nodes[a],p)<=radius+1e-5 and math.dist(nodes[b],p)<=radius+1e-5]
            for a,b in links:graph[a].append((b,0.));graph[b].append((a,0.))
            lo,hi=solve();feasible=all(a<=b+1e-5 for a,b in zip(lo,hi))
            for a,b in reversed(links):graph[a].pop();graph[b].pop()
            if feasible:
                best=radius;lower_radius=radius;added=links
                if attempt==0:break
            else:upper_radius=radius
        if best>=.5:
            for a,b in added:graph[a].append((b,0.));graph[b].append((a,0.))
            accepted.append((p,best,owners))
    aprons=accepted
    upper=_envelope(high,graph); lower=[-v for v in _envelope([-v for v in low],graph)]
    infeasible=[{"point_xy":list(nodes[i]),"lower_z_m":round(lo,5),"upper_z_m":round(hi,5)}
                for i,(lo,hi) in enumerate(zip(lower,upper)) if lo>hi+1e-5]
    z=[(lo+hi)/2 for lo,hi in zip(lower,upper)]
    roads=[]
    for identity,district,width,controls in specs:
        ids=road_nodes[identity]
        points=[[*nodes[i],round(z[i],6)] for i in ids]
        grades=[abs(b[2]-a[2])/math.dist(a[:2],b[:2]) for a,b in zip(points,points[1:]) if math.dist(a[:2],b[:2])>1e-7]
        roads.append({"id":identity,"kind":"public_street" if width>=3 else "pedestrian_mews",
                      "district":district,"width_m":width,"shoulder_m":3.,"graded_verge_m":2.,
                      "points_xy":[p[:2] for p in points],"points_m":points,
                      "authored_controls_xy":controls,"grade_limit":GRADE,
                      "maximum_grade":round(max(grades,default=0),7),
                      "length_m":round(sum(math.dist(a[:2],b[:2]) for a,b in zip(points,points[1:])),3),
                      "maximum_cut_fill_m":round(max(abs(z[i]-natural[i]) for i in ids),4),
                      "junction_aprons":[{"center_xy":list(p),"radius_m":radius,"road_ids":owners,
                                           "requested_radius_m":apron_requested[p],"constraint_limited":radius<apron_requested[p]-.001,
                                           "level_m":round(z[indices[p]],6)}
                                          for p,radius,owners in aprons if identity in owners],
                      "baseline_crossings":[c for c in crossings if c["road"]==identity]})
    return roads, infeasible, anchors


def _road_segments(roads):
    return [(row,a,b) for row in roads for a,b in zip(row["points_m"],row["points_m"][1:])]


def _profile(roads, identity, station):
    row=next(r for r in roads if r["id"]==identity)
    remaining=station
    for a,b in zip(row["points_m"],row["points_m"][1:]):
        length=math.dist(a[:2],b[:2])
        if remaining<=length or b is row["points_m"][-1]:
            t=max(0.,min(1.,remaining/length))
            return [a[i]+(b[i]-a[i])*t for i in range(3)],[(b[0]-a[0])/length,(b[1]-a[1])/length]
        remaining-=length
    raise ValueError("Road station beyond profile")


DISTRICTS = [
    {"id":"D06","name":"Northern harbor quarter","character":"Landward quay street, fishing households, sail repair, fishmonger and small inns; no reclaimed coast.","kinds":["cottage","longere","shop","workshop","cafe","townhouse"],"target":22},
    {"id":"D07","name":"West market and workshop courts","character":"Bent market street and service loop with craft yards, small mixed-use plots and shared courts.","kinds":["shop","workshop","halftimber","cafe","longere","townhouse"],"target":22},
    {"id":"D08","name":"Contour hillside neighborhood","character":"Two contour streets with terraced foundations, paired houses, gardens and framed reserve views.","kinds":["cottage","longere","townhouse","whitehouse","ochre"],"target":26},
    {"id":"D09","name":"Orchard and horticultural edge","character":"An irregular lane around orchard meadows, nursery shops, gardeners' homes and potting/work buildings.","kinds":["longere","cottage","shop","workshop","whitehouse"],"target":20},
    {"id":"D10","name":"Forest trailhead village","character":"A compact loop adjoining the existing reserve: ranger support, outfitter, guest cottages and a cycling cafe.","kinds":["shop","cafe","workshop","cottage","longere"],"target":14},
]


def _candidate_buildings(roads, existing, routes, pond, authority, seed):
    segments=_road_segments(roads)
    baseline_segments=[(r,a,b) for r in routes for a,b in zip(r["points"],r["points"][1:])]
    occupied=[(b["id"],b.get("footprint_polygon") or _polygon(b["center"],b["width"],b["depth"],b.get("yaw_degrees",0))) for b in existing]
    buildings, pads, approaches, rejected=[],[],[],defaultdict(int)
    for district in DISTRICTS:
        proposals=[]
        for road in roads:
            if road["district"]!=district["id"]:continue
            for side in (-1,1):
                rng=random.Random(_seed(seed,"frontage",road["id"]+str(side)))
                station=8.+rng.uniform(0,3)
                serial=0
                while station<road["length_m"]-6:
                    width=rng.choice([7.2,7.8,8.4,9.0,9.8])
                    depth=rng.choice([7.2,7.6,8.0,8.8])
                    if district["id"]=="D10":width=max(7.2,width-.6)
                    p,tangent=_profile(roads,road["id"],station)
                    outward=[side*tangent[1],-side*tangent[0]]
                    setback=rng.choice([1.6,2.0,2.5,3.2])
                    offset=road["width_m"]/2+setback+depth/2
                    center=[p[0]-outward[0]*offset,p[1]-outward[1]*offset]
                    yaw=math.degrees(math.atan2(outward[0],-outward[1]))
                    identity=f"Expansion_{district['id']}_{road['id']}_{'L' if side==1 else 'R'}{serial:02d}"
                    proposals.append((identity,road,station,p,outward,setback,center,yaw,width,depth))
                    serial+=1;station+=width+rng.choice([1.5,1.8,2.2,3.0,4.5])
        # Interleave opposite sides/roads without making later insertion IDs
        # depend on acceptance order. Stable hash priority yields reproducibility.
        proposals.sort(key=lambda row:_seed(seed,"parcel_priority",row[0]))
        accepted=0
        for identity,road,station,p,outward,setback,center,yaw,width,depth in proposals:
            if accepted>=district["target"]:break
            poly=_polygon(center,width,depth,yaw)
            if any(not(-600<x<66 and -340<y<500) or x>authority.CORE.coast_x(y)-9 for x,y in poly):
                rejected["coast_or_bounds"]+=1;continue
            if _polygon_distance(poly,[[-76,-66],[71,-66],[71,66],[-76,66]])<.0001:
                rejected["preserved_core"]+=1;continue
            if any(_polygon_distance(poly,q)<1.4 for _,q in occupied):
                rejected["building_clearance"]+=1;continue
            if any(_segment_polygon(a["points_m"][0],a["points_m"][-1],poly)<.7 for a in approaches):
                rejected["existing_front_door_buffer"]+=1;continue
            if any(_segment_polygon(a,b,poly)<r["width_m"]/2+1.25 for r,a,b in segments):
                rejected["new_road_clearance"]+=1;continue
            if any(_segment_polygon(a,b,poly)<r["width"]/2+2.5 for r,a,b in baseline_segments):
                rejected["preserved_route_clearance"]+=1;continue
            if any(((x-pond["center"][0])/(pond["outer_bank_radii_m"][0]+2))**2+((y-pond["center"][1])/(pond["outer_bank_radii_m"][1]+2))**2<1 for x,y in poly):
                rejected["pond"]+=1;continue
            threshold=[center[0]+outward[0]*depth/2,center[1]+outward[1]*depth/2]
            edge=[p[0]-outward[0]*road["width_m"]/2,p[1]-outward[1]*road["width_m"]/2]
            # Pads meet the street with a shallow entry apron; the .38m floor
            # offset is handled by explicit three-riser entrance steps.
            ground_z=p[2]-.012*road["width_m"]/2
            natural_samples=[authority.design_height(x,y) for x,y in poly+[center]]
            cutfill=max(abs(z-ground_z) for z in natural_samples)
            if cutfill>3.8:
                rejected["foundation_earthworks"]+=1;continue
            # Entry routes must not cross a different shell or reserved path.
            if any(_segment_polygon(threshold,edge,q)<.7 for _,q in occupied):
                rejected["blocked_front_door"]+=1;continue
            if any(_segment_distance(threshold,edge,a,b)<r["width"]/2+.75 for r,a,b in baseline_segments):
                rejected["entry_reserved_route"]+=1;continue
            variant=_seed(seed,"building",identity)
            kind=district["kinds"][variant%len(district["kinds"])]
            floors=1 if kind=="workshop" else (2 if variant%4 else 3)
            if district["id"] in ("D09","D10"):floors=min(floors,2)
            programs={"cafe":["public dining","working kitchen","private WC","upper dwelling"],"shop":["sales room","counter","stock and service","upper dwelling"],"workshop":["working bay","materials store","office and washroom"]}
            b={"id":identity,"kind":kind,"district":district["id"],"center":[round(v,6) for v in center],
               "center_m":[round(v,6) for v in center],"width":width,"depth":depth,"floors":floors,
               "yaw_degrees":round(yaw,6),"footprint_polygon":poly,"seed":variant,
               "typology":"mixed_use" if kind in ("shop","cafe","workshop") else "garden_house",
               "front_outward":[round(v,8) for v in outward],"front_threshold":[round(v,6) for v in threshold],
               "entry_local":[0,-depth/2],"pad_id":identity+"_pad","pad_level_m":round(ground_z,6),
               "finished_floor_offset_m":.38,"entry_threshold_m":[*[round(v,6) for v in threshold],round(ground_z+.38,6)],
               "street_id":road["id"],"street_station_m":round(station,5),"setback_m":setback,
               "program":programs.get(kind,["entrance and stair hall","living/dining","kitchen","bathroom","private bedrooms"]),
               "foundation_cut_fill_max_m":round(cutfill,5),
               "entry_steps":{"risers":3,"riser_m":round(.38/3,7),"tread_m":.30,"width_m":1.4},
               "courtyard":{"type":"rear garden or shared planted court","minimum_side_gap_m":1.4}}
            pad={"id":b["pad_id"],"owner":identity,"center_m":b["center"],"width_m":width+.6,"depth_m":depth+.6,
                 "yaw_degrees":b["yaw_degrees"],"level_m":b["pad_level_m"],"blend_m":2.5,
                 "maximum_cut_fill_m":b["foundation_cut_fill_max_m"],
                 "foundation_policy":"Terrain-supported granite plinth; expose retaining base where the authored slope requires it."}
            approaches.append({"id":identity+"_Approach","kind":"entrance_approach","owner":identity,
                               "street_id":road["id"],"width_m":1.4,"grade_limit":.08,"maximum_grade":0.,
                               "points_m":[[round(edge[0],6),round(edge[1],6),round(ground_z,6)],
                                           [round(threshold[0],6),round(threshold[1],6),round(ground_z,6)]],
                               "steps_at_threshold":b["entry_steps"]})
            buildings.append(b);pads.append(pad);occupied.append((identity,poly));accepted+=1
    return sorted(buildings,key=lambda b:b["id"]),pads,approaches,dict(rejected)


def make_height_function(plan, baseline_root):
    """Return the actual finished surface callable used by the scene adapter.

    The original design_height is the base. New local pads/road shoulders are
    bounded overlays. Existing route ribbons and the core remain authoritative.
    No global flattening or extrapolated coast is permitted.
    """
    authority=_authority(baseline_root)
    core=plan["terrain"].get("preserved_core_rect_xyxy_m",CORE_RECT)
    blend=plan["terrain"].get("surface_blending",{})
    core_fade=blend.get("core_preservation_fade_m",CORE_FADE)
    route_fade=blend.get("existing_route_preservation_fade_m",ROUTE_FADE)
    route_fades=blend.get("existing_route_fade_overrides_m",{})
    pads=plan["terrain"]["pads"]
    segments=_road_segments(plan["roads"]+plan.get("approaches",[]))
    master=json.loads((_root(baseline_root)/"masterplan.json").read_text(encoding="utf-8"))
    reserve=json.loads((_root(baseline_root)/"reserve_plan.json").read_text(encoding="utf-8"))
    landscape=json.loads((_root(baseline_root)/"landscape_plan.json").read_text(encoding="utf-8"))
    protected=[(r,a,b) for r in _baseline_routes(master,reserve,landscape) for a,b in zip(r["points"],r["points"][1:])]
    route_guard=_route_guard(authority,_baseline_routes(master,reserve,landscape),route_fade,route_fades)
    cell=20.;road_index=defaultdict(list);pad_index=defaultdict(list);protect_index=defaultdict(list)
    def index(target,identity,bounds):
        x0,y0,x1,y1=bounds
        for x in range(math.floor(x0/cell),math.floor(x1/cell)+1):
            for y in range(math.floor(y0/cell),math.floor(y1/cell)+1):target[x,y].append(identity)
    for i,(r,a,b) in enumerate(segments):
        radius=r["width_m"]/2+r.get("graded_verge_m",.3)+r.get("shoulder_m",1.2)
        index(road_index,i,(min(a[0],b[0])-radius,min(a[1],b[1])-radius,max(a[0],b[0])+radius,max(a[1],b[1])+radius))
    for i,p in enumerate(pads):
        radius=math.hypot(p["width_m"],p["depth_m"])/2+p["blend_m"]
        x,y=p["center_m"];index(pad_index,i,(x-radius,y-radius,x+radius,y+radius))
    for i,(r,a,b) in enumerate(protected):
        radius=r["width"]/2+.12+route_fades.get(r["id"],route_fade)
        index(protect_index,i,(min(a[0],b[0])-radius,min(a[1],b[1])-radius,max(a[0],b[0])+radius,max(a[1],b[1])+radius))
    def smooth(value):
        t=max(0.,min(1.,value));return t*t*(3-2*t)
    def height(x,y):
        base=authority.design_height(x,y)
        core_distance=math.hypot(max(core[0]-x,0.,x-core[2]),max(core[1]-y,0.,y-core[3]))
        if core_distance==0:return base
        key=(math.floor(x/cell),math.floor(y/cell))
        protected,extension,_,protected_distance,extension_strength=route_guard(x,y)
        if protected:return base
        # Compact weighted unions have continuous owner transitions. A hard
        # nearest-owner switch creates seams even when every individual blend
        # is smooth. Inverse distance gives an exact continuous limit at each
        # authored road centreline and each disjoint flat pad.
        road_weight=0.;road_target=0.;road_strength=0.;exact_road=[]
        pavement_distance=math.inf;approach_distances=[];constraint_distance=math.inf
        for i in road_index.get(key,()):
            r,a,b=segments[i];t,d=_project((x,y),a,b)
            length=math.dist(a[:2],b[:2])
            raw_t=((x-a[0])*(b[0]-a[0])+(y-a[1])*(b[1]-a[1]))/(length*length)
            overrun=max(0.,-raw_t,raw_t-1)*length
            # Angular support covers the rounded/mitered outside of a bend.
            # A fixed tip-distance cutoff leaves those real paving corners
            # outside every segment and exposes the ungraded natural ground.
            tip=(1-smooth(overrun/max(.75,d)))**4
            if not tip:continue
            half=r["width_m"]/2;verge=r.get("graded_verge_m",.3);shoulder=r.get("shoulder_m",1.2)
            if d>half+verge+shoulder:continue
            constraint_distance=min(constraint_distance,d)
            if r.get("owner"):
                # Same-owner approaches meet their own pad at the identical
                # datum. Foreign approach centrelines remain hard constraints;
                # their broad ribbons may touch a non-building pad margin.
                approach_distances.append((r["owner"],d))
            # The paved union includes the actual .78m sidewalk bands. A pad
            # must not tilt that walk simply because it lies outside the road's
            # carriageway half-width; retaining grade belongs beyond the walk.
            else:pavement_distance=min(pavement_distance,max(0.,d-half-.78))
            lateral_kernel=1-smooth((d-half-verge)/shoulder)
            kernel=lateral_kernel*tip
            target=a[2]+t*(b[2]-a[2])-.012*min(d,half)
            road_strength=max(road_strength,lateral_kernel)
            if d<1e-9:exact_road.append(target)
            else:
                # First-power Shepard weights give a linear bank between two
                # parallel datums. Fourth-power nearest-owner weights amplify
                # otherwise feasible 8% profile differences into 30% banks.
                weight=kernel/d
                road_weight+=weight;road_target+=weight*target
        if exact_road:road_z=sum(exact_road)/len(exact_road)
        elif road_weight:
            road_z=base*(1-road_strength)+(road_target/road_weight)*road_strength
        else:road_z=base
        pad_weight=0.;pad_target=0.;exact_pad=None;pad_constraint_distance=math.inf;pad_guard_limit=1.
        for i in pad_index.get(key,()):
            p=pads[i];theta=math.radians(p["yaw_degrees"])
            dx=x-p["center_m"][0];dy=y-p["center_m"][1]
            lx=dx*math.cos(theta)+dy*math.sin(theta);ly=-dx*math.sin(theta)+dy*math.cos(theta)
            distance=math.hypot(max(0,abs(lx)-p["width_m"]/2),max(0,abs(ly)-p["depth_m"]/2))
            if distance>p["blend_m"]:continue
            pad_constraint_distance=min(pad_constraint_distance,distance)
            pad_kernel=1-smooth(distance/p["blend_m"])
            if extension_strength:
                denominator=distance**2+protected_distance**2
                contact_ratio=distance**2/denominator if denominator else 0.
                # Compact support also fades this constraint at the *outer*
                # blend boundary; otherwise the cap itself would switch there.
                pad_guard_limit=min(pad_guard_limit,1-pad_kernel+pad_kernel*contact_ratio)
            if distance<1e-9:
                exact_pad=p["level_m"]
                break
            road_distance=min([pavement_distance]+[d for owner,d in approach_distances if owner!=p["owner"]])
            gate=1. if math.isinf(road_distance) else road_distance**2/(distance**2+road_distance**2)
            weight=pad_kernel*gate/distance**4
            pad_weight+=weight;pad_target+=weight*p["level_m"]
        z=exact_pad if exact_pad is not None else (road_z+pad_target)/(1+pad_weight)
        # Preserve original core and trail surfaces exactly, with a short C1
        # fade outside their protected ribbons. These masks stop before every
        # accepted flat pad. Existing intentional reserve stairs/walls remain.
        # Full shoulders, rather than centimetre-wide masks, grade unused grass
        # outside the actual built core. Profiles remain fixed through existing
        # route shoulders so a crossing follows that route's banked surface.
        if extension_strength and (not math.isinf(constraint_distance) or not math.isinf(pad_constraint_distance)):
            # Spread a crossing bank across the entire available space between
            # the exact old ribbon and the new datum, not a narrow grass-mask
            # shoulder. Both endpoint constraints have their exact limits.
            ratio=1. if math.isinf(constraint_distance) else constraint_distance/(constraint_distance+protected_distance) if constraint_distance+protected_distance else 0.
            if not math.isinf(pad_constraint_distance):
                # A road may bank linearly toward an old crossing; a flat pad
                # needs the stronger quadratic contact limit at its boundary.
                # Keep that independent constraint instead of letting the old
                # route guard reintroduce a first-order pad-edge kink.
                ratio=min(ratio,pad_guard_limit)
            protection=extension_strength*ratio
            guard_target=base*(1-road_strength)+extension*road_strength
            z=z*(1-protection)+guard_target*protection
        return base+(z-base)*smooth(core_distance/core_fade)
    return height


def _retained_boundary_scan(plan, baseline_root, height=None):
    """Sample narrow preservation shoulders and author collision-safe masonry.

    Only *introduced* grade changes trigger support. Original reserve steps,
    ravine structures and retaining terraces retain their original authority.
    Steep sections interrupted by a road are explicitly reported as causeway
    support reviews rather than silently filled by a wall across a passage.
    """
    root=_root(baseline_root);height=height or make_height_function(plan,root)
    base=_authority(root).design_height
    routes=_baseline_routes(json.loads((root/"masterplan.json").read_text(encoding="utf-8")),
                            json.loads((root/"reserve_plan.json").read_text(encoding="utf-8")),
                            json.loads((root/"landscape_plan.json").read_text(encoding="utf-8")))
    core=plan["terrain"].get("preserved_core_rect_xyxy_m",CORE_RECT)
    blending=plan["terrain"].get("surface_blending",{})
    core_fade=blending.get("core_preservation_fade_m",CORE_FADE)
    route_fade=blending.get("existing_route_preservation_fade_m",ROUTE_FADE)
    route_fades=blending.get("existing_route_fade_overrides_m",{})
    x0,y0,x1,y1=core
    domains=[("Core_West","core",[x0,y0],[x0,y1],[-1,0],core_fade),
             ("Core_East","core",[x1,y0],[x1,y1],[1,0],core_fade),
             ("Core_South","core",[x0,y0],[x1,y0],[0,-1],core_fade),
             ("Core_North","core",[x0,y1],[x1,y1],[0,1],core_fade)]
    for route in routes:
        for i,(a,b) in enumerate(zip(route["points"],route["points"][1:])):
            length=math.dist(a[:2],b[:2])
            if length<1e-8:continue
            nx,ny=-(b[1]-a[1])/length,(b[0]-a[0])/length
            for side in (-1,1):
                normal=[side*nx,side*ny];offset=route["width"]/2+.12
                aa=[a[k]+normal[k]*offset for k in range(2)]
                bb=[b[k]+normal[k]*offset for k in range(2)]
                domains.append((f"{route['id']}_{i}_{side}",route["id"],aa,bb,normal,route_fades.get(route["id"],route_fade)))
    barriers=defaultdict(list);cell=20.
    def add_barrier(source,a,b,radius):
        item=(source,a,b,radius)
        for x in range(math.floor((min(a[0],b[0])-radius)/cell),math.floor((max(a[0],b[0])+radius)/cell)+1):
            for y in range(math.floor((min(a[1],b[1])-radius)/cell),math.floor((max(a[1],b[1])+radius)/cell)+1):barriers[x,y].append(item)
    for route in plan["roads"]+plan.get("approaches",[]):
        radius=route["width_m"]/2+(.25 if route.get("owner") else .95)
        for a,b in zip(route["points_m"],route["points_m"][1:]):add_barrier(route["id"],a,b,radius)
    for route in routes:
        for a,b in zip(route["points"],route["points"][1:]):add_barrier(route["id"],a,b,route["width"]/2+.22)
    walls=[];measurements=[];gaps=[];samples=0
    for identity,source,a,b,normal,span in domains:
        count=max(1,math.ceil(math.dist(a,b)/.75))
        for i in range(count):
            lo=[a[k]+(b[k]-a[k])*i/count for k in range(2)]
            hi=[a[k]+(b[k]-a[k])*(i+1)/count for k in range(2)]
            mid=[(lo[k]+hi[k])/2 for k in range(2)]
            inner=[];outer=[];baseline_deltas=[]
            for point in (lo,mid,hi):
                q=[point[k]+normal[k]*span for k in range(2)]
                inner.append([*point,height(*point)]);outer.append([*q,height(*q)])
                baseline_deltas.append(base(*q)-base(*point));samples+=1
            actual=[q[2]-p[2] for p,q in zip(inner,outer)]
            introduced=[dz-bz for dz,bz in zip(actual,baseline_deltas)]
            if max(abs(d) for d in introduced)<.00001:continue
            worst=max(range(3),key=lambda k:abs(introduced[k]))
            row={"id":identity+"_"+str(i),"source_id":source,"points_xy":[lo,hi],
                 "side_normal_xy":normal,"span_m":span,"width_m":span+.12,
                 "inside_samples_m":inner,"outside_samples_m":outer,
                 "sampled_tops_m":[max(p[2],q[2])+.04 for p,q in zip(inner,outer)],
                 "sampled_toes_m":[min(p[2],q[2])-.08 for p,q in zip(inner,outer)],
                 "inside_level_m":inner[1][2],"outside_level_m":outer[1][2],
                 "max_height_change_m":max(abs(d) for d in actual),
                 "max_introduced_height_change_m":max(abs(d) for d in introduced),
                 "worst_point_xy":inner[worst][:2],"high_level_m":max(inner[worst][2],outer[worst][2]),
                 "low_level_m":min(inner[worst][2],outer[worst][2]),
                 "baseline_height_change_m":baseline_deltas[worst]}
            measurements.append(row)
            if row["max_height_change_m"]<=.15 or row["max_introduced_height_change_m"]<=.10:continue
            crossing=set()
            for point in (lo,mid,hi):
                center=[point[k]+normal[k]*span/2 for k in range(2)]
                for other,c,d,radius in barriers.get((math.floor(center[0]/cell),math.floor(center[1]/cell)),()):
                    if other==source:continue
                    if _project(center,c,d)[1]<radius+row["width_m"]/2:crossing.add(other)
            if crossing:
                gaps.append({**row,"crossing_ids":sorted(crossing),"action":"Keep passage open; inspect/support raised road or approach edges as an engineered causeway where required."})
            else:
                walls.append({**row,"material":"local granite","coping_height_m":.08,
                              "policy":"Measured retaining face spanning the preservation mask; follow sampled tops/toes and preserve all explicit crossing gaps."})
    return {"walls":walls,"measurements":measurements,"crossing_gaps":gaps,"samples":samples}


def retained_boundary_segments(plan, baseline_root):
    """Actual sampled retaining wall sections, excluding connected passages."""
    return _retained_boundary_scan(plan,baseline_root)["walls"]


def preservation_mask_audit(plan, baseline_root, height=None):
    scan=_retained_boundary_scan(plan,baseline_root,height)
    rows=scan["measurements"]
    ordered=sorted(rows,key=lambda r:r["max_introduced_height_change_m"],reverse=True)
    return {"schema":"living_town.preservation_mask_support_review.v1",
            "status":"ENGINEERED_SUPPORT_REQUIRED" if scan["walls"] or scan["crossing_gaps"] else "PASS",
            "core_fade_m":plan["terrain"].get("surface_blending",{}).get("core_preservation_fade_m",CORE_FADE),
            "existing_route_fade_m":plan["terrain"].get("surface_blending",{}).get("existing_route_preservation_fade_m",ROUTE_FADE),"sample_count":scan["samples"],
            "maximum_actual_height_change_m":max((r["max_height_change_m"] for r in rows),default=0),
            "maximum_introduced_height_change_m":max((r["max_introduced_height_change_m"] for r in rows),default=0),
            "worst_sections":ordered[:20],"retaining_wall_sections":scan["walls"],
            "crossing_gap_support_reviews":scan["crossing_gaps"],"native_support_geometry_verified":False,
            "policy":"Analytic continuity does not certify landscaping. Add measured granite faces at listed sections and engineer raised passage edges without blocking crossings; native geometry/contacts require separate review."}


def _validate(plan, master, reserve, baseline_routes, authority, infeasible, anchors):
    errors=[];buildings=plan["buildings"];roads=plan["roads"]
    all_existing=master["buildings"]+reserve["buildings"]
    shells=[(b["id"],b.get("footprint_polygon") or _polygon(b["center"],b["width"],b["depth"],b.get("yaw_degrees",0))) for b in all_existing]
    overlaps=[];minimum=math.inf
    for i,b in enumerate(buildings):
        for ident,poly in shells+[(q["id"],q["footprint_polygon"]) for q in buildings[i+1:]]:
            d=_polygon_distance(b["footprint_polygon"],poly);minimum=min(minimum,d)
            if d<1.399:overlaps.append([b["id"],ident,round(d,5)])
    if overlaps:errors.append("Building shell clearance below 1.4m")
    road_collisions=[]
    for r,a,b in _road_segments(roads):
        for ident,poly in shells+[(q["id"],q["footprint_polygon"]) for q in buildings]:
            if _segment_polygon(a,b,poly)<r["width_m"]/2+.05:road_collisions.append([r["id"],ident])
    if road_collisions:errors.append("Street ribbon overlaps a building")
    reserved_collisions=[]
    for b in buildings:
        for route in baseline_routes:
            if any(_segment_polygon(a,c,b["footprint_polygon"])<route["width"]/2+2.49 for a,c in zip(route["points"],route["points"][1:])):
                reserved_collisions.append([b["id"],route["id"]])
    if reserved_collisions:errors.append("Building intrudes on a preserved route buffer")
    # Actual segment incidence, including inserted intersections, is used for
    # reachability; road counts alone do not establish a connected network.
    graph=defaultdict(set)
    for r,a,b in _road_segments(roads):graph[_xy(a)].add(_xy(b));graph[_xy(b)].add(_xy(a))
    # The three attachment nodes share the existing connected core network.
    root=(0.,0.);graph[root]=set(anchors)
    for a in anchors:graph[a].add(root)
    reached={root};todo=[root]
    while todo:
        for node in graph[todo.pop()]-reached:reached.add(node);todo.append(node)
    disconnected=sorted(p for p in graph if p not in reached)
    if disconnected:errors.append("Expansion streets are disconnected from preserved town anchors")
    bad_grades=[r["id"] for r in roads if r["maximum_grade"]>GRADE+.00001]
    if bad_grades or infeasible:errors.append("Road elevation constraints are infeasible at 8%")
    access_errors=[]
    approaches={a["owner"]:a for a in plan["approaches"]}
    byroad={r["id"]:r for r in roads}
    for b in buildings:
        a=approaches[b["id"]];road=byroad[b["street_id"]];start=a["points_m"][0]
        distance=min(_project(start,p,q)[1] for p,q in zip(road["points_m"],road["points_m"][1:]))
        # At an inside bend, the normal offset can enter the neighboring
        # ribbon segment. That is a valid connection into the street union.
        if distance>road["width_m"]/2+.003 or math.dist(a["points_m"][-1][:2],b["front_threshold"])>.003:access_errors.append(b["id"])
        for ident,poly in shells+[(q["id"],q["footprint_polygon"]) for q in buildings if q["id"]!=b["id"]]:
            if _segment_polygon(a["points_m"][0],a["points_m"][-1],poly)<.699:access_errors.append(b["id"]);break
    if access_errors:errors.append("A front door approach is blocked or disconnected")
    if len(buildings)<80:errors.append("Fewer than 80 valid additional buildings")
    old_hull=_hull([p for b in master["buildings"] for p in b["footprint_polygon"]])
    new_hull=_hull([p for b in master["buildings"]+buildings for p in b["footprint_polygon"]])
    def bounds(poly):
        return [min(p[0] for p in poly),min(p[1] for p in poly),max(p[0] for p in poly),max(p[1] for p in poly)]
    old_bounds,new_bounds=bounds(old_hull),bounds(new_hull)
    coast_failures=[r["id"] for r in roads if any(p[0]+r["width_m"]/2>authority.CORE.coast_x(p[1]) for p in r["points_m"])]
    if coast_failures:errors.append("Road ribbon crosses the preserved shoreline")
    return {"status":"PASS" if not errors else "FAIL","errors":errors,
            "additional_buildings":len(buildings),"preserved_urban_buildings":len(master["buildings"]),
            "preserved_reserve_buildings":len(reserve["buildings"]),"minimum_shell_clearance_m":round(minimum,5),
            "building_overlap_pairs":overlaps,"street_building_collisions":road_collisions,
            "preserved_route_buffer_collisions":reserved_collisions,"blocked_entrances":sorted(set(access_errors)),
            "connected_graph_vertices":len(reached)-1,"disconnected_graph_vertices":[list(p) for p in disconnected],
            "road_grade_failures":bad_grades,"infeasible_profile_nodes":infeasible,
            "maximum_road_grade":max(r["maximum_grade"] for r in roads),
            "maximum_road_cut_fill_m":max(r["maximum_cut_fill_m"] for r in roads),
            "shoreline_violations":coast_failures,
            "original_urban_bounds_xyxy_m":[round(v,3) for v in old_bounds],
            "expanded_urban_bounds_xyxy_m":[round(v,3) for v in new_bounds],
            "linear_extent_ratio_xy":[round((new_bounds[i+2]-new_bounds[i])/(old_bounds[i+2]-old_bounds[i]),3) for i in (0,1)],
            "original_urban_convex_hull_m2":round(_area(old_hull),2),
            "expanded_urban_convex_hull_m2":round(_area(new_hull),2),
            "urban_convex_hull_area_ratio":round(_area(new_hull)/_area(old_hull),3),
            "scope":"Exact 2D shell/ribbon/access graph and sampled authored profile checks. Native geometry, actual retaining bank slopes, foliage clearance and interior reachability require scene QA; fictional terrain is not surveyed civil engineering."}


def surface_boundary_audit(plan, baseline_root, height=None):
    """Measure real pad boundaries and previously observed road-owner seams.

    A centre/corner contact audit cannot detect a cliff immediately outside its
    samples. Test both 2cm and 2mm spans at the exact flat-pad boundary, then
    test convergence at the road-owner seams found in the original v2 field.
    Steep continuous banks are reported separately for real retaining masonry.
    """
    height=height or make_height_function(plan,baseline_root)
    pad_rows=[];pairs=0
    for pad in plan["terrain"]["pads"]:
        angle=math.radians(pad["yaw_degrees"]);c,s=math.cos(angle),math.sin(angle)
        cx,cy=pad["center_m"];w,d=pad["width_m"]/2,pad["depth_m"]/2
        coarse=fine=bank=0.;bank_point=None
        for axis,edge,length in (("x",-w,d),("x",w,d),("y",-d,w),("y",d,w)):
            count=math.ceil(length*2/.25)
            for i in range(count+1):
                t=-length+2*length*i/count
                x,y=(edge,t) if axis=="x" else (t,edge)
                nx,ny=((1 if edge>0 else -1),0) if axis=="x" else (0,(1 if edge>0 else -1))
                wx,wy=cx+x*c-y*s,cy+x*s+y*c
                nx,ny=nx*c-ny*s,nx*s+ny*c
                a=abs(height(wx-.01*nx,wy-.01*ny)-height(wx+.01*nx,wy+.01*ny))
                b=abs(height(wx-.001*nx,wy-.001*ny)-height(wx+.001*nx,wy+.001*ny))
                coarse=max(coarse,a);fine=max(fine,b);pairs+=1
                change=abs(pad["level_m"]-height(wx+nx,wy+ny))
                if change>bank:bank=change;bank_point=[round(wx,6),round(wy,6)]
        pad_rows.append({"id":pad["owner"],"maximum_2cm_delta_m":round(coarse,10),
                         "maximum_2mm_delta_m":round(fine,12),"maximum_one_meter_bank_change_m":round(bank,6),
                         "bank_point_xy":bank_point,"retaining_terrace_review_required":bank>.5})
    locations=[[-24.67301932536,102.32097857462],[-20.76236681628,96.33419323183],
               [-198.55374472450,-21.10532324352],[-15.81825466910,124.75058951335],
               [-97.92384987412,-1.07480807227],[-14.22876268145,69.90213668606],
               [-172.99218869810,3.43610459397]]
    seams=[]
    for point in locations:
        for nx,ny in ((1,0),(0,1)):
            x,y=point
            coarse=abs(height(x-.01*nx,y-.01*ny)-height(x+.01*nx,y+.01*ny))
            fine=abs(height(x-.001*nx,y-.001*ny)-height(x+.001*nx,y+.001*ny))
            seams.append({"point_xy":point,"axis":"x" if nx else "y",
                          "delta_2cm_m":round(coarse,9),"delta_2mm_m":round(fine,9),
                          "converges":fine<=coarse*.22+.00001})
    maximum=max(r["maximum_2cm_delta_m"] for r in pad_rows)
    maximum_fine=max(r["maximum_2mm_delta_m"] for r in pad_rows)
    masks=preservation_mask_audit(plan,baseline_root,height)
    return {"schema":"living_town.expansion_surface_boundary_review.v1",
            "status":"PASS" if maximum<=.001 and maximum_fine<=.0001 and all(r["converges"] for r in seams) else "FAIL",
            "pad_count":len(pad_rows),"pad_edge_station_spacing_m":.25,"pad_edge_sample_pairs":pairs,
            "paired_span_m":[.02,.002],"maximum_pad_edge_2cm_delta_m":maximum,
            "maximum_pad_edge_2mm_delta_m":maximum_fine,"pads":pad_rows,"road_owner_seams":seams,
            "retaining_terrace_candidates":[r for r in pad_rows if r["retaining_terrace_review_required"]],
            "preservation_masks":masks,
            "policy":"No new unplanned C0 pad/owner jumps. Continuous banks changing >0.5m in one metre require native retaining-terrace review. Original reserve stair/retaining discontinuities remain under the unchanged baseline authority."}


def _surface_audit(plan, root, authority, routes):
    height=make_height_function(plan,root)
    rows=[]
    for road in plan["roads"]+plan["approaches"]:
        vertex_error=max(abs(height(*p[:2])-p[2]) for p in road["points_m"])
        midpoint_error=max(abs(height((a[0]+b[0])/2,(a[1]+b[1])/2)-(a[2]+b[2])/2)
                           for a,b in zip(road["points_m"],road["points_m"][1:]))
        rows.append({"id":road["id"],"maximum_vertex_drift_m":round(vertex_error,7),
                     "maximum_midpoint_drift_m":round(midpoint_error,7)})
    pad_error=max(abs(height(*point)-b["pad_level_m"]) for b in plan["buildings"]
                  for point in b["footprint_polygon"]+[b["center"],b["front_threshold"]])
    preserved_error=max(abs(height(*p[:2])-authority.design_height(*p[:2])) for r in routes for p in r["points"][::max(1,len(r["points"])//20)])
    maximum=max(max(row["maximum_vertex_drift_m"],row["maximum_midpoint_drift_m"]) for row in rows)
    boundary=surface_boundary_audit(plan,root,height)
    return {"status":"PASS" if maximum<=.04 and pad_error<=1e-6 and preserved_error<=1e-6 and boundary["status"]=="PASS" else "FAIL",
            "profile_contact_tolerance_m":.04,"maximum_profile_contact_drift_m":maximum,
            "maximum_pad_drift_m":round(pad_error,7),"maximum_preserved_route_drift_m":round(preserved_error,7),
            "records":rows,"surface_boundary":boundary,
            "note":"Profiles tessellate at <=0.75m. The few-centimetre midpoint residual occurs at the preserved curved baseline ribbons; foundation corners and thresholds must match exactly. A native mesh contact audit remains required."}


def add_paved_sections(plan, baseline_root, height=None):
    """Author one banked paving datum, shared with the actual finished terrain.

    All rows in a road have identical offsets, including physical carriageway
    and sidewalk limits. Adaptive longitudinal subdivisions resolve shoulders;
    transverse midpoint checks add a common offset to every row when needed.
    Source centreline profiles and their unchanged 4cm contact test remain
    independent of these genuinely three-dimensional pavement sections.
    """
    height=height or make_height_function(plan,baseline_root)
    reports=[]
    for road in plan["roads"]+plan.get("approaches",[]):
        points=road["points_m"];stations=[0.]
        for a,b in zip(points,points[1:]):stations.append(stations[-1]+math.dist(a[:2],b[:2]))
        tangents=[]
        for i,p in enumerate(points):
            a,b=points[max(0,i-1)],points[min(len(points)-1,i+1)]
            length=math.dist(a[:2],b[:2]);tangents.append(((b[0]-a[0])/length,(b[1]-a[1])/length))
        half=road["width_m"]/2
        road["sidewalk_width_m"]=0. if road.get("owner") else .78
        outer=half+road["sidewalk_width_m"]
        offsets=sorted(set(round(v,8) for v in [-outer,-half,0.,half,outer]+
                           [-outer+2*outer*i/math.ceil(2*outer/.2) for i in range(math.ceil(2*outer/.2)+1)]))
        def sample(station, lateral):
            i=min(len(points)-2,max(0,bisect.bisect_right(stations,station)-1))
            t=(station-stations[i])/(stations[i+1]-stations[i])
            center=[points[i][k]+t*(points[i+1][k]-points[i][k]) for k in range(3)]
            tx=tangents[i][0]+t*(tangents[i+1][0]-tangents[i][0]);ty=tangents[i][1]+t*(tangents[i+1][1]-tangents[i][1])
            length=math.hypot(tx,ty);nx,ny=-ty/length,tx/length
            xyz=[]
            for offset in lateral:
                x,y=center[0]+nx*offset,center[1]+ny*offset
                xyz.append([round(x,8),round(y,8),round(height(x,y),8)])
            return {"center_m":center,"station_m":station,"offsets_m":lateral,"points_m":xyz}
        cache={}
        def row(s):
            if s not in cache:cache[s]=sample(s,offsets)
            return cache[s]
        final_stations=set(stations);max_interp=0.
        def subdivide(a,b,depth=0):
            nonlocal max_interp
            mid=(a+b)/2;ra,rb,rm=row(a),row(b),row(mid)
            error=max(abs(pm[2]-(pa[2]+pb[2])/2) for pa,pb,pm in zip(ra["points_m"],rb["points_m"],rm["points_m"]))
            if b-a>.375 or (error>.01 and b-a>.025 and depth<8):
                final_stations.add(mid);subdivide(a,mid,depth+1);subdivide(mid,b,depth+1)
            else:max_interp=max(max_interp,error)
        for a,b in zip(stations,stations[1:]):subdivide(a,b)
        rows=[row(s) for s in sorted(final_stations)]
        # Reuse one lateral topology for every row, including any extra offsets
        # required by curved masks. Never stitch variable-length strip rows.
        transverse_error=0.
        for _ in range(3):
            additions=set();transverse_error=0.
            for r in rows:
                mids=[(a+b)/2 for a,b in zip(offsets,offsets[1:])]
                probe=sample(r["station_m"],mids)
                for k,p in enumerate(probe["points_m"]):
                    error=abs(p[2]-(r["points_m"][k][2]+r["points_m"][k+1][2])/2)
                    transverse_error=max(transverse_error,error)
                    if error>.01 and offsets[k+1]-offsets[k]>.025:additions.add(mids[k])
            if not additions:break
            offsets=sorted(set(offsets)|additions);rows=[sample(r["station_m"],offsets) for r in rows]
        # Test the actual two triangles consumed by Blender, not just separate
        # row/column interpolation. Positive residual means terrain could bury
        # a slab. Refine common offsets and stations until it is below 1.5cm.
        triangle_positive=0.;triangle_absolute=0.;triangle_worst=None
        for iteration in range(4):
            more_offsets=set();more_stations=set();triangle_positive=0.;triangle_absolute=0.
            for ra,rb in zip(rows,rows[1:]):
                for k in range(len(offsets)-1):
                    aa,ab=ra["points_m"][k:k+2];ba,bb=rb["points_m"][k:k+2]
                    for vertices in ((aa,ba,bb),(aa,bb,ab)):
                        point=[sum(v[j] for v in vertices)/3 for j in range(3)]
                        residual=height(*point[:2])-point[2]
                        triangle_absolute=max(triangle_absolute,abs(residual))
                        if residual>triangle_positive:triangle_positive=residual;triangle_worst=point
                        if abs(residual)>.012:
                            if rb["station_m"]-ra["station_m"]>.025:more_stations.add((ra["station_m"]+rb["station_m"])/2)
                            if offsets[k+1]-offsets[k]>.025:more_offsets.add((offsets[k]+offsets[k+1])/2)
            if not more_offsets and not more_stations:break
            if iteration==3:break
            offsets=sorted(set(offsets)|more_offsets)
            station_values=sorted({r["station_m"] for r in rows}|more_stations)
            rows=[sample(s,offsets) for s in station_values]
        longitudinal=(0.,None);transverse=(0.,None)
        finite_long=(0.,None);finite_cross=(0.,None)
        carriage_long=(0.,None);carriage_cross=(0.,None)
        for r in rows:
            for k,(a,b) in enumerate(zip(r["points_m"],r["points_m"][1:])):
                distance=math.dist(a[:2],b[:2]);slope=abs(b[2]-a[2])/distance if distance else 0.
                if slope>transverse[0]:transverse=(slope,{"points_m":[a,b],"station_m":r["station_m"]})
                if max(abs(offsets[k]),abs(offsets[k+1]))<=half+1e-7 and slope>carriage_cross[0]:carriage_cross=(slope,{"points_m":[a,b],"station_m":r["station_m"]})
            for k,a in enumerate(r["points_m"]):
                for span in (.5,1.):
                    j=bisect.bisect_left(offsets,offsets[k]+span)
                    if j>=len(offsets):continue
                    b=r["points_m"][j];distance=math.dist(a[:2],b[:2])
                    if .499<=distance<=1.25:
                        slope=abs(b[2]-a[2])/distance
                        if slope>finite_cross[0]:finite_cross=(slope,{"points_m":[a,b],"span_m":distance})
        for ra,rb in zip(rows,rows[1:]):
            for k,(a,b) in enumerate(zip(ra["points_m"],rb["points_m"])):
                distance=math.dist(a[:2],b[:2]);slope=abs(b[2]-a[2])/distance if distance>1e-8 else 0.
                if slope>longitudinal[0]:longitudinal=(slope,{"points_m":[a,b],"offset_m":offsets[k]})
                if abs(offsets[k])<=half+1e-7 and slope>carriage_long[0]:carriage_long=(slope,{"points_m":[a,b],"offset_m":offsets[k]})
        row_stations=[r["station_m"] for r in rows]
        for i,ra in enumerate(rows):
            for span in (.5,1.):
                j=bisect.bisect_left(row_stations,ra["station_m"]+span)
                if j>=len(rows):continue
                rb=rows[j]
                for k,(a,b) in enumerate(zip(ra["points_m"],rb["points_m"])):
                    distance=math.dist(a[:2],b[:2])
                    if .499<=distance<=1.25:
                        slope=abs(b[2]-a[2])/distance
                        if slope>finite_long[0]:finite_long=(slope,{"points_m":[a,b],"offset_m":offsets[k],"span_m":distance})
        road["paved_sections_m"]=rows
        report={"id":road["id"],"row_count":len(rows),"offset_count":len(offsets),
                "maximum_lateral_spacing_m":max(b-a for a,b in zip(offsets,offsets[1:])),
                "maximum_longitudinal_slope":longitudinal[0],"worst_longitudinal":longitudinal[1],
                "maximum_transverse_slope":transverse[0],"worst_transverse":transverse[1],
                "maximum_carriageway_longitudinal_slope":carriage_long[0],"worst_carriageway_longitudinal":carriage_long[1],
                "maximum_carriageway_transverse_slope":carriage_cross[0],"worst_carriageway_transverse":carriage_cross[1],
                "maximum_finite_longitudinal_slope":finite_long[0],"worst_finite_longitudinal":finite_long[1],
                "maximum_finite_transverse_slope":finite_cross[0],"worst_finite_transverse":finite_cross[1],
                "maximum_longitudinal_midpoint_residual_m":max_interp,
                "maximum_transverse_midpoint_residual_m":transverse_error,
                "maximum_triangle_positive_ground_residual_m":triangle_positive,
                "maximum_triangle_absolute_ground_residual_m":triangle_absolute,
                "worst_triangle_ground_residual_point_m":triangle_worst}
        reports.append(report)
    return {"schema":"living_town.paved_surface_sections.v1","status":"AUTHORED_REQUIRES_NATIVE_CONTACT_QA",
            "datum":"Every points_m Z samples make_height_function. Add 0.035m for paving or 0.055m for sidewalks.",
            "maximum_longitudinal_slope":max(r["maximum_longitudinal_slope"] for r in reports),
            "maximum_transverse_slope":max(r["maximum_transverse_slope"] for r in reports),
            "maximum_finite_longitudinal_slope":max(r["maximum_finite_longitudinal_slope"] for r in reports),
            "maximum_finite_transverse_slope":max(r["maximum_finite_transverse_slope"] for r in reports),
            "records":reports,"policy":"Reported slopes include existing-route banks and shoulders; 8% applies to authored street centrelines. Geometry must follow these sections, preserve open passage, and pass the independent 15cm native contact test."}


def generate(baseline_root: Path, seed: int) -> dict:
    """Generate a complete spatial expansion plan without writing files."""
    if isinstance(seed,bool) or not isinstance(seed,int) or not 0<=seed<2**32:
        raise ValueError("seed must be an unsigned 32-bit integer")
    root=_root(baseline_root)
    source={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in SOURCES}
    master=json.loads((root/"masterplan.json").read_text(encoding="utf-8"))
    reserve=json.loads((root/"reserve_plan.json").read_text(encoding="utf-8"))
    landscape=json.loads((root/"landscape_plan.json").read_text(encoding="utf-8"))
    authority=_authority(root)
    routes=_baseline_routes(master,reserve,landscape)
    roads,infeasible,anchors=_plan_roads(_road_specs(),routes,authority)
    buildings,pads,approaches,rejected=_candidate_buildings(roads,master["buildings"]+reserve["buildings"],routes,landscape["pond"],authority,seed)
    districts=[]
    for d in DISTRICTS:
        members=[b for b in buildings if b["district"]==d["id"]]
        districts.append({**d,"building_ids":[b["id"] for b in members],"building_count":len(members),
                          "boundary_polygon":_hull([p for b in members for p in b["footprint_polygon"]]) if members else []})
    plan={"schema":SCHEMA,"seed":seed,"authority":"Authored fictional irregular coastal town expansion, deterministically parcelled and validated against preserved source geometry.",
          "coordinate_system":"Metres; X east, Y north, Z up; building local frontage -Y; yaw about +Z.",
          "source_bindings":source,"planner_source_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),"bounds_xyxy_m":[-600,-340,66,500],
          "roads":roads,"buildings":buildings,"approaches":approaches,"districts":districts,
          "terrain":{"base_authority":"tools/reserve_plan.py:design_height(x,y)",
                     "finished_authority":"tools.town_generation.territory.make_height_function(plan, baseline_root)",
                     "preserved_core_rect_xyxy_m":list(CORE_RECT),"pads":pads,
                     "road_earthworks":{"grade_limit":GRADE,"maximum_centerline_cut_fill_m":4.,"graded_verge_m":2.,"blend_shoulder_m":3.,"surface_crossfall":.012},
                     "surface_blending":{"method":"First-power Shepard road union; fourth-power exact pad limits; distance-ratio gates across full pavement and sidewalk ribbons; walkable tangent-plane extensions outside exact original route masks.","core_preservation_fade_m":CORE_FADE,"existing_route_preservation_fade_m":ROUTE_FADE,"existing_route_fade_overrides_m":dict(ROUTE_FADE_OVERRIDES),"crossing_extension_support_m":4.,"retaining_terrace_review_bank_grade":.5},
                     "preservation":"Base design_height remains the only original terrain authority. Apply bounded pad/road overlays using make_height_function; preserved core and existing route ribbons remain exact. Retain the original coast_x; no eastward land infill."},
          "connection_anchors":[{"point_xy":list(p),"baseline_route":r,"z_m":round(authority.design_height(*p),6)} for p,r in anchors.items()],
          "vegetation":{"policy":"Retain reserve variation and meadow gaps. Regenerate only instances intersecting new streets/pads; surround the extension with the existing forest, not a flat lawn.",
                        "new_building_buffer_m":3.,"new_road_edge_buffer_m":2.,"species":["oak","beech","birch","pine","hawthorn","orchard apple"],
                        "district_gardens":{"D06":"salt tolerant hedges, hollyhocks and roses","D07":"climbing roses, courtyard pots and small lime trees","D08":"retained woodland fingers, hydrangea terraces and cottage gardens","D09":"orchard rows, vegetable beds, meadow margins and nursery glasshouses","D10":"mixed native woodland, ferns, heather and bike-cafe planters"}},
          "parcel_rejections":rejected,
          "presentation":{"camera_overview":{"target_m":[-64,25,5],"location_m":[250,-340,350]},"route_road_ids":["North_Harbor_Road","Hillside_Contour_Road","West_Market_Street","Trailhead_Village_Loop","Orchard_Lane_Loop"]}}
    plan["detailed_focus_ids"]=[next((b["id"] for b in buildings if b["district"]==d and b["kind"]==kind),next(b["id"] for b in buildings if b["district"]==d)) for d,kind in [("D06","cafe"),("D07","workshop"),("D08","cottage"),("D09","shop"),("D10","cafe")]]
    plan["validation"]=_validate(plan,master,reserve,routes,authority,infeasible,anchors)
    plan["validation"]["surface_contact"]=_surface_audit(plan,root,authority,routes)
    if plan["validation"]["surface_contact"]["status"]!="PASS":
        plan["validation"]["errors"].append("Finished terrain/profile contact audit failed")
        plan["validation"]["status"]="FAIL"
    plan["occupied_bounds_xyxy_m"]=plan["validation"]["expanded_urban_bounds_xyxy_m"]
    # Sparse baseline samples let a planning-map consumer draw contours without
    # importing Blender. Runtime authority is available for exact local samples.
    height=make_height_function(plan,root)
    plan["terrain"]["paved_surface_review"]=add_paved_sections(plan,root,height)
    pavement=plan["terrain"]["paved_surface_review"]
    failures=[r["id"] for r in pavement["records"] if r["maximum_triangle_absolute_ground_residual_m"]>.02]
    pavement["analytic_triangle_status"]="FAIL" if failures else "PASS"
    pavement["analytic_triangle_tolerance_m"]=.02
    pavement["triangle_failure_ids"]=failures
    if failures:
        plan["validation"]["status"]="FAIL"
        plan["validation"]["errors"].append("Planned paving triangle/finished-ground residual exceeds2cm: "+", ".join(failures))
    plan["terrain"]["site_samples_m"]=[[x,y,round(height(x,y),5)] for y in range(-140,161,10) for x in range(-240,51,10) if x<authority.CORE.coast_x(y)]
    return plan
